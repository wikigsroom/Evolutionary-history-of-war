"""Regression for old guest identities and queues lasting over one minute."""
import argparse
import json
import time
from integration_smoke import ROOT, Player, Peer, check, checks, pump


def wait_with_heartbeat(player, seconds):
    deadline = time.monotonic() + seconds
    latest = None
    while time.monotonic() < deadline:
        latest = player.activity()
        if latest["kind"] != "queue":
            raise AssertionError("A live waiting player left the queue")
        time.sleep(min(2, max(0, deadline - time.monotonic())))
    return latest


def main(url):
    first = Player(url)
    # This is deliberately a stale authentication timestamp. Do not heartbeat
    # before enqueueing: it would hide the original queue admission defect.
    time.sleep(65)
    entered = first.change("POST", "/v1/matchmaking/tickets", {"loadout": first.loadout})
    check(entered["activity"]["kind"] == "queue", "An identity authenticated over 60 seconds ago can enter matchmaking")
    time.sleep(3)
    check(first.activity()["kind"] == "queue", "Queue admission refreshes the old identity before maintenance expires it")
    waiting = wait_with_heartbeat(first, 65)
    check(waiting["kind"] == "queue", "Polling keeps a real player queued for more than 60 seconds")
    second = Player(url)
    second.change("POST", "/v1/matchmaking/tickets", {"loadout": second.loadout})
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        a, b = first.activity(), second.activity()
        if a["kind"] == "room" and b["kind"] == "room":
            break
        time.sleep(.25)
    check(a["kind"] == b["kind"] == "room" and a["id"] == b["id"] and a["room"]["phase"] == "OFFER", "The long-waiting player receives the arriving real opponent's offer")
    for player in (first, second):
        player.change("POST", f"/v1/match-offers/{a['id']}/decision", {"accept": True, "offer_revision": a["room"]["revision"]})
    match = first.activity()
    check(match["kind"] == "match" and second.activity()["id"] == match["id"], "Both accepted offers start one authoritative battle")
    peers = [Peer(first, match["id"]), Peer(second, match["id"])]
    try:
        pump(peers, lambda: all(p.resume and p.current and p.current["connection"]["phase"] == "RUNNING" for p in peers), 30)
        check(all(p.current["connection"]["phase"] == "RUNNING" for p in peers), "Both long-queue subscribers load and run the battle")
        first.change("POST", f"/v1/matches/{match['id']}/surrender", {"confirm": True})
        pump(peers, lambda: all(hasattr(p, "final") for p in peers), 20)
        check(peers[0].final["result_id"] == peers[1].final["result_id"], "Accepted matchmaking ends with one shared result")
    finally:
        for peer in peers:
            peer.close()
    for player in (first, second):
        player.change("POST", f"/v1/matches/{match['id']}/ack-result")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="https://jyqx-server.sidcloud.cn")
    args = parser.parse_args()
    failure = None
    started = time.monotonic()
    try:
        main(args.url)
    except Exception as error:
        failure = type(error).__name__ + ": " + str(error)
    destination = ROOT / "output/qa/public-online/queue-liveness.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps({"endpoint": args.url, "checks": checks, "failed": failure, "seconds": time.monotonic() - started}, indent=2), encoding="utf-8")
    print("QUEUE LIVENESS:", len(checks), "checks;", failure or "all passed")
    raise SystemExit(1 if failure else 0)
