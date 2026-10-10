"""Run real native Godot QA with explicit output paths and an error-log gate."""
import argparse
import os
import pathlib
import subprocess

ROOT=pathlib.Path(__file__).resolve().parents[2]
PROJECT=ROOT/"godot"


def main():
    parser=argparse.ArgumentParser();parser.add_argument("--script",required=True);parser.add_argument("--pack",action="store_true");parser.add_argument("--headless",action="store_true")
    args=parser.parse_args()
    name=pathlib.Path(args.script).stem+("-embedded" if args.pack else "-source")
    output=ROOT/"output/qa/online";output.mkdir(parents=True,exist_ok=True)
    log=output/(name+".log")
    command=[str(PROJECT/"toolchain/editor/Godot_v4.7.2-stable_win64.exe"),"--path",str(PROJECT)]
    if args.pack:command += ["--main-pack",str(PROJECT/"build/windows/Epoch-Rush-Godot.exe")]
    if args.headless:command.append("--headless")
    command += ["--script",str(PROJECT/args.script)]
    env=dict(os.environ);env["EPOCH_QA_OUTPUT"]=str(output)
    with log.open("wb") as stream:
        process=subprocess.Popen(command,env=env,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0))
        try:process.wait(timeout=140)
        except subprocess.TimeoutExpired:process.kill();process.wait();print("Native QA timeout:",name)
    text=log.read_text(encoding="utf-8",errors="replace")
    errors=[line for line in text.splitlines() if "SCRIPT ERROR:" in line or line.startswith("ERROR:")]
    print("\n".join(text.splitlines()[-8:]))
    print("Native QA",name,"exit",process.returncode,"errors",len(errors),"log",log.relative_to(ROOT))
    if process.returncode or errors:
        print("\n".join(errors[:8]));raise SystemExit(1)


if __name__=="__main__":main()
