import Phaser from 'phaser';
import {catalog} from '../content/catalog';
import {clamp,worldX,type BattleEvent,type Entity} from '../core/types';
import type {Battle} from '../core/battle';
import {assetEntries} from './assets';
import {BattleCamera} from './battle-camera';
import {fighterPose,type MotionClass} from './motion';
import {animationSheets,actorFrame,type AnimationSheet} from './animation';
import {fighterProfile,visualActorId} from '../core/fighter-profiles';
import {ageSpecials} from '../core/age-specials';

export interface SceneBridge {
  battle():Battle | null;advance(delta:number):void;point(x:number,targetId?:number):void;
  selectedSkill():string | null;reducedMotion():boolean;interpolation():number;ready(errors?:string[]):void;
  camera:BattleCamera;canNavigate():boolean;cameraChanged():void;
  playbackSpeed?():number;
}
interface RigPart {key:string;role:string;bounds:number[];pivot:number[]}
interface Rig {size:number[];visibleBounds:number[];bodyTop:number;anchor:number[];motionClass:MotionClass;parts:RigPart[]}
interface FighterView {
  container:Phaser.GameObjects.Container;sprite?:Phaser.GameObjects.Image;hp:Phaser.GameObjects.Graphics;
  shadow:Phaser.GameObjects.Ellipse;marker:Phaser.GameObjects.Graphics;statusIcons:Map<string,Phaser.GameObjects.Image>;
  height:number;rig?:{container:Phaser.GameObjects.Container;motionClass:MotionClass;parts:{image:Phaser.GameObjects.Image;role:string;x:number;y:number}[]};
  lastPhase:string;releasedAt:number;hitAt:number;hitDirection:number;skillAt:number;upgradeAt:number;destroyed:boolean;
  sheet?:AnimationSheet;frame:number;
}
interface TowerView {image:Phaser.GameObjects.Image;builtAt:number;releasedAt:number}
interface Flight {fromX:number;fromY:number;toX:number;toY:number}
const GROUND=595;
export const buildingStage=(ratio:number)=>ratio<=0 ? 'ruin' : ratio<=.35 ? 'critical' : ratio<=.65 ? 'worn' : '';
const direction=(entity:Entity)=>entity.side===0 ? 1 : -1;

