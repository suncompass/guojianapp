import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description='从 assets/branding/app_icon.png 生成平台图标与电视横幅；需要 Pillow。')
parser.add_argument('--output', type=Path, default=root)
parser.add_argument('--font', type=Path, default=Path('/System/Library/Fonts/PingFang.ttc'))
options = parser.parse_args()
output = options.output
with Image.open(root / 'assets/branding/app_icon.png') as source:
    icon = source.convert('RGBA')
if icon.width != icon.height:
    parser.error('应用图标必须是正方形。')
opaque_icon = Image.new('RGB', icon.size, icon.getpixel((icon.width // 2, 0))[:3])
opaque_icon.paste(icon, mask=icon.getchannel('A'))

def save(image, name, **options):
    destination = output / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, **options)

for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                      ('xxhdpi', 144), ('xxxhdpi', 192)]:
    save(icon.resize((size, size), Image.Resampling.LANCZOS),
         f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')

contents = json.loads((root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json').read_text())
for entry in contents['images']:
    if 'filename' in entry:
        size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
        save(opaque_icon.resize((size, size), Image.Resampling.LANCZOS),
             'ios/Runner/Assets.xcassets/AppIcon.appiconset/' + entry['filename'])
save(icon.resize((256, 256), Image.Resampling.LANCZOS),
     'windows/runner/resources/app_icon.ico',
     sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)])
font = ImageFont.truetype(str(options.font), 76)
banner_icon = icon.resize((180, 180), Image.Resampling.LANCZOS)
for name, resource in [('红果鉴', 'tv_banner'), ('真果鉴', 'tv_banner_all_sources')]:
    banner = Image.new('RGB', (640, 360), '#101114')
    banner.paste(banner_icon, (44, 90), banner_icon)
    draw = ImageDraw.Draw(banner)
    draw.text((255, 128), name, font=font, fill='white')
    save(banner, f'android/app/src/main/res/drawable-xhdpi/{resource}.png')
