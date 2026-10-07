import { catalog, eras, rules } from '../content/catalog';
import { effects, loadoutErrors } from './loadout';
import { boundedRandom } from './rng';
import { castSkill, updateSkills } from './skills';
import { applyHits, updateCombat, updateProjectiles, updateStatuses } from './combat';
import { decide } from './ai';
import { fighterProfile } from './fighter-profiles';
import { nearestSpace, spaceFree, spawnX } from './occupancy';
import { attackResearch, researchById, researchCost, researchLevel } from './research';
import { ageSpecials, updateAgeSpecials } from './age-specials';
import { activeItems, defaultActiveItems, defaultItemCooldowns } from './active-items';
import { clamp, position, ticks, value, worldX, type Action, type BattleState, type Effects, type Entity, type Fighter, type MatchConfig, type Side, type SideState, type Status } from './types';

export class Battle {
  state: BattleState;
  constructor(config: MatchConfig, restored?: BattleState) {
    if (restored) { this.state = structuredClone(restored); return; }
    for (const loadout of [config.loadout, config.enemyLoadout]) {
      const errors = loadoutErrors(loadout);
      if (errors.length) throw new Error(errors.join('；'));
    }
    const mission = config.missionId ? catalog.missions[config.missionId] : undefined;
    const eraId = config.startingEraId ?? mission?.startingEraId ?? 'A1';
    if (!catalog.eras[eraId]) throw new Error('未知初始时代');
    const side = (index: Side): SideState => ({
      eraId, gold: (index === 0 ? mission?.playerStartingGold ?? rules.resources.startingGold : mission?.enemyStartingGold ?? rules.resources.startingGold) * 1000,
      knowledge: 0, command: rules.resources.startingCommand * 1000, remainders: [0,0,0],
      loadout: structuredClone(index === 0 ? config.loadout : config.enemyLoadout), stance: 'cover', stanceReadyAt: 0,
      queue: [], cooldowns: {}, upgrades: [], unlockedSlots: 1, turrets: [], heroRespawnAt: 0,
      rushDeadline: 0, rushSpawns: 0, awaitingUpgrade: false, kills: 0, comboHits: 0,
      research: {}, ageSpecialReadyAt: 0,
      activeItems: defaultActiveItems(), itemCooldowns: defaultItemCooldowns(),
    });
    this.state = { contentVersion: rules.designVersion, config: structuredClone(config), tick: 0, nextId: 1, rng: config.seed || rules.rng.zeroSeedFallback,
      paused: false, winner: null, sides: [side(0),side(1)], entities: [], projectiles: [], scheduledSkills: [], ageStrikes: [], pendingHits: [], events: [], processedActionIds: [], lastActionSequence:-1,bossThresholds: [], bossPending: 0, castTargets: {} };
    for (const index of [0,1] as Side[]) {
      const modifiers = this.modifiers(index);
      const hp = Math.floor(catalog.eras[eraId].baseHp * (1 + value(modifiers,'baseHpBonus') + (index === 1 ? Number(mission?.bossParameters?.enemyBaseHpBonus ?? 0) : 0)));
      const base: Entity = {
        id: this.id(), contentId: `base-${index}`, side: index, kind: 'base', eraId, x: position(rules.world.basePositions[index]), hp, maxHp: hp,
        radius: 55, attack: 0, baseAttack: 0, attackBonus: 0, armor: rules.base.armor, energyResistance: rules.base.energyResistance, range: 0, speed: 0, moveRemainder: 0,
        weaponId: 'W02', damageType: 'physical', heavy: true, role: 'base', period: 0, windup: 0, nextAttack: 0, releaseAt: 0, targetId: null,
        phase: 'idle', statuses: [], shields: [], bornTick: 0, runDistance: 0, rushUntil: 0, rushFirstHit: false, staggerImmuneUntil: 0, counterReadyAt: 0,
      };
      this.state.entities.push(base);
      if (config.heroEnabled !== false) this.spawn(index, this.state.sides[index].loadout.heroId, eraId, 'hero');
    }
    if (mission?.bossParameters?.prebuiltTurretId) this.act({ type: 'turret', side: 1, turretId: String(mission.bossParameters.prebuiltTurretId), slot: 0 });
  }

