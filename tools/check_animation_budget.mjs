import {readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const scene=readFileSync(path.join(root,'src/presentation/battle-scene.ts'),'utf8');
const manifest=JSON.parse(readFileSync(path.join(root,'src/content/animation-manifest.json'),'utf8'));
const bootstrap=scene.match(/for\(const id of \[(.*?)\]\)/s)?.[1]
  ?.match(/'([A-Z]\d{2})'/g)?.map(value=>value.slice(1,-1)) ?? [];
if(!bootstrap.length)throw new Error('Animation bootstrap roster is missing');
const actors=manifest.actors;
const atlasBytes=id=>{
  const sheet=actors[id];
  if(!sheet)throw new Error(`Unknown bootstrap actor: ${id}`);
  return sheet.frameWidth*6*sheet.frameHeight*5*4*2;
};
const initialBytes=bootstrap.reduce((sum,id)=>sum+atlasBytes(id),0);
const budgetBytes=64*1024*1024;
const report={
  version:manifest.version,
  bootstrapActors:bootstrap,
  acceptedActors:Object.values(actors).filter(sheet=>sheet.review==='accepted').length,
  totalActors:Object.keys(actors).length,
  bytesPerActor:Object.fromEntries(bootstrap.map(id=>[id,atlasBytes(id)])),
  initialDecodedBytes:initialBytes,
  budgetBytes,
  withinBudget:initialBytes<budgetBytes,
  strategy:'bootstrap first-era units plus first hero; stream remaining accepted atlases on entity entry',
};
if(!report.withinBudget)throw new Error(`Initial animation atlases exceed budget: ${initialBytes} > ${budgetBytes}`);
if(report.acceptedActors!==report.totalActors)throw new Error(`Animation release is incomplete: ${report.acceptedActors}/${report.totalActors}`);
const out=path.join(root,'output/qa/v0.3/animation-loading-budget.json');
mkdirSync(path.dirname(out),{recursive:true});writeFileSync(out,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
