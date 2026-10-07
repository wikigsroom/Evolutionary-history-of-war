import { catalog, rules } from '../content/catalog';
import { fire } from './combat';
import { clamp, position, ticks, value, worldX, type Action, type Entity, type Hit, type ScheduledSkill, type Side, type Status } from './types';
import type { Battle } from './battle';
import { fighterProfile } from './fighter-profiles';
import { spaceFree } from './occupancy';

const other = (side: Side) => (1-side) as Side;
export function castSkill(battle: Battle, action: Extract<Action,{ type: 'cast' }>): { ok: boolean; reason?: string } {
  const skill = catalog.skills[action.skillId], player = battle.state.sides[action.side], hero = battle.hero(action.side);
  const fail = (reason: string) => ({ ok: false, reason });
  if (!skill || !hero) return fail('英雄正在重建');
  if (hero.garrisoned) return fail('指挥官正在基地休整');
  if (skill.heroId && skill.heroId !== hero.contentId || skill.category === 'common' && !player.loadout.commonSkillIds.includes(skill.id)) return fail('技能未装配');
  if ((player.cooldowns[skill.id] ?? 0) > battle.state.tick) return fail('技能冷却中');
  const cost = battle.skillCost(action.side,skill.id)*1000;
  if (player.command < cost) return fail('指挥能量不足');
  const modifiers = battle.modifiers(action.side), spec = battle.specification(action.side);
  const range = battle.skillRange(action.side,skill.id);
  const isSelf = skill.targetMode === 'self' || skill.targetMode === 'direction_self';
  const x = isSelf ? worldX(hero) : action.x;
  if (!Number.isFinite(x) || x < 80 || x > 1520 || Math.abs(x-worldX(hero)) > range) return fail('目标超出施法范围');
  let target: Entity | undefined;
  if (skill.targetMode === 'enemy_entity') {
    target = battle.living(other(action.side)).find(entity => entity.id === action.targetId);
    if (!target) return fail('目标已消失');
    if (Math.abs(worldX(target)-worldX(hero)) > range) return fail('目标超出施法范围');
    if (target.kind === 'base' && !skill.canDamageBase) return fail('该技能不能对基地使用');
  }
  if (skill.id === 'HS04') {
    if (battle.population(action.side) >= battle.populationCap()) return fail('人口已满');
    if (battle.living(action.side).some(entity => entity.kind === 'summon')) return fail('同一时间只能部署一座临时炮台');
    const front = battle.living(action.side).filter(entity => entity.kind !== 'base').map(worldX);
    if (action.side === 0 ? x > Math.max(...front)+100 : x < Math.min(...front)-100) return fail('部署点需要处于己方战线内');
    if (!spaceFree(battle.state, position(x), fighterProfile('summon-H04').radius)) return fail('部署位置被单位占用');
  }
  player.command -= cost;
  const cooldown = (skill.cooldownSec + (skill.category === 'signature' ? value(spec,'signatureCooldownAddSec') : 0)) * (1-clamp(skill.category === 'signature' ? value(modifiers,'signatureCooldownReduction') : 0,0,rules.caps.cooldownReduction));
  player.cooldowns[skill.id] = battle.state.tick+ticks(cooldown);
  const id = battle.id();
  battle.state.castTargets[id] = { until: battle.state.tick+ticks(10), ids: [] };
  battle.event('cast',x,action.side,{ targetId: hero.id, skillId: skill.id });
  if (skill.id === 'HS01') {
    const direction = action.side === 0 ? 1 : -1;
    hero.charge = { until: battle.state.tick+ticks(value(skill.effects,'chargeSec')),
      destination: clamp(hero.x+direction*position(value(skill.effects,'chargeDistance')+value(spec,'chargeRangeAdd')),position(120),position(1480)),
      hitIds: [], skillId: skill.id, distance: value(skill.effects,'chargeDistance'), castId: id,
      raw: skill.damageBase*catalog.eras[player.eraId].hpAttackMultiplier*(1+clamp(value(modifiers,'skillPowerBonus')+value(spec,'signatureDamageBonus'),-.9,rules.caps.skillPowerBonus)),
      knockback: value(skill.effects,'knockbackDistance')*value(spec,'knockbackMultiplier',1) };
    hero.releaseAt = 0;
    if (value(spec,'allyAttackBonus')) for (const ally of battle.living(action.side)) if (ally.kind !== 'base' && Math.abs(ally.x-hero.x) <= position(160)) ally.attackBuff = { until: battle.state.tick+ticks(value(spec,'durationSec')), bonus: value(spec,'allyAttackBonus') };
  } else if (skill.id === 'HS04') {
    const summon = skill.effects.summon as Record<string,number | string>;
    const era = catalog.eras[player.eraId];
    const hp = Math.floor(Number(summon.hpBase)*era.hpAttackMultiplier*(1+value(spec,'summonHpBonus')));
    const entity: Entity = {
      ...structuredClone(hero), id: battle.id(), contentId: 'summon-H04', kind: 'summon', x: position(x), previousX: position(x), hp, maxHp: hp, radius: fighterProfile('summon-H04').radius,
      attack: Number(summon.attackBase)*era.hpAttackMultiplier*(1+value(spec,'summonAttackBonus')), armor: Number(summon.armor), range: Number(summon.range),
      baseAttack: Number(summon.attackBase)*era.hpAttackMultiplier, attackBonus: value(spec,'summonAttackBonus'),
      period: ticks(Number(summon.attackPeriodSec)*(1+value(spec,'summonAttackPeriodBonus'))), windup: ticks(.2), speed: 0, moveRemainder: 0,
      weaponId: String(summon.weaponId), damageType: 'physical', statuses: [], shields: [], targetId: null, releaseAt: 0, nextAttack: battle.state.tick,
      phase: 'idle', bornTick: battle.state.tick, rushFirstHit: false, rushUntil: 0, charge: undefined, yielding: false,
      expiresAt: battle.state.tick+ticks(Number(summon.durationSec)+value(spec,'summonDurationAddSec')),
    };
    battle.state.entities.push(entity); battle.event('spawn',x,action.side,{ targetId: entity.id });
  } else {
    const scheduled: ScheduledSkill = { id, side: action.side, sourceId: hero.id, sourceSnapshot: structuredClone(hero), skillId: skill.id, x: target ? worldX(target) : x, targetId: target?.id,
      due: battle.state.tick+1, remaining: value(skill.effects,'burstCount',value(skill.effects,'shotCount',skill.id === 'HS05' ? 6 : 1)),
      spacing: ticks(value(skill.effects,'burstSpacingSec',value(skill.effects,'shotSpacingSec',skill.id === 'HS05' ? 1 : 0))),
      eraMultiplier: catalog.eras[player.eraId].hpAttackMultiplier, visited: [] };
    if (skill.id === 'HS05') scheduled.due = battle.state.tick+30;
    if (skill.id === 'S05') scheduled.due = battle.state.tick+ticks(.5+(action.side === 1 && battle.state.config.missionId === 'M09' ? .4 : 0));
    battle.state.scheduledSkills.push(scheduled);
  }
  return { ok: true };
}

