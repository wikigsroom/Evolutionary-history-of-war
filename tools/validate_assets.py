"""Validate runtime files, source provenance and audio signals without changing art approval."""
from pathlib import Path
import hashlib,json,subprocess,wave
import numpy as np
from PIL import Image

root=Path(__file__).resolve().parents[1]
assets=root/'public/assets'
manifest=json.loads((assets/'manifest.json').read_text(encoding='utf-8'))['entries']
plan=json.loads((root/'docs/epoch-rush/data/asset-manifest.json').read_text(encoding='utf-8'))['entries']
errors=[];texture_bytes=0;audio=[]
for key,entry in manifest.items():
    path=assets/entry['path']
    if not path.is_file():errors.append('Missing '+key);continue
    if entry.get('sha256') and hashlib.sha256(path.read_bytes()).hexdigest()!=entry['sha256']:errors.append('Hash mismatch '+key)
    if path.suffix in ['.png','.webp']:
        with Image.open(path) as image:
            texture_bytes+=image.width*image.height*4;image.verify()
    if entry['kind']=='audio':
        decoded=subprocess.run(['ffmpeg','-v','error','-i',str(path),'-f','f32le','-acodec','pcm_f32le','-ac','2','-ar','48000','-'],capture_output=True,check=True).stdout
        signal=np.frombuffer(decoded,dtype='<f4').reshape(-1,2)
        peak=float(np.max(np.abs(signal)));rms=float(np.sqrt(np.mean(signal**2)))
        row={'key':key,'durationSec':round(len(signal)/48000,3),'peak':round(peak,6),'rms':round(rms,6),'clippedSamples':int(np.count_nonzero(np.abs(signal)>=1)),'boundaryJump':round(float(np.max(np.abs(signal[-1]-signal[0]))),6)}
        audio.append(row)
        if peak>=1 or rms<.0001:errors.append('Audio signal invalid '+key)
missing=[e['key'] for e in plan if e['key'] not in manifest]
errors.extend('Missing logical asset '+key for key in missing)
sources=[]
for path in sorted((root/'output/imagegen/epoch-rush/raw').glob('*.metadata.json')):
    data=json.loads(path.read_text(encoding='utf-8'));name=data['name'];png=path.with_name(name+'.png')
    valid=png.is_file() and hashlib.sha256(png.read_bytes()).hexdigest()==data['sha256']
    sources.append({'name':name,'model':data['model'],'quality':data['quality'],'sha256':data['sha256'],'valid':valid})
    if not valid or data['model']!='gpt-image-2.5':errors.append('Source provenance invalid '+name)
redesign_sources=[]
for path in sorted((root/'output/imagegen/epoch-rush/redesign').glob('*.metadata.json')):
    data=json.loads(path.read_text(encoding='utf-8'));png=path.with_suffix('').with_suffix('.png');valid=png.is_file() and hashlib.sha256(png.read_bytes()).hexdigest()==data['sourceSha256']
    redesign_sources.append({'name':png.stem,'requestedModel':data['requestedModel'],'valid':valid})
    if not valid or data['requestedModel']!='gpt-image-2.5':errors.append('Redesign source provenance invalid '+png.stem)
raw_masters=list((root/'output/imagegen/epoch-rush/raw').glob('*.png'))
without_batch_metadata=[p.stem for p in raw_masters if not p.with_suffix('.metadata.json').is_file()]
report={'logicalAssets':len(plan),'logicalAssetsPresent':len(plan)-len(missing),'runtimeEntries':len(manifest),'runtimeBytes':sum((assets/e['path']).stat().st_size for e in manifest.values() if (assets/e['path']).is_file()),'uncompressedTextureBytesEstimate':texture_bytes,'generatedMasters':len(raw_masters),'generatedRedesignMasters':len(redesign_sources),'redesignMasters':redesign_sources,'batchMetadataMasters':len(sources),'mastersWithoutBatchMetadata':without_batch_metadata,'masters':sources,'audio':audio,'errors':errors,'note':'Technical validation only; source art and rig motion retain their separate review status. Texture bytes are a size estimate, not measured GPU memory.'}
version=json.loads((root/'package.json').read_text(encoding='utf-8'))['version']
qa=root/'output/qa'/('v'+'.'.join(version.split('.')[:2]));qa.mkdir(parents=True,exist_ok=True)
(qa/'asset-audio-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k not in ['masters','audio']},ensure_ascii=False))
raise SystemExit(bool(errors))
