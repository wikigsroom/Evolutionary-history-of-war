"""Fit collision bodies to the standing hulls, and finish ten-era socket metadata."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'godot/assets'

def main():
    path = ASSETS / 'data/animations.json'
    metadata = json.loads(path.read_text(encoding='utf-8'))
    measured = []
    for actor, row in metadata.items():
        if actor.startswith('SUM-'):
            row.update(bodyRadius=27, muzzle=[30, 50], hit=[0, 37])
            continue
        hero = actor.startswith('H')
        slot = int(actor[-1]) if actor.startswith('U') else 0
        height = 122 if hero else 124 if slot == 4 else 106 if slot == 5 else 96
        width, frame_height = row['frameWidth'], row['frameHeight']
        atlas = Image.open(ASSETS / row['path']).convert('RGBA')
        spans = []
        # Only the lower standing hull counts: weapon tips above it do not block movement.
        for index in row['clips']['idle']:
            columns = row.get('columns', 6)
            tile = atlas.crop((index % columns * width, index // columns * frame_height,
                               (index % columns + 1) * width, (index // columns + 1) * frame_height))
            alpha = np.asarray(tile)[:, :, 3]
            box = tile.getchannel('A').getbbox()
            if not box:
                raise RuntimeError(actor + ': missing standing hull')
            cutoff = round(box[1] + (box[3] - box[1]) * .55)
            ys, xs = np.nonzero((alpha > 64) & (np.indices(alpha.shape)[0] >= cutoff))
            if len(xs):
                anchor = float(row['anchor'][0]) * width
                spans.append(float(np.percentile(np.abs(xs - anchor), 98)) * height / row['bodyHeight'])
        minimum = 24 if hero else 38 if slot == 4 else 22 if slot == 1 else 16
        # Human cloaks, shields and weapon barrels are visual overhangs. Keep the
        # physical body constant during a hero's in-place era transformation.
        radius = round(max(minimum, min(140, max(spans) * .90)), 1) if slot == 4 else minimum
        row['bodyRadius'] = radius
        row['muzzle'] = [42, 73] if hero else [50, 76] if slot == 4 else [35, 57]
        row['hit'] = [0, 66] if hero else [0, 68] if slot == 4 else [0, 54]
        row['atlasSha256'] = {key: hashlib.sha256((ASSETS / row[file]).read_bytes()).hexdigest()
                              for key, file in [('own', 'path'), ('enemy', 'enemyPath')]}
        if '-A' in actor or actor.startswith('U'):
            first = atlas.crop((0, 0, width, frame_height))
            subject = first.crop(first.getchannel('A').getbbox())
            subject.thumbnail((88, 88), Image.Resampling.NEAREST)
            icon = Image.new('RGBA', (96, 96))
            icon.alpha_composite(subject, ((96-subject.width)//2, 92-subject.height))
            icon_path = ASSETS / ('ui/heroes' if hero else 'ui/units') / (actor + '.png')
            icon.save(icon_path, optimize=True)
            row['iconNormalization'] = 'standing silhouette fitted inside 88x88 pixels'
        measured.append({'id': actor, 'radius': radius, 'standingHalfWidth': round(max(spans), 2),
                         'logicalHeight': height, 'method': 'lower standing vehicle hull' if slot == 4 else 'stable humanoid body core; gear is visual overhang'})
    path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    report = ROOT / 'output/qa/ten-eras/assets/body-geometry.json'
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(measured, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'measuredActors': len(measured), 'wideBodies': [r for r in measured if r['radius'] > 38]}, ensure_ascii=False))

if __name__ == '__main__':
    main()
