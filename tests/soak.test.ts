import { afterAll, expect, test } from 'vitest';
import { mkdirSync, writeFileSync } from 'node:fs';
import { Battle } from '../src/core/battle';
import { decide } from '../src/core/ai';
import { builds, eras, enemies } from '../src/content/catalog';
import { BODY_GAP, grounded } from '../src/core/occupancy';
import { position } from '../src/core/types';

const cases=eras.flatMap(era=>builds.map((build,index)=>({era,build,index,label:`${era.id} / ${build.id}`})));
const rows:Array<{era:string;build:string;seconds:number;winner:0|1|'draw'|null;peak:number}>=[];
test.each(cases)('$label 自动对战能结束且没有资源、人口或身体重叠错误',({era,build,index})=>{
    const battle=new Battle({matchId:`SOAK-${era.id}-${build.id}`,mode:'standard',seed:100+index,loadout:build,enemyLoadout:builds[(index+1)%builds.length],enemyProfileId:enemies[index].id,difficultyId:'D03',startingEraId:era.id,maximumEraId:era.id});
    let peak=0;
    while(battle.state.winner===null && battle.state.tick<30*18*60) {
      battle.step(); decide(battle,0);
      peak=Math.max(peak,battle.living().filter(entity=>entity.kind!=='base').length);
      if(battle.state.tick%300===0) {
        for(const side of battle.state.sides) expect(Math.min(side.gold,side.command,side.knowledge)).toBeGreaterThanOrEqual(0);
        expect(peak).toBeLessThanOrEqual(60);
        expect(battle.state.entities.every(entity=>Number.isFinite(entity.hp) && Number.isFinite(entity.x))).toBe(true);
        const bodies=battle.living().filter(grounded);
        let overlap:string|undefined;
        for(let i=0;i<bodies.length && !overlap;i++)for(let j=i+1;j<bodies.length;j++)if(Math.abs(bodies[i].x-bodies[j].x)<position(bodies[i].radius+bodies[j].radius+BODY_GAP)-1){overlap=`${bodies[i].contentId}/${bodies[j].contentId} @ ${battle.state.tick}`;break;}
        expect(overlap).toBeUndefined();
      }
    }
    expect(battle.state.winner).not.toBeNull();
    rows.push({era:era.id,build:build.id,seconds:Math.round(battle.state.tick/30),winner:battle.state.winner,peak});
},30000);
afterAll(()=>{
  const summary={automaticMatches:rows.length,maximumSeconds:Math.max(...rows.map(row=>row.seconds)),peakEntities:Math.max(...rows.map(row=>row.peak)),wins:rows.filter(row=>row.winner===0).length,losses:rows.filter(row=>row.winner===1).length,draws:rows.filter(row=>row.winner==='draw').length};
  mkdirSync('output/qa/v0.3',{recursive:true});writeFileSync('output/qa/v0.3/soak-tests.json',JSON.stringify({...summary,rows},null,2)+'\n');
  console.log(JSON.stringify(summary));
});
