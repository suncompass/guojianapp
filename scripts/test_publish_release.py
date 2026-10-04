import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

from publish_release import GitHubRelease, prepare_assets, publish_assets, sha256_file


class FakeRelease:
    def __init__(self):
        self.exists = True
        self.remote = [{'id': 1, 'name': 'previous.apk'}]
        self.calls = []
        self.fail_upload = False
        self.bad_digest = False
        self.fail_promote = False

    def release(self, tag):
        return {'id': 10} if self.exists else None

    def create_draft(self, *args):
        self.calls.append('draft')
        self.exists = True
        return {'id': 10}

    def assets(self, release_id):
        self.calls.append('list')
        return list(self.remote)

    def upload(self, tag, path):
        self.calls.append('upload:' + path.name)
        if self.fail_upload:
            raise RuntimeError('upload interrupted')
        self.remote.append({
            'id': len(self.remote) + 10, 'name': path.name, 'state': 'uploaded',
            'size': path.stat().st_size,
            'digest': None if self.bad_digest else 'sha256:' + sha256_file(path),
        })

    def promote(self, *args):
        self.calls.append('promote')
        if self.fail_promote:
            raise RuntimeError('release update failed')

    def remove_asset(self, asset_id):
        self.calls.append('delete')
        self.remote = [asset for asset in self.remote if asset['id'] != asset_id]


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

    def test_upload_and_verify_before_deleting_previous_generation(self):
        self.publish()
        self.assertEqual(self.client.calls, ['list', 'upload:new.apk', 'list', 'promote', 'delete'])
        self.assertEqual([asset['name'] for asset in self.client.remote], ['new.apk'])

    def test_upload_failure_preserves_old_downloads(self):
        self.client.fail_upload = True
        with self.assertRaisesRegex(RuntimeError, 'interrupted'):
            self.publish()
        self.assertNotIn('delete', self.client.calls)
        self.assertNotIn('promote', self.client.calls)
        self.assertEqual(self.client.remote[0]['name'], 'previous.apk')

    def test_missing_digest_prevents_promotion_and_cleanup(self):
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

    def test_collection_requires_both_android_editions_and_records_ios(self):
        artifacts = self.root / 'artifacts'
        first = artifacts / 'hongguojian-android' / 'hongguojian.apk'
        first.parent.mkdir(parents=True)
        first.write_bytes(b'hongguojian')
        with self.assertRaisesRegex(ValueError, 'Both Android'):
            prepare_assets(artifacts, self.root / 'incomplete', 'a' * 40, '123', '1', 'failure')
        second = artifacts / 'zhenguojian-android' / 'zhenguojian.apk'
        second.parent.mkdir(parents=True)
        second.write_bytes(b'zhenguojian')
        ios = artifacts / 'zhenguojian-ios-unsigned' / 'ios.zip'
        ios.parent.mkdir(parents=True)
        ios.write_bytes(b'unsigned-ios')
        unrelated = artifacts / 'format-patch' / 'unrelated.zip'
        unrelated.parent.mkdir(parents=True)
        unrelated.write_bytes(b'not a package')
        assets = prepare_assets(artifacts, self.root / 'release', 'a' * 40, '123', '2', 'success')
        manifest = next(path for name, path in assets.items() if name.endswith('.json'))
        data = json.loads(manifest.read_text(encoding='utf-8'))
        self.assertEqual(data['commit'], 'a' * 40)
        self.assertEqual(data['iosJobResult'], 'success')
        self.assertEqual(len(data['packages']), 3)
        self.assertTrue(all('-aaaaaaaaaaaa-123-2' in name for name in assets))
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
