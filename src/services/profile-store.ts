import { startingProfile,settle,validateProfile,type Profile,type RewardReceipt } from '../core/profile';
import { Battle } from '../core/battle';
import type { BattleState,MatchConfig } from '../core/types';
import type { StoragePort } from './storage';
import { loadoutErrors } from '../core/loadout';
import { availability,missionAvailable } from '../core/profile';
import { catalog } from '../content/catalog';

export class ProfileStore {
  private queue=Promise.resolve();
  constructor(private storage:StoragePort) {}
  private ledgerKey(profile:Profile){return `profile-ledger:${profile.profileId}`;}
  private ensureCurrent(next:Profile,previous:Profile){
    if(next.rewardJournal.lastCommittedSequence<previous.rewardJournal.lastCommittedSequence || next.rewardJournal.lastReservedSequence<previous.rewardJournal.lastReservedSequence || next.revision<previous.revision) throw new Error('该文件早于本机奖励日志，不能覆盖当前档案');
  }
  async load():Promise<Profile> {
    const saved=await this.storage.read<Profile>('profile');
    if(saved){const profile=validateProfile(saved),ledger=await this.storage.read<Profile>(this.ledgerKey(profile));if(ledger)this.ensureCurrent(profile,validateProfile(ledger));else await this.storage.writeAtomic(this.ledgerKey(profile),profile);return profile;}
    const created=startingProfile(crypto.randomUUID());await this.storage.writeBatchAtomic({profile:created,[this.ledgerKey(created)]:created});return created;
  }
  private serial<T>(action:()=>Promise<T>):Promise<T> {
    const work=this.queue.catch(()=>undefined).then(action);
    this.queue=work.then(()=>undefined,()=>undefined);return work;
  }
  begin(config:MatchConfig):Promise<{profile:Profile;battle:Battle}> {
    return this.serial(async()=>{
      const profile=await this.load(),next=structuredClone(profile);
      if(config.mode!=='challenge') {
        const errors=[...loadoutErrors(config.loadout,profile.masteryPoints,availability(profile)),...loadoutErrors(config.enemyLoadout,profile.masteryPoints,{...availability(profile),heroes:Object.keys(catalog.heroes)})];
        if(errors.length)throw new Error(errors.join('；'));
      }
      if(config.missionId && !missionAvailable(profile,config.missionId))throw new Error('关卡尚未开放');
      next.rewardJournal.lastReservedSequence++;next.revision++;
      const reserved={...config,profileId:next.profileId,rewardSequence:next.rewardJournal.lastReservedSequence,lootSeed:crypto.getRandomValues(new Uint32Array(1))[0]};
      const battle=new Battle(reserved);
      await this.storage.writeBatchAtomic({'profile-backup':profile,profile:next,[this.ledgerKey(next)]:next,match:battle.snapshot()});
      return {profile:next,battle};
    });
  }
  commit(state:BattleState):Promise<{profile:Profile;receipt:RewardReceipt}> {
    return this.serial(async()=>{
      const profile=await this.load(),last=await this.storage.read<RewardReceipt>('last-reward');
      if(last?.matchId===state.config.matchId && last.sequence===state.config.rewardSequence) return {profile,receipt:last};
      await this.storage.writeAtomic('match',state);
      const result=settle(profile,state);
      await this.storage.writeBatchAtomic({'profile-backup':profile,profile:result.profile,[this.ledgerKey(result.profile)]:result.profile,'last-reward':result.receipt},['match']);
      return result;
    });
  }
  update(mutator:(profile:Profile)=>Profile):Promise<Profile> {
    return this.serial(async()=>{const profile=await this.load(),next=validateProfile(mutator(structuredClone(profile)));if(next.profileId!==profile.profileId)throw new Error('军议不能更换档案身份');this.ensureCurrent(next,profile);next.revision=profile.revision+1;await this.storage.writeBatchAtomic({'profile-backup':profile,profile:next,[this.ledgerKey(next)]:next});return next;});
  }
  import(input:unknown):Promise<Profile> {
    return this.serial(async()=>{
      const current=await this.load(),next=validateProfile(input);
      const ledger=await this.storage.read<Profile>(this.ledgerKey(next));
      if(ledger)this.ensureCurrent(next,validateProfile(ledger));
      if(next.profileId===current.profileId)this.ensureCurrent(next,current);
      next.revision=Math.max(current.revision,next.revision)+1;
      await this.storage.writeBatchAtomic({'profile-backup':current,profile:next,[this.ledgerKey(next)]:next},['match','last-reward']);return next;
    });
  }
  restoreBackup():Promise<Profile>{
    return this.serial(async()=>{
      const backup=validateProfile(await this.storage.read<Profile>('profile-backup'));
      const ledger=await this.storage.read<Profile>(this.ledgerKey(backup));
      const next=ledger ? validateProfile(ledger) : backup;
      next.revision++;await this.storage.writeBatchAtomic({profile:next,[this.ledgerKey(next)]:next});return next;
    });
  }
}
