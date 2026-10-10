"""Verify shipped Android networking/privacy boundaries and matching simulation data."""
import hashlib
import json
import os
import pathlib
import re
import struct
import subprocess
import zipfile

ROOT=pathlib.Path(__file__).resolve().parents[2]
PROJECT=ROOT/"godot"


def main():
    sdk=pathlib.Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or pathlib.Path.home()/"AppData/Local/Android/Sdk")
    aapt=sdk/"build-tools/35.0.0/aapt.exe"
    expected=(PROJECT/"assets/data/online-manifest.json").read_bytes()
    rows=[]
    for kind in ["debug","release"]:
        path=PROJECT/"build/android"/f"Epoch-Rush-Godot-{kind}.apk"
        def dump(*options):
            return subprocess.run([str(aapt),"dump",*options,path.name],cwd=path.parent,capture_output=True,check=True).stdout.decode("utf-8",errors="replace")
        badge=dump("badging")
        # aapt's xmltree argument follows the APK name.
        tree=subprocess.run([str(aapt),"dump","xmltree",path.name,"AndroidManifest.xml"],cwd=path.parent,capture_output=True,check=True).stdout.decode("utf-8",errors="replace")
        permissions=re.findall(r"uses-permission: name='([^']+)'",badge)
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None,"APK CRC"
            packed=archive.read("assets/assets/data/online-manifest.json")
            dex=b"".join(archive.read(name) for name in archive.namelist() if name.endswith(".dex"))
            elf=archive.read("lib/arm64-v8a/libgodot_android.so")
            phoff=struct.unpack_from("<Q",elf,32)[0];size,count=struct.unpack_from("<HH",elf,54)
            aligns=[struct.unpack_from("<Q",elf,phoff+i*size+48)[0] for i in range(count) if struct.unpack_from("<I",elf,phoff+i*size)[0]==1]
            checks={
                "identity_version":"name='studio.epochrush.pixelcommand' versionCode='13' versionName='0.8.0'" in badge,
                "only_internet_permission":permissions==["android.permission.INTERNET"],
                "backup_disabled":bool(re.search(r'allowBackup[^\n]*0x0',tree)),
                "keystore_plugin_registered":"org.godotengine.plugin.v2.EpochSecureStore" in tree and "studio.epochrush.security.EpochSecureStore" in tree,
                "keystore_plugin_methods_in_dex":all(value in dex for value in [b"EpochSecureStore",b"readSecret",b"writeSecret",b"AndroidKeyStore",b"AES/GCM/NoPadding"]),
                "simulation_manifest_matches":packed==expected,
                "windows_identity_helper_in_pack":"assets/scripts/net/credential_helper.ps1" in archive.namelist(),
                "native_16kb_load_segments":bool(aligns) and min(aligns)>=16384,
                "no_private_configuration":not any(value in name.lower() for name in archive.namelist() for value in [".keystore","export_presets.cfg","local.credentials","database-credential","pgdata/"]),
            }
            if not all(checks.values()):raise AssertionError(kind+": "+str([key for key,value in checks.items() if not value]))
        rows.append({"platform":kind,"bytes":path.stat().st_size,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"permissions":permissions,"checks":checks})
    output=ROOT/"output/qa/online/packages/online-android.json"
    output.write_text(json.dumps({"passed":True,"version":"0.8.0","packages":rows,"physical_device_playtested":False},indent=2),encoding="utf-8")
    print("ONLINE ANDROID:",sum(len(row["checks"]) for row in rows),"checks passed; physical device pending")


if __name__=="__main__":main()
