import {clamp,type Entity} from '../core/types';

export type MotionClass='biped'|'mounted'|'chariot'|'vehicle'|'mech';
export interface MotionContext{now:number;releasedAt:number;hitAt:number;hitDirection:number;skillAt:number;motionClass:MotionClass;reducedMotion:boolean}
export interface Pose{angle:number;x:number;y:number;scaleX:number;scaleY:number;alpha:number;parts:Record<string,{angle:number;x:number;y:number}>}
const ease=(v:number)=>1-Math.pow(1-clamp(v,0,1),3);
/** Attack preparation, release and recovery use simulation timestamps, never independent looping attacks. */
export function fighterPose(entity:Entity,context:MotionContext):Pose{
  const {now,motionClass,reducedMotion}=context;
  const pose:Pose={angle:0,x:0,y:0,scaleX:1,scaleY:1,alpha:1,parts:{}};
  const dead=entity.hp<=0,elapsed=clamp((now-entity.bornTick)/24,0,1);
  if(dead){pose.alpha=1-ease(Math.max(0,(elapsed-.25)/.75));pose.angle=reducedMotion ? 0 : ease(elapsed)*(motionClass==='vehicle' ? 6 : 76);pose.y=motionClass==='vehicle' ? 0 : elapsed*8;return pose;}
  const spawn=clamp((now-entity.bornTick)/10,0,1);pose.alpha=.3+.7*spawn;
  if(reducedMotion){
    // Accessibility removes decorative movement, while preserving action cues.
    if(entity.phase==='windup')pose.parts.weapon={angle:-8,x:-2,y:0};
    const releaseAge=now-context.releasedAt;
    if(releaseAge>=0 && releaseAge<7)pose.parts.weapon={angle:entity.range>=100 ? -5 : 18,x:entity.range>=100 ? -4 : 4,y:0};
    return pose;
  }
  pose.y=(1-ease(spawn))*-9;
  const isMoving=entity.phase==='move' || entity.phase==='charge';
  const quadruped=motionClass==='mounted' || motionClass==='chariot';
  const stride=entity.runDistance/(quadruped ? 72 : motionClass==='mech' ? 95 : 54)*Math.PI*2;
  const goingBack=(entity.x-(entity.previousX ?? entity.x))*(entity.side===0 ? 1 : -1)<0;
  const gait=stride*(goingBack ? -1 : 1),bob=isMoving ? Math.cos(gait*2)*1.7 : Math.sin(now/30*2.6+entity.id)*.65;
  const windup=entity.phase==='windup' ? ease(1-clamp((entity.releaseAt-now)/Math.max(entity.windup,1),0,1)) : 0;
  const releaseAge=now-context.releasedAt,release=releaseAge>=0 && releaseAge<9 ? Math.exp(-releaseAge/2.6) : 0;
  const ranged=entity.range>=100,gun=['W04','W05','W06','W07'].includes(entity.weaponId),bow=entity.weaponId==='W03';
  const skillAge=now-context.skillAt,skill=skillAge>=0 && skillAge<16 ? Math.sin(Math.PI*clamp(skillAge/16,0,1)) : 0;
  pose.x=(ranged ? -windup*2-release*(gun ? 5 : 1) : -windup*3+release*9);
  pose.angle=isMoving ? (goingBack ? -2 : motionClass==='vehicle' ? 0 : 3) : -windup*2+release*3;
  if(entity.phase==='charge'){pose.angle=10;pose.x+=5;pose.y-=2;}
  pose.parts.body={angle:0,x:0,y:bob+(motionClass==='mounted' ? Math.sin(gait)*1.2 : 0)};
  pose.parts.head={angle:-windup*2+release*2,x:windup*-1+release*2,y:bob*.8};
  pose.parts.weapon={angle:ranged ? windup*(bow ? -8 : -3)+release*(gun ? -5 : 4)-skill*12 : -windup*23+release*38-skill*10,x:ranged ? -windup*(bow ? 4 : 0)-release*(gun ? 9 : 2) : -windup*2+release*5,y:bob};
  if(entity.contentId==='H03')pose.parts.weapon={angle:-windup*6+release*12,x:-windup*2+release*8,y:bob};
  pose.parts.cloth={angle:isMoving ? Math.sin(gait+.8)*7+(goingBack ? -5 : 5) : Math.sin(now/30*2)*1.5,x:0,y:bob};
  const feet=quadruped ? 4 : 2;
  for(let i=0;i<feet;i++){
    const wave=Math.sin(gait+(quadruped ? i*Math.PI/2 : i*Math.PI));
    pose.parts['leg'+i]={angle:isMoving ? wave*(quadruped ? 12 : motionClass==='mech' ? 7 : 11) : windup*(i%2 ? 2 : -2),x:isMoving ? -wave*1.7 : 0,y:isMoving ? -Math.max(0,wave)*3.5 : 0};
  }
  pose.parts.track={angle:0,x:isMoving ? Math.sin(gait*3)*1.1 : 0,y:isMoving ? Math.sin(gait*4)*.65 : 0};
  pose.parts.wheel={angle:isMoving ? entity.runDistance/16*180/Math.PI : 0,x:0,y:0};
  if(motionClass==='chariot'){pose.parts.body.y=isMoving ? Math.sin(gait*4)*.55 : 0;pose.parts.cloth.angle*=.6;pose.parts.head.y*=.5;}
  if(motionClass==='mech'){pose.parts.body.y=isMoving ? Math.abs(Math.sin(gait))*1.2 : 0;pose.parts.weapon.angle*=.4;pose.angle*=.35;}
  if(motionClass==='vehicle'){pose.parts.body.y=isMoving ? Math.sin(gait*4)*.6 : 0;pose.parts.weapon.x-=release*4;pose.angle=0;}
  const hurtAge=now-context.hitAt,hurt=hurtAge>=0 && hurtAge<7 ? Math.sin(Math.PI*hurtAge/7)*(1-hurtAge/7) : 0;
  pose.x+=hurt*context.hitDirection*(entity.heavy ? 2 : 6)*(entity.side===0 ? 1 : -1);
  pose.angle+=hurt*context.hitDirection*(entity.heavy ? 1 : 5)*(entity.side===0 ? 1 : -1);
  return pose;
}
