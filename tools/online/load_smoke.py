"""Measure a target host's capacity gate with real subscribed players."""
import argparse
import concurrent.futures
import json
import secrets
import statistics
import time
from integration_smoke import Player,Peer,pump,check,checks,ROOT


def prepare_pair(url):
    a,b=Player(url),Player(url)
    code=str(secrets.randbelow(1000000)).zfill(6)
    a.change("POST","/v1/rooms/by-code",{"code":code,"loadout":a.loadout})
    room=b.change("POST","/v1/rooms/by-code",{"code":code,"loadout":b.loadout})["activity"]["room"]
    for player in [a,b]:player.change("POST",f"/v1/rooms/{room['id']}/ready",{"ready":True,"expected_revision":room["revision"]})
    match=a.activity()["id"]
    peers=[Peer(a,match),Peer(b,match)]
    # Over a public network, serially creating every other pair can consume the
    # first match's 30-second loading deadline before it receives resume_ready.
    # Complete each real client's loading handshake as soon as it subscribes.
    pump(peers,lambda:all(p.resume and p.current and p.current["connection"]["phase"]=="RUNNING" for p in peers),30)
    return (a,b,match),peers


def main(url,matches,seconds):
    with concurrent.futures.ThreadPoolExecutor(max_workers=matches) as pool:
        prepared=list(pool.map(prepare_pair,[url]*matches))
    pairs=[pair for pair,subscribers in prepared]
    peers=[peer for pair,subscribers in prepared for peer in subscribers]
    pump(peers,lambda:all(p.resume and p.current and p.current["connection"]["phase"]=="RUNNING" for p in peers),30)
    check(len(peers)==matches*2,"All real subscribers finish loading at capacity")
    start=time.monotonic();initial=[p.current["tick"] for p in peers]
    sent=time.monotonic();latencies={}
    for peer in peers:
        peer.send("command",{"client_seq":1,"last_seen_tick":peer.current["tick"],"action":{"type":"train","unitId":"U11"}})
    while time.monotonic()-start<seconds:
        for i,peer in enumerate(peers):
            peer.poll(0.001)
            if i not in latencies and peer.results.get(1,{}).get("status")=="APPLIED":latencies[i]=(time.monotonic()-sent)*1000
    elapsed=time.monotonic()-start
    rates=[(p.current["tick"]-initial[i])/elapsed for i,p in enumerate(peers)]
    check(len(latencies)==matches*2 and all(p.results[1]["ok"] for p in peers),"Every player receives a committed recruitment ACK")
    check(min(rates)>=28.5,"Every match sustains at least 28.5 simulation ticks per second")
    with concurrent.futures.ThreadPoolExecutor(max_workers=matches) as pool:
        futures=[pool.submit(a.change,"POST",f"/v1/matches/{match}/surrender",{"confirm":True}) for a,b,match in pairs]
        pump(peers,lambda:all(f.done() for f in futures),15)
        for future in futures:future.result()
    pump(peers,lambda:all(hasattr(p,"final") for p in peers),15)
    check(all(peers[i*2].final["result_id"]==peers[i*2+1].final["result_id"] for i in range(matches)),"Every capacity match produces one shared final result")
    for peer in peers:peer.close()
    for a,b,match in pairs:
        for player in [a,b]:player.change("POST",f"/v1/matches/{match}/ack-result")
    ordered=sorted(latencies.values())
    return {"endpoint":url,"matches":matches,"subscribers":matches*2,"seconds":elapsed,"simulation_hz_min":min(rates),"simulation_hz_mean":statistics.mean(rates),"command_ack_ms_p95":ordered[max(0,int(len(ordered)*.95)-1)],"command_ack_ms_max":max(ordered),"scope":"Public Singapore host, real HTTPS/WSS subscribers from the test workstation" if url.startswith("https://jyqx-server.sidcloud.cn") else "Native self-hosted endpoint; capacity evidence applies only to the tested machine"}


if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--url",default="http://127.0.0.1:28187");parser.add_argument("--matches",type=int,default=10);parser.add_argument("--seconds",type=float,default=30)
    args=parser.parse_args();failure=None;measurements={}
    try:measurements=main(args.url,args.matches,args.seconds)
    except Exception as exc:failure=type(exc).__name__+": "+str(exc)
    report=ROOT/"output/qa/online/native-load.json"
    report.write_text(json.dumps({"checks":checks,"failed":failure,"measurements":measurements},indent=2),encoding="utf-8")
    print(json.dumps({"checks":len(checks),"failed":failure,"measurements":measurements}))
    raise SystemExit(1 if failure else 0)
