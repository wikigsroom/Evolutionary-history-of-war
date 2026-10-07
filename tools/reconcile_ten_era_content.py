"""Reconcile ten-era equipment, economy and campaign metadata without touching live art."""
import json, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'godot/assets/data'

def load(name):
    return json.loads((DATA / (name + '.json')).read_text(encoding='utf-8'))

def save(name, value):
    (DATA / (name + '.json')).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

units = load('units')
for row in units:
    era = int(row['eraId'][1:]); slot = int(row['id'][-1])
    if slot == 3 and era in [1, 2, 4]: row['weaponId'] = 'W06'
    if era == 3 and slot == 3: row.update(weaponId='W03', animationFamily='bow', range=170)
    if era in [7, 8] and slot == 3: row.update(weaponId='W05', animationFamily='gun')
    if era == 10:
        row.update(weaponId=['W02', 'W07', 'W06', 'W07', 'W07'][slot-1], animationFamily=['shield', 'gun', 'spear', 'mech', 'mech'][slot-1], range=[42, 240, 90, 255, 200][slot-1])
save('units', units)
missions = load('missions')
for row in missions:
    row['playerStartingGold'] = row['enemyStartingGold'] = round(240 * 1.28 ** (int(row['startingEraId'][1:])-1))
    row['chapter']=int(row['startingEraId'][1:])
    row['reinforcements']['waves']=40
save('missions', missions)
heroes = load('heroes')
unlocks = {hero_id:row['id'] for row in missions for hero_id in row['heroUnlockIds']}
for row in heroes: row['unlockMissionId'] = unlocks.get(row['id'])
save('heroes', heroes)
forms = load('hero-evolutions')
for row in forms:
    age = int(row['eraId'][1:])
    if row['heroId'] == 'H03' and age >= 8:
        row.update(weaponId='W07' if age == 10 else 'W04', range=185.0,
                   damageType='energy' if age == 10 else 'physical')
        row['skillVariant']['projectileWeapon'] = row['weaponId']
    if row['heroId'] == 'H01' and age == 10:
        row.update(weaponId='W02', range=52.0)
        row['skillVariant']['projectileWeapon'] = 'W02'
save('hero-evolutions', forms)
upgrades=load('run-upgrades')
for row in upgrades:row['choiceGroup']='evolution_'+row['eraId']
save('run-upgrades',upgrades)
loot = load('loot')
loot.pop('bossMissionIds', None)
loot['chapterBossMissionIds'] = [row['id'] for row in missions if row['boss']]
loot['missionFirstClearFragments'] = {row['id']:4 if row['boss'] else 2 for row in missions if int(row['id'][1:]) >= 13}
loot['battleKillKnowledge'] = 'round(units.killKnowledge * era.knowledgeMultiplier); defender receives 65%'
save('loot', loot)
docs = ROOT / 'docs/epoch-rush/data-v0.7'
docs.mkdir(parents=True, exist_ok=True)
for path in DATA.glob('*.json'):
    if path.name != 'animations.json': shutil.copy2(path, docs / path.name)
print('Reconciled equipment, 20 mission economies and commander unlock descriptions.')
