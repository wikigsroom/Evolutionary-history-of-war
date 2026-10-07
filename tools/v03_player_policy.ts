// QA player uses only actions exposed in the shipping UI, without granting resources.
import {catalog,units} from '../src/content/catalog';
import {worldX,value,type Side} from '../src/core/types';
import {ageSpecials} from '../src/core/age-specials';
import type {Battle} from '../src/core/battle';
export function playerPolicy(battle:Battle,side:Side=0){
  if(battle.state.tick%15!==0 || battle.state.winner!==null || battle.state.paused)return;
  const player=battle.state.sides[side],era=catalog.eras[player.eraId],opponent=(1-side) as Side;
  const soldiers=battle.living(side).filter(e=>e.kind==='unit'),foes=battle.living(opponent).filter(e=>e.kind!=='base');
  if(era.nextEvolutionKnowledge!==null && player.eraId!==battle.maxEraId && player.knowledge>=era.nextEvolutionKnowledge*1000)battle.act({type:'evolve',side});
  const hero=battle.hero(side);
  if(hero){
    const front=soldiers.sort((a,b)=>side===0 ? b.x-a.x : a.x-b.x)[0];
    const ratio=hero.hp/hero.maxHp;
    const withdrawing=ratio<.2 || hero.garrisoned && ratio<.85 || player.stance==='retreat' && ratio<.75;
    battle.act({type:'stance',side,stance:withdrawing ? 'retreat' : front && Math.abs(front.x-hero.x)<16000 ? 'rush' : 'cover'});
    for(const id of [catalog.heroes[hero.contentId].signatureSkillId,...player.loadout.commonSkillIds]){
      if(hero.garrisoned)break;
      const skill=catalog.skills[id],range=skill.targetMode==='direction_self' ? value(skill.effects,'chargeDistance')+value(battle.specification(side),'chargeRangeAdd') : skill.targetMode==='self' ? hero.range+90 : battle.skillRange(side,id);
      if((player.cooldowns[id]??0)>battle.state.tick || player.command<battle.skillCost(side,id)*1000)continue;
      const target=foes.filter(e=>Math.abs(e.x-hero.x)<=range*100 && (skill.targetMode!=='direction_self' || (e.x-hero.x)*(side===0 ? 1 : -1)>=0)).sort((a,b)=>Math.abs(a.x-hero.x)-Math.abs(b.x-hero.x))[0];
      const nearby=soldiers.filter(e=>Math.abs(e.x-hero.x)<=16000);
      if(skill.targetMode==='self' || skill.targetMode==='direction_self'){
        if(target || hero.hp/hero.maxHp<.6)battle.act({type:'cast',side,skillId:id,x:worldX(hero)});
      }else if(skill.targetMode.startsWith('ally')){
        const ally=[hero,...nearby].sort((a,b)=>a.hp/a.maxHp-b.hp/b.maxHp)[0];
        if(ally && (nearby.length>=2 || ally.hp/ally.maxHp<.55))battle.act({type:'cast',side,skillId:id,x:worldX(ally),targetId:ally.id});
      }else if(target){
        if(id==='HS04')battle.act({type:'cast',side,skillId:id,x:worldX(hero)+(side===0 ? 80 : -80)});
        else battle.act({type:'cast',side,skillId:id,x:worldX(target),targetId:target.id});
      }
    }
  }
  const special=ageSpecials[player.eraId as keyof typeof ageSpecials];
  const cluster=[...foes].sort((a,b)=>foes.filter(e=>Math.abs(e.x-b.x)<=special.radius*100).length-foes.filter(e=>Math.abs(e.x-a.x)<=special.radius*100).length)[0];
  const assault=cluster && Math.abs(cluster.x-battle.base(opponent).x)<24000;
  if(cluster && player.ageSpecialReadyAt<=battle.state.tick && player.knowledge>=special.cost*1000 && (player.eraId===battle.maxEraId || assault || foes.filter(e=>Math.abs(e.x-cluster.x)<=special.radius*100).length>=3) && (player.eraId===battle.maxEraId || battle.base(side).hp/battle.base(side).maxHp<.5)){
    battle.act({type:'ageSpecial',side,x:worldX(cluster)});
  }
  if(player.queue.length>=2)return;
  const available=units.filter(u=>u.eraId===player.eraId);
  const queued=player.queue.map(q=>catalog.units[q.unitId]);
  const count=(role:string)=>soldiers.filter(e=>e.role===role).length+queued.filter(u=>u.role===role).length;
  const frontCount=count('front')+count('heavy'),rangeCount=count('ranged');
  let unit=available.find(u=>u.role==='front')!;
  let needSoldier=true;
  if(frontCount>=1){
    if(count('anti_armor')<1 || foes.some(e=>e.heavy) && count('anti_armor')<2)unit=available.find(u=>u.role==='anti_armor')!;
    else if(rangeCount>=2 && battle.heavyUnlocked(side) && count('heavy')<1)unit=available.find(u=>u.heavy)!;
    else if(rangeCount<3)unit=available.find(u=>u.role==='ranged')!;
    else if(frontCount<2)unit=available.find(u=>u.role==='front')!;
    else if(battle.heavyUnlocked(side) && count('heavy')<1)unit=available.find(u=>u.heavy)!;
    else needSoldier=false;
  }
  if(soldiers.length>=4 && (!needSoldier || player.gold>=battle.unitCost(side,unit.id)*2500)){
    if(!battle.heavyUnlocked(side))battle.act({type:'research',side,researchId:'heavy-unlock'});
    else if((player.research['ranged-attack']??0)<2)battle.act({type:'research',side,researchId:'ranged-attack'});
    else if((player.research['ranged-range']??0)<3)battle.act({type:'research',side,researchId:'ranged-range'});
    else if((player.research['front-armor']??0)<2)battle.act({type:'research',side,researchId:'front-armor'});
    else if((player.research['heavy-attack']??0)<2)battle.act({type:'research',side,researchId:'heavy-attack'});
  }
  if(needSoldier)battle.act({type:'train',side,unitId:unit.id});
}