export class BattleScene extends Phaser.Scene {
  private views=new Map<number,FighterView>();
  private background:Phaser.GameObjects.Container | null=null;
  private effectsObjects=new Set<Phaser.GameObjects.GameObject>();
  private towers=new Map<number,TowerView>();
  private flights=new Map<number,Flight>();
  private era='';private active:Battle | null=null;private seen=0;private visualTime=0;
  private preview!:Phaser.GameObjects.Graphics;private missiles!:Phaser.GameObjects.Graphics;private warnings!:Phaser.GameObjects.Graphics;
  private pointerId:number | null=null;private multiTouch=false;
  private skyTint!:Phaser.GameObjects.Graphics;
  private loadErrors:string[]=[];
  private shakenAt=-100;
  // Animation atlases are requested by the fighters that actually enter the
  // scene. Only the first-era roster (plus the first hero portrait) is in the
  // initial loader queue; later eras are streamed through Phaser's loader.
  private animationLoading=new Set<string>();
  private animationQueued=new Map<string,{sheet:AnimationSheet;path:string}>();
  private animationLoaderBusy=false;
  private animationLoaded=new Set<string>();
  private animationEstimatedBytes=0;
  private animationPeakBytes=0;
  constructor(private bridge:SceneBridge){super('Battle');}
  preload(){
    this.load.on('loaderror',(file:Phaser.Loader.File)=>{this.loadErrors.push(file.key);});
    // The clean panoramas leave the foreground to actual bases and troops.
    for(const asset of assetEntries){
      if((asset.kind==='rig' || asset.kind==='rig_part') && Object.keys(animationSheets).some(id=>asset.key===`rig.${id}` || asset.key.startsWith(`rig.${id}.`)))continue;
      if(asset.kind==='rig')this.load.json(asset.key,`./assets/${asset.path}`);
      else if(asset.kind==='rig_part' || /^(base\.|turret\.|fx\.|status\.)/.test(asset.key) || /^background\..*\.battle$/.test(asset.key))this.load.image(asset.key,`./assets/${asset.path}`);
    }
    // Keep the first playable encounter immediately available. Every other
    // accepted atlas is loaded on demand when an entity of that era appears.
    for(const id of ['U11','U12','U13','U14','H01']){
      const sheet=animationSheets[id];if(!sheet)continue;
      for(const [key,path] of [[sheet.key,sheet.path],[sheet.enemyKey,sheet.enemyPath]] as const){
        this.load.spritesheet(key,`./assets/${path}`,{frameWidth:sheet.frameWidth,frameHeight:sheet.frameHeight});
        this.animationLoading.add(key);
      }
    }
  }
  create(){
    for(const key of [...this.animationLoading])if(this.textures.exists(key)){this.animationLoading.delete(key);this.animationLoaded.add(key);}
    this.refreshAnimationStats();
    this.publishAnimationStats();
    this.load.on('filecomplete-spritesheet',(key:string)=>{this.animationLoading.delete(key);this.animationLoaded.add(key);this.refreshAnimationStats();});
    this.load.on('loaderror',(file:Phaser.Loader.File)=>{this.animationLoading.delete(file.key);this.loadErrors.push(file.key);this.publishAnimationStats();});
    this.game.canvas.dataset.engineReady=String(this.loadErrors.length===0);this.bridge.ready(this.loadErrors);
    this.cameras.main.setBounds(0,-1000,1600,3000).setBackgroundColor('#7896a1');
    this.skyTint=this.add.graphics().setScrollFactor(0).setDepth(-8);
    this.preview=this.add.graphics().setDepth(75);this.missiles=this.add.graphics().setDepth(55);this.warnings=this.add.graphics().setDepth(8);
    const screenScale=()=>this.game.canvas.getBoundingClientRect().width/this.scale.gameSize.width;
    this.input.on('pointerdown',(pointer:Phaser.Input.Pointer)=>{
      if(!this.bridge.canNavigate() || pointer.rightButtonDown())return;
      if(this.pointerId!==null){this.multiTouch=true;return;}
      this.pointerId=pointer.id;this.multiTouch=false;this.bridge.camera.begin(pointer.x*screenScale(),pointer.y*screenScale());
    });
    this.input.on('pointermove',(pointer:Phaser.Input.Pointer)=>{
      if(this.pointerId===pointer.id && this.bridge.canNavigate())this.bridge.camera.drag(pointer.x*screenScale(),pointer.y*screenScale(),1/screenScale());
    });
    const finish=(pointer:Phaser.Input.Pointer,outside=false)=>{
      if(pointer.id!==this.pointerId)return;
      const dragged=this.bridge.camera.end();this.pointerId=null;
      if(dragged || this.multiTouch || outside || !this.bridge.canNavigate())return;
      const battle=this.bridge.battle(),skillId=this.bridge.selectedSkill();if(!battle || !skillId)return;
      const point=this.cameras.main.getWorldPoint(pointer.x,pointer.y);point.x=this.bridge.camera.worldAt(pointer.x);
      if(point.y<GROUND-240 || point.y>GROUND+40)return;
      if(skillId.startsWith('item:')){this.bridge.point(point.x);return;}
      const skill=catalog.skills[skillId];
      const hit=skill?.targetMode==='enemy_entity' ? battle.living(1).filter(e=>e.kind!=='base' || skill.canDamageBase).filter(e=>{
        const view=this.views.get(e.id);return view && Math.abs(worldX(e)-point.x)<Math.max(24,e.radius+22) && point.y>=GROUND-view.height && point.y<=GROUND+20;
      }).sort((a,b)=>Math.abs(worldX(a)-point.x)-Math.abs(worldX(b)-point.x))[0] : undefined;
      this.bridge.point(point.x,hit?.id);
    };
    this.input.on('pointerup',(p:Phaser.Input.Pointer)=>finish(p));
    this.input.on('pointerupoutside',(p:Phaser.Input.Pointer)=>finish(p,true));
    this.input.on('gameout',()=>{this.bridge.camera.end();this.pointerId=null;});
    this.input.on('wheel',(_p:Phaser.Input.Pointer,_objects:unknown,dx:number,dy:number)=>{if(this.bridge.canNavigate())this.bridge.camera.pan(clamp((dx || dy)*.75,-180,180));});
    this.game.canvas.addEventListener('pointercancel',()=>{this.bridge.camera.end();this.pointerId=null;});
  }
  private publishAnimationStats(){
    const stats={
      loadedKeys:this.animationLoaded.size,loadingKeys:this.animationLoading.size,
      estimatedBytes:this.animationEstimatedBytes,peakEstimatedBytes:this.animationPeakBytes,
      budgetBytes:64*1024*1024,
    };
    if(typeof window!=='undefined')(window as unknown as {__epochAnimationStats?:Record<string,unknown>}).__epochAnimationStats=stats;
    const canvas=this.game?.canvas as HTMLCanvasElement | undefined;
    if(canvas){
      canvas.dataset.animationLoadedKeys=String(stats.loadedKeys);
      canvas.dataset.animationLoadingKeys=String(stats.loadingKeys);
      canvas.dataset.animationEstimatedBytes=String(stats.estimatedBytes);
      canvas.dataset.animationPeakBytes=String(stats.peakEstimatedBytes);
      canvas.dataset.animationBudgetBytes=String(stats.budgetBytes);
    }
  }
  private refreshAnimationStats(){
    this.animationEstimatedBytes=0;
    for(const key of this.animationLoaded){
      const texture=this.textures.get(key),source=texture?.source?.[0];
      this.animationEstimatedBytes+=(source?.width ?? 0)*(source?.height ?? 0)*4;
    }
    this.animationPeakBytes=Math.max(this.animationPeakBytes,this.animationEstimatedBytes);this.publishAnimationStats();
  }
  private queueAnimation(actorId:string,side:0|1){
    const sheet=animationSheets[actorId];if(!sheet)return;
    const key=side===1 ? sheet.enemyKey : sheet.key;
    if(this.textures.exists(key) || this.animationLoading.has(key) || this.animationQueued.has(key))return;
    this.animationQueued.set(key,{sheet,path:side===1 ? sheet.enemyPath : sheet.path});
    if(!this.animationLoaderBusy)this.flushAnimationQueue();
  }
  private flushAnimationQueue(){
    if(this.animationLoaderBusy || !this.animationQueued.size)return;
    const entries=[...this.animationQueued.entries()];this.animationQueued.clear();this.animationLoaderBusy=true;
    for(const [key,{sheet,path}] of entries){
      this.animationLoading.add(key);this.load.spritesheet(key,`./assets/${path}`,{frameWidth:sheet.frameWidth,frameHeight:sheet.frameHeight});
    }
    this.load.once('complete',()=>{
      for(const key of [...this.animationLoading])if(this.textures.exists(key)){this.animationLoading.delete(key);this.animationLoaded.add(key);}
      this.animationLoaderBusy=false;this.refreshAnimationStats();this.flushAnimationQueue();
    });
    this.load.start();
  }
  private promoteAnimation(entity:Entity,view:FighterView){
    if(view.sprite || !view.sheet)return;
    const key=entity.side===1 ? view.sheet.enemyKey : view.sheet.key;
    if(!this.textures.exists(key))return;
    view.rig?.container.destroy(true);view.rig=undefined;
    view.sprite=this.add.image(0,0,key,view.sheet.clips.idle[0]).setOrigin(...view.sheet.anchor).setFlipX(entity.side===1).setScale(view.height/Math.max(1,view.sheet.bodyHeight));
    view.container.addAt(view.sprite,1);view.frame=view.sheet.clips.idle[0];
  }
  private setBackground(eraId:string){
    const old=this.background,layers:Phaser.GameObjects.GameObject[]=[];
    const panorama=`background.${eraId}.battle`;
    if(this.textures.exists(panorama))layers.push(this.add.image(800,-100,panorama).setOrigin(.5,0).setDisplaySize(1600,900).setScrollFactor(.4,.45));
    const road=this.add.graphics().fillStyle(0xe6d3a5,.12).fillRect(0,GROUND-12,1600,25).lineStyle(1,0x675c43,.35).lineBetween(0,GROUND,1600,GROUND);
    layers.push(road);this.background=this.add.container(0,0,layers).setDepth(-10);this.era=eraId;
    if(old){if(this.bridge.reducedMotion())old.destroy(true);else{this.background.setAlpha(0);this.tweens.add({targets:this.background,alpha:1,duration:650});this.tweens.add({targets:old,alpha:0,duration:650,onComplete:()=>old.destroy(true)});}}
  }
  private makeView(entity:Entity):FighterView {
    const prefix=entity.kind==='unit' ? 'unit' : entity.kind==='hero' ? 'hero' : entity.kind==='base' ? 'base' : 'turret';
    const id=entity.kind==='base' ? entity.eraId : entity.kind==='summon' ? `TR${entity.eraId[1]}1` : entity.contentId;
    const initialStage=entity.kind==='base' ? buildingStage(entity.hp/entity.maxHp) : '';
    const key=`${prefix}.${id}${initialStage ? '.'+initialStage : ''}${entity.side===1 ? '.enemy' : ''}`;
    const profile=fighterProfile(entity.contentId),actorId=visualActorId(entity.contentId),sheet=animationSheets[actorId];
    if(sheet)this.queueAnimation(actorId,entity.side);
    let height=entity.kind==='base' ? 340 : profile.height;
    const shadow=this.add.ellipse(0,1,entity.kind==='base' ? 218 : profile.radius*2,entity.kind==='base' ? 18 : 7,0x1b2930,.25);
    let sprite:Phaser.GameObjects.Image | undefined,rig:FighterView['rig'];
    const specification=this.cache.json.get(`rig.${visualActorId(id)}`) as Rig | undefined;
    if(sheet && this.textures.exists(entity.side===1 ? sheet.enemyKey : sheet.key)){
      sprite=this.add.image(0,0,entity.side===1 ? sheet.enemyKey : sheet.key,sheet.clips.idle[0]).setOrigin(...sheet.anchor).setFlipX(entity.side===1).setScale(height/Math.max(1,sheet.bodyHeight));
    }else if(specification && (entity.kind==='unit' || entity.kind==='hero')){
      const bounds=specification.visibleBounds ?? [0,0,...specification.size];
      const targetHeight=['vehicle','chariot'].includes(specification.motionClass) ? 95 : height;
      const physicalTop=entity.kind==='hero' ? specification.bodyTop : bounds[1];
      const scale=Math.min(targetHeight/(bounds[3]-physicalTop),(entity.kind==='hero' ? 300 : entity.heavy ? 255 : 215)/(bounds[2]-bounds[0]));
      height=(bounds[3]-bounds[1])*scale;
      const parts:FighterView['rig']={container:this.add.container(0,0).setScale(direction(entity),1),parts:[],motionClass:specification.motionClass};
      for(const part of specification.parts){
        const partKey=part.key+(entity.side===1 ? '.enemy' : '');if(!this.textures.exists(partKey))continue;
        const x=(part.pivot[0]-specification.size[0]*.5)*scale,y=(part.pivot[1]-specification.size[1]*.9)*scale;
        const image=this.add.image(x,y,partKey).setScale(scale).setOrigin((part.pivot[0]-part.bounds[0])/(part.bounds[2]-part.bounds[0]),(part.pivot[1]-part.bounds[1])/(part.bounds[3]-part.bounds[1]));
        parts.container.add(image);parts.parts.push({image,role:part.role,x,y});
      }
      rig=parts;
    }else if(this.textures.exists(key)){sprite=this.add.image(0,0,key).setOrigin(.5,.9).setFlipX(entity.side===1).setDisplaySize(height,height);}
    const hp=this.add.graphics(),marker=this.add.graphics();
    const container=this.add.container(worldX(entity),GROUND,[shadow,...rig ? [rig.container] : sprite ? [sprite] : [],marker,hp]).setDepth(entity.kind==='base' ? 5 : 15);
    return {container,sprite,hp,shadow,marker,rig,height,sheet,frame:sheet?.clips.idle[0] ?? -1,statusIcons:new Map(),lastPhase:entity.phase,releasedAt:-100,hitAt:-100,hitDirection:0,skillAt:-100,upgradeAt:-100,destroyed:false};
  }
  private transient(object:Phaser.GameObjects.GameObject,duration:number,options:Record<string,unknown>={}){
    if(this.effectsObjects.size>=180){object.destroy();return;}
    this.effectsObjects.add(object);
    this.tweens.add({targets:object,alpha:0,duration,...options,onComplete:()=>{this.effectsObjects.delete(object);object.destroy();}});
  }
  private stamp(key:string,x:number,y:number,size:number,duration=260){
    if(!this.textures.exists(key))return;
    const stamp=this.add.image(x,y,key).setDisplaySize(size,size).setDepth(65);
    this.transient(stamp,duration,this.bridge.reducedMotion() ? {} : {scaleX:stamp.scaleX*1.25,scaleY:stamp.scaleY*1.25});
  }
  private debris(x:number,y:number,color:number,seed:number,count=6,large=false){
    if(this.bridge.reducedMotion())return;
    for(let i=0;i<count;i++){
      const angle=(i+.3)*2.399+seed*.23,travel=large ? 35+i*4 : 12+i*3;
      const shard=this.add.rectangle(x,y,large ? 5 : 2,large ? 7 : 3,color,.85).setRotation(angle).setDepth(64);
      this.transient(shard,large ? 550 : 280,{x:x+Math.cos(angle)*travel,y:y+Math.sin(angle)*travel+20,rotation:angle+2});
    }
  }
  private burstParticles(x:number,y:number,color:number,seed:number,count=8,spread=26,heavy=false){
    if(this.bridge.reducedMotion())return;
    for(let i=0;i<count;i++){
      const angle=(i+.37)*2.399+seed*.17,travel=spread*(.55+(i%4)*.16),size=heavy ? 5+(i%3)*2 : 2+(i%3);
      const particle=this.add.circle(x,y,size,color,.88).setDepth(72);
      this.transient(particle,heavy ? 460 : 260,{x:x+Math.cos(angle)*travel,y:y+Math.sin(angle)*travel-12,scaleX:.25,scaleY:.25});
    }
  }
  private floatText(text:string,x:number,y:number,color:string,large=false){
    const label=this.add.text(x,y,text,{fontFamily:'EpochRounded, sans-serif',fontSize:large ? '23px' : '15px',fontStyle:'bold',color,stroke:'#3c3b31',strokeThickness:3}).setOrigin(.5).setDepth(90);
    this.transient(label,650,{y:y-(this.bridge.reducedMotion() ? 12 : 38)});
  }
  private effects(event:BattleEvent){
    const battle=this.active;if(!battle)return;
    const target=event.targetId ? battle.state.entities.find(e=>e.id===event.targetId) : undefined;
    const view=event.targetId ? this.views.get(event.targetId) : undefined;
    const sourceView=event.sourceId ? this.views.get(event.sourceId) : undefined;
    const y=GROUND-(target?.kind==='base' ? 142 : fighterProfile(target?.contentId ?? '').hit[1]);
    if(event.type==='hit'){
      if(view){view.hitAt=event.tick;view.hitDirection=Math.sign(event.x-(event.fromX ?? event.x+(event.side===0 ? -1 : 1)));}
      if(event.absorbed && !event.amount){this.stamp('fx.shield_ring',event.x,y,54,190);return;}
      const bodyMaterial=target?.kind==='base' ? ['A1','A2'].includes(target.eraId) ? 'wood' : 'metal' : fighterProfile(target?.contentId ?? '').material;
      const material=event.damageType==='energy' ? 'arc_spark' : event.damageType==='blast' ? 'cannon_shock' : bodyMaterial==='metal' ? 'metal_impact' : bodyMaterial==='wood' ? 'stone_impact' : 'dust';
      const heavy=event.damageType==='blast',size=heavy ? 72 : event.damageType==='energy' ? 40 : target?.kind==='base' ? 43 : 27;
      this.stamp(`fx.${material}`,event.x,y,size,heavy ? 360 : 220);
      this.debris(event.x,y,event.damageType==='energy' ? 0x81d9ec : bodyMaterial==='metal' ? 0xf0ce88 : 0x9f825c,event.id,heavy || target?.kind==='base' ? 6 : bodyMaterial==='flesh' ? 0 : 3,target?.kind==='base');
      this.burstParticles(event.x,y,event.damageType==='energy' ? 0x9feaf1 : heavy ? 0xf2a557 : 0xf6d59b,event.id,heavy ? 16 : 8,heavy ? 42 : 25,heavy);
      if(!this.bridge.reducedMotion()){
        const ring=this.add.graphics().setDepth(67).lineStyle(2,event.damageType==='energy' ? 0x91e7ef : heavy ? 0xf2b35f : 0xf5dfb2,.72).strokeEllipse(event.x,y,heavy ? 84 : 48,heavy ? 42 : 24);
        this.transient(ring,heavy ? 340 : 210,{scaleX:1.5,scaleY:1.35});
      }
      if(event.skillId || target?.kind==='hero' || target?.kind==='base')this.floatText(`−${event.amount ?? 0}`,event.x,y-24,heavy ? '#ffd17c' : event.damageType==='energy' ? '#9ce3f1' : '#f6e5c6',heavy);
      if(!this.bridge.reducedMotion() && heavy && event.tick-this.shakenAt>=8 && Math.abs(event.x-(this.bridge.camera.x+this.bridge.camera.width/2))<600){this.cameras.main.shake(80,.0015);this.shakenAt=event.tick;}
    }else if(event.type==='release'){
      if(sourceView)sourceView.releasedAt=event.tick;
      const tower=event.sourceId ? this.towers.get(event.sourceId) : undefined;if(tower)tower.releasedAt=this.visualTime;
      const shooter=battle.state.entities.find(e=>e.id===event.sourceId);
      const socket=fighterProfile(shooter?.contentId ?? '').muzzle,sign=event.side===0 ? 1 : -1;
      const x=tower?.image.x ?? event.fromX ?? event.x,fromY=tower ? tower.image.y-35 : GROUND-socket[1],family=fighterProfile(shooter?.contentId ?? '').family;
      if(tower || ['gun','launcher','cannon'].includes(family))this.stamp(event.weaponId==='W07' ? 'fx.arc_spark' : 'fx.muzzle',x+sign*(tower ? 24 : socket[0]),fromY,family==='cannon' ? 44 : 26,95);
      else if(family==='mech')this.stamp('fx.arc_spark',x+sign*socket[0],fromY,33,130);
      else if(['shield','spear','mounted'].includes(family)){
        const swipe=this.add.graphics().setDepth(45).lineStyle(3,event.side===0 ? 0xf8d98e : 0xf5b6a1,.85);
        if(family==='spear')swipe.lineBetween(x+sign*(socket[0]-22),fromY,x+sign*(socket[0]+10),fromY);
        else swipe.beginPath().moveTo(x+sign*(socket[0]-14),fromY-18).lineTo(x+sign*(socket[0]+4),fromY-3).lineTo(x+sign*(socket[0]+7),fromY+13).strokePath();this.transient(swipe,105);
      }
      this.burstParticles(x+sign*(tower ? 24 : socket[0]),fromY,event.weaponId==='W07' ? 0x9feaf1 : 0xf6d38c,event.id,family==='cannon' ? 10 : 5,22,family==='cannon');
    }else if(event.type==='arc'){
      if(sourceView)sourceView.releasedAt=event.tick;
      const arc=this.add.graphics().setDepth(65).lineStyle(2,0x8be3ed,.95),start=event.fromX ?? event.x;
      arc.beginPath().moveTo(start,y).lineTo((start+event.x)/2-5,y-10).lineTo((start+event.x)/2+9,y+7).lineTo(event.x,y).strokePath();this.transient(arc,170);
    }else if(event.type==='cast'){
      if(view)view.skillAt=event.tick;
      const skill=catalog.skills[event.skillId!];
      this.stamp(skill.damageType==='energy' ? 'fx.chrono_ripple' : skill.targetMode.startsWith('ally') || skill.targetMode==='self' ? 'fx.shield_ring' : 'fx.mark_stamp',event.x,GROUND-32,Math.min(110,Math.max(46,skill.radius)),420);
    }else if(event.type==='shield' || event.type==='shieldBreak'){
      this.stamp('fx.shield_ring',event.x,y,event.type==='shield' ? 74 : 85,300);
      if(event.type==='shieldBreak')this.debris(event.x,y,0x88d7e5,event.id,8);
    }else if(event.type==='itemCast'){
      const id=event.text ?? '',color=id==='smoke-bomb' ? 0x9ab6ad : id==='war-drum' ? 0xf1c76a : 0x80dbe6;
      const radius=id==='smoke-bomb' ? (event.amount ?? 135) : 90;
      const ring=this.add.graphics().setDepth(62).lineStyle(3,color,.85).strokeEllipse(event.x,GROUND-20,radius*2,Math.max(26,radius*.28));
      this.transient(ring,520,{scaleX:1.2,scaleY:1.5});
      this.burstParticles(event.x,GROUND-35,color,event.id,id==='smoke-bomb' ? 18 : 12,id==='smoke-bomb' ? radius*.55 : 38,id==='chrono-crate');
      if(id==='war-drum')this.floatText('战鼓令',event.x,GROUND-132,'#f3d38d',true);
      if(id==='chrono-crate')this.floatText('时序补给',event.x,GROUND-132,'#9feaf1',true);
    }else if(event.type==='evolve' || event.type==='upgrade'){
      const base=battle.base(event.side),baseView=this.views.get(base.id);if(baseView)baseView.upgradeAt=this.visualTime;
      const banner=this.add.text(this.scale.gameSize.width/2,104,`${event.side===0 ? '文明进化' : '敌方进化'} · ${event.text}`,{fontFamily:'EpochDisplay, sans-serif',fontSize:'25px',color:'#f9dda0',stroke:'#3c3b31',strokeThickness:4}).setOrigin(.5).setScrollFactor(0).setDepth(90);
      this.transient(banner,1500,{y:122,delay:250});this.stamp('fx.chrono_ripple',worldX(base),GROUND-80,210,750);
    }else if((event.type==='spawn' && event.tick>0) || event.type==='rejoin'){
      this.stamp('fx.dust',event.x,GROUND-6,target?.kind==='hero' ? 66 : 36,350);
      if(target?.kind==='hero')this.stamp('fx.shield_ring',event.x,GROUND-58,90,600);
    }else if(event.type==='death'){
      if(target?.kind==='base' && view)view.destroyed=true;
      this.stamp(target?.kind==='base' ? 'fx.cannon_shock' : 'fx.dust',event.x,target?.kind==='base' ? GROUND-124 : GROUND-5,target?.kind==='base' ? 240 : 42,600);
      if(target?.kind==='base')this.debris(event.x,GROUND-138,0xb89c6b,event.id,20,true);
    }else if(event.type==='ageImpact'){
      const era=event.text ?? 'A1',color=era==='A5' ? 0x86e3ef : 0xf1b666;
      const ring=this.add.graphics().setDepth(64).lineStyle(3,color,.9).strokeEllipse(event.x,GROUND-3,Math.min(180,event.amount ?? 100),22);this.transient(ring,280);
      if(era==='A5'){const beam=this.add.graphics().setDepth(62).lineStyle(18,color,.28).lineBetween(event.x,GROUND-380,event.x,GROUND-8).lineStyle(4,0xe7fcff,.95).lineBetween(event.x,GROUND-380,event.x,GROUND-8);this.transient(beam,240);}
      else if(era==='A1' || era==='A4')this.stamp('fx.cannon_shock',event.x,GROUND-22,era==='A4' ? 115 : 82,320);
      else this.stamp(era==='A2' ? 'fx.muzzle' : 'fx.dust',event.x,GROUND-30,76,260);
    }else if(event.type==='ageTrail'){
      const color=event.text==='A5' ? 0x93e9f2 : event.text==='A2' ? 0xee9250 : 0xf3dbab;
      const trail=this.add.graphics().setDepth(59).lineStyle(event.text==='A4' ? 5 : 2,color,.92).lineBetween(event.x-48,y-240,event.x,y);
      if(event.text==='A1')trail.fillStyle(0xa36d48).fillCircle(event.x,y,9);this.transient(trail,170);
    }else if(event.type==='rushContact'){
      this.stamp('fx.chrono_ripple',event.x,GROUND-32,64,250);
    }else if(event.type==='rush'){
      this.floatText('换代冲锋',event.x,GROUND-140,'#f4d38d');
    }else if(event.type==='reward' && event.side===0){
      this.floatText(`+${event.amount}`,event.x,GROUND-13,'#f1d38a');
    }else if(event.type==='end'){
      this.bridge.camera.jump(battle.state.winner===0 ? 'enemy' : 'ally',battle);
      for(const side of [0,1] as const)if(battle.base(side).hp<=0 && !this.views.get(battle.base(side).id)?.destroyed){this.stamp('fx.cannon_shock',worldX(battle.base(side)),GROUND-130,260,700);this.debris(worldX(battle.base(side)),GROUND-120,0xb6986e,event.id,20,true);}
    }
  }
  private updateFighter(entity:Entity,view:FighterView,now:number){
    view.container.setVisible(!entity.garrisoned);
    if(entity.garrisoned)return;
    const reduced=this.bridge.reducedMotion();
    const x=((entity.previousX ?? entity.x)*(1-this.bridge.interpolation())+entity.x*this.bridge.interpolation())/100;
    view.container.setPosition(x,GROUND).setDepth(entity.kind==='base' ? 5 : entity.hp<=0 ? 10 : entity.heavy ? 16 : entity.kind==='hero' ? 18 : 17);view.marker.clear();view.hp.clear();
    if(entity.kind==='base'){
      const stage=buildingStage(entity.hp/entity.maxHp),key=`base.${entity.eraId}${stage ? '.'+stage : ''}${entity.side===1 ? '.enemy' : ''}`;
      if(view.sprite && this.textures.exists(key) && view.sprite.texture.key!==key){
        const ghost=this.add.image(x,GROUND,view.sprite.texture.key).setOrigin(.5,.9).setDisplaySize(view.height,view.height).setFlipX(entity.side===1).setDepth(7);
        if(!reduced)this.transient(ghost,420);else ghost.destroy();view.sprite.setTexture(key);
      }
      const hurt=now-view.hitAt,upgrade=clamp((this.visualTime-view.upgradeAt)/800,0,1);
      view.sprite?.setX(!reduced && hurt>=0 && hurt<6 ? Math.sin(hurt*3)*3*(1-hurt/6) : 0).setY(!reduced && upgrade<1 ? -Math.sin(upgrade*Math.PI)*6 : 0);
      if(view.sprite){if(hurt>=0 && hurt<2)view.sprite.setTintFill(0xffe1bc);else if(upgrade<.75)view.sprite.setTint(0xffe4b4);else view.sprite.clearTint();}
      if(entity.hp<=0)view.destroyed=true;
      const slots=this.active!.state.sides[entity.side].unlockedSlots;
      view.marker.lineStyle(1,entity.side===0 ? 0x6bc3d2 : 0xda927d,.65);
      // The enlarged fortress remains a landmark even when the camera follows
      // the front. Turret sockets sit on its parapet instead of on the troop
      // line, keeping the scale contrast legible.
      view.marker.fillStyle(entity.side===0 ? 0x67c6d4 : 0xda927d,.18).fillEllipse(0,-12,232,30);
      view.marker.lineStyle(2,entity.side===0 ? 0x67c6d4 : 0xda927d,.58).strokeEllipse(0,-12,232,30);
      if(entity.hp>0)for(let slot=0;slot<slots;slot++)view.marker.strokeEllipse(direction(entity)*(slot*46-42),-260,34,9);
      if(entity.hp>0 && entity.hp/entity.maxHp<=.35 && !reduced){
        for(let i=0;i<4;i++){const progress=((now/60+i*.31)%1);view.marker.fillStyle(0x29353b,.25*(1-progress)).fillCircle(18+Math.sin(progress*3+i)*14,-145-progress*125,6+progress*20);}
      }
      if(upgrade<1){view.marker.lineStyle(2,0xf2d390,(1-upgrade)*.8).strokeEllipse(0,-14,120+upgrade*80,18+upgrade*16);}
    }else{
      if(view.sheet && view.sprite){
        view.frame=actorFrame(entity,view.sheet,{now,releasedAt:view.releasedAt,hitAt:view.hitAt,skillAt:view.skillAt,previousFrame:view.frame,reducedMotion:reduced});view.sprite.setFrame(view.frame);
        view.container.setAlpha(entity.hp<=0 ? clamp((24-(now-entity.bornTick))/8,0,1) : 1);
        if(now-view.hitAt>=0 && now-view.hitAt<2)view.sprite.setTintFill(0xffe4c9);else view.sprite.clearTint();
      }else{
        const pose=fighterPose(entity,{now,releasedAt:view.releasedAt,hitAt:view.hitAt,hitDirection:view.hitDirection,skillAt:view.skillAt,motionClass:view.rig?.motionClass ?? 'vehicle',reducedMotion:reduced});
        view.container.setX(x+pose.x*direction(entity)).setY(GROUND+pose.y).setAlpha(pose.alpha);
        if(view.rig){
        view.rig.container.setAngle(pose.angle*direction(entity));
        for(const part of view.rig.parts){const offset=pose.parts[part.role];part.image.setPosition(part.x+(offset?.x ?? 0),part.y+(offset?.y ?? 0)).setAngle(offset?.angle ?? 0);if(now-view.hitAt>=0 && now-view.hitAt<2)part.image.setTintFill(0xffe4c9);else part.image.clearTint();}
        }else view.sprite?.setAngle(pose.angle*direction(entity));
      }
      view.shadow.setAlpha(entity.hp<=0 ? .08 : .22);
      if(entity.hp>0 && (entity.kind==='hero' || entity.hp<entity.maxHp)){
        const top=-view.height-10,width=entity.kind==='hero' ? 61 : 45;
        view.hp.fillStyle(0x112735,.9).fillRoundedRect(-width/2,top,width,7,2).fillStyle(entity.side===0 ? 0x70c9cc : 0xe58a75).fillRoundedRect(-width/2+1,top+1,(width-2)*entity.hp/entity.maxHp,5,1);
      }
      if(entity.statuses.some(s=>s.id==='ST06')){
        view.marker.fillStyle(0xe9903f,.45).fillEllipse(0,-4,32,7);
        for(let i=0;i<3;i++)view.marker.lineStyle(2,0xf4c276,.8).lineBetween(i*9-9,-5,i*9-5,-(10+(reduced ? 5 : 7*Math.sin(now*.2+i))));
      }
      if(entity.rushArmed || entity.rushUntil>this.active!.state.tick)view.marker.lineStyle(2,0xe4c476,.75).lineBetween(-18,-3,18,-3);
      if(entity.kind==='hero' && entity.hp>0){
        this.drawHeroEraEquipment(view.marker,entity,view.height,now);
      }
      if(entity.kind==='unit' && entity.hp>0){
        const special=catalog.units[entity.contentId]?.special ?? {};
        const auraRadius=Number(special.auraRadius ?? 0);
        if(auraRadius>0){
          const auraColor=entity.contentId==='U45' ? 0x8ed6ae : entity.contentId==='U55' ? 0x86e2ee : 0xf0c66b;
          const pulse=this.bridge.reducedMotion() ? .18 : .12+.05*Math.sin(now*.12);
          view.marker.fillStyle(auraColor,pulse*.22).fillEllipse(0,-view.height*.28,auraRadius*2,.28*auraRadius);
          view.marker.lineStyle(1.5,auraColor,pulse+.25).strokeEllipse(0,-view.height*.28,auraRadius*2,.28*auraRadius);
        }
      }
    }
    const shield=entity.shields.reduce((sum,s)=>sum+s.hp,0);
    if(shield && entity.hp>0){view.marker.fillStyle(0x67c6d4,.07).fillEllipse(0,-view.height*.4,entity.kind==='base' ? 270 : entity.heavy ? 82 : 65,entity.kind==='base' ? 300 : view.height*.83);view.marker.lineStyle(2,0x83d2de,.75).strokeEllipse(0,-view.height*.4,entity.kind==='base' ? 270 : entity.heavy ? 82 : 65,entity.kind==='base' ? 300 : view.height*.83);}
    const statuses=entity.hp>0 ? [...new Set(entity.statuses.map(s=>s.id))].slice(0,3) : [];
    for(const [id,image] of view.statusIcons)if(!statuses.includes(id)){view.container.remove(image,true);view.statusIcons.delete(id);}
    statuses.forEach((id,i)=>{let image=view.statusIcons.get(id);if(!image && this.textures.exists(`status.${id}`)){image=this.add.image(0,0,`status.${id}`).setDisplaySize(15,15);view.container.add(image);view.statusIcons.set(id,image);}image?.setPosition((i-(statuses.length-1)/2)*18,-view.height-23);});
    view.lastPhase=entity.phase;
  }
  private updateTowers(battle:Battle){
    const ids=new Set<number>();
    for(const side of [0,1] as const)for(const tower of battle.state.sides[side].turrets){
      ids.add(tower.id);let view=this.towers.get(tower.id);
      const key=`turret.${tower.contentId}${side===1 ? '.enemy' : ''}`;
      if(!view && this.textures.exists(key)){
        const born=battle.state.events.find(e=>e.type==='build' && e.sourceId===tower.id);
        view={image:this.add.image(0,0,key).setOrigin(.5,.9).setDisplaySize(94,94).setFlipX(side===1).setDepth(25),builtAt:born && battle.state.tick-born.tick<10 ? this.visualTime : this.visualTime-650,releasedAt:-1000};this.towers.set(tower.id,view);
      }
      if(view){const progress=clamp((this.visualTime-view.builtAt)/600,0,1),recoil=this.bridge.reducedMotion() ? 0 : Math.exp(-(this.visualTime-view.releasedAt)/90);view.image.setVisible(battle.base(side).hp>0).setPosition(worldX(battle.base(side))+(side===0 ? 1 : -1)*(tower.slot*46-42),GROUND-252+(1-progress)*15).setAlpha(.25+.75*progress).setAngle(recoil*5*(side===0 ? -1 : 1));}
    }
    for(const [id,view] of this.towers)if(!ids.has(id)){view.image.destroy();this.towers.delete(id);}
  }
  private drawHeroEraEquipment(marker:Phaser.GameObjects.Graphics,entity:Entity,height:number,now:number){
    const era=clamp(Number(entity.eraId[1]),1,5),d=direction(entity),back=-d;
    const ally=entity.side===0;
    const palette=ally ? [0x9b7047,0xb88947,0xaebbc2,0x617f76,0x62d8e6] : [0x9a5c45,0xb56d4e,0x9f7472,0x81564f,0xd67d76];
    const trim=ally ? 0x85d8e4 : 0xefab8b;
    const shoulderY=-height*.62, chestY=-height*.42, weaponY=-height*.34;
    const plateW=[18,22,27,31,35][era-1],plateH=[12,15,18,21,23][era-1];
    // The authored sprite remains the character body. These compact overlays
    // are the commander’s era loadout: each age changes its silhouette,
    // material, and weapon accent without replacing the calibrated atlas.
    marker.fillStyle(palette[era-1],.94).fillRoundedRect(back*17-plateW/2,shoulderY-plateH/2,plateW,plateH,Math.min(7,plateH/2));
    marker.lineStyle(1.5,0x3d483e,.72).strokeRoundedRect(back*17-plateW/2,shoulderY-plateH/2,plateW,plateH,Math.min(7,plateH/2));
    if(era===1){
      marker.lineStyle(2,0x6e4a34,.85).lineBetween(back*5,shoulderY-5,back*11,chestY+7);
      marker.fillStyle(0xe2bd71,.95).fillTriangle(d*27,weaponY-4,d*39,weaponY,d*27,weaponY+4);
    }else if(era===2){
      marker.lineStyle(2,0xe1b25c,.9).strokeEllipse(back*17,shoulderY,plateW+8,plateH+5);
      marker.lineStyle(2,0x85582f,.85).lineBetween(back*4,chestY-2,back*21,chestY+5);
      marker.fillStyle(0xe6c77c,.95).fillCircle(d*28,weaponY,4);
    }else if(era===3){
      marker.lineStyle(2,0xd9e4e8,.9).lineBetween(back*5,shoulderY+plateH/2,back*20,shoulderY+plateH/2);
      marker.lineStyle(2,0x718794,.9).lineBetween(back*4,chestY-6,back*19,chestY+3);
      marker.fillStyle(0xf0f6f3,.95).fillTriangle(d*29,weaponY-5,d*43,weaponY,d*29,weaponY+5);
    }else if(era===4){
      marker.fillStyle(0x2f4847,.9).fillRoundedRect(back*23-6,chestY-7,12,16,3);
      marker.lineStyle(2,0xc6a862,.9).lineBetween(back*28,chestY-3,back*28,chestY+10);
      marker.fillStyle(0xe4c16e,.95).fillRect(d*28,weaponY-3,15,6);
      marker.lineStyle(2,0xf5d27e,.7).strokeEllipse(d*37,weaponY,20,11);
    }else{
      const pulse=entity.hp>0 ? .55+.25*Math.sin(now*.16) : .55;
      marker.fillStyle(0x2d7380,.7).fillRoundedRect(back*23-7,shoulderY-8,14,19,5);
      marker.lineStyle(2,trim,.95).strokeEllipse(back*23,shoulderY,22,26);
      marker.fillStyle(trim,pulse).fillCircle(back*23,shoulderY,4);
      marker.lineStyle(3,trim,.9).lineBetween(d*24,weaponY,d*47,weaponY);
      marker.lineStyle(1,0xe8ffff,.9).lineBetween(d*38,weaponY-4,d*48,weaponY-4);
    }
    for(let i=0;i<era;i++)marker.fillStyle(trim,.96).fillCircle(back*15+(i-(era-1)/2)*4,shoulderY+plateH*.8,1.8);
  }
  private updateProjectiles(battle:Battle){
    this.missiles.clear();const ids=new Set(battle.state.projectiles.map(p=>p.id));
    for(const [id] of this.flights)if(!ids.has(id))this.flights.delete(id);
    for(const p of battle.state.projectiles){
      let flight=this.flights.get(p.id);const source=battle.state.entities.find(e=>e.id===p.sourceId),tower=this.towers.get(p.sourceId),target=battle.state.entities.find(e=>e.id===p.targetId);
      if(!flight){flight={fromX:p.previousX/100,fromY:tower ? tower.image.y-42 : GROUND-fighterProfile(source?.contentId ?? '').muzzle[1],toX:target ? worldX(target) : worldX(p)+p.direction*300,toY:GROUND-(target?.kind==='base' ? 142 : fighterProfile(target?.contentId ?? '').hit[1])};this.flights.set(p.id,flight);}
      const x=(p.previousX*(1-this.bridge.interpolation())+p.x*this.bridge.interpolation())/100;
      const progress=clamp(Math.abs(x-flight.fromX)/Math.max(1,Math.abs(flight.toX-flight.fromX)),0,1),arc=p.weaponId==='W03' ? 35 : p.weaponId==='W05' ? 23 : 0;
      const y=flight.fromY+(flight.toY-flight.fromY)*progress-Math.sin(progress*Math.PI)*arc;
      const color=p.hit.damageType==='energy' ? 0x98e6ec : p.hit.damageType==='blast' ? 0x4c3c31 : 0xfbe5b3;
      const slope=(flight.toY-flight.fromY-Math.cos(progress*Math.PI)*arc*Math.PI)/Math.max(1,Math.abs(flight.toX-flight.fromX));
      if(p.hit.damageType==='blast')this.missiles.fillStyle(color).fillCircle(x,y,5).lineStyle(2,0xeac779,.7).lineBetween(x-p.direction*20,y-20*slope,x-p.direction*7,y-7*slope);
      else{this.missiles.lineStyle(p.weaponId==='W03' ? 2 : 3,color,.95).lineBetween(x-p.direction*20,y-20*slope,x,y);if(p.weaponId==='W03')this.missiles.fillStyle(color).fillTriangle(x,y,x-p.direction*6,y-3,x-p.direction*6,y+3);if(p.hit.damageType==='energy')this.missiles.lineStyle(7,color,.13).lineBetween(x-p.direction*31,y-31*slope,x,y);}
    }
  }
  private aim(battle:Battle){
    this.preview.clear();const id=this.bridge.selectedSkill(),hero=battle.hero(0);if(!id || !this.bridge.canNavigate())return;
    if(id.startsWith('item:')){
      const itemId=id.slice(5),radius=itemId==='smoke-bomb' ? 135 : 60,p=this.cameras.main.getWorldPoint(this.input.activePointer.x,this.input.activePointer.y);p.x=this.bridge.camera.worldAt(this.input.activePointer.x);
      const valid=p.x>=140 && p.x<=1460 && p.y>=GROUND-240 && p.y<=GROUND+40,color=valid ? 0x9ab6ad : 0xe9897a;
      this.preview.fillStyle(color,.13).fillEllipse(p.x,GROUND-8,radius*2,Math.max(28,radius*.26)).lineStyle(2,color,.88).strokeEllipse(p.x,GROUND-8,radius*2,Math.max(28,radius*.26));
      return;
    }
    if(id==='age-special'){
      const special=ageSpecials[battle.state.sides[0].eraId as keyof typeof ageSpecials],p=this.cameras.main.getWorldPoint(this.input.activePointer.x,this.input.activePointer.y);p.x=this.bridge.camera.worldAt(this.input.activePointer.x);
      const valid=p.x>=140 && p.x<=1460 && p.y>=GROUND-240 && p.y<=GROUND+40,color=valid ? 0xf0bb66 : 0xe9897a;
      this.preview.fillStyle(color,.1).fillEllipse(p.x,GROUND-5,special.radius*2,42).lineStyle(2,color,.9).strokeEllipse(p.x,GROUND-5,special.radius*2,42).lineBetween(p.x,GROUND-120,p.x,GROUND-15);return;
    }
    if(!hero)return;
    const skill=catalog.skills[id],p=this.cameras.main.getWorldPoint(this.input.activePointer.x,this.input.activePointer.y),range=battle.skillRange(0,id);p.x=this.bridge.camera.worldAt(this.input.activePointer.x);
    const valid=p.x>=80 && p.x<=1520 && Math.abs(p.x-worldX(hero))<=range && p.y>=GROUND-240 && p.y<=GROUND+40;
    const color=valid ? skill.targetMode.startsWith('ally') ? 0x79d9bd : 0xf2d284 : 0xf19b83;
    this.preview.lineStyle(1,0x6ba6bd,.42).lineBetween(Math.max(80,worldX(hero)-range),GROUND+13,Math.min(1520,worldX(hero)+range),GROUND+13);
    this.preview.fillStyle(color,.08).fillEllipse(p.x,GROUND-8,Math.max(40,skill.radius*2),Math.min(55,Math.max(20,skill.radius*.25)));
    this.preview.lineStyle(2,color,.85).strokeEllipse(p.x,GROUND-8,Math.max(40,skill.radius*2),Math.min(55,Math.max(20,skill.radius*.25)));
    this.preview.lineStyle(1,color,.5).lineBetween(worldX(hero),GROUND-65,p.x,GROUND-8);
    if(skill.targetMode==='enemy_entity'){const target=battle.living(1).filter(e=>(e.kind!=='base' || skill.canDamageBase) && Math.abs(worldX(e)-p.x)<=e.radius+22).sort((a,b)=>Math.abs(worldX(a)-p.x)-Math.abs(worldX(b)-p.x))[0];if(target)this.preview.lineStyle(2,color,.85).strokeEllipse(worldX(target),GROUND-48,60,95);}
  }
  update(_time:number,delta:number){
    const playbackSpeed=this.bridge.playbackSpeed?.() ?? 1;
    this.time.timeScale=playbackSpeed;this.tweens.timeScale=playbackSpeed;
    this.visualTime+=Math.min(delta,100)*playbackSpeed;const battle=this.bridge.battle();
    if(battle!==this.active){
      for(const view of this.views.values())view.container.destroy(true);this.views.clear();for(const tower of this.towers.values())tower.image.destroy();this.towers.clear();this.flights.clear();
      for(const object of this.effectsObjects){this.tweens.killTweensOf(object);object.destroy();}this.effectsObjects.clear();
      this.missiles.clear();this.warnings.clear();this.preview.clear();this.active=battle;this.seen=battle && battle.state.tick>0 ? Math.max(0,...battle.state.events.map(e=>e.id)) : 0;this.era='';this.bridge.camera.reset(this.scale.gameSize.width);this.pointerId=null;
    }
    this.bridge.advance(delta);
    if(!battle){if(!this.background || this.era!=='A3')this.setBackground('A3');return;}
    const canvas=this.game.canvas.getBoundingClientRect(),footer=document.querySelector('.war-dock,.battle-bottom')?.getBoundingClientRect();
    this.bridge.camera.setWidth(this.scale.gameSize.width);this.bridge.camera.update(battle,delta,this.bridge.reducedMotion());
    this.cameras.main.scrollX=this.bridge.camera.x;this.cameras.main.scrollY=footer ? Math.max(0,GROUND-(footer.top-canvas.top-17)*this.scale.gameSize.height/canvas.height) : Math.max(0,GROUND-this.scale.gameSize.height+75);
    this.bridge.cameraChanged();this.game.canvas.dataset.cameraX=String(Math.round(this.bridge.camera.x));this.game.canvas.dataset.visibleWidth=String(this.bridge.camera.width);
    const commonEra=`A${Math.min(Number(battle.state.sides[0].eraId[1]),Number(battle.state.sides[1].eraId[1]))}`;
    if(this.era!==commonEra)this.setBackground(commonEra);
    this.skyTint.clear().fillStyle(0x123447,.04).fillRect(0,0,this.scale.gameSize.width,this.scale.gameSize.height);
    const ids=new Set(battle.state.entities.map(e=>e.id));for(const [id,view] of this.views)if(!ids.has(id)){view.container.destroy(true);this.views.delete(id);}
    for(const entity of battle.state.entities)if(!this.views.has(entity.id))this.views.set(entity.id,this.makeView(entity));
    this.updateTowers(battle);
    for(const event of battle.state.events)if(event.id>this.seen){this.effects(event);this.seen=event.id;}
    const now=battle.state.tick+(battle.state.paused || battle.state.winner!==null ? 0 : this.bridge.interpolation());
    for(const entity of battle.state.entities){const view=this.views.get(entity.id)!;this.promoteAnimation(entity,view);this.updateFighter(entity,view,now);}
    this.updateProjectiles(battle);this.warnings.clear();
    for(const strike of battle.state.ageStrikes){
      const radius=ageSpecials[strike.eraId as keyof typeof ageSpecials].radius,color=strike.side===0 ? 0xf2bd73 : 0xe98572;
      this.warnings.fillStyle(color,.11).fillEllipse(strike.x,GROUND-3,radius*2,38).lineStyle(2,color,.85).strokeEllipse(strike.x,GROUND-3,radius*2,38);
      if(strike.due>battle.state.tick)this.warnings.lineStyle(1,color,.65).lineBetween(strike.x-10,GROUND-3,strike.x+10,GROUND-3).lineBetween(strike.x,GROUND-12,strike.x,GROUND+6);
    }
    for(const cast of battle.state.scheduledSkills){
      if(cast.skillId==='S05'){
        const color=cast.side===0 ? 0xf2d284 : 0xe88774;this.warnings.fillStyle(color,.13).fillEllipse(cast.x,GROUND-3,240,37).lineStyle(2,color,.85).strokeEllipse(cast.x,GROUND-3,240,37);
        this.warnings.lineStyle(1,color,.8).lineBetween(cast.x-12,GROUND-3,cast.x+12,GROUND-3).lineBetween(cast.x,GROUND-10,cast.x,GROUND+5);
      }else if(cast.skillId==='S08' && cast.fieldUntil){
        this.warnings.fillStyle(0xe39846,.25).fillEllipse(cast.x,GROUND-4,150,22).lineStyle(1,0xe0aa57,.8).strokeEllipse(cast.x,GROUND-4,150,22);
        for(let i=0;i<7;i++){const x=cast.x-60+i*20,h=14+(this.bridge.reducedMotion() ? 2 : 6*Math.sin(now*.24+i));this.warnings.lineStyle(3,0xf2cc7c,.7).lineBetween(x,GROUND-6,x+3,GROUND-h);}
      }
    }
    this.aim(battle);
  }
}
