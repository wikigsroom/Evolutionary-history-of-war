"""Build a self-contained native Windows authority with no UI textures or audio."""
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import zipfile

ROOT=pathlib.Path(__file__).resolve().parents[2]
PROJECT=ROOT/"godot"
VERSION=re.search(r'config/version="([^"]+)"',(PROJECT/"project.godot").read_text(encoding="utf-8")).group(1)
TARGET=ROOT/"output/releases"/f"v{VERSION}"/"server"
FLAGS=getattr(subprocess,"CREATE_NO_WINDOW",0)


def copy(source,destination):
    destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,destination)


def main():
    TARGET.mkdir(parents=True,exist_ok=True)
    bundle=TARGET/"Epoch-Rush-Server";bundle.mkdir(exist_ok=True)
    (bundle/"bin").mkdir(exist_ok=True)
    subprocess.run([str(ROOT/".local-tools/online/go/bin/go.exe"),"build","-trimpath","-o",str(bundle/"bin/epoch-online.exe"),"."],cwd=ROOT/"services/online-gateway",check=True,creationflags=FLAGS)
    copy(PROJECT/"toolchain/editor/Godot_v4.7.2-stable_win64.exe",bundle/"engine/Godot.exe")
    for script in (ROOT/"services/online-gateway/deploy").iterdir():
        if script.is_file():copy(script,bundle/script.name)
    (bundle/"README.md").write_text((ROOT/"services/online-gateway/README.md").read_text(encoding="utf-8").replace("deploy/linux/README.md","docs/linux/README.md"),encoding="utf-8",newline="\n")
    copy(ROOT/"services/online-gateway/deploy/linux/README.md",bundle/"docs/linux/README.md")
    referee=bundle/"referee"
    core=["game_model.gd","game_data.gd","epoch_combat.gd","epoch_skills.gd","epoch_environment.gd","epoch_snapshot_migration.gd"]
    for name in core:
        copy(PROJECT/"scripts"/name,referee/"scripts"/name)
        uid=PROJECT/"scripts"/(name+".uid")
        if uid.exists():copy(uid,referee/"scripts"/uid.name)
    for path in (PROJECT/"server").glob("*.gd"):copy(path,referee/"server"/path.name)
    for path in (PROJECT/"assets/data").glob("*.json"):copy(path,referee/"assets/data"/path.name)
    (referee/"project.godot").write_text('config_version=5\n[application]\nconfig/name="Epoch Rush Authority"\nconfig/features=PackedStringArray("4.7", "GL Compatibility")\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding="utf-8")
    pgsource=ROOT/".local-tools/online/pgsql"
    pgdest=(bundle/"pgsql").resolve()
    if not pgdest.is_relative_to(TARGET.resolve()):raise RuntimeError("Server staging directory escapes workspace release path")
    if pgdest.exists():shutil.rmtree(pgdest)
    required=["postgres.exe","initdb.exe","pg_ctl.exe","icudt77.dll","icuin77.dll","icuuc77.dll","libcrypto-3-x64.dll","libiconv-2.dll","libintl-9.dll","liblz4.dll","libpq.dll","libssl-3-x64.dll","libwinpthread-1.dll","libxml2.dll","libzstd.dll","zlib1.dll"]
    for name in required:copy(pgsource/"bin"/name,pgdest/"bin"/name)
    for path in (pgsource/"lib").glob("*.dll"):
        if path.name in ["plpgsql.dll","pgoutput.dll","dict_snowball.dll"] or "_and_" in path.name or path.name.startswith(("utf8_","latin2_")):
            copy(path,pgdest/"lib"/path.name)
    shutil.copytree(pgsource/"share",pgdest/"share",dirs_exist_ok=True)
    notices=bundle/"licenses";notices.mkdir(exist_ok=True)
    for name in ["Godot-LICENSE.txt","Godot-third-party-notices.txt"]:copy(PROJECT/"docs/distribution"/name,notices/name)
    copy(ROOT/".local-tools/online/go/LICENSE",notices/"Go-LICENSE.txt")
    copy(ROOT/"services/online-gateway/THIRD-PARTY.txt",notices/"Gateway-THIRD-PARTY.txt")
    shutil.copytree(ROOT/"services/online-gateway/licenses",notices,dirs_exist_ok=True)
    manifest={}
    for path in sorted(bundle.rglob("*")):
        if path.is_file() and ".godot" not in path.parts and path.name != "BUNDLE-MANIFEST.json":
            manifest[path.relative_to(bundle).as_posix()]={"bytes":path.stat().st_size,"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}
    (bundle/"BUNDLE-MANIFEST.json").write_text(json.dumps({"version":VERSION,"simulation_hash":json.loads((PROJECT/"assets/data/online-manifest.json").read_text(encoding="utf-8"))["simulation_hash"],"files":manifest},indent=2),encoding="utf-8")
    archive=TARGET/f"Epoch-Rush-Server-{VERSION}-Windows-x64.zip"
    with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as zipped:
        for path in sorted(bundle.rglob("*")):
            if path.is_file() and ".godot" not in path.parts:zipped.write(path,"Epoch-Rush-Server/"+path.relative_to(bundle).as_posix())
    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip():raise RuntimeError("Server ZIP is corrupt")
        forbidden=[p for p in zipped.namelist() if any(x in p.lower() for x in ["credential.xml","local.credentials","pgdata/","export_presets.cfg",".keystore"])]
        if forbidden:raise RuntimeError("Private runtime data entered the server ZIP")
    digest=hashlib.sha256(archive.read_bytes()).hexdigest()
    (TARGET/"server-package.json").write_text(json.dumps({"version":VERSION,"archive":str(archive.relative_to(ROOT)),"bytes":archive.stat().st_size,"sha256":digest,"files":len(manifest),"native":True,"requires_docker_wsl_vm":False},indent=2),encoding="utf-8")
    print("Native server bundle ready:",archive,archive.stat().st_size,"bytes")


if __name__=="__main__":main()
