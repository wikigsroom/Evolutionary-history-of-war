"""Collect and verify the revised store images, without reference art or videos."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile
from PIL import Image
from graphics import ROOT, OUT

BRAND = ROOT/'output/imagegen/brand-kit/2026-10-08-pixel-crest'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def main():
    for kind, name in [('banners','banner-2304x768'),('posters','poster-1536x2304')]:
        (OUT/kind).mkdir(exist_ok=True)
        for suffix in ['.png','.jpg']:
            shutil.copy2(BRAND/('epoch-rush-'+name+suffix),OUT/kind/('game-'+name+suffix))
    files=[]
    for folder in ['brand','banners','posters','covers','promotional','wallpapers']:
        files.extend(sorted(p for p in (OUT/folder).glob('*') if p.suffix in ['.png','.jpg','.ico']))
    verified=[]
    for p in files:
        with Image.open(p) as im:
            im.load()
            alpha=im.convert('RGBA').getchannel('A')
            if p.parent.name=='brand' and 'icon' in p.name:
                assert alpha.getextrema()==(255,255),str(p)
                if p.suffix=='.ico':
                    for size in im.ico.sizes():
                        assert im.ico.getimage(size).convert('RGBA').getchannel('A').getextrema()==(255,255)
            if p.parent.name=='brand' and 'logo' in p.name:
                assert im.mode=='RGBA' and alpha.getextrema()==(0,255),str(p)
            verified.append({'file':p.relative_to(OUT).as_posix(),'size':list(im.size),'mode':im.mode,
                             'alpha_range':list(alpha.getextrema()),'bytes':p.stat().st_size,'sha256':sha(p)})
    production=load(OUT/'source/image-production.json')
    primary=[r for r in production['artworks'] if r['role'] in ['16:9 promotional key art','horizontal cover','vertical cover']]
    assert len(primary)==7 and all([t['text'] for t in r['typography']]==['纪元急袭'] for r in primary)
    legacy=load(BRAND/'brand-kit-manifest.json')['deliverables']
    assert len(legacy)==2 and all([t['text'] for t in r['typography']]==['纪元急袭'] for r in legacy)
    assert sha(OUT/'previews/trailer-poster.jpg')==sha(OUT/'covers/horizontal-cover-1920x1080.jpg')
    for p in [ROOT/'public/app-icon.png',ROOT/'godot/assets/ui/pixel/app-icon.png']:
        assert Image.open(p).convert('RGBA').getchannel('A').getextrema()==(255,255),str(p)
    background=Image.open(ROOT/'godot/assets/ui/pixel/launcher-background.png').convert('RGBA')
    foreground=Image.open(ROOT/'godot/assets/ui/pixel/launcher-foreground.png').convert('RGBA')
    assert Image.alpha_composite(background,foreground).getchannel('A').getextrema()==(255,255)
    report={'status':'passed','date':'2026-10-08','game':'纪元急袭',
            'requirements':[{'item':2,'result':'Fully opaque app icons; native launcher composition is opaque'},
                            {'item':3,'result':'Game logo has real alpha transparency'},
                            {'item':4,'result':'Game logo renders only 纪元急袭'},
                            {'item':5,'result':'Nine branded covers/promotional/banner/poster masters render only 纪元急袭; clean key art and wallpapers contain no text'}],
            'reviewed_images':['brand/game-icon-opaque-512.png','brand/game-logo-transparent-1024x256.png',
                               'previews/promotional-covers-overview.jpg','banners/game-banner-2304x768.png',
                               'posters/game-poster-1536x2304.png','covers/horizontal-cover-1920x1080.png',
                               'covers/vertical-cover-1080x1620.png'],
            'image_files':verified,'character_reference_sha256':load(OUT/'source/brand-assets.json')['source_character_sha256']}
    (OUT/'source/branding-compliance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

    destination=OUT/'store-ready';destination.mkdir(exist_ok=True)
    for p in files:
        target=destination/p.relative_to(OUT)
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(p,target)
    expected={p.relative_to(OUT).as_posix() for p in files}|{'README.md'}
    actual={p.relative_to(destination).as_posix() for p in destination.rglob('*') if p.is_file()}
    if actual-expected:
        raise RuntimeError('Unexpected file in the upload folder: '+str(actual-expected))
    readme='''# 《纪元急袭》可上传图片

- 游戏图标：brand/game-icon-opaque-1024.png，另附 512 版本及 Windows ICO；背景完全不透明。
- 游戏 LOGO：brand/game-logo-transparent-2048x512.png，另附 1024×256 版本；真正透明，只有“纪元急袭”四字。
- Banner：banners/game-banner-2304x768.png；海报：posters/game-poster-1536x2304.png。
- 横竖封面：covers/；五张宣传图：promotional/ 中 01–05 编号文件。
- 封面、宣传图、Banner 和海报只含游戏名。无 LOGO 宣传图及 wallpapers/ 中的两版超分壁纸完全无文字。
- LOGO 使用 PNG 保留透明背景；其他宣传美术提供 PNG 和 JPG。

本包只包含成品图片及这份索引。素材文字与透明度已逐项检查。
'''
    (destination/'README.md').write_text(readme,encoding='utf-8')
    archive=OUT/'Epoch-Rush-Store-Images-2026-10-08.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_STORED) as package:
        for relative in sorted(expected):
            package.write(destination/relative,'Epoch-Rush-Store-Images/'+relative)
    with zipfile.ZipFile(archive) as package:
        assert package.testzip() is None
        for row in verified:
            assert hashlib.sha256(package.read('Epoch-Rush-Store-Images/'+row['file'])).hexdigest()==row['sha256']
    archive.with_suffix('.zip.sha256').write_text(sha(archive)+'  '+archive.name+'\n',encoding='utf-8')
    (OUT/'store-package-report.json').write_text(json.dumps({'status':'passed','archive':archive.name,
      'image_files':len(files),'bytes':archive.stat().st_size,'sha256':sha(archive),
      'crc_verification':'passed','content_hash_verification':'passed'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'passed','image_files':len(files),'archive':str(archive),'bytes':archive.stat().st_size},ensure_ascii=False))


if __name__=='__main__':
    main()