  id() { return this.state.nextId++; }
  random(bound: number) { const draw = boundedRandom(this.state.rng, bound); this.state.rng = draw.seed; return draw.value; }
  base(side: Side) { return this.state.entities.find(entity => entity.kind === 'base' && entity.side === side)!; }
  hero(side: Side) { return this.state.entities.find(entity => entity.kind === 'hero' && entity.side === side && entity.hp > 0); }
  living(side?: Side) { return this.state.entities.filter(entity => entity.hp > 0 && !entity.garrisoned && (side === undefined || entity.side === side)); }
  population(side: Side) { return this.living(side).filter(entity => entity.kind === 'unit' || entity.kind === 'summon').length; }
  populationCap() { return rules.world.populationPerSide - (this.state.config.heroEnabled === false ? 0 : rules.world.heroReservedSlots); }
  spawnBlocked(side: Side, contentId: string) {
    if (this.population(side) >= this.populationCap()) return 'population' as const;
    return spaceFree(this.state, spawnX(side, contentId), fighterProfile(contentId).radius) ? null : 'exit' as const;
  }
  heavyUnlocked(side: Side) { return this.state.config.mode === 'trial' || researchLevel(this.state.sides[side], 'heavy-unlock') > 0; }
  modifiers(side: Side): Effects { const player = this.state.sides[side]; return this.state.config.heroEnabled===false ? {} : effects(player.loadout, player.upgrades); }
  specification(side: Side) { return this.state.config.heroEnabled===false ? {} : catalog.specializations[this.state.sides[side].loadout.specializationId].effects; }
  event(type: string, x: number, side: Side, extra: Partial<BattleState['events'][number]> = {}) {
    this.state.events.push({ id: this.id(), tick: this.state.tick, type, x, side, ...extra });
  }
  get maxEraId() { return this.state.config.maximumEraId ?? (this.state.config.missionId ? catalog.missions[this.state.config.missionId].maximumEraId : 'A5'); }
  commandMax(side: Side) { return Math.min(rules.caps.commandMax, rules.resources.commandMax + value(this.modifiers(side), 'commandMaxAdd')) * 1000; }
  unitCost(side: Side, unitId: string) {
    const unit = catalog.units[unitId];
    return Math.ceil(unit.costBase * catalog.eras[unit.eraId].costMultiplier * (1 - clamp(value(this.modifiers(side),'unitCostReduction'),0,rules.caps.costReduction)));
  }
  skillCost(side: Side, skillId: string) {
    const skill = catalog.skills[skillId], modifiers = this.modifiers(side), spec = this.specification(side);
    return skill.commandCost + (skill.category === 'signature' ? value(modifiers,'signatureCostAdd') + value(spec,'signatureCostAdd') : (skill.damageType === 'energy' ? value(modifiers,'energyCommonCostAdd') : 0) + Number((modifiers.skillCostAdd as Record<string,number> | undefined)?.[skillId] ?? 0));
  }
  skillRange(side:Side,skillId:string){const skill=catalog.skills[skillId];return skill.castRange+(skill.category==='common' ? value(this.modifiers(side),'commonCastRangeAdd') : 0);}

