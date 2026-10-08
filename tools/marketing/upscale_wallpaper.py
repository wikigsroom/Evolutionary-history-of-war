"""Restore the unlettered library artwork with native Windows GPU Real-ESRGAN."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

from graphics import ROOT, OUT, ART, INK, IVORY


CACHE = ROOT / 'output/tool-cache/real-esrgan-ncnn-vulkan-v0.2.0'
JOB = ROOT / 'output/tool-cache/native-wallpaper-sr-job'
SOURCE = ART / '01-evolution.png'
RECORD = OUT / 'source/upscale'
MASTER = RECORD / 'library-unlettered-real-esrgan-4x-6688x3764.png'
OUTPUTS = [('library-background-no-logo-6144x1984', (6144, 1984), (.5, .94)),
           ('library-background-no-logo-6144x3456', (6144, 3456), (.5, .5))]


def sha(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def native():
    executable = CACHE / 'realesrgan-ncnn-vulkan-v0.2.0-windows/realesrgan-ncnn-vulkan.exe'
    if not executable.is_file() or not (CACHE / 'models/realesrgan-x4plus-anime.bin').is_file():
        raise RuntimeError('The official Windows runtime and anime model must be prepared first')
    JOB.mkdir(parents=True, exist_ok=True)
    RECORD.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE, JOB / 'input.png')
    # ASCII relative paths keep the native image loader independent of path encoding.
    command = [str(executable), '-i', 'input.png', '-o', 'upscaled-4x.png',
               '-m', '../real-esrgan-ncnn-vulkan-v0.2.0/models',
               '-n', 'realesrgan-x4plus-anime', '-s', '4', '-t', '256',
               '-g', '0', '-j', '1:2:1', '-f', 'png']
    started = time.monotonic()
    print('Native GPU Real-ESRGAN 4x started.', flush=True)
    with (RECORD / 'native-inference.log').open('w', encoding='utf-8') as log:
        result = subprocess.run(command, cwd=JOB, stdout=log, stderr=subprocess.STDOUT,
                                creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        raise RuntimeError((RECORD / 'native-inference.log').read_text(encoding='utf-8', errors='replace')[-3000:])
    with Image.open(JOB / 'upscaled-4x.png') as image, Image.open(SOURCE) as original:
        image.load()
        if image.size != (original.width * 4, original.height * 4):
            raise RuntimeError('Neural output is not four times the source dimensions')
    shutil.copy2(JOB / 'upscaled-4x.png', MASTER)
    receipt = {'model': 'realesrgan-x4plus-anime', 'scale': 4,
               'runtime': 'native Windows ncnn Vulkan on GPU 0', 'tile_size': 256,
               'exit_code': result.returncode, 'wall_seconds': round(time.monotonic() - started, 3),
               'source': SOURCE.relative_to(ROOT).as_posix(), 'source_sha256': sha(SOURCE),
               'master': MASTER.relative_to(OUT).as_posix(), 'master_sha256': sha(MASTER),
               'model_provenance': json.loads((CACHE / 'download-info.json').read_text(encoding='utf-8')),
               'command': command, 'external_branding_added': False, 'text_added': False}
    (RECORD / 'native-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    shutil.copy2(CACHE / 'MODEL-LICENSE.txt', OUT / 'licenses/Real-ESRGAN-model-LICENSE.txt')
    shutil.copy2(CACHE / 'realesrgan-ncnn-vulkan-v0.2.0-windows/LICENSE',
                 OUT / 'licenses/Real-ESRGAN-ncnn-runtime-LICENSE.txt')
    print('Neural 4x master ready: ' + str(MASTER), flush=True)


def export():
    receipt = json.loads((RECORD / 'native-receipt.json').read_text(encoding='utf-8'))
    if receipt['master_sha256'] != sha(MASTER) or receipt['source_sha256'] != sha(SOURCE):
        raise RuntimeError('Source or neural master changed since inference')
    with Image.open(MASTER) as opened:
        master = opened.convert('RGB')
    with Image.open(SOURCE) as opened:
        original = opened.convert('RGB')
    if master.size != (6688, 3764):
        raise RuntimeError('Unexpected master dimensions')
    values = np.asarray(master.resize((512, 288), Image.Resampling.LANCZOS), np.float32)
    if float(values.std()) < 10 or float(values.mean()) < 10:
        raise RuntimeError('Invalid or empty neural output')
    reconstructed = np.asarray(master.resize(original.size, Image.Resampling.LANCZOS), np.float32)
    source_values = np.asarray(original, np.float32)
    mse = float(np.mean((reconstructed - source_values) ** 2))
    receipt['downsampled_source_psnr_db'] = round(float(10 * np.log10(255 ** 2 / max(mse, 1e-8))), 3)
    receipt['master_size'] = list(master.size)
    receipt['source_size'] = list(original.size)
    receipt['exports'] = []
    for stem, size, center in OUTPUTS:
        if size[0] <= 3840 or size[1] <= 1240:
            raise RuntimeError('Both output dimensions must exceed the requested minimum')
        image = ImageOps.fit(master, size, method=Image.Resampling.LANCZOS, centering=center)
        file = OUT / 'wallpapers' / (stem + '.png')
        image.save(file, optimize=True)
        image.save(file.with_suffix('.jpg'), quality=97, subsampling=0, optimize=True)
        with Image.open(file) as checked:
            checked.load()
            if checked.size != size:
                raise RuntimeError('Export dimensions do not match')
        receipt['exports'].append({'file': file.relative_to(OUT).as_posix(), 'size': list(size),
                                   'centering': list(center), 'bytes': file.stat().st_size,
                                   'sha256': sha(file), 'typography': [], 'logo': None,
                                   'postprocessing': 'Aspect-preserving crop and Lanczos reduction of neural 4x master'})
        print('Exported ' + file.name, flush=True)
    (RECORD / 'wallpaper-production.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    # Comparison labels belong only to this separate evidence sheet.
    font = ImageFont.truetype(str(OUT / 'source/fonts/body.ttf'), 24)
    board = Image.new('RGB', (1800, 1540), INK)
    draw = ImageDraw.Draw(board)
    draw.text((32, 16), 'Original (nearest)', font=font, fill=IVORY)
    draw.text((932, 16), 'Real-ESRGAN 4x', font=font, fill=IVORY)
    for i, crop in enumerate([(310, 540, 710, 870), (1070, 530, 1500, 860)]):
        left = original.crop(crop).resize((868, 716), Image.Resampling.NEAREST)
        right = master.crop(tuple(c * 4 for c in crop)).resize((868, 716), Image.Resampling.LANCZOS)
        board.paste(left, (16, 62 + i * 736))
        board.paste(right, (916, 62 + i * 736))
    board.save(OUT / 'previews/wallpaper-super-resolution-comparison.jpg', quality=97, subsampling=0)
    print('Saved dimensions, neural provenance and comparison sheet.', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['native', 'export', 'all'])
    stage = parser.parse_args().stage
    if stage in ['native', 'all']:
        native()
    if stage in ['export', 'all']:
        export()


if __name__ == '__main__':
    main()
