"""Pixel typography and exact-logo compositing for the approved identity."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageFilter,ImageOps
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/marketing/2026-10-08'
ART=ROOT/'output/imagegen/marketing/2026-10-08'
INK=(7,17,38)
GOLD=(255,213,119)
IVORY=(255,240,206)

def font_path(display=False):
    path=OUT/'source/fonts'/('display.ttf' if display else 'body.ttf')
    return path if path.exists() else ROOT/'godot/assets/fonts'/('smiley.ttf' if display else 'resource-rounded.ttf')

def mask_text(text,size,display=False,tracking=0,block=2):
    font=ImageFont.truetype(str(font_path(display)),max(8,round(size/block)))
    advance=sum(font.getlength(c) for c in text)+(tracking/block)*(len(text)-1)
    mask=Image.new('L',(int(advance)+size*2,size*3),0)
    d=ImageDraw.Draw(mask);x=size//2
    for c in text:
        d.text((round(x),size//2),c,font=font,fill=255)
        x+=font.getlength(c)+tracking/block
    bounds=mask.getbbox()
    if bounds is None:raise ValueError('Empty text '+text)
    mask=mask.crop(bounds).point(lambda a:255 if a>=96 else 0)
    return mask.resize((mask.width*block,mask.height*block),Image.Resampling.NEAREST)

def text_art(text,size,display=False,tracking=0,block=2,color=IVORY):
    ink=mask_text(text,size,display,tracking,block)
    pad=24 if display else 10
    mask=Image.new('L',(ink.width+pad*2,ink.height+pad*2),0);mask.paste(ink,(pad,pad))
    image=Image.new('RGBA',mask.size)
    if display:
        border=mask.filter(ImageFilter.MaxFilter(17))
        image.paste((*INK,255),(0,0),border)
        border=mask.filter(ImageFilter.MaxFilter(9))
        for z in range(12,0,-3):image.paste((96,48,20,255),(z,z),border)
        image.paste((88,43,21,255),(0,0),border)
        ramp=np.clip((np.arange(mask.height)-pad)//3*3/max(1,ink.height-1),0,1)
        pixels=np.zeros((mask.height,mask.width,4),dtype=np.uint8)
        for c in range(3):pixels[:,:,c]=np.interp(ramp,[0,.35,.7,1],[(255,243,191)[c],(255,218,133)[c],(248,187,69)[c],(207,132,37)[c]])[:,None]
        pixels[:,:,3]=np.asarray(mask)
        image.alpha_composite(Image.fromarray(pixels))
    else:
        image.paste((*INK,255),(0,0),mask.filter(ImageFilter.MaxFilter(9)))
        image.paste((9,14,25,255),(2,4),mask)
        image.paste((*color,255),(0,0),mask)
    return image,pad,ink.size

def label(canvas,text,size,x,y,center=False,**options):
    art,pad,extent=text_art(text,size,**options)
    if center:x-=extent[0]/2
    left=round(x);top=round(y)
    canvas.alpha_composite(art,(left-pad,top-pad))
    box=[left,top,left+extent[0],top+extent[1]]
    if box[0]<0 or box[1]<0 or box[2]>canvas.width or box[3]>canvas.height:
        raise RuntimeError('Clipped text: '+text+' '+str(box))
    return {'text':text,'visible_box':box}

def scene(file,size):
    source=Image.open(file).convert('RGBA')
    # Center-crop at most the tiny model aspect rounding, never stretch geometry.
    return ImageOps.fit(source,size,method=Image.Resampling.NEAREST,centering=(.5,.5)),list(source.size)

def wash(canvas,top=0,left=0,bottom=0):
    w,h=canvas.size;x=np.arange(w)[None,:]/w;y=np.arange(h)[:,None]/h
    opacity=np.zeros((h,w),np.float32)
    if top:opacity=np.maximum(opacity,np.clip((.49-y)/.23,0,1)*top)
    if left:opacity=np.maximum(opacity,np.clip((.47-x)/.22,0,1)*left)
    if bottom:opacity=np.maximum(opacity,np.clip((y-.88)/.12,0,1)*bottom)
    pixels=np.zeros((h,w,4),np.uint8);pixels[:,:,:3]=INK;pixels[:,:,3]=(opacity*255).astype(np.uint8)
    canvas.alpha_composite(Image.fromarray(pixels))

def logo(canvas,x,y,size):
    approved=Image.open(OUT/'source/selected-logo.png').convert('RGBA').resize((size,size),Image.Resampling.NEAREST)
    mask=approved.getchannel('A').point(lambda a:round(a*.85)).filter(ImageFilter.MaxFilter(9))
    shadow=Image.new('RGBA',approved.size,(*INK,0));shadow.putalpha(mask)
    canvas.alpha_composite(shadow,(x+3,y+6));canvas.alpha_composite(approved,(x,y))
    return {'source':'source/selected-logo.png','box':[x,y,x+size,y+size],'preserved_identity':True}

def save(canvas,path):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    canvas=canvas.convert('RGB');canvas.save(path,optimize=True)
    canvas.save(path.with_suffix('.jpg'),quality=96,subsampling=0,optimize=True)