export function updateSkills(battle: Battle) {
  for (const cast of battle.state.scheduledSkills) {
    if(cast.skillId==='S08' && cast.fieldUntil && cast.fieldUntil>battle.state.tick && cast.remaining===0){
      const skill=catalog.skills.S08,ledger=battle.state.castTargets[cast.id];
      const arrivals=battle.living(other(cast.side)).filter(entity=>entity.kind!=='base' && !cast.visited.includes(entity.id) && Math.abs(worldX(entity)-cast.x)<=skill.radius+entity.radius).sort((a,b)=>Math.abs(worldX(a)-cast.x)-Math.abs(worldX(b)-cast.x) || a.id-b.id);
      for(const target of arrivals){
        if(!ledger || ledger.ids.length>=rules.caps.damageCastTargetsIncludingChains)break;
        ledger.ids.push(target.id);cast.visited.push(target.id);
        battle.status(target,{id:'ST06',until:cast.fieldUntil,magnitude:cast.fieldDamage!,nextTick:battle.state.tick+30,eraMultiplier:cast.eraMultiplier,sourceSide:cast.side,sourceId:cast.sourceId});
        battle.state.sides[cast.side].comboHits++;battle.event('burn',worldX(target),cast.side,{targetId:target.id,skillId:skill.id});
      }
    }
    if (cast.due > battle.state.tick || cast.remaining <= 0) continue;
    const skill = catalog.skills[cast.skillId], effects = skill.effects, spec = battle.specification(cast.side), modifiers = battle.modifiers(cast.side);
    const hero = cast.sourceSnapshot;
    if(skill.id==='S08'){cast.fieldUntil=battle.state.tick+ticks(value(effects,'durationSec')+value(modifiers,'burnDurationAddSec'));cast.fieldDamage=value(effects,'dotDamageBasePerSec')*(1+clamp(value(modifiers,'skillPowerBonus'),-.9,rules.caps.skillPowerBonus));}
    let targets = battle.living(skill.targetMode.startsWith('ally') || skill.targetMode === 'self' ? cast.side : other(cast.side))
      .filter(entity => entity.kind !== 'base' || skill.canDamageBase)
      .filter(entity => Math.abs(worldX(entity)-cast.x) <= skill.radius+entity.radius)
      .sort((a,b) => Math.abs(worldX(a)-cast.x)-Math.abs(worldX(b)-cast.x) || a.id-b.id).slice(0,skill.maxTargets);
    if (skill.targetMode === 'enemy_entity') targets = battle.living(other(cast.side)).filter(entity => entity.id === cast.targetId).slice(0,1);
    if (skill.id === 'S07') {
      const enemies = battle.living(other(cast.side)).filter(entity => entity.kind !== 'base' || skill.canDamageBase);
      targets = [];
      let origin = position(cast.x);
      for (let index = 0; index < skill.maxTargets; index++) {
        const next = enemies.filter(entity => !targets.includes(entity) && Math.abs(entity.x-origin) <= position(index === 0 ? 80 : 150)).sort((a,b) => Math.abs(a.x-origin)-Math.abs(b.x-origin) || a.id-b.id)[0];
        if (!next) break;
        targets.push(next); origin = next.x;
      }
    }
    if (skill.id === 'HS03' && spec.shieldPriority === 'lowest_health_3') targets = [hero,...targets.filter(entity => entity.kind === 'unit').sort((a,b) => a.hp/a.maxHp-b.hp/b.maxHp || a.id-b.id).slice(0,3)].map(entity => battle.state.entities.find(item => item.id === entity.id)!).filter(entity => entity?.hp > 0);
    if (skill.id === 'HS06') {
      battle.state.sides[cast.side].gold += value(spec,'signatureGold',value(effects,'goldFlat'))*1000;
      battle.advanceQueue(cast.side,skill.id,value(spec,'queueProgressRatio',value(effects,'queueRemainingReduction')));
    }
    if (skill.id === 'S12') battle.advanceQueue(cast.side,skill.id,value(effects,'queueRemainingReduction'));
    for (const [index,target] of targets.entries()) {
      if (target.hp <= 0 && skill.id !== 'HS02' && skill.id !== 'S04') continue;
      const status = (id: string, magnitude: number, duration: number): Status => ({ id, magnitude, until: battle.state.tick+ticks(duration), sourceId: cast.sourceId, sourceSide: cast.side });
      if (skill.id === 'S01' || skill.id === 'HS03') {
        const ratio = value(effects,'shieldHpRatio')+value(modifiers,'shieldHpRatioAdd')+(skill.id === 'HS03' ? value(spec,'shieldHpRatioAdd') : 0);
        const multiplier = skill.id === 'HS03' && target.id === cast.sourceId ? value(spec,'selfShieldMultiplier',1) : 1;
        battle.shield(target,ratio*multiplier,value(effects,'durationSec')+value(modifiers,'shieldDurationAddSec')); continue;
      }
      if (skill.id === 'S02') { battle.status(target,status('ST08',value(effects,'attackSpeedBonus'),value(effects,'durationSec'))); continue; }
      if (skill.id === 'S10') { const mark = status('ST04',value(effects,'conditionalDamageBonus')+value(modifiers,'markConditionalBonus'),value(effects,'durationSec')+value(spec,'markDurationAddSec')); mark.charges = value(effects,'markCharges'); battle.status(target,mark); continue; }
      if (skill.id === 'S11') { battle.status(target,status('ST10',value(effects,'projectileReduction'),value(effects,'durationSec'))); continue; }
      if (skill.id === 'S12') { target.moveBuff = { until: battle.state.tick+ticks(value(effects,'durationSec')), bonus: value(effects,'moveBonus') }; continue; }
      if (skill.id === 'HS06') { const healing = Math.min(target.maxHp-target.hp,Math.floor(target.maxHp*value(spec,'healHpRatio',value(effects,'healHpRatio')))); target.hp += healing; battle.event('heal',worldX(target),cast.side,{ targetId: target.id, amount: healing }); continue; }
      let raw = skill.damageBase*cast.eraMultiplier*(1+clamp(value(modifiers,'skillPowerBonus')+(skill.category === 'signature' ? value(spec,'signatureDamageBonus') : 0),-.9,rules.caps.skillPowerBonus));
      if (skill.id === 'S07') raw *= Number((effects.mainChainDamageFactors as number[])[index]);
      const statuses: Status[] = [];
      if (skill.id === 'S04') statuses.push(status('ST01',value(effects,'armorBreakMagnitude'),value(effects,'durationSec')));
      if (skill.id === 'S06') { statuses.push(status('ST03',value(effects,'slowMagnitude'),value(effects,'slowDurationSec')),status('ST05',.4,value(effects,'conductiveDurationSec'))); }
      if (skill.id === 'S08') { const burn = status('ST06',value(effects,'dotDamageBasePerSec')*(1+clamp(value(modifiers,'skillPowerBonus'),-.9,rules.caps.skillPowerBonus)),value(effects,'durationSec')+value(modifiers,'burnDurationAddSec')); burn.nextTick = battle.state.tick+30; burn.eraMultiplier = cast.eraMultiplier; statuses.push(burn);cast.visited.push(target.id); }
      if (skill.id === 'S09') statuses.push(status('ST09',.1,value(effects,'staggerSec')));
      if (skill.id === 'HS05') { statuses.push(status('ST03',value(spec,'signatureSlowMagnitude',value(effects,'slowMagnitude')),value(effects,'slowRefreshDurationSec'))); if (spec.signatureAddsConductive) statuses.push(status('ST05',.4,6)); }
      const hit: Hit = { sourceId: cast.sourceId, side: cast.side, targetId: target.id, raw, damageType: skill.damageType,
        projectile: ['S03','S04','S05','HS02'].includes(skill.id), skillId: skill.id, castId: cast.id, statuses, conductive: true,
        displacement: skill.id === 'S09' ? { center: cast.x, distance: value(effects,'maxDistance') } : undefined };
      if (skill.id === 'S04' || skill.id === 'HS02') {
        fire(battle,hero,target,hit,skill.id === 'S04' ? 'W04' : 'W03',0,1,false,skill.id === 'HS02' ? value(spec,'pierceTargets',1) : 1);
      } else battle.state.pendingHits.push(hit);
    }
    if (skill.id === 'HS05' && targets.length >= 2 && !cast.refunded && value(spec,'refundCommandOnTwoHits')) { battle.state.sides[cast.side].command = Math.min(battle.commandMax(cast.side),battle.state.sides[cast.side].command+value(spec,'refundCommandOnTwoHits')*1000); cast.refunded = true; }
    battle.event(skill.damageType === 'energy' ? 'arc' : 'skillImpact',cast.x,cast.side,{ skillId: skill.id, fromX: worldX(hero) });
    cast.remaining--; cast.due += cast.spacing;
  }
  battle.state.scheduledSkills = battle.state.scheduledSkills.filter(cast => cast.remaining > 0 || (cast.fieldUntil ?? 0)>battle.state.tick);
}
