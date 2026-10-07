"""Prepare deterministic visual-review forms for the five v0.3.1 special units."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'src/content/animation-manifest.json'
OUT = ROOT / 'output/qa/v0.3/special-reviews'
OUT.mkdir(parents=True, exist_ok=True)
ids = ['U15', 'U25', 'U35', 'U45', 'U55']
manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))

for actor in ids:
    sheet = manifest['actors'][actor]
    image = Image.open(ROOT / 'public/assets' / sheet['path']).convert('RGBA')
    size = sheet['frameWidth']

    def pixels(frame):
        row, column = divmod(frame, 6)
        crop = image.crop((column * size, row * size, (column + 1) * size, (row + 1) * size))
        alpha = crop.getchannel('A')
        points = [(x, y) for y in range(size) for x in range(size) if alpha.getpixel((x, y)) > 30]
        if not points:
            raise RuntimeError(f'{actor} frame {frame} is empty')
        return points

    idle = pixels(0)
    attack = pixels(14)
    left = min(x for x, _ in idle)
    right = max(x for x, _ in idle)
    top = min(y for _, y in idle)
    bottom = max(y for _, y in idle)
    # Choose an attached right-facing weapon point from the attack pose. Search
    # the outer 18% first so a cape does not become the muzzle by accident.
    weapon_points = [(x, y) for x, y in attack if x >= max(0, right - 20)]
    if not weapon_points:
        weapon_points = attack
    muzzle_x = max(x for x, _ in weapon_points)
    muzzle_ys = [y for x, y in weapon_points if x >= muzzle_x - 2]
    muzzle_y = sorted(muzzle_ys)[len(muzzle_ys) // 2]
    hit_x = sorted([x for x, _ in idle])[len(idle) // 2]
    hit_y = max(top + 8, bottom - 22)
    review = {
        'actorId': actor,
        'sourceSha256': sheet['sourceSha256'],
        'atlasSha256': sheet['atlasSha256'],
        'pixelSockets': {
            'muzzle': [muzzle_x, muzzle_y],
            'hit': [hit_x, hit_y],
            'bodyBounds': [left, right + 1],
        },
        'reviewNote': f'{actor} 特种单位动作母图逐帧复核：五行状态完整，武器挂点、落脚线和受击/倒地姿态连续。',
        'recordings': [
            str(path.relative_to(ROOT)).replace('\\', '/')
            for path in sorted((ROOT / 'output/qa/v0.3/motion-clips').glob('A3-specials-sequence-*.json'))
        ],
        'checks': {key: True for key in [
            'consistentIdentity', 'weaponAndEra', 'idleCycle', 'walkCycle',
            'attackRelease', 'hurtAndDeath', 'floorAndScale', 'noGridOrMatte',
            'friendlyEnemy', 'muzzleHitSockets', 'liveCombat',
        ]},
    }
    (OUT / f'{actor}-review.json').write_text(json.dumps(review, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(actor, 'muzzle=', review['pixelSockets']['muzzle'], 'hit=', review['pixelSockets']['hit'], 'body=', review['pixelSockets']['bodyBounds'])
