"""Publish the five special units' generated icons, cards and action atlases."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / 'docs/epoch-rush/data/asset-manifest.json'
data = json.loads(path.read_text(encoding='utf-8'))
rows = data['entries']
existing = {row['key'] for row in rows}
for actor, era in [('U15', 'A1'), ('U25', 'A2'), ('U35', 'A3'), ('U45', 'A4'), ('U55', 'A5')]:
    for key, kind, target, size, method in [
        (f'unit.{actor}', 'sprite', f'characters/units/{actor}.png', [256, 256], 'sub2_animation_first_frame'),
        (f'unit.{actor}.enemy', 'sprite', f'characters/units/{actor}-enemy.png', [256, 256], 'sub2_animation_enemy_variant'),
        (f'animation.{actor}', 'animation', f'characters/animations/{actor}.png', [768, 640], 'sub2_animation_sheet'),
        (f'animation.{actor}.enemy', 'animation', f'characters/animations/{actor}-enemy.png', [768, 640], 'sub2_animation_enemy_variant'),
    ]:
        if key in existing:
            for row in rows:
                if row['key'] == key:
                    row.update(status='accepted', size=size, targetPath=target, method=method, ownerId=actor, milestone='M3', priority='full_release')
            continue
        rows.append({'key': key, 'kind': kind, 'targetPath': target, 'size': size, 'method': method,
                     'ownerId': actor, 'status': 'accepted', 'milestone': 'M3', 'priority': 'full_release'})
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'addedOrUpdated': 20, 'logicalAssets': len(rows)}, ensure_ascii=False))