  spawn(side: Side, contentId: string, eraId: string, kind: 'unit' | 'hero' = 'unit'): Entity {
    const content = (kind === 'hero' ? catalog.heroes[contentId] : catalog.units[contentId]) as Fighter;
    if (!content) throw new Error(`未知实体：${contentId}`);
    const unit = kind === 'unit' ? catalog.units[contentId] : undefined;
    const fighter: Entity = {
      id: this.id(), contentId, side, kind, eraId, x: spawnX(side, contentId), hp: 1, maxHp: 1,
      radius: fighterProfile(contentId).radius, attack: 0, baseAttack: 0, attackBonus: 0, armor: content.armor, energyResistance: content.energyResistance,
      range: content.range, speed: content.moveSpeed, moveRemainder: 0, weaponId: content.weaponId, damageType: content.damageType,
      heavy: unit?.heavy ?? false, role: unit?.role ?? 'hero', period: ticks(content.attackPeriodSec), windup: ticks(unit?.windupSec ?? .25),
      nextAttack: this.state.tick, releaseAt: 0, targetId: null, phase: 'idle', statuses: [], shields: [], bornTick: this.state.tick,
      runDistance: 0, rushUntil: 0, rushFirstHit: false, staggerImmuneUntil: 0, counterReadyAt: 0,
    };
    this.refresh(fighter, false);
    const player = this.state.sides[side];
    if (kind === 'unit' && eraId === player.eraId && this.state.tick < player.rushDeadline && player.rushSpawns > 0) {
      fighter.rushArmed = true;
      fighter.rushFirstHit = true;
      player.rushSpawns--;
      this.event('rush', worldX(fighter), side, { targetId: fighter.id });
    }
    this.state.entities.push(fighter);
    this.event('spawn', worldX(fighter), side, { targetId: fighter.id });
    return fighter;
  }

  refresh(entity: Entity, preserve = true) {
    if (entity.kind !== 'unit' && entity.kind !== 'hero') return;
    const content = entity.kind === 'unit' ? catalog.units[entity.contentId] : catalog.heroes[entity.contentId];
    const modifier = this.modifiers(entity.side), spec = entity.kind === 'hero' ? this.specification(entity.side) : {};
    const era = catalog.eras[entity.eraId];
    const hpBonus = entity.kind === 'hero' ? value(modifier,'heroHpBonus') + value(spec,'heroHpBonus') : value(modifier,'unitHpBonus') + (entity.role === 'front' ? value(modifier,'frontHpBonus') : 0);
    const ratio = preserve ? entity.hp / entity.maxHp : 1;
    entity.maxHp = Math.floor(content.hpBase * era.hpAttackMultiplier * (1 + hpBonus));
    entity.hp = clamp(Math.floor(entity.maxHp * ratio), entity.hp > 0 ? 1 : 0, entity.maxHp);
    const attackBonus = entity.kind === 'hero' ? value(spec,'heroAttackBonus') : value(modifier,'unitAttackBonus') + (entity.role === 'front' ? value(modifier,'frontAttackBonus') : 0);
    entity.baseAttack = content.attackBase * era.hpAttackMultiplier;
    entity.attackBonus = clamp(attackBonus + (entity.kind === 'unit' ? attackResearch(this.state.sides[entity.side], entity.role) : 0),-.9,rules.caps.attackBonus);
    entity.attack = entity.baseAttack * (1 + entity.attackBonus);
    entity.range = content.range + value(spec,'rangeAdd') + (entity.role === 'ranged' ? value(modifier,'rangedRangeAdd') + researchLevel(this.state.sides[entity.side], 'ranged-range') * 25 : 0);
    entity.armor = content.armor + (entity.role === 'front' ? researchLevel(this.state.sides[entity.side], 'front-armor') * 10 : 0);
    entity.speed = content.moveSpeed * (1 + value(spec,'heroMoveBonus'));
  }

