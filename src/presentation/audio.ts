import {catalog} from '../content/catalog';
import type {BattleEvent,BattleState} from '../core/types';
import {assetPath} from './assets';
import {fighterProfile} from '../core/fighter-profiles';
export class GameAudio {
  private context:AudioContext | null=null;
  private gain:GainNode | null=null;
  private buffers=new Map<string,Promise<AudioBuffer | null>>();
  private voices=new Set<AudioBufferSourceNode>();
  private music:AudioBufferSourceNode | null=null;
  private musicGain:GainNode | null=null;
  private musicKey='';
  private desiredMusic='music.menu';
  private last=0;
  private recent=new Map<string,number>();
  private variants=new Map<string,number>();
  volume=.65;muted=false;
  async unlock(){
    this.context ??=new AudioContext();
    if(!this.gain){this.gain=this.context.createGain();this.gain.connect(this.context.destination);}
    this.gain.gain.value=this.muted ? 0 : this.volume;
    await this.context.resume();void this.setMusic(this.desiredMusic);
  }
  private buffer(key:string):Promise<AudioBuffer | null>{
    let promise=this.buffers.get(key);
    if(!promise){const path=assetPath(key),context=this.context;promise=path && context ? fetch(path).then(response=>{if(!response.ok)throw new Error('Audio unavailable');return response.arrayBuffer();}).then(data=>context.decodeAudioData(data)).catch(()=>null) : Promise.resolve(null);this.buffers.set(key,promise);}
    return promise;
  }
  async setMusic(key:string){
    this.desiredMusic=key;
    if(!this.context || !this.gain || this.musicKey===key)return;
    const buffer=await this.buffer(assetPath(key+'.ogg') ? key+'.ogg' : key);if(!buffer || this.desiredMusic!==key || this.musicKey===key)return;
    const context=this.context,now=context.currentTime,old=this.music,oldGain=this.musicGain;
    if(old && oldGain){oldGain.gain.cancelScheduledValues(now);oldGain.gain.setTargetAtTime(.001,now,.15);old.stop(now+.55);old.onended=()=>{old.disconnect();oldGain.disconnect();};}
    const source=context.createBufferSource(),gain=context.createGain();source.buffer=buffer;source.loop=!['music.victory','music.defeat','music.draw'].includes(key);source.connect(gain);gain.connect(this.gain);gain.gain.setValueAtTime(0,now);gain.gain.linearRampToValueAtTime(.32,now+(source.loop ? .7 : .12));source.start();
    this.music=source;this.musicGain=gain;this.musicKey=key;
  }
  setMuted(value:boolean){this.muted=value;if(this.gain)this.gain.gain.value=value ? 0 : this.volume;}
  suspend(){void this.context?.suspend();}
  reset(){this.last=0;this.recent.clear();}
  private async play(key:string,volume=.3){
    const context=this.context;if(!context || context.state!=='running' || !this.gain || this.muted || this.voices.size>=8)return;
    const variation=this.variants.get(key) ?? 0;this.variants.set(key,variation+1);
    const variant=variation%3===0 ? key : key+'.v'+(variation%3+1);
    const buffer=await this.buffer(assetPath(variant) ? variant : key);if(!buffer || context.state!=='running' || this.voices.size>=8)return;
    const source=context.createBufferSource(),gain=context.createGain();source.buffer=buffer;source.playbackRate.value=[1,.982,1.018][variation%3] ?? 1;gain.gain.value=volume;source.connect(gain);gain.connect(this.gain);this.voices.add(source);source.start();source.onended=()=>{this.voices.delete(source);source.disconnect();gain.disconnect();};
  }
  confirm(){void this.play('sfx.ui_confirm',.3);}
  error(){void this.play('sfx.ui_error',.3);}
  consume(events:BattleEvent[],state:BattleState){
    for(const event of events){
      if(event.id<=this.last)continue;this.last=event.id;
      const now=performance.now(),gap=event.type==='hit' ? 70 : event.type==='death' ? 100 : 35;
      let key='';
      const target=state.entities.find(entity=>entity.id===event.targetId);
      if(event.type==='hit'){
        if(event.absorbed)void this.play('sfx.shield_hit',.25);
        if(!event.amount)continue;
        const material=target?.kind==='base' ? Number(target.eraId.slice(1))<4 ? 'stone' : 'metal' : fighterProfile(target?.contentId ?? '').material;
        key=event.damageType==='blast' ? 'sfx.cannon_hit' : event.damageType==='energy' ? 'sfx.energy_hit' : event.weaponId==='W03' && material==='flesh' ? 'sfx.arrow_hit' : 'sfx.'+material+'_hit';
      }
      else if(event.type==='shieldBreak')key='sfx.shield_break';
      else if(event.type==='queue' && event.side===0)key='sfx.queue_add';
      else if(event.type==='spawn')key=target?.kind==='hero' && event.tick>0 ? 'sfx.hero_respawn' : 'sfx.unit_spawn';
      else if(event.type==='rejoin')key='sfx.hero_respawn';
      else if(event.type==='release'){
        const cue:Record<string,string>={W01:'stone_throw',W02:'sword_swing',W03:'arrow_fire',W04:'musket_fire',W05:'cannon_fire',W06:'spear_swing',W07:'arc_fire',W08:'support_pulse'};
        key='sfx.'+(cue[event.weaponId ?? 'W02'] ?? 'sword_swing');
      }
      else if(event.type==='arc')key='sfx.arc_fire';
      else if(event.type==='cast')key='sfx.skill_cast';
      else if(event.type==='evolve')key='sfx.evolve';
      else if(event.type==='ageWarn' && event.side===1)key='sfx.danger_warning';
      else if(event.type==='ageImpact')key=event.text==='A5' ? 'sfx.orbital_impact' : event.text==='A4' ? 'sfx.airstrike' : event.text==='A3' ? 'sfx.arrow_rain' : 'sfx.meteor_impact';
      else if(event.type==='rush')key='sfx.rush_flag';
      else if(event.type==='death')key=target?.kind==='hero' ? 'sfx.hero_death' : 'sfx.unit_death';
      else if(event.type==='reward' && event.side===0)key='sfx.loot_collect';
      else if(event.type==='end')key='sfx.base_destroyed';
      else if(event.type==='heal')key='sfx.heal';
      else if(event.type==='research' && event.side===0)key='sfx.research_complete';
      else if(event.type==='item')key=event.text==='war-drum' ? 'sfx.item_drum' : event.text==='smoke-bomb' ? 'sfx.item_smoke' : 'sfx.item_supply';
      if(key){if(now-(this.recent.get(key) ?? -1000)<gap)continue;this.recent.set(key,now);void this.play(key,key==='sfx.cannon_hit' ? .6 : .25);}
    }
  }
}
