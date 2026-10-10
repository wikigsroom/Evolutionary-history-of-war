extends SceneTree

# Private IPC is bound by the gateway to loopback only. No public RPC surface.
const Router = preload("res://server/command_router.gd")
const NetProjection = preload("res://server/network_projection.gd")
const MAX_FRAME = 4194304
var socket = StreamPeerTCP.new()
var model: GameModel
var buffered = PackedByteArray()
var started_at = 0

func _initialize() -> void:
	model = GameModel.new()
	root.add_child(model)
	started_at = Time.get_ticks_msec()
	var port = int(OS.get_environment("EPOCH_WORKER_PORT"))
	if port < 1 or socket.connect_to_host("127.0.0.1", port) != OK: quit(2)

func _process(_delta: float) -> bool:
	socket.poll()
	if socket.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		if Time.get_ticks_msec() - started_at > 10000: quit(2)
		return false
	if socket.get_status() != StreamPeerTCP.STATUS_CONNECTED: quit(0); return false
	var available = socket.get_available_bytes()
	if available > 0:
		var received = socket.get_data(available)
		if received[0] != OK: quit(2); return false
		buffered.append_array(received[1])
	if buffered.size() > MAX_FRAME + 4: quit(3); return false
	while buffered.size() >= 4:
		var size = int(buffered[0]) * 16777216 + int(buffered[1]) * 65536 + int(buffered[2]) * 256 + int(buffered[3])
		if size < 2 or size > MAX_FRAME: quit(3); return false
		if buffered.size() < size + 4: break
		var parsed = JSON.parse_string(buffered.slice(4, size + 4).get_string_from_utf8())
		buffered = buffered.slice(size + 4)
		var response = handle(parsed) if parsed is Dictionary else {"error": "INVALID_FRAME"}
		var payload = JSON.stringify(response, "", true, true).to_utf8_buffer()
		var header = PackedByteArray([payload.size() >> 24 & 255, payload.size() >> 16 & 255, payload.size() >> 8 & 255, payload.size() & 255])
		if socket.put_data(header) != OK or socket.put_data(payload) != OK: quit(2); return false
	return false

func handle(request: Dictionary) -> Dictionary:
	match request.get("type", ""):
		"init":
			var options = {"mode": "online", "missionId": "", "aiEnabled": false, "randomEvents": false, "controlTypes": ["human", "human"], "seed": int(request.get("seed", 42571))}
			options["loadout"] = request.get("loadouts", [model.db.default_loadout(), model.db.default_loadout("H03")])[0]
			options["enemyLoadout"] = request.get("loadouts", [model.db.default_loadout(), model.db.default_loadout("H03")])[1]
			model.reset_battle(options)
			model.consume_events()
		"restore":
			if not model.restore(request.get("snapshot", {})): return {"error": "INVALID_CHECKPOINT", "detail": model.last_restore_error}
		"batch":
			pass
		_: return {"error": "INVALID_OPERATION"}
	var results = []
	if request.get("type") == "batch":
		model.paused = false
		var commands = request.get("commands", [])
		var steps = clampi(int(request.get("steps", 0)), 0, 30)
		for i in range(steps + 1):
			for command in commands:
				if command.has("processed") or int(command.get("apply_tick", model.tick)) > model.tick: continue
				command["processed"] = true
				var side = int(command.get("side", -1))
				var action: Dictionary = command.get("action", {}).duplicate(true)
				var error = Router.validate(model, action, side) if side in [0, 1] else "INVALID_SIDE"
				var result = {"ok": false, "reason": error}
				if error.is_empty():
					action["side"] = side
					result = model.act(action)
				results.append({"player_id": String(command["player_id"]), "client_seq": int(command["client_seq"]), "result": result, "tick": int(model.tick)})
			if i < steps and model.winner == -1: model.step_tick()
		if model.tick >= 2400 * GameModel.HZ and model.winner == -1: model.winner = 2
	var events = model.consume_events()
	return {"snapshot": model.snapshot(), "tick": model.tick, "winner": model.winner,
		"results": results, "projections": [NetProjection.make(model, 0, events), NetProjection.make(model, 1, events)]}
