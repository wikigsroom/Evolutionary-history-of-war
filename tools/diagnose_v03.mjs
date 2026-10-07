import {createServer} from 'vite';
import {mkdirSync,writeFileSync} from 'node:fs';
const server=await createServer({server:{middlewareMode:true},appType:'custom'});
try{
  const {Battle}=await server.ssrLoadModule('/src/core/battle.ts');
  const {playerPolicy}=await server.ssrLoadModule('/tools/v03_player_policy.ts');
  const {builds,catalog}=await server.ssrLoadModule('/src/content/catalog.ts');
  const {startingProfile,loadoutFor}=await server.ssrLoadModule('/src/core/profile.ts');
  const {grounded}=await server.ssrLoadModule('/src/core/occupancy.ts');
  const profile=startingProfile('CAMPAIGN-DIAGNOSE'),mission=catalog.missions[process.argv[2]??'M01'];
  const battle=new Battle({matchId:'DIAGNOSE',heroEnabled:false,mode:'campaign',missionId:mission.id,seed:92,loadout:loadoutFor(profile,'H01'),enemyLoadout:builds[2],enemyProfileId:mission.enemyProfileId,difficultyId:'D01'});
  const report=[];
  while(battle.state.winner===null && battle.state.tick<30*900){
    battle.step();playerPolicy(battle);
    if(battle.state.tick%1800!==0)continue;
    report.push({seconds:battle.state.tick/30,base:battle.state.entities.filter(e=>e.kind==='base').map(e=>({side:e.side,hp:e.hp,maxHp:e.maxHp})),sides:battle.state.sides.map(s=>({gold:Math.floor(s.gold/1000),knowledge:Math.floor(s.knowledge/1000),era:s.eraId,research:s.research,towers:s.turrets,queue:s.queue})),army:battle.living().filter(e=>e.kind!=='base').map(e=>({id:e.id,side:e.side,type:e.contentId,x:e.x/100,radius:e.radius,range:e.range,hp:e.hp,phase:e.phase,target:e.targetId,grounded:grounded(e)}))});
  }
  mkdirSync('output/qa/v0.3',{recursive:true});writeFileSync('output/qa/v0.3/diagnose-'+mission.id+'.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify({mission:mission.id,winner:battle.state.winner,seconds:battle.state.tick/30,...report.at(-1)},null,2));
}finally{await server.close();}
