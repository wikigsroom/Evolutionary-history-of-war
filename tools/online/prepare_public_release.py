"""Collect current public/native deliveries only after their evidence passes."""
import hashlib,json,re,shutil,tarfile,zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
VERSION=re.search(r'config/version="([^"]+)"',(ROOT/'godot/project.godot').read_text(encoding='utf-8')).group(1)
CODE=int(re.search(r'version/code=(\d+)',(ROOT/'godot/export_presets.example.cfg').read_text(encoding='utf-8')).group(1))
DEST=ROOT/'output/releases'/('v'+VERSION)
QA=ROOT/'docs/qa'/('v'+VERSION)


def report(path,count=None):
    data=json.loads(path.read_text(encoding='utf-8-sig'))
    if data.get('failed') or data.get('passed') is False or any(not row.get('passed') for row in data.get('checks',[])):
        raise RuntimeError('Failed validation: '+str(path.relative_to(ROOT)))
    if count is not None and len(data['checks'])!=count:raise RuntimeError('Unexpected check count: '+path.name)
    return data


def digest(path):
    checksum=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):checksum.update(chunk)
    return checksum.hexdigest()


def main():
    QA.mkdir(parents=True,exist_ok=True);DEST.mkdir(parents=True,exist_ok=True)
    reports=[
        ('output/qa/online/server-bundle.json','server-bundle.json',10),
        ('output/qa/online/server-bundle-integration.json','server-bundle-integration.json',23),
        ('output/qa/public-online/native-client-playable.json','public-client-playable.json',22),
        ('output/qa/public-online/network-integration.json','public-network.json',23),
        ('output/qa/public-online/recovery/public-native-recovery.json','public-recovery.json',11),
        ('output/qa/public-online/queue-liveness.json','queue-liveness.json',7),
        ('output/qa/public-online/public-load.json','public-load.json',4),
        ('output/qa/public-online/privacy-live.json','privacy-live.json',6),
        ('output/qa/public-online/server-operations.json','server-operations.json',12),
    ]
    for relative,name,count in reports:
        source=ROOT/relative;report(source,count);shutil.copy2(source,QA/name)
    android_path=ROOT/'output/qa/online/packages/online-android.json'
    branding_path=ROOT/'output/qa/public-online/packages/launcher-branding.json'
    android=report(android_path);branding=report(branding_path)
    if not android.get('passed') or not branding.get('passed'):raise RuntimeError('Incomplete Android/branding checks')
    shutil.copy2(android_path,QA/'android-packages.json');shutil.copy2(branding_path,QA/'launcher-branding.json')
    signed_path=ROOT/'output/qa/ten-eras/android-finalization.json'
    signed=report(signed_path)
    if not signed.get('passed'):raise RuntimeError('Incomplete APK signature/alignment checks')
    shutil.copy2(signed_path,QA/'android-finalization.json')
    go_text=(ROOT/'output/qa/online/go-control.jsonl').read_text(encoding='utf-8-sig')
    events=[json.loads(line) for line in go_text.splitlines() if line.strip()]
    if len([row for row in events if row.get('Action')=='pass' and row.get('Test')])!=7 or any(row.get('Action')=='fail' for row in events):raise RuntimeError('Go control checks failed')
    (QA/'go-control.jsonl').write_text(go_text,encoding='utf-8',newline='\n')
    for relative,name in [('output/qa/public-online/client_playable-embedded.log','public-client.txt'),('output/qa/public-online/recovery/native.log','public-recovery.txt')]:
        text=(ROOT/relative).read_text(encoding='utf-8-sig')
        if 'SCRIPT ERROR:' in text or 'Parse Error:' in text or '\nERROR:' in text:raise RuntimeError('Native script log contains errors')
        (QA/name).write_text(text,encoding='utf-8')
    font_path=ROOT/'output/qa/public-online/font-coverage.json'
    if not report(font_path).get('passed'):raise RuntimeError('Incomplete CJK font coverage')
    shutil.copy2(font_path,QA/'font-coverage.json')
    artifacts=[ROOT/'godot/build/windows/Epoch-Rush-Godot.exe',ROOT/'godot/build/windows/Epoch-Rush-Godot-Windows.zip',ROOT/'godot/build/android/Epoch-Rush-Godot-debug.apk',ROOT/'godot/build/android/Epoch-Rush-Godot-release.apk',DEST/'server'/f'Epoch-Rush-Server-{VERSION}-Windows-x64.zip',DEST/'linux-server'/f'Epoch-Rush-Server-{VERSION}-Linux-x64.tar.gz']
    packages={row['platform']:row for row in android['packages']}
    signed_packages={row['file']:row for row in signed['packages']}
    servers={key:report(DEST/key/'server-package.json') for key in ['server','linux-server']}
    receipt={'version':VERSION,'android_version_code':CODE,'official_endpoint':'https://jyqx-server.sidcloud.cn','artifacts':[]}
    for source in artifacts:
        if not source.is_file():raise RuntimeError('Missing artifact: '+source.name)
        sha256=digest(source)
        if source.suffix=='.apk' and sha256!=packages['debug' if 'debug' in source.name else 'release']['sha256']:raise RuntimeError('APK changed after inspection')
        if source.suffix=='.apk' and sha256!=signed_packages[source.name]['sha256']:raise RuntimeError('APK changed after signature verification')
        if 'Server-' in source.name and sha256!=servers['linux-server' if source.name.endswith('.tar.gz') else 'server']['sha256']:raise RuntimeError('Server changed after packaging')
        if source.suffix=='.zip':
            with zipfile.ZipFile(source) as archive:
                if archive.testzip():raise RuntimeError('Corrupt ZIP: '+source.name)
                if source.name=='Epoch-Rush-Godot-Windows.zip' and hashlib.sha256(archive.read('Epoch-Rush-Godot.exe')).hexdigest()!=digest(ROOT/'godot/build/windows/Epoch-Rush-Godot.exe'):raise RuntimeError('Portable ZIP does not contain the verified executable')
        if source.name.endswith('.tar.gz'):
            with tarfile.open(source,'r:gz') as archive:
                if any(not member.isfile() or member.issym() or member.islnk() for member in archive.getmembers()):raise RuntimeError('Unexpected Linux archive member')
        destination=DEST/source.name;shutil.copy2(source,destination)
        if digest(destination)!=sha256:raise RuntimeError('Release copy differs from inspected source')
        receipt['artifacts'].append({'name':source.name,'bytes':source.stat().st_size,'sha256':sha256})
    encoded=json.dumps(receipt,indent=2)+'\n'
    (DEST/'release-artifacts.json').write_text(encoded,encoding='utf-8');(QA/'release-artifacts.json').write_text(encoded,encoding='utf-8')
    (DEST/'SHA256SUMS.txt').write_text(''.join(row['sha256']+'  '+row['name']+'\n' for row in receipt['artifacts']),encoding='utf-8')
    shutil.copy2(ROOT/'output/qa/online/windows-online-content.json',QA/'windows-online-content.json')
    media=ROOT/'docs/media'/('v'+VERSION);media.mkdir(parents=True,exist_ok=True)
    captures=[]
    for name in ['consent','hall','room','battle','result']:
        source=ROOT/'output/qa/online'/('native-online-'+name+'.png')
        target=media/('online-'+name+'.png');shutil.copy2(source,target)
        captures.append({'file':str(target.relative_to(ROOT)).replace('\\','/'),'sha256':digest(target)})
    (QA/'media-provenance.json').write_text(json.dumps({'version':VERSION,'windows_executable_sha256':receipt['artifacts'][0]['sha256'],'source':'Final exported Windows resource pack; actual public matches from the 22-check client run','captures':captures},indent=2),encoding='utf-8')
    print('Six validated native artifacts and SHA256SUMS ready:',DEST)


if __name__=='__main__':main()
