"""Download upstream release fonts and subset them natively on Windows."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import base64, json, subprocess, urllib.request, zipfile
import py7zr
from fontTools import subset
ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'output/font-sources'
DEST = ROOT / 'public/fonts'
SOURCES.mkdir(parents=True, exist_ok=True); DEST.mkdir(parents=True, exist_ok=True)
def download(url, path):
 if path.exists(): return
 print('Downloading ' + path.name, flush=True)
 partial = path.with_suffix(path.suffix + '.part')
 result = subprocess.run(['curl.exe','--fail','--location','--retry','2','--connect-timeout','20','--max-time','180','--silent','--show-error','--output',str(partial),url],capture_output=True,text=True)
 if result.returncode: raise RuntimeError('Font download failed: '+path.name+' '+result.stderr[-500:])
 partial.replace(path)
def prepare(job):
 name, url = job
 path = SOURCES / url.rsplit('/',1)[-1]
 download(url, path)
 unpacked = SOURCES / name
 if not unpacked.exists():
  unpacked.mkdir()
  if path.suffix == '.zip':
   with zipfile.ZipFile(path) as archive: archive.extractall(unpacked)
  else:
   with py7zr.SevenZipFile(path, 'r') as archive: archive.extractall(unpacked)
 return name, unpacked
jobs = [('resource-rounded','https://github.com/CyanoHao/Resource-Han-Rounded/releases/download/v0.990/RHR-CN-0.990.7z'),('smiley','https://github.com/atelier-anchor/smiley-sans/releases/download/v2.0.1/smiley-sans-v2.0.1.zip')]
with ThreadPoolExecutor(max_workers=2) as pool: prepared = dict(pool.map(prepare,jobs))
text = ''.join(path.read_text(encoding='utf-8') for base in ['src','docs/epoch-rush/data'] for path in (ROOT / base).rglob('*') if path.suffix in ['.ts','.json','.css','.html'])
text += ''.join(chr(code) for code in range(32,127)) + '暂停继续进化金币经验出口堵塞满员强化重型军团陨石雨烈焰齐射王国箭雨空袭轰炸轨道审判獠牙兽骑已解锁冷却战场军议说明'
unicode_set = set(map(ord,text))
for name, directory in prepared.items():
 fonts = list(directory.rglob('*.otf')) + list(directory.rglob('*.ttf'))
 if name == 'resource-rounded':
  selected = [path for path in fonts if 'Medium' in path.name or 'Regular' in path.name]
  if not selected: selected = fonts[:1]
 else: selected = fonts[:1]
 if not selected: raise RuntimeError('No font in '+name)
 source = selected[0]
 options = subset.Options()
 options.flavor = 'woff2'; options.layout_features = ['*']; options.name_IDs = ['*']; options.name_legacy = True
 font = subset.load_font(str(source), options)
 coverage = set(font.getBestCmap())
 missing = sorted(code for code in unicode_set if code >= 0x4e00 and code <= 0x9fff and code not in coverage)
 if missing: raise RuntimeError('Missing Chinese glyphs: '+''.join(map(chr,missing[:40])))
 sub = subset.Subsetter(options=options); sub.populate(unicodes=unicode_set); sub.subset(font)
 family = 'Epoch Rounded' if name=='resource-rounded' else 'Epoch Display'
 for record in font['name'].names:
  if record.nameID in [1,4,16]: record.string = family.encode(record.getEncoding())
  elif record.nameID==6: record.string = family.replace(' ','').encode(record.getEncoding())
  elif record.nameID==3: record.string = ('EpochRush;'+family+';0.3.0').encode(record.getEncoding())
 target = DEST / (name + '.woff2'); subset.save_font(font,str(target),options)
 print('Built '+target.name+' from '+source.name+' ('+str(target.stat().st_size)+' bytes)',flush=True)
 licenses = [path for path in directory.rglob('*') if path.is_file() and any(word in path.name.lower() for word in ['license','ofl','licence'])]
 if not licenses:
  api_url = 'https://api.github.com/repos/'+ ('adobe-fonts/source-han-sans/contents/LICENSE.txt' if name=='resource-rounded' else 'atelier-anchor/smiley-sans/contents/LICENSE')
  request = urllib.request.Request(api_url,headers={'User-Agent':'Epoch-Rush-build'})
  with urllib.request.urlopen(request,timeout=30) as response: license_data = json.load(response)
  (DEST / (name + '-LICENSE.txt')).write_bytes(base64.b64decode(license_data['content']))
 else: (DEST / (name + '-LICENSE.txt')).write_bytes(licenses[0].read_bytes())
(DEST / 'sources.json').write_text(json.dumps({'sources':[{'name':name,'url':url} for name,url in jobs],'subset':'All shipped game UI and content text, ASCII, full shaping features'},indent=2)+'\n',encoding='utf-8')
