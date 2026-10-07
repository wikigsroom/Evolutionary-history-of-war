import { catalog, rules } from '../content/catalog';
import { clamp, position, ticks, value, worldX, type Entity, type Hit, type Side, type Status } from './types';
import type { Battle } from './battle';
import { fighterProfile } from './fighter-profiles';
import { BODY_GAP, constrainedGoal, displace, grounded, legalContact, nearestSpace, settleExceptionalMove, spaceFree, spawnX } from './occupancy';
import { researchLevel } from './research';

const magnitude = (entity: Entity, id: string) => Math.max(0,...entity.statuses.filter(item => item.id === id).map(item => item.magnitude));
const distance = (left: Entity, right: Entity) => Math.abs(left.x-right.x)/100-left.radius-right.radius;
const opponent = (side: Side) => (1-side) as Side;
export function nearestEnemy(battle: Battle, entity: Entity): Entity | undefined {
  const direction = entity.side === 0 ? 1 : -1;
  return battle.living(opponent(entity.side)).filter(enemy => (enemy.x-entity.x)*direction >= -position(entity.radius+enemy.radius))
    .sort((a,b) => Math.abs(a.x-entity.x)-Math.abs(b.x-entity.x) || a.id-b.id)[0];
}

export function updateStatuses(battle: Battle) {
  const now = battle.state.tick;
  for (const entity of battle.living()) {
    for (const status of entity.statuses) if (status.id === 'ST06' && status.nextTick !== undefined && status.nextTick <= now && status.until >= now) {
      battle.state.pendingHits.push({ sourceId: status.sourceId, side: status.sourceSide, targetId: entity.id, raw: status.magnitude*(status.eraMultiplier ?? 1), damageType: 'blast', projectile: false, conductive: false });
      status.nextTick += 30;
    }
    entity.statuses = entity.statuses.filter(status => status.until > now);
    entity.shields = entity.shields.filter(shield => shield.until > now && shield.hp > 0);
    if (entity.expiresAt !== undefined && now >= entity.expiresAt) battle.kill(entity,true);
  }
  for (const drummer of battle.living()) {
    const aura = catalog.units[drummer.contentId]?.special;
    if (!aura) continue;
    const radius=value(aura,'auraRadius',value(aura,'radius',0));
    if (value(aura,'auraAttackSpeedBonus')>0) for (const ally of battle.living(drummer.side)) if (ally.kind !== 'base' && Math.abs(ally.x-drummer.x) <= position(radius)) battle.status(ally,{ id: 'ST08', until: now+30, magnitude: value(aura,'auraAttackSpeedBonus'), sourceId: drummer.id, sourceSide: drummer.side });
    if (value(aura,'auraHealPerTick')>0) for (const ally of battle.living(drummer.side)) if (ally.kind !== 'base' && ally.hp < ally.maxHp && Math.abs(ally.x-drummer.x) <= position(radius)) {
      const healing=Math.min(ally.maxHp-ally.hp,Math.max(1,Math.floor(value(aura,'auraHealPerTick'))));
      ally.hp+=healing;
      if (now%15===0) battle.event('heal',worldX(ally),drummer.side,{targetId:ally.id,amount:healing,sourceId:drummer.id});
    }
    if (value(aura,'auraShieldRatio')>0 && now%60===0) for (const ally of battle.living(drummer.side)) if (ally.kind !== 'base' && Math.abs(ally.x-drummer.x) <= position(radius)) battle.shield(ally,value(aura,'auraShieldRatio'),3);
  }
}

function move(battle: Battle, entity: Entity, goal: number, multiplier = 1) {
  goal = constrainedGoal(battle.state, entity, goal);
  const bonuses = (entity.rushArmed || entity.rushUntil > battle.state.tick ? rules.evolutionRush.moveBonus : 0) + (entity.moveBuff && entity.moveBuff.until > battle.state.tick ? entity.moveBuff.bonus : 0);
  const speed = entity.speed*(1+clamp(bonuses,-.9,rules.caps.moveSpeedBonus))*(1-magnitude(entity,'ST03'))*multiplier;
  entity.moveRemainder += Math.round(speed*100);
  const amount = Math.floor(entity.moveRemainder/30); entity.moveRemainder %= 30;
  const previous = entity.x;
  entity.x += clamp(goal-entity.x,-amount,amount);
  entity.runDistance += Math.abs(entity.x-previous)/100;
  entity.phase = entity.x !== previous ? 'move' : 'idle';
}

