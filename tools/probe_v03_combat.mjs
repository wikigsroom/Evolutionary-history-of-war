import {createServer} from 'vite';
const server=await createServer({server:{middlewareMode:true},appType:'custom'});
try{
  const {Battle}=await server.ssrLoadModule('/src/core/battle.ts');
  const {decide}=await server.ssrLoadModule('/src/core/ai.ts');
  const {builds}=await server.ssrLoadModule('/src/content/catalog.ts');
  for(const heroEnabled of [false,true]){
    const battle=new Battle({matchId:'V03-CORE-PROBE',heroEnabled,mode:'standard',seed:92,loadout:builds[0],enemyLoadout:builds[2],enemyProfileId:'AP01',difficultyId:'D02'});
    for(let i=0;i<30*300 && battle.state.winner===null;i++){
      battle.step();decide(battle,0);
      if(battle.state.tick%900===0)console.log(JSON.stringify({heroEnabled,seconds:battle.state.tick/30,sides:battle.state.sides.map(p=>({era:p.eraId,gold:Math.round(p.gold/1000),xp:Math.round(p.knowledge/1000),queue:p.queue.map(q=>[q.unitId,q.remaining]),kills:p.kills})),actors:battle.living().filter(e=>e.kind!=='base').map(e=>({id:e.id,unit:e.contentId,side:e.side,x:Math.round(e.x/100),hp:e.hp,phase:e.phase,yield:e.yielding,target:e.targetId}))}));
    }
  }
}finally{await server.close();}
