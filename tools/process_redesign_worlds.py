"""Publish visually reviewed five-era Sub2 panoramas as compressed runtime textures."""
from pathlib import Path
from PIL import Image
import hashlib,json
r=Path(__file__).resolve().parents[1];assets=r/'public/assets';m=json.loads((assets/'manifest.json').read_text(encoding='utf-8'))
for i in range(1,6):
 era=f'A{i}';raw=r/f'output/imagegen/epoch-rush/redesign/battle-{era}.png';out=assets/f'environment/backgrounds/{era}-battle.webp'
 Image.open(raw).convert('RGB').save(out,quality=92,method=6)
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 key=f'background.{era}.battle';m['entries'][key]={'key':key,'kind':'background','path':out.relative_to(assets).as_posix(),'size':[1536,1024],'status':'reviewed_clear_battle_panorama','model':'gpt-image-2.5','source':raw.relative_to(r).as_posix(),'sourceSha256':sha(raw),'sha256':sha(out),'method':'sub2_image_gen_cli_webp_derivative'}
 meta=json.loads(raw.with_suffix('.metadata.json').read_text(encoding='utf-8'));meta['review']='Inspected all five panoramas together: clear horizontal foreground, small distant era scenery, no foreground bases or actors.';raw.with_suffix('.metadata.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(assets/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'reviewedPanoramas':5}))
