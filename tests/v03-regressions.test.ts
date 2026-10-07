import {expect,test} from 'vitest';
import {Battle} from '../src/core/battle';
import {builds,rules} from '../src/content/catalog';
import {damageFor,fire,updateCombat} from '../src/core/combat';
import {bounds,grounded,settleExceptionalMove,spaceFree,spawnX} from '../src/core/occupancy';
import {position,type Entity} from '../src/core/types';
import {startingProfile,validateProfile,settle} from '../src/core/profile';
import {validateSnapshot} from '../src/services/save-validation';
import {advanceSimulation} from '../src/presentation/simulation-clock';
import {actorFrame,type AnimationSheet} from '../src/presentation/animation';
const game=()=>new Battle({matchId:'V03-REGRESSIONS',mode:'trial',heroEnabled:false,seed:123,loadout:builds[0],enemyLoadout:builds[2],enemyProfileId:'AP01',difficultyId:'D02'});
const place=(b:Battle,id:string,x:number,side:0|1=0)=>{const e=b.spawn(side,id,`A${id[1]}`);e.x=e.previousX=position(x);return e;};
test('同一按 tick 输入在 30、60、120 FPS 下得到完全相同的战斗存档',()=>{
  const run=(fps:number)=>{const b=game();let accumulator=0;
    for(let frame=0;frame<fps*20;frame++)accumulator=advanceSimulation(accumulator,1000/fps,()=>{if(b.state.tick===0)b.act({type:'train',side:0,unitId:'U11'});if(b.state.tick===30)b.act({type:'train',side:0,unitId:'U12'});b.step();}).accumulator;
    expect(b.state.tick).toBe(600);return b.snapshot();};
  expect(run(30)).toEqual(run(60));expect(run(60)).toEqual(run(120));
});
test('换代冲锋在长途行军后第一次合法接敌时才开始八秒计时',()=>{
  const b=game();b.state.sides[0].knowledge=85000;b.act({type:'evolve',side:0});const newcomer=place(b,'U21',200);b.step(270);
  expect(newcomer.rushArmed).toBe(true);expect(newcomer.rushUntil).toBe(0);
  const foe=place(b,'U21',newcomer.x/100+newcomer.radius+16+43,1);foe.speed=0;b.step();
  expect(newcomer.rushArmed).toBe(false);expect(newcomer.rushUntil).toBe(b.state.tick+rules.evolutionRush.buffSec*30);
});
test('没有落点时冲锋角色停止攻击并等待合法空位，空位释放后恢复身体',()=>{
  const b=game(),hero=b.spawn(0,'H01','A1','hero');hero.x=position(700);
  const [min,max]=bounds(16),army:Entity[]=[];
  for(let x=min;x<=max;x+=position(36)){const e=place(b,'U11',x/100);e.speed=0;army.push(e);}
  hero.yielding=true;settleExceptionalMove(b.state,hero);expect(hero.settlementPending).toBe(true);expect(grounded(hero)).toBe(false);
  const before=b.state.pendingHits.length;updateCombat(b);expect(b.state.pendingHits.length).toBe(before);
  const slot=Math.floor(army.length/2);b.kill(army[slot],true);updateCombat(b);expect(hero.settlementPending).toBe(true);
  b.kill(army[slot+1],true);updateCombat(b);
  expect(hero.settlementPending).toBeUndefined();expect(hero.yielding).toBe(false);expect(spaceFree(b.state,hero.x,hero.radius,hero.id)).toBe(true);
});
test('射手清理后炮弹保留出手时的类别克制和攻城属性',()=>{
  const b=game(),gun=place(b,'U44',400),target=b.base(1);
  const hit={sourceId:gun.id,side:0 as const,targetId:target.id,raw:100,damageType:'blast' as const,projectile:true,attackerRole:gun.role,attackerHeavy:true,attackerKind:'unit' as const};
  fire(b,gun,target,hit);const expected=damageFor(b,hit,target);b.state.entities=b.state.entities.filter(e=>e.id!==gun.id);expect(damageFor(b,b.state.projectiles[0].hit,target)).toBe(expected);
  const ranged=place(b,'U52',800,1),ordinary=damageFor(b,{...hit,attackerHeavy:false,attackerRole:'front',targetId:ranged.id,damageType:'physical'},ranged);
  expect(ordinary).toBeGreaterThan(damageFor(b,{...hit,attackerHeavy:false,attackerRole:'anti_armor',targetId:ranged.id,damageType:'physical'},ranged));
});
test('旧档保留解锁与收藏，旧队列金额和出生时代不被重置',()=>{
  let profile=startingProfile('LEGACY-MIGRATION');
  for(const missionId of ['M01','M02']){profile.rewardJournal.lastReservedSequence++;const completed=game();completed.state.config={...completed.state.config,matchId:missionId,mode:'campaign',missionId,profileId:profile.profileId,rewardSequence:profile.rewardJournal.lastReservedSequence,lootSeed:73};completed.state.winner=0;profile=settle(profile,completed.state).profile;}
  profile.contentVersion='0.1.0';
  const migrated=validateProfile(profile);expect(migrated.contentVersion).toBe('0.3.0');expect(migrated.clearedMissionIds).toEqual(profile.clearedMissionIds);expect(migrated.ownedRelicIds).toEqual(profile.ownedRelicIds);
  const b=game();b.act({type:'train',side:0,unitId:'U11'});const old=b.snapshot() as any;old.contentVersion='0.1.0';delete old.ageStrikes;delete old.config.heroEnabled;for(const side of old.sides){delete side.research;delete side.ageSpecialReadyAt;}
  const queue=structuredClone(old.sides[0].queue),restored=validateSnapshot(old);expect(restored.sides[0].queue).toEqual(queue);expect(restored.config.heroEnabled).toBe(true);expect(old.contentVersion).toBe('0.1.0');
});
test('当前版本旧占位半径恢复时只重排身体，保留生命、队列、研究与驻营英雄',()=>{
  const b=game();
  const first=place(b,'U11',420),second=place(b,'U12',400);
  first.hp=73;second.hp=61;b.state.sides[0].gold=777;b.state.sides[0].knowledge=1234;b.state.sides[0].research['front-attack']=1;
  const hero=b.spawn(0,'H01','A1','hero');hero.garrisoned=true;hero.x=hero.previousX=b.base(0).x;hero.phase='idle';hero.releaseAt=0;hero.targetId=null;
  const snapshot=structuredClone(b.snapshot()) as any;
  snapshot.entities.find((e:any)=>e.id===first.id).radius=16;
  snapshot.entities.find((e:any)=>e.id===second.id).radius=16;
  const restored=validateSnapshot(snapshot);
  const a=restored.entities.find(e=>e.id===first.id)!;const c=restored.entities.find(e=>e.id===second.id)!;const h=restored.entities.find(e=>e.id===hero.id)!;
  expect(a.hp).toBe(73);expect(c.hp).toBe(61);expect(restored.sides[0].gold).toBe(777);expect(restored.sides[0].knowledge).toBe(1234);expect(restored.sides[0].research['front-attack']).toBe(1);
  expect(a.radius).toBeGreaterThan(16);expect(c.radius).toBe(14);expect(Math.abs(a.x-c.x)).toBeGreaterThanOrEqual(Math.round((a.radius+c.radius+4)*100));
  expect(h.garrisoned).toBe(true);expect(h.x).toBe(b.base(0).x);expect(h.yielding).toBeUndefined();
});
test('攻击帧对齐释放，降低动态效果保留攻击、受击与死亡',()=>{
  const b=game(),e=place(b,'U42',400),sheet={clips:{idle:[0,1,2,3,4,5],walk:[6,7,8,9,10,11],attack:[12,13,14,15,16,17],hurt:[18,19,20,21,22,23],death:[24,25,26,27,28,29]}} as AnimationSheet;
  const clock={now:30,releasedAt:30,hitAt:-100,skillAt:-100,previousFrame:0,reducedMotion:true};
  e.phase='windup';e.releaseAt=40;e.windup=10;expect(actorFrame(e,sheet,clock)).toBe(12);e.phase='recover';expect(actorFrame(e,sheet,clock)).toBe(14);
  expect(actorFrame(e,sheet,{...clock,now:43,hitAt:40,releasedAt:-100})).toBe(18);b.kill(e,true);expect(actorFrame(e,sheet,{...clock,now:b.state.tick+18})).toBe(29);
});
test('撤回英雄驻营后不堵出兵口，休整期间不能出手或消耗军令',()=>{
  const b=game(),hero=b.spawn(0,'H01','A1','hero');hero.hp=Math.floor(hero.maxHp*.15);hero.x=position(230);
  expect(b.act({type:'stance',side:0,stance:'retreat'}).ok).toBe(true);b.step(120);
  expect(hero.garrisoned).toBe(true);expect(hero.x).toBe(b.base(0).x);expect(grounded(hero)).toBe(false);
  expect(b.living(0)).not.toContain(hero);expect(b.hero(0)).toBe(hero);
  const command=b.state.sides[0].command;
  expect(b.act({type:'cast',side:0,skillId:'HS01',x:hero.x/100}).ok).toBe(false);
  expect(b.state.sides[0].command).toBe(command);expect(hero.charge).toBeUndefined();
  for(const unitId of ['U11','U12','U13'])expect(b.act({type:'train',side:0,unitId}).ok).toBe(true);
  b.step(360);expect(b.state.sides[0].queue).toHaveLength(0);expect(b.population(0)).toBe(3);
  expect(b.living(0).filter(e=>e.kind==='unit').every(e=>e.x>position(400))).toBe(true);
});
test('驻营恢复保留整数余量，出口占用时等待，空位释放后合法归队',()=>{
  const b=game(),hero=b.spawn(0,'H01','A1','hero');hero.x=spawnX(0,hero.contentId);hero.hp=50;
  b.act({type:'stance',side:0,stance:'retreat'});b.step();expect(hero.garrisoned).toBe(true);
  const hp=hero.hp;b.step(30);expect(hero.hp-hp).toBe(Math.floor(hero.maxHp*.025));
  const restored=new Battle(b.state.config,validateSnapshot(b.snapshot()));b.step(17);restored.step(17);expect(restored.snapshot()).toEqual(b.snapshot());
  const door=place(b,'U11',spawnX(0,'U11')/100);door.speed=0;
  expect(b.act({type:'stance',side:0,stance:'rush'}).ok).toBe(true);b.step(10);expect(hero.garrisoned).toBe(true);
  b.kill(door,true);b.step();expect(hero.garrisoned).toBe(false);expect(grounded(hero)).toBe(true);
  expect(spaceFree(b.state,hero.x,hero.radius,hero.id)).toBe(true);expect(hero.nextAttack).toBeGreaterThan(b.state.tick);
});
