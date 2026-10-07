import { describe, expect, test } from 'vitest';
import { Battle } from '../src/core/battle';
import { applyHits, damageFor, fire, updateProjectiles, updateCombat } from '../src/core/combat';
import { catalog, builds, heroes, skills } from '../src/content/catalog';
import { fitLoadout, loadoutErrors } from '../src/core/loadout';
import { position, type MatchConfig, type Hit, type Side } from '../src/core/types';

const loadout = { heroId: 'H01', specializationId: 'P011', commonSkillIds: ['S01','S02'], relicIds: [], talentIds: ['T11','T12'] };
function match(overrides: Partial<MatchConfig> = {}) {
  return new Battle({ matchId: 'TEST-MATCH',mode: 'trial',seed: 1234,loadout,enemyLoadout: { ...loadout, heroId: 'H03',specializationId: 'P031' },enemyProfileId: 'AP01',difficultyId: 'D02',...overrides });
}

describe('开局与成长预算',() => {
  test('无遗物的新档可开局，六构筑可裁剪到两点和初始技能',() => {
    expect(loadoutErrors(loadout,2)).toEqual([]);
    for (const build of builds) {
      const fitted = fitLoadout(build,2,['S01','S02'],[]);
      expect(loadoutErrors(fitted,2)).toEqual([]);
      expect(fitted.talentIds).toHaveLength(2);
      expect(fitted.relicIds).toEqual([]);
    }
  });
  test('不能仅装第三层、重复遗物或其他角色专精',() => {
    expect(loadoutErrors({ ...loadout,talentIds: ['T15'] },2).length).toBeGreaterThan(0);
    expect(loadoutErrors({ ...loadout,relicIds: ['I01','I01'] }).length).toBeGreaterThan(0);
    expect(loadoutErrors({ ...loadout,specializationId: 'P031' }).length).toBeGreaterThan(0);
  });
  test('收入余数使30个tick恰好等于一秒',() => {
    const battle = match(); battle.step(30);
    expect(battle.state.sides[0].gold).toBe(242500);
    expect(battle.state.sides[0].knowledge).toBe(0);
    expect(battle.state.sides[0].command).toBe(53000);
  });
});

describe('队列与时代',() => {
  test('未训练全额退款；已开始75%；同一ID不能再次退款',() => {
    const battle = match();
    expect(battle.act({ type: 'train',side: 0,unitId: 'U11' }).ok).toBe(true);
    const first = battle.state.sides[0].queue[0].id;
    battle.act({ type: 'cancel',side: 0,queueId: first });
    expect(battle.state.sides[0].gold).toBe(240000);
    battle.act({ type: 'train',side: 0,unitId: 'U11' }); battle.step();
    const item = battle.state.sides[0].queue[0];
    const before = battle.state.sides[0].gold;
    battle.act({ type: 'cancel',side: 0,queueId: item.id });
    expect(battle.state.sides[0].gold-before).toBe(33750);
    expect(battle.act({ type: 'cancel',side: 0,queueId: item.id }).ok).toBe(false);
  });
  test('进化保留基地伤血，已付旧兵保持出生时代',() => {
    const battle = match();
    battle.base(0).hp = 1200;
    battle.act({ type: 'train',side: 0,unitId: 'U11' });
    battle.state.sides[0].knowledge = 160000;
    expect(battle.act({ type: 'evolve',side: 0 }).ok).toBe(true);
    expect(battle.base(0).hp).toBe(1600);
    const tick = battle.state.tick; battle.step(100);
    expect(battle.state.tick).toBe(tick+100);
    battle.step(48);
    const old = battle.living(0).find(entity => entity.kind === 'unit')!;
    expect(old.eraId).toBe('A1'); expect(old.rushFirstHit).toBe(false);
    expect(battle.act({ type: 'train',side: 0,unitId: 'U11' }).ok).toBe(false);
  });
  test('人口满保留待出营项目，腾出槽位才生成',() => {
    const battle = match();
    battle.hero(0)!.x=position(1300);
    for (let i=0;i<29;i++) {const entity=battle.spawn(0,'U11','A1');entity.x=position(200+i*36);entity.speed=0;}
    battle.act({ type: 'train',side: 0,unitId: 'U11' }); battle.step(60);
    expect(battle.population(0)).toBe(29); expect(battle.state.sides[0].queue[0].remaining).toBe(0);
    battle.kill(battle.living(0).find(entity => entity.kind === 'unit')!); battle.step();
    expect(battle.population(0)).toBe(29); expect(battle.state.sides[0].queue).toHaveLength(0);
  });
  test('瞬时推进同来源一次，所有来源累计不超过原时长50%',() => {
    const battle = match({ startingEraId: 'A4' }); battle.state.sides[0].gold = 500000;
    battle.act({ type: 'train',side: 0,unitId: 'U44' }); battle.step(10);
    const item = battle.state.sides[0].queue[0];
    battle.advanceQueue(0,'S12',.15); const remainder = item.remaining;
    battle.advanceQueue(0,'S12',.15); expect(item.remaining).toBe(remainder);
    battle.advanceQueue(0,'HS06',.9); expect(item.progressUsed).toBe(Math.floor(item.duration*.5));
  });
});

