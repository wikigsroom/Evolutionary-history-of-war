class_name EpochEnvironment
extends RefCounted

const EVENT_NAMES = {"meteor":"陨石坠落", "plane":"飞机迫降", "dinosaur":"迷途小恐龙", "rockfall":"山岩滚落", "drone":"无人机失控", "debris":"轨道碎片", "storm":"局地雷暴"}

var m
var scene_rng = 1
var event_rng = 1
var scene = {}
var next_event_at = 0
var events_spawned = 0

func _init(model) -> void: m = model

func roll(bound: int, stream: String = "event") -> int:
	var value = scene_rng if stream == "scene" else event_rng
	value = value ^ ((value << 13) & 0xffffffff)
	value = value ^ (value >> 17)
	value = (value ^ ((value << 5) & 0xffffffff)) & 0xffffffff
	if stream == "scene": scene_rng = value
	else: event_rng = value
	return int(value % maxi(1, bound))

func leading_era() -> String:
	return String(m.sides[0]["eraId"]) if m.db.era_index(m.sides[0]["eraId"]) >= m.db.era_index(m.sides[1]["eraId"]) else String(m.sides[1]["eraId"])

func reset(seed_value: int) -> void:
	scene_rng = (seed_value ^ 0x9e3779b9) & 0xffffffff
	event_rng = (seed_value ^ 0x85ebca6b) & 0xffffffff
	if scene_rng == 0: scene_rng = 137
	if event_rng == 0: event_rng = 419
	events_spawned = 0
	scene = {"eraId": leading_era(), "variant": 1 + roll(3, "scene"), "changedAt": -90, "serial": 0}
	var rules = m.db.rules["randomEvents"]
	next_event_at = ceili((float(rules["firstMinSec"]) + roll(int(rules["firstMaxSec"]) - int(rules["firstMinSec"]) + 1)) * m.HZ)

func on_evolve() -> void:
	var previous = scene.duplicate(true)
	var era_id = leading_era()
	var variant = 1 + roll(3, "scene")
	if previous.get("eraId") == era_id and int(previous.get("variant", 0)) == variant:
		variant = variant % 3 + 1
	scene = {"eraId": era_id, "variant": variant, "previousEraId": previous.get("eraId", era_id), "previousVariant": previous.get("variant", 1), "changedAt": m.tick, "serial": int(previous.get("serial", 0)) + 1}
	m.emit_event("mapChanged", 800.0, -1, scene.duplicate(true))

func update() -> void:
	if not bool(m.config.get("randomEvents", true)) or m.winner >= 0: return
	var rules = m.db.rules["randomEvents"]
	if m.tick < next_event_at or events_spawned >= int(rules["maximumEvents"]): return
	var era_id = leading_era()
	var pool = m.db.era(era_id)["eventPool"]
	spawn_event(String(pool[roll(pool.size())]), 300.0 + roll(1001), era_id)
	next_event_at = m.tick + ceili((float(rules["intervalMinSec"]) + roll(int(rules["intervalMaxSec"]) - int(rules["intervalMinSec"]) + 1)) * m.HZ)

func spawn_event(kind: String, x: float, era_id: String = "") -> void:
	if era_id.is_empty(): era_id = leading_era()
	x = clampf(x, 230.0, 1370.0)
	var event_id = m.id()
	var radius = 130.0 if kind in ["meteor", "plane"] else 105.0
	var warning = ceili(float(m.db.rules["randomEvents"]["warningSec"]) * m.HZ)
	var source = {"id": event_id, "kind": "environment", "neutral": true, "side": -1, "eraId": era_id, "x": x, "weaponId": "W05", "heavy": true}
	m.scheduled.append({"kind": "environment", "due": m.tick + warning, "source": source, "x": x, "radius": radius, "eventKind": kind, "castId": event_id})
	m.emit_event("eventWarning", x, -1, {"eventKind": kind, "eraId": era_id, "radius": radius, "until": m.tick + warning, "castId": event_id})
	events_spawned += 1

func resolve(event: Dictionary) -> void:
	var source = event["source"]
	for target in m.living(-1, false):
		if absf(float(target["x"]) - float(event["x"])) > float(event["radius"]) + float(target["radius"]): continue
		var amount = minf(float(target["maxHp"]) * float(m.db.rules["randomEvents"]["maximumDamageHpRatioPerEvent"]), 18.0 * m.db.attack_multiplier(source["eraId"]))
		m.combat.hit(source, target, amount, "blast", {"environment": true, "eventKind": event["eventKind"], "canDamageBase": false})
	m.emit_event("eventImpact", float(event["x"]), -1, {"eventKind": event["eventKind"], "eraId": source["eraId"], "radius": event["radius"], "castId": event["castId"]})

func snapshot() -> Dictionary:
	return {"scene_rng": scene_rng, "event_rng": event_rng, "scene": scene.duplicate(true), "next_event_at": next_event_at, "events_spawned": events_spawned}

func can_restore(data: Dictionary) -> bool:
	if not data.get("scene") is Dictionary: return false
	var state = data["scene"]
	if m.db.era(String(state.get("eraId", ""))).is_empty(): return false
	for key in ["variant", "changedAt", "serial"]:
		var number = state.get(key)
		if (not number is int and not number is float) or not is_finite(float(number)) or float(number) != int(number): return false
	if int(state["variant"]) not in [1,2,3] or int(state["serial"]) < 0: return false
	if state.has("previousEraId"):
		if m.db.era(String(state["previousEraId"])).is_empty() or int(state.get("previousVariant", 0)) not in [1,2,3]: return false
	for key in ["scene_rng", "event_rng", "next_event_at", "events_spawned"]:
		var number = data.get(key)
		if (not number is int and not number is float) or not is_finite(float(number)) or float(number) != int(number) or float(number) < 0.0: return false
	if int(data["scene_rng"]) == 0 or int(data["event_rng"]) == 0 or int(data["scene_rng"]) > 0xffffffff or int(data["event_rng"]) > 0xffffffff: return false
	if int(data["events_spawned"]) > int(m.db.rules["randomEvents"]["maximumEvents"]): return false
	return true

func restore(data: Dictionary) -> bool:
	if not can_restore(data): return false
	scene_rng = int(data["scene_rng"]); event_rng = int(data["event_rng"])
	scene = data["scene"].duplicate(true); next_event_at = int(data["next_event_at"]); events_spawned = int(data["events_spawned"])
	for key in ["variant", "changedAt", "serial", "previousVariant"]:
		if scene.has(key): scene[key] = int(scene[key])
	return true
