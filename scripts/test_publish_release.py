import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

from publish_release import GitHubRelease, main, prepare_assets, publish_assets, sha256_file


class ReleaseIdentityTests(unittest.TestCase):
    def publish_run(self, event='push', ref='refs/heads/main', run_id='123', attempt='1'):
        environment = {
            'GITHUB_EVENT_NAME': event,
            'GITHUB_SHA': 'a' * 40,
            'GITHUB_REF': ref,
            'GITHUB_REF_NAME': ref.split('/', 2)[2],
            'GITHUB_RUN_ID': run_id,
            'GITHUB_RUN_ATTEMPT': attempt,
            'GITHUB_SERVER_URL': 'https://github.com',
            'GITHUB_REPOSITORY': 'owner/repo',
            'IOS_RESULT': 'success',
        }
        assets = {'app.apk': Path('app.apk'), 'ios.zip': Path('ios.zip')}
        with mock.patch.dict('os.environ', environment, clear=True), \
                mock.patch('publish_release.prepare_assets', return_value=assets) as prepare, \
                mock.patch('publish_release.publish_assets') as publish:
            main()
        prepare.assert_called_once_with(
            Path('artifacts'), Path('release'), 'a' * 40, run_id, attempt, 'success',
        )
        publish.assert_called_once()
        client, tag, title, notes, commit, published_assets = publish.call_args.args
        self.assertEqual(client.repository, 'owner/repo')
        self.assertEqual(commit, 'a' * 40)
        self.assertIs(published_assets, assets)
        self.assertIn(f'/actions/runs/{run_id}', notes)
        return tag, title

    def test_branch_pushes_use_separate_tags_even_for_the_same_commit(self):
        self.assertEqual(self.publish_run(run_id='123')[0], 'build-123-1')
        self.assertEqual(self.publish_run(run_id='124')[0], 'build-124-1')

    def test_rerun_uses_a_new_tag(self):
        self.assertEqual(self.publish_run(attempt='1')[0], 'build-123-1')
        self.assertEqual(self.publish_run(attempt='2')[0], 'build-123-2')

    def test_build_tag_title_stays_distinct_from_version_tags(self):
        self.assertEqual(self.publish_run()[1], '构建 build-123-1 · aaaaaaa')

    def test_manual_branch_run_uses_a_build_tag(self):
        self.assertEqual(self.publish_run(event='workflow_dispatch')[0], 'build-123-1')

    def test_explicit_tags_are_preserved(self):
        for event in ['push', 'workflow_dispatch']:
            with self.subTest(event=event):
                tag, title = self.publish_run(event=event, ref='refs/tags/v0.3.1')
                self.assertEqual(tag, 'v0.3.1')
                self.assertEqual(title, 'v0.3.1')


class FakeRelease:
    def __init__(self):
        self.exists = True
        self.drafted = False
        self.remote = [{'id': 1, 'name': 'previous.apk'}]
        self.calls = []
        self.release_ids = []
        self.fail_upload = False
        self.bad_digest = False
        self.fail_promote = False

    def release(self, tag):
        # 按 tag 查询只看得到已发布的 Release，与 GitHub 行为一致。
        return {'id': 10} if self.exists and not self.drafted else None

    def create_draft(self, tag, title, notes, commit):
        self.calls.append('draft')
        self.drafted = True
        return {'id': 10, 'tag_name': tag, 'draft': True}

    def assets(self, release_id):
        self.calls.append('list')
        return list(self.remote)

    def upload(self, release_id, path):
        self.calls.append('upload:' + path.name)
        self.release_ids.append(release_id)
        if self.fail_upload:
            raise RuntimeError('upload interrupted')
        self.remote.append({
            'id': len(self.remote) + 10, 'name': path.name, 'state': 'uploaded',
            'size': path.stat().st_size,
            'digest': None if self.bad_digest else 'sha256:' + sha256_file(path),
        })

    def promote(self, release_id, title, notes):
        self.calls.append('promote')
        self.release_ids.append(release_id)
        if self.fail_promote:
            raise RuntimeError('release update failed')

    def remove_asset(self, asset_id):
        raise AssertionError('Publishing must never delete existing release assets')


class PublishReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.package = self.root / 'new.apk'
        self.package.write_bytes(b'synthetic package')
        self.assets = {self.package.name: self.package}
        self.client = FakeRelease()

    def publish(self):
        publish_assets(self.client, 'latest', 'title', 'notes', 'a' * 40, self.assets)

    def test_later_publish_keeps_every_previous_generation(self):
        self.publish()
        self.assertEqual(self.client.calls, ['list', 'upload:new.apk', 'list', 'promote'])
        self.assertEqual([asset['name'] for asset in self.client.remote], ['previous.apk', 'new.apk'])
        previous = list(self.client.remote)
        package = self.root / 'next-run.apk'
        package.write_bytes(b'next synthetic package')
        self.assets = {package.name: package}
        self.client.calls.clear()
        self.publish()
        self.assertEqual(self.client.calls, ['list', 'upload:next-run.apk', 'list', 'promote'])
        self.assertEqual(self.client.remote[:-1], previous)
        self.assertEqual(self.client.remote[-1]['name'], 'next-run.apk')

    def test_upload_targets_the_release_id_without_clobbering(self):
        client = GitHubRelease('owner/repo')
        with mock.patch.object(client, 'command') as command:
            client.upload(10, self.package)
        command.assert_called_once_with(
            'api', '--method', 'POST',
            'https://uploads.github.com/repos/owner/repo/releases/10'
            '/assets?name=new.apk',
            '-H', 'Content-Type: application/octet-stream',
            '--input', str(self.package),
        )

    def test_promotion_publishes_the_created_release(self):
        for release_id in [10, 20]:
            with self.subTest(release_id=release_id):
                client = GitHubRelease('owner/repo')
                with mock.patch.object(client, 'command') as command:
                    client.promote(release_id, 'title', 'notes')
                command.assert_called_once_with(
                    'api', '--method', 'PATCH',
                    f'repos/owner/repo/releases/{release_id}',
                    '-F', 'draft=false',
                    '-f', 'name=title',
                    '-f', 'body=notes',
                )

    def test_new_draft_returns_the_created_release(self):
        client = GitHubRelease('owner/repo')
        created = {'id': 10, 'draft': True, 'tag_name': 'build-123-1'}
        with mock.patch.object(
            client, 'command', return_value=json.dumps(created),
        ) as command:
            self.assertEqual(
                client.create_draft('build-123-1', 'title', 'notes', 'a' * 40),
                created,
            )
        command.assert_called_once_with(
            'api', '--method', 'POST', 'repos/owner/repo/releases',
            '-f', 'tag_name=build-123-1',
            '-f', 'target_commitish=' + 'a' * 40,
            '-F', 'draft=true',
            '-f', 'name=title',
            '-f', 'body=notes',
        )

    def test_upload_failure_preserves_old_downloads(self):
        self.client.fail_upload = True
        with self.assertRaisesRegex(RuntimeError, 'interrupted'):
            self.publish()
        self.assertNotIn('delete', self.client.calls)
        self.assertNotIn('promote', self.client.calls)
        self.assertEqual(self.client.remote[0]['name'], 'previous.apk')

    def test_missing_digest_prevents_promotion(self):
        self.client.bad_digest = True
        with self.assertRaisesRegex(RuntimeError, 'verified'):
            self.publish()
        self.assertNotIn('delete', self.client.calls)
        self.assertNotIn('promote', self.client.calls)

    def test_metadata_failure_keeps_both_generations(self):
        self.client.fail_promote = True
        with self.assertRaisesRegex(RuntimeError, 'update failed'):
            self.publish()
        self.assertNotIn('delete', self.client.calls)
        self.assertEqual(len(self.client.remote), 2)

    def test_repeated_publish_reuses_identical_verified_assets(self):
        self.publish()
        self.client.calls.clear()
        self.publish()
        self.assertEqual(self.client.calls, ['list', 'list', 'promote'])

    def test_name_collision_is_not_overwritten(self):
        self.client.remote[0]['name'] = 'new.apk'
        with self.assertRaisesRegex(RuntimeError, 'Conflicting'):
            self.publish()
        self.assertEqual(self.client.calls, ['list'])

    def test_first_publish_stays_draft_if_upload_fails(self):
        self.client.exists = False
        self.client.remote = []
        self.client.fail_upload = True
        with self.assertRaises(RuntimeError):
            self.publish()
        self.assertEqual(self.client.calls[0], 'draft')
        self.assertNotIn('promote', self.client.calls)

    def test_first_publish_creates_the_draft_and_uploads_by_id(self):
        # 创建响应自带 release 对象，草稿链路全程按 id 操作，不回读列表接口。
        self.client.exists = False
        self.client.remote = []
        self.publish()
        self.assertEqual(self.client.calls,
                         ['draft', 'list', 'upload:new.apk', 'list', 'promote'])
        self.assertEqual(self.client.release_ids, [10, 10])

    def test_only_404_is_treated_as_missing_release(self):
        client = GitHubRelease('owner/repo')
        for status in [403, 500]:
            error = subprocess.CalledProcessError(1, ['gh'], stderr=f'gh: error (HTTP {status})')
            with mock.patch.object(client, 'command', side_effect=error):
                with self.assertRaises(subprocess.CalledProcessError):
                    client.release('latest')
        error = subprocess.CalledProcessError(1, ['gh'], stderr='gh: Not Found (HTTP 404)')
        with mock.patch.object(client, 'command', side_effect=error):
            self.assertIsNone(client.release('latest'))

    def test_collection_requires_an_android_package_and_records_ios(self):
        artifacts = self.root / 'artifacts'
        ios = artifacts / 'hongguojian-ios-unsigned' / 'ios.zip'
        ios.parent.mkdir(parents=True)
        ios.write_bytes(b'unsigned-ios')
        unrelated = artifacts / 'format-patch' / 'unrelated.zip'
        unrelated.parent.mkdir(parents=True)
        unrelated.write_bytes(b'not a package')
        with self.assertRaisesRegex(ValueError, 'Android APK'):
            prepare_assets(artifacts, self.root / 'incomplete', 'a' * 40, '123', '1', 'failure')
        apk = artifacts / 'hongguojian-android' / 'hongguojian.apk'
        apk.parent.mkdir(parents=True)
        apk.write_bytes(b'hongguojian')
        assets = prepare_assets(artifacts, self.root / 'release', 'a' * 40, '123', '2', 'success')
        manifest = next(path for name, path in assets.items() if name.endswith('.json'))
        data = json.loads(manifest.read_text(encoding='utf-8'))
        self.assertEqual(data['commit'], 'a' * 40)
        self.assertEqual(data['iosJobResult'], 'success')
        self.assertEqual(len(data['packages']), 2)
        # 附件名只带这一次运行的编号，不带提交哈希。
        self.assertTrue(all('-123-2' in name for name in assets))
        self.assertFalse(any('aaaaaaaaaaaa' in name for name in assets))
        self.assertTrue(all(len(package['sha256']) == 64 for package in data['packages']))
        self.assertFalse(any('unrelated' in name for name in assets))

    def test_workflow_waits_for_ios_without_adding_checks_dependency(self):
        workflow = (Path(__file__).resolve().parents[1] / '.github/workflows/build.yml').read_text(encoding='utf-8')
        release = workflow.split('  release:\n', 1)[1]
        self.assertIn('needs: [android, ios]', release)
        self.assertIn("needs.android.result == 'success'", release)
        self.assertNotIn('needs.ios.result ==', release)
        self.assertNotIn('needs.checks', release)
        self.assertIn('!cancelled()', release)


if __name__ == '__main__':
    unittest.main()
