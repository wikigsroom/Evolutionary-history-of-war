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
    version=re.search(r'config/version="([^"]+)"',(PROJECT/"project.godot").read_text(encoding="utf-8")).group(1)
    version_code=re.search(r'^version/code=(\d+)',(PROJECT/"export_presets.example.cfg").read_text(encoding="utf-8"),re.MULTILINE).group(1)
    sdk=pathlib.Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or pathlib.Path.home()/"AppData/Local/Android/Sdk")
    aapt=sdk/"build-tools/35.0.0/aapt.exe"
    expected=(PROJECT/"assets/data/online-manifest.json").read_bytes()
    windows=json.loads((ROOT/"output/qa/online/windows-online-content.json").read_text(encoding="utf-8"))
    assert windows["passed"] and windows["version"]==version,"Current Windows pack contract"
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
            def matches_windows(resource):
                return hashlib.sha256(archive.read("assets/"+resource)).hexdigest()==windows["files"][resource]
            dex=b"".join(archive.read(name) for name in archive.namelist() if name.endswith(".dex"))
            elf=archive.read("lib/arm64-v8a/libgodot_android.so")
            phoff=struct.unpack_from("<Q",elf,32)[0];size,count=struct.unpack_from("<HH",elf,54)
            aligns=[struct.unpack_from("<Q",elf,phoff+i*size+48)[0] for i in range(count) if struct.unpack_from("<I",elf,phoff+i*size)[0]==1]
            checks={
                "identity_version":f"name='studio.epochrush.pixelcommand' versionCode='{version_code}' versionName='{version}'" in badge,
                "only_internet_permission":permissions==["android.permission.INTERNET"],
                "backup_disabled":bool(re.search(r'allowBackup[^\n]*0x0',tree)),
                "keystore_plugin_registered":"org.godotengine.plugin.v2.EpochSecureStore" in tree and "studio.epochrush.security.EpochSecureStore" in tree,
                "keystore_plugin_methods_in_dex":all(value in dex for value in [b"EpochSecureStore",b"readSecret",b"writeSecret",b"AndroidKeyStore",b"AES/GCM/NoPadding"]),
                "simulation_manifest_matches":packed==expected,
                "online_client_matches_verified_windows":matches_windows("scripts/net/net_client.gdc"),
                "connect_menu_matches_verified_windows":matches_windows("scripts/ui/online_menu.gdc"),
                "font_data_matches_verified_windows":all(matches_windows(name) for name in windows["files"] if name.endswith(".fontdata")),
                "windows_identity_helper_in_pack":"assets/scripts/net/credential_helper.ps1" in archive.namelist(),
                "native_16kb_load_segments":bool(aligns) and min(aligns)>=16384,
                "no_private_configuration":not any(value in name.lower() for name in archive.namelist() for value in [".keystore","export_presets.cfg","local.credentials","database-credential","pgdata/"]),
            }
            if not all(checks.values()):raise AssertionError(kind+": "+str([key for key,value in checks.items() if not value]))
        rows.append({"platform":kind,"bytes":path.stat().st_size,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"permissions":permissions,"checks":checks})
    output=ROOT/"output/qa/online/packages/online-android.json"
    output.write_text(json.dumps({"passed":True,"version":version,"packages":rows,"physical_device_playtested":False},indent=2),encoding="utf-8")
    print("ONLINE ANDROID:",sum(len(row["checks"]) for row in rows),"checks passed; physical device pending")


if __name__=="__main__":main()
