"""Verify the delivered files, decoded movies and native-capture provenance."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import math
import shutil
import subprocess

import numpy as np
from PIL import Image

from graphics import ROOT, OUT


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def digest(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def verify_movie(file, seconds, dimensions):
    info = json.loads(subprocess.run(
        [shutil.which('ffprobe'), '-v', 'error', '-count_frames', '-show_streams',
         '-show_format', '-of', 'json', str(file)],
        check=True, capture_output=True, text=True, encoding='utf-8').stdout)
    video = next(s for s in info['streams'] if s['codec_type'] == 'video')
    sound = next(s for s in info['streams'] if s['codec_type'] == 'audio')
    require([video['width'], video['height']] == dimensions, f'{file.name}: dimensions')
    require(video['r_frame_rate'] == '30/1', f'{file.name}: fps')
    require(int(video['nb_read_frames']) == seconds * 30, f'{file.name}: decoded frames')
    require(abs(float(info['format']['duration']) - seconds) < .01, f'{file.name}: duration')
    require(sound['sample_rate'] == '48000' and sound['channels'] == 2, f'{file.name}: audio format')
    decoded = subprocess.run(
        [shutil.which('ffmpeg'), '-hide_banner', '-v', 'error', '-i', str(file),
         '-f', 'null', 'NUL'], capture_output=True, text=True, encoding='utf-8')
    require(decoded.returncode == 0 and not decoded.stderr.strip(), f'{file.name}: decode errors')
    pcm = subprocess.run(
        [shutil.which('ffmpeg'), '-v', 'error', '-i', str(file), '-vn',
         '-ar', '48000', '-ac', '2', '-f', 'f32le', 'pipe:1'],
        check=True, capture_output=True).stdout
    audio = np.frombuffer(pcm, dtype='<f4').reshape(-1, 2)
    peak = float(np.max(np.abs(audio)))
    rms = np.sqrt(np.mean(audio.astype(np.float64) ** 2, axis=0))
    require(np.isfinite(audio).all() and np.all(rms > .0001), f'{file.name}: empty audio')
    clipping = float(np.mean(np.abs(audio) >= 1))
    require(clipping == 0, f'{file.name}: clipped audio')
    # Extract every second to detect frozen output and accidental black intervals.
    raw = subprocess.run(
        [shutil.which('ffmpeg'), '-v', 'error', '-i', str(file), '-an',
         '-vf', 'fps=1,scale=160:90', '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'],
        check=True, capture_output=True).stdout
    frames = np.frombuffer(raw, np.uint8).reshape(-1, 90, 160, 3)
    brightness = frames.mean(axis=(1, 2, 3))
    unique = len({hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames})
    require(float(brightness.min()) > 3, f'{file.name}: black interval')
    require(unique >= seconds * .9, f'{file.name}: frozen intervals')
    return {'file': file.relative_to(OUT).as_posix(), 'seconds': seconds,
            'size': dimensions, 'fps': 30, 'decoded_frames': int(video['nb_read_frames']),
            'codec': video['codec_name'], 'audio_codec': sound['codec_name'],
            'audio_sample_rate': 48000, 'audio_channels': 2,
            'audio_peak_dbfs': round(20 * math.log10(max(peak, 1e-12)), 3),
            'audio_rms_dbfs': [round(20 * math.log10(float(r)), 3) for r in rms],
            'audio_clipped_fraction': clipping, 'unique_sampled_frames': unique,
            'minimum_sampled_brightness': round(float(brightness.min()), 2),
            'full_decode': 'passed', 'bytes': file.stat().st_size, 'sha256': digest(file)}


def main():
    images = []
    shots = sorted((OUT / 'screenshots').glob('*.png'))
    require(len(shots) == 12, 'Expected exactly twelve native screenshots')
    key_art = sorted((OUT / 'promotional').glob('[0-9][0-9]-*.png'))
    require(len(key_art) == 5, 'Expected five branded promotional images')
    expected = [(file, (1920, 1080)) for file in shots + key_art]
    expected += [(OUT / 'promotional/no-logo-key-art-1920x1080.png', (1920, 1080)),
                 (OUT / 'covers/horizontal-cover-1920x1080.png', (1920, 1080)),
                 (OUT / 'covers/vertical-cover-1080x1620.png', (1080, 1620)),
                 (OUT / 'brand/game-icon-opaque-1024.png', (1024, 1024)),
                 (OUT / 'brand/game-logo-transparent-2048x512.png', (2048, 512)),
                 (OUT / 'banners/game-banner-2304x768.png', (2304, 768)),
                 (OUT / 'posters/game-poster-1536x2304.png', (1536, 2304)),
                 (OUT / 'wallpapers/library-background-no-logo-6144x1984.png', (6144, 1984)),
                 (OUT / 'wallpapers/library-background-no-logo-6144x3456.png', (6144, 3456))]
    for file, size in expected:
        with Image.open(file) as image:
            image.load()
            require(image.size == size, file.name + ': dimensions')
        images.append({'file': file.relative_to(OUT).as_posix(), 'size': list(size),
                       'bytes': file.stat().st_size, 'sha256': digest(file)})
    require(len({digest(f) for f in shots}) == 12, 'Duplicate screenshots')
    require(len({digest(f) for f in key_art}) == 5, 'Duplicate promotional images')
    plan = read_json(OUT / 'source/production-plan.json')
    require(digest(ROOT / plan['source_exe']) == plan['source_exe_sha256'], 'Release EXE changed')
    require(digest(OUT / 'source/selected-logo.png') == plan['logo_sha256'], 'Approved logo changed')
    image_report = read_json(OUT / 'source/image-production.json')
    branded = [r for r in image_report['artworks'] if r['role'] in ('16:9 promotional key art', 'horizontal cover', 'vertical cover')]
    require(len(branded) == 7 and all([t['text'] for t in r['typography']] == ['纪元急袭'] for r in branded),
            'Cover or promotional image contains text other than the game name')
    brand_report = read_json(OUT / 'source/brand-assets.json')
    for row in brand_report['files']:
        with Image.open(OUT / row['file']) as image:
            alpha = image.convert('RGBA').getchannel('A')
            require(digest(OUT / row['file']) == row['sha256'], 'Brand master changed')
            if row['role'].startswith('game icon'):
                require(alpha.getextrema() == (255,255), 'Game icon contains transparency')
            else:
                require(image.mode == 'RGBA' and alpha.getextrema() == (0,255), 'Logo has no real transparency')
                require(all(alpha.getpixel(corner) == 0 for corner in [(0,0),(image.width-1,0),(0,image.height-1),(image.width-1,image.height-1)]), 'Logo corners contain a matte background')
                require(row['text'] == ['纪元急袭'], 'Logo contains unexpected text')
    banner_report = read_json(ROOT / 'output/imagegen/brand-kit/2026-10-08-pixel-crest/brand-kit-manifest.json')
    require(all([t['text'] for t in r['typography']] == ['纪元急袭'] for r in banner_report['deliverables']),
            'Banner or poster contains unexpected text')
    clean = next(row for row in image_report['artworks'] if row['file'].startswith('promotional/no-logo'))
    require(not clean['typography'] and 'logo' not in clean, 'No-logo export contains added branding')
    library = [row for row in image_report['artworks'] if row['file'].startswith('wallpapers/')]
    require(len(library) == 2 and all(not row['typography'] and 'logo' not in row for row in library),
            'Library backgrounds contain added text or branding')
    neural = read_json(OUT / 'source/upscale/wallpaper-production.json')
    require(neural['exit_code'] == 0 and neural['scale'] == 4 and neural['master_size'] == [6688, 3764],
            'Neural upscale provenance missing')
    require(digest(OUT / neural['master']) == neural['master_sha256'], 'Neural master changed')
    for item in neural['exports']:
        require(item['size'][0] > 3840 and item['size'][1] > 1240, 'Library background below minimum')
        require(digest(OUT / item['file']) == item['sha256'], 'Neural export changed')
    for mode in ('screenshots', 'recording', 'showcase'):
        directory = OUT / 'source/native' / mode
        require(read_json(directory / 'exit.json')['exit_code'] == 0, mode + ': process failed')
        log = (directory / 'capture.log').read_text(encoding='utf-8', errors='replace')
        require('SCRIPT ERROR' not in log and 'ERROR:' not in log, mode + ': engine errors')
    recording = read_json(OUT / 'source/native/recording/recording-report.json')
    require(recording['audio_missing'] == 0, 'Missing native recording audio')
    for sample in recording['samples']:
        require(abs(sample['elapsed'] - (sample['video_time'] - 7)) < .001,
                'Continuous recording is not running at normal simulation speed')
    paid = [a for a in recording['actions'] if a['action']['type'] in ('train', 'research')]
    require(paid and all(a['after']['gold'] < a['before']['gold'] for a in paid),
            'Paid recruitment/research provenance missing')
    edit = read_json(OUT / 'source/video/trailer-edit.json')
    for scene in edit['scenes']:
        if scene['role'] != 'gameplay':
            continue
        require(scene['edit_start'] >= scene['normal_source_start'], 'Accelerated pre-roll in trailer')
        require(scene['edit_start'] + scene['duration'] <=
                scene['normal_source_start'] + scene['normal_source_duration'],
                'Trailer clip exceeds normal-rate native source')
    require(abs(sum(s['duration'] for s in edit['scenes']) - 7 * .3 - 45) < 1e-6,
            'Trailer timeline length')
    old_report = OUT / 'source/quality-report.json'
    cache = {m['file']: m for m in read_json(old_report)['movies']} if old_report.exists() else {}
    movies = []
    with ThreadPoolExecutor(max_workers=2) as pool:
        tasks = []
        for file, seconds, size in [('videos/gameplay-120s.mp4', 120, [1280, 720]),
                                    ('videos/trailer-45s-1920x1080.mp4', 45, [1920, 1080])]:
            old = cache.get(file)
            if old and old.get('full_decode') == 'passed' and old['sha256'] == digest(OUT / file):
                movies.append(old)
            else:
                tasks.append(pool.submit(verify_movie, OUT / file, seconds, size))
        movies += [task.result() for task in tasks]
    movies.sort(key=lambda m: m['file'])
    require((OUT / 'copy/game-introduction.txt').stat().st_size > 1000, 'Introduction missing')
    require((OUT / 'copy/developer-message.txt').stat().st_size > 1000, 'Developer message missing')
    copy = read_json(OUT / 'copy/homepage-recommendation.json')
    require(all(copy.get(key) for key in ['headline', 'recommendation', 'short']), 'Homepage text missing')
    banned = ''.join(chr(n) for n in [20687, 32032, 25351, 25381, 21488])
    for directory in ['copy', 'licenses']:
        for file in (OUT / directory).glob('*'):
            require(banned not in file.read_text(encoding='utf-8'), 'Removed subtitle in copy')
    report = {'status': 'passed', 'date': plan['date'], 'game': plan['game'],
              'version': plan['version'], 'screenshots': 12, 'promotional_images': 5,
              'final_still_images': len(images), 'images': images, 'movies': movies,
              'branding_requirements': {'opaque_icon':'passed', 'transparent_logo':'passed',
                                        'only_game_name_logo':'passed', 'only_game_name_marketing_stills':'passed'},
              'provenance': {'release_sha256': plan['source_exe_sha256'],
                             'approved_logo_sha256': plan['logo_sha256'],
                             'normal_rate_recording': True, 'legal_paid_actions': len(paid),
                             'normal_rate_trailer_source_ranges': True,
                             'missing_audio_files': recording['audio_missing'],
                             'library_neural_upscale': {'scale': neural['scale'], 'master_size': neural['master_size'],
                                                        'outputs': [item['size'] for item in neural['exports']]}},
              'visual_review': 'Review contact sheets and full covers before marking delivery complete.'}
    (OUT / 'source/quality-report.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': report['status'], 'stills': len(images), 'movies': movies},
                     ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