export function fire(battle: Battle, source: Entity, target: Entity, hit: Hit, weaponId = source.weaponId, splash = 0, maxTargets = 1, suppress = false, pierceTargets = 1) {
  const weapon = catalog.weapons[weaponId];
  if (!weapon.projectileSpeed) {
    battle.state.pendingHits.push(hit);
    battle.event('release',worldX(target),source.side,{ fromX: worldX(source),targetId:target.id,sourceId:hit.sourceId,weaponId,skillId:hit.skillId });
    return;
  }
  const direction = source.side === 0 ? 1 : -1;
  const socket = source.kind === 'base' ? 38 : fighterProfile(source.contentId).muzzle[0];
  const muzzle = source.x + direction * position(Math.min(socket, Math.max(0, Math.abs(target.x-source.x)/100 - target.radius - 1)));
  battle.state.projectiles.push({ id: battle.id(), sourceId: hit.sourceId, side: source.side, x: muzzle, previousX: muzzle, targetId: target.id,
    speed: weapon.projectileSpeed, moveRemainder: 0, expiresAt: battle.state.tick+ticks(4), hit, splash, maxTargets, weaponId, suppress, direction: target.x >= source.x ? 1 : -1, pierceRemaining: pierceTargets, hitIds: [] });
  battle.event('release',worldX(source),source.side,{ fromX:worldX(source),targetId:target.id,sourceId:hit.sourceId,weaponId,skillId:hit.skillId });
}

function normalAttack(battle: Battle, entity: Entity, target: Entity) {
  const special = catalog.units[entity.contentId]?.special ?? {};
  const hit: Hit = { sourceId: entity.id, side: entity.side, targetId: target.id,
    raw: entity.baseAttack * (1+clamp(entity.attackBonus+(entity.attackBuff && entity.attackBuff.until > battle.state.tick ? entity.attackBuff.bonus : 0),-.9,rules.caps.attackBonus)),
    damageType: entity.damageType, projectile: catalog.weapons[entity.weaponId].projectileSpeed > 0,
    conditional: 0, conductive: true, castId: battle.id(),attackerRole:entity.role,attackerHeavy:entity.heavy,attackerKind:entity.kind };
  if (entity.runDistance >= value(special,'minRunDistance',Infinity) && special.firstContactBonus) {
    hit.conditional = (hit.conditional ?? 0)+value(special,'firstContactBonus'); entity.runDistance = 0;
  }
  if (entity.rushFirstHit && entity.rushUntil > battle.state.tick) hit.isRush = true;
  if (special.chainTargets) {
    const targets = battle.living(opponent(entity.side)).filter(item => item.kind !== 'base' && Math.abs(item.x-target.x) <= position(160))
      .sort((a,b) => Math.abs(a.x-target.x)-Math.abs(b.x-target.x) || a.id-b.id).slice(0,value(special,'chainTargets'));
    for (const [index,item] of targets.entries()) battle.state.pendingHits.push({ ...hit, targetId: item.id, raw: hit.raw*Math.pow(value(special,'chainFalloff',.6),index), castId: entity.id*100000+battle.state.tick });
    if (!targets.length) battle.state.pendingHits.push(hit);
    battle.event('arc',worldX(target),entity.side,{ fromX: worldX(entity), targetId: target.id,sourceId:entity.id,weaponId:entity.weaponId });
  } else fire(battle,entity,target,hit,entity.weaponId,value(special,'splashRadius'),value(special,'maxTargets',1),Boolean(special.suppressStatusId));
}

