import raw from '../content/animation-manifest.json';
import {clamp,type Entity} from '../core/types';
export interface AnimationSheet {key:string;enemyKey:string;path:string;enemyPath:string;frameWidth:number;frameHeight:number;bodyHeight:number;anchor:[number,number];clips:{idle:number[];walk:number[];attack:number[];hurt:number[];death:number[]};sourceSha256:string;atlasSha256?:{own:string;enemy:string};muzzle?:[number,number];hit?:[number,number];bodyRadius?:number;review?:'pending'|'accepted'|'rejected'}
const reviewing=import.meta.env.DEV && typeof location!=='undefined' && new URLSearchParams(location.search).get('review')==='combat';
export const animationSheets=Object.fromEntries(Object.entries(raw.actors as unknown as Record<string,AnimationSheet>).filter(([,sheet])=>sheet.review==='accepted' || reviewing && sheet.review!=='rejected'));
export interface AnimationClock {now:number;releasedAt:number;hitAt:number;skillAt:number;previousFrame:number;reducedMotion:boolean}
/** Frames follow the fixed simulation's windup and release, rather than a free-running loop. */
export function actorFrame(entity:Entity,sheet:AnimationSheet,clock:AnimationClock):number{
  const {now}=clock,clips=sheet.clips;
  if(entity.hp<=0)return clips.death[Math.min(clips.death.length-1,Math.floor(Math.max(0,now-entity.bornTick)/3))];
  const releaseAge=now-clock.releasedAt,hurtAge=now-clock.hitAt;
  if(hurtAge>=0 && hurtAge<2 && clock.previousFrame>=0)return clock.previousFrame;
  if(entity.phase==='windup'){
    const progress=1-clamp((entity.releaseAt-now)/Math.max(1,entity.windup),0,1);
    return clips.attack[Math.min(1,Math.floor(progress*2))];
  }
  if(releaseAge>=0 && releaseAge<12)return clips.attack[Math.min(5,2+Math.floor(releaseAge/3))];
  if(hurtAge>=2 && hurtAge<9)return clips.hurt[Math.min(5,Math.floor((hurtAge-2)*.85))];
  const castAge=now-clock.skillAt;
  if(castAge>=0 && castAge<12)return clips.attack[Math.min(5,Math.floor(castAge/2))];
  if(entity.phase==='move' || entity.phase==='charge'){
    const stride=entity.heavy ? 76 : 48;
    return clips.walk[Math.floor(entity.runDistance/stride*clips.walk.length)%clips.walk.length];
  }
  return clips.idle[clock.reducedMotion ? 0 : Math.floor(Math.max(0,now-entity.bornTick)/6)%clips.idle.length];
}
