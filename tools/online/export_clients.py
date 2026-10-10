"""Native exports with bounded logs; never echo local signing credentials."""
import argparse
import pathlib
import re
import subprocess
import time

ROOT=pathlib.Path(__file__).resolve().parents[2]
PROJECT=ROOT/"godot"
FLAGS=getattr(subprocess,"CREATE_NO_WINDOW",0)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--platform",choices=["windows","android-debug","android-release"],required=True)
    args=parser.parse_args()
    choices={"windows":("--export-release","Windows Desktop","build/windows/Epoch-Rush-Godot.exe"),"android-debug":("--export-debug","Android","build/android/Epoch-Rush-Godot-debug.apk"),"android-release":("--export-release","Android","build/android/Epoch-Rush-Godot-release.apk")}
    command,preset,target=choices[args.platform]
    (PROJECT/target).parent.mkdir(parents=True,exist_ok=True)
    # Read for redaction only. Signing configuration is never printed or copied.
    private=(PROJECT/"export_presets.cfg").read_text(encoding="utf-8")
    redactions=[]
    for key,value in re.findall(r'^([^=\n]+)="([^"\n]+)"',private,re.MULTILINE):
        if key.endswith(("_password","_user")) or key.startswith("keystore/"):redactions.append(value)
    # Use the real engine executable: the Windows console wrapper can wait on an
    # inherited Gradle daemon pipe after the engine itself has exited.
    log=ROOT/"output/qa/online/exports";log.mkdir(parents=True,exist_ok=True)
    raw=log/(args.platform+".raw.tmp")
    with raw.open("wb") as stream:
        proc=subprocess.Popen([str(PROJECT/"toolchain/editor/Godot_v4.7.2-stable_win64.exe"),"--headless","--path",str(PROJECT),command,preset,target],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,creationflags=FLAGS)
        try: proc.wait(timeout=600)
        except subprocess.TimeoutExpired:
            proc.kill();proc.wait();print("Native export timed out:",args.platform)
    output=raw.read_bytes();raw.unlink()
    text=output.decode("utf-8",errors="replace")
    for value in redactions:text=text.replace(value,"[local signing value]")
    text=re.sub(r'(export_keystore_[^=\s]*=)[^\s]+',r'\1[redacted]',text)
    (log/(args.platform+".log")).write_text(text,encoding="utf-8")
    errors=[line for line in text.splitlines() if any(term in line for term in ["ERROR:","FAILURE:","What went wrong:","> Failed","> Could not","> Cannot","BUILD FAILED"])]
    artifact=PROJECT/target
    if proc.returncode or errors or not artifact.exists():
        print("Native export failed:",args.platform)
        print("\n".join(errors[-12:]))
        print("Sanitized log:",log/(args.platform+".log"))
        raise SystemExit(1)
    print("Native export ready:",args.platform,artifact.stat().st_size,"bytes")


if __name__=="__main__":main()
