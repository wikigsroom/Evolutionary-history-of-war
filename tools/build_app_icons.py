from pathlib import Path
import json
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
icon=Image.open(ROOT/'public/app-icon.png').convert('RGBA')
if icon.getchannel('A').getextrema()!=(255,255):raise ValueError('Approved application icon must be fully opaque')
icon=icon.convert('RGB')
icon.save(ROOT/'public/app-icon.ico',sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    target=ROOT/'android/app/src/main/res'/('mipmap-'+density)
    target.mkdir(exist_ok=True)
    for name in ['ic_launcher.png','ic_launcher_round.png']:icon.resize((size,size),Image.Resampling.NEAREST).save(target/name)
    foreground_size=round(size*108/48)
    foreground=Image.new('RGBA',(foreground_size,foreground_size),(0,0,0,0))
    badge=icon.resize((size,size),Image.Resampling.NEAREST).convert('RGBA')
    foreground.alpha_composite(badge,((foreground_size-size)//2,(foreground_size-size)//2))
    foreground.save(target/'ic_launcher_foreground.png')
ios=ROOT/'ios/App/App/Assets.xcassets/AppIcon.appiconset';ios.mkdir(parents=True,exist_ok=True)
icon.convert('RGB').save(ios/'AppIcon-1024.png')
(ios/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon-1024.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2)+'\n',encoding='utf-8')
print('Windows, Android and iOS icons derived from the approved opaque knight master.')