  act(action: Action, sequence?: number): { ok: boolean; reason?: string } {
    const state = this.state, player = state.sides[action.side];
    const fail = (reason: string) => ({ ok: false, reason });
    if (state.winner !== null) return fail('对局已结束');
    if(sequence!==undefined){if(!Number.isSafeInteger(sequence) || sequence<0 || sequence<=state.lastActionSequence)return fail('重复或无效指令');state.lastActionSequence=sequence;state.processedActionIds=[...state.processedActionIds,sequence].slice(-200);}
    if (state.paused && action.type !== 'upgrade') return fail('对局已暂停');
    const modifier = this.modifiers(action.side);
    if (action.type === 'train') {
      const unit = catalog.units[action.unitId];
      if (!unit || unit.eraId !== player.eraId) return fail('只能训练当前时代兵种');
      if (unit.heavy && !this.heavyUnlocked(action.side)) return fail('先在强化中开放重型军团');
      if (player.queue.length >= rules.world.trainingQueueMax) return fail('训练队列已满');
      const price = this.unitCost(action.side, action.unitId) * 1000;
      if (player.gold < price) return fail('军资不足');
      const duration = ticks(unit.trainSec * (1-clamp(value(modifier,'trainingReduction'),0,rules.caps.trainingReduction)));
      player.gold -= price;
      player.queue.push({ id: this.id(), unitId: unit.id, eraId: player.eraId, paid: price, duration, remaining: duration, advancedBy: [], progressUsed: 0 });
      this.event('queue', worldX(this.base(action.side)), action.side);
    } else if (action.type === 'cancel') {
      const index = player.queue.findIndex(item => item.id === action.queueId);
      if (index < 0) return fail('训练项目已离开队列');
      const item = player.queue[index];
      player.gold += Math.floor(item.paid * (index > 0 || item.remaining === item.duration ? rules.queue.unstartedCancelRefund : rules.queue.inProgressCancelRefund));
      player.queue.splice(index,1);
    } else if (action.type === 'stance') {
      if (!this.hero(action.side)) return fail('英雄正在重建');
      if (state.tick < player.stanceReadyAt) return fail('站位指令间隔中');
      player.stance = action.stance;
      player.stanceReadyAt = state.tick + ticks(rules.hero.stanceChangeIntervalSec);
      this.event('stance', worldX(this.hero(action.side)!), action.side, { text: action.stance });
    } else if (action.type === 'evolve') {
      const era = catalog.eras[player.eraId];
      if (player.eraId === this.maxEraId || era.nextEvolutionKnowledge === null) return fail('已达本局时代上限');
      if (player.knowledge < era.nextEvolutionKnowledge * 1000) return fail('学识不足');
      player.knowledge -= era.nextEvolutionKnowledge * 1000;
      player.eraId = eras[eras.findIndex(item => item.id === player.eraId)+1].id;
      const base = this.base(action.side), ratio = base.hp/base.maxHp;
      const bossBonus = action.side === 1 && state.config.missionId ? Number(catalog.missions[state.config.missionId].bossParameters?.enemyBaseHpBonus ?? 0) : 0;
      base.maxHp = Math.floor(catalog.eras[player.eraId].baseHp * (1+value(modifier,'baseHpBonus')+bossBonus));
      base.hp = Math.floor(base.maxHp * ratio); base.eraId = player.eraId;
      const hero = this.hero(action.side);
      if (hero) { hero.eraId = player.eraId; this.refresh(hero); }
      player.awaitingUpgrade = false;
      player.rushDeadline = state.tick + ticks(rules.evolutionRush.eligibleSec + value(modifier, 'rushEligibleAddSec'));
      player.rushSpawns = rules.evolutionRush.spawnCount;
      this.event('evolve', worldX(base), action.side, { text: catalog.eras[player.eraId].name });
    } else if (action.type === 'research') {
      const research = researchById[action.researchId];
      if (!research || researchLevel(player, research.id) >= research.max) return fail('强化已达上限');
      if (research.id === 'heavy-attack' && !this.heavyUnlocked(action.side)) return fail('先开放重型军团');
      const cost = researchCost(player, research.id) * 1000;
      if (player.gold < cost) return fail('金币不足');
      player.gold -= cost; player.research[research.id] = researchLevel(player, research.id) + 1;
      for (const entity of this.living(action.side)) this.refresh(entity);
      this.event('research', worldX(this.base(action.side)), action.side, { text: research.name });
    } else if (action.type === 'ageSpecial') {
      const special = ageSpecials[player.eraId as keyof typeof ageSpecials];
      if (state.tick < player.ageSpecialReadyAt) return fail('时代大招冷却中');
      if (player.knowledge < special.cost * 1000) return fail('战斗经验不足');
      if (!Number.isFinite(action.x) || action.x < 140 || action.x > 1460) return fail('请选择战场中的位置');
      player.knowledge -= special.cost * 1000;
      player.ageSpecialReadyAt = state.tick + ticks(special.cooldown);
      state.ageStrikes.push({ id: this.id(), side: action.side, eraId: player.eraId, x: action.x, due: state.tick + ticks(.75), remaining: special.pulses });
      this.event('ageWarn', action.x, action.side, { text: player.eraId, amount: special.radius });
    } else if (action.type === 'item') {
      const item = activeItems[action.itemId];
      if (!item) return fail('未知主动道具');
      const charges = player.activeItems?.[action.itemId] ?? 0;
      if (charges <= 0) return fail('该道具已经用完');
      if ((player.itemCooldowns?.[action.itemId] ?? 0) > state.tick) return fail('主动道具冷却中');
      if (item.targetMode === 'point' && (!Number.isFinite(action.x) || (action.x ?? 0) < 140 || (action.x ?? 0) > 1460)) return fail('请选择战线中的位置');
      player.activeItems[action.itemId] = charges - 1;
      player.itemCooldowns[action.itemId] = state.tick + ticks(item.cooldownSec);
      const center = item.targetMode === 'point' ? action.x! : worldX(this.base(action.side));
      if (action.itemId === 'war-drum') {
        const until = state.tick + ticks(8);
        for (const entity of this.living(action.side)) if (entity.kind !== 'base') {
          entity.attackBuff = { until, bonus: .18 };
          entity.moveBuff = { until, bonus: .12 };
        }
        this.advanceQueue(action.side, `item:${action.itemId}:${state.tick}`, .35);
      } else if (action.itemId === 'smoke-bomb') {
        const radius = item.radius ?? 135;
        for (const entity of this.living((1-action.side) as Side)) if (entity.kind !== 'base' && Math.abs(worldX(entity)-center) <= radius) {
          this.status(entity, { id: 'ST03', until: state.tick + ticks(5), magnitude: .35, sourceId: this.base(action.side).id, sourceSide: action.side });
        }
      } else {
        player.gold += 65000;
        player.command = Math.min(this.commandMax(action.side), player.command + 15000);
        this.advanceQueue(action.side, `item:${action.itemId}:${state.tick}`, .45);
      }
      this.event('itemCast', center, action.side, { text: action.itemId, amount: item.radius ?? 0, sourceId: this.base(action.side).id });
    } else if (action.type === 'upgrade') {
      if (!player.awaitingUpgrade || catalog.upgrades[action.upgradeId]?.eraId !== player.eraId) return fail('不是本次时代的选项');
      player.upgrades.push(action.upgradeId); player.awaitingUpgrade = false;
      player.rushDeadline = state.tick + ticks(rules.evolutionRush.eligibleSec + value(this.modifiers(action.side),'rushEligibleAddSec'));
      player.rushSpawns = rules.evolutionRush.spawnCount;
      for (const entity of this.living(action.side)) if (entity.kind === 'unit') this.refresh(entity);
      this.event('upgrade',worldX(this.base(action.side)),action.side,{text:catalog.upgrades[action.upgradeId].name});
      if (action.side === 0) state.paused = false;
    } else if (action.type === 'unlockSlot') {
      if (player.unlockedSlots >= 3) return fail('炮塔槽已全部开放');
      const cost = rules.base.slotUnlockCosts[player.unlockedSlots-1] * 1000;
      if (player.gold < cost) return fail('金币不足');
      player.gold -= cost; player.unlockedSlots++;
    } else if (action.type === 'turret') {
      const turret = catalog.turrets[action.turretId];
      if (!turret || turret.eraId !== player.eraId || action.slot < 0 || action.slot >= player.unlockedSlots || player.turrets.some(item => item.slot === action.slot)) return fail('炮塔位置或时代无效');
      const cost = Math.ceil(turret.costBase*catalog.eras[turret.eraId].costMultiplier) * 1000;
      if (player.gold < cost) return fail('军资不足');
      const towerId=this.id();
      player.gold -= cost; player.turrets.push({ id: towerId, contentId: turret.id, paid: cost, slot: action.slot, nextAttack: state.tick+ticks(.6) });
      this.event('build',worldX(this.base(action.side)),action.side,{sourceId:towerId,text:turret.name});
    } else if (action.type === 'sell') {
      const index = player.turrets.findIndex(item => item.slot === action.slot);
      if (index < 0) return fail('此处没有炮塔');
      this.event('sell',worldX(this.base(action.side)),action.side,{sourceId:player.turrets[index].id});
      player.gold += Math.floor(player.turrets[index].paid*rules.base.turretSellRefund); player.turrets.splice(index,1);
    } else if (action.type === 'cast') {
      const result = castSkill(this, action);
      if (!result.ok) return result;
    }
    return { ok: true };
  }