describe('真实伤害与状态',() => {
  test('穿透弹体只命中每个敌人一次，继续穿过第二个敌人',() => {
    const battle=match();
    const first=battle.spawn(1,'U11','A1'),second=battle.spawn(1,'U11','A1');
    first.x=position(220); second.x=position(255);
    fire(battle,battle.hero(0)!,first,{sourceId:battle.hero(0)!.id,side:0,targetId:first.id,raw:10,damageType:'pierce',projectile:true},'W03',0,1,false,2);
    for(let i=0;i<15;i++) updateProjectiles(battle);
    expect(battle.state.pendingHits.map(hit=>hit.targetId)).toEqual([first.id,second.id]);
    expect(battle.state.projectiles).toHaveLength(0);
  });
  test('常驻攻击加成与临时旗枪加成合计不能突破30%',() => {
    const battle=match(),unit=battle.spawn(0,'U11','A1'),target=battle.spawn(1,'U11','A1');
    unit.x=target.x=position(400); unit.baseAttack=100; unit.attackBonus=.28; unit.attackBuff={until:100,bonus:.1}; unit.releaseAt=1; unit.targetId=target.id;
    battle.state.tick=1; updateCombat(battle);
    expect(battle.state.pendingHits.find(hit=>hit.sourceId===unit.id)?.raw).toBe(130);
  });
  test('已经提交的冲锋伤害在途中换代时保留施法时代',() => {
    const battle=match();
    battle.act({type:'cast',side:0,skillId:'HS01',x:150});
    const raw=battle.hero(0)!.charge!.raw;
    battle.state.sides[0].knowledge=160000;
    battle.act({type:'evolve',side:0}); battle.act({type:'upgrade',side:0,upgradeId:'R21'});
    const enemy=battle.spawn(1,'U11','A1'); enemy.x=position(190);
    battle.step(6);
    expect(battle.hero(0)!.charge!.raw).toBe(raw);
    const hit=battle.state.events.find(event=>event.type==='hit' && event.skillId==='HS01' && event.targetId===enemy.id);
    expect(hit?.amount).toBe(77);
  });
  test('破甲轰击145→182，首发先算伤害再施加状态',() => {
    const battle = match({ startingEraId: 'A4' });
    const target = battle.spawn(1,'U34','A3');
    const hit: Hit = { sourceId: battle.hero(0)!.id,side: 0,targetId: target.id,raw: 72*2.9,damageType: 'blast',projectile: true,skillId: 'S05' };
    expect(damageFor(battle,hit,target)).toBe(145);
    battle.status(target,{ id: 'ST01',until: 120,magnitude: .25,sourceId: battle.hero(0)!.id,sourceSide: 0 });
    expect(damageFor(battle,hit,target)).toBe(182);
    const fresh = battle.spawn(1,'U34','A3'); const hp = fresh.hp;
    battle.state.pendingHits.push({ ...hit,targetId: fresh.id,statuses: [{ id: 'ST01',until: 120,magnitude: .25,sourceId: hit.sourceId,sourceSide: 0 }] });
    applyHits(battle); expect(hp-fresh.hp).toBe(145); expect(fresh.statuses[0].id).toBe('ST01');
  });
  test('护盾独立批次、总量30%，零伤害技能不制造1点假命中',() => {
    const battle = match(); const hero = battle.hero(0)!; hero.hp = hero.maxHp = 400; hero.armor = 0;
    battle.shield(hero,.2,6); battle.shield(hero,.25,8);
    expect(hero.shields.map(shield => shield.hp)).toEqual([73,47]);
    expect(hero.shields.reduce((sum,shield) => sum+shield.hp,0)).toBe(120);
    expect(damageFor(battle,{ sourceId: 5,side: 1,targetId: hero.id,raw: 0,damageType: 'physical',projectile: false },hero)).toBe(0);
  });
  test('主动鼓舞按时结束，重型兽骑不再伪装为支援战鼓',() => {
    const battle = match(); const hero = battle.hero(0)!;
    const drummer = battle.spawn(0,'U14','A1'); drummer.x = hero.x;
    battle.status(hero,{ id: 'ST08',until: 4,magnitude: .15,sourceId: hero.id,sourceSide: 0 });
    battle.step(4);
    expect(hero.statuses.filter(status => status.id === 'ST08')).toHaveLength(0);
    expect(drummer.heavy).toBe(true);expect(drummer.role).toBe('heavy');
  });
  test('导电支链不递归，一次施法最多六个不同伤害目标',() => {
    const battle = match(); const targets = Array.from({ length: 8 },(_,index) => { const entity = battle.spawn(1,'U11','A1'); entity.x = position(600+index*10); battle.status(entity,{ id: 'ST05',until: 180,magnitude: .4,sourceId: 9,sourceSide: 0 }); return entity; });
    for (const target of targets.slice(0,3)) battle.state.pendingHits.push({ sourceId: battle.hero(0)!.id,side: 0,targetId: target.id,raw: 54,damageType: 'energy',projectile: false,skillId: 'S07',castId: 123,conductive: true });
    applyHits(battle);
    expect(new Set(battle.state.events.filter(event => event.type === 'hit').map(event => event.targetId)).size).toBe(6);
  });
  test('同tick基地双杀为平局',() => {
    const battle = match();
    for (const side of [0,1] as Side[]) battle.state.pendingHits.push({ sourceId: battle.base(side).id,side,targetId: battle.base((1-side) as Side).id,raw: 100000,damageType: 'physical',projectile: false });
    battle.step(); expect(battle.state.winner).toBe('draw');
  });
  test('英雄倒下后25秒重建，保留尚未到期的技能冷却',() => {
    const guardian = { ...loadout,heroId: 'H03',specializationId: 'P031' };
    const battle = match({ loadout: guardian });
    battle.act({ type: 'cast',side: 0,skillId: 'HS03',x: 150 });
    battle.kill(battle.hero(0)!); battle.step(749); expect(battle.hero(0)).toBeUndefined();
    battle.step(); expect(battle.hero(0)?.hp).toBe(battle.hero(0)?.maxHp);
    expect(battle.state.sides[0].cooldowns.HS03-battle.state.tick).toBe(210);
  });
});

