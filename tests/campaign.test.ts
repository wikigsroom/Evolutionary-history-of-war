import {expect,test} from 'vitest';
import {mkdirSync,writeFileSync} from 'node:fs';
import {Battle} from '../src/core/battle';
import {catalog,missions} from '../src/content/catalog';
import {fitLoadout,loadoutErrors} from '../src/core/loadout';
import {loadoutFor,settle,startingProfile} from '../src/core/profile';
import {playerPolicy} from '../tools/v03_player_policy';

test('新档通过十五关合法战斗，逐关真实结算并解锁全部指挥官',()=>{
  let profile=startingProfile('CAMPAIGN-SIMULATION');const rows=[];
  for(const mission of missions){
    let cleared=false;
    for(let attempt=0;attempt<1 && !cleared;attempt++){
      const heroId='H01';
      const player=loadoutFor(profile,heroId),enemyProfile=catalog.enemies[mission.enemyProfileId];
      const enemy=fitLoadout(catalog.builds[enemyProfile.buildId],profile.masteryPoints,profile.unlockedSkillIds,profile.ownedRelicIds);
      expect(loadoutErrors(player,profile.masteryPoints)).toEqual([]);
      profile.rewardJournal.lastReservedSequence++;
      const battle=new Battle({matchId:`${mission.id}-${attempt}`,profileId:profile.profileId,rewardSequence:profile.rewardJournal.lastReservedSequence,lootSeed:73+attempt,heroEnabled:false,mode:'campaign',missionId:mission.id,seed:92+attempt,loadout:player,enemyLoadout:enemy,enemyProfileId:enemyProfile.id,difficultyId:'D01'});
      while(battle.state.winner===null && battle.state.tick<30*18*60){
        battle.step();playerPolicy(battle);
      }
      expect(battle.state.winner).toBe(0);
      rows.push({mission:mission.id,attempt,heroId,winner:battle.state.winner,seconds:Math.round(battle.state.tick/30),era:battle.state.sides[0].eraId});
      profile=settle(profile,battle.state).profile;cleared=profile.clearedMissionIds.includes(mission.id);
    }
    expect(cleared,JSON.stringify(rows)).toBe(true);
  }
  mkdirSync('output/qa/v0.3',{recursive:true});writeFileSync('output/qa/v0.3/campaign-combat.json',JSON.stringify({rows,cleared:profile.clearedMissionIds,heroes:profile.unlockedHeroIds,skills:profile.unlockedSkillIds,mastery:profile.masteryPoints},null,2));
  expect(profile.tutorialComplete).toBe(true);expect(profile.unlockedHeroIds).toHaveLength(6);expect(profile.clearedMissionIds).toHaveLength(15);
},30000);
