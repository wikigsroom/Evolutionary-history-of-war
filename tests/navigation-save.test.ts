import {describe,expect,test} from 'vitest';
import {Battle} from '../src/core/battle';
import {decide} from '../src/core/ai';
import {builds} from '../src/content/catalog';
import {position,type BattleState} from '../src/core/types';
import {BattleCamera} from '../src/presentation/battle-camera';
import {MatchSaver} from '../src/services/match-saver';
import type {StoragePort} from '../src/services/storage';
import {validateSnapshot} from '../src/services/save-validation';

const fixture=()=>new Battle({matchId:'CAMERA-SAVE',mode:'trial',seed:876123,loadout:builds[0],enemyLoadout:builds[0],enemyProfileId:'AP01',difficultyId:'D03'});
describe('横向战场导航',()=>{
  test('定位两座基地，各自处于世界的左右尽头，平移不会改变对局',()=>{
    const battle=fixture(),before=battle.snapshot(),camera=new BattleCamera();
    camera.jump('ally',battle);expect(camera.x).toBe(0);expect(camera.worldAt(80)).toBe(battle.base(0).x/100);
    camera.jump('enemy',battle);expect(camera.x).toBe(600);expect(camera.worldAt(920)).toBe(battle.base(1).x/100);
    camera.pan(5000);expect(camera.x).toBe(600);camera.pan(-5000);expect(camera.x).toBe(0);
    expect(battle.snapshot()).toEqual(before);
  });
  test('手指轻点可用于施法，拖动和拖到边界都只能平移',()=>{
    const camera=new BattleCamera();camera.begin(400,220);camera.drag(404,222,1);expect(camera.end()).toBe(false);
    camera.begin(700,220);camera.drag(380,220,1);expect(camera.end()).toBe(true);expect(camera.x).toBe(320);
    camera.begin(700,220);camera.drag(-100,220,1);expect(camera.end()).toBe(true);expect(camera.x).toBe(600);
  });
  test('跟随英雄与前线，手动操作解除跟随，改变视野宽度保持边界',()=>{
    const battle=fixture(),camera=new BattleCamera();battle.hero(0)!.x=position(1120);camera.jump('hero',battle);expect(camera.x).toBe(600);
    battle.hero(0)!.x=position(760);camera.update(battle,50,true);expect(camera.x).toBe(260);
    const front=battle.spawn(0,'U11','A1');front.x=position(1050);camera.jump('front',battle);expect(camera.x).toBe(550);
    camera.pan(-90);expect(camera.tracking).toBe('free');camera.update(battle,50,true);expect(camera.x).toBe(460);
    camera.setWidth(1300);expect(camera.x).toBe(300);
  });
});

class DelayedStorage implements StoragePort{
  records=new Map<string,unknown>();writes:BattleState[]=[];release:(()=>void)|null=null;failNext=false;
  async read<T>(key:string){return structuredClone(this.records.get(key) ?? null) as T|null;}
  async writeAtomic<T>(key:string,value:T){
    if(this.failNext){this.failNext=false;throw new Error('disk failure');}
    if(!this.writes.length)await new Promise<void>(resolve=>{this.release=resolve;});
    this.records.set(key,structuredClone(value));this.writes.push(structuredClone(value) as BattleState);
  }
  async writeBatchAtomic(records:Record<string,unknown>,remove:string[]=[]){for(const [key,value] of Object.entries(records))this.records.set(key,structuredClone(value));for(const key of remove)this.records.delete(key);}
  async remove(key:string){this.records.delete(key);}
}
describe('保存并返回与结算屏障',()=>{
  test('写入期间的最新保存不会被跳过，返回营地前必须完成最新快照',async()=>{
    const storage=new DelayedStorage(),saver=new MatchSaver(storage),battle=fixture();
    battle.state.tick=30;const first=saver.save(battle.snapshot());await Promise.resolve();
    battle.state.tick=47;battle.state.paused=true;const latest=saver.save(battle.snapshot());
    battle.state.tick=90;let returned=false;void latest.then(()=>{returned=true;});await Promise.resolve();expect(returned).toBe(false);
    storage.release!();await first;const saved=await latest;expect(saved.tick).toBe(47);expect(saved.paused).toBe(true);expect(storage.writes.map(s=>s.tick)).toEqual([30,47]);
    await saver.flush();await storage.remove('match');expect(await storage.read('match')).toBeNull();
  });
  test('失败保存报告错误，重试可写入后续快照',async()=>{
    const storage=new DelayedStorage();storage.failNext=true;storage.writes.push(fixture().snapshot());const saver=new MatchSaver(storage);
    await expect(saver.save(fixture().snapshot())).rejects.toThrow('disk failure');
    const state=fixture().snapshot();state.tick=150;await saver.save(state);expect((await storage.read<BattleState>('match'))!.tick).toBe(150);
  });
});
describe('炮塔与技能的实际战斗流程',()=>{
  test('炮塔完成0.6秒建造后开火，弹体与事件都记录实际炮塔',()=>{
    const battle=fixture();battle.state.sides[0].gold=1000000;const enemy=battle.spawn(1,'U11','A1');enemy.x=position(250);enemy.hp=enemy.maxHp=5000;
    expect(battle.act({type:'turret',side:0,turretId:'TR11',slot:0}).ok).toBe(true);const tower=battle.state.sides[0].turrets[0];
    battle.step(17);expect(battle.state.events.some(e=>e.type==='release' && e.sourceId===tower.id)).toBe(false);
    battle.step();expect(battle.state.events.some(e=>e.type==='release' && e.sourceId===tower.id)).toBe(true);
    const shot=battle.state.projectiles.find(p=>p.sourceId===tower.id);expect(shot).toBeDefined();expect(shot!.hit.sourceId).toBe(tower.id);
    expect(validateSnapshot(battle.snapshot())).toEqual(battle.state);
  });
  test('敌方战旗先锋可对正前方目标使用冲锋，消费同一份能量与冷却',()=>{
    const battle=fixture();battle.state.config.mode='standard';battle.state.sides[1].loadout={heroId:'H01',specializationId:'P011',commonSkillIds:['S01','S02'],relicIds:[],talentIds:[]};battle.hero(1)!.x=position(550);battle.hero(0)!.x=position(380);
    for(let tick=15;tick<=150 && !battle.hero(1)!.charge;tick+=15){battle.state.tick=tick;decide(battle,1);}
    expect(battle.hero(1)!.charge).toBeDefined();expect(battle.state.sides[1].cooldowns.HS01).toBeGreaterThan(battle.state.tick);expect(battle.state.sides[1].command).toBeLessThan(50000);
  });
});
