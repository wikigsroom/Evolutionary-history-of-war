"""Create five promotional artworks, two covers, wallpaper and clean key art."""
from pathlib import Path
import argparse,json,hashlib,shutil
from PIL import Image,ImageDraw,ImageFont
from graphics import ROOT,OUT,ART,INK,GOLD,IVORY,scene,wash,label,logo,save

def library_rows():
    production=OUT/'source/upscale/wallpaper-production.json'
    if not production.exists():raise RuntimeError('Run upscale_wallpaper.py before exporting library backgrounds.')
    data=json.loads(production.read_text(encoding='utf-8'))
    source=OUT/data['master'];rows=[]
    for i,item in enumerate(data['exports']):
        path=OUT/item['file']
        if hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']:raise RuntimeError('Library wallpaper changed after neural export')
        role='no-logo, no-text ultrawide library background' if i==0 else 'no-logo, no-text full-scene library background'
        row=record(path,role,source,data['master_size'],[])
        row['neural_upscale']={'model':data['model'],'scale':data['scale'],'source_size':data['source_size'],'receipt':'source/upscale/wallpaper-production.json'}
        rows.append(row)
    return rows

def record(path,role,source,native,texts,mark=None):
    row={'file':path.relative_to(OUT).as_posix(),'role':role,'size':list(Image.open(path).size),'source_art':str(source.relative_to(ROOT)),'source_art_size':native,'typography':texts,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    if mark:row['logo']=mark
    return row

def still_previews():
    files=sorted((OUT/'screenshots').glob('*.png'))
    names=['首页营地','主将整军','石器部落','青铜城邦','古典帝国','中世纪王国','火药列阵','工业战壕','二战钢盔','现代机械化','无人战术','轨道文明']
    font=ImageFont.truetype(str(OUT/'source/fonts/body.ttf'),24)
    for start in [0,6]:
        board=Image.new('RGB',(1920,828),INK);d=ImageDraw.Draw(board)
        for local,file in enumerate(files[start:start+6]):
            i=start+local;x=(local%3)*640;y=(local//3)*414
            image=Image.open(file).convert('RGB').resize((636,358),Image.Resampling.LANCZOS)
            board.paste(image,(x+2,y+2));d.text((x+16,y+372),f'{i+1:02d}  {names[i]}',font=font,fill=IVORY)
        board.save(OUT/'previews'/f'screenshots-{start+1:02d}-{min(start+6,len(files)):02d}.jpg',quality=95,subsampling=0)
    print('Built screenshot contact sheets.')

def art_previews(rows,plan):
    gallery=Image.new('RGB',(1920,1260),INK)
    for i,row in enumerate(rows[:5]+[rows[-1]]):
        x=(i%3)*640;y=(i//3)*414
        image=Image.open(OUT/row['file']).convert('RGB').resize((636,358),Image.Resampling.LANCZOS)
        gallery.paste(image,(x+2,y+2))
    for i,row in enumerate(rows[5:8]):
        x=i*640;y=828
        image=Image.open(OUT/row['file']).convert('RGB');image.thumbnail((636,360),Image.Resampling.LANCZOS)
        gallery.paste(image,(x+(640-image.width)//2,y+2))
    gallery.save(OUT/'previews/promotional-covers-overview.jpg',quality=95,subsampling=0)

def archive_old_library():
    directory=OUT/'source/history/superseded-branded-library-wallpaper'
    for suffix in ['.png','.jpg']:
        file=OUT/'wallpapers'/('library-poster-3840x2160'+suffix)
        if file.exists():
            directory.mkdir(parents=True,exist_ok=True)
            target=directory/file.name
            if target.exists():raise RuntimeError('An archive already exists for '+file.name)
            shutil.move(str(file),str(target))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--screens-only',action='store_true');parser.add_argument('--refresh-library',action='store_true');parser.add_argument('--stills-only',action='store_true');args=parser.parse_args()
    if args.refresh_library:
        path=OUT/'source/image-production.json';data=json.loads(path.read_text(encoding='utf-8'))
        rows=[r for r in data['artworks'] if not r['file'].startswith('wallpapers/')]
        rows=rows[:7]+library_rows()+rows[7:];data['artworks']=rows
        path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        archive_old_library()
        plan=json.loads((OUT/'source/production-plan.json').read_text(encoding='utf-8'))
        art_previews(rows,plan)
        shutil.copy2(ROOT/'docs/epoch-rush/marketing-materials-plan.md',OUT/'source/marketing-materials-plan.md')
        print('Updated library artwork, manifest source and art overview.')
        return
    still_previews()
    if args.screens_only:return
    plan=json.loads((OUT/'source/production-plan.json').read_text(encoding='utf-8'))
    rows=[]
    for theme in plan['themes'][:5]:
        file=ART/(theme['id']+'.png')
        canvas,native=scene(file,(1920,1080));wash(canvas,top=.36,bottom=.38)
        texts=[label(canvas,'纪元急袭',256,83,61,display=True,tracking=20,block=3)]
        mark=logo(canvas,1510,30,354)
        path=OUT/'promotional'/(theme['id']+'-1920x1080.png');save(canvas,path)
        rows.append(record(path,'16:9 promotional key art',file,native,texts,mark))
    base=ART/'01-evolution.png'
    canvas,native=scene(base,(1920,1080));wash(canvas,top=.18,left=.56,bottom=.30)
    mark=logo(canvas,48,170,724)
    texts=[label(canvas,'纪元急袭',286,844,307,display=True,tracking=18,block=3)]
    path=OUT/'covers/horizontal-cover-1920x1080.png';save(canvas,path);rows.append(record(path,'horizontal cover',base,native,texts,mark))
    base=ROOT/'output/imagegen/brand-kit/2026-10-08-pixel-crest/poster-art.png'
    canvas,native=scene(base,(1080,1620));wash(canvas,top=.30,bottom=.4)
    texts=[label(canvas,'纪元急袭',212,540,100,center=True,display=True,tracking=12,block=2)]
    mark=logo(canvas,133,456,814)
    path=OUT/'covers/vertical-cover-1080x1620.png';save(canvas,path);rows.append(record(path,'vertical cover',base,native,texts,mark))
    rows.extend(library_rows());archive_old_library()
    base=ART/'06-no-logo.png'
    canvas,native=scene(base,(1920,1080))
    path=OUT/'promotional/no-logo-key-art-1920x1080.png';save(canvas,path);rows.append(record(path,'no-logo, no-text promotional key art',base,native,[]))
    (OUT/'source/image-production.json').write_text(json.dumps({'artworks':rows,'logo_source_sha256':plan['logo_sha256'],'glyph_coverage':'Checked against licensed source fonts before export.','native_art_sources_preserved':True},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    art_previews(rows,plan)
    shutil.copy2(OUT/'covers/horizontal-cover-1920x1080.jpg',OUT/'previews/trailer-poster.jpg')
    if args.stills_only:
        shutil.copy2(ROOT/'docs/epoch-rush/marketing-materials-plan.md',OUT/'source/marketing-materials-plan.md')
        print('Built '+str(len(rows))+' still artworks with game-name-only typography.')
        return
    # A simple title-led opening/end card is a distinct motion-graphics surface.
    base=ART/'01-evolution.png'
    for name in ['opening','ending']:
        canvas,native=scene(base,(1920,1080));wash(canvas,top=.42,left=.7,bottom=.22)
        logo(canvas,98,170,718)
        label(canvas,'纪元急袭',282,900,277,display=True,tracking=18,block=3)
        canvas.convert('RGB').save(OUT/'source/video'/f'{name}-card.png',optimize=True)
    shutil.copy2(ROOT/'docs/epoch-rush/marketing-materials-plan.md',OUT/'source/marketing-materials-plan.md')
    print('Built '+str(len(rows))+' final image artworks and two trailer cards.')

if __name__=='__main__':main()
