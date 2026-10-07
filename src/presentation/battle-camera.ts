import { clamp,worldX,type Entity } from '../core/types';
import type { Battle } from '../core/battle';

export type CameraAnchor='ally'|'enemy'|'hero'|'front';
/** Camera navigation is cosmetic: it never changes simulation positions or time. */
export class BattleCamera {
  readonly worldWidth=1600;
  width=1000;
  x=0;
  tracking: 'free'|'hero'|'front'='free';
  dragging=false;
  private startX=0;
  private startY=0;
  private startScroll=0;
  private moved=false;
  reset(width=1000){this.width=width;this.x=0;this.tracking='free';this.dragging=false;this.moved=false;}
  setWidth(width:number){this.width=clamp(width,400,this.worldWidth);this.x=clamp(this.x,0,this.worldWidth-this.width);}
  pan(amount:number){this.tracking='free';this.x=clamp(this.x+amount,0,this.worldWidth-this.width);}
  focus(position:number){this.x=clamp(position-this.width*.5,0,this.worldWidth-this.width);}
  jump(anchor:CameraAnchor,battle:Battle){
    this.tracking=anchor==='hero' || anchor==='front' ? anchor : 'free';
    if(anchor==='ally')this.x=0;
    else if(anchor==='enemy')this.x=this.worldWidth-this.width;
    else this.focus(this.target(battle,anchor));
  }
  private target(battle:Battle,anchor:'hero'|'front'){
    const fighters=battle.living(0).filter((entity:Entity)=>entity.kind!=='base');
    return anchor==='hero' ? worldX(battle.hero(0) ?? battle.base(0)) : Math.max(120,...fighters.map(worldX));
  }
  update(battle:Battle,delta:number,reducedMotion:boolean){
    if(this.tracking==='free' || this.dragging)return;
    const target=clamp(this.target(battle,this.tracking)-this.width*.5,0,this.worldWidth-this.width);
    this.x=reducedMotion ? target : this.x+(target-this.x)*(1-Math.exp(-Math.min(delta,100)/180));
  }
  begin(screenX:number,screenY:number){this.dragging=true;this.startX=screenX;this.startY=screenY;this.startScroll=this.x;this.moved=false;}
  drag(screenX:number,screenY:number,worldPerScreenPixel:number){
    if(!this.dragging)return;
    if(Math.hypot(screenX-this.startX,screenY-this.startY)>=7)this.moved=true;
    if(this.moved){this.tracking='free';this.x=clamp(this.startScroll-(screenX-this.startX)*worldPerScreenPixel,0,this.worldWidth-this.width);}
  }
  end(){const wasDrag=this.moved;this.dragging=false;this.moved=false;return wasDrag;}
  worldAt(viewportX:number){return this.x+viewportX;}
}
