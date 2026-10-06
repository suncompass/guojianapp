import hashlib
import json
from pathlib import Path


# 只出红果鉴单一版本：站源、启动器名称、包名与可执行文件名都不再随编译开关变化。
APP_NAME = '红果鉴'
APP_SLUG = 'hongguojian'


def record_native_build(library, *, platform, architecture):
    library = Path(library)
    metadata = {
        'format': 1,
        # 原生核心不再编译全站源变体；该字段恒为 False，用于拒绝历史遗留的核心。
        'allSources': False,
        'platform': platform,
        'architecture': architecture,
        'sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
    }
    library.with_suffix('.build.json').write_text(
        json.dumps(metadata, sort_keys=True) + '\n', encoding='utf-8')


def verify_native_build(library, *, packaged=None):
    library = Path(library)
    manifest = library.with_suffix('.build.json')
    try:
        metadata = json.loads(manifest.read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        raise ValueError('原生核心缺少有效构建记录，请先运行完整构建脚本：' + str(library)) from error
    if not isinstance(metadata, dict) or metadata.get('format') != 1:
        raise ValueError('原生核心构建记录无效：' + str(library))
    if metadata.get('allSources') is not False:
        raise ValueError('原生核心仍是全站源版本，请先运行完整构建脚本：' + str(library))
    data = library.read_bytes() if packaged is None else packaged
    if hashlib.sha256(data).hexdigest() != metadata.get('sha256'):
        raise ValueError('原生核心内容与构建记录不一致，请重新构建安装包：' + str(library))
    return metadata
