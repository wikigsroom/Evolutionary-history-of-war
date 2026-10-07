import { describe,expect,test } from 'vitest';
import { catalog,missions,relics } from '../src/content/catalog';
import { Battle } from '../src/core/battle';
import { craft,loadoutFor,rollChest,settle,startingProfile,validateProfile,type Profile } from '../src/core/profile';
import { fitLoadout } from '../src/core/loadout';
import { ProfileStore } from '../src/services/profile-store';
import type { StoragePort } from '../src/services/storage';
import type { MatchConfig } from '../src/core/types';

function config(profile:Profile,id?:string):MatchConfig {
  return {matchId:`MATCH-${profile.rewardJournal.lastReservedSequence+1}`,mode:id ? 'campaign' : 'standard',missionId:id,seed:1234,loadout:loadoutFor(profile,'H01'),enemyLoadout:fitLoadout(catalog.builds.B03,profile.masteryPoints,profile.unlockedSkillIds,profile.ownedRelicIds),enemyProfileId:'AP03',difficultyId:'D02',profileId:profile.profileId,rewardSequence:profile.rewardJournal.lastReservedSequence+1,lootSeed:42};
}
function victory(profile:Profile,id?:string) {
  const c=config(profile,id);profile.rewardJournal.lastReservedSequence++;
  const battle=new Battle(c);battle.state.winner=0;return {state:battle.snapshot(),...settle(profile,battle.state)};
}
class MemoryStorage implements StoragePort {
  records=new Map<string,unknown>();failCommit=false;
  async read<T>(key:string){return structuredClone(this.records.get(key) ?? null) as T | null;}
  async writeAtomic<T>(key:string,value:T){await this.writeBatchAtomic({[key]:value});}
  async writeBatchAtomic(records:Record<string,unknown>,remove:string[]=[]){if(this.failCommit && 'last-reward' in records){this.failCommit=false;throw new Error('simulated power loss');}const next=new Map(this.records);for(const [key,value] of Object.entries(records))next.set(key,structuredClone(value));for(const key of remove)next.delete(key);this.records=next;}
  async remove(key:string){this.records.delete(key);}
}
describe('档案成长与结算',()=>{
  test('新档两英雄两技能、无遗物、两点传承，默认专精合法',()=>{
    const profile=startingProfile('PROFILE');expect(validateProfile(profile)).toEqual(profile);
    expect(profile.loadouts.map(l=>l.specializationId)).toEqual(['P011','P031']);
    expect(profile.ownedRelicIds).toEqual([]);expect(profile.masteryPoints).toBe(2);
  });
  test('首次教程先解锁技能，再开随机箱，固定遗物不占箱子',()=>{
    const result=victory(startingProfile('PROFILE'),'M01');
    expect(result.profile.tutorialComplete).toBe(true);expect(result.profile.unlockedSkillIds).toHaveLength(12);
    expect(result.receipt.relics).toHaveLength(2);expect(result.receipt.relics[0].id).toBe('I01');
    expect(()=>settle(result.profile,result.state)).toThrow(/已结算/);
  });
  test('十五关按首通推进到六英雄六点，章末开两箱',()=>{
    let profile=startingProfile('PROFILE');
    for(const mission of missions){const result=victory(profile,mission.id);profile=result.profile;expect(result.receipt.relics.filter(r=>r.source==='chest').length).toBe([3,6,9,12,15].includes(Number(mission.id.slice(1))) ? 2 : 1);}
    expect(profile.unlockedHeroIds).toHaveLength(6);expect(profile.masteryPoints).toBe(6);expect(profile.clearedMissionIds).toHaveLength(15);
  });
  test('第五箱稀有与第二十箱史诗保底，史诗优先且重置稀有',()=>{
    for(let seed=1;seed<50;seed++){const p=startingProfile('PROFILE');p.pity.rareMisses=4;expect(catalog.relics[rollChest(p,seed).id].rarity).not.toBe('common');p.pity={rareMisses:4,epicMisses:19};expect(catalog.relics[rollChest(p,seed).id].rarity).toBe('epic');expect(p.pity).toEqual({rareMisses:0,epicMisses:0});}
  });
  test('定向制作仅消耗四碎片，不能重复购买，不影响保底',()=>{
    let p=startingProfile('PROFILE');for(const id of ['M01','M02','M03'])p=victory(p,id).profile;
    p.fragments=4;const id=relics.find(r=>!p.ownedRelicIds.includes(r.id))!.id;const next=craft(p,id);
    expect(next.fragments).toBe(0);expect(next.pity).toEqual(p.pity);expect(()=>craft(next,id)).toThrow();expect(p.fragments).toBe(4);
  });
  test('旧ID离开最近200项后，终身序号仍阻止重复领奖',()=>{
    let p=startingProfile('PROFILE');const first=victory(p,'M01');p=first.profile;
    for(let i=0;i<201;i++)p=victory(p).profile;
    expect(p.rewardJournal.completedMatchIds).toHaveLength(200);expect(p.rewardJournal.completedMatchIds).not.toContain(first.state.config.matchId);
    expect(()=>settle(p,first.state)).toThrow(/已结算/);
  });
  test('提前失败与演练没有藏品，短失败不增加熟练度',()=>{
    const p=startingProfile('PROFILE'),c=config(p);p.rewardJournal.lastReservedSequence++;
    const battle=new Battle(c);battle.state.winner=1;const result=settle(p,battle.state);
    expect(result.receipt.proficiency).toBe(0);expect(result.receipt.relics).toEqual([]);
    battle.state.config.mode='trial';expect(()=>settle(p,battle.state)).toThrow();
  });
  test('原子提交失败保留完整结算战场，恢复后结果相同且只领取一次',async()=>{
    const memory=new MemoryStorage(),store=new ProfileStore(memory),profile=await store.load();
    const begin=await store.begin(config(profile,'M01'));begin.battle.state.winner=0;
    memory.failCommit=true;await expect(store.commit(begin.battle.state)).rejects.toThrow('power loss');
    expect((await store.load()).tutorialComplete).toBe(false);
    const recovered=new ProfileStore(memory),result=await recovered.commit((await memory.read<typeof begin.battle.state>('match'))!);
    expect(await recovered.commit(begin.battle.state)).toEqual(result);expect((await recovered.load()).tutorialComplete).toBe(true);
  });
  test('导入同一档案的旧版本不能倒退已预留或已提交序号',async()=>{
    const store=new ProfileStore(new MemoryStorage()),old=await store.load();await store.begin(config(old,'M01'));
    await expect(store.import(old)).rejects.toThrow(/早于/);
  });
  test('切换到其他档案后，旧档案仍受本机终身奖励日志约束',async()=>{
    const store=new ProfileStore(new MemoryStorage()),old=await store.load();
    const started=await store.begin(config(old,'M01'));started.battle.state.winner=0;await store.commit(started.battle.state);
    await store.import(startingProfile('ANOTHER-PROFILE'));
    await expect(store.import(old)).rejects.toThrow(/早于/);
  });
  test('恢复备份使用最后完整事务的档案，保留已经提交的收藏与序号',async()=>{
    const memory=new MemoryStorage(),store=new ProfileStore(memory),old=await store.load();
    const started=await store.begin(config(old,'M01'));started.battle.state.winner=0;
    const committed=await store.commit(started.battle.state);memory.records.set('profile',{broken:true});
    const restored=await store.restoreBackup();
    expect(restored.rewardJournal).toEqual(committed.profile.rewardJournal);expect(restored.ownedRelicIds).toEqual(committed.profile.ownedRelicIds);
    expect(()=>settle(restored,started.battle.state)).toThrow(/已结算/);
  });
});
