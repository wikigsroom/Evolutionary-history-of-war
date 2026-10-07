from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/qa/redesign';OUT.mkdir(parents=True,exist_ok=True)
m=json.loads((ROOT/'public/assets/manifest.json').read_text(encoding='utf-8'))['entries']
font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',18)
for group,keys,cols,size in [('heroes',[f'hero.H0{i}' for i in range(1,7)],3,450),('units',[f'unit.U{era}{i}' for era in range(1,6) for i in range(1,5)],5,300)]:
    rows=(len(keys)+cols-1)//cols;sheet=Image.new('RGB',(cols*size,rows*(size+30)),(28,48,64));draw=ImageDraw.Draw(sheet)
    for index,key in enumerate(keys):
        x=index%cols*size;y=index//cols*(size+30);image=Image.open(ROOT/'public/assets'/m[key]['path']).convert('RGBA');image=image.resize((size,size),Image.Resampling.LANCZOS);sheet.paste(image,(x,y+30),image)
        draw.text((x+10,y+5),key,font=font,fill=(245,225,174))
        for n in range(1,5):draw.line((x+n*size/5,y+30,x+n*size/5,y+30+size),fill=(63,90,108),width=1);draw.line((x,y+30+n*size/5,x+size,y+30+n*size/5),fill=(63,90,108),width=1)
    sheet.save(OUT/(group+'-rig-source.jpg'),quality=95)