export function updateCombat(battle: Battle) {
  const now = battle.state.tick;
  // Withdrawing commanders leave the road. Residency is explicit and saved;
  // they neither occupy the recruitment exit nor fight from inside the base.
  for (const hero of battle.state.entities.filter(entity => entity.kind === 'hero' && entity.hp > 0 && entity.garrisoned)) {
    hero.statuses = hero.statuses.filter(status => status.until > now);
    hero.shields = hero.shields.filter(shield => shield.until > now && shield.hp > 0);
    const remainder = (hero.garrisonHealRemainder ?? 0) + hero.maxHp * 25;
    hero.hp = Math.min(hero.maxHp, hero.hp + Math.floor(remainder / 30000));
    hero.garrisonHealRemainder = remainder % 30000;
    const exit = spawnX(hero.side, hero.contentId);
    if (battle.state.sides[hero.side].stance !== 'retreat' && spaceFree(battle.state, exit, hero.radius, hero.id)) {
      hero.garrisoned = false; hero.x = hero.previousX = exit; hero.yielding = false;
      hero.phase = 'idle'; hero.releaseAt = 0; hero.targetId = null;
      hero.nextAttack = Math.max(hero.nextAttack, now + ticks(.25));
      battle.event('rejoin', worldX(hero), hero.side, { targetId: hero.id });
    }
  }
  // Normalize any stale/imported formation once per tick from the front body
  // backwards. This preserves the front fighter's contact point while moving
  // every rear body to the first legal slot, including the one-pixel rounding
  // margin introduced by measured sprite footprints.
  for (const side of [0,1] as Side[]) {
    const direction = side===0 ? 1 : -1;
    const formation = battle.living(side).filter(entity => entity.kind!=='base' && grounded(entity) && entity.speed>0)
      .sort((a,b)=>direction*(b.x-a.x) || a.bornTick-b.bornTick || a.id-b.id);
    for (let index=1;index<formation.length;index++) {
      const front=formation[index-1],rear=formation[index];
      const required=position(front.radius+rear.radius+BODY_GAP);
      if ((front.x-rear.x)*direction < required) {
        rear.x=front.x-direction*required;rear.previousX=rear.x;rear.moveRemainder=0;
        rear.yielding=false;delete rear.settlementPending;
      }
    }
  }
  // Front bodies move first, so rear bodies can fill newly opened space this tick.
  const actors = battle.living().sort((a, b) => a.side - b.side || (a.side === 0 ? b.x-a.x : a.x-b.x) || a.bornTick-b.bornTick || a.id-b.id);
  for (const entity of actors) {
    if (entity.kind === 'base') continue;
    const player = battle.state.sides[entity.side], direction = entity.side === 0 ? 1 : -1;
    if (entity.kind === 'hero' && player.stance === 'retreat' && !entity.charge && !entity.statuses.some(status => status.id === 'ST09')) {
      entity.releaseAt = 0; entity.targetId = null; entity.yielding = true;
      delete entity.settlementPending;
      const entry = spawnX(entity.side, entity.contentId);
      move(battle, entity, entry);
      if (entity.x === entry) {
        entity.garrisoned = true; entity.x = entity.previousX = battle.base(entity.side).x;
        entity.yielding = false; entity.phase = 'idle'; entity.garrisonHealRemainder = 0;
        battle.event('garrison', worldX(entity), entity.side, { targetId: entity.id });
      }
      continue;
    }
    if(entity.settlementPending){settleExceptionalMove(battle.state,entity);entity.phase='recover';if(entity.settlementPending)continue;}
    if (entity.charge) {
      const charge = entity.charge, previous = entity.x;
      const duration = Math.max(1,charge.until-now+1);
      entity.x += Math.round((charge.destination-entity.x)/duration); entity.phase = 'charge';
      const skill = catalog.skills[charge.skillId];
      for (const target of battle.living(opponent(entity.side))) {
        if (charge.hitIds.length >= skill.maxTargets || charge.hitIds.includes(target.id)) continue;
        if (target.x+position(target.radius) < Math.min(previous,entity.x) || target.x-position(target.radius) > Math.max(previous,entity.x)+position(entity.radius)) continue;
        charge.hitIds.push(target.id);
        battle.state.pendingHits.push({ sourceId: entity.id, side: entity.side, targetId: target.id, skillId: skill.id, castId: charge.castId,
          raw: charge.raw,
          damageType: skill.damageType, projectile: false,
          displacement: { distance: charge.knockback },
          statuses: [{ id: 'ST09', until: now+ticks(.1), magnitude: .1, sourceId: entity.id, sourceSide: entity.side }], conductive: false });
      }
      if (now >= charge.until) { delete entity.charge; settleExceptionalMove(battle.state, entity); entity.phase = 'recover'; entity.nextAttack = now+ticks(.25); }
      continue;
    }
    if (entity.statuses.some(status => status.id === 'ST09')) continue;
    const target = nearestEnemy(battle,entity);
    if(entity.kind==='hero' && player.stance==='cover'){
      const front=battle.living(entity.side).filter(ally=>ally.kind==='unit').sort((a,b)=>direction*(b.x-a.x))[0];
      if(front){
        const desired=front.x-direction*position(entity.radius+front.radius+8);
        if((entity.x-desired)*direction>0){
          const gap=nearestSpace(battle.state,desired,entity.radius,entity.id);
          if(gap!==undefined && (gap-front.x)*direction<0 || !target || distance(entity,target)>entity.range){
            entity.releaseAt=0;entity.targetId=null;entity.yielding=true;
            if(gap!==undefined && (gap-front.x)*direction<0){move(battle,entity,gap);if(entity.x===gap && spaceFree(battle.state,entity.x,entity.radius,entity.id))entity.yielding=false;}
            else entity.phase='idle';
            continue;
          }
          if(entity.yielding)settleExceptionalMove(battle.state,entity);
        }
        if(entity.yielding && spaceFree(battle.state,entity.x,entity.radius,entity.id))entity.yielding=false;
      }
    }
    if (entity.releaseAt > 0) {
      const locked = battle.state.entities.find(item => item.id === entity.targetId && item.hp > 0 && !item.garrisoned);
      if (!locked || distance(entity,locked) > entity.range+8 || !legalContact(battle.state, entity, locked)) { entity.releaseAt = 0; entity.targetId = null; entity.phase = 'idle'; }
      else if (now >= entity.releaseAt) {
        normalAttack(battle,entity,locked); entity.releaseAt = 0; entity.phase = 'recover';
        const speed = clamp((entity.kind === 'unit' ? value(battle.modifiers(entity.side),'unitAttackSpeedBonus') : 0)+magnitude(entity,'ST08')-magnitude(entity,'ST02'),-.8,rules.caps.attackSpeedBonus);
        entity.nextAttack = now+Math.max(1,Math.ceil(entity.period/(1+speed))-entity.windup);
      }
      continue;
    }
    if (!target) { entity.phase = 'idle'; continue; }
    const desiredRange=entity.kind==='hero' && player.stance==='rush' && entity.range>=100 ? entity.range*.65 : entity.range;
    // Support troops close behind the shield line instead of stopping at maximum
    // range and leaving every following archer outside firing distance.
    if(entity.kind==='unit' && entity.range>=100 && !fighterProfile(entity.contentId).overShoulder){
      const formationRange=Math.max(80,entity.range*.55);
      const closeGoal=constrainedGoal(battle.state,entity,target.x-direction*position(formationRange+entity.radius+target.radius-1));
      if((closeGoal-entity.x)*direction>position(1)){move(battle,entity,closeGoal);continue;}
    }
    if (distance(entity,target) <= desiredRange) {
      if (now >= entity.nextAttack && legalContact(battle.state, entity, target) && !entity.yielding) {
        if(entity.rushArmed){entity.rushArmed=false;entity.rushUntil=now+ticks(rules.evolutionRush.buffSec+value(battle.modifiers(entity.side),'rushBuffAddSec'));battle.event('rushContact',worldX(entity),entity.side,{targetId:entity.id});}
        entity.targetId = target.id; entity.attackStartedAt = now; entity.releaseAt = now+Math.max(ticks(.08),entity.windup); entity.phase = 'windup';
      } else entity.phase = now < entity.nextAttack ? 'recover' : 'idle';
      continue;
    }
    if (entity.speed === 0) continue;
    let goal = target.x-direction*position(desiredRange+entity.radius+target.radius-1);
    if (entity.kind === 'hero' && player.stance === 'cover') {
      const soldiers = battle.living(entity.side).filter(item => item.kind === 'unit');
      const front = soldiers.sort((a,b) => direction*(b.x-a.x))[0];
      goal = front ? front.x-direction*position(40) : position(rules.world.basePositions[entity.side]+direction*180);
      if (entity.range >= 100) goal = direction === 1 ? Math.min(goal,target.x-position(entity.range*.8)) : Math.max(goal,target.x+position(entity.range*.8));
      if ((goal-entity.x)*direction < 0) {
        const gap = nearestSpace(battle.state, goal, entity.radius, entity.id);
        if (gap !== undefined) { entity.yielding = true; goal = gap; }
      }
    }
    move(battle,entity,goal);
    if (entity.yielding && spaceFree(battle.state, entity.x, entity.radius, entity.id)) entity.yielding = false;
  }
  for (const side of [0,1] as Side[]) {
    const base = battle.base(side), modifier = battle.modifiers(side);
    for (const instance of battle.state.sides[side].turrets) {
      if (now < instance.nextAttack) continue;
      const turret = catalog.turrets[instance.contentId];
      const target = battle.living(opponent(side)).filter(enemy => enemy.kind !== 'base' && Math.abs(enemy.x-base.x) <= position(turret.range+enemy.radius))
        .sort((a,b) => Math.abs(a.x-base.x)-Math.abs(b.x-base.x) || a.id-b.id)[0];
      if (!target) continue;
      const raw = turret.attackBase*catalog.eras[turret.eraId].hpAttackMultiplier*(1+value(modifier,'turretAttackBonus')+researchLevel(battle.state.sides[side],'tower-attack')*.15);
      fire(battle,base,target,{ sourceId: instance.id, side, targetId: target.id, raw, damageType: turret.damageType, projectile: true },turret.mode === 'siege' ? 'W05' : 'W04',turret.splashRadius,turret.maxTargets);
      instance.nextAttack = now+ticks(turret.attackPeriodSec);
    }
  }
}

