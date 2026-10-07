import {existsSync,readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const checks=['consistentIdentity','weaponAndEra','idleCycle','walkCycle','attackRelease','hurtAndDeath','floorAndScale','noGridOrMatte','friendlyEnemy','muzzleHitSockets','liveCombat'];
const phases=['idle','walk','attack','hurt','death'];
const hash=file=>createHash('sha256').update(readFileSync(file)).digest('hex');
const json=file=>JSON.parse(readFileSync(file,'utf8').replace(/^\uFEFF/,''));
function localFile(root,name){
  if(typeof name!=='string' || path.isAbsolute(name))throw new Error('Expected a relative artifact path');
  const file=path.resolve(root,name),relative=path.relative(root,file);
  if(relative.startsWith('..') || path.isAbsolute(relative) || !existsSync(file))throw new Error('Artifact missing or outside workspace: '+name);
  return file;
}
function verifyActor(root,id,sheet,runtime){
  if(!sheet || sheet.review!=='accepted')throw new Error('Visual review is pending');
  if(!sheet.reviewNote || !checks.every(key=>sheet.reviewChecks?.[key]===true))throw new Error('Visual checks missing');
  const source=localFile(root,sheet.sourcePath),metadata=json(source.replace(/\.png$/,'.metadata.json'));
  if(metadata.model!=='gpt-image-2.5' || metadata.route!=='Sub2 CLI edit' || metadata.status!=='generated' || hash(source)!==sheet.sourceSha256 || metadata.sha256!==sheet.sourceSha256)throw new Error('Generation source/provenance changed');
  if(hash(localFile(root,`output/imagegen/epoch-rush/v0.3-animation/prompts/${id}.txt`))!==metadata.promptSha256)throw new Error('Generation recipe changed');
  if(![128,160].includes(sheet.frameWidth) || sheet.frameHeight!==sheet.frameWidth || sheet.bodyHeight<24 || sheet.bodyHeight>sheet.frameHeight || JSON.stringify(sheet.anchor)!=='[0.5,0.9]')throw new Error('Invalid normalized geometry');
  if(!phases.every((phase,row)=>JSON.stringify(sheet.clips?.[phase])===JSON.stringify(Array.from({length:6},(_,i)=>row*6+i))))throw new Error('Canonical 30-frame sequence missing');
  for(const [side,key] of [['own','path'],['enemy','enemyPath']]){
    const file=localFile(path.join(root,'public/assets'),sheet[key]),bytes=readFileSync(file);
    if(hash(file)!==sheet.atlasSha256?.[side] || bytes.toString('hex',0,8)!=='89504e470d0a1a0a' || bytes.readUInt32BE(16)!==sheet.frameWidth*6 || bytes.readUInt32BE(20)!==sheet.frameHeight*5)throw new Error('Normalized atlas changed: '+side);
  }
  for(const key of ['muzzle','hit'])if(!Array.isArray(sheet[key]) || sheet[key].length!==2 || !sheet[key].every(Number.isFinite))throw new Error('Calibrated socket missing: '+key);
  if(!Number.isInteger(sheet.bodyRadius) || sheet.bodyRadius<8 || sheet.bodyRadius>110)throw new Error('Calibrated body footprint missing');
  const reviewFile=localFile(root,sheet.reviewFile?.path),review=json(reviewFile);
  if(hash(reviewFile)!==sheet.reviewFile.sha256 || review.actorId!==id || review.sourceSha256!==sheet.sourceSha256 || JSON.stringify(review.atlasSha256)!==JSON.stringify(sheet.atlasSha256) || review.reviewNote.trim()!==sheet.reviewNote || !checks.every(key=>review.checks?.[key]===true))throw new Error('Bound review record changed');
  const combinations=new Set();
  for(const record of sheet.reviewEvidence ?? []){
    const sidecar=localFile(root,record.metadataPath),clip=json(sidecar),video=localFile(root,record.videoPath);
    const relative=path.relative(path.join(root,'output/qa/v0.3/motion-clips'),sidecar);
    if(relative.startsWith('..') || hash(sidecar)!==record.metadataSha256 || hash(video)!==record.videoSha256 || clip.bytes!==readFileSync(video).length)throw new Error('Recording evidence changed');
    if(clip.kind!=='epoch_animation_review' || clip.mode!=='sequence' || clip.live!==false || clip.completeSequence!==true || clip.tickStart!==0 || clip.tickEnd<251 || !clip.visibleActorIds?.includes(id) || ![0,1].includes(clip.side) || ![1,.25].includes(clip.speed))throw new Error('Recording does not show a complete visible sequence');
    const pose=clip.sources?.[id],expected=251/30/clip.speed;
    if(pose?.representation!=='authored_pose' || pose.sourceSha256!==sheet.sourceSha256 || pose.atlasSha256!==sheet.atlasSha256[clip.side===0 ? 'own' : 'enemy'] || Math.abs(record.decodedDurationSec-expected)>expected*.15 || record.capturedFrames<100 || Math.abs(clip.durationSec-expected)>expected*.15)throw new Error('Recording uses different art or speed');
    if(pose.bodyRadius!==sheet.bodyRadius || JSON.stringify(pose.muzzle)!==JSON.stringify(sheet.muzzle) || JSON.stringify(pose.hit)!==JSON.stringify(sheet.hit))throw new Error('Recording uses a different footprint or weapon socket');
    combinations.add(`${clip.side}:${clip.speed}`);
  }
  if(!['0:1','0:0.25','1:1','1:0.25'].every(pair=>combinations.has(pair)))throw new Error('Both teams require original and quarter-speed recordings');
  const prefix=id.startsWith('H') ? 'hero' : 'unit',keys=[`${prefix}.${id}`,`${prefix}.${id}.enemy`,...(!id.startsWith('H') ? [`icon.${id}`] : [])];
  for(const key of keys){
    const derivative=sheet.visualDerivatives?.find(entry=>entry.key===key),entry=runtime.entries[key];
    if(!derivative || !entry || entry.status!=='visual_review_accepted' || entry.path!==derivative.path || entry.sourceSha256!==sheet.sourceSha256 || hash(localFile(path.join(root,'public/assets'),entry.path))!==derivative.sha256 || entry.sha256!==derivative.sha256)throw new Error('Portrait/card still differs from the accepted actor: '+key);
  }
}
/** Candidate builds retain explicit pending art; final builds verify the exact reviewed files. */
export function assertAnimationRelease(root,candidate=false){
  const manifest=json(path.join(root,'src/content/animation-manifest.json')),runtime=json(path.join(root,'public/assets/manifest.json'));
  const expected=['units','heroes'].flatMap(name=>JSON.parse(readFileSync(path.join(root,`docs/epoch-rush/data/${name}.json`),'utf8')).map(row=>row.id));
  const issues={};
  for(const id of expected)try{verifyActor(root,id,manifest.actors[id],runtime);}catch(error){issues[id]=error.message;}
  const missing=expected.filter(id=>issues[id]);
  if(missing.length && !candidate)throw new Error(`Final release blocked: ${missing.length}/${expected.length} actors still need reviewed gpt-image-2.5 animation sheets. Use --candidate for an explicitly named preview.`);
  return {candidate,requiredActors:expected.length,acceptedActors:expected.length-missing.length,missing,issues};
}
if(process.argv[1] && path.resolve(process.argv[1])===path.resolve(fileURLToPath(import.meta.url))){
  const root=process.cwd(),candidate=process.argv.includes('--candidate');
  console.log(JSON.stringify(assertAnimationRelease(root,candidate),null,2));
}
