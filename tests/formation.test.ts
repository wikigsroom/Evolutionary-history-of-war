import {describe,expect,test} from 'vitest';
import {Battle} from '../src/core/battle';
import {builds,catalog} from '../src/content/catalog';
import {applyHits,damageFor,updateCombat} from '../src/core/combat';
import {BODY_GAP,grounded,spaceFree,spawnX} from '../src/core/occupancy';
import {position,ticks,type Entity} from '../src/core/types';
import {validateSnapshot} from '../src/services/save-validation';
const game=(heroEnabled=false)=>new Battle({matchId:'FORMATION-TEST',mode:'trial',heroEnabled,seed:120,loadout:builds[0],enemyLoadout:builds[2],enemyProfileId:'AP01',difficultyId:'D02'});
function place(battle:Battle,side:0|1,id:string,x:number){const entity=battle.spawn(side,id,catalog.units[id].eraId);entity.x=position(x);entity.previousX=entity.x;return entity;}
function assertBodies(battle:Battle){
  const bodies=battle.living().filter(grounded);
  for(let i=0;i<bodies.length;i++)for(let j=i+1;j<bodies.length;j++)expect(Math.abs(bodies[i].x-bodies[j].x),`${bodies[i].contentId} / ${bodies[j].contentId}`).toBeGreaterThanOrEqual(position(bodies[i].radius+bodies[j].radius+BODY_GAP)-1);
}
describe('真实阵线与接敌',()=>{
  test('八名短兵不能穿过友军，只有前排接敌；前排死亡后立刻补位',()=>{
    const battle=game(),army:Array<Entity>=[];
    for(let i=0;i<8;i++)army.push(place(battle,0,'U11',650-i*36));
    const target=place(battle,1,'U11',724);target.hp=target.maxHp=10000;target.attack=target.baseAttack=0;
    battle.step(30);
    expect(army.filter(e=>e.targetId===target.id && e.phase!=='dead')).toHaveLength(1);assertBodies(battle);
    const next=army[1],before=next.x;battle.kill(army[0]);battle.step(30);
    expect(next.x).toBeGreaterThan(before);expect(next.targetId).toBe(target.id);assertBodies(battle);
  });
  test('三名支援兵在前排身后可以同时攻击，长矛允许隔一名前排接敌',()=>{
    const battle=game(),front=place(battle,0,'U11',650),spear=place(battle,0,'U13',614);
    const ranged=[place(battle,0,'U12',580),place(battle,0,'U12',548),place(battle,0,'U12',516)];
    const target=place(battle,1,'U11',724);target.hp=target.maxHp=10000;target.attack=target.baseAttack=0;
    battle.step(30);
    expect(front.targetId).toBe(target.id);expect(spear.targetId).toBe(target.id);
    expect(ranged.every(e=>e.targetId===target.id)).toBe(true);assertBodies(battle);
  });
  test('训练完成与出口可用分别判断，敌方营门占位不冻结我方订单',()=>{
    const battle=game(),door=place(battle,1,'U11',spawnX(0,'U11')/100);door.speed=0;
    expect(battle.act({type:'train',side:0,unitId:'U11'}).ok).toBe(true);battle.step(ticks(2));
    // An enemy gate body must not freeze a completed order: the producer can
    // use the next legal gap in the lane and preserve the order's birth era.
    expect(battle.state.sides[0].queue).toHaveLength(0);
    const spawned=battle.living(0).find(e=>e.kind==='unit');
    expect(spawned).toBeDefined();expect(spawned?.eraId).toBe('A1');assertBodies(battle);
  });
  test('重型单位、英雄、临时炮台共享身体空间；撤回后的英雄重新落位',()=>{
    const battle=game(true);battle.hero(0)!.x=position(500);battle.hero(1)!.x=position(1300);
    const mounted=place(battle,0,'U14',420),soldier=place(battle,0,'U11',356);const target=place(battle,1,'U11',900);
    expect(spaceFree(battle.state,mounted.x,mounted.radius)).toBe(false);
    battle.act({type:'stance',side:0,stance:'retreat'});battle.step(210);
    expect(battle.hero(0)?.yielding).toBe(false);assertBodies(battle);expect(soldier.x).toBeLessThan(mounted.x);expect(target.hp).toBeGreaterThan(0);
  });
  test('ID 余数不改变军团移动规则',()=>{
    const run=(offset:number)=>{const battle=game();battle.state.nextId+=offset;const rear=place(battle,0,'U12',350),front=place(battle,0,'U11',400);place(battle,1,'U11',900);battle.step(90);return [rear.x,front.x];};
    expect(run(0)).toEqual(run(1));expect(run(0)).toEqual(run(2));
  });
  test('英雄掩护会给生产军团让出道路，不会把整支军团锁死在基地',()=>{
    const battle=game(true);battle.state.sides[0].gold=1000000;
    battle.act({type:'train',side:0,unitId:'U11'});battle.act({type:'train',side:0,unitId:'U12'});battle.step(300);
    expect(battle.population(0)).toBe(2);expect(battle.living(0).find(e=>e.contentId==='U11')!.x).toBeGreaterThan(position(400));assertBodies(battle);
  });
  test('单位出生顺序决定前后，角色类型不改变生产排序',()=>{
    const battle=game();const first=place(battle,0,'U12',650);const second=place(battle,0,'U11',650);place(battle,1,'U11',900);
    battle.step();
    expect(first.x).toBeGreaterThan(second.x);assertBodies(battle);
  });
});
describe('时代与资源取舍',()=>{
  test('空等不产出 XP，敌兵击破和己兵阵亡给经验，重复死亡与免费召唤不产经验',()=>{
    const battle=game();battle.state.config.mode='standard';battle.step(30);expect(battle.state.sides[0].knowledge).toBe(0);
    const enemy=place(battle,1,'U11',1000);battle.kill(enemy);expect(battle.state.sides[0].knowledge).toBe(8000);expect(battle.state.sides[1].knowledge).toBe(5000);
    battle.kill(enemy);expect(battle.state.sides[0].knowledge).toBe(8000);
    const summon=place(battle,1,'U11',1000);summon.kind='summon';summon.contentId='summon-H04';battle.kill(summon,true);expect(battle.state.sides[0].knowledge).toBe(8000);
  });
  test('金币强化独立于时代，重型需要解锁，进化保留强化、旧兵和旧队列',()=>{
    const battle=game();battle.state.config.mode='standard';battle.state.sides[0].gold=1000000;
    expect(battle.act({type:'train',side:0,unitId:'U14'}).ok).toBe(false);
    const veteran=place(battle,0,'U11',400),hp=veteran.maxHp;const xp=battle.state.sides[0].knowledge;
    expect(battle.act({type:'research',side:0,researchId:'front-attack'}).ok).toBe(true);expect(veteran.attackBonus).toBeGreaterThanOrEqual(.15);expect(battle.state.sides[0].knowledge).toBe(xp);
    battle.act({type:'research',side:0,researchId:'heavy-unlock'});expect(battle.act({type:'train',side:0,unitId:'U14'}).ok).toBe(true);
    battle.state.sides[0].knowledge=85000;battle.act({type:'evolve',side:0});expect(battle.state.paused).toBe(false);expect(veteran.eraId).toBe('A1');expect(veteran.maxHp).toBe(hp);expect(battle.state.sides[0].research['front-attack']).toBe(1);expect(battle.heavyUnlocked(0)).toBe(true);
  });
  test('时代大招有预告、冷却和 XP 成本，不能把一份 XP 同时用于进化',()=>{
    const battle=game();const target=place(battle,1,'U11',850);target.speed=0;const hp=target.hp;const cost=catalog.eras.A1.nextEvolutionKnowledge!*1000;battle.state.sides[0].knowledge=cost;
    expect(battle.act({type:'ageSpecial',side:0,x:850}).ok).toBe(true);expect(battle.state.sides[0].knowledge).toBe(cost-25000);expect(battle.act({type:'evolve',side:0}).ok).toBe(false);
    battle.step(12);expect(target.hp).toBe(hp);battle.step(12);expect(target.hp).toBeLessThan(hp);expect(battle.act({type:'ageSpecial',side:0,x:850}).ok).toBe(false);
  });
  test('四兵种克制独立于护甲与伤害类型',()=>{
    const battle=game(),source=place(battle,0,'U11',400),target=place(battle,1,'U12',800);target.armor=0;
    const hit={sourceId:source.id,side:0 as const,targetId:target.id,raw:100,damageType:'physical' as const,projectile:false};
    expect(damageFor(battle,hit,target)).toBe(130);target.role='anti_armor';expect(damageFor(battle,hit,target)).toBe(100);
  });
  test('保存恢复跨预告大招与排队时点，后续模拟结果保持一致',()=>{
    const battle=game();place(battle,1,'U11',850);battle.state.sides[0].knowledge=50000;battle.act({type:'ageSpecial',side:0,x:850});battle.act({type:'train',side:0,unitId:'U11'});battle.step(12);
    const restored=new Battle(battle.state.config,validateSnapshot(battle.snapshot()));battle.step(120);restored.step(120);expect(restored.snapshot()).toEqual(battle.snapshot());
  });
  test('指挥官阵亡扣除当前时代升级经验的 20%',()=>{
    const battle=game(true);const hero=battle.hero(0)!;battle.state.sides[0].knowledge=100000;
    battle.kill(hero);
    expect(battle.state.sides[0].knowledge).toBe(100000 - catalog.eras.A1.nextEvolutionKnowledge! * 1000 * 0.2);
    expect(battle.state.sides[0].heroRespawnAt).toBeGreaterThan(0);
  });
});