export function updateProjectiles(battle: Battle) {
  const remove = new Set<number>();
  for (const projectile of battle.state.projectiles) {
    if (projectile.expiresAt <= battle.state.tick) { remove.add(projectile.id); continue; }
    projectile.previousX = projectile.x; projectile.moveRemainder += projectile.speed*100;
    projectile.x += projectile.direction*Math.floor(projectile.moveRemainder/30); projectile.moveRemainder %= 30;
    const collisions = battle.living(opponent(projectile.side)).filter(entity => !projectile.hitIds.includes(entity.id) && entity.x+position(entity.radius) >= Math.min(projectile.previousX,projectile.x) && entity.x-position(entity.radius) <= Math.max(projectile.previousX,projectile.x))
      .sort((a,b) => Math.abs(a.x-projectile.previousX)-Math.abs(b.x-projectile.previousX) || a.id-b.id);
    for (const collision of collisions) {
      const victims = projectile.splash ? battle.living(opponent(projectile.side)).filter(entity => Math.abs(entity.x-collision.x) <= position(projectile.splash)).sort((a,b) => Math.abs(a.x-collision.x)-Math.abs(b.x-collision.x) || a.id-b.id).slice(0,projectile.maxTargets) : [collision];
      for (const victim of victims) battle.state.pendingHits.push({ ...projectile.hit, targetId: victim.id, statuses: projectile.suppress ? [{ id: 'ST02', until: battle.state.tick+ticks(4), magnitude: .2, sourceSide: projectile.side, sourceId: projectile.sourceId }] : projectile.hit.statuses });
      projectile.hitIds.push(collision.id); projectile.pierceRemaining--;
      if (projectile.pierceRemaining<=0 || projectile.splash || collision.kind==='base') { remove.add(projectile.id); break; }
    }
  }
  battle.state.projectiles = battle.state.projectiles.filter(projectile => !remove.has(projectile.id));
}

