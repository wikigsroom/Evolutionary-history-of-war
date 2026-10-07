import { builds,catalog,heroes,loot,missions,relics,rules,skills } from '../content/catalog';
import { fitLoadout,loadoutErrors } from './loadout';
import { boundedRandom } from './rng';
import type { BattleState,Loadout } from './types';

export interface Profile {
  schemaVersion:1; contentVersion:string; profileId:string; revision:number; tutorialComplete:boolean;
  unlockedHeroIds:string[]; unlockedSkillIds:string[]; clearedMissionIds:string[]; masteryPoints:number;
  heroProficiency:Record<string,number>; ownedRelicIds:string[]; fragments:number; loadouts:Loadout[];
  pity:{rareMisses:number;epicMisses:number};
  settings:{muted:boolean;reducedMotion:boolean;quality:'auto'|'high'|'low'};
  rewardJournal:{lastCommittedSequence:number;lastReservedSequence:number;completedMatchIds:string[]};
}
export interface RewardReceipt {
  matchId:string;sequence:number;seed:number;status:'committed';firstClear:boolean;relics:{id:string;duplicate:boolean;source:'first_clear'|'chest'}[];
  fragments:number;proficiency:number;heroUnlocks:string[];mastery:number;pityBefore:Profile['pity'];pityAfter:Profile['pity'];
}
export const availability=(profile:Profile)=>({heroes:profile.unlockedHeroIds,skills:profile.unlockedSkillIds,relics:profile.ownedRelicIds});
export function startingProfile(id:string):Profile {
  const profile:Profile={schemaVersion:1,contentVersion:rules.designVersion,profileId:id,revision:0,tutorialComplete:false,
    unlockedHeroIds:[...rules.initialUnlocks.heroIds],unlockedSkillIds:[...rules.initialUnlocks.commonSkillIds],clearedMissionIds:[],masteryPoints:rules.mastery.startingPoints,
    heroProficiency:Object.fromEntries(heroes.map(hero=>[hero.id,0])),ownedRelicIds:[],fragments:0,loadouts:[],pity:{rareMisses:0,epicMisses:0},
    settings:{muted:false,reducedMotion:false,quality:'auto'},rewardJournal:{lastCommittedSequence:0,lastReservedSequence:0,completedMatchIds:[]}};
  profile.loadouts=profile.unlockedHeroIds.map(heroId=>({...fitLoadout(builds.find(build=>build.heroId===heroId)!,profile.masteryPoints,profile.unlockedSkillIds,profile.ownedRelicIds),specializationId:catalog.heroes[heroId].specializationIds[0]}));
  return profile;
}
export function loadoutFor(profile:Profile,heroId:string):Loadout {
  return profile.loadouts.find(loadout=>loadout.heroId===heroId) ?? fitLoadout(builds.find(build=>build.heroId===heroId)!,profile.masteryPoints,profile.unlockedSkillIds,profile.ownedRelicIds);
}
export function missionAvailable(profile:Profile,id:string) {
  const index=missions.findIndex(mission=>mission.id===id);
  return index===0 || index>0 && profile.clearedMissionIds.includes(missions[index-1].id);
}
export function validateProfile(input:unknown):Profile {
  const p=input as Profile, fail=()=>{throw new Error('档案文件不完整或不兼容，原档案已保留');};
  if(!p || p.schemaVersion!==1 || ![rules.designVersion,'0.1.0'].includes(p.contentVersion) || typeof p.profileId!=='string' || !p.profileId || !Number.isSafeInteger(p.revision) || p.revision<0) fail();
  for(const [field,index] of [['unlockedHeroIds',catalog.heroes],['unlockedSkillIds',catalog.skills],['ownedRelicIds',catalog.relics],['clearedMissionIds',catalog.missions]] as const) {
    if(!Array.isArray(p[field]) || new Set(p[field]).size!==p[field].length || p[field].some(id=>!index[id])) fail();
  }
  if(p.clearedMissionIds.some(id=>!missionAvailable(p,id))) fail();
  const expectedHeroes=heroes.filter(hero=>!hero.unlockMissionId || p.clearedMissionIds.includes(hero.unlockMissionId)).map(hero=>hero.id);
  if(expectedHeroes.some(id=>!p.unlockedHeroIds.includes(id)) || p.unlockedHeroIds.some(id=>!expectedHeroes.includes(id))) fail();
  if(p.masteryPoints!==rules.mastery.startingPoints+rules.mastery.pointMissionIds.filter(id=>p.clearedMissionIds.includes(id)).length || p.tutorialComplete!==p.clearedMissionIds.includes('M01')) fail();
  const expectedSkills=p.tutorialComplete ? skills.filter(skill=>skill.category==='common').map(skill=>skill.id) : rules.initialUnlocks.commonSkillIds;
  if(p.unlockedSkillIds.length!==expectedSkills.length || expectedSkills.some(id=>!p.unlockedSkillIds.includes(id))) fail();
  if(!Number.isSafeInteger(p.fragments) || p.fragments<0 || !p.heroProficiency || heroes.some(hero=>!Number.isSafeInteger(p.heroProficiency[hero.id]) || p.heroProficiency[hero.id]<0)) fail();
  if(!p.pity || !Number.isSafeInteger(p.pity.rareMisses) || p.pity.rareMisses<0 || p.pity.rareMisses>=loot.rareOrBetterGuaranteedEvery || !Number.isSafeInteger(p.pity.epicMisses) || p.pity.epicMisses<0 || p.pity.epicMisses>=loot.epicGuaranteedEvery) fail();
  if(!p.settings || typeof p.settings.muted!=='boolean' || typeof p.settings.reducedMotion!=='boolean' || !['auto','high','low'].includes(p.settings.quality)) fail();
  if(!p.rewardJournal || !Number.isSafeInteger(p.rewardJournal.lastCommittedSequence) || p.rewardJournal.lastCommittedSequence<0 || !Number.isSafeInteger(p.rewardJournal.lastReservedSequence) || p.rewardJournal.lastReservedSequence<p.rewardJournal.lastCommittedSequence || !Array.isArray(p.rewardJournal.completedMatchIds) || p.rewardJournal.completedMatchIds.length>200 || p.rewardJournal.completedMatchIds.some(id=>typeof id!=='string') || new Set(p.rewardJournal.completedMatchIds).size!==p.rewardJournal.completedMatchIds.length) fail();
  if(!Array.isArray(p.loadouts) || new Set(p.loadouts.map(loadout=>loadout.heroId)).size!==p.loadouts.length || p.loadouts.some(loadout=>loadoutErrors(loadout,p.masteryPoints,availability(p)).length)) fail();
  return {...structuredClone(p), contentVersion: rules.designVersion};
}
export function rollChest(profile:Profile,seed:number):{id:string;seed:number} {
  let random=seed;
  const draw=(bound:number)=>{const result=boundedRandom(random,bound);random=result.seed;return result.value;};
  let rarity:string;
  if(profile.pity.epicMisses>=loot.epicGuaranteedEvery-1) rarity='epic';
  else if(profile.pity.rareMisses>=loot.rareOrBetterGuaranteedEvery-1) rarity=draw(40)<30 ? 'rare' : 'epic';
  else {const n=draw(100);rarity=n<60 ? 'common' : n<90 ? 'rare' : 'epic';}
  profile.pity.rareMisses=rarity==='common' ? profile.pity.rareMisses+1 : 0;
  profile.pity.epicMisses=rarity==='epic' ? 0 : profile.pity.epicMisses+1;
  const pool=relics.filter(relic=>relic.rarity===rarity);
  return {id:pool[draw(pool.length)].id,seed:random};
}
export function settle(profile:Profile,state:BattleState):{profile:Profile;receipt:RewardReceipt} {
  const c=state.config,j=profile.rewardJournal;
  if(state.winner===null || c.mode==='trial' || c.profileId!==profile.profileId || !Number.isSafeInteger(c.rewardSequence) || (c.rewardSequence ?? 0)<=j.lastCommittedSequence || (c.rewardSequence ?? Infinity)>j.lastReservedSequence || j.completedMatchIds.includes(c.matchId) || !Number.isSafeInteger(c.lootSeed)) throw new Error('该场对局已结算或不属于当前档案');
  if(c.missionId && (c.mode!=='campaign' || !missionAvailable(profile,c.missionId))) throw new Error('战役关卡尚未开放');
  const next=structuredClone(profile),mission=c.missionId ? catalog.missions[c.missionId] : undefined;
  const firstClear=state.winner===0 && Boolean(mission && !next.clearedMissionIds.includes(mission.id));
  const receipt:RewardReceipt={matchId:c.matchId,sequence:c.rewardSequence!,seed:c.lootSeed!,status:'committed',firstClear,relics:[],fragments:0,proficiency:0,heroUnlocks:[],mastery:0,pityBefore:{...next.pity},pityAfter:{...next.pity}};
  const collect=(id:string,source:'first_clear'|'chest')=>{const duplicate=next.ownedRelicIds.includes(id);if(duplicate){next.fragments+=loot.duplicatesToFragments;receipt.fragments+=loot.duplicatesToFragments;}else next.ownedRelicIds.push(id);receipt.relics.push({id,duplicate,source});};
  if(firstClear && mission) {
    next.clearedMissionIds.push(mission.id);if(mission.id==='M01'){next.tutorialComplete=true;next.unlockedSkillIds=skills.filter(skill=>skill.category==='common').map(skill=>skill.id);}
    if(mission.firstClearRelicId) collect(mission.firstClearRelicId,'first_clear');
    const fragments=Number((loot.missionFirstClearFragments as Record<string,number>)[mission.id] ?? 0);receipt.fragments+=fragments;next.fragments+=fragments;
    for(const id of mission.heroUnlockIds) if(!next.unlockedHeroIds.includes(id)){next.unlockedHeroIds.push(id);receipt.heroUnlocks.push(id);}
    next.masteryPoints+=mission.firstClearMasteryPoints;receipt.mastery=mission.firstClearMasteryPoints;
  }
  if(state.winner===0 && next.tutorialComplete) {
    let seed=c.lootSeed!;
    const count=mission && loot.chapterBossMissionIds.includes(mission.id) ? loot.chapterBossVictoryChests : loot.victoryChests;
    for(let i=0;i<count;i++){const rolled=rollChest(next,seed);seed=rolled.seed;collect(rolled.id,'chest');}
  }
  const eligibleLoss=state.winner!==0 && (state.tick>=rules.heroProficiency.lossEligibilityMinSec*30 || state.sides[0].kills>=rules.heroProficiency.lossEligibilityMinKills);
  receipt.proficiency=c.heroEnabled===false ? 0 : state.winner===0 ? rules.heroProficiency.winXp : eligibleLoss ? rules.heroProficiency.lossXp : 0;
  next.heroProficiency[c.loadout.heroId]+=receipt.proficiency;
  next.loadouts=next.unlockedHeroIds.map(id=>loadoutFor(next,id));next.revision++;
  next.rewardJournal.lastCommittedSequence=c.rewardSequence!;next.rewardJournal.completedMatchIds=[...j.completedMatchIds,c.matchId].slice(-loot.completedRewardIdsRetained);
  receipt.pityAfter={...next.pity};return {profile:validateProfile(next),receipt};
}
export function craft(profile:Profile,relicId:string):Profile {
  if(!profile.clearedMissionIds.includes('M03') || !catalog.relics[relicId] || profile.ownedRelicIds.includes(relicId) || profile.fragments<loot.targetCraftCostFragments) throw new Error('制作需通关第一章、四片碎片，且藏品尚未拥有');
  const next=structuredClone(profile);next.fragments-=loot.targetCraftCostFragments;next.ownedRelicIds.push(relicId);next.revision++;return next;
}
