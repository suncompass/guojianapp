import re
import unittest
from pathlib import Path


def workflow():
    return (Path(__file__).resolve().parents[1] / '.github/workflows/build.yml').read_text(
        encoding='utf-8')


def job_block(name):
    # 只截到下一个顶层 job（两个空格后紧跟非空白），不误伤 job 内部的缩进行。
    match = re.search(r'(?ms)^  ' + re.escape(name) + r':\n.*?(?=^  \S|\Z)', workflow())
    if match is None:
        raise AssertionError('workflow 缺少 job：' + name)
    return match.group(0)


class WorkflowTests(unittest.TestCase):
    def test_checks_are_independent_jobs(self):
        text = workflow()
        for name in ['scripts', 'dart', 'go']:
            self.assertIn('\n  ' + name + ':\n', text)
        self.assertNotIn('\n  checks:\n', text)
        self.assertIn('python3 -m unittest discover -s scripts', job_block('scripts'))
        self.assertIn('dart format --output=none --set-exit-if-changed', job_block('dart'))
        self.assertIn('dart analyze lib test integration_test test_driver', job_block('dart'))
        self.assertEqual(job_block('dart').count('flutter test --dart-define=DISABLE_REMOTE_IMAGES=true'), 1)
        self.assertIn('go test -race ./...', job_block('go'))
        self.assertIn('working-directory: native', job_block('go'))

    def test_packaging_and_release_do_not_depend_on_checks(self):
        text = workflow()
        android = job_block('android')
        ios = job_block('ios')
        release = job_block('release')
        for block in [android, ios]:
            self.assertNotIn('needs:', block)
        self.assertIn('needs: [android, ios]', release)
        for name in ['scripts', 'dart', 'go', 'checks']:
            self.assertNotIn('needs.' + name, release)
        self.assertIn("needs.android.result == 'success'", release)
        self.assertIn('!cancelled()', release)

    def test_single_edition_builds_on_both_platforms(self):
        text = workflow()
        self.assertNotIn('--all-sources', text)
        self.assertNotIn('ALL_SOURCES', text)
        self.assertNotIn('zhenguojian', text)
        self.assertIn('hongguojian-android', text)
        self.assertIn('hongguojian-ios-unsigned', text)
        self.assertIn('python3 scripts/publish_release.py', job_block('release'))


if __name__ == '__main__':
    unittest.main()
