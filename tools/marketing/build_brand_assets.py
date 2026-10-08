"""Export an opaque knight app icon and a transparent, game-name-only wordmark."""
from pathlib import Path
import hashlib
import json
import shutil

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from graphics import ROOT, OUT, INK, text_art, font_path

BRAND = ROOT / 'output/imagegen/brand-kit/2026-10-08-pixel-crest'
DEST = OUT / 'brand'
GAME_NAME = '纪元急袭'
BACKGROUND = (13, 23, 45)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def describe(path, role, text):
    with Image.open(path) as image:
        alpha = image.convert('RGBA').getchannel('A')
        return {'file': path.relative_to(OUT).as_posix(), 'role': role,
                'size': list(image.size), 'mode': image.mode,
                'alpha_range': list(alpha.getextrema()),
                'content_bounds': list(alpha.getbbox()), 'text': text,
                'sha256': sha(path)}


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    reference = BRAND / 'selected-logo.png'
    if not reference.exists():
        reference = ROOT / 'public/brand/approved-knight-crest.png'
    approved = Image.open(reference).convert('RGBA')
    portrait = approved.crop(approved.getchannel('A').getbbox())
    portrait.thumbnail((864, 864), Image.Resampling.NEAREST)
    icon = Image.new('RGBA', (1024, 1024), (*BACKGROUND, 255))
    draw = ImageDraw.Draw(icon)
    # Every corner is painted. The operating system supplies its launcher mask.
    for inset, color in [(24, (31, 49, 76)), (48, (22, 37, 61)), (80, (16, 28, 49))]:
        draw.rectangle((inset, inset, 1023-inset, 1023-inset), fill=(*color, 255))
    x, y = (1024-portrait.width)//2, (1024-portrait.height)//2
    shadow = Image.new('RGBA', portrait.size, (*INK, 0))
    shadow.putalpha(portrait.getchannel('A').filter(ImageFilter.MaxFilter(9)).point(lambda a: round(a*.8)))
    icon.alpha_composite(shadow, (x+6, y+12))
    icon.alpha_composite(portrait, (x, y))
    rows = []
    for size in [1024, 512]:
        path = DEST / f'game-icon-opaque-{size}.png'
        icon.convert('RGB').resize((size, size), Image.Resampling.NEAREST).save(path, optimize=True)
        rows.append(describe(path, 'game icon; fully opaque background', []))
    icon.convert('RGB').save(DEST / 'game-icon-opaque.ico', sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])

    font = ImageFont.truetype(str(font_path(True)), 64)
    missing = font.getmask('\uffff')
    for character in GAME_NAME:
        glyph = font.getmask(character)
        if not glyph.getbbox() or (glyph.size == missing.size and bytes(glyph) == bytes(missing)):
            raise RuntimeError('Game name glyph coverage is incomplete: '+character)
    size = 432
    while True:
        art, _, _ = text_art(GAME_NAME, size, display=True, tracking=30, block=3)
        art = art.crop(art.getchannel('A').getbbox())
        if art.width <= 1920 and art.height <= 400:
            break
        size -= 3
    master = Image.new('RGBA', (2048,512), (0,0,0,0))
    master.alpha_composite(art, ((master.width-art.width)//2, (master.height-art.height)//2))
    for width in [2048, 1024]:
        path = DEST / f'game-logo-transparent-{width}x{width//4}.png'
        master.resize((width,width//4), Image.Resampling.NEAREST).save(path, optimize=True)
        rows.append(describe(path, 'transparent game-name-only logo', [GAME_NAME]))

    # Store master assets in the project too, so application icon exports agree.
    public_brand = ROOT / 'public/brand'
    public_brand.mkdir(exist_ok=True)
    shutil.copy2(reference, public_brand / 'approved-knight-crest.png')
    shutil.copy2(DEST / 'game-logo-transparent-2048x512.png', public_brand / 'game-logo.png')
    shutil.copy2(DEST / 'game-icon-opaque-1024.png', ROOT / 'public/app-icon.png')
    shutil.copy2(DEST / 'game-icon-opaque.ico', ROOT / 'public/app-icon.ico')
    shutil.copy2(DEST / 'game-icon-opaque-512.png', ROOT / 'godot/assets/ui/pixel/app-icon.png')

    for density, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
        folder = ROOT / 'android/app/src/main/res' / ('mipmap-'+density)
        if folder.exists():
            image = icon.convert('RGB').resize((size,size), Image.Resampling.NEAREST)
            for name in ['ic_launcher.png','ic_launcher_round.png']:
                image.save(folder / name, optimize=True)
    ios = ROOT / 'ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png'
    if ios.parent.exists():
        shutil.copy2(DEST / 'game-icon-opaque-1024.png', ios)

    for row in rows:
        if row['role'].startswith('game icon') and row['alpha_range'] != [255,255]:
            raise RuntimeError('An icon contains transparent pixels')
        if row['role'].startswith('transparent'):
            if row['alpha_range'] != [0,255] or row['text'] != [GAME_NAME]:
                raise RuntimeError('Logo background or text requirement failed')
    with Image.open(DEST / 'game-icon-opaque.ico') as ico:
        ico_sizes = sorted(ico.ico.sizes())
        for ico_size in ico_sizes:
            if ico.ico.getimage(ico_size).convert('RGBA').getchannel('A').getextrema() != (255,255):
                raise RuntimeError('ICO frame contains transparency')
    report = {'game':GAME_NAME, 'date':'2026-10-08', 'source_character':reference.relative_to(ROOT).as_posix(),
              'source_character_sha256':sha(reference), 'font':'licensed Epoch Marketing Display / 得意黑',
              'requirements':{'icon_background':'fully opaque RGB; all ICO frames opaque',
                              'logo_background':'real alpha transparency', 'logo_text':[GAME_NAME],
                              'logo_composition':'four Chinese game-name glyphs only'},
              'files':rows, 'ico_sizes':[list(s) for s in ico_sizes]}
    (OUT / 'source/brand-assets.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'passed','brand_files':rows,'ico_frames_opaque':True},ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
