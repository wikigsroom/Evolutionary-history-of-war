"""Generate five uncluttered battle panoramas through the authorized Sub2 skill."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess,json,time,hashlib
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/epoch-rush/redesign'
CLI=Path('C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py')
SCENES={
 'A1':'Prehistoric river valley: sage green forest, distant blue mountains, ochre earth, sparse primitive campfires far away, a warm dawn sky. The playable field is bare packed earth.',
 'A2':'Bronze age Mediterranean river plain: terraced olive hills, distant tiny bronze-age rooftops beyond the river, dusty warm copper earth and turquoise sky. The playable field is bare earth.',
 'A3':'Medieval kingdom valley: muted blue-green mountains, distant fir woods and a placid river, only tiny settlements far on the horizon, warm buff earth under a clear morning sky. The playable field is bare packed earth. Absolutely no castle or walls on either side of the foreground.',
 'A4':'Industrial civilization valley: distant small factories with graceful brick chimneys and thin smoke on the horizon, steel blue cloudy sky, muted russet hills, distant rail viaduct. The playable field is flat dusty earth. No foreground machinery.',
 'A5':'Hopeful orbital civilization frontier: distant mountains and elegant tiny futuristic buildings on the horizon, a faint planet and orbital ring in a pale turquoise sky, slate blue and muted indigo atmosphere. The playable field is a flat sandy stone plain. No foreground spacecraft.',
}
STYLE='''Original polished 2D side-view strategy game background, landscape 3:2 composition, stylized hand-painted animation art with clean dark contour lines, restrained cel-shaded shapes and soft painterly gradients, readable large shapes and muted colors so foreground cartoon soldiers stand out. Side-on camera with ZERO perspective convergence in the playable field. Distant horizon halfway down, layered mountains and sky in the upper half, the bottom 40 percent is a completely EMPTY flat horizontal field. Keep all large landscape features small and distant. The left edge and right edge MUST both be entirely open, with no foreground structures, so separate game base sprites can be placed there later. NO people, soldiers, animals, flags, weapons, castles, towers, gates, walls, pillars, oversized trees, foreground buildings, UI, text, lettering, watermark or logos. Soft bright atmospheric background, evenly readable light from left to right. This is scenery only, not a game screenshot. '''
def generate(era,scene):
    target=OUT/f'battle-{era}.png';prompt=OUT/f'battle-{era}-prompt.txt';prompt.write_text(STYLE+scene,encoding='utf-8')
    if target.exists():return {'era':era,'status':'existing','path':str(target.relative_to(ROOT))}
    for attempt in range(4):
        result=subprocess.run(['python','-X','utf8',str(CLI),'generate','--prompt-file',str(prompt),'--model','gpt-image-2.5','--quality','high','--size','1536x1024','--out',str(target)],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        if result.returncode==0 and target.exists():
            with Image.open(target) as image:image.verify()
            record={'era':era,'requestedModel':'gpt-image-2.5','size':'1536x1024','quality':'high','route':'sub2-image-gen CLI','promptFile':prompt.name,'sourceSha256':hashlib.sha256(target.read_bytes()).hexdigest(),'status':'generated_pending_visual_review'}
            target.with_suffix('.metadata.json').write_text(json.dumps(record,indent=2,ensure_ascii=False)+'\n',encoding='utf-8');return record
        message=(result.stderr or result.stdout)[-1200:]
        if '429' in message and attempt<3:time.sleep((attempt+1)*10);continue
        return {'era':era,'status':'error','error':message}
OUT.mkdir(parents=True,exist_ok=True)
results=[]
with ThreadPoolExecutor(max_workers=2) as pool:
    tasks=[pool.submit(generate,era,scene) for era,scene in SCENES.items()]
    for future in as_completed(tasks):
        result=future.result();results.append(result);print(json.dumps(result,ensure_ascii=False),flush=True)
(OUT/'battle-generation-report.json').write_text(json.dumps(results,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
if any(r['status']=='error' for r in results):raise SystemExit(1)