describe('恢复与全库执行',() => {
  test('序列化后恢复，相同后续动作得到完全相同状态',() => {
    const battle = match({ mode: 'standard' });
    battle.act({ type: 'train',side: 0,unitId: 'U11' }); battle.step(91);
    const restored = new Battle(battle.state.config,JSON.parse(JSON.stringify(battle.snapshot())));
    for (const item of [battle,restored]) { item.act({ type: 'train',side: 0,unitId: 'U12' }); item.step(300); }
    expect(restored.snapshot()).toEqual(battle.snapshot());
  });
  test.each(skills.map(skill => [skill.id,skill.heroId ?? 'H01']))('%s能按合法目标执行且不产生NaN',(skillId,heroId) => {
    const hero = catalog.heroes[heroId];
    const common = skillId.startsWith('HS') ? ['S01','S02'] : [skillId,skillId === 'S01' ? 'S02' : 'S01'];
    const battle = match({ loadout: { ...loadout,heroId,specializationId: hero.specializationIds[0],commonSkillIds: common },startingEraId: 'A3' });
    battle.state.sides[0].command = 100000;
    const target = battle.spawn(1,'U31','A3'); target.x = position(280);
    const result = battle.act({ type: 'cast',side: 0,skillId,x: skillId === 'HS04' ? 220 : 280,targetId: target.id });
    expect(result.ok).toBe(true); battle.step(180);
    for (const entity of battle.state.entities) { expect(Number.isFinite(entity.hp)).toBe(true); expect(Number.isFinite(entity.x)).toBe(true); }
  });
});
