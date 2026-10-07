import {describe,expect,test} from 'vitest';
import {Battle} from '../src/core/battle';
import {applyHits,updateStatuses} from '../src/core/combat';
import {updateSkills} from '../src/core/skills';
import {catalog,builds} from '../src/content/catalog';
import {position,type BattleState} from '../src/core/types';
import {validateSnapshot} from '../src/services/save-validation';

const fixture=()=>new Battle({matchId:'INTEGRITY',mode:'trial',seed:7,loadout:{...builds[0],commonSkillIds:['S08','S09']},enemyLoadout:builds[2],enemyProfileId:'AP03',difficultyId:'D02'});
describe('对局完整性与持续技能',()=>{
  test('失败指令也消耗序号，最近200条之外的旧指令仍不能重放',()=>{
    const battle=fixture();expect(battle.act({type:'evolve',side:0},0).ok).toBe(false);
    for(let sequence=1;sequence<=205;sequence++)battle.act({type:'evolve',side:0},sequence);
    expect(battle.state.processedActionIds).not.toContain(0);
    expect(battle.act({type:'train',side:0,unitId:'U11'},0).reason).toMatch(/重复/);
    expect(battle.state.sides[0].queue).toEqual([]);
    const restored=new Battle(battle.state.config,validateSnapshot(battle.snapshot()));
    expect(restored.act({type:'train',side:0,unitId:'U11'},1).ok).toBe(false);
  });
  test('所有时代的实际战斗快照都能完整恢复，包含弹体、队列和持续技能',()=>{
    for(const startingEraId of Object.keys(catalog.eras)){
      const battle=new Battle({...fixture().state.config,startingEraId,maximumEraId:startingEraId});
      battle.state.sides[0].gold=1000000;battle.state.sides[0].command=100000;
      const unit=Object.values(catalog.units).find(u=>u.eraId===startingEraId)!;
      battle.act({type:'train',side:0,unitId:unit.id});
      battle.act({type:'cast',side:0,skillId:'S08',x:400});
      for(let i=0;i<600;i++){battle.step();if(i%30===0)expect(validateSnapshot(battle.snapshot())).toEqual(battle.state);}
    }
  });
  test('篡改冷却、攻击、弹体、序号或缺失嵌套数组均拒绝且保留输入',()=>{
    const corruptions:((s:BattleState)=>void)[]=[s=>s.lastActionSequence=NaN,s=>s.entities[1].speed=Infinity,s=>s.entities[1].statuses=[{id:'ST99',until:100,magnitude:1,sourceSide:0,sourceId:1}],s=>s.sides[0].cooldowns.S01=-1,s=>s.sides[0].remainders[0]=30,s=>s.config.loadout.commonSkillIds=null as never,s=>s.nextId=1];
    for(const corrupt of corruptions){const state=fixture().snapshot();corrupt(state);const before=structuredClone(state);expect(()=>validateSnapshot(state)).toThrow(/已保留/);expect(state).toEqual(before);}
  });
  test('火区初始目标仅受四次燃烧；后来被牵入的目标用原时代强度和原结束时间',()=>{
    const battle=fixture();battle.state.sides[0].command=100000;
    const first=battle.spawn(1,'U14','A1');first.x=position(350);first.maxHp=first.hp=1000;
    expect(battle.act({type:'cast',side:0,skillId:'S08',x:350}).ok).toBe(true);
    battle.state.tick=1;updateSkills(battle);applyHits(battle);const field=battle.state.scheduledSkills[0];
    let burnHits=0;
    for(let tick=2;tick<=61;tick++){battle.state.tick=tick;updateStatuses(battle);burnHits+=battle.state.pendingHits.length;applyHits(battle);updateSkills(battle);}
    const arrival=battle.spawn(1,'U14','A1');arrival.x=position(350);battle.state.sides[0].eraId='A5';
    battle.state.tick=62;updateSkills(battle);const burn=arrival.statuses.find(s=>s.id==='ST06')!;
    expect(burn.eraMultiplier).toBe(1);expect(burn.until).toBe(field.fieldUntil);expect(burn.nextTick).toBe(92);
    for(let tick=63;tick<=121;tick++){battle.state.tick=tick;updateStatuses(battle);burnHits+=battle.state.pendingHits.filter(h=>h.targetId===first.id).length;applyHits(battle);updateSkills(battle);}
    expect(burnHits).toBe(4);expect(battle.state.scheduledSkills).toEqual([]);
  });
  test('同一火区含初始命中与后来进入者最多影响六个不同目标',()=>{
    const battle=fixture();battle.state.sides[0].command=100000;
    for(let i=0;i<4;i++)battle.spawn(1,'U14','A1').x=position(350);
    battle.act({type:'cast',side:0,skillId:'S08',x:350});battle.state.tick=1;updateSkills(battle);applyHits(battle);
    for(let i=0;i<4;i++)battle.spawn(1,'U14','A1').x=position(350);
    battle.state.tick=2;updateSkills(battle);
    expect(battle.living(1).filter(e=>e.statuses.some(s=>s.id==='ST06'))).toHaveLength(6);
  });
});
