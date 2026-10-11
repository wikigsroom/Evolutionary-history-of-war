class_name EpochNetClient
extends Node

signal status_changed
signal activity_changed
signal battle_available(state)
signal result_available(result: Dictionary)

const RETRIES = [0.0, 1.0, 2.0, 4.0]
const DEFAULT_ENDPOINT = "https://jyqx-server.sidcloud.cn"
const ERRORS = {"ROOM_FULL":"房间已满", "INVALID_ROOM_CODE":"请输入六位数字", "CODE_COOLDOWN":"该房间码刚结束，请稍后使用", "VERSION_MISMATCH":"双方需要使用相同游戏版本", "ROOM_REVISION_CHANGED":"房间已变化，请重新准备", "SERVER_FULL":"服务器对战席位已满", "MAINTENANCE":"服务器正在维护", "OFFER_EXPIRED":"对战邀请已过期", "UNAUTHORIZED":"身份需要重新验证", "NOT_MEMBER":"无法进入其他玩家的对局", "INPUT_LOCKED":"正在同步战局", "SEQUENCE_GAP":"正在核对指令", "RATE_LIMITED":"操作过快，请稍后重试"}

var endpoint = ""
var status = "连接服务器，开始真人对战"
var busy = false
var authenticated = false
var activity = {"kind":"", "id":""}
var loadout = {}
var player_id = ""
var access_token = ""
var manifest = {}
var battle_state: OnlineBattleState
var credentials: SessionCredentials
var socket: WebSocketPeer
var connection_epoch = 0
var match_id = ""
var next_seq = 1
var pending = {}
var state_cache = {}
var chunks = {}
var retry_index = 0
var retry_at = -1.0
var last_packet_at = 0.0
var last_state_at = 0.0
var full_sync_requested = false
var next_ping_at = 0.0
var activity_poll_at = 0.0
var syncing = false
var socket_connecting = false
var resume_sent = false
var first_projection = true
var backgrounded = false
var seen_feedback = {}
var finished = false
var session_directory = "user://"
var loadout_dirty = false
var loadout_flushing = false

func _ready() -> void:
	credentials = SessionCredentials.new()
	credentials.directory = session_directory
	DirAccess.make_dir_recursive_absolute(session_directory)
	add_child(credentials)
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/online-manifest.json"))
	var preferences = _read_session()
	endpoint = String(preferences.get("endpoint", DEFAULT_ENDPOINT))
	if endpoint.is_empty(): endpoint = DEFAULT_ENDPOINT
	loadout = preferences.get("loadout", EpochData.new().default_loadout("H03"))
	var from_environment = OS.get_environment("EPOCH_ONLINE_URL")
	if not from_environment.is_empty(): endpoint = from_environment
	# Returning players reconnect as soon as the application starts.
	if not endpoint.is_empty() and not String(preferences.get("match_id", "")).is_empty(): connect_service()

