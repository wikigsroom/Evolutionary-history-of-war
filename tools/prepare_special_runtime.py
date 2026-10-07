"""Create first-frame sprite/card derivatives for special-unit review acceptance."""
from pathlib import Path
import hashlib, json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ANIMATION = json.loads((ROOT / 'src/content/animation-manifest.json').read_text(encoding='utf-8'))
RUNTIME_PATH = ROOT / 'public/assets/manifest.json'
RUNTIME = json.loads(RUNTIME_PATH.read_text(encoding='utf-8'))
DEST = ROOT / 'public/assets/characters/units'
DEST.mkdir(parents=True, exist_ok=True)

for actor in ['U15', 'U25', 'U35', 'U45', 'U55']:
    sheet = ANIMATION['actors'][actor]
    source_sha = sheet['sourceSha256']
    for enemy, atlas_key in [(False, 'own'), (True, 'enemy')]:
        key = f'unit.{actor}.enemy' if enemy else f'unit.{actor}'
        name = f'{actor}-enemy.png' if enemy else f'{actor}.png'
        atlas_path = ROOT / 'public/assets' / (sheet['enemyPath'] if enemy else sheet['path'])
        with Image.open(atlas_path).convert('RGBA') as atlas:
            frame = atlas.crop((0, 0, sheet['frameWidth'], sheet['frameHeight'])).resize((256, 256), Image.Resampling.LANCZOS)
            target = DEST / name
            frame.save(target, optimize=True)
        sha = hashlib.sha256(target.read_bytes()).hexdigest()
        RUNTIME['entries'][key] = {
            'key': key, 'path': f'characters/units/{name}', 'kind': 'sprite',
            'size': [256, 256], 'anchor': [0.5, 0.9],
            'status': 'processed_pending_visual_review', 'model': 'gpt-image-2.5',
            'source': sheet['sourcePath'], 'sha256': sha, 'sourceSha256': source_sha,
            'derivedFrom': sheet['sourcePath'],
        }

RUNTIME_PATH.write_text(json.dumps(RUNTIME, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'created': 10, 'actors': 5}, ensure_ascii=False))
