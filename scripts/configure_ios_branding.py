import os
from pathlib import Path
import plistlib

from app_build import APP_NAME, APP_SLUG


def configure(path):
    data = plistlib.loads(path.read_bytes())
    data['CFBundleDisplayName'] = APP_NAME
    data['CFBundleName'] = APP_SLUG
    path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY, sort_keys=False))


if __name__ == '__main__':
    configure(Path(os.environ['TARGET_BUILD_DIR']) / os.environ['INFOPLIST_PATH'])
