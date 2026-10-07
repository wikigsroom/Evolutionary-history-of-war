"""Prepare the approved raster assets and deterministic nine-slice UI surfaces."""
from pathlib import Path
import json, shutil
from PIL import Image, ImageDraw
from fontTools import subset

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'godot/assets'
UI = DEST / 'ui/pixel'
UI.mkdir(parents=True, exist_ok=True)
sheet = Image.open(ROOT/'output/imagegen/epoch-rush/godot-polish/pixel-icons-v2.png').convert('RGBA')
names = ['ally','enemy','gold','xp','command','population','queue','lock','research','tower','evolve','drum','smoke','crystal','warning','target','back','check','heal','shield','meteor','sword','crown','sound']
for i,name in enumerate(names):
 x,y=(i%6)*256,(i//6)*256
 im=sheet.crop((x+12,y+12,x+244,y+244))
 bbox=im.getchannel('A').point(lambda x:255 if x>80 else 0).getbbox()
 if bbox: im=im.crop(bbox)
 im.thumbnail((192,192),Image.Resampling.NEAREST)
 tile=Image.new('RGBA',(208,208));tile.alpha_composite(im,((208-im.width)//2,(208-im.height)//2))
 tile.save(UI/(name+'.png'))

palettes={
 'navy':('#070d20','#253f60','#51789e','#102139','#091429'),
 'hover':('#070d20','#49c7ed','#b4f0ff','#21446a','#102945'),
 'pressed':('#050b17','#315c7b','#6093b2','#0b192a','#122b43'),
 'paper':('#0a1020','#9e7441','#fff1c5','#ecdab1','#d4b98b'),
 'paper-hover':('#0a1020','#dfaa42','#fff3b2','#f7eac6','#e0c58d'),
 'gold':('#211b22','#b37720','#fff2ad','#e8ad3c','#966123'),
 'red':('#150f20','#873d4f','#e27877','#54263d','#29182d'),
 'disabled':('#080e19','#344556','#607381','#172535','#101b29'),
 'tab':('#080d1d','#244365','#4c7193','#192e4b','#10203a')}
for name,(outline,border,light,fill,shadow) in palettes.items():
 im=Image.new('RGBA',(24,24));d=ImageDraw.Draw(im)
 shape=[(3,0),(20,0),(20,1),(22,1),(22,3),(23,3),(23,20),(22,20),(22,22),(20,22),(20,23),(3,23),(3,22),(1,22),(1,20),(0,20),(0,3),(1,3),(1,1),(3,1)]
 d.polygon(shape,fill=outline)
 d.rectangle((3,1,20,22),fill=border);d.rectangle((1,3,22,20),fill=border)
 d.rectangle((3,3,20,20),fill=fill);d.rectangle((2,4,21,19),fill=fill)
 d.line((4,2,19,2),fill=light);d.line((2,4,2,18),fill=light)
 d.line((4,21,19,21),fill=shadow);d.line((21,4,21,19),fill=shadow)
 d.point((3,3),fill=light);d.point((20,20),fill=shadow)
 im.resize((72,72),Image.Resampling.NEAREST).save(UI/('frame-'+name+'.png'))

target=DEST/'environment/turrets';target.mkdir(parents=True,exist_ok=True)
for p in (ROOT/'public/assets/environment/turrets').glob('*.png'):shutil.copy2(p,target/p.name)
# All fonts remain OFL licensed; add native UI strings to the shipped subset.
text=''.join(p.read_text(encoding='utf-8') for base in ['godot/scripts','docs/epoch-rush/data','src'] for p in (ROOT/base).rglob('*') if p.suffix in ['.gd','.ts','.json'])
text+=''.join(chr(i) for i in range(32,127))+'战役继续归队撤退推进轻松标准挑战远征战斗研究工坊设置说明觉醒先锋守城升级返回全部恢复胜利失败平局胜场败场音量降低动态全屏保存暂停关闭取消选择装配图鉴准备就绪未解锁已装备所需人口军令冷却战鼓烟幕补给掌握点领取重新出征进化战斗经验'
for name,source in [('resource-rounded','resource-rounded/ResourceHanRoundedCN-Medium.ttf'),('smiley','smiley/SmileySans-Oblique.ttf')]:
 options=subset.Options();options.flavor='woff2';options.layout_features=['*']
 font=subset.load_font(str(ROOT/'output/font-sources'/source),options)
 sub=subset.Subsetter(options=options);sub.populate(text=text);sub.subset(font)
 subset.save_font(font,str(DEST/'fonts'/(name+'.woff2')),options)
print('Prepared 24 AI icons, 9 nine-slice frames, turret assets, and OFL Chinese fonts.')
