import { catalog, rules } from '../content/catalog';
import { loadoutErrors } from '../core/loadout';
import type { BattleState,Entity,Hit,Loadout,Status } from '../core/types';
import { researchById } from '../core/research';
import { fighterProfile } from '../core/fighter-profiles';
import { nearestSpace } from '../core/occupancy';
import { activeItemIds, defaultActiveItems, defaultItemCooldowns } from '../core/active-items';

/** Validate the complete offline simulation before any imported record replaces local data. */
export function validateSnapshot(input: unknown): BattleState {
  const fail=():never=>{throw new Error('对局文件不完整或版本不兼容，当前存档已保留');};
  const integer=(n:unknown,min=0,max=Number.MAX_SAFE_INTEGER)=>typeof n==='number' && Number.isSafeInteger(n) && n>=min && n<=max;
  const finite=(n:unknown,min=0,max=Number.MAX_SAFE_INTEGER)=>typeof n==='number' && Number.isFinite(n) && n>=min && n<=max;
  const side=(n:unknown)=>n===0 || n===1;
  const id=(n:unknown)=>integer(n,1);
  const point=(n:unknown)=>finite(n,0,160000);
  const array=(a:unknown,max=2000)=>Array.isArray(a) && a.length<=max;
  const uniqueIds=(a:unknown,max=2000)=>array(a,max) && (a as number[]).every(id) && new Set(a as number[]).size===(a as number[]).length;
  const loadout=(l:Loadout)=>l && ['commonSkillIds','relicIds','talentIds'].every(k=>Array.isArray(l[k as keyof Loadout])) && loadoutErrors(l).length===0;
  const status=(s:Status)=>s && /^ST(0[1-9]|10)$/.test(s.id) && integer(s.until) && finite(s.magnitude) && side(s.sourceSide) && id(s.sourceId) && (s.charges===undefined || integer(s.charges)) && (s.nextTick===undefined || integer(s.nextTick)) && (s.eraMultiplier===undefined || finite(s.eraMultiplier,.001));
  const entity=(e:Entity)=>{
    if(!e || !id(e.id) || !side(e.side) || !['unit','hero','base','summon'].includes(e.kind) || !catalog.eras[e.eraId] || !point(e.x) || !finite(e.maxHp,1) || !finite(e.hp,0,e.maxHp) || !catalog.weapons[e.weaponId] || !['physical','pierce','blast','energy'].includes(e.damageType) || !['idle','move','windup','recover','dead','charge'].includes(e.phase) || typeof e.heavy!=='boolean' || typeof e.rushFirstHit!=='boolean' || typeof e.role!=='string')return false;
    if(e.kind==='unit' && !catalog.units[e.contentId] || e.kind==='hero' && !catalog.heroes[e.contentId] || e.kind==='base' && e.contentId!==`base-${e.side}` || e.kind==='summon' && e.contentId!=='summon-H04')return false;
    if(!['radius','attack','baseAttack','armor','energyResistance','range','speed','moveRemainder','runDistance'].every(k=>finite(e[k as keyof Entity])) || !finite(e.attackBonus,-.9,.3) || !['period','windup','nextAttack','releaseAt','bornTick','rushUntil','staggerImmuneUntil','counterReadyAt'].every(k=>integer(e[k as keyof Entity])))return false;
    if(e.targetId!==null && !id(e.targetId) || e.previousX!==undefined && !point(e.previousX) || e.expiresAt!==undefined && !integer(e.expiresAt) || !array(e.statuses,64) || !e.statuses.every(status) || !array(e.shields,128) || e.shields.some(s=>!s || !finite(s.hp) || !integer(s.until)))return false;
    if(e.yielding!==undefined && typeof e.yielding!=='boolean' || e.settlementPending!==undefined && typeof e.settlementPending!=='boolean' || e.rushArmed!==undefined && typeof e.rushArmed!=='boolean' || e.attackStartedAt!==undefined && !integer(e.attackStartedAt))return false;
    if(e.garrisoned!==undefined && typeof e.garrisoned!=='boolean' || e.garrisonHealRemainder!==undefined && !integer(e.garrisonHealRemainder,0,29999))return false;
    if(e.garrisoned && (e.kind!=='hero' || e.charge || e.yielding || e.settlementPending || e.x!==rules.world.basePositions[e.side]*100 || e.releaseAt!==0 || e.targetId!==null || e.phase!=='idle'))return false;
    if(e.charge && (!integer(e.charge.until) || !point(e.charge.destination) || !uniqueIds(e.charge.hitIds,6) || !catalog.skills[e.charge.skillId] || !finite(e.charge.distance) || !id(e.charge.castId) || !finite(e.charge.raw) || !finite(e.charge.knockback)))return false;
    for(const buff of [e.attackBuff,e.moveBuff])if(buff && (!integer(buff.until) || !finite(buff.bonus,-.9,1)))return false;
    return true;
  };
  const hit=(h:Hit)=>h && id(h.sourceId) && side(h.side) && id(h.targetId) && finite(h.raw) && ['physical','pierce','blast','energy'].includes(h.damageType) && typeof h.projectile==='boolean' && (h.skillId===undefined || !!catalog.skills[h.skillId]) && (h.castId===undefined || id(h.castId)) && (h.conditional===undefined || finite(h.conditional)) && (h.statuses===undefined || array(h.statuses,64) && h.statuses.every(status)) && (!h.displacement || finite(h.displacement.distance) && (h.displacement.center===undefined || finite(h.displacement.center,0,1600))) && (h.conductive===undefined || typeof h.conductive==='boolean') && (h.isRush===undefined || typeof h.isRush==='boolean');
  try {
    const s=structuredClone(input) as BattleState,c=s?.config;
    const legacy=s?.contentVersion==='0.1.0';
    const footprintChanged=s.entities.some(e=>e.kind!=='base' && e.radius!==fighterProfile(e.contentId).radius);
    if(legacy){
      s.contentVersion=rules.designVersion; s.ageStrikes=[];
      if(c)c.heroEnabled=true;
      if(Array.isArray(s.sides))for(const p of s.sides){p.research={};p.ageSpecialReadyAt=0;}
    }
    if(!s || s.contentVersion!==rules.designVersion || !c || !array(s.sides,2) || s.sides.length!==2 || !array(s.entities,200) || !integer(s.tick) || !id(s.nextId) || !integer(s.rng,0,4294967295) || typeof s.paused!=='boolean' || ![null,0,1,'draw'].includes(s.winner) || !integer(s.lastActionSequence,-1))fail();
    for (const player of s.sides) {
      if (!player.activeItems) player.activeItems = defaultActiveItems();
      if (!player.itemCooldowns) player.itemCooldowns = defaultItemCooldowns();
    }
    if(!['campaign','standard','trial','challenge'].includes(c.mode) || !catalog.enemies[c.enemyProfileId] || !rules.difficulty.some(d=>d.id===c.difficultyId) || typeof c.matchId!=='string' || !c.matchId || !integer(c.seed,0,4294967295) || !loadout(c.loadout) || !loadout(c.enemyLoadout))fail();
    if(c.heroEnabled!==undefined && typeof c.heroEnabled!=='boolean')fail();
    if(c.missionId && (c.mode!=='campaign' || !catalog.missions[c.missionId]) || c.startingEraId && !catalog.eras[c.startingEraId] || c.maximumEraId && !catalog.eras[c.maximumEraId])fail();
    if(c.profileId!==undefined && (typeof c.profileId!=='string' || !c.profileId) || c.rewardSequence!==undefined && !integer(c.rewardSequence,1) || c.lootSeed!==undefined && !integer(c.lootSeed,0,4294967295))fail();
    if(!s.entities.every(entity) || new Set(s.entities.map(e=>e.id)).size!==s.entities.length)fail();
    for(const n of [0,1]){
      const p=s.sides[n];
      if(!p || !catalog.eras[p.eraId] || !loadout(p.loadout) || !array(p.remainders,3) || p.remainders.length!==3 || p.remainders.some(v=>!integer(v,0,29)) || !['gold','knowledge','command','stanceReadyAt','heroRespawnAt','rushDeadline','rushSpawns','kills','comboHits'].every(k=>integer(p[k as keyof typeof p])) || !['cover','rush','retreat'].includes(p.stance) || typeof p.awaitingUpgrade!=='boolean' || !integer(p.unlockedSlots,1,3))fail();
      if(s.entities.filter(e=>e.kind==='base' && e.side===n).length!==1 || s.entities.filter(e=>e.kind==='hero' && e.side===n && e.hp>0).length>1)fail();
      if(!p.cooldowns || Array.isArray(p.cooldowns) || Object.entries(p.cooldowns).some(([k,v])=>!catalog.skills[k] || !integer(v)) || !array(p.upgrades,5) || new Set(p.upgrades).size!==p.upgrades.length || p.upgrades.some(k=>!catalog.upgrades[k]))fail();
      if(!p.research || Array.isArray(p.research) || Object.entries(p.research).some(([k,v])=>!researchById[k] || !integer(v,0,researchById[k].max)) || !integer(p.ageSpecialReadyAt))fail();
      if(!p.activeItems || activeItemIds.some(id=>!integer(p.activeItems[id],0,20)) || !p.itemCooldowns || activeItemIds.some(id=>!integer(p.itemCooldowns[id],0)))fail();
      if(!array(p.queue,5) || new Set(p.queue.map(q=>q.id)).size!==p.queue.length || p.queue.some(q=>!q || !id(q.id) || !catalog.units[q.unitId] || catalog.units[q.unitId].eraId!==q.eraId || !integer(q.paid) || !integer(q.duration,1) || !integer(q.remaining,0,q.duration) || !integer(q.progressUsed,0,Math.floor(q.duration*.5)) || !array(q.advancedBy,20) || new Set(q.advancedBy).size!==q.advancedBy.length || q.advancedBy.some(k=>typeof k!=='string')))fail();
      if(!array(p.turrets,3) || new Set(p.turrets.map(t=>t.slot)).size!==p.turrets.length || p.turrets.some(t=>!t || !id(t.id) || !catalog.turrets[t.contentId] || !integer(t.paid) || !integer(t.nextAttack) || !integer(t.slot,0,p.unlockedSlots-1)))fail();
    }
    if(!array(s.projectiles,2000) || !array(s.scheduledSkills,200) || !array(s.pendingHits,2000) || !array(s.events,10000) || !array(s.processedActionIds,200) || new Set(s.processedActionIds).size!==s.processedActionIds.length || s.processedActionIds.some((v,i)=>!integer(v,0,s.lastActionSequence) || i>0 && v<=s.processedActionIds[i-1]) || !array(s.bossThresholds,2) || s.bossThresholds.some(v=>v!==.65 && v!==.3) || !integer(s.bossPending,0,2) || !s.castTargets || Array.isArray(s.castTargets))fail();
    for(const p of s.projectiles)if(!p || !id(p.id) || !id(p.sourceId) || !side(p.side) || !point(p.x) || !point(p.previousX) || !id(p.targetId) || !finite(p.speed) || !finite(p.moveRemainder) || !integer(p.expiresAt) || !hit(p.hit) || !finite(p.splash) || !integer(p.maxTargets,1,6) || !catalog.weapons[p.weaponId] || typeof p.suppress!=='boolean' || ![-1,1].includes(p.direction) || !integer(p.pierceRemaining,0,6) || !uniqueIds(p.hitIds,6))fail();
    for(const a of s.scheduledSkills)if(!a || !id(a.id) || !side(a.side) || !id(a.sourceId) || !catalog.skills[a.skillId] || !finite(a.x,0,1600) || a.targetId!==undefined && !id(a.targetId) || !integer(a.due) || !integer(a.remaining,0,20) || !integer(a.spacing) || !finite(a.eraMultiplier,.001) || !uniqueIds(a.visited,6) || !entity(a.sourceSnapshot) || a.refunded!==undefined && typeof a.refunded!=='boolean' || a.fieldUntil!==undefined && !integer(a.fieldUntil) || a.fieldDamage!==undefined && !finite(a.fieldDamage) || a.fieldUntil!==undefined && a.fieldDamage===undefined)fail();
    if(!s.pendingHits.every(hit))fail();
    if(!array(s.ageStrikes,40) || s.ageStrikes.some(a=>!a || !id(a.id) || !side(a.side) || !catalog.eras[a.eraId] || !finite(a.x,140,1460) || !integer(a.due) || !integer(a.remaining,1,4)))fail();
    for(const e of s.events)if(!e || !id(e.id) || !integer(e.tick,0,s.tick) || typeof e.type!=='string' || !finite(e.x,0,1600) || !side(e.side) || e.targetId!==undefined && !id(e.targetId) || e.amount!==undefined && !finite(e.amount) || e.absorbed!==undefined && !finite(e.absorbed) || e.skillId!==undefined && !catalog.skills[e.skillId] || e.sourceId!==undefined && !id(e.sourceId) || e.weaponId!==undefined && !catalog.weapons[e.weaponId] || e.fromX!==undefined && !finite(e.fromX,0,1600) || e.damageType!==undefined && !['physical','pierce','blast','energy'].includes(e.damageType))fail();
    for(const [key,g] of Object.entries(s.castTargets))if(!id(Number(key)) || !g || !integer(g.until) || !uniqueIds(g.ids,6))fail();
    const allIds=[...s.entities.map(e=>e.id),...s.projectiles.map(p=>p.id),...s.scheduledSkills.map(a=>a.id),...s.ageStrikes.map(a=>a.id),...s.events.map(e=>e.id),...s.sides.flatMap(p=>[...p.queue.map(q=>q.id),...p.turrets.map(t=>t.id)])];
    if(allIds.some(n=>n>=s.nextId))fail();
    if(legacy || footprintChanged){
      const fighters=s.entities.filter(e=>e.kind!=='base');
      s.entities=s.entities.filter(e=>e.kind==='base');
      fighters.sort((a,b)=>a.side-b.side || (a.side===0 ? b.x-a.x : a.x-b.x) || a.id-b.id);
      for(const fighter of fighters){
        fighter.radius=fighterProfile(fighter.contentId).radius;
        if(fighter.kind==='unit'){
          fighter.role=catalog.units[fighter.contentId].role;
          fighter.heavy=catalog.units[fighter.contentId].heavy;
          if(fighter.heavy)s.sides[fighter.side].research['heavy-unlock']=1;
        }
        if(fighter.hp>0 && !fighter.charge && !fighter.garrisoned){
          const x=nearestSpace(s,fighter.x,fighter.radius);
          if(x===undefined){fighter.yielding=true;fighter.settlementPending=true;}
          else{fighter.x=x;fighter.previousX=x;}
        }
        s.entities.push(fighter);
      }
      for(const p of s.sides)if(p.queue.some(q=>catalog.units[q.unitId].heavy))p.research['heavy-unlock']=1;
    }
    return s;
  }catch{return fail();}
}
