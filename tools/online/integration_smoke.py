"""Two real WebSocket subscribers, real PostgreSQL and the native Godot referee."""
import argparse
import base64
import concurrent.futures
import hashlib
import json
import pathlib
import secrets
import time

import requests
from websockets.sync.client import connect

ROOT = pathlib.Path(__file__).resolve().parents[2]
REPORT = ROOT / "output/qa/online/network-integration.json"
checks = []


def check(value, name):
    checks.append({"name": name, "passed": bool(value)})
    if not value:
        raise AssertionError(name)


class Player:
    def __init__(self, url):
        self.url = url
        self.token = ""
        self.bootstrap = self.request("GET", "/v1/bootstrap")
        identity = self.request("POST", "/v1/auth/guest", {"installation_key": secrets.token_hex(32)})
        self.token = identity["access_token"]
        self.id = identity["player_id"]
        db = ROOT / "godot/assets/data"
        heroes = json.loads((db / "heroes.json").read_text(encoding="utf-8"))
        hero = next(h for h in heroes if h["id"] == "H03")
        self.loadout = {"heroId": "H03", "specializationId": hero["specializationIds"][0], "commonSkillIds": hero["defaultCommonSkillIds"], "relicIds": ["I01", "I03"], "talentIds": ["T11", "T12"]}

    def contract(self, body):
        return {"request_id": secrets.token_hex(16), "protocol_version": "1.0", "simulation_hash": self.bootstrap["simulation_hash"], "ruleset_id": "pvp-classic-v1", **body}

    def request(self, method, path, body=None, permit_error=False):
        response = requests.request(method, self.url + path, json=body, headers={"Authorization": "Bearer " + self.token}, timeout=10)
        result = response.json()
        if not permit_error and not result.get("ok"):
            raise RuntimeError(f"{method} {path}: {response.status_code} {result.get('error')}")
        return result

    def change(self, method, path, body=None, permit_error=False):
        return self.request(method, path, self.contract(body or {}), permit_error)

    def activity(self):
        return self.request("GET", "/v1/activities/me")["activity"]


class Peer:
    def __init__(self, player, match):
        self.player = player
        self.match = match
        self.epoch = 0
        self.states = {}
        self.current = None
        self.results = {}
        self.assembly = {}
        self.resume = None
        self.next_ping = 0
        ticket = player.change("POST", "/v1/ws-tickets", {"match_id": match})
        self.socket = connect(player.url.replace("https://", "wss://").replace("http://", "ws://") + "/v1/socket", additional_headers={"Authorization": "Bearer " + ticket["ticket"]}, subprotocols=["epoch-rush.v1"], max_size=1048576, open_timeout=10, close_timeout=0.5)

    def send(self, kind, payload):
        self.socket.send(json.dumps({"v": "1.0", "type": kind, "match_id": self.match, "connection_epoch": self.epoch, "payload": payload}))

    def poll(self, timeout=0.1):
        if hasattr(self, "final"):
            return
        if self.epoch and time.monotonic() >= self.next_ping:
            self.send("ping", {"client_time_ms": int(time.monotonic() * 1000)})
            self.next_ping = time.monotonic() + 1
        try:
            message = json.loads(self.socket.recv(timeout=timeout))
        except TimeoutError:
            return
        self.message(message)

    def message(self, message):
        kind = message["type"]
        p = message.get("payload", {})
        if kind == "hello":
            self.epoch = message["connection_epoch"]
        elif kind == "state_chunk":
            seq = p["snapshot_seq"]
            self.assembly.setdefault(seq, {})[p["index"]] = base64.b64decode(p["data"])
            if len(self.assembly[seq]) == p["count"]:
                raw = b"".join(self.assembly[seq][i] for i in range(p["count"]))
                check(hashlib.sha256(raw).hexdigest() == p["hash"], "Snapshot chunk digest")
                self.assembly.clear()
                self.message(json.loads(raw))
        elif kind in ["state_full", "state_delta"]:
            if kind == "state_delta":
                if p["base_snapshot_seq"] not in self.states:
                    self.send("full_sync", {})
                    return
                p = {**self.states[p["base_snapshot_seq"]], **p["changes"], "snapshot_seq": p["snapshot_seq"]}
            self.current = p
            self.states[p["snapshot_seq"]] = p
            while len(self.states) > 32:
                del self.states[min(self.states)]
            self.send("state_ack", {"snapshot_seq": p["snapshot_seq"]})
            if self.resume is None:
                self.resume = False
                self.send("resume_ready", {"pending_sequences": getattr(self,"pending_sequences",[])})
        elif kind == "resume_ready":
            self.resume = p
        elif kind in ["command_result", "command_receipt"]:
            self.results[p.get("client_seq")] = p
        elif kind == "match_result":
            self.final = p
        elif kind == "error":
            raise RuntimeError("Protocol error: " + str(p.get("error")))

    def close(self):
        self.socket.close()


