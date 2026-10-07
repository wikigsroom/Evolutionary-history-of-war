"""Apply the reviewed five-era rule changes to the live content, preserving IDs."""
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'docs/epoch-rush/data'
def load(name): return json.loads((DATA / (name + '.json')).read_text(encoding='utf-8'))
def save(name, value): (DATA / (name + '.json')).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
rules = load('rules')
rules['designVersion'] = '0.3.0'
rules['status'] = 'implemented_v03_rebuild'
rules['world']['maxMeleeContacts'] = 1
rules['resources'].update(startingGold=240, goldPerSec=2.5, knowledgePerSec=0)
rules['resources']['experienceFromOwnLossRatio'] = .65
rules['resources']['experienceFromCombatOnly'] = True
rules['evolutionRush']['eligibleSec'] = 30
rules['damage']['roleCounterBonus'] = 1.3
rules['damage']['heavyBaseDamageMultiplier'] = 2.6
save('rules', rules)
eras = load('eras')
for era, power, price, income, xp, hp in zip(eras, [1,1.6,2.55,4.05,6.4], [1,1.4,1.95,2.7,3.75], [1,1.25,1.6,2.1,2.8], [85,150,250,390,None], [1920,2560,3360,4400,5760]):
 era.update(hpAttackMultiplier=power, costMultiplier=price, incomeMultiplier=income, nextEvolutionKnowledge=xp,baseHp=hp)
save('eras', eras)
units = load('units')
for unit in units:
 unit['bountyGold'] = round(unit['costBase'] * .85)
 if unit['role'] == 'signature': unit['role'] = 'heavy'
 # Weapon anticipation is part of the simulation, and later drives the release frame.
 unit['windupSec'] = {'W01':.36,'W02':.32,'W03':.42,'W04':.24,'W05':.52,'W06':.38,'W07':.38,'W08':.3}[unit['weaponId']]
 if unit['id'] in ['U13','U23','U33','U53']: unit['range'] = {'U13':90,'U23':104,'U33':110,'U53':132}[unit['id']]
 if unit['id'] == 'U14':
  unit.update(name='獠牙兽骑', hpBase=245, attackBase=30, armor=12, range=52, moveSpeed=54, attackPeriodSec=1.8, windupSec=.38, heavy=True, weaponId='W06', damageType='physical', visual='重型獠牙兽骑', special={'firstContactBonus':.2,'minRunDistance':100})
save('units', units)
enemies = load('enemy-profiles')
for enemy in enemies:
 weights = enemy['roleWeights']
 if 'signature' in weights: weights['heavy'] = weights.pop('signature')
save('enemy-profiles', enemies)
missions = load('missions')
missions[0].update(maximumEraId='A2', teaching='先用盾兵挡住战线、投石兵在后方输出；通过交战积累经验，完成第一次青铜时代进化。', playerStartingGold=260, enemyStartingGold=240)
for mission in missions:
 chapter=mission['chapter']
 mission['reinforcements']={'waves':min(6,chapter+3)+(1 if mission['boss'] else 0),'periodSec':52+chapter*4,'deploySec':26+chapter*3}
save('missions', missions)
package = json.loads((ROOT / 'package.json').read_text(encoding='utf-8'))
package['version'] = '0.3.0'
(ROOT / 'package.json').write_text(json.dumps(package, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
lock = json.loads((ROOT / 'package-lock.json').read_text(encoding='utf-8'))
lock['version'] = '0.3.0'; lock['packages']['']['version'] = '0.3.0'
(ROOT / 'package-lock.json').write_text(json.dumps(lock, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Updated live content to v0.3.0; stable content IDs retained.')
