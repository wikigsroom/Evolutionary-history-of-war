import {Battle} from '../core/battle';
import {applyHits,fire,updateProjectiles} from '../core/combat';
import {builds,catalog,eras,heroes,units} from '../content/catalog';
import {position,worldX,type Entity,type Action} from '../core/types';
import {BattleCamera} from '../presentation/battle-camera';
import type {SceneBridge} from '../presentation/battle-scene';
import './review.css';
import {MotionRecorder} from './motion-recorder';
import {animationSheets} from '../presentation/animation';
import {fighterProfile} from '../core/fighter-profiles';

/** Explicit development gallery; never reads, writes, unlocks or rewards a player profile. */
export function createReviewBridge():SceneBridge{
  let era='A3',group='units',side:0|1=0,mode='idle',damage='intact',live=false,accumulator=0,age=0,paused=true,speed=1;
  const camera=new BattleCamera(),root=document.getElementById('interface')!;
  let battle:Battle,actors:Entity[]=[];
  let recordStatus='';
  const recorder=new MotionRecorder(message=>{recordStatus=message;const label=document.getElementById('record-status');if(label)label.textContent=message;const button=root.querySelector<HTMLElement>('[data-review=record]');if(button)button.textContent=recorder.running ? '停止并保存' : '录制画面';});
  const probeAction=(action:Action)=>{battle.state.paused=false;const result=battle.act(action);battle.state.paused=paused;return result;};
  const rebuild=()=>{
    recorder.stop();
    battle=new Battle({matchId:'DEVELOPMENT-VISUAL-REVIEW',mode:'trial',seed:1234,loadout:builds[0],enemyLoadout:builds[2],enemyProfileId:'AP01',difficultyId:'D02',startingEraId:era});
    battle.state.entities=battle.state.entities.filter(e=>e.kind==='base');battle.state.paused=paused;actors=[];age=0;accumulator=0;
    const rows=group==='heroes' ? heroes : group==='specials' ? units.filter(u=>u.id.endsWith('5')) : units.filter(u=>u.eraId===era);
    // Keep the six-hero evidence set inside the same 0–1000 review viewport so
    // both faction recordings prove every hero's authored pose. Unit spacing
    // remains intentionally wider because mounted units need their footprint.
    rows.forEach((row,index)=>{const actor=battle.spawn(side,row.id,'eraId' in row ? String(row.eraId) : era,group==='heroes' ? 'hero' : 'unit');actor.x=position(group==='heroes' ? 125+index*150 : group==='specials' ? 155+index*168 : 165+index*168);actor.previousX=actor.x;actor.bornTick=-60;actors.push(actor);});
    for(const base of battle.state.entities.filter(e=>e.kind==='base'))base.hp=Math.round(base.maxHp*({intact:1,worn:.6,critical:.3,ruin:0}[damage] ?? 1));
    if(live){actors=[];for(const s of [0,1] as const){battle.spawn(s,battle.state.sides[s].loadout.heroId,era,'hero').x=position(s===0 ? 430 : 1030);units.filter(u=>u.eraId===era).forEach((u,index)=>battle.spawn(s,u.id,era).x=position(s===0 ? 480-index*65 : 980+index*65));}camera.jump('front',battle);}
    root.innerHTML=`<section id="page" hidden></section><section id="overlay" hidden></section><section id="hud"><header class="review-header"><div><strong>动作与建筑检视</strong><span>开发场景 · 不修改玩家档案 · ${group==='heroes' ? '六名指挥官' : group==='specials' ? '五名时代特种单位' : catalog.eras[era].name+'四兵种'}</span></div><nav>${eras.map(e=>`<button data-review="era" data-value="${e.id}" aria-pressed="${e.id===era}">${e.name}</button>`).join('')}</nav></header><footer class="battle-bottom review-controls"><div><span>角色与阵营</span><button data-review="group" data-value="units" aria-pressed="${group==='units'}">时代兵种</button><button data-review="group" data-value="specials" aria-pressed="${group==='specials'}">五名特种</button><button data-review="group" data-value="heroes" aria-pressed="${group==='heroes'}">六名指挥官</button><button data-review="side" aria-pressed="${side===1}">${side===1 ? '定序军' : '续火盟'}</button><button data-review="live">交战实测</button><button data-review="view" data-value="left">查看左半战场</button><button data-review="view" data-value="right">查看右半战场</button></div><div><span>动作</span>${[['idle','待机'],['move','行进'],['attack','攻击循环'],['hit','受击'],['charge','冲锋'],['dead','死亡']].map(([id,title])=>`<button data-review="mode" data-value="${id}" aria-pressed="${mode===id}">${title}</button>`).join('')}</div><div><span>基地</span>${[['intact','完好'],['worn','裂损'],['critical','重损'],['ruin','残骸']].map(([id,title])=>`<button data-review="damage" data-value="${id}" aria-pressed="${damage===id}">${title}</button>`).join('')}<button data-review="impact">基地受击</button><button data-review="upgrade">进化</button><button data-review="tower">建塔</button></div><div><span>逐帧检视</span><button data-review="freeze">${paused ? '继续动作' : '冻结动作'}</button><button data-review="step" data-value="1">前进 1 帧</button><button data-review="step" data-value="6">前进 6 帧</button></div><div class="review-status" role="status" id="review-status"></div></footer></section>`;
  };
  root.addEventListener('click',event=>{
    const button=(event.target as HTMLElement).closest<HTMLElement>('[data-review]');if(!button)return;
    const action=button.dataset.review,value=button.dataset.value;
    if(action==='record'){
      if(recorder.running){recorder.stop();button.textContent='录制画面';return;}
      if(recorder.busy)return;
      if(mode==='sequence'){age=0;battle.state.tick=0;battle.state.projectiles=[];battle.state.events=[];for(const actor of actors){actor.hp=actor.maxHp;actor.phase='idle';actor.bornTick=0;actor.releaseAt=0;actor.statuses=[];}}
      paused=false;battle.state.paused=false;root.querySelector('[data-review=freeze]')!.textContent='冻结动作';
      const rows=battle.state.entities.filter(actor=>actor.kind!=='base');
      const sources=Object.fromEntries(rows.map(actor=>[actor.contentId,{sourceSha256:animationSheets[actor.contentId]?.sourceSha256 ?? null,atlasSha256:animationSheets[actor.contentId]?.atlasSha256?.[side===0 ? 'own' : 'enemy'] ?? null,representation:animationSheets[actor.contentId] ? 'authored_pose' : 'legacy_rig',bodyRadius:actor.radius,muzzle:fighterProfile(actor.contentId).muzzle,hit:fighterProfile(actor.contentId).hit}]));
      const visibleActorIds=rows.filter(actor=>worldX(actor)-120>=camera.x && worldX(actor)+120<=camera.x+camera.width).map(actor=>actor.contentId);
      recorder.start({era,group,side,mode,live,speed,tickStart:battle.state.tick,sources,visibleActorIds,viewport:{x:camera.x,width:camera.width},phaseSchedule:mode==='sequence' ? {idle:36,walk:90,attack:90,hurt:15,death:21} : undefined});
      if(recorder.running)button.textContent='停止并保存';return;
    }
    // Any gallery change ends the current evidence clip before altering its context.
    recorder.stop();
    if(action==='speed'){recorder.stop();speed=Number(value);root.querySelectorAll<HTMLElement>('[data-review=speed]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.value)===speed)));return;}
    if(action==='era'){era=value!;live=false;rebuild();}
    else if(action==='group'){group=value!;live=false;rebuild();}
    else if(action==='side'){side=side===0 ? 1 : 0;live=false;rebuild();}
    else if(action==='mode'){mode=value!;live=false;rebuild();if(mode==='dead')for(const actor of actors)battle.kill(actor);}
    else if(action==='damage'){damage=value!;live=false;rebuild();}
    else if(action==='freeze'){paused=!paused;battle.state.paused=paused;button.textContent=paused ? '继续动作' : '冻结动作';}
    else if(action==='step'){paused=true;battle.state.paused=true;for(let i=0;i<Number(value);i++)advance(1000/30,true);root.querySelector('[data-review=freeze]')!.textContent='继续动作';}
    else if(action==='live'){live=true;rebuild();}
    else if(action==='view'){camera.jump(value==='left' ? 'ally' : 'enemy',battle);}
    else if(action==='impact'){const base=battle.base(0);battle.state.pendingHits.push({sourceId:battle.base(1).id,side:1,targetId:base.id,raw:base.maxHp*.06,damageType:era==='A5' ? 'energy' : 'blast',projectile:true});applyHits(battle);}
    else if(action==='upgrade'){if(era!=='A5'){battle.state.sides[0].knowledge=10000000;probeAction({type:'evolve',side:0});probeAction({type:'upgrade',side:0,upgradeId:`R${battle.state.sides[0].eraId[1]}1`});era=battle.state.sides[0].eraId;}}
    else if(action==='tower'){battle.state.sides[0].gold=1000000;probeAction({type:'turret',side:0,turretId:`TR${battle.state.sides[0].eraId[1]}1`,slot:0});if(!battle.living(1).some(e=>e.kind!=='base'))battle.spawn(1,`U${era[1]}1`,era).x=position(290);}
    root.querySelectorAll<HTMLElement>('[data-review=mode]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.value===mode)));
  });
  rebuild();
  const insertRecordingControls=()=>{
    const footer=root.querySelector('.review-controls');if(!footer || root.querySelector('[data-review=record]'))return;
    const controls=document.createElement('div');controls.innerHTML='<span>录像审查</span><button data-review="mode" data-value="sequence">五段动作</button><button data-review="speed" data-value="1" aria-pressed="true">原速 1×</button><button data-review="speed" data-value="0.25" aria-pressed="false">慢放 0.25×</button><button data-review="record">录制画面</button><span id="record-status" role="status"></span>';footer.append(controls);
    controls.querySelector('#record-status')!.textContent=recordStatus;
    controls.querySelectorAll<HTMLElement>('[data-review=speed]').forEach(button=>button.setAttribute('aria-pressed',String(Number(button.dataset.value)===speed)));
  };
  insertRecordingControls();
  const advance=(delta:number,force=false)=>{
    insertRecordingControls();
    if(force)accumulator=1000/30;else if(!paused)accumulator+=Math.min(delta*speed,120);let steps=0;
    while(accumulator>=1000/30 && steps++<4){
      accumulator-=1000/30;age++;
      if(live){battle.state.paused=false;battle.step();battle.state.paused=paused;recorder.progress({tickEnd:battle.state.tick});continue;}
      battle.state.tick++;
      const sequencePosition=age%252;
      const effectiveMode=mode==='sequence' ? sequencePosition<36 ? 'idle' : sequencePosition<126 ? 'move' : sequencePosition<216 ? 'attack' : sequencePosition<231 ? 'hit' : 'dead' : mode;
      for(const actor of actors){
        if(mode==='sequence' && sequencePosition===0){actor.hp=actor.maxHp;actor.phase='idle';actor.bornTick=battle.state.tick;}
        if(mode==='sequence' && sequencePosition===231)battle.kill(actor,true);
        actor.previousX=actor.x;
        if(effectiveMode==='idle')actor.phase='idle';
        else if(effectiveMode==='move'){actor.phase='move';actor.runDistance+=actor.speed/30;}
        else if(effectiveMode==='charge'){actor.phase='charge';actor.runDistance+=actor.speed/20;}
        else if(effectiveMode==='hit'){actor.releaseAt=0;actor.phase='idle';if(mode==='sequence' ? sequencePosition===216 : age%25===1){actor.hp=actor.maxHp;battle.state.pendingHits.push({sourceId:battle.base(side===0 ? 1 : 0).id,side:side===0 ? 1 : 0,targetId:actor.id,raw:actor.maxHp*.05,damageType:era==='A5' ? 'energy' : 'physical',projectile:false});}}
        else if(effectiveMode==='attack'){
          const period=Math.max(actor.period,20),cycle=(mode==='sequence' ? sequencePosition-126 : age)%period;actor.nextAttack=battle.state.tick+period-cycle;actor.releaseAt=cycle<actor.windup ? battle.state.tick+actor.windup-cycle : 0;actor.phase=cycle<actor.windup ? 'windup' : 'recover';
          if(cycle===actor.windup)fire(battle,actor,battle.base(side===0 ? 1 : 0),{sourceId:actor.id,side,targetId:battle.base(side===0 ? 1 : 0).id,raw:actor.attack,damageType:actor.damageType,projectile:actor.range>=100});
        }
      }
      updateProjectiles(battle);applyHits(battle);
      battle.state.events=battle.state.events.filter(e=>battle.state.tick-e.tick<90);
      recorder.progress({tickEnd:battle.state.tick,completeSequence:mode==='sequence' && age>=251});
      if(mode==='sequence' && recorder.running && age>=251){
        recorder.stop();paused=true;battle.state.paused=true;accumulator=0;
        root.querySelector('[data-review=freeze]')!.textContent='继续动作';
        break;
      }
    }
    const status=document.getElementById('review-status');if(status)status.textContent=`${live ? '实际模拟' : '检视动作'} · ${battle.state.tick} tick · ${battle.state.entities.filter(e=>e.kind!=='base').length}角色 · ${live ? battle.state.entities.filter(e=>e.kind!=='base').map(e=>e.phase).join(' / ') : actors.map(a=>(catalog.heroes[a.contentId]?.name ?? catalog.units[a.contentId]?.name)+':'+a.phase).join(' / ')} · 基地 ${battle.base(0).hp}/${battle.base(0).maxHp} · 视野 ${Math.round(camera.x)}–${Math.round(camera.x+camera.width)}`;
  };
  return {battle:()=>battle,advance,point:()=>{},selectedSkill:()=>null,reducedMotion:()=>false,interpolation:()=>Math.min(1,accumulator/(1000/30)),ready:()=>{},camera,canNavigate:()=>!recorder.busy,cameraChanged:()=>{},playbackSpeed:()=>speed};
}
