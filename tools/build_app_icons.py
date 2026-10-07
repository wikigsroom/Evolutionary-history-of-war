from pathlib import Path
import json
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
icon=Image.new('RGBA',(1024,1024),'#ede0c4');draw=ImageDraw.Draw(icon)
draw.rounded_rectangle((70,70,954,954),radius=200,fill='#3b3028')
draw.rounded_rectangle((95,95,929,929),radius=180,fill='#397ea5')
manifest=json.loads((ROOT/'public/assets/manifest.json').read_text(encoding='utf-8'))
face=Image.open(ROOT/'public/assets'/manifest['entries']['portrait.H01']['path']).convert('RGBA')
if not face.getchannel('A').getbbox():raise ValueError('Empty commander portrait')
face=face.crop(face.getchannel('A').getbbox());face.thumbnail((670,700),Image.Resampling.LANCZOS)
icon.alpha_composite(face,((1024-face.width)//2,200+(700-face.height)//2))
icon.convert('RGB').save(ROOT/'public/app-icon.png')
icon.save(ROOT/'public/app-icon.ico',sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    target=ROOT/'android/app/src/main/res'/('mipmap-'+density)
    target.mkdir(exist_ok=True)
    for name in ['ic_launcher.png','ic_launcher_round.png']:icon.resize((size,size),Image.Resampling.LANCZOS).save(target/name)
    foreground_size=round(size*108/48)
    foreground=Image.new('RGBA',(foreground_size,foreground_size),(0,0,0,0))
    badge=icon.resize((size,size),Image.Resampling.LANCZOS)
    foreground.alpha_composite(badge,((foreground_size-size)//2,(foreground_size-size)//2))
    foreground.save(target/'ic_launcher_foreground.png')
ios=ROOT/'ios/App/App/Assets.xcassets/AppIcon.appiconset';ios.mkdir(parents=True,exist_ok=True)
icon.convert('RGB').save(ios/'AppIcon-1024.png')
(ios/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon-1024.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2)+'\n',encoding='utf-8')
print('Windows, Android and iOS icons derived from the generated H01 master.')