  advanceQueue(side: Side, source: string, ratio: number) {
    const item = this.state.sides[side].queue[0];
    if (!item || item.advancedBy.includes(source)) return;
    const reduction = Math.min(Math.floor(item.remaining*ratio), Math.floor(item.duration*rules.caps.queueProgressCapOfOriginal)-item.progressUsed);
    item.remaining -= Math.max(0,reduction); item.progressUsed += Math.max(0,reduction); item.advancedBy.push(source);
  }

  step(count = 1) {
    for (let index = 0; index < count; index++) {
      const state = this.state;
      if (state.paused || state.winner !== null) return;
      state.tick++;
      for(const entity of state.entities)entity.previousX=entity.x;
      for (const side of [0,1] as Side[]) {
        const player = state.sides[side], era = catalog.eras[player.eraId], modifier = this.modifiers(side);
        const rates = [rules.resources.goldPerSec*era.incomeMultiplier*(1+clamp(value(modifier,'incomeBonus'),0,rules.caps.incomeBonus)), 0, rules.resources.commandPerSec];
        const fields = ['gold','knowledge','command'] as const;
        rates.forEach((rate,i) => { player.remainders[i] += Math.round(rate*1000); const change = Math.floor(player.remainders[i]/30); player[fields[i]] += change; player.remainders[i] %= 30; });
        player.command = Math.min(player.command,this.commandMax(side));
        if (state.config.heroEnabled !== false && !this.hero(side) && player.heroRespawnAt > 0 && state.tick >= player.heroRespawnAt && spaceFree(state, spawnX(side, player.loadout.heroId), fighterProfile(player.loadout.heroId).radius)) {
          this.spawn(side,player.loadout.heroId,player.eraId,'hero'); player.heroRespawnAt = 0; player.stance = 'cover';
        }
        const item = player.queue[0];
        if (item) {
          item.remaining = Math.max(0,item.remaining-1);
          if (item.remaining === 0 && !this.spawnBlocked(side, item.unitId)) { this.spawn(side,item.unitId,item.eraId); player.queue.shift(); }
        }
      }
      updateStatuses(this); updateSkills(this); updateAgeSpecials(this); updateCombat(this); updateProjectiles(this);
      applyHits(this);
      this.updateBoss();
      if (state.tick >= ticks(rules.overtime.burnStartsSec) && state.tick % 30 === 0) for (const side of [0,1] as Side[]) this.base(side).hp = Math.max(0,this.base(side).hp-Math.ceil(this.base(side).maxHp*rules.overtime.baseMaxHpBurnPerSec));
      const left = this.base(0).hp, right = this.base(1).hp;
      if (left <= 0 || right <= 0) { state.winner = left <= 0 && right <= 0 ? 'draw' : left <= 0 ? 1 : 0; this.event('end',800,0); }
      else decide(this,1);
      state.events = state.events.filter(event => state.tick-event.tick <= 90);
      for (const [id,cast] of Object.entries(state.castTargets)) if (cast.until <= state.tick) delete state.castTargets[Number(id)];
      state.entities = state.entities.filter(entity => entity.phase !== 'dead' || entity.kind === 'base' || state.tick-entity.bornTick < 24);
    }
  }

