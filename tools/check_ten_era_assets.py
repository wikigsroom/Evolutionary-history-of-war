"""Audit real runtime assets and build complete animation contact sheets for review."""
import argparse, hashlib, json
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'godot/assets'; OUT=ROOT/'output/qa/ten-eras/assets'
def load(name):return json.loads((ASSETS/'data'/f'{name}.json').read_text(encoding='utf-8'))
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--partial',action='store_true');parser.add_argument('--require-review',action='store_true');args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True);meta=load('animations');failures=[];actors=[];maps=[];review_boards=[]
    ids=[r['id'] for r in load('units')]+[r['id'] for r in load('hero-evolutions')]+[f'SUM-A{i}' for i in range(1,11)]
    for actor in ids:
        if actor not in meta:
            failures.append(actor+': missing animation metadata');continue
        row=meta[actor];record={'id':actor,'palettes':[],'review':row.get('review',row.get('status','legacy'))}
        if args.require_review and row.get('review')!='accepted_visual_review':failures.append(actor+': visual review not accepted')
        if args.require_review and row.get('reviewedAtlasSha256')!=row.get('atlasSha256'):failures.append(actor+': reviewed atlas changed')
        for key in ['path','enemyPath']:
            path=ASSETS/row[key]
            if not path.exists():failures.append(actor+': missing '+key);continue
            image=Image.open(path).convert('RGBA');w,h=row['frameWidth'],row['frameHeight'];columns,rows=row.get('columns',6),row.get('rows',5)
            if image.size!=(w*columns,h*rows):failures.append(actor+': inconsistent atlas dimensions')
            hashes=[];bounds=[]
            for index in range(columns*rows):
                tile=image.crop((index%columns*w,index//columns*h,(index%columns+1)*w,(index//columns+1)*h));box=tile.getchannel('A').getbbox()
                if not box:failures.append(actor+': empty frame '+str(index))
                elif not actor.startswith('SUM-') and (min(box[:2])==0 or box[2]>=w or box[3]>=h):failures.append(actor+': clipped frame '+str(index))
                hashes.append(hashlib.sha256(tile.tobytes()).hexdigest());bounds.append(box)
            variation={clip:len({hashes[int(i)] for i in frames}) for clip,frames in row['clips'].items()}
            if not actor.startswith('SUM-'):
                for clip,unique in variation.items():
                    if unique<3:failures.append(actor+': insufficient motion '+clip+' '+str(unique))
            array=np.asarray(image);matte=(array[:,:,0]>220)&(array[:,:,2]>220)&(array[:,:,1]<45)&(array[:,:,3]>24)
            if matte.sum()>16:failures.append(actor+': visible magenta matte')
            palette='own' if key=='path' else 'enemy'
            if not row.get('atlasSha256',{}).get(palette):failures.append(actor+': missing atlas hash '+palette)
            elif digest(path)!=row['atlasSha256'][palette]:failures.append(actor+': hash mismatch '+palette)
            record['palettes'].append({'key':key,'size':list(image.size),'frames':columns*rows,'clipVariation':variation,'sha256':digest(path),'bounds':bounds})
        actors.append(record)
    for era in load('eras'):
        for path in era['backgrounds']:
            file=ASSETS/path
            if not file.exists():failures.append(path+': missing map');continue
            with Image.open(file) as image:dimensions=list(image.size)
            if dimensions[0]/dimensions[1]<3:failures.append(path+': insufficient panorama width')
            maps.append({'era':era['id'],'path':path,'size':dimensions,'sha256':digest(file)})
        hashes=[r['sha256'] for r in maps if r['era']==era['id']]
        if len(hashes)==3 and len(set(hashes))!=3:failures.append(era['id']+': duplicate candidate maps')
    inventory=[]
    jobs=json.loads((ROOT/'output/imagegen/ten-eras/jobs.json').read_text(encoding='utf-8'))['jobs']
    ambient_names=next(j['names'] for j in jobs if j['kind']=='ambient')
    event_names=next(j['names'] for j in jobs if j['kind']=='events')
    paths=[]
    paths.extend(f'base/A{age}{state}{palette}.png' for age in range(1,11) for state in ['', '-worn','-critical','-ruin'] for palette in ['', '-enemy'])
    paths.extend(f'fx/eras/A{age}-{kind}.png' for age in range(1,11) for kind in ['carrier','projectile','impact','shock','sparks','smoke'])
    paths.extend(f'environment/turrets/TR{age}{slot}{palette}.png' for age in range(1,11) for slot in [1,2] for palette in ['', '-enemy'])
    paths.extend('environment/ambient/'+name+'.png' for name in ambient_names)
    paths.extend('fx/events/'+name+'.png' for name in event_names)
    paths.extend('ui/units/'+row['id']+'.png' for row in load('units'))
    paths.extend('ui/heroes/'+row['id']+'.png' for row in load('hero-evolutions'))
    for relative in paths:
        path=ASSETS/relative
        if not path.exists():failures.append(relative+': missing runtime texture');continue
        with Image.open(path) as im:
            image=im.convert('RGBA');array=np.asarray(image)
            if not image.getchannel('A').getbbox():failures.append(relative+': empty runtime texture')
            matte=(array[:,:,0]>220)&(array[:,:,2]>220)&(array[:,:,1]<45)&(array[:,:,3]>24)
            if matte.sum()>16:failures.append(relative+': visible matte')
            dimensions=list(im.size)
        inventory.append({'path':relative,'size':dimensions,'sha256':digest(path)})
    for era in range(1,11):
        for group,names in [('heroes',[f'H0{i}-A{era}' for i in range(1,7)]),('units',[f'U{era}{i}' for i in range(1,6)])]:
            if any(name not in meta or not (ASSETS/meta[name]['path']).exists() for name in names):continue
            board=Image.new('RGB',(1160,1572),(238,231,207));draw=ImageDraw.Draw(board)
            for index,name in enumerate(names):
                atlas=Image.open(ASSETS/meta[name]['path']).convert('RGBA');atlas.thumbnail((568,480),Image.Resampling.NEAREST)
                left=(index%2)*580+6;top=(index//2)*524+26
                draw.text((left,top-20),name+'  idle / walk / attack / hurt / death',fill=(40,44,55))
                board.paste(atlas,(left,top),atlas)
            destination=OUT/f'review-A{era}-{group}.png';board.save(destination)
            review_boards.append(destination.relative_to(ROOT).as_posix())
    for group,selected,columns,size in [
        ('fx',[p for p in paths if p.startswith('fx/eras/')],6,(190,230)),
        ('base',[f'base/A{i}.png' for i in range(1,11)],5,(240,320)),
        ('ambient-events',[p for p in paths if p.startswith(('environment/ambient/','fx/events/'))],6,(170,170)),
        ('turrets',[p for p in paths if p.startswith('environment/turrets/') and not p.endswith('-enemy.png')],5,(190,160))]:
        if any(not (ASSETS/p).exists() for p in selected):continue
        board=Image.new('RGB',(columns*size[0],((len(selected)+columns-1)//columns)*size[1]),(238,231,207));draw=ImageDraw.Draw(board)
        for index,relative in enumerate(selected):
            image=Image.open(ASSETS/relative).convert('RGBA');image.thumbnail((size[0]-12,size[1]-30),Image.Resampling.NEAREST)
            x=index%columns*size[0];y=index//columns*size[1]
            draw.text((x+5,y+5),Path(relative).stem,fill=(40,44,55));board.paste(image,(x+(size[0]-image.width)//2,y+26),image)
        board.save(OUT/f'review-{group}.png');review_boards.append((OUT/f'review-{group}.png').relative_to(ROOT).as_posix())
    report={'passed':not failures,'partial':args.partial,'activeActorsExpected':len(ids),'actorsPresent':len(actors),'mapsPresent':len(maps),'runtimeTexturesPresent':len(inventory),'reviewBoards':review_boards,'actors':actors,'maps':maps,'textures':inventory,'failures':failures}
    (OUT/'asset-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'passed':not failures,'actors':len(actors),'maps':len(maps),'failures':failures[:20],'reviewBoards':len(review_boards)},ensure_ascii=False))
    if failures and not args.partial:raise SystemExit(1)
if __name__=='__main__':main()
