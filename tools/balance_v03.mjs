import {createServer} from 'vite';
import {mkdirSync,writeFileSync} from 'node:fs';
const server=await createServer({server:{middlewareMode:true},appType:'custom'});
try{
  const {Battle}=await server.ssrLoadModule('/src/core/battle.ts');
  const {playerPolicy}=await server.ssrLoadModule('/tools/v03_player_policy.ts');
  const {builds,catalog,missions}=await server.ssrLoadModule('/src/content/catalog.ts');
  const {fitLoadout}=await server.ssrLoadModule('/src/core/loadout.ts');
  const {startingProfile,loadoutFor,settle}=await server.ssrLoadModule('/src/core/profile.ts');
  const report={standard:[],campaign:[]};
  for(const heroEnabled of process.argv.includes('--campaign') ? [] : [false,true])for(const seed of [31,73,109]){
    const profile=startingProfile('STANDARD-BALANCE');
    const battle=new Battle({matchId:'BALANCE-'+seed,heroEnabled,mode:'standard',seed,loadout:loadoutFor(profile,'H01'),enemyLoadout:fitLoadout(builds[2],2,['S01','S02'],[]),enemyProfileId:'AP01',difficultyId:'D02'});
    const eraTimes={A1:0};let maxBodies=0;
    while(battle.state.winner===null && battle.state.tick<30*900){battle.step();playerPolicy(battle);const era=battle.state.sides[0].eraId;eraTimes[era]??=Math.round(battle.state.tick/30);maxBodies=Math.max(maxBodies,battle.living().length-2);}
    const row={heroEnabled,seed,winner:battle.state.winner,seconds:Math.round(battle.state.tick/30),eras:eraTimes,kills:battle.state.sides[0].kills,maxBodies,baseHp:[battle.base(0).hp,battle.base(1).hp],army:battle.living().filter(e=>e.kind!=='base').map(e=>({side:e.side,type:e.contentId,x:e.x/100,hp:e.hp,phase:e.phase})),research:battle.state.sides.map(s=>s.research)};report.standard.push(row);console.log(JSON.stringify({...row,army:undefined,research:undefined}));
  }
  let profile=startingProfile('CAMPAIGN-BALANCE');
  for(const mission of process.argv.includes('--standard') ? [] : missions){
    let won=false;
    for(const heroEnabled of [false,true]){
      const enemy=fitLoadout(catalog.builds[catalog.enemies[mission.enemyProfileId].buildId],profile.masteryPoints,profile.unlockedSkillIds,profile.ownedRelicIds);
      const heroId=profile.unlockedHeroIds.includes('H02') ? 'H02' : 'H01';
      profile.rewardJournal.lastReservedSequence++;
      const battle=new Battle({matchId:mission.id+'-'+heroEnabled,profileId:profile.profileId,rewardSequence:profile.rewardJournal.lastReservedSequence,lootSeed:73,mode:'campaign',missionId:mission.id,heroEnabled,seed:92,loadout:loadoutFor(profile,heroId),enemyLoadout:enemy,enemyProfileId:mission.enemyProfileId,difficultyId:'D01'});
      const eraTimes={};while(battle.state.winner===null && battle.state.tick<30*900){battle.step();playerPolicy(battle);const era=battle.state.sides[0].eraId;eraTimes[era]??=Math.round(battle.state.tick/30);}
      const row={mission:mission.id,heroEnabled,winner:battle.state.winner,seconds:Math.round(battle.state.tick/30),eras:eraTimes,kills:battle.state.sides[0].kills};report.campaign.push(row);console.log(JSON.stringify(row));
      if(battle.state.winner!==null)profile=settle(profile,battle.state).profile;
      if(battle.state.winner===0){won=true;break;}
    }
    if(!won)break;
  }
  const suffix=process.argv.includes('--standard') ? '-standard' : process.argv.includes('--campaign') ? '-campaign' : '';
  mkdirSync('output/qa/v0.3',{recursive:true});writeFileSync('output/qa/v0.3/balance'+suffix+'.json',JSON.stringify(report,null,2)+'\n');
}finally{await server.close();}
