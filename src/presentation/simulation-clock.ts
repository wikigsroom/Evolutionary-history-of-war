const STEP=1000/30;
/** Rendering may run at any refresh rate; combat advances in complete 30 Hz ticks. */
export function advanceSimulation(accumulator:number,delta:number,step:()=>void){
  accumulator+=Math.min(Math.max(0,delta),166.7);let steps=0;
  while(accumulator+1e-7>=STEP && steps<5){step();accumulator=Math.max(0,accumulator-STEP);steps++;}
  return {accumulator:steps===5 ? Math.min(accumulator,STEP) : accumulator,steps};
}
