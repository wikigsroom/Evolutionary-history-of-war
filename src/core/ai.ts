import { catalog, rules, units } from '../content/catalog';
import { position, ticks, value, worldX, type Side } from './types';
import type { Battle } from './battle';
import { ageSpecials } from './age-specials';
import { researchLevel } from './research';
import {reinforcementWindow} from './campaign-waves';

export function decide(battle: Battle, side: Side) {
  if (battle.state.config.mode === 'trial') return;
  const difficulty = rules.difficulty.find(item => item.id === battle.state.config.difficultyId) ?? rules.difficulty[1];
  if (battle.state.tick % ticks(difficulty.decisionSec) !== 0) return;
  const player = battle.state.sides[side], profile = catalog.enemies[battle.state.config.enemyProfileId];
  const hero = battle.hero(side), enemy = (1-side) as Side;
  const available = units.filter(unit => unit.eraId === player.eraId);
  const foes = battle.living(enemy).filter(entity => entity.kind !== 'base');
  const friends = battle.living(side).filter(entity => entity.kind === 'unit');
  const mistake = battle.random(10000) < Math.round(difficulty.mistakeProbability*10000);
  if (hero) {
    const ratio = hero.hp/hero.maxHp;
    const withdrawing = ratio < .25 || hero.garrisoned && ratio < .8 || player.stance === 'retreat' && ratio < .75;
    battle.act({ type: 'stance', side, stance: withdrawing ? 'retreat' : friends.length > 3 ? 'rush' : 'cover' });
    const signature = catalog.heroes[hero.contentId].signatureSkillId;
    for (const skillId of [...player.loadout.commonSkillIds,signature]) {
      if (hero.garrisoned) break;
      const skill = catalog.skills[skillId];
      if(skill.targetMode==='direction_self'){
        if(!mistake && foes.some(e=>(e.x-hero.x)*(side===0 ? 1 : -1)>=0 && Math.abs(e.x-hero.x)<=position(value(skill.effects,'chargeDistance')+value(battle.specification(side),'chargeRangeAdd'))))battle.act({type:'cast',side,skillId,x:worldX(hero)});
        continue;
      }
      const friendSkill = skill.targetMode.startsWith('ally') || skill.targetMode === 'self';
      const candidates = friendSkill ? [hero,...friends].sort((a,b) => a.hp/a.maxHp-b.hp/b.maxHp) : [...foes].sort((a,b) => Math.abs(a.x-hero.x)-Math.abs(b.x-hero.x) || a.id-b.id);
      const target = candidates.find(entity => Math.abs(entity.x-hero.x) <= position(battle.skillRange(side,skillId)));
      if (target && !mistake && (friendSkill ? friends.length >= 2 || hero.hp/hero.maxHp < .5 : foes.some(entity => Math.abs(entity.x-hero.x) <= position(battle.skillRange(side,skillId))))) {
        if (skillId === 'HS04') battle.act({ type: 'cast', side, skillId, x: worldX(hero)+(side === 0 ? 80 : -80) });
        else battle.act({ type: 'cast', side, skillId, x: worldX(target), targetId: target.id });
      }
    }
  }
  const era = catalog.eras[player.eraId];
  if (era.nextEvolutionKnowledge !== null && player.eraId !== battle.maxEraId && player.knowledge >= era.nextEvolutionKnowledge*1000) battle.act({ type: 'evolve', side });
  const special = ageSpecials[player.eraId as keyof typeof ageSpecials];
  const threatened = foes.filter(foe => Math.abs(foe.x-battle.base(side).x)<position(420));
  const emergency=battle.base(side).hp/battle.base(side).maxHp<.35 || battle.state.config.difficultyId==='D03';
  if (!mistake && emergency && threatened.length >= 3 && player.knowledge >= special.cost*1000 && (player.eraId === battle.maxEraId || threatened.length >= friends.length+2)) {
    const center = threatened.reduce((sum, foe) => sum+worldX(foe),0)/threatened.length;
    battle.act({ type: 'ageSpecial', side, x: center });
  }
  if (friends.length >= 3 && player.queue.length < 2 && player.gold >= battle.unitCost(side,`U${player.eraId[1]}1`)*3000) {
    if (!battle.heavyUnlocked(side)) battle.act({ type: 'research', side, researchId: 'heavy-unlock' });
    else {
      const upgrades = ['front-armor','ranged-attack','anti-attack','front-attack','ranged-range'];
      const id = upgrades.find(id => researchLevel(player,id) < (id === 'front-armor' || id === 'ranged-range' ? 3 : 2));
      if (id) battle.act({ type: 'research',side,researchId:id });
    }
  }
  if (profile.id === 'AP03' && friends.length > 0 && !player.turrets.length) battle.act({ type: 'turret',side,turretId: `TR${player.eraId[1]}1`,slot: 0 });
  if(side===1 && reinforcementWindow(battle.state)?.deploying===false)return;
  if (player.queue.length >= 2 || battle.population(side) >= battle.populationCap()) return;
  const currentAvailable = units.filter(unit => unit.eraId === player.eraId && (!unit.heavy || battle.heavyUnlocked(side)));
  let chosen = currentAvailable[0];
  if (!friends.some(entity => entity.role === 'front') && !mistake) chosen = currentAvailable.find(unit => unit.role === 'front')!;
  else if (foes.filter(entity => entity.heavy).length >= 2 && !mistake) chosen = currentAvailable.find(unit => unit.role === 'anti_armor')!;
  else {
    let roll = battle.random(10000);
    for (const unit of currentAvailable) { roll -= Math.round((profile.roleWeights[unit.role] ?? .25)*10000); if (roll < 0) { chosen = unit; break; } }
  }
  if (player.gold >= battle.unitCost(side,chosen.id)*1000) battle.act({ type: 'train',side,unitId: chosen.id });
}
