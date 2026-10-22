"""Publish verified workflow assets without deleting previous downloads."""

import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import quote


ARTIFACTS = {
    'hongguojian-android': ('hongguojian', 'android'),
    'hongguojian-ios-unsigned': ('hongguojian', 'ios'),
}


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def prepare_assets(artifacts, output, commit, run_id, attempt, ios_result):
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Invalid commit SHA')
    if not str(run_id).isdigit() or not str(attempt).isdigit():
        raise ValueError('Invalid workflow run identity')
    # 附件名只带这一次 CI 运行的编号，不带提交哈希：同一轮运行的产物可重复校验，
    # 重跑也不会覆盖上一轮已经公开的下载地址。
    suffix = f'{run_id}-{attempt}'
    output.mkdir(parents=True, exist_ok=True)
    assets, packages = {}, []
    has_android_apk = False
    for artifact, (edition, platform) in ARTIFACTS.items():
        directory = artifacts / artifact
        for source in sorted(directory.rglob('*')):
            if not source.is_file() or source.suffix.lower() not in {'.apk', '.zip', '.ipa'}:
                continue
            if source.is_symlink() or source.stat().st_size == 0:
                raise ValueError(f'Invalid package: {source}')
            name = f'{source.stem}-{suffix}{source.suffix}'
            if name in assets:
                raise ValueError(f'Duplicate package name: {name}')
            target = output / name
            shutil.copyfile(source, target)
            assets[name] = target
            packages.append({
                'name': name, 'originalName': source.name,
                'edition': edition, 'platform': platform,
                'bytes': target.stat().st_size, 'sha256': sha256_file(target),
            })
            if platform == 'android' and source.suffix.lower() == '.apk':
                has_android_apk = True
    if not has_android_apk:
        raise ValueError('Android APK is required before publishing')
    manifest = output / f'build-{suffix}.json'
    manifest.write_text(json.dumps({
        'commit': commit, 'runId': str(run_id), 'runAttempt': str(attempt),
        'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'iosJobResult': ios_result,
        'validation': 'Build artifacts only; checks are independent and device acceptance is not implied.',
        'packages': packages,
    }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    assets[manifest.name] = manifest
    checksums = output / f'SHA256SUMS-{suffix}.txt'
    checksums.write_text(''.join(
        f'{sha256_file(path)}  {name}\n' for name, path in sorted(assets.items())
    ), encoding='utf-8')
    assets[checksums.name] = checksums
    return assets


class GitHubRelease:
    def __init__(self, repository):
        self.repository = repository
        self.base = f'repos/{repository}/releases'

    def command(self, *arguments):
        return subprocess.run(
            ['gh', *arguments], check=True, capture_output=True, text=True,
            timeout=180,
        ).stdout

    def release(self, tag):
        try:
            return json.loads(self.command('api', f'{self.base}/tags/{quote(tag, safe="")}'))
        except subprocess.CalledProcessError as error:
            # Auth/network/API errors are not evidence that a release is absent.
            if '(HTTP 404)' in (error.stderr or ''):
                return None
            raise

    def create_draft(self, tag, title, notes, commit):
        # 直接使用创建响应里的 release 对象：按 tag 读回对草稿 404，列表接口
        # 对新建草稿又有延迟，回读在 CI 里读不到刚创建的草稿。
        return json.loads(self.command(
            'api', '--method', 'POST', self.base,
            '-f', f'tag_name={tag}',
            '-f', f'target_commitish={commit}',
            '-F', 'draft=true',
            '-f', f'name={title}',
            '-f', f'body={notes}',
        ))

    def assets(self, release_id):
        pages = json.loads(self.command(
            'api', '--paginate', '--slurp', f'{self.base}/{release_id}/assets?per_page=100',
        ))
        return [asset for page in pages for asset in page]

    def upload(self, release_id, path):
        # 草稿按 id 上传附件，避免按 tag 解析草稿时再次依赖列表接口；
        # 绝不使用 --clobber 之类会先删除已有附件的方式。
        self.command(
            'api', '--method', 'POST',
            f'https://uploads.github.com/repos/{self.repository}'
            f'/releases/{release_id}/assets?name={quote(path.name, safe="")}',
            '-H', 'Content-Type: application/octet-stream',
            '--input', str(path),
        )

    def promote(self, release_id, title, notes):
        # 只公开发布本次创建/命中的 Release；不移动也不重建任何已有 tag。
        self.command(
            'api', '--method', 'PATCH', f'{self.base}/{release_id}',
            '-F', 'draft=false',
            '-f', f'name={title}',
            '-f', f'body={notes}',
        )


def matches_asset(remote, path):
    return (remote.get('state') == 'uploaded'
            and remote.get('size') == path.stat().st_size
            and remote.get('digest') == 'sha256:' + sha256_file(path))


def publish_assets(client, tag, title, notes, commit, assets):
    if not assets:
        raise ValueError('No release assets')
    release = client.release(tag)
    if release is None:
        release = client.create_draft(tag, title, notes, commit)
    existing = {asset['name']: asset for asset in client.assets(release['id'])}
    for name, path in assets.items():
        if name in existing:
            if not matches_asset(existing[name], path):
                raise RuntimeError(f'Conflicting release asset, preserved without overwrite: {name}')
        else:
            client.upload(release['id'], path)
    uploaded = {asset['name']: asset for asset in client.assets(release['id'])}
    for name, path in assets.items():
        if name not in uploaded or not matches_asset(uploaded[name], path):
            # Missing SHA-256 is a failed verification, not permission to remove old packages.
            raise RuntimeError(f'Uploaded release asset could not be verified: {name}')
    # 只追加本次附件；历史安装包、清单和校验文件继续保留原下载地址。
    client.promote(release['id'], title, notes)


def main():
    environment = os.environ
    commit = environment['GITHUB_SHA']
    ref = environment['GITHUB_REF']
    run_id = environment['GITHUB_RUN_ID']
    attempt = environment['GITHUB_RUN_ATTEMPT']
    explicit_tag = ref.startswith('refs/tags/')
    # run_id 区分构建批次，attempt 区分重跑；显式 tag 仍使用用户指定的版本。
    tag = environment['GITHUB_REF_NAME'] if explicit_tag else f'build-{run_id}-{attempt}'
    title = tag if explicit_tag else f'构建 {tag} · {commit[:7]}'
    assets = prepare_assets(
        Path('artifacts'), Path('release'), commit, run_id, attempt,
        environment.get('IOS_RESULT', 'unknown'),
    )
    notes = (f'由自动或手动运行的工作流发布 · 提交 {commit}\n\n'
             f'构建记录：{environment["GITHUB_SERVER_URL"]}/{environment["GITHUB_REPOSITORY"]}'
             f'/actions/runs/{environment["GITHUB_RUN_ID"]}\n\n'
             '校验与设备验收独立于出包；请参阅 workflow 状态。附件包含构建清单及 SHA-256。')
    publish_assets(GitHubRelease(environment['GITHUB_REPOSITORY']),
                   tag, title, notes, commit, assets)


if __name__ == '__main__':
    main()
