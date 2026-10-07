"""Run the designated image CLI with at most two gateway requests at a time."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys
import time
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'output/imagegen/epoch-rush'
CLI = Path('C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py')
PARSER = argparse.ArgumentParser()
PARSER.add_argument('--phase',choices=['slice','full'],default='slice')
PARSER.add_argument('--limit',type=int)
PARSER.add_argument('--only',help='Comma-separated source names')
PARSER.add_argument('--regenerate',action='store_true')
ARGS = PARSER.parse_args()
entries = json.loads((ROOT / 'docs/epoch-rush/data/asset-manifest.json').read_text(encoding='utf-8'))['entries']
jobs = {}
for entry in entries:
    if entry['method'] != 'sub2_then_local_process' or ARGS.phase == 'slice' and entry['milestone'] != 'M1':
        continue
    domain, *tail = entry['key'].split('.')
    if domain in ['unit','hero','portrait','turret']:
        name = entry['ownerId']
    else:
        name = '-'.join([domain,*tail])
    jobs[name] = {'name':name,'prompt':OUTPUT / 'prompts' / (name+'.txt'),'background':'opaque' if domain == 'background' and tail[-1] in ['far','ground'] else 'transparent'}
jobs = list(jobs.values())
if ARGS.only:
    selected=set(ARGS.only.split(','))
    jobs=[job for job in jobs if job['name'] in selected]
if ARGS.limit is not None: jobs = jobs[:ARGS.limit]
OUTPUT.mkdir(parents=True,exist_ok=True)
(OUTPUT / 'raw').mkdir(exist_ok=True)

def run(job):
    target = OUTPUT / 'raw' / (job['name']+'.png')
    if target.exists() and ARGS.regenerate:
        rejected=OUTPUT/'raw/rejected'; rejected.mkdir(exist_ok=True)
        digest=hashlib.sha256(target.read_bytes()).hexdigest()[:12]
        backup=rejected/(job['name']+'-'+digest+'.png')
        if not backup.exists(): backup.write_bytes(target.read_bytes())
        metadata=target.with_suffix('.metadata.json')
        if metadata.exists(): (rejected/(job['name']+'-'+digest+'.metadata.json')).write_bytes(metadata.read_bytes())
    if target.exists() and not ARGS.regenerate:
        with Image.open(target) as image: image.verify()
        return {'name':job['name'],'status':'existing_raw'}
    if not job['prompt'].is_file():
        return {'name':job['name'],'status':'missing_prompt'}
    print('Generating '+job['name'],flush=True)
    for attempt in range(3):
        command=[sys.executable,'-X','utf8',str(CLI),'generate','--prompt-file',str(job['prompt']),'--model','gpt-image-2.5','--quality','high','--background',job['background'],'--out',str(target)]
        if ARGS.regenerate: command.append('--force')
        result = subprocess.run(command,cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
        if result.returncode == 0:
            with Image.open(target) as image:
                dimensions=list(image.size); image.verify()
            metadata={'name':job['name'],'status':'generated','model':'gpt-image-2.5','quality':'high','background':job['background'],'sourceSize':dimensions,'promptSha256':hashlib.sha256(job['prompt'].read_bytes()).hexdigest(),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
            (OUTPUT / 'raw' / (job['name']+'.metadata.json')).write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
            print('Generated '+job['name'],flush=True)
            return metadata
        error=result.stderr.strip() or result.stdout.strip()
        if '429' in error and attempt < 2:
            print('Gateway 429 for '+job['name']+'; retrying the same model.',flush=True)
            time.sleep(2*(attempt+1))
            continue
        print('Failed '+job['name']+': '+error[:500],flush=True)
        return {'name':job['name'],'status':'failed','error':error[:500]}

results=[]
with ThreadPoolExecutor(max_workers=2) as pool:
    futures=[pool.submit(run,job) for job in jobs]
    for future in as_completed(futures): results.append(future.result())
report={'phase':ARGS.phase,'model':'gpt-image-2.5','results':results}
report_name='generation-'+ARGS.phase+('-revision' if ARGS.regenerate else '')+'.json'
(OUTPUT / report_name).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
failed=[item for item in results if item['status'] not in ['generated','existing_raw']]
print(json.dumps({'requested':len(jobs),'successful':len(results)-len(failed),'failed':len(failed)},ensure_ascii=False),flush=True)
raise SystemExit(1 if failed else 0)