export function damageFor(battle: Battle, hit: Hit, target: Entity): number {
  if (hit.raw <= 0) return 0;
  const skill = hit.skillId ? catalog.skills[hit.skillId] : undefined;
  if (target.kind === 'base' && skill && !skill.canDamageBase) return 0;
  const modifiers = battle.modifiers(hit.side), specification = battle.specification(hit.side);
  let conditional = hit.conditional ?? 0;
  if (target.heavy && target.kind !== 'base') conditional += value(modifiers,'heavyConditionalBonus') + (skill?.category === 'signature' ? value(specification,'heavyConditionalBonus') : 0);
  if (skill?.effects.conditionalStatusId && target.statuses.some(status => status.id === skill.effects.conditionalStatusId)) conditional += value(skill.effects,'conditionalDamageBonus');
  const mark = target.kind !== 'base' && hit.projectile && (hit.damageType === 'physical' || hit.damageType === 'pierce') ? target.statuses.find(status => status.id === 'ST04' && (status.charges ?? 0) > 0) : undefined;
  if (mark) { conditional += mark.magnitude; mark.charges!--; }
  const source = battle.state.entities.find(entity => entity.id === hit.sourceId);
  if (hit.isRush && source?.rushFirstHit && source.rushUntil > battle.state.tick) {
    conditional += rules.evolutionRush.firstAttackBonus + value(modifiers,'rushFirstAttackBonus'); source.rushFirstHit = false;
  }
  const armor = Math.max(0,target.armor*(1-magnitude(target,'ST01'))*(hit.damageType === 'pierce' ? 1-rules.damage.pierceArmorIgnore : 1));
  const mitigation = hit.damageType === 'energy' ? 1-target.energyResistance : rules.damage.armorConstant/(rules.damage.armorConstant+armor);
  const category = target.kind === 'base' ? 'base' : target.heavy ? 'heavy' : 'light';
  const counter = rules.damage.counter[hit.damageType][category];
  const roleCounter: Record<string, string> = { front: 'ranged', ranged: 'anti_armor', anti_armor: 'heavy', heavy: 'front' };
  const attackerKind=hit.attackerKind ?? source?.kind,attackerRole=hit.attackerRole ?? source?.role,attackerHeavy=hit.attackerHeavy ?? source?.heavy;
  const roleBonus = !skill && target.kind === 'unit' && attackerKind === 'unit' && roleCounter[attackerRole ?? ''] === target.role ? rules.damage.roleCounterBonus : 1;
  const reduction = clamp(hit.projectile ? magnitude(target,'ST10') : 0,0,rules.caps.receivedDamageReduction);
  const overtime = target.kind === 'base' ? battle.state.tick >= ticks(rules.overtime.secondSec) ? rules.overtime.secondBaseDamageMultiplier : battle.state.tick >= ticks(rules.overtime.firstSec) ? rules.overtime.firstBaseDamageMultiplier : 1 : 1;
  const baseCoefficient = target.kind === 'base' && skill ? rules.damage.baseSkillDamageMultiplier : 1;
  const siege=target.kind==='base' && attackerKind==='unit' && attackerHeavy && !skill ? rules.damage.heavyBaseDamageMultiplier : 1;
  return Math.max(rules.damage.minimumDamage,Math.floor(hit.raw*mitigation*counter*roleBonus*(1+clamp(conditional,0,rules.caps.conditionalDamageBonus))*(1-reduction)*overtime*baseCoefficient*siege));
}

