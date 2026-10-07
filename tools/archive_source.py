"""Create a self-contained source/assets handoff without local SDK paths or dependencies."""
from pathlib import Path
import hashlib,json,zipfile,sys,subprocess

root=Path(__file__).resolve().parents[1]
version=json.loads((root/'package.json').read_text(encoding='utf-8'))['version']
candidate='--candidate' in sys.argv
out=root/(f'output/releases/candidates/v{version}/source' if candidate else 'output/releases/source');out.mkdir(parents=True,exist_ok=True)
target=out/f'Epoch-Rush-{version}-{"Candidate-" if candidate else ""}source.zip'
if not candidate:subprocess.run(['node','--input-type=module','-e',"import {assertAnimationRelease} from './tools/release_gate.mjs'; assertAnimationRelease(process.cwd());"],cwd=root,check=True)
top_files=['README.md','package.json','package-lock.json','tsconfig.json','vite.config.ts','index.html','capacitor.config.json','.gitignore']
trees=['src','public','desktop','tools','tests','docs','design-system','android','ios','output/imagegen/epoch-rush','output/imagegen/directions','output/qa']
files={root/name for name in top_files if (root/name).is_file()}
for folder in trees:
    for path in (root/folder).rglob('*'):
        if not path.is_file():continue
        rel=path.relative_to(root);parts=rel.parts
        if any(p in ['node_modules','.gradle','build','__pycache__','Pods','DerivedData'] for p in parts):continue
        qa_logs={'output/qa/v0.3/tests-final.log','output/qa/v0.3/windows-native.log','output/qa/v0.3/image-gateway.log','output/qa/v0.3/final-release-gate.log'}
        if path.name=='local.properties' or path.suffix=='.pyc' or path.suffix=='.log' and rel.as_posix() not in qa_logs:continue
        if str(rel).replace('\\','/').startswith(('android/app/src/main/assets/public/','ios/App/App/public/')):continue
        files.add(path)
manifest=[]
with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=5,allowZip64=True) as archive:
    for path in sorted(files):
        name=path.relative_to(root).as_posix();content=path.read_bytes()
        manifest.append({'path':name,'bytes':len(content),'sha256':hashlib.sha256(content).hexdigest()})
        archive.writestr('Epoch-Rush/'+name,content)
    archive.writestr('Epoch-Rush/SOURCE-MANIFEST.json',json.dumps({'version':version,'files':manifest},ensure_ascii=False,indent=2)+'\n')
with zipfile.ZipFile(target) as archive:
    bad=archive.testzip()
    if bad:raise RuntimeError('ZIP CRC failed: '+bad)
    for record in manifest:
        if hashlib.sha256(archive.read('Epoch-Rush/'+record['path'])).hexdigest()!=record['sha256']:raise RuntimeError('Archive hash mismatch: '+record['path'])
report={'path':target.relative_to(root).as_posix(),'files':len(manifest),'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'crcVerified':True,'entryHashesVerified':True,'excluded':'node_modules, native build caches, duplicated native web output, machine SDK paths'}
(out/'source-archive.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
