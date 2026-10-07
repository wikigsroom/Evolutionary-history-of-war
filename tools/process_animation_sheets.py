"""Normalize complete generated poses with a shared scale, center root and floor anchor."""
from pathlib import Path
import argparse, colorsys, hashlib, json
from PIL import Image, ImageDraw
import numpy as np
from scipy.ndimage import label, find_objects
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'output/imagegen/epoch-rush/v0.3-animation/raw'
DEST=ROOT/'public/assets/characters/animations'
DEST.mkdir(parents=True,exist_ok=True)
parser=argparse.ArgumentParser();parser.add_argument('--only',default='all');args=parser.parse_args()
actors=sorted(p.stem for p in SOURCE.glob('*.png')) if args.only=='all' else args.only.split(',')
if not actors:raise SystemExit('No generated animation sources; normalization has not run')
manifest_path=ROOT/'src/content/animation-manifest.json'
manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
runtime_path=ROOT/'public/assets/manifest.json'
runtime=json.loads(runtime_path.read_text(encoding='utf-8'))
clips={name:list(range(row*6,(row+1)*6)) for row,name in enumerate(['idle','walk','attack','hurt','death'])}
large={'U14','U24','U34','U44','U54'}
report_path=SOURCE.parent/'normalization-report.json'
try:
 existing_reports=json.loads(report_path.read_text(encoding='utf-8'))
except (FileNotFoundError,json.JSONDecodeError):
 existing_reports=[]
