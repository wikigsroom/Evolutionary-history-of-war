"""Generate/normalize the complete ten-era pack with at most two native Sub2 jobs."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED
from datetime import datetime, timezone
from io import BytesIO
import argparse, colorsys, hashlib, json, os, shutil, subprocess, sys, time, zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance
from scipy.ndimage import label, find_objects
from expand_ten_eras import ROOT, OUT, QA, REUSE, HERO_DETAILS, baseline

ASSETS=ROOT/'godot/assets'
CLI=ROOT/'tools/sub2_image_compat.py'
CLIPS={name:list(range(i*6,(i+1)*6)) for i,name in enumerate(['idle','walk','attack','hurt','death'])}

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_suffix(path.suffix+'.tmp');temp.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');os.replace(temp,path)

def set_base_orientation(era_id, enemy_mirrored):
    """Record whether the enemy PNG already includes its horizontal mirror."""
    path=ASSETS/'data/eras.json';eras=read(path)
    for era in eras:
        if era['id']==era_id:
            era['enemyBaseMirrored']=enemy_mirrored
            write(path,eras)
            return
    raise ValueError('Unknown base era: '+era_id)

def remove_matte(image):
    data=np.array(image.convert('RGBA'))
    r=data[:,:,0].astype(int);g=data[:,:,1].astype(int);b=data[:,:,2].astype(int)
    matte=(np.minimum(r,b)-g>65)&(np.abs(r-b)<125)&(r>130)&(b>130)
    data[matte]=0
    return Image.fromarray(data)

def enemy_palette(image):
    data=np.array(image.convert('RGBA'));r=data[:,:,0].astype(float);g=data[:,:,1].astype(float);b=data[:,:,2].astype(float)
    mask=(data[:,:,3]>0)&(b>r*1.12)&(b>g*.9)&(np.maximum.reduce([r,g,b])-np.minimum.reduce([r,g,b])>38)
    data[:,:,0][mask]=np.clip(b[mask]*1.05,0,255);data[:,:,1][mask]=np.clip(g[mask]*.65,0,255);data[:,:,2][mask]=np.clip(r[mask]*.8,0,255)
    return Image.fromarray(data)

def cells(image,columns,rows,count=None):
    for i in range(count or columns*rows):
        left=round(i%columns*image.width/columns);right=round((i%columns+1)*image.width/columns)
        top=round(i//columns*image.height/rows);bottom=round((i//columns+1)*image.height/rows)
        yield image.crop((left,top,right,bottom))

def source_image(job):return Image.open(OUT/'raw'/f'{job["name"]}.png').convert('RGBA')
def padded_seed(image):
    transparent=remove_matte(image);box=transparent.getchannel('A').getbbox()
    if not box:raise RuntimeError('Empty generated seed cell')
    subject=transparent.crop(box);subject.thumbnail((400,430),Image.Resampling.NEAREST)
    canvas=Image.new('RGBA',(512,512),(255,0,255,255));canvas.alpha_composite(subject,((512-subject.width)//2,460-subject.height))
    return canvas.convert('RGB')

def isolated_frames(image,actor):
    pixels=np.array(remove_matte(image));mask=pixels[:,:,3]>24
    if mask[0].any() or mask[-1].any() or mask[:,0].any() or mask[:,-1].any():raise RuntimeError(actor+' reaches source canvas edge')
    labels,count=label(mask,np.ones((3,3)));areas=np.bincount(labels.ravel());objects=find_objects(labels)
    major=[i+1 for i in range(count) if areas[i+1]>max(230,areas[1:].max()*.13)]
    if len(major)!=30:raise RuntimeError(f'{actor}: {len(major)} complete silhouettes, expected 30')
    def bounds(index):
        y,x=objects[index-1];return (x.start,y.start,x.stop,y.stop)
    def center(index):
        box=bounds(index);return ((box[0]+box[2])/2,(box[1]+box[3])/2)
    ordered=sorted(major,key=lambda i:center(i)[1]);rows=[sorted(ordered[r*6:r*6+6],key=lambda i:center(i)[0]) for r in range(5)]
    owners={i:i for i in major}
    for i in range(1,count+1):
        if i in owners:continue
        x,y=center(i);owners[i]=min(major,key=lambda body:(max(bounds(body)[0]-x,0,x-bounds(body)[2])**2+max(bounds(body)[1]-y,0,y-bounds(body)[3])**2,abs(center(body)[0]-x)+abs(center(body)[1]-y)))
    frames=[];roots=[];boxes=[]
    for row in rows:
        for column,index in enumerate(row):
            owned=[i for i,owner in owners.items() if owner==index];silhouette=np.isin(labels,owned);ys,xs=np.nonzero(silhouette)
            box=(int(xs.min()),int(ys.min()),int(xs.max())+1,int(ys.max())+1)
            data=pixels[box[1]:box[3],box[0]:box[2]].copy();data[:,:,3]=np.where(silhouette[box[1]:box[3],box[0]:box[2]],data[:,:,3],0)
            frames.append(Image.fromarray(data));roots.append((column+.5)*image.width/6-box[0]);boxes.append(box)
    return frames,roots,boxes

def normalize_animation(job):
    actor=job['actor'];frames,roots,boxes=isolated_frames(source_image(job),actor)
    size=128 if actor.startswith('U') and actor.endswith('4') else 96
    max_height=max(frame.height for frame in frames);extent=max(max(root,frame.width-root) for root,frame in zip(roots,frames))
    scale=min(size*.83/max_height,size*.46/extent)
    atlas=Image.new('RGBA',(size*6,size*5));tiles=[]
    for i,(frame,root) in enumerate(zip(frames,roots)):
        frame=frame.resize((max(1,round(frame.width*scale)),max(1,round(frame.height*scale))),Image.Resampling.NEAREST)
        tile=Image.new('RGBA',(size,size));x=round(size*.5-root*scale);y=round(size*.9-frame.height)
        tile.alpha_composite(frame,(x,y));box=tile.getchannel('A').getbbox()
        if not box or min(box[:2])==0 or box[2]>=size or box[3]>=size:raise RuntimeError(actor+' normalized silhouette clipped')
        tiles.append(tile);atlas.alpha_composite(tile,((i%6)*size,(i//6)*size))
    own=ASSETS/'characters/animations'/f'{actor}.png';enemy=own.with_name(actor+'-enemy.png');own.parent.mkdir(parents=True,exist_ok=True)
    atlas.save(own,optimize=True);enemy_palette(atlas).save(enemy,optimize=True)
    metadata=read(ASSETS/'data/animations.json');body_height=max(tiles[i].getchannel('A').getbbox()[3]-tiles[i].getchannel('A').getbbox()[1] for i in range(6))
    role_slot=int(actor[-1]) if actor.startswith('U') else 0
    metadata[actor]={'path':own.relative_to(ASSETS).as_posix(),'enemyPath':enemy.relative_to(ASSETS).as_posix(),
        'frameWidth':size,'frameHeight':size,'columns':6,'rows':5,'bodyHeight':body_height,'anchor':[.5,.9],
        'clips':CLIPS,'sourcePath':(OUT/'raw'/f'{actor}.png').relative_to(ROOT).as_posix(),'sourceSha256':sha(OUT/'raw'/f'{actor}.png'),
        'atlasSha256':{'own':sha(own),'enemy':sha(enemy)},'bodyRadius':24 if actor.startswith('H') else 38 if role_slot==4 else 22 if role_slot==1 else 16,
        'muzzle':[42.0,73.0] if actor.startswith('H') else [50.0,76.0] if role_slot==4 else [35.0,57.0],
        'hit':[0.0,66.0] if actor.startswith('H') else [0.0,68.0] if role_slot==4 else [0.0,54.0],
        'review':'pending_visual_review','generatedModel':'gpt-image-2.5'}
    write(ASSETS/'data/animations.json',metadata)
    preview=Image.new('RGBA',atlas.size,(238,231,207,255));preview.alpha_composite(atlas)
    folder=OUT/'previews';folder.mkdir(exist_ok=True);preview.convert('RGB').save(folder/f'{actor}.png')
    for row,clip in enumerate(CLIPS):
        frames_gif=[]
        for tile in tiles[row*6:row*6+6]:
            bg=Image.new('RGBA',tile.size,(238,231,207,255));bg.alpha_composite(tile);frames_gif.append(bg.convert('RGB'))
        frames_gif[0].save(folder/f'{actor}-{clip}.gif',save_all=True,append_images=frames_gif[1:],duration=110 if clip=='walk' else 140,loop=0,disposal=2)
    icon=tiles[0].resize((96,96),Image.Resampling.NEAREST)
    icon_path=ASSETS/('ui/heroes' if actor.startswith('H') else 'ui/units')/f'{actor}.png';icon_path.parent.mkdir(parents=True,exist_ok=True);icon.save(icon_path,optimize=True)
    return {'actor':actor,'frames':30,'frameSize':size,'bodyHeight':body_height,'sourceBoxes':boxes,'reviewStatus':'pending_visual_review'}

def process(job):
    image=source_image(job);kind=job['kind'];result={'name':job['name'],'kind':kind,'sourceSize':list(image.size)}
    if kind=='animation':result.update(normalize_animation(job))
    elif kind=='maps':
        folder=ASSETS/'environment/eras';folder.mkdir(parents=True,exist_ok=True)
        for i,cell in enumerate(cells(image,1,3),1):cell.convert('RGB').save(folder/f'{job["era"]}-{i}.png',optimize=True)
        result['outputs']=3
    elif kind in ['hero_seeds','unit_seeds']:
        folder=OUT/'seeds';folder.mkdir(exist_ok=True)
        names=[hid+'-'+job['era'] for hid in HERO_DETAILS] if kind=='hero_seeds' else [f'U{job["era"][1:]}{i}' for i in range(1,6)]
        for name,cell in zip(names,cells(image,3,2,len(names))):padded_seed(cell).save(folder/f'{name}.png')
        result['outputs']=len(names)
    elif kind=='base':
        image=remove_matte(image);box=image.getchannel('A').getbbox()
        if not box:raise RuntimeError('Empty base')
        image=image.crop(box);image.thumbnail((440,400),Image.Resampling.NEAREST)
        folder=ASSETS/'base';folder.mkdir(exist_ok=True)
        for suffix,brightness in [('',1.0),('-worn',.85),('-critical',.65),('-ruin',.4)]:
            state=ImageEnhance.Brightness(image).enhance(brightness)
            if suffix=='-ruin':state=state.resize((state.width,max(1,round(state.height*.45))),Image.Resampling.NEAREST)
            state.save(folder/f'{job["era"]}{suffix}.png',optimize=True);enemy_palette(state).save(folder/f'{job["era"]}{suffix}-enemy.png',optimize=True)
        set_base_orientation(job['era'],False)
    elif kind in ['fx','events','ambient','turrets']:
        folder=ASSETS/('fx/eras' if kind=='fx' else 'environment/ambient' if kind=='ambient' else 'fx/events' if kind=='events' else 'environment/turrets');folder.mkdir(parents=True,exist_ok=True)
        names=['carrier','projectile','impact','shock','sparks','smoke'] if kind=='fx' else job.get('names',[])
        if kind=='turrets':names=[f'TR{era}{slot}' for era in range(1,11) for slot in [1,2]]
        columns,rows=(4,3) if kind=='ambient' else (4,5) if kind=='turrets' else (3,2)
        for name,cell in zip(names,cells(image,columns,rows,len(names))):
            cell=remove_matte(cell)
            if kind=='turrets':
                pixels=np.array(cell);labels,count=label(pixels[:,:,3]>24,np.ones((3,3)))
                if not count:raise RuntimeError('Empty turret '+name)
                body=int(np.argmax(np.bincount(labels.ravel())[1:]))+1
                pixels[labels!=body]=0
                cell=Image.fromarray(pixels)
            box=cell.getchannel('A').getbbox()
            if not box:raise RuntimeError('Empty asset cell '+name)
            cell=cell.crop(box);cell.thumbnail((192,192) if kind in ['fx','events'] else (96,96),Image.Resampling.NEAREST)
            path=folder/f'{job["era"]}-{name}.png' if kind=='fx' else folder/f'{name}.png';cell.save(path,optimize=True)
            if kind=='turrets':
                enemy_path=path.with_name(path.stem+'-enemy.png');enemy_palette(cell).save(enemy_path,optimize=True)
                if name.endswith('1'):
                    era=name[2:-1];metadata=read(ASSETS/'data/animations.json')
                    metadata['SUM-A'+era]={'path':path.relative_to(ASSETS).as_posix(),'enemyPath':enemy_path.relative_to(ASSETS).as_posix(),
                        'frameWidth':cell.width,'frameHeight':cell.height,'columns':1,'rows':1,'bodyHeight':cell.height,
                        'anchor':[.5,1.0],'bodyRadius':27,'muzzle':[30,50],'hit':[0,37],
                        'atlasSha256':{'own':sha(path),'enemy':sha(enemy_path)},'clips':{clip:[0] for clip in CLIPS},'sourceSha256':sha(OUT/'raw'/'turret-pack.png'),'review':'pending_visual_review'}
                    write(ASSETS/'data/animations.json',metadata)
    return result

def reuse_originals():
    baseline();metadata=read(ASSETS/'data/animations.json')
    with zipfile.ZipFile(QA/'baseline-0.6.2-sources.zip') as archive:
        old=json.loads(archive.read('godot/assets/data/animations.json').decode('utf-8'))
        for era,old_era in REUSE.items():
            for slot in range(1,6):
                actor=f'U{era}{slot}';source=f'U{old_era}{slot}';row=copy_record=dict(old[source])
                for side,key in [('','path'),('-enemy','enemyPath')]:
                    data=archive.read('godot/assets/'+old[source][key]);destination=ASSETS/f'characters/animations/{actor}{side}.png';destination.write_bytes(data);row[key]=destination.relative_to(ASSETS).as_posix()
                row['columns']=6;row['rows']=5;row['reusedFrom']=source;metadata[actor]=row
                with Image.open(BytesIO(archive.read('godot/assets/'+old[source]['path']))) as image:
                    first=image.crop((0,0,row['frameWidth'],row['frameHeight'])).resize((96,96),Image.Resampling.NEAREST)
                    (ASSETS/'ui/units').mkdir(exist_ok=True);first.save(ASSETS/f'ui/units/{actor}.png')
            for suffix in ['', '-worn','-critical','-ruin']:
                for side in ['', '-enemy']:
                    destination=ASSETS/f'base/A{era}{suffix}{side}.png';destination.write_bytes(archive.read(f'godot/assets/base/A{old_era}{suffix}{side}.png'))
            set_base_orientation('A'+str(era),True)
    write(ASSETS/'data/animations.json',metadata)
    print('Reused 20 approved era unit animation sheets; original identities preserved.',flush=True)

def generate(job,force=False):
    path=OUT/'raw'/f'{job["name"]}.png';prompt=ROOT/job['prompt'];meta=path.with_suffix('.metadata.json')
    if path.exists() and not force:
        with Image.open(path) as image:dimensions=list(image.size);image.verify()
        record={'name':job['name'],'model':'gpt-image-2.5','status':'generated','size':dimensions,'sha256':sha(path),'promptSha256':sha(prompt),'route':'designated Sub2 CLI with image tool declaration'}
        write(meta,record);return record
    if force and path.exists():
        folder=OUT/'rejected'/sha(path)[:12];folder.mkdir(parents=True,exist_ok=True);shutil.copy2(path,folder/path.name)
    command=[sys.executable,'-X','utf8',str(CLI),'edit' if job.get('reference') else 'generate']
    if job.get('reference'):command+=['--image',str(ROOT/job['reference'])]
    command+=['--prompt-file',str(prompt),'--model','gpt-image-2.5','--size',job['size'],'--quality','high','--background','opaque','--out',str(path)]
    if force:command.append('--force')
    print('Sub2 '+job['name'],flush=True)
    for attempt in range(3):
        completed=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace')
        if completed.returncode==0:
            with Image.open(path) as image:dimensions=list(image.size);image.verify()
            record={'name':job['name'],'model':'gpt-image-2.5','status':'generated','size':dimensions,'sha256':sha(path),'promptSha256':sha(prompt),'route':'designated Sub2 CLI with image tool declaration','generatedAt':datetime.now(timezone.utc).isoformat()}
            if job.get('reference'):record['referenceSha256']=sha(ROOT/job['reference'])
            write(meta,record);return record
        message=(completed.stderr or completed.stdout).strip()
        if any(code in message for code in ['429','500','502','503','504','timed out']) and attempt<2:time.sleep(3*(attempt+1));continue
        raise RuntimeError(job['name']+': '+message[:600])
    raise RuntimeError('Generation exhausted retries')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only');parser.add_argument('--force',action='store_true');parser.add_argument('--normalize-only',action='store_true');parser.add_argument('--reuse-only',action='store_true');args=parser.parse_args()
    if args.reuse_only:reuse_originals();return
    document=read(OUT/'jobs.json');all_jobs=document['jobs'];selected=set(args.only.split(',')) if args.only else None
    jobs=[job for job in all_jobs if selected is None or job['name'] in selected]
    report_path=OUT/'production-state.json';records=read(report_path).get('records',{}) if report_path.exists() else {}
    if args.normalize_only:
        for job in jobs:
            if (OUT/'raw'/f'{job["name"]}.png').exists():records[job['name']]={'status':'processed',**process(job)}
        write(report_path,{'records':records});return
    pending=list(jobs);running={};failed=set();done=set()
    for job in all_jobs:
        if job not in jobs and (OUT/'raw'/f'{job["name"]}.png').exists():done.add(job['name'])
    def persist():write(report_path,{'model':'gpt-image-2.5','total':len(all_jobs),'processed':sum(r.get('status')=='processed' for r in records.values()),'records':records,'running':[job['name'] for job in running.values()]})
    with ThreadPoolExecutor(max_workers=2) as pool:
        while pending or running:
            while len(running)<2:
                ready=next((job for job in pending if all(dep in done for dep in job.get('dependencies',[]))),None)
                if ready is None:break
                pending.remove(ready);running[pool.submit(generate,ready,args.force)]=ready;records[ready['name']]={'status':'running'};persist()
            if not running:
                for job in pending:records[job['name']]={'status':'blocked_dependency'}
                break
            finished,_=wait(running,timeout=30,return_when=FIRST_COMPLETED)
            for future in finished:
                job=running.pop(future)
                try:
                    generation=future.result();processed=process(job);records[job['name']]={'status':'processed','generation':generation,**processed};done.add(job['name']);print('Ready '+job['name'],flush=True)
                except Exception as error:
                    records[job['name']]={'status':'failed','error':str(error)[:700]};failed.add(job['name']);print('Failed '+job['name']+': '+str(error)[:350],flush=True)
                persist()
            if not finished:persist()
    persist();print(json.dumps({'processed':len(done),'failed':len(failed),'blocked':len(pending)},ensure_ascii=False),flush=True)
    if failed or pending:raise SystemExit(1)

if __name__=='__main__':main()