  updateBoss() {
    const state = this.state;
    if (state.config.missionId !== 'M15') return;
    const base = this.base(1), player = state.sides[1];
    for (const threshold of [.65,.3]) if (base.hp/base.maxHp <= threshold && !state.bossThresholds.includes(threshold)) { state.bossThresholds.push(threshold); state.bossPending++; }
    if (state.bossPending > 0 && player.command >= 20000 && base.hp > 0) { player.command -= 20000; this.shield(base,.1,4); state.bossPending--; }
  }
  status(entity: Entity, status: Status) {
    if (entity.kind === 'base') return;
    if (status.id === 'ST09') {
      if (this.state.tick < entity.staggerImmuneUntil) return;
      entity.staggerImmuneUntil = status.until + ticks(2);
      entity.releaseAt = 0; entity.targetId = null; entity.phase = 'idle';
    }
    const old = entity.statuses.find(item => item.id === status.id && (status.id !== 'ST08' || item.sourceId === status.sourceId));
    if (!old) entity.statuses.push(status);
    else if (status.id === 'ST04') Object.assign(old,status);
    else { const until = Math.max(old.until,status.until); if (status.magnitude >= old.magnitude) { const nextTick = old.nextTick; Object.assign(old,status); if (status.id === 'ST06' && nextTick !== undefined) old.nextTick = nextTick; } old.until = until; }
  }
  shield(entity: Entity, ratio: number, duration: number) {
    if (entity.hp <= 0) return;
    const current = entity.shields.reduce((sum,batch) => sum+batch.hp,0);
    const received = entity.kind === 'hero' ? 1+value(this.specification(entity.side),'shieldReceivedBonus') : 1;
    const amount = Math.max(0,Math.min(Math.floor(entity.maxHp*ratio*received),Math.floor(entity.maxHp*rules.caps.shieldHpRatio)-current));
    if (amount) { entity.shields.push({ hp: amount, until: this.state.tick+ticks(duration) }); this.event('shield',worldX(entity),entity.side,{ targetId: entity.id, amount }); }
  }
  kill(entity: Entity, naturalExpiry = false) {
    if (entity.phase === 'dead') return;
    entity.hp = 0; entity.phase = 'dead'; entity.bornTick = this.state.tick; entity.statuses = []; entity.shields = [];
    this.event('death',worldX(entity),entity.side,{ targetId: entity.id });
    const enemy = (1-entity.side) as Side;
    if (entity.kind === 'unit' && !naturalExpiry) {
      const unit = catalog.units[entity.contentId], modifier = this.modifiers(enemy);
      const gold = Math.floor(unit.bountyGold*catalog.eras[entity.eraId].costMultiplier*(1+clamp(value(modifier,'bountyBonus'),0,rules.caps.bountyBonus)));
      this.state.sides[enemy].kills++;
      if(this.state.config.mode!=='trial'){
        const experience = Math.round(unit.killKnowledge * catalog.eras[entity.eraId].hpAttackMultiplier);
        this.state.sides[enemy].gold += gold*1000;
        this.state.sides[enemy].knowledge += experience*1000;
        this.state.sides[entity.side].knowledge += Math.floor(experience * .65)*1000;
        this.event('reward',worldX(entity),enemy,{ amount: gold });
      }
    } else if (entity.kind === 'hero') this.state.sides[entity.side].heroRespawnAt = this.state.tick + ticks(rules.hero.respawnSec-value(this.modifiers(entity.side),'respawnReductionSec'));
    else if (entity.kind === 'summon' && naturalExpiry) this.state.sides[entity.side].gold += value(this.specification(entity.side),'naturalExpiryGold')*1000;
  }
  snapshot() { return structuredClone(this.state); }
}
