"""Prepare concrete Sub2 generation requests from the reviewed design catalog."""
from pathlib import Path
import re
import json

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / 'docs/epoch-rush'
OUTPUT = ROOT / 'output/imagegen/epoch-rush/prompts'
OUTPUT.mkdir(parents=True, exist_ok=True)
for name in ['02-角色与专精.md', '04-兵种与炮塔.md']:
    content = (DESIGN / 'prompts' / name).read_text(encoding='utf-8')
    for identifier, block in re.findall(r'(?ms)^## ((?:H\d{2}|U\d{2}|TR\d{2})) .*?\n\n(.*?)(?=^## |\Z)', content):
        prompt = re.search(r'```text\n(.*?)\n```', block, re.S).group(1)
        (OUTPUT / f'{identifier}.txt').write_text(prompt, encoding='utf-8')
content = (DESIGN / 'prompts/03-五时代场景.md').read_text(encoding='utf-8')
for identifier, block in re.findall(r'(?ms)^## (A\d) .*?\n\n(.*?)(?=^## |\Z)', content):
    prompts = re.findall(r'```text\n(.*?)\n```', block, re.S)
    (OUTPUT / f'base-{identifier}.txt').write_text(prompts[0], encoding='utf-8')
    for layer, detail in [('far', 'far sky and distant mountains, very low contrast, fully opaque'), ('mid', 'distant historical buildings, low contrast, transparent lower edge'), ('ground', 'a flat walkable ochre earth strip, seamless horizontal edges, no foreground obstacles')]:
        (OUTPUT / f'background-{identifier}-{layer}.txt').write_text(prompts[1].replace('[LAYER]', detail), encoding='utf-8')
content = (DESIGN / 'prompts/05-界面掉落与特效.md').read_text(encoding='utf-8')
icon_template = 'Original 2D painted historical cartoon game icon, [SUBJECT], one centered clear object, chunky dark-brown contour, warm ochre and blue accents, two flat shading levels, true transparent background, no letters, digits, logo or decorative microdetail, legible at 32 pixels. No panel frame or background scene.'
for identifier, subject in re.findall(r'(?m)^\| ((?:HS|S|ST)\d{2}) \| ([^|]+) \|$', content):
    family = 'status' if identifier.startswith('ST') else 'skill'
    (OUTPUT / f'{family}-{identifier}.txt').write_text(icon_template.replace('[SUBJECT]',subject.strip()),encoding='utf-8')
for identifier, _, subject in re.findall(r'(?m)^\| (I\d{2}) \| ([^|]+) \| ([^|]+) \|$',content):
    (OUTPUT / f'relic-{identifier}.txt').write_text(icon_template.replace('[SUBJECT]',subject.strip()),encoding='utf-8')
subjects = {
    'resource.gold':'one thick brass military coin', 'resource.knowledge':'a compact rolled archive scroll',
    'resource.command':'one clear amber time crystal', 'resource.proficiency':'a simple commander silhouette badge',
    'resource.fragment':'two broken cyan crystal pieces', 'resource.mastery':'one branching wooden emblem',
    'fx.stone_impact':'a small scattered burst of pale stone chips', 'fx.metal_impact':'three chunky steel chips with one short ochre spark',
    'fx.muzzle':'a compact three-point ochre muzzle flash', 'fx.dust':'one soft brown ground dust puff',
    'fx.arrow_trail':'a short narrow ivory arrow trail', 'fx.cannon_shock':'one broad ochre impact ring with three stone chips',
    'fx.arc_spark':'one short cyan electric fork', 'fx.shield_ring':'one clean blue shield edge ring',
    'fx.mark_stamp':'one readable blue aiming ring with four ticks', 'fx.chrono_ripple':'two restrained cyan concentric ripple rings',
}
for key,subject in subjects.items():
    prompt = icon_template.replace('[SUBJECT]',subject)
    if key.startswith('fx.'):
        prompt = f'An isolated game VFX particle texture: {subject}. Effect only, painted in a warm hand-drawn historical cartoon style. Center the small burst or ring on a truly transparent canvas. Clean soft alpha edges, simple ochre or cyan luminous shapes, readable when displayed at 40 pixels. Absolutely no people, faces, soldiers, weapons, guns, arrows as objects, cannons, hammers, pots, helmets, badges, scrolls, maps, scenery, icon frame, letters, digits, or checkerboard. The entire image consists solely of the described transient particles, light or smoke.'
    (OUTPUT / (key.replace('.','-')+'.txt')).write_text(prompt,encoding='utf-8')
print(json.dumps({'promptsPrepared': len(list(OUTPUT.glob('*.txt'))), 'source': 'docs/epoch-rush/prompts'}, ensure_ascii=False))
