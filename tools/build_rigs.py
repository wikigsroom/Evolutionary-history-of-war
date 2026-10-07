"""Split approved master sprites into compact, deterministic cutout rigs."""
from pathlib import Path
import hashlib,json,re
from PIL import Image,ImageDraw,ImageChops
from rig_anatomy import REGIONS
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'public/assets'
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
plan=json.loads((ROOT/'docs/epoch-rush/data/asset-manifest.json').read_text(encoding='utf-8'))['entries']
chariot=manifest['entries']['unit.U24'];chariot_path=OUT/chariot['path'];corrected=Image.open(chariot_path).convert('RGBA');pixels=corrected.load()
for y in range(round(corrected.height*.43),round(corrected.height*.72)):
    for x in range(round(corrected.width*.03),round(corrected.width*.31)):
        r,g,b,a=pixels[x,y]
        if a and r>g*1.7 and r>b*1.7 and r>75:pixels[x,y]=(round(b*.8),round(r*.66),r,a)
corrected.save(chariot_path,optimize=True);chariot.update(sha256=hashlib.sha256(chariot_path.read_bytes()).hexdigest(),method='normalized_master_with_allied_banner_correction')
alternate=corrected.copy();pixels=alternate.load()
for y in range(alternate.height):
    for x in range(alternate.width):
        r,g,b,a=pixels[x,y]
        if a>0 and b>r*1.18 and b>g*.9 and max(r,g,b)-min(r,g,b)>40:pixels[x,y]=(min(255,round(b*1.10)),round(g*.65),round(r*.98),a)
enemy_entry=manifest['entries']['unit.U24.enemy'];enemy_path=OUT/enemy_entry['path'];alternate.save(enemy_path,optimize=True);enemy_entry['sha256']=hashlib.sha256(enemy_path.read_bytes()).hexdigest()
manifest['entries']={k:v for k,v in manifest['entries'].items() if v['kind']!='rig_part'}
for entry in plan:
    if entry['kind']!='rig':continue
    identifier=entry['ownerId'];domain='hero' if identifier.startswith('H') else 'unit';source_key=domain+'.'+identifier
    source=manifest['entries'][source_key];image=Image.open(OUT/source['path']).convert('RGBA');width,height=image.size
    bounds=image.getchannel('A').point(lambda v:255 if v>24 else 0).getbbox();left,top,right,bottom=bounds;span=bottom-top
    vehicle=identifier=='U44';mounted=identifier in ['U24','U34'];parts=[]
    motion='vehicle' if vehicle else 'chariot' if identifier=='U24' else 'mounted' if identifier=='U34' else 'mech' if identifier=='U54' else 'biped'
    masks=[]
    def region(role,shape,pivot,polygon=False):
        mask=Image.new('L',image.size);draw=ImageDraw.Draw(mask)
        if polygon:draw.polygon([(x*width,y*height) for x,y in shape],fill=255)
        else:draw.rectangle((shape[0]*width,shape[1]*height,shape[2]*width,shape[3]*height),fill=255)
        masks.append((role,mask,(pivot[0]*width,pivot[1]*height)))
    head,neck,weapon,shoulder,cloth,attachment,hips,foot_span=REGIONS[identifier]
    if head:region('head',head,neck)
    region('weapon',weapon,shoulder,True)
    if vehicle:region('track',(foot_span[0],hips,foot_span[1],.91),(.49,.84))
    else:
        for n in range(4 if mounted else 2):
            count=4 if mounted else 2;x0=foot_span[0]+(foot_span[1]-foot_span[0])*n/count;x1=foot_span[0]+(foot_span[1]-foot_span[0])*(n+1)/count
            region('leg'+str(n),(x0,hips,x1,.91),((x0+x1)/2,hips+.012))
        if identifier=='U24':region('wheel',(.12,.72,.36,.91),(.241,.812))
    region('cloth',cloth,attachment)
    remaining=Image.new('L',image.size,255)
    separated=[];joints=Image.new('L',image.size)
    for role,mask,pivot in masks:
        mask=ImageChops.multiply(mask,remaining);remaining=ImageChops.subtract(remaining,mask)
        separated.append((role,mask,pivot))
        if role!='wheel':ImageDraw.Draw(joints).ellipse((pivot[0]-10,pivot[1]-10,pivot[0]+10,pivot[1]+10),fill=255)
    separated.insert(0,('body',ImageChops.lighter(remaining,joints),(width*.5,height*.9)))
    rig_path=OUT/entry['targetPath'];rig_path.parent.mkdir(parents=True,exist_ok=True)
    for role,mask,pivot in separated:
        normal=image.copy();normal.putalpha(ImageChops.multiply(image.getchannel('A'),mask));bbox=normal.getchannel('A').getbbox()
        if not bbox:continue
        cropped=normal.crop(bbox);part_key=entry['key']+'.'+role;path=rig_path.parent/(identifier+'-'+role+'.png');cropped.save(path,optimize=True)
        enemy=Image.open(OUT/manifest['entries'][source_key+'.enemy']['path']).convert('RGBA');enemy.putalpha(ImageChops.multiply(enemy.getchannel('A'),mask));enemy_path=path.with_name(path.stem+'-enemy.png');enemy.crop(bbox).save(enemy_path,optimize=True)
        for key,location in [(part_key,path),(part_key+'.enemy',enemy_path)]:
            manifest['entries'][key]={'key':key,'path':location.relative_to(OUT).as_posix(),'kind':'rig_part','size':list(cropped.size),'status':'rig_pending_animation_review','derivedFrom':source_key,'method':'per_actor_anatomy_cutout','sha256':hashlib.sha256(location.read_bytes()).hexdigest()}
        parts.append({'key':part_key,'role':role,'bounds':list(bbox),'pivot':list(pivot)})
    rig={'schemaVersion':2,'sourceKey':source_key,'size':list(image.size),'visibleBounds':list(bounds),'bodyTop':head[1]*height if head else top,'anchor':[.5,.9],'motionClass':motion,'parts':parts,
         'clips':{'idle':{'periodSec':2.4},'move':{'stride':46 if not mounted else 65},'windup':{'weaponAngle':-12},'release':{'weaponAngle':8,'recoil':7},'hit':{'flashMs':75},'dead':{'durationSec':.8},'skill':{'leanAngle':7},'respawn':{'fadeSec':.35}}}
    rig_path.write_text(json.dumps(rig,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    manifest['entries'][entry['key']]={'key':entry['key'],'kind':'rig','path':entry['targetPath'],'size':list(image.size),'status':'rig_pending_animation_review','method':'per_actor_anatomy_cutout_covered_joints','derivedFrom':source_key,'sha256':hashlib.sha256(rig_path.read_bytes()).hexdigest()}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
referenced={str((OUT/e['path']).resolve()) for e in manifest['entries'].values()}
character_root=(OUT/'characters').resolve()
for path in character_root.rglob('*.png'):
    # Only remove obsolete, generated rig parts inside the verified character directory.
    if path.resolve().is_relative_to(character_root) and re.fullmatch(r'[HU]\d{2}-(?:body|head|weapon|cloth|leg[0-3]|track|wheel)(?:-enemy)?',path.stem) and str(path.resolve()) not in referenced:path.unlink()
print(json.dumps({'rigs':sum(e['kind']=='rig' for e in manifest['entries'].values()),'parts':sum(e['kind']=='rig_part' for e in manifest['entries'].values())}))
