"""Exercise the shipped native server, including fresh start, drain and persistence."""
import json
import os
import pathlib
import secrets
import subprocess
import time
import zipfile
import hashlib
import requests
from integration_smoke import ROOT,Player,Peer,pump,check,checks

URL="http://127.0.0.1:28188"
DATA=pathlib.Path(os.environ["LOCALAPPDATA"])/"EpochRushStandaloneQA"
STAGE=ROOT/"output/qa/online/server-bundle"
BUNDLE=STAGE/"Epoch-Rush-Server"
FLAGS=getattr(subprocess,"CREATE_NO_WINDOW",0)


def administrative(name,extra=()):
    args=["powershell.exe","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",str(BUNDLE/name),"-DataDirectory",str(DATA),*extra]
    # A Windows background child may retain inherited capture-pipe handles after
    # PowerShell exits. Wait on the real script process and use a disk log instead.
    log=ROOT/"output/qa/online"/("admin-"+name+"-"+str(time.time_ns())+".log")
    with log.open("wb") as stream:
        result=subprocess.run(args,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,timeout=65,creationflags=FLAGS)
    text=log.read_bytes().decode("utf-8",errors="replace")
    if result.returncode:raise RuntimeError("Native bundle administration failed: "+name+" "+text[-1200:])
    print(text.strip(),flush=True)


def start():
    administrative("Start-Server.ps1",["-LocalOnly","-Port","28188","-DatabasePort","54330"])


def main():
    if (DATA/"gateway.pid").exists():administrative("Stop-Server.ps1")
    archive=ROOT/"output/releases/v0.8.0/server/Epoch-Rush-Server-0.8.0-Windows-x64.zip"
    with zipfile.ZipFile(archive) as zipped:
        assert STAGE.resolve().is_relative_to(ROOT.resolve())
        assert all((STAGE/n).resolve().is_relative_to(STAGE.resolve()) for n in zipped.namelist())
        zipped.extractall(STAGE)
    manifest=json.loads((BUNDLE/"BUNDLE-MANIFEST.json").read_text(encoding="utf-8"))
    verified=all(hashlib.sha256((BUNDLE/relative).read_bytes()).hexdigest()==entry["sha256"] for relative,entry in manifest["files"].items())
    check(verified,"Every shipped server file matches the release bundle manifest")
    administrative("Resume-Admissions.ps1");start()
    health=requests.get(URL+"/healthz",timeout=3).json()
    check(health["ok"] and not health["draining"],"Extracted native server starts after a fully stopped database")
    result=subprocess.run(["python","-u","-X","utf8",str(ROOT/"tools/online/integration_smoke.py"),"--url",URL],cwd=ROOT,capture_output=True,timeout=80,creationflags=FLAGS)
    (ROOT/"output/qa/online/server-bundle-network.log").write_bytes(result.stdout+result.stderr)
    check(result.returncode==0,"Shipped gateway and minimal referee pass the 23 real network checks")
    (ROOT/"output/qa/online/server-bundle-integration.json").write_bytes((ROOT/"output/qa/online/network-integration.json").read_bytes())
    a,b=Player(URL),Player(URL);code=str(secrets.randbelow(1000000)).zfill(6)
    a.change("POST","/v1/rooms/by-code",{"code":code,"loadout":a.loadout})
    room=b.change("POST","/v1/rooms/by-code",{"code":code,"loadout":b.loadout})["activity"]["room"]
    for player in [a,b]:player.change("POST",f"/v1/rooms/{room['id']}/ready",{"ready":True,"expected_revision":room["revision"]})
    match=a.activity()["id"];p,q=Peer(a,match),Peer(b,match)
    pump([p,q],lambda:all(peer.resume and peer.current and not peer.current["connection"]["paused"] for peer in [p,q]))
    administrative("Stop-Server.ps1")
    health=requests.get(URL+"/healthz",timeout=3).json()
    check(health["draining"] and health["active_matches"]==1,"Stop script drains admission and retains the running battle")
    stranger=Player(URL)
    denied=stranger.change("POST","/v1/rooms/by-code",{"code":str(secrets.randbelow(1000000)).zfill(6),"loadout":stranger.loadout},True)
    check(denied.get("error")=="MAINTENANCE","New rooms are refused during drain")
    p.send("command",{"client_seq":1,"last_seen_tick":p.current["tick"],"action":{"type":"train","unitId":"U11"}})
    pump([p,q],lambda:p.results.get(1,{}).get("status")=="APPLIED")
    check(p.results[1]["status"]=="APPLIED","An existing battle still applies committed commands while draining")
    a.change("POST",f"/v1/matches/{match}/surrender",{"confirm":True})
    pump([p,q],lambda:hasattr(p,"final") and hasattr(q,"final"))
    check(p.final==q.final,"Draining battle ends with one shared authoritative result")
    for player in [a,b]:player.change("POST",f"/v1/matches/{match}/ack-result")
    p.socket.close();q.socket.close()
    administrative("Resume-Admissions.ps1")
    deadline=time.monotonic()+5
    while requests.get(URL+"/healthz",timeout=2).json()["draining"] and time.monotonic()<deadline:time.sleep(.1)
    check(not requests.get(URL+"/healthz",timeout=2).json()["draining"],"Resume script reopens admission without resetting data")
    administrative("Stop-Server.ps1")
    check((DATA/"pgdata/PG_VERSION").exists() and (DATA/"database-credential.xml").exists(),"Stopping retains the database and protected server credential")
    administrative("Resume-Admissions.ps1");start()
    restored=a.request("GET",f"/v1/matches/{match}/result")
    check(restored["result"]==p.final,"A full native server/database restart retains the finished result")
    administrative("Stop-Server.ps1")
    print("SERVER BUNDLE:",len(checks),"checks passed",flush=True)


if __name__=="__main__":
    failure=None
    try:main()
    except Exception as error:failure=str(error);raise
    finally:
        (ROOT/"output/qa/online/server-bundle.json").write_text(json.dumps({"checks":checks,"failed":failure,"url":URL,"native":True},indent=2),encoding="utf-8")
