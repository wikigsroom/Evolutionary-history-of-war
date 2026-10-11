"""Collect a client-only release from verified final native packages and screenshots."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile
import requests

ROOT = Path(__file__).resolve().parents[2]
VERSION = re.search(r'config/version="([^"]+)"', (ROOT/'godot/project.godot').read_text(encoding='utf-8')).group(1)
CODE = int(re.search(r'version/code=(\d+)', (ROOT/'godot/export_presets.example.cfg').read_text(encoding='utf-8')).group(1))
SOURCE = ROOT/'output/qa/online'
DEST = ROOT/'output/releases'/('v'+VERSION)
QA = ROOT/'docs/qa'/('v'+VERSION)


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''): value.update(chunk)
    return value.hexdigest()


def report(path, count=None):
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    assert not data.get('failures') and not data.get('failed') and data.get('passed') is not False, path.name
    assert all(row['passed'] for row in data.get('checks', [])), path.name
    if count is not None: assert len(data['checks']) == count, path.name
    return data


def main():
    QA.mkdir(parents=True, exist_ok=True)
    DEST.mkdir(parents=True, exist_ok=True)
    for name, count, log in [
        ('native-client-playable.json',24,'client_playable-embedded.log'),
        ('lobby-layout.json',65,'lobby_layout-embedded.log'),
        ('lobby-reconnect.json',12,'lobby_reconnect-embedded.log'),
        ('endpoint-lock.json',5,'endpoint_lock-embedded.log'),
    ]:
        report(SOURCE/name, count)
        text = (SOURCE/log).read_text(encoding='utf-8-sig')
        assert not any(term in text for term in ['SCRIPT ERROR:', 'Parse Error:', '\nERROR:']), log
        shutil.copy2(SOURCE/name, QA/name)
        (QA/log.replace('.log','.txt')).write_text(text, encoding='utf-8', newline='\n')
    windows = report(SOURCE/'windows-online-content.json')
    assert windows['version'] == VERSION and windows['passed']
    android = report(SOURCE/'packages/online-android.json')
    assert android['passed'] and android['version'] == VERSION
    branding_path = SOURCE/'packages/launcher-branding.json'
    branding = report(branding_path)
    assert branding['passed'] and branding['version'] == VERSION
    signed_path = ROOT/'output/qa/ten-eras/android-finalization.json'
    signed = report(signed_path)
    assert signed['passed']
    font_path = ROOT/'output/qa/public-online/font-coverage.json'
    assert report(font_path)['passed']
    for path in [SOURCE/'windows-online-content.json', SOURCE/'packages/online-android.json', branding_path, signed_path, font_path]:
        shutil.copy2(path, QA/path.name)
    for name in ['windows','android-debug','android-release']:
        path = SOURCE/'exports'/(name+'.log')
        text = path.read_text(encoding='utf-8')
        assert not any(term in text for term in ['ERROR:', 'FAILURE:', 'What went wrong:']), name
    # Check the unchanged authority contract against the existing public service.
    bootstrap = requests.get('https://jyqx-server.sidcloud.cn/v1/bootstrap', timeout=25)
    bootstrap.raise_for_status()
    authority = bootstrap.json()
    manifest = json.loads((ROOT/'godot/assets/data/online-manifest.json').read_text(encoding='utf-8'))
    assert authority['ok'] and all(authority[key] == manifest[key] for key in ['protocol_version','simulation_hash','ruleset_id'])
    (QA/'authority-compatibility.json').write_text(json.dumps({'passed':True,'protocol_version':manifest['protocol_version'],'simulation_hash':manifest['simulation_hash'],'ruleset_id':manifest['ruleset_id'],'server_release':'0.8.1','client_release':VERSION},indent=2)+'\n',encoding='utf-8')
    policy_checks = []
    for route, local in [('/', 'index.html'),('/privacy','index.html'),('/privacy-policy','index.html'),('/privacy-policy.md','privacy-policy.md'),('/privacy-policy.docx','privacy-policy.docx'),('/styles.css','styles.css')]:
        response = requests.get('https://jyqx.sidcloud.cn'+route,timeout=25)
        same = response.status_code == 200 and response.content == (ROOT/'web/privacy-policy'/local).read_bytes()
        policy_checks.append({'name':route+' matches the current reviewed policy','passed':same})
    assert all(row['passed'] for row in policy_checks)
    (QA/'privacy-live.json').write_text(json.dumps({'checks':policy_checks,'failures':[],'version':'ER-PRIVACY-2026-10-11-AUTOCONNECT','docx_pages_reviewed':15},indent=2)+'\n',encoding='utf-8')
    signed_packages = {row['file']:row for row in signed['packages']}
    checked_packages = {'Epoch-Rush-Godot-'+row['platform']+'.apk':row for row in android['packages']}
    sources = [ROOT/'godot/build/windows/Epoch-Rush-Godot.exe',ROOT/'godot/build/windows/Epoch-Rush-Godot-Windows.zip',ROOT/'godot/build/android/Epoch-Rush-Godot-debug.apk',ROOT/'godot/build/android/Epoch-Rush-Godot-release.apk']
    receipt = {'version':VERSION,'android_version_code':CODE,'server_release':'0.8.1','artifacts':[]}
    for path in sources:
        sha = digest(path)
        if path.suffix == '.apk':
            assert sha == signed_packages[path.name]['sha256'] == checked_packages[path.name]['sha256']
        if path.suffix == '.zip':
            with zipfile.ZipFile(path) as archive:
                assert archive.testzip() is None
                assert hashlib.sha256(archive.read('Epoch-Rush-Godot.exe')).hexdigest() == digest(sources[0])
        shutil.copy2(path, DEST/path.name)
        assert digest(DEST/path.name) == sha
        receipt['artifacts'].append({'name':path.name,'bytes':path.stat().st_size,'sha256':sha})
    encoded = json.dumps(receipt,indent=2)+'\n'
    (DEST/'release-artifacts.json').write_text(encoded,encoding='utf-8')
    (QA/'release-artifacts.json').write_text(encoded,encoding='utf-8')
    (DEST/'SHA256SUMS.txt').write_text(''.join(row['sha256']+'  '+row['name']+'\n' for row in receipt['artifacts']),encoding='utf-8')
    media = ROOT/'docs/media'/('v'+VERSION)
    media.mkdir(parents=True,exist_ok=True)
    captures = []
    for name in ['hall','room','battle','result']:
        source = SOURCE/('native-online-'+name+'.png')
        target = media/('online-'+name+'.png')
        shutil.copy2(source,target)
        captures.append({'file':target.relative_to(ROOT).as_posix(),'sha256':digest(target),'source':'Final exported Windows resource pack; real public two-player match'})
    for name in ['hall','room','room-waiting','offer','queue','retrying']:
        source = SOURCE/('lobby-'+name+'.png')
        target = media/('layout-'+name+'.png')
        shutil.copy2(source,target)
        captures.append({'file':target.relative_to(ROOT).as_posix(),'sha256':digest(target),'source':'Final exported Windows resource pack; explicit UI-state fixture'})
    (QA/'media-provenance.json').write_text(json.dumps({'version':VERSION,'windows_executable_sha256':receipt['artifacts'][0]['sha256'],'captures':captures},indent=2)+'\n',encoding='utf-8')
    print('Four verified client packages and SHA256SUMS ready:',DEST)


if __name__ == '__main__': main()