reports=[r for r in existing_reports if r.get('id') not in actors]
def persist():
 manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 runtime_path.write_text(json.dumps(runtime,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 report_path.write_text(json.dumps(sorted(reports,key=lambda r:r.get('id','')),indent=2)+'\n',encoding='utf-8')
def remove_matte(image):
 image=image.convert('RGBA');pixels=[]
 for r,g,b,a in image.getdata():
  magenta=min(r,b)-g
  if magenta>70 and abs(r-b)<110 and r>135 and b>135: pixels.append((0,0,0,0))
  else: pixels.append((r,g,b,a))
 image.putdata(pixels);return image
def enemy_palette(image):
 result=image.copy();pixels=[]
 for r,g,b,a in image.getdata():
  h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
  if a and .47<h<.73 and s>.25 and v>.15:
   red,green,blue=colorsys.hsv_to_rgb(.025,s,v);pixels.append((round(red*255),round(green*255),round(blue*255),a))
  else:pixels.append((r,g,b,a))
 result.putdata(pixels);return result

def extract_poses(image, actor):
 # A model may vary the grid spacing. Preserve each complete silhouette instead of
 # cutting a spear, shield or attack extension at a nominal cell boundary.
 pixels=np.array(image);mask=pixels[:,:,3]>24
 if mask[0].any() or mask[-1].any() or mask[:,0].any() or mask[:,-1].any():
  raise RuntimeError(actor+' silhouette reaches the source canvas edge; repair the source')
 labels,count=label(mask,np.ones((3,3)));areas=np.bincount(labels.ravel());objects=find_objects(labels)
 major=[index+1 for index in range(count) if areas[index+1]>max(300,areas[1:].max()*.15)]
 if len(major)!=30:raise RuntimeError(f'{actor} has {len(major)} separate main silhouettes, expected 30; inspect/repair the source')
 def bounds(index):
  rows,cols=objects[index-1];return (cols.start,rows.start,cols.stop,rows.stop)
 def center(index):
  box=bounds(index);return ((box[0]+box[2])/2,(box[1]+box[3])/2)
 ordered=sorted(major,key=lambda index:center(index)[1]);rows=[sorted(ordered[r*6:(r+1)*6],key=lambda index:center(index)[0]) for r in range(5)]
 # Loose details belong to the nearest complete body; visual review still checks
 # that weapons remain attached and that no source figures touch each other.
 owners={index:index for index in major}
 for index in range(1,count+1):
  if index in owners:continue
  x,y=center(index)
  owners[index]=min(major,key=lambda body:(max(bounds(body)[0]-x,0,x-bounds(body)[2])**2+max(bounds(body)[1]-y,0,y-bounds(body)[3])**2,abs(center(body)[0]-x)+abs(center(body)[1]-y)))
 frames=[];boxes=[];roots=[];source_boxes=[]
 for row in rows:
  for column,index in enumerate(row):
   ids=[part for part,owner in owners.items() if owner==index]
   silhouette=np.isin(labels,ids);ys,xs=np.nonzero(silhouette)
   box=(int(xs.min()),int(ys.min()),int(xs.max())+1,int(ys.max())+1)
   data=pixels[box[1]:box[3],box[0]:box[2]].copy();data[:,:,3]=np.where(silhouette[box[1]:box[3],box[0]:box[2]],data[:,:,3],0)
   frame=Image.fromarray(data);frames.append(frame);boxes.append((0,0,frame.width,frame.height))
   roots.append((column+.5)*image.width/6-box[0]);source_boxes.append(list(box))
 return frames,boxes,roots,source_boxes
for actor in actors:
 if actor in manifest.get('actors',{}) and manifest['actors'][actor].get('review')=='accepted':
  print('Skipping already accepted '+actor)
  continue
 path=SOURCE/(actor+'.png')
 if not path.exists():raise RuntimeError('Missing Sub2 source '+actor)
 metadata_path=path.with_suffix('.metadata.json')
 if not metadata_path.exists():raise RuntimeError('Missing generation provenance '+actor)
 metadata=json.loads(metadata_path.read_text(encoding='utf-8'))
 sha=hashlib.sha256(path.read_bytes()).hexdigest()
 if metadata.get('model')!='gpt-image-2.5' or metadata.get('sha256')!=sha or metadata.get('status')!='generated':raise RuntimeError('Generation provenance does not match '+actor)
 image=remove_matte(Image.open(path))
 frames,boxes,roots,source_boxes=extract_poses(image,actor);edge_contacts=[]
 size=160 if actor.startswith('H') or actor in large else 128
 max_height=max(b[3]-b[1] for b in boxes);max_extent=max(max(root,b[2]-root) for root,b in zip(roots,boxes))
 scale=min((size*.85)/max_height,(size*.46)/max_extent)
 atlas=Image.new('RGBA',(size*6,size*5),(0,0,0,0));normalized=[]
 for index,(cell,bbox,root) in enumerate(zip(frames,boxes,roots)):
  tile=Image.new('RGBA',(size,size),(0,0,0,0))
  scaled=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS)
  x=round(size*.5-root*scale);y=round(size*.9-bbox[3]*scale)
  tile.alpha_composite(scaled,(x,y));normalized.append(tile)
  atlas.alpha_composite(tile,((index%6)*size,(index//6)*size))
 # Invalidate the old review before replacing any texture at its shipping path.
 if actor in manifest['actors']:
  manifest['actors'][actor]['review']='pending'
  manifest['actors'][actor].pop('reviewNote',None)
  manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 own=DEST/(actor+'.png');enemy=DEST/(actor+'-enemy.png')
 atlas.save(own,optimize=True);enemy_palette(atlas).save(enemy,optimize=True)
 sha=hashlib.sha256(path.read_bytes()).hexdigest()
 body_height=round(max(boxes[index][3]-boxes[index][1] for index in range(6))*scale)
 record={'key':'animation.'+actor,'enemyKey':'animation.'+actor+'.enemy','path':'characters/animations/'+own.name,'enemyPath':'characters/animations/'+enemy.name,'frameWidth':size,'frameHeight':size,'bodyHeight':body_height,'anchor':[.5,.9],'clips':clips,'sourceSha256':sha,'sourcePath':path.relative_to(ROOT).as_posix(),'atlasSha256':{'own':hashlib.sha256(own.read_bytes()).hexdigest(),'enemy':hashlib.sha256(enemy.read_bytes()).hexdigest()},'review':'pending'}
 manifest['actors'][actor]=record
 reviews=SOURCE.parent/'reviews';reviews.mkdir(exist_ok=True)
 template={'actorId':actor,'sourceSha256':sha,'atlasSha256':record['atlasSha256'],
           'pixelSockets':{'muzzle':None,'hit':None,'bodyBounds':None},'reviewNote':'','recordings':[],
           'checks':{name:False for name in ['consistentIdentity','weaponAndEra','idleCycle','walkCycle','attackRelease','hurtAndDeath','floorAndScale','noGridOrMatte','friendlyEnemy','muzzleHitSockets','liveCombat']}}
 (reviews/(actor+'-review-template.json')).write_text(json.dumps(template,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 for key,png in [(record['key'],own),(record['enemyKey'],enemy)]:
  runtime['entries'][key]={'key':key,'path':'characters/animations/'+png.name,'kind':'animation','size':list(atlas.size),'anchor':[.5,.9],'status':'processed_pending_visual_review','derivedFrom':str(path.relative_to(ROOT)).replace('\\','/'),'sourceSha256':sha}
 # Diagnostic contact sheets retain the exact cells and can reveal identity or anchor drift.
 preview=Image.new('RGB',(size*6,size*5),(238,231,207));preview.paste(atlas,mask=atlas.getchannel('A'))
 draw=ImageDraw.Draw(preview)
 for row in range(5):draw.line((0,row*size+size*.9,size*6,row*size+size*.9),fill=(157,183,144),width=1)
 preview.save(SOURCE.parent/(actor+'-normalized-review.png'))
 frames_dir=SOURCE.parent/'previews'/actor;frames_dir.mkdir(parents=True,exist_ok=True)
 for row,name in enumerate(clips):
  strip=[]
  for tile in normalized[row*6:(row+1)*6]:
   bg=Image.new('RGBA',tile.size,(238,231,207,255));bg.alpha_composite(tile);strip.append(bg.convert('RGB'))
  strip[0].save(frames_dir/(name+'.gif'),save_all=True,append_images=strip[1:],duration=100 if name=='walk' else 150,loop=0,disposal=2)
 reports.append({'id':actor,'frames':30,'frameSize':size,'bodyHeight':body_height,'scale':scale,'decodedBytesBothTeams':size*size*30*4*2,'edgeContacts':edge_contacts,'sourceBoxes':source_boxes,'extraction':'30 isolated full silhouettes; nominal grid root; common scale; floor anchor','status':'pending_visual_review'})
 persist()
print(json.dumps({'processed':len(reports),'authoredPoseFrames':len(reports)*30,'decodedBytesBothTeams':sum(r['decodedBytesBothTeams'] for r in reports)}))
