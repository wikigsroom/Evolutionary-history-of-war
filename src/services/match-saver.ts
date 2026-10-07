import type {BattleState} from '../core/types';
import type {StoragePort} from './storage';

/** Every explicit save has its own completion promise; ending a match waits for older writes. */
export class MatchSaver {
  private queue=Promise.resolve();
  constructor(private storage:StoragePort){}
  save(state:BattleState):Promise<BattleState>{
    const frozen=structuredClone(state);
    const operation=this.queue.then(async()=>{await this.storage.writeAtomic('match',frozen);return frozen;});
    this.queue=operation.then(()=>undefined,()=>undefined);
    return operation;
  }
  async flush(){await this.queue;}
}
