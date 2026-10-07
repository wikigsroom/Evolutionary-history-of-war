"""Normalize generated PNGs; retain provenance and a truthful production manifest."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageOps

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'output/imagegen/epoch-rush'
TARGET=ROOT/'public/assets'
TARGET.mkdir(parents=True,exist_ok=True)
planned=json.loads((ROOT/'docs/epoch-rush/data/asset-manifest.json').read_text(encoding='utf-8'))['entries']
manifest_path=TARGET/'manifest.json'
manifest=json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {'version':'0.1.0','entries':{}}
review_path=SOURCE/'art-review.json'
reviews=json.loads(review_path.read_text(encoding='utf-8')) if review_path.exists() else {}
previews=[]
failures=[]

def source_name(entry):
    domain,*tail=entry['key'].split('.')
    return entry['ownerId'] if domain in ['unit','hero','portrait','turret'] else '-'.join([domain,*tail])

for entry in planned:
    if entry['kind'] in ['audio','rig','reference']: continue
    name=source_name(entry)
    raw=SOURCE/'raw'/(name+'.png')
    if entry['method']=='crop_from_unit': raw=SOURCE/'raw'/(entry['ownerId']+'.png')
    if not raw.exists(): continue
    try:
        with Image.open(raw) as opened: image=opened.convert('RGBA')
        size=tuple(entry['size'])
        if entry['kind']=='background':
            if entry['key'].endswith('.ground'):
                image=image.crop((0,round(image.height*.75),image.width,image.height))
            elif entry['key'].endswith('.mid'):
                alpha=image.getchannel('A')
                for y in range(image.height):
                    progress=y/max(1,image.height-1)
                    opacity=max(0,min(1,(progress-.22)/.22,(.96-progress)/.19))
                    alpha.paste(alpha.crop((0,y,image.width,y+1)).point(lambda v:round(v*opacity)),(0,y))
                image.putalpha(alpha)
            image=ImageOps.fit(image,size,method=Image.Resampling.LANCZOS)
            anchor=[.5,.5]
        else:
            if image.getchannel('A').getextrema()[0]==255:
                corners=[image.getpixel(point) for point in [(0,0),(image.width-1,0),(0,image.height-1),(image.width-1,image.height-1)]]
                if any(max(abs(corners[0][i]-color[i]) for i in range(3))>15 for color in corners):
                    raise ValueError('Opaque non-flat background requires regeneration or manual extraction')
                for point in [(0,0),(image.width-1,0),(0,image.height-1),(image.width-1,image.height-1)]:
                    ImageDraw.floodfill(image,point,(0,0,0,0),thresh=30)
            alpha=image.getchannel('A')
            bounds=alpha.point(lambda value: 255 if value>12 else 0).getbbox()
            if not bounds: raise ValueError('Empty alpha mask')
            crop=image.crop(bounds)
            if entry['kind']=='portrait':
                # Approved head crops for the first two commanders. Further heroes need per-image review.
                face={'H01':(.56,.24,.76,.44),'H02':(.40,.07,.67,.27),'H03':(.54,.04,.72,.29),'H04':(.40,.08,.65,.28),'H05':(.39,.04,.67,.24),'H06':(.40,.12,.65,.31)}.get(entry['ownerId'])
                if face is None: continue
                crop=image.crop(tuple(round(face[i]*([image.width,image.height]*2)[i]) for i in range(4)))
            output=Image.new('RGBA',size,(0,0,0,0))
            if entry['kind']=='sprite':
                band=crop.getchannel('A').crop((0,round(crop.height*.94),crop.width,crop.height))
                feet=band.getbbox()
                foot_x=(feet[0]+feet[2])/2 if feet else crop.width/2
                margin=min(size)*.035
                scale=min((size[0]/2-margin)/max(foot_x,1),(size[0]/2-margin)/max(crop.width-foot_x,1),(size[1]*.87-margin)/crop.height)
                resized=crop.resize((max(1,round(crop.width*scale)),max(1,round(crop.height*scale))),Image.Resampling.LANCZOS)
                x=round(size[0]*.5-foot_x*scale); y=round(size[1]*.9-resized.height)
                output.alpha_composite(resized,(x,y)); anchor=[.5,.9]
            else:
                crop.thumbnail((round(size[0]*.88),round(size[1]*.88)),Image.Resampling.LANCZOS)
                output.alpha_composite(crop,((size[0]-crop.width)//2,(size[1]-crop.height)//2)); anchor=[.5,.5]
            image=output
            if image.getchannel('A').getextrema()[0]!=0: raise ValueError('Output transparency validation failed')
            if entry['key']=='unit.U24':
                pixels=image.load()
                for y in range(round(image.height*.45)):
                    for x in range(round(image.width*.55)):
                        r,g,b,a=pixels[x,y]
                        if a and r>g*1.7 and r>b*1.7 and r>75:pixels[x,y]=(round(b*.8),round(r*.66),r,a)
        path=TARGET/entry['targetPath']; path.parent.mkdir(parents=True,exist_ok=True); image.save(path,optimize=True)
        source_hash=hashlib.sha256(raw.read_bytes()).hexdigest()
        review=reviews.get(entry['key'],{})
        status=review.get('status','processed_pending_ingame_review') if review.get('sourceSha256')==source_hash else 'processed_pending_ingame_review'
        manifest['entries'][entry['key']]={'key':entry['key'],'path':entry['targetPath'],'kind':entry['kind'],'size':list(image.size),'anchor':anchor,'status':status,'model':'gpt-image-2.5','source':str(raw.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'sourceSha256':source_hash}
        if entry['kind']=='sprite':
            enemy=image.copy(); pixels=enemy.load()
            for y in range(enemy.height):
                for x in range(enemy.width):
                    r,g,b,a=pixels[x,y]
                    if a>0 and b>r*1.18 and b>g*.9 and max(r,g,b)-min(r,g,b)>40:
                        pixels[x,y]=(min(255,round(b*1.10)),round(g*.65),round(r*.98),a)
            enemy_path=path.with_name(path.stem+'-enemy.png'); enemy.save(enemy_path,optimize=True)
            enemy_key=entry['key']+'.enemy'
            manifest['entries'][enemy_key]={**manifest['entries'][entry['key']],'key':enemy_key,'path':str(enemy_path.relative_to(TARGET)).replace('\\','/'),'derivedFrom':entry['key'],'sha256':hashlib.sha256(enemy_path.read_bytes()).hexdigest()}
        previews.append((entry['key'],image.copy()))
    except Exception as error:
        failures.append({'key':entry['key'],'error':str(error)})

reference=ROOT/'docs/epoch-rush/assets/reference/epoch-rush-concept.png'
reference_out=TARGET/'reference/epoch-rush-concept.png'
reference_out.parent.mkdir(exist_ok=True)
reference_out.write_bytes(reference.read_bytes())
manifest['entries']['reference.epoch_rush']={'key':'reference.epoch_rush','path':'reference/epoch-rush-concept.png','kind':'reference','status':'reference_ready','size':[1536,1024]}
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if previews:
    width=1000; cell_w=200; cell_h=180
    board=Image.new('RGB',(width,((len(previews)+4)//5)*cell_h),'#ede0c4'); draw=ImageDraw.Draw(board)
    for index,(key,source_image) in enumerate(previews):
        source_image.thumbnail((180,145),Image.Resampling.LANCZOS)
        x=(index%5)*cell_w; y=(index//5)*cell_h
        board.paste(source_image,(x+(cell_w-source_image.width)//2,y+4),source_image)
        draw.text((x+10,y+155),key,fill='#3b3028')
    board.save(SOURCE/'processed-contact-sheet.png')
report={'processed':len(previews),'manifestEntries':len(manifest['entries']),'failures':failures}
(SOURCE/'processing-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