export function applyHits(battle: Battle) {
  const hits = battle.state.pendingHits;
  const alive = new Map(battle.living().map(entity => [entity.id,entity]));
  const losses = new Map<number,number>(), deferred: Hit[] = [];
  const statuses: { entity: Entity; status: Status }[] = [];
  for (const hit of hits) if (hit.castId !== undefined) {
    const group = battle.state.castTargets[hit.castId] ??= { until: battle.state.tick+ticks(10), ids: [] };
    if (!group.ids.includes(hit.targetId) && group.ids.length < rules.caps.damageCastTargetsIncludingChains) group.ids.push(hit.targetId);
  }
  for (let index = 0; index < hits.length; index++) {
    const hit = hits[index], target = alive.get(hit.targetId);
    if (!target || target.side === hit.side) continue;
    const group = hit.castId !== undefined ? battle.state.castTargets[hit.castId] : undefined;
    if (group && !group.ids.includes(target.id)) continue;
    const damage = damageFor(battle,hit,target);
    let remaining = damage, absorbed = 0;
    const shieldBefore = target.shields.reduce((sum,shield) => sum+shield.hp,0);
    target.shields.sort((a,b) => a.until-b.until);
    for (const shield of target.shields) { const used = Math.min(shield.hp,remaining); shield.hp -= used; remaining -= used; absorbed += used; }
    target.shields = target.shields.filter(shield => shield.hp > 0);
    losses.set(target.id,(losses.get(target.id) ?? 0)+remaining);
    const source=alive.get(hit.sourceId);
    battle.event('hit',worldX(target),hit.side,{ targetId: target.id,sourceId:hit.sourceId,weaponId:source?.weaponId,damageType:hit.damageType,amount: remaining, absorbed, skillId: hit.skillId, fromX: worldX(source ?? battle.base(hit.side)) });
    if (hit.skillId === 'S05' && target.statuses.some(status => status.id === 'ST01')) battle.state.sides[hit.side].comboHits++;
    if (target.kind !== 'base') {
      for (const status of hit.statuses ?? []) statuses.push({ entity: target, status });
      if (hit.displacement) {
        const resistance = target.kind === 'hero' ? .5 : target.heavy ? .2 : 1;
        const amount = hit.displacement.distance*resistance*(1-value(battle.modifiers(target.side),'displacementResistance'));
        const direction = hit.displacement.center !== undefined ? Math.sign(position(hit.displacement.center)-target.x) : hit.side === 0 ? 1 : -1;
        displace(battle.state, target, position(amount)*direction);
      }
      const conductive = target.statuses.find(status => status.id === 'ST05');
      if (damage > 0 && hit.damageType === 'energy' && hit.conductive !== false && conductive) {
        target.statuses = target.statuses.filter(status => status.id !== 'ST05');
        const visited = group?.ids ?? [target.id];
        const next = battle.living(opponent(hit.side)).filter(entity => entity.kind !== 'base' && !visited.includes(entity.id) && Math.abs(entity.x-target.x) <= position(150))
          .sort((a,b) => Math.abs(a.x-target.x)-Math.abs(b.x-target.x) || a.id-b.id)[0];
        if (next && visited.length < rules.caps.damageCastTargetsIncludingChains) {
          group?.ids.push(next.id);
          hits.push({ ...hit, targetId: next.id, raw: hit.raw*value(battle.modifiers(hit.side),'conductiveChainRatio',.4), conductive: false, statuses: [], displacement: undefined });
          battle.event('arc',worldX(next),hit.side,{ fromX: worldX(target),targetId: next.id,skillId: hit.skillId });
          battle.state.sides[hit.side].comboHits++;
        }
      }
    }
    if (shieldBefore > 0 && !target.shields.length) {
      battle.event('shieldBreak',worldX(target),target.side,{ targetId: target.id });
      const spec = battle.specification(target.side);
      if (target.kind === 'hero' && value(spec,'shieldBreakDamageBase') && target.counterReadyAt <= battle.state.tick) {
        const enemy = nearestEnemy(battle,target);
        if (enemy && distance(target,enemy) <= target.range+40) deferred.push({ sourceId: target.id, side: target.side, targetId: enemy.id, raw: value(spec,'shieldBreakDamageBase')*catalog.eras[target.eraId].hpAttackMultiplier, damageType: 'physical', projectile: false });
        target.counterReadyAt = battle.state.tick+ticks(value(spec,'internalCooldownSec'));
      }
    }
  }
  for (const [id,amount] of losses) { const entity = alive.get(id)!; entity.hp = Math.max(0,entity.hp-amount); }
  for (const { entity,status } of statuses) if (entity.hp > 0) battle.status(entity,status);
  for (const entity of alive.values()) if (entity.hp <= 0) battle.kill(entity);
  battle.state.pendingHits = deferred;
}
