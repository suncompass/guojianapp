import base64
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class BuildVariant:
    all_sources: bool = False

    @property
    def name(self):
        return '真果鉴' if self.all_sources else '红果鉴'

    @property
    def slug(self):
        return 'zhenguojian' if self.all_sources else 'hongguojian'

    @property
    def arguments(self):
        return ['--all-sources'] if self.all_sources else []

    @property
    def flutter_arguments(self):
        return ['--dart-define=ALL_SOURCES=' + str(self.all_sources).lower()]

    @property
    def linker_flags(self):
        return '-s -w -X duanjuapp/native/core.buildAllSources=' + str(self.all_sources).lower()

    @classmethod
    def from_dart_defines(cls, encoded):
        values = {}
        for item in encoded.split(','):
            if not item:
                continue
            key, separator, value = base64.b64decode(item, validate=True).decode('utf-8').partition('=')
            if separator:
                values[key] = value
        return cls(values.get('ALL_SOURCES') == 'true')


def add_variant_argument(parser):
    parser.add_argument('--all-sources', action='store_true',
                        help='构建包含全部站源的真果鉴；默认构建仅红果的红果鉴')


def record_native_build(library, variant, *, platform, architecture):
    library = Path(library)
    metadata = {
        'format': 1,
        'allSources': variant.all_sources,
        'platform': platform,
        'architecture': architecture,
        'sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
    }
    library.with_suffix('.build.json').write_text(
        json.dumps(metadata, sort_keys=True) + '\n', encoding='utf-8')


def verify_native_build(library, variant, *, packaged=None):
    library = Path(library)
    manifest = library.with_suffix('.build.json')
    try:
        metadata = json.loads(manifest.read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        raise ValueError('原生核心缺少有效构建记录，请先运行完整构建脚本：' + str(library)) from error
    if not isinstance(metadata, dict) or metadata.get('format') != 1:
        raise ValueError('原生核心构建记录无效：' + str(library))
    if metadata.get('allSources') is not variant.all_sources:
        raise ValueError('应用与原生核心的站源配置不一致，请先运行完整构建脚本：' + str(library))
    data = library.read_bytes() if packaged is None else packaged
    if hashlib.sha256(data).hexdigest() != metadata.get('sha256'):
        raise ValueError('原生核心内容与构建记录不一致，请重新构建安装包：' + str(library))
    return metadata
