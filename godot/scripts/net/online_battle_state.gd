class_name OnlineBattleState
extends GameModel

signal command_requested(action: Dictionary)
signal connection_changed
signal command_feedback(result: Dictionary)

var seat = 0
var connected = false
var connection_status = "同步战局"
var match_id = ""
var result_reason = ""
var status_data = {}
var network_age = 0.0
var blend_duration = 0.1
var last_server_tick = -1
var event_cursor = 0
var previous_positions = {}
var render_positions = {}
var is_online = true

func _init() -> void:
	super()
	config["mode"] = "online"
	config["aiEnabled"] = false
	config["randomEvents"] = false
	config["controlTypes"] = ["human", "human"]

func apply_projection(projection: Dictionary, full_sync: bool = false) -> bool:
	if not projection.get("entities") is Array or not projection.get("own") is Dictionary or not projection.get("enemy") is Dictionary: return false
	if projection["entities"].size() < 2 or projection["entities"].size() > 180: return false
	var incoming_tick = int(projection.get("tick", -1))
	if incoming_tick < last_server_tick: return false
	previous_positions = render_positions.duplicate()
	seat = int(projection.get("seat", seat))
	if seat not in [0, 1]: return false
	var visible = BattlePerspective.project(projection, seat)
	sides = [visible["own"], visible["enemy"]]
	entities = visible["entities"]
	projectiles = visible.get("projectiles", [])
	fields = visible.get("fields", [])
	cast_targets = visible.get("cast_targets", {})
	tick = incoming_tick
	winner = int(visible.get("winner", -1))
	max_era = "A10"
	config["matchId"] = match_id
	config["loadout"] = sides[0]["loadout"].duplicate(true)
	config["enemyLoadout"] = sides[1]["loadout"].duplicate(true)
	environment.scene = visible.get("scene", environment.scene)
	status_data = projection.get("connection", {})
	paused = bool(status_data.get("paused", false)) or not connected
	result_reason = String(projection.get("result_reason", ""))
	blend_duration = clampf(float(incoming_tick - last_server_tick) / HZ, 0.08, 0.15)
	last_server_tick = incoming_tick
	network_age = 0.0
	accumulator = 0.0
	for entity in entities:
		var entity_id = int(entity["id"])
		var x = float(entity["x"])
		entity["previousX"] = x if full_sync else float(previous_positions.get(entity_id, x))
		render_positions[entity_id] = x if full_sync else entity["previousX"]
	if full_sync:
		pending_events.clear()
		event_cursor = int(projection.get("event_cursor", 0))
	else:
		for event in visible.get("events", []):
			if int(event.get("id", 0)) <= event_cursor: continue
			pending_events.append(event)
			event_cursor = int(event["id"])
	changed.emit()
	return true

func advance(delta: float) -> void:
	# Interpolation only: no combat, resources, production, RNG or AI on clients.
	network_age += delta
	accumulator = minf(STEP, network_age / maxf(0.001, blend_duration) * STEP)
	for entity in entities:
		render_positions[int(entity["id"])] = lerpf(float(entity["previousX"]), float(entity["x"]), interpolation)

func act(action: Dictionary, _sequence: int = -1) -> Dictionary:
	if not connected or paused or winner != -1: return {"ok": false, "reason": "连接恢复后再操作"}
	command_requested.emit(BattlePerspective.server_action(action, seat))
	return {"ok": true, "pending": true}

func set_paused(_value: bool) -> void:
	# Local menus cannot pause a server-owned match.
	pass

func mark_connection(ready: bool, text: String) -> void:
	connected = ready
	connection_status = text
	paused = not ready or bool(status_data.get("paused", false))
	if not ready: pending_events.clear()
	connection_changed.emit()
