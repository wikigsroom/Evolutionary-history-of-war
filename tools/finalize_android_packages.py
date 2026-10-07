"""Fix the prebuilt template's missing adaptive-icon alias, align and re-sign locally."""
import configparser
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'godot/build/android'

def resolve_toolchain():
    """Allow a fresh native checkout to use its own SDK and JDK installations."""
    local_app_data=Path(os.environ.get('LOCALAPPDATA',Path.home()/'AppData/Local'))
    sdk_root=Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME') or local_app_data/'Android/Sdk')
    explicit_tools=os.environ.get('EPOCH_RUSH_ANDROID_BUILD_TOOLS')
    if explicit_tools:
        sdk=Path(explicit_tools)
    else:
        sdk=sdk_root/'build-tools/35.0.0'
        if not sdk.is_dir():
            candidates=[p for p in (sdk_root/'build-tools').glob('*') if p.is_dir()]
            candidates.sort(key=lambda p:tuple(int(n) for n in re.findall(r'\d+',p.name)))
            if candidates:sdk=candidates[-1]
    java_option=os.environ.get('EPOCH_RUSH_JAVA')
    java_name='java.exe' if os.name=='nt' else 'java'
    if java_option:
        java=Path(java_option)
    elif os.environ.get('JAVA_HOME'):
        java=Path(os.environ['JAVA_HOME'])/'bin'/java_name
    else:
        java=Path(shutil.which(java_name) or 'C:/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot/bin/java.exe')
    zipalign=sdk/('zipalign.exe' if os.name=='nt' else 'zipalign')
    for path in [java,zipalign,sdk/'lib/apksigner.jar']:
        if not path.is_file():raise RuntimeError('Android tool unavailable; configure JAVA_HOME / ANDROID_SDK_ROOT: '+str(path))
    return sdk,java,zipalign

def value(raw):return json.loads(raw)

def main():
    sdk,java,zipalign=resolve_toolchain()
    cfg=configparser.ConfigParser(interpolation=None)
    cfg.read(ROOT/'godot/export_presets.cfg',encoding='utf-8')
    options=cfg['preset.1.options']
    editor={}
    settings_default=Path(os.environ.get('APPDATA',Path.home()/'AppData/Roaming'))/'Godot/editor_settings-4.7.tres'
    settings_path=Path(os.environ.get('EPOCH_RUSH_GODOT_EDITOR_SETTINGS',str(settings_default)))
    for line in settings_path.read_text(encoding='utf-8').splitlines():
        if line.startswith(('export/android/debug_keystore =','export/android/debug_keystore_pass =')):
            key,raw=line.split('=',1);editor[key.strip()]=value(raw.strip())
    reports=[]
    for kind in ['release','debug']:
        package=BUILD/f'Epoch-Rush-Godot-{kind}.apk'
        key=value(options.get(f'keystore/{kind}','""'))
        alias=value(options.get(f'keystore/{kind}_user','""'))
        password=value(options.get(f'keystore/{kind}_password','""'))
        if kind=='debug':
            key=key or editor['export/android/debug_keystore']
            alias=alias or 'androiddebugkey'
            password=password or editor['export/android/debug_keystore_pass']
        key_path=Path(key.removeprefix('res://'))
        if not key_path.is_absolute():key_path=ROOT/'godot'/key_path
        key=str(key_path.resolve())
        if not key or not alias or not password or not Path(key).is_file():
            raise RuntimeError('Configured signing identity unavailable: '+kind)
        with tempfile.TemporaryDirectory(prefix='icon-compat-',dir=BUILD) as directory:
            stage=Path(directory).resolve()
            if not stage.is_relative_to(BUILD.resolve()):raise RuntimeError('Invalid staging directory')
            unsigned=stage/'unsigned.apk';aligned=stage/'aligned.apk'
            with zipfile.ZipFile(package) as original,zipfile.ZipFile(unsigned,'w') as corrected:
                for entry in original.infolist():corrected.writestr(copy.copy(entry),original.read(entry.filename))
                alias_path='res/mipmap-anydpi-v26/themed_icon.xml'
                if alias_path not in original.namelist():
                    corrected.writestr(alias_path,original.read('res/mipmap-anydpi-v26/icon.xml'),compress_type=zipfile.ZIP_DEFLATED)
            subprocess.run([str(zipalign),'-P','16','-f','4',str(unsigned),str(aligned)],check=True,capture_output=True)
            signing_env=dict(os.environ);signing_env['EPOCH_RUSH_APK_SIGNING_PASSWORD']=password
            subprocess.run([str(java),'-jar',str(sdk/'lib/apksigner.jar'),'sign','--ks',key,'--ks-key-alias',alias,
                '--ks-pass','env:EPOCH_RUSH_APK_SIGNING_PASSWORD','--key-pass','env:EPOCH_RUSH_APK_SIGNING_PASSWORD',str(aligned)],
                env=signing_env,check=True,capture_output=True)
            subprocess.run([str(java),'-jar',str(sdk/'lib/apksigner.jar'),'verify',str(aligned)],check=True,capture_output=True)
            subprocess.run([str(zipalign),'-c','-P','16','4',str(aligned)],check=True,capture_output=True)
            with zipfile.ZipFile(aligned) as archive:
                if archive.testzip():raise RuntimeError('Corrupt Android archive')
                assert alias_path in archive.namelist()
            os.replace(aligned,package)
        reports.append({'file':package.name,'bytes':package.stat().st_size,'sha256':hashlib.sha256(package.read_bytes()).hexdigest(),
            'adaptiveAliasPresent':True,'signatureVerified':True,'nativePageAlignment':16384})
    out=ROOT/'output/qa/ten-eras/android-finalization.json'
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps({'passed':True,'packages':reports},indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'passed':True,'packages':len(reports),'fixedMissingAdaptiveAlias':True}))

if __name__=='__main__':main()
