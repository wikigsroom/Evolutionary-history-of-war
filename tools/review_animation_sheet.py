"""Calibrate or accept a Sub2 sheet only after explicit visual review and bound canvas clips."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, hashlib, json, math, re, subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'public/assets'
MANIFEST = ROOT / 'src/content/animation-manifest.json'
CLIPS = {name: list(range(i * 6, (i + 1) * 6)) for i, name in enumerate(('idle', 'walk', 'attack', 'hurt', 'death'))}
CHECKS = ('consistentIdentity', 'weaponAndEra', 'idleCycle', 'walkCycle', 'attackRelease',
          'hurtAndDeath', 'floorAndScale', 'noGridOrMatte', 'friendlyEnemy', 'muzzleHitSockets', 'liveCombat')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
read = lambda p: json.loads(p.read_text(encoding='utf-8-sig'))

def local_path(value, base=ROOT):
    if not isinstance(value, str) or Path(value).is_absolute():
        raise ValueError('Expected a workspace-relative path')
    result = (base / value).resolve()
    if not result.is_relative_to(base.resolve()) or not result.is_file():
        raise ValueError('Missing or out-of-workspace file: ' + value)
    return result

def require(condition, message):
    if not condition:
        raise ValueError(message)

def validate_sheet(actor, sheet):
    source = local_path(sheet['sourcePath'])
    metadata = read(source.with_suffix('.metadata.json'))
    require(metadata.get('status') == 'generated' and metadata.get('model') == 'gpt-image-2.5'
            and metadata.get('route') == 'Sub2 CLI edit', 'Designated generation provenance missing')
    require(sha(source) == sheet['sourceSha256'] == metadata.get('sha256'), 'Raw source hash changed')
    prompt = local_path(f'output/imagegen/epoch-rush/v0.3-animation/prompts/{actor}.txt')
    require(sha(prompt) == metadata.get('promptSha256'), 'Generation prompt hash changed')
    require(sheet['clips'] == CLIPS, 'Expected five canonical six-frame rows')
    for side, key in [('own', 'path'), ('enemy', 'enemyPath')]:
        texture = local_path(sheet[key], ASSETS)
        require(sha(texture) == sheet['atlasSha256'][side], 'Atlas hash changed: ' + side)
        with Image.open(texture) as image:
            require(image.size == (sheet['frameWidth'] * 6, sheet['frameHeight'] * 5), 'Invalid atlas grid')
            require(image.mode == 'RGBA', 'Atlas must preserve transparency')
    return Image.open(local_path(sheet['path'], ASSETS)).convert('RGBA')

def calibrate(actor, sheet, review, atlas):
    profile_text = (ROOT / 'src/core/fighter-profiles.ts').read_text(encoding='utf-8')
    profile = re.search(r'\b' + re.escape(actor) + r": infantry\([^)]*\)", profile_text)
    require(profile is not None, 'Actor runtime height not found')
    height_match = re.search(r'height:\s*(\d+)', profile.group())
    height = int(height_match.group(1)) if height_match else 96
    scale = height / sheet['bodyHeight']
    width, frame_height = sheet['frameWidth'], sheet['frameHeight']
    result = {}
    body = review.get('pixelSockets', {}).get('bodyBounds')
    require(isinstance(body, list) and len(body) == 2 and all(isinstance(v, (int, float)) and math.isfinite(v) for v in body)
            and 0 <= body[0] < body[1] <= width, 'Mark the idle body bounds, excluding long weapons and capes')
    radius = math.ceil(max(sheet['anchor'][0] * width - body[0], body[1] - sheet['anchor'][0] * width) * scale)
    require(8 <= radius <= 110, 'Body footprint outside supported bounds')
    result['bodyRadius'] = radius
    for socket, frame in [('muzzle', 14), ('hit', 0)]:
        pixel = review.get('pixelSockets', {}).get(socket)
        require(isinstance(pixel, list) and len(pixel) == 2 and all(isinstance(v, (int, float)) and math.isfinite(v) for v in pixel), 'Missing pixel socket: ' + socket)
        x, y = pixel
        require(0 <= x < width and 0 <= y < frame_height, 'Socket outside its frame')
        tile = atlas.crop((frame % 6 * width, frame // 6 * frame_height,
                           (frame % 6 + 1) * width, (frame // 6 + 1) * frame_height))
        area = tile.getchannel('A').crop((max(0, round(x)-4), max(0, round(y)-4), min(width, round(x)+5), min(frame_height, round(y)+5)))
        require(area.getextrema()[1] > 30, 'Socket does not touch the character or weapon')
        world_x = (x - sheet['anchor'][0] * width) * scale if socket == 'muzzle' else 0
        world_y = (sheet['anchor'][1] * frame_height - y) * scale
        require(0 <= world_y <= height + 24 and abs(world_x) <= 150, 'Socket outside runtime character bounds')
        result[socket] = [round(world_x, 3), round(world_y, 3)]
    return result

def evidence(actor, sheet, names, sockets):
    require(isinstance(names, list), 'Recording metadata paths missing')
    result, covered = [], set()
    for name in names:
        sidecar = local_path(name)
        require(sidecar.is_relative_to((ROOT / 'output/qa/v0.3/motion-clips').resolve()), 'Use the real gallery recorder output')
        clip = read(sidecar)
        side, speed = clip.get('side'), clip.get('speed')
        require(side in (0, 1) and speed in (1, .25), 'Invalid clip side or speed')
        require(clip.get('kind') == 'epoch_animation_review' and clip.get('mode') == 'sequence'
                and clip.get('live') is False and clip.get('completeSequence') is True
                and clip.get('tickStart') == 0 and clip.get('tickEnd', 0) >= 251, 'Five-phase recording incomplete')
        require(actor in clip.get('visibleActorIds', []), 'Actor is outside the recorded viewport')
        source = clip.get('sources', {}).get(actor, {})
        require(source.get('representation') == 'authored_pose' and source.get('sourceSha256') == sheet['sourceSha256']
                and source.get('atlasSha256') == sheet['atlasSha256']['own' if side == 0 else 'enemy'], 'Recording used different or legacy art')
        require(all(source.get(key) == value for key, value in sockets.items()), 'Recording used different body or weapon calibration')
        video = sidecar.with_suffix('.webm')
        require(video.is_file() and video.stat().st_size == clip.get('bytes'), 'Recording file size changed')
        probe = subprocess.run(['ffprobe', '-v', 'error', '-show_entries',
                'stream=codec_name,width,height:packet=pts_time,duration_time', '-of', 'json', str(video)], capture_output=True, text=True, check=True)
        decoded = json.loads(probe.stdout)
        require(any(s.get('codec_name') in ('vp8', 'vp9') and s.get('width', 0) >= 480 for s in decoded.get('streams', [])), 'Recording cannot be decoded')
        packets = [p for p in decoded.get('packets', []) if 'pts_time' in p]
        require(len(packets) >= 100, 'Insufficient captured frames')
        duration = max(float(p['pts_time']) + float(p.get('duration_time', 1/30)) for p in packets) - min(float(p['pts_time']) for p in packets)
        expected = 251 / 30 / speed
        require(abs(duration - expected) <= expected * .15 and abs(clip.get('durationSec', 0) - expected) <= expected * .15, 'Recording speed or duration mismatch')
        result.append({'metadataPath': sidecar.relative_to(ROOT).as_posix(), 'metadataSha256': sha(sidecar),
                       'videoPath': video.relative_to(ROOT).as_posix(), 'videoSha256': sha(video),
                       'side': side, 'speed': speed, 'decodedDurationSec': round(duration, 3), 'capturedFrames': len(packets)})
        covered.add((side, speed))
    require(covered == {(0, 1), (0, .25), (1, 1), (1, .25)}, 'Record both teams at original and quarter speed')
    return result

parser = argparse.ArgumentParser()
parser.add_argument('--actor', required=True)
parser.add_argument('--review-file', required=True)
operation = parser.add_mutually_exclusive_group(required=True)
operation.add_argument('--calibrate-only', action='store_true')
operation.add_argument('--accept', action='store_true')
args = parser.parse_args()
manifest = read(MANIFEST)
require(args.actor in manifest['actors'], 'No generated sheet for ' + args.actor)
sheet = manifest['actors'][args.actor]
review_path = local_path(args.review_file)
review = read(review_path)
require(review.get('actorId') == args.actor and review.get('sourceSha256') == sheet['sourceSha256']
        and review.get('atlasSha256') == sheet['atlasSha256'], 'Review refers to a different source or atlas')
atlas = validate_sheet(args.actor, sheet)
sockets = calibrate(args.actor, sheet, review, atlas)
if args.accept:
    require(all(review.get('checks', {}).get(key) is True for key in CHECKS), 'Every visual check must be explicitly completed')
    note = review.get('reviewNote', '').strip()
    require(len(note) >= 16, 'Write a concrete visual review note')
    records = evidence(args.actor, sheet, review.get('recordings'), sockets)
    require(all(sheet.get(key) == value for key, value in sockets.items()), 'Calibrate, capture, then accept without changing sockets')
# Changing sockets or derivative files invalidates any previous acceptance first.
sheet.update(sockets, review='pending')
sheet.pop('reviewNote', None)
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
if args.accept:
    runtime_path = ASSETS / 'manifest.json'
    runtime = read(runtime_path)
    derivatives = []
    prefix = 'hero' if args.actor.startswith('H') else 'unit'
    keys = [prefix+'.'+args.actor, prefix+'.'+args.actor+'.enemy']
    if prefix == 'unit': keys.append('icon.'+args.actor)
    for key in keys:
        entry = runtime['entries'][key]
        texture = local_path(entry['path'], ASSETS)
        source_atlas = Image.open(local_path(sheet['enemyPath'] if key.endswith('.enemy') else sheet['path'], ASSETS)).convert('RGBA')
        first = source_atlas.crop((0, 0, sheet['frameWidth'], sheet['frameHeight']))
        size = tuple(entry['size'])
        first.resize(size, Image.Resampling.LANCZOS).save(texture, optimize=True)
        entry.update(status='visual_review_accepted', sourceSha256=sheet['sourceSha256'], sha256=sha(texture),
                     derivedFrom=sheet['sourcePath'], model='gpt-image-2.5')
        derivatives.append({'key': key, 'path': entry['path'], 'sha256': sha(texture)})
    frozen = ROOT / f'output/imagegen/epoch-rush/v0.3-animation/reviews/{args.actor}-{sheet["sourceSha256"][:12]}.json'
    frozen.parent.mkdir(parents=True, exist_ok=True)
    frozen.write_bytes(review_path.read_bytes())
    sheet.update(review='accepted', reviewNote=note, reviewedAtUtc=datetime.now(timezone.utc).isoformat(),
                 reviewChecks=review['checks'], reviewEvidence=records, visualDerivatives=derivatives,
                 reviewFile={'path': frozen.relative_to(ROOT).as_posix(), 'sha256': sha(frozen)})
    for key in (sheet['key'], sheet['enemyKey']):
        runtime['entries'][key].update(status='visual_review_accepted', sha256=sheet['atlasSha256']['own' if key == sheet['key'] else 'enemy'])
    runtime_path.write_text(json.dumps(runtime, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(json.dumps({'actor': args.actor, 'status': sheet['review'], 'sockets': sockets, 'acceptedImages': 1 if args.accept else 0}, ensure_ascii=False))
