"""Derive Android adaptive layers from the approved pixel crest."""
from pathlib import Path
from PIL import Image

root=Path(__file__).resolve().parents[1]
folder=root/'godot/assets/ui/pixel'
crest=Image.open(root/'public/brand/approved-knight-crest.png').convert('RGBA')
crest=crest.crop(crest.getchannel('A').getbbox())
crest.thumbnail((256,256),Image.Resampling.NEAREST)
foreground=Image.new('RGBA',(432,432))
foreground.alpha_composite(crest,((432-crest.width)//2,(432-crest.height)//2))
foreground.save(folder/'launcher-foreground.png',optimize=True)
Image.new('RGBA',(432,432),(13,23,45,255)).save(folder/'launcher-background.png',optimize=True)
monochrome=Image.new('RGBA',(432,432),(255,255,255,255))
monochrome.putalpha(foreground.getchannel('A'))
monochrome.save(folder/'launcher-monochrome.png',optimize=True)
print('Prepared adaptive foreground, background and monochrome pixel crest.')
