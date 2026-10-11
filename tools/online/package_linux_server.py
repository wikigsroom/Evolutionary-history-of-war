"""Build a minimal native Linux authority; no credentials or client art enter it."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import tarfile

ROOT=Path(__file__).resolve().parents[2]
PROJECT=ROOT/'godot'
VERSION=re.search(r'config/version="([^"]+)"',(PROJECT/'project.godot').read_text(encoding='utf-8')).group(1)
TARGET=ROOT/'output/releases'/('v'+VERSION)/'linux-server'


def copy(source,target):
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,target)


def main():
    bundle=TARGET/'Epoch-Rush-Server'
    copy(ROOT/'output/deploy/online/epoch-online-linux-amd64',bundle/'bin/epoch-online')
    if (bundle/'bin/epoch-online').read_bytes()[:4]!=b'\x7fELF':raise RuntimeError('Expected native Linux ELF executable')
    for name in ['game_model.gd','game_data.gd','epoch_combat.gd','epoch_skills.gd','epoch_environment.gd','epoch_snapshot_migration.gd']:
        copy(PROJECT/'scripts'/name,bundle/'referee/scripts'/name)
        uid=PROJECT/'scripts'/(name+'.uid')
        if uid.exists():copy(uid,bundle/'referee/scripts'/uid.name)
    for path in (PROJECT/'server').glob('*.gd'):copy(path,bundle/'referee/server'/path.name)
    for path in (PROJECT/'assets/data').glob('*.json'):copy(path,bundle/'referee/assets/data'/path.name)
    (bundle/'referee/project.godot').write_text('config_version=5\n[application]\nconfig/name="Epoch Rush Authority"\nconfig/features=PackedStringArray("4.7", "GL Compatibility")\n[threading]\nworker_pool/max_threads=2\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8',newline='\n')
    for path in (ROOT/'services/online-gateway/deploy/linux').iterdir():
        if path.is_file():copy(path,bundle/'ops'/path.name)
    (bundle/'README.md').write_text((ROOT/'services/online-gateway/README.md').read_text(encoding='utf-8').replace('deploy/linux/README.md','ops/README.md'),encoding='utf-8',newline='\n')
    copy(ROOT/'services/online-gateway/THIRD-PARTY.txt',bundle/'licenses/THIRD-PARTY.txt')
    for name in ['Godot-LICENSE.txt','Godot-third-party-notices.txt']:copy(PROJECT/'docs/distribution'/name,bundle/'licenses'/name)
    copy(ROOT/'.local-tools/online/go/LICENSE',bundle/'licenses/Go-LICENSE.txt')
    shutil.copytree(ROOT/'services/online-gateway/licenses/go-modules',bundle/'licenses/go-modules',dirs_exist_ok=True)
    manifest={}
    for path in sorted(bundle.rglob('*')):
        if path.is_file() and '.godot' not in path.parts and path.name!='BUNDLE-MANIFEST.json':
            name=path.relative_to(bundle).as_posix()
            if any(value in name.lower() for value in ['credentials','online.env','password','known_hosts','.dpapi']):raise RuntimeError('Private file in bundle')
            manifest[name]={'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    simulation_hash=json.loads((PROJECT/'assets/data/online-manifest.json').read_text(encoding='utf-8'))['simulation_hash']
    (bundle/'BUNDLE-MANIFEST.json').write_text(json.dumps({'version':VERSION,'native':'linux-amd64','simulation_hash':simulation_hash,'files':manifest,'godot_url':'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip','godot_archive_sha256':'cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4'},indent=2),encoding='utf-8')
    archive=TARGET/f'Epoch-Rush-Server-{VERSION}-Linux-x64.tar.gz'
    with tarfile.open(archive,'w:gz') as tar:
        for path in sorted(bundle.rglob('*')):
            if path.is_file() and '.godot' not in path.parts:
                info=tar.gettarinfo(str(path),arcname='Epoch-Rush-Server/'+path.relative_to(bundle).as_posix())
                info.uid=info.gid=0;info.uname=info.gname='root'
                info.mode=0o755 if path.name=='epoch-online' or path.suffix=='.sh' else 0o644
                with path.open('rb') as stream:tar.addfile(info,stream)
    (TARGET/'server-package.json').write_text(json.dumps({'version':VERSION,'archive':str(archive.relative_to(ROOT)),'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'files':len(manifest),'native':'linux-amd64','requires_docker_wsl_vm':False},indent=2),encoding='utf-8')
    print('Linux authority archive ready:',archive,archive.stat().st_size,'bytes')


if __name__=='__main__':main()
