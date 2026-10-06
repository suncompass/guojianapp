import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from app_build import record_native_build, verify_native_build
from configure_ios_branding import configure


def dart_defines(*values):
    return ','.join(base64.b64encode(value.encode()).decode() for value in values)


class AppBuildTests(unittest.TestCase):
    def test_native_core_rejects_missing_record_and_stale_packaged_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / 'libduanju_core.so'
            library.write_bytes(b'synthetic native core')
            with self.assertRaisesRegex(ValueError, '缺少有效构建记录'):
                verify_native_build(library)
            record_native_build(library, platform='android', architecture='arm64')
            self.assertFalse(verify_native_build(library)['allSources'])
            with self.assertRaisesRegex(ValueError, '内容与构建记录不一致'):
                verify_native_build(library, packaged=b'old packaged core')
            library.write_bytes(b'replaced core')
            with self.assertRaisesRegex(ValueError, '内容与构建记录不一致'):
                verify_native_build(library)

    def test_full_source_native_core_is_rejected(self):
        # 历史遗留的全站源核心即使自洽也不能再打包：现在的脚本只产出红果鉴核心。
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / 'libduanju_core.so'
            library.write_bytes(b'synthetic native core')
            library.with_suffix('.build.json').write_text(json.dumps({
                'format': 1, 'allSources': True, 'platform': 'android',
                'architecture': 'arm64',
                'sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
            }), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, '全站源版本'):
                verify_native_build(library)

    def test_ios_branding_is_fixed_to_the_single_edition(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'Info.plist'
            original = {'CFBundleIdentifier': 'com.duanju.duanjuApp', 'CFBundleVersion': '9'}
            path.write_bytes(plistlib.dumps(original))
            configure(path)
            actual = plistlib.loads(path.read_bytes())
            self.assertEqual(actual['CFBundleDisplayName'], '红果鉴')
            self.assertEqual(actual['CFBundleName'], 'hongguojian')
            for key, value in original.items():
                self.assertEqual(actual[key], value)

    @unittest.skipUnless(shutil.which('cmake'), 'CMake is unavailable')
    def test_windows_branding_ignores_dart_defines(self):
        branding = Path(__file__).resolve().parents[1] / 'windows/runner/app_branding.cmake'
        for flags in [[], ['ALL_SOURCES=true']]:
            with self.subTest(flags=flags), tempfile.TemporaryDirectory() as temporary:
                script = Path(temporary) / 'check.cmake'
                result = Path(temporary) / 'name.txt'
                script.write_text(
                    'list(APPEND FLUTTER_TOOL_ENVIRONMENT "OTHER=1" "DART_DEFINES=' + dart_defines(*flags) + '")\n'
                    'include("' + branding.as_posix() + '")\n'
                    'file(WRITE "' + result.as_posix() + '" "${APP_DISPLAY_NAME} ${APP_EXECUTABLE_NAME}")\n',
                    encoding='utf-8',
                )
                subprocess.run(['cmake', '-P', str(script)], check=True, capture_output=True)
                self.assertEqual(result.read_text(encoding='utf-8'), '红果鉴 hongguojian.exe')

    def test_android_and_windows_build_one_edition_without_variant_flags(self):
        root = Path(__file__).resolve().parent
        for target in ['android', 'windows']:
            with self.subTest(target=target):
                script = root / f'build_{target}.py'
                with mock.patch.object(sys, 'argv', [str(script)]), \
                        mock.patch.dict(os.environ, {'PATH': '/tools'}, clear=True), \
                        mock.patch('shutil.which', return_value='/tools/flutter'), \
                        mock.patch('subprocess.run') as run:
                    runpy.run_path(str(script), run_name='__main__')
                calls = [call.args[0] for call in run.call_args_list]
                native = next(call for call in calls if any(str(arg).endswith('build_native.py') for arg in call))
                flutter = next(call for call in calls if 'build' in call)
                package = next(call for call in calls if any(str(arg).endswith('package_release.py') for arg in call))
                for call in [native, flutter, package]:
                    arguments = [str(arg) for arg in call]
                    self.assertNotIn('--all-sources', arguments)
                    self.assertFalse([arg for arg in arguments if 'ALL_SOURCES' in arg])


if __name__ == '__main__':
    unittest.main()
