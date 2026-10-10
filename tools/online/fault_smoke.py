"""Crash only this workspace's native referee/gateway/database and prove recovery."""
import hashlib
import json
import os
import pathlib
import re
import subprocess
import time
import requests
from integration_smoke import Player, Peer, pump, check, checks, ROOT

URL = "http://127.0.0.1:28187"
FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def native(args):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True, creationflags=FLAGS, stdout=subprocess.DEVNULL)


def new_match():
    import secrets
    a, b = Player(URL), Player(URL)
    code = str(secrets.randbelow(1000000)).zfill(6)
    a.change("POST", "/v1/rooms/by-code", {"code":code,"loadout":a.loadout})
    room = b.change("POST", "/v1/rooms/by-code", {"code":code,"loadout":b.loadout})["activity"]["room"]
    for p in [a,b]: p.change("POST", f"/v1/rooms/{room['id']}/ready", {"ready":True,"expected_revision":room["revision"]})
    match = a.activity()["id"]
    peers = [Peer(a,match),Peer(b,match)]
    pump(peers, lambda:all(p.resume and p.current and p.current["connection"]["phase"]=="RUNNING" for p in peers))
    return a,b,match,peers


def command(peer, seq, action):
    peer.send("command", {"client_seq":seq,"last_seen_tick":peer.current["tick"],"action":action})


def main():
    a,b,match,peers = new_match()
    p,q=peers
    command(p,1,{"type":"train","unitId":"U11"})
    pump(peers,lambda:p.results.get(1,{}).get("status")=="APPLIED")
    acknowledged_tick=p.results[1]["applied_tick"]
    before_tick=p.current["tick"]
    check(bool(re.fullmatch("[a-f0-9]{32}",match)),"Fault fixture has a verified match identity")
    script = f"$p=Get-CimInstance Win32_Process | Where-Object {{$_.Name -like 'Godot*' -and $_.Name -notlike '*console*' -and $_.CommandLine -like '*res://server/server_main.gd*' -and $_.CommandLine -like '*--epoch-match={match}*'}}; if(@($p).Count -ne 1){{exit 2}}; $p | ForEach-Object {{Stop-Process -Id $_.ProcessId}}"
    native(["powershell.exe","-NoProfile","-NonInteractive","-WindowStyle","Hidden","-Command",script])
    pump(peers,lambda:p.current["tick"]>=before_tick+60,20)
    check(p.current["tick"]>=before_tick,"Killed referee restores a monotonic committed tick")
    command(p,1,{"type":"train","unitId":"U11"})
    pump(peers,lambda:p.results.get(1,{}).get("applied_tick")==acknowledged_tick)
    check(p.results[1]["applied_tick"]==acknowledged_tick,"Referee crash preserves the original acknowledged command result")
    native([os.sys.executable,"-u","-X","utf8","tools/online/start_local.py","--restart","--no-build"])
    for peer in peers:
        try:peer.close()
        except Exception:pass
    peers=[Peer(a,match),Peer(b,match)];p,q=peers
    pump(peers,lambda:all(x.resume and x.current and not x.current["connection"]["paused"] for x in peers),20)
    check(p.current["tick"]>=before_tick and p.resume["next_client_seq"]==2,"Gateway hard restart restores the same battle and durable cursor")
    check(p.resume["results"][0]["applied_tick"]==acknowledged_tick,"Gateway crash cannot roll back a published command ACK")
    # Stop the isolated, path-verified native development cluster. No shared DB is touched.
    native_root=pathlib.Path(os.environ["LOCALAPPDATA"])/"EpochRushOnline"/hashlib.sha256(str(ROOT).encode()).hexdigest()[:12]
    pg=native_root/"pgsql/bin/pg_ctl.exe";data=native_root/"pgdata"
    check(data.resolve().is_relative_to(native_root.resolve()),"Crash target stays within this workspace's isolated PostgreSQL cluster")
    native([pg,"-D",data,"stop","-m","immediate","-w"])
    time.sleep(3)
    config=json.loads((ROOT/"output/online-local/local.credentials.json").read_text(encoding="utf-8"))
    native([pg,"-D",data,"-l",ROOT/"output/online-local/postgres.log","-o",f"-p {config['db_port']} -h 127.0.0.1","start","-w"])
    until=time.monotonic()+15
    while time.monotonic()<until:
        try:
            if requests.get(URL+"/healthz",timeout=1).status_code==200:break
        except requests.RequestException:pass
        time.sleep(.25)
    for peer in peers:
        try:peer.close()
        except Exception:pass
    peers=[Peer(a,match),Peer(b,match)];p,q=peers
    pump(peers,lambda:all(x.resume and x.current and not x.current["connection"]["paused"] for x in peers),25)
    check(p.resume["next_client_seq"]==2 and p.resume["results"][0]["applied_tick"]==acknowledged_tick,"PostgreSQL immediate crash preserves committed battle and command ACK")
    a.change("POST",f"/v1/matches/{match}/surrender",{"confirm":True})
    pump(peers,lambda:all(hasattr(x,"final") for x in peers))
    check(p.final["result_id"]==q.final["result_id"],"Recovery produces one final result for both subscribers")
    for peer in peers:peer.close()
    for player in [a,b]:player.change("POST",f"/v1/matches/{match}/ack-result")
    # A lost, unsent seq must be tombstoned, never replayed into a stale world.
    a,b,match,peers=new_match();p,q=peers
    p.close();p=Peer(a,match)
    p.pending_sequences=[1]
    # The integration peer defaults to no pending; set it before the first state.
    peers=[p,q]
    pump(peers,lambda:p.resume and q.current and not q.current["connection"]["paused"])
    check(p.resume["next_client_seq"]==2 and p.resume["results"][0]["status"]=="CANCELLED_NOT_EXECUTED","An unsent old click is abandoned durably on resume")
    check(len(p.current["own"]["queue"])==0,"Abandoned old click never recruits after reconnect")
    a.change("POST",f"/v1/matches/{match}/surrender",{"confirm":True})
    pump(peers,lambda:all(hasattr(x,"final") for x in peers))
    for peer in peers:peer.close()
    for player in [a,b]:player.change("POST",f"/v1/matches/{match}/ack-result")


if __name__=="__main__":
    failure=None;started=time.monotonic()
    try:main()
    except Exception as exc:failure=type(exc).__name__+": "+str(exc)
    report=ROOT/"output/qa/online/native-faults.json"
    report.write_text(json.dumps({"checks":checks,"failed":failure,"seconds":time.monotonic()-started},indent=2),encoding="utf-8")
    print(f"NATIVE FAULTS: {len(checks)} checks, {'FAILED: '+failure if failure else 'all passed'}")
    raise SystemExit(1 if failure else 0)