def pump(peers, predicate, seconds=20):
    start = time.monotonic()
    while time.monotonic() - start < seconds:
        for peer in peers:
            peer.poll(min(0.05,0.5/len(peers)))
        if predicate():
            return
    raise TimeoutError("Expected authoritative state was not reached")


def main(url):
    left, right = Player(url), Player(url)
    code = "0" + str(secrets.randbelow(100000)).zfill(5)
    body = left.contract({"code": code, "loadout": left.loadout})
    first = left.request("POST", "/v1/rooms/by-code", body)
    retry = left.request("POST", "/v1/rooms/by-code", body)
    check(first["activity"]["id"] == retry["activity"]["id"], "Lost create response reuses one room")
    room = right.change("POST", "/v1/rooms/by-code", {"code": code, "loadout": right.loadout})["activity"]["room"]
    check(room["code"] == code and room["code"][0] == "0", "Six-digit code preserves leading zero")
    check(len(room["roster"]) == 2, "One room contains exactly two seats")
    third = Player(url)
    denial = third.change("POST", "/v1/rooms/by-code", {"code": code, "loadout": third.loadout}, True)
    check(denial.get("error") == "ROOM_FULL", "Third identity cannot occupy full room")
    mixed = left.change("POST", "/v1/matchmaking/tickets", {"loadout": left.loadout})
    check(mixed["activity"]["kind"] == "room", "One player cannot queue while occupying a room")
    for player in [left, right]:
        player.change("POST", f"/v1/rooms/{room['id']}/ready", {"ready": True, "expected_revision": room["revision"]})
    match = left.activity()["id"]
    check(right.activity()["id"] == match, "Both members start the same match UUID")
    a, b = Peer(left, match), Peer(right, match)
    try:
        pump([a, b], lambda: a.current and b.current and a.resume and b.resume and a.current["connection"]["phase"] == "RUNNING" and b.current["connection"]["phase"] == "RUNNING")
        check(a.current["seat"] != b.current["seat"], "Seats are assigned by authenticated identity")
        for peer in [a, b]:
            check(not any(k in peer.current["enemy"] for k in ["gold", "knowledge", "queue", "cooldowns", "activeItems"]), "Subscriber projection hides enemy private state")
            peer.send("command", {"client_seq": 1, "last_seen_tick": peer.current["tick"], "action": {"type": "train", "unitId": "U11"}})
        pump([a, b], lambda: a.results.get(1, {}).get("status") == "APPLIED" and b.results.get(1, {}).get("status") == "APPLIED")
        check(a.results[1]["ok"] and b.results[1]["ok"], "Both independent seq=1 recruit successfully")
        for _ in range(100):
            a.send("command", {"client_seq": 1, "last_seen_tick": a.current["tick"], "action": {"type": "train", "unitId": "U11"}})
        pump([a, b], lambda: a.current["tick"] >= a.results[1]["applied_tick"] + 60)
        def trained(state):
            return len(state["own"]["queue"]) + sum(1 for entity in state["entities"] if entity["kind"] == "unit" and entity["side"] == state["seat"])
        check(trained(a.current) == 1, "100 repeated recruitment packets spend and train once")
        check(trained(b.current) == 1, "Opponent recruitment remains independent")
        original_epoch = a.epoch
        a.close()
        pump([b], lambda: b.current["connection"]["paused"] and not b.current["connection"]["opponent_connected"], 10)
        check(b.current["connection"]["pause_reason"] == "TECHNICAL_PAUSE", "Detected disconnect enters bounded technical pause")
        a = Peer(left, match)
        pump([a, b], lambda: a.resume and a.current and not a.current["connection"]["paused"] and not b.current["connection"]["paused"])
        check(a.epoch > original_epoch and a.match == match, "Reconnect retains match and fences old connection epoch")
        check(a.resume["next_client_seq"] == 2, "Reconnect retains durable per-player command cursor")
        check(trained(a.current) == 1, "Reconnect never replays the old recruitment")
        a.send("command", {"client_seq": 2, "last_seen_tick": a.current["tick"], "action": {"type": "evolve", "upgradeId": "R101"}})
        pump([a, b], lambda: a.results.get(2, {}).get("status") == "REJECTED")
        check(a.current["own"]["eraId"] == "A1" and b.current["own"]["eraId"] == "A1", "Invalid evolution changes neither player's era")
        left.change("POST", f"/v1/matches/{match}/surrender", {"confirm": True})
        pump([a, b], lambda: hasattr(a, "final") and hasattr(b, "final"))
        check(a.final["result_id"] == b.final["result_id"] and a.final["winner"] == b.current["seat"], "Both clients receive one durable surrender result")
        again = left.request("GET", f"/v1/matches/{match}/result")["result"]
        check(again["result_id"] == a.final["result_id"], "App restart can retrieve the same final result")
    finally:
        a.close(); b.close()
    for player in [left, right]:
        player.change("POST", f"/v1/matches/{match}/ack-result")
    # Parallel admission uses actual transactions, not a mock in-memory room map.
    contenders = [Player(url) for _ in range(20)]
    shared = "0" + str(secrets.randbelow(100000)).zfill(5)
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as pool:
        responses = list(pool.map(lambda p: p.change("POST", "/v1/rooms/by-code", {"code": shared, "loadout": p.loadout}, True), contenders))
    accepted = [r for r in responses if r.get("ok")]
    check(len(accepted) == 2 and len({r["activity"]["id"] for r in accepted}) == 1, "20 simultaneous same-code requests create one room and two members")
    check(sum(r.get("error") == "ROOM_FULL" for r in responses) == 18, "18 overflow members get explicit ROOM_FULL")
    for player in contenders:
        activity = player.activity()
        if activity["kind"] == "room":
            player.change("POST", f"/v1/rooms/{activity['id']}/leave")
    for player in [left, right]:
        player.change("POST", "/v1/matchmaking/tickets", {"loadout": player.loadout})
    for _ in range(30):
        activity_left, activity_right = left.activity(), right.activity()
        if activity_left["kind"] == "room" and activity_right["kind"] == "room":
            break
        time.sleep(0.2)
    check(activity_left["id"] == activity_right["id"] and activity_left["room"]["phase"] == "OFFER", "Free matchmaking offers a real human opponent")
    left.change("POST", f"/v1/match-offers/{activity_left['id']}/decision", {"accept": False, "offer_revision": activity_left["room"]["revision"]})
    check(right.activity()["kind"] == "", "Declining an offer releases both reservations")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:28187")
    args = parser.parse_args()
    failure = None
    start = time.monotonic()
    try:
        main(args.url)
    except Exception as exc:
        failure = type(exc).__name__ + ": " + str(exc)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps({"checks": checks, "failed": failure, "seconds": time.monotonic() - start, "native_postgresql": True, "native_godot_worker": True}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"NETWORK INTEGRATION: {len(checks)} checks, {'FAILED: '+failure if failure else 'all passed'}")
    raise SystemExit(1 if failure else 0)
