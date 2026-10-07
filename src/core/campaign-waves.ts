import {catalog} from '../content/catalog';
import type {BattleState} from './types';
/** Campaign reinforcements have visible rally breaks and finite reserves. */
export function campaignWave(state:BattleState){
  const mission=state.config.mode==='campaign' && state.config.missionId ? catalog.missions[state.config.missionId] : undefined;
  if(!mission)return null;
  const total=mission.reinforcements?.waves ?? Math.min(6,mission.chapter+3)+(mission.boss ? 1 : 0);
  const period=mission.reinforcements?.periodSec ?? 52+mission.chapter*4;
  const active=mission.reinforcements?.deploySec ?? 26+mission.chapter*3;
  const seconds=state.tick/30,index=Math.floor(seconds/period),phase=seconds%period;
  return {wave:Math.min(total,index+1),total,deploying:index<total && phase<active,exhausted:index>=total || index===total-1 && phase>=active,nextSec:index>=total || index===total-1 && phase>=active ? 0 : Math.ceil(phase<active ? active-phase : period-phase)};
}
export function reinforcementWindow(state:BattleState){
  const campaign=campaignWave(state);if(campaign)return campaign;
  if(state.config.mode==='trial')return null;
  const active=state.config.difficultyId==='D01' ? 38 : state.config.difficultyId==='D03' ? 54 : 48;
  const phase=state.tick/30%60;
  return {wave:Math.floor(state.tick/1800)+1,total:null,deploying:phase<active,exhausted:false,nextSec:Math.ceil(phase<active ? active-phase : 60-phase)};
}