func _read_session() -> Dictionary:
	var path = session_directory + "online-session.json"
	if not FileAccess.file_exists(path): return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 131072: return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _save_session() -> bool:
	var file = FileAccess.open(session_directory + "online-session.json.tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"endpoint":endpoint,"loadout":loadout,"match_id":match_id,"pending":pending},"",true,true))
	file.flush();file.close()
	return DirAccess.rename_absolute(session_directory + "online-session.json.tmp", session_directory + "online-session.json") == OK

func set_endpoint(value: String) -> bool:
	var url = value.strip_edges().trim_suffix("/")
	var valid = RegEx.new()
	valid.compile("^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?$")
	var local = RegEx.new()
	local.compile("^http://(localhost|127\\.0\\.0\\.1|10\\.[0-9]+\\.[0-9]+\\.[0-9]+|192\\.168\\.[0-9]+\\.[0-9]+|172\\.(1[6-9]|2[0-9]|3[01])\\.[0-9]+\\.[0-9]+)(:[0-9]{1,5})?$")
	if not valid.search(url) and not local.search(url): _set_status("公网地址需使用 HTTPS；局域网可使用 HTTP"); return false
	if match_id != "" and not finished and endpoint != url: _set_status("请先结束当前对局再切换服务器"); return false
	if endpoint != url:
		access_token = ""; authenticated = false; player_id = ""; activity = {"kind":"", "id":""}
	endpoint = url
	_save_session()
	return true

func _set_status(text: String) -> void:
	status = text
	status_changed.emit()

func connect_service() -> bool:
	if busy or endpoint.is_empty(): return false
	busy = true; _set_status("正在连接服务器")
	var bootstrap = await _http("GET", "/v1/bootstrap", {}, false)
	if not bootstrap.get("ok", false): busy = false; return false
	if bootstrap.get("protocol_version") != manifest["protocol_version"] or bootstrap.get("simulation_hash") != manifest["simulation_hash"]:
		busy = false; _set_status(ERRORS["VERSION_MISMATCH"]); return false
	var key = await credentials.installation_key(endpoint)
	if key.is_empty(): busy = false; _set_status(credentials.last_error); return false
	var identity = await _http("POST", "/v1/auth/guest", {"installation_key":key}, false)
	if not identity.get("ok", false): busy = false; return false
	access_token = identity["access_token"]; player_id = identity["player_id"]; authenticated = true
	busy = false; _set_status("已连接 · 真人对战")
	await refresh_activity()
	return true

func _http(method: String, path: String, body: Dictionary = {}, authorize: bool = true) -> Dictionary:
	var request = HTTPRequest.new(); request.timeout = 8.0; request.body_size_limit = 524288
	add_child(request)
	var headers = PackedStringArray(["Content-Type: application/json"])
	if authorize: headers.append("Authorization: Bearer " + access_token)
	var verbs = {"GET":HTTPClient.METHOD_GET,"POST":HTTPClient.METHOD_POST,"PATCH":HTTPClient.METHOD_PATCH,"DELETE":HTTPClient.METHOD_DELETE}
	var error = request.request(endpoint + path, headers, verbs[method], "" if method == "GET" else JSON.stringify(body))
	if error != OK: request.queue_free(); _set_status("服务器暂时无法连接"); return {"ok":false}
	var response = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS: _set_status("连接中断，正在等待网络恢复"); return {"ok":false,"retryable":true}
	# Reverse proxies can return HTML or an empty body while the gateway restarts.
	# Parse quietly and let reconnection handle it as a temporary network failure.
	var decoder = JSON.new()
	if decoder.parse(response[3].get_string_from_utf8()) != OK:
		_set_status("连接中断，正在等待网络恢复"); return {"ok":false,"retryable":true}
	var parsed = decoder.data
	if not parsed is Dictionary: _set_status("服务器响应无效"); return {"ok":false,"retryable":true}
	if not parsed.get("ok", false):
		_set_status(String(ERRORS.get(parsed.get("error", ""), "服务器暂时无法完成请求")))
		if int(response[1]) == 401: authenticated = false
		if int(response[1]) == 503 and parsed.get("error") != "MAINTENANCE": parsed["retryable"] = true
	return parsed

func _contract(body: Dictionary) -> Dictionary:
	body["request_id"] = Crypto.new().generate_random_bytes(16).hex_encode()
	body["protocol_version"] = manifest["protocol_version"]
	body["simulation_hash"] = manifest["simulation_hash"]
	body["ruleset_id"] = manifest["ruleset_id"]
	return body

func _change(method: String, path: String, body: Dictionary) -> Dictionary:
	if busy: return {"ok":false}
	if not authenticated:
		if not await connect_service(): return {"ok":false}
	busy = true
	var request_body = _contract(body)
	var result = await _http(method, path, request_body)
	# A lost response repeats the same idempotency key, never invents a new room/action.
	if result.get("retryable", false): result = await _http(method, path, request_body)
	busy = false
	if result.get("activity") is Dictionary: _apply_activity(result["activity"])
	else: await refresh_activity()
	return result

func join_code(code: String) -> void:
	await _change("POST", "/v1/rooms/by-code", {"code":code,"loadout":loadout})
func queue_match() -> void:
	await _change("POST", "/v1/matchmaking/tickets", {"loadout":loadout})
func cancel_queue() -> void:
	await _change("DELETE", "/v1/matchmaking/tickets/" + String(activity.get("id", "")), {})
func leave_room() -> void:
	await _change("POST", "/v1/rooms/" + String(activity.get("id", "")) + "/leave", {})
func room_ready(value: bool) -> void:
	if loadout_dirty:
		await _flush_loadout()
		if loadout_dirty: _set_status("构筑尚未同步，请稍后准备"); return
	await _change("POST", "/v1/rooms/" + String(activity.get("id", "")) + "/ready", {"expected_revision":activity.get("room", {}).get("revision", 0),"ready":value})
func accept_offer(value: bool) -> void:
	await _change("POST", "/v1/match-offers/" + String(activity.get("id", "")) + "/decision", {"offer_revision":activity.get("room", {}).get("revision", 0),"accept":value})
func update_loadout(value: Dictionary) -> void:
	if activity.get("kind") in ["queue", "match"] or activity.get("room",{}).get("phase") == "OFFER": _set_status("结束当前匹配后再调整构筑"); return
	loadout = value.duplicate(true); _save_session()
	if activity.get("kind") == "room":
		loadout_dirty = true; await _flush_loadout()

func _flush_loadout() -> void:
	if loadout_flushing: return
	loadout_flushing = true
	var attempts = 0
	while loadout_dirty and activity.get("kind") == "room" and attempts < 3:
		if busy: await get_tree().create_timer(0.1).timeout; continue
		attempts += 1
		var desired = loadout.duplicate(true)
		var response = await _change("PATCH", "/v1/rooms/" + String(activity["id"]) + "/loadout", {"expected_revision":activity["room"]["revision"],"loadout":desired})
		if response.get("ok",false): loadout_dirty = JSON.stringify(desired,"",true) != JSON.stringify(loadout,"",true)
		elif response.get("error") != "ROOM_REVISION_CHANGED": break
	loadout_flushing = false
func surrender() -> void:
	await _change("POST", "/v1/matches/" + match_id + "/surrender", {"confirm":true})
func acknowledge_result() -> void:
	var result = await _change("POST", "/v1/matches/" + match_id + "/ack-result", {})
	if result.get("ok", false):
		match_id = ""; pending.clear(); _save_session()

func refresh_activity() -> void:
	if not authenticated or busy: return
	activity_poll_at = Time.get_ticks_msec() / 1000.0 + 1.0
	var result = await _http("GET", "/v1/activities/me")
	if result.get("ok", false): _apply_activity(result["activity"])

func _apply_activity(value: Dictionary) -> void:
	activity = value
	activity_changed.emit()
	if value.get("kind") != "match": return
	var id = String(value["id"])
	if value.get("phase") == "FINISHED":
		match_id = id; _finish(value.get("result", {})); return
	if match_id != id or battle_state == null:
		if battle_state != null: battle_state.queue_free()
		battle_state = OnlineBattleState.new(); battle_state.match_id = id; add_child(battle_state)
		battle_state.command_requested.connect(submit_action)
		match_id = id; finished = false; seen_feedback.clear(); state_cache.clear()
		var saved = _read_session()
		pending = saved.get("pending", {}) if saved.get("match_id") == id else {}
		_save_session()
	if socket == null and not socket_connecting and retry_at < 0: _open_socket()

func _open_socket() -> void:
	if socket_connecting or backgrounded or finished: return
	socket_connecting = true; syncing = true; first_projection = true; resume_sent = false
	connection_epoch = 0
	battle_state.mark_connection(false, "正在恢复原对局")
	if not authenticated:
		if not await connect_service(): socket_connecting = false; _schedule_retry(); return
	var ticket = await _http("POST", "/v1/ws-tickets", _contract({"match_id":match_id}))
	if not ticket.get("ok", false): socket_connecting = false; _schedule_retry(); return
	socket = WebSocketPeer.new(); socket.inbound_buffer_size = 1048576; socket.outbound_buffer_size = 65536; socket.max_queued_packets = 256
	socket.supported_protocols = PackedStringArray(["epoch-rush.v1"])
	socket.handshake_headers = PackedStringArray(["Authorization: Bearer " + String(ticket["ticket"])])
	var url = endpoint.replace("https://", "wss://").replace("http://", "ws://") + String(ticket["socket_path"])
	var error = socket.connect_to_url(url)
	last_packet_at = Time.get_ticks_msec() / 1000.0; next_ping_at = last_packet_at
	last_state_at = last_packet_at; full_sync_requested = false
	socket_connecting = false
	if error != OK: socket = null; _schedule_retry()

func _send(type: String, payload: Dictionary) -> bool:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN or connection_epoch == 0: return false
	return socket.send_text(JSON.stringify({"v":"1.0","type":type,"match_id":match_id,"connection_epoch":connection_epoch,"payload":payload})) == OK

func submit_action(action: Dictionary) -> void:
	if syncing or not battle_state.connected or pending.size() >= 64: battle_state.command_feedback.emit({"ok":false,"reason":"连接恢复后再操作"}); return
	var seq = next_seq; next_seq += 1
	pending[str(seq)] = {"action":action,"created_at":Time.get_unix_time_from_system()}
	if not _save_session():
		pending.erase(str(seq)); next_seq = seq
		battle_state.command_feedback.emit({"ok":false,"reason":"本机无法保存指令，请检查磁盘空间"}); return
	if not _send("command", {"client_seq":seq,"last_seen_tick":battle_state.last_server_tick,"action":action}): _lose_connection()

func _feedback(result: Dictionary) -> void:
	var seq = str(int(result.get("client_seq", 0)))
	if seq == "0" or result.get("status") == "QUEUED": return
	if seen_feedback.has(seq): return
	seen_feedback[seq] = true
	if pending.has(seq):
		pending.erase(seq); _save_session()
		battle_state.command_feedback.emit(result)
	if seen_feedback.size() > 256: seen_feedback.erase(seen_feedback.keys()[0])

func _message(message: Dictionary) -> void:
	if message.get("match_id", match_id) != match_id: return
	if message.get("type") != "hello" and message.has("connection_epoch") and int(message["connection_epoch"]) != connection_epoch: return
	var payload = message.get("payload", {})
	match message.get("type", ""):
		"hello": connection_epoch = int(message["connection_epoch"]); battle_state.seat = int(payload["seat"])
		"pong": pass
		"state_chunk": _chunk(payload)
		"state_full": _state(payload, true)
		"state_delta":
			var base = int(payload.get("base_snapshot_seq", -1))
			if not state_cache.has(base):
				if not full_sync_requested: full_sync_requested = _send("full_sync", {})
				return
			var state = state_cache[base].duplicate(true); state.merge(payload.get("changes", {}), true)
			state["snapshot_seq"] = int(payload["snapshot_seq"])
			_state(state, false)
		"resume_ready":
			next_seq = int(payload["next_client_seq"])
			for result in payload.get("results", []): _feedback(result)
			syncing = false; retry_index = 0; retry_at = -1.0
			battle_state.mark_connection(true, "联机对战")
		"connection_status":
			if payload.get("server_recovering", false): battle_state.mark_connection(false, "服务器正在恢复战局")
		"command_receipt":
			if not payload.get("ok", false):
				# Reconcile an unconsumed sequence before allowing another click.
				battle_state.command_feedback.emit({"ok":false,"reason":ERRORS.get(payload.get("error", ""), "指令未受理")})
				_lose_connection()
			elif payload.get("status") != "QUEUED": _feedback(payload)
		"command_result": _feedback(payload)
		"match_result": _finish(payload)
		"error": _lose_connection()

func _state(state: Dictionary, full: bool) -> void:
	var seq = int(state.get("snapshot_seq", -1))
	state_cache[seq] = state.duplicate(true)
	while state_cache.size() > 32:
		var keys = state_cache.keys(); keys.sort(); state_cache.erase(keys[0])
	if not battle_state.apply_projection(state, full and first_projection): _send("full_sync", {}); return
	last_state_at = Time.get_ticks_msec() / 1000.0
	full_sync_requested = false
	_send("state_ack", {"snapshot_seq":seq})
	if first_projection:
		first_projection = false
		battle_available.emit(battle_state)
	if not resume_sent:
		var sequences = []
		for key in pending: sequences.append(int(key))
		resume_sent = _send("resume_ready", {"pending_sequences":sequences})
	if not syncing:
		var connection = state.get("connection", {})
		var label = "联机对战"
		if connection.get("phase") == "LOADING": label = "等待双方加载"
		elif connection.get("server_recovering", false): label = "服务器正在恢复战局"
		elif not connection.get("opponent_connected", true): label = "对手重连中 · %d 秒" % ceili(float(connection.get("opponent_grace_ms",0))/1000.0)
		battle_state.mark_connection(not connection.get("server_recovering", false), label)

func _chunk(payload: Dictionary) -> void:
	var seq = int(payload.get("snapshot_seq", -1)); var count = int(payload.get("count", 0)); var index = int(payload.get("index", -1))
	if count < 1 or count > 16 or index < 0 or index >= count: _lose_connection(); return
	if not chunks.has(seq): chunks = {seq:{"count":count,"hash":payload.get("hash", ""),"parts":{},"at":Time.get_ticks_msec()}}
	var assembly = chunks[seq]
	if assembly["count"] != count or assembly["hash"] != payload.get("hash"): _lose_connection(); return
	var data = Marshalls.base64_to_raw(String(payload.get("data", "")))
	if data.size() > 16384: _lose_connection(); return
	assembly["parts"][index] = data
	if assembly["parts"].size() != count: return
	var bytes = PackedByteArray()
	for i in range(count): bytes.append_array(assembly["parts"][i])
	var hashing = HashingContext.new(); hashing.start(HashingContext.HASH_SHA256); hashing.update(bytes)
	if bytes.size() > 262144 or hashing.finish().hex_encode() != assembly["hash"]: _lose_connection(); return
	chunks.clear()
	var parsed = JSON.parse_string(bytes.get_string_from_utf8())
	if parsed is Dictionary: _message(parsed)
	else: _lose_connection()

func _schedule_retry() -> void:
	if finished or backgrounded: return
	var delay = RETRIES[mini(retry_index, RETRIES.size() - 1)] * randf_range(0.8, 1.2)
	retry_index += 1; retry_at = Time.get_ticks_msec() / 1000.0 + delay
	_set_status("连接中断，正在返回原对局")

func _lose_connection() -> void:
	if socket != null: socket.close()
	socket = null; syncing = true; chunks.clear(); state_cache.clear(); resume_sent = false
	if battle_state != null: battle_state.mark_connection(false, "连接中断 · 自动重连")
	_schedule_retry()

func _finish(result: Dictionary) -> void:
	if finished: return
	finished = true; retry_at = -1.0; syncing = false
	if socket != null: socket.close(); socket = null
	if battle_state != null:
		var winner = int(result.get("winner", -1))
		battle_state.winner = 2 if winner < 0 else (winner if battle_state.seat == 0 or winner == 2 else 1-winner)
		battle_state.result_reason = String(result.get("reason", "")); battle_state.mark_connection(true, "对战已结束")
	_set_status("对战已结束")
	result_available.emit(result)

func _process(_delta: float) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if socket != null:
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			var count = 0
			while socket.get_available_packet_count() > 0 and count < 64:
				count += 1; var packet = socket.get_packet()
				if packet.size() > 65536: _lose_connection(); break
				var message = JSON.parse_string(packet.get_string_from_utf8())
				if not message is Dictionary: _lose_connection(); break
				last_packet_at = now; _message(message)
				if socket == null: break
			if socket != null and connection_epoch > 0 and now >= next_ping_at:
				next_ping_at = now + 2.0; _send("ping", {"client_time_ms":Time.get_ticks_msec()})
		if socket != null and (socket.get_ready_state() == WebSocketPeer.STATE_CLOSED or now - last_packet_at > 8.0): _lose_connection()
		elif socket != null and not syncing and now - last_state_at > 1.5:
			battle_state.mark_connection(false, "等待服务器恢复战局")
	if retry_at >= 0 and now >= retry_at and not socket_connecting and not backgrounded:
		retry_at = -1.0; _open_socket()
	if authenticated and not busy and not backgrounded and now >= activity_poll_at and (socket == null or finished):
		activity_poll_at = now + 2.0; refresh_activity()
	elif not authenticated and not busy and not backgrounded and not endpoint.is_empty() and activity.get("kind","") != "" and now >= activity_poll_at:
		activity_poll_at = now + 4.0; connect_service()
	for seq in chunks.keys():
		if Time.get_ticks_msec() - int(chunks[seq]["at"]) > 10000: _lose_connection(); break

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		backgrounded = true; _send("suspend", {}); _save_session()
		if socket != null: socket.close(); socket = null
		if battle_state != null: battle_state.mark_connection(false, "回到前台后恢复原局")
	if what == NOTIFICATION_APPLICATION_RESUMED:
		backgrounded = false
		if not finished and not match_id.is_empty(): retry_at = Time.get_ticks_msec() / 1000.0
