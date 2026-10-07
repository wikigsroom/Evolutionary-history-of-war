"""Build compact portraits and anchored building damage states from the original art."""
from pathlib import Path
import hashlib,json,math
import numpy as np
from PIL import Image,ImageDraw,ImageOps,ImageFilter
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'public/assets'
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
faces={'H01':(.56,.24,.76,.44),'H02':(.40,.07,.67,.27),'H03':(.54,.04,.72,.29),'H04':(.40,.08,.65,.28),'H05':(.39,.04,.67,.24),'H06':(.40,.12,.65,.31)}
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
for identifier,face in faces.items():
    entry=manifest['entries']['portrait.'+identifier]
    raw=ROOT/entry['source'];image=Image.open(raw).convert('RGBA')
    crop=image.crop(tuple(round(face[i]*([image.width,image.height]*2)[i]) for i in range(4)))
    bounds=crop.getchannel('A').point(lambda v:255 if v>20 else 0).getbbox()
    if bounds:crop=crop.crop(bounds)
    crop.thumbnail((224,224),Image.Resampling.LANCZOS)
    result=Image.new('RGBA',(256,256));result.alpha_composite(crop,((256-crop.width)//2,(256-crop.height)//2))
    target=OUT/entry['path'];result.save(target,optimize=True)
    entry.update(size=[256,256],sha256=digest(target),method='reviewed_head_crop_tight_alpha',status='processed_pending_ingame_review')
for era in range(1,6):
    for enemy in [False,True]:
        base_key=f'base.A{era}'+('.enemy' if enemy else '')
        source=manifest['entries'][base_key];image=Image.open(OUT/source['path']).convert('RGBA');w,h=image.size
        alpha=image.getchannel('A');bbox=alpha.point(lambda v:255 if v>20 else 0).getbbox();left,top,right,bottom=bbox
        for stage,damage in [('worn',.22),('critical',.48),('ruin',.72)]:
            pixels=np.array(image,dtype=np.float32);grey=pixels[:,:,:3].mean(axis=2,keepdims=True)
            pixels[:,:,:3]=pixels[:,:,:3]*(1-damage*.6)+grey*damage*.6
            yy,xx=np.mgrid[:h,:w];soot=np.exp(-(((xx-w*.55)/(w*.24))**2+((yy-h*.68)/(h*.21))**2))
            pixels[:,:,:3]*=1-soot[:,:,None]*damage*.68
            result=Image.fromarray(np.clip(pixels,0,255).astype('uint8'))
            cracks=Image.new('RGBA',(w,h));draw=ImageDraw.Draw(cracks)
            # Restrict all cracks and scorch to the source silhouette; keep the original feet anchor.
            for i in range(2 if stage=='worn' else 5):
                x=left+(right-left)*(.24+i*.135);y=top+(bottom-top)*(.45+(i%2)*.13)
                points=[(x,y),(x+9,y+21),(x-4,y+35),(x+7,y+62),(x-9,y+81)]
                draw.line(points,fill=(30,29,29,240),width=4 if stage=='worn' else 6)
                draw.line([(a+2,b) for a,b in points],fill=(193,153,93,105),width=2)
                if i%2==0:draw.line([points[2],(x-24,y+41)],fill=(30,29,29,215),width=3)
            cracks.putalpha(Image.fromarray(np.minimum(np.array(cracks.getchannel('A')),np.array(alpha))))
            result=Image.alpha_composite(result,cracks)
            if stage=='ruin':
                mask=Image.new('L',(w,h));draw=ImageDraw.Draw(mask)
                edge=[]
                for x in range(0,w+1,16):edge.append((x,top+(bottom-top)*(.56+.075*math.sin(x*.12+era)+.045*math.sin(x*.29))))
                draw.polygon([*edge,(w,h),(0,h)],fill=255)
                result.putalpha(Image.fromarray(np.minimum(np.array(result.getchannel('A')),np.array(mask))))
            key=f'base.A{era}.{stage}'+('.enemy' if enemy else '')
            target=OUT/'base'/f'A{era}-{stage}{"-enemy" if enemy else ""}.png';target.parent.mkdir(parents=True,exist_ok=True);result.save(target,optimize=True)
            manifest['entries'][key]={**source,'key':key,'path':target.relative_to(OUT).as_posix(),'sha256':digest(target),'derivedFrom':base_key,'method':'local_silhouette_damage_state','status':'damage_state_pending_ingame_review'}
home=ROOT/'output/imagegen/epoch-rush/redesign/home-world.png'
if home.exists():
    target=OUT/'ui/home-world.webp';Image.open(home).convert('RGB').save(target,quality=92,method=6)
    manifest['entries']['ui.home-world']={'key':'ui.home-world','kind':'ui','path':target.relative_to(OUT).as_posix(),'size':[1536,1024],'status':'reviewed_home_art','model':'gpt-image-2.5','source':home.relative_to(ROOT).as_posix(),'sourceSha256':digest(home),'sha256':digest(target),'method':'sub2_image_gen_cli_webp_derivative'}
    record={'requestedModel':'gpt-image-2.5','quality':'high','size':'1536x1024','route':'sub2-image-gen CLI','promptFile':'home-prompt.txt','sourceSha256':digest(home),'review':'Inspected panorama: no interface/text, clear left title area, coherent five-era landscape.'}
    (home.parent/'home-world.metadata.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'portraits':6,'buildingStates':30,'home':home.exists()},ensure_ascii=False))
