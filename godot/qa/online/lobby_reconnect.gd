extends SceneTree

var client: EpochNetClient
var checks = []
var output = ""

func _initialize() -> void:
	output = OS.get_environment("EPOCH_QA_OUTPUT").trim_suffix("/") + "/"
	call_deferred("run")

func check(value: bool, title: String) -> void:
	checks.append({"name":title, "passed":value})
	if not value: push_error(title)

func wait_for(predicate: Callable, seconds: float = 25) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return false

func control(path: String) -> Dictionary:
	var request = HTTPRequest.new()
	root.add_child(request)
	request.request(OS.get_environment("EPOCH_ONLINE_URL") + "/qa/" + path)
	var response = await request.request_completed
	request.queue_free()
	return JSON.parse_string(response[3].get_string_from_utf8())

func run() -> void:
	client = EpochNetClient.new()
	client.session_directory = "user://qa-lobby-retry-%d/" % Time.get_ticks_usec()
	root.add_child(client)
	await create_timer(0.3).timeout
	check(not client.service_requested and not client.authenticated, "Cold offline client makes no connection request")
	client.request_connection()
	check(await wait_for(func():return client.service_retry_index >= 3 and not client.busy), "Initial HTML proxy errors trigger periodic retries even with no activity")
	check(client.service_retry_at > Time.get_ticks_msec() / 1000.0 and not client.authenticated, "Network actions remain unauthenticated during retry delay")
	check(await wait_for(func():return client.authenticated and client.service_state == "connected"), "Initial connection recovers automatically after the service becomes available")
	var player = client.player_id
	check(not player.is_empty() and client.activity.get("kind", "") == "", "Recovered empty lobby retains a protected anonymous identity")
	await control("offline")
	await client.refresh_activity()
	check(not client.authenticated and client.service_state == "retrying", "Connection loss in an empty lobby is detected and schedules reconnect")
	check(await wait_for(func():return client.service_retry_index >= 2 and not client.busy), "Lobby keeps retrying after repeated connection failures")
	await control("online")
	check(await wait_for(func():return client.authenticated and client.player_id == player and client.service_state == "connected"), "Restored service reconnects the same player without another click")
	var before = await control("stats")
	client._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await create_timer(3).timeout
	var paused = await control("stats")
	check(before["requests"] == paused["requests"], "Application background pauses service polling and retries")
	client._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(await wait_for(func():return client.authenticated and client.service_state == "connected"), "Returning to the foreground reconnects the lobby automatically")
	client.access_token = "expired-test-token"
	await client.refresh_activity()
	check(await wait_for(func():return client.authenticated and client.player_id == player), "Unauthorized token is renewed automatically without changing identity")
	# Persisting a build must not reintroduce an editable saved endpoint.
	client.update_loadout(client.loadout)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(client.session_directory + "online-session.json"))
	check(saved is Dictionary and not saved.has("endpoint"), "Preferences no longer store a user-editable server address")
	var failures = checks.filter(func(row):return not row["passed"])
	var file = FileAccess.open(output + "lobby-reconnect.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures}, "  "))
	file.close()
	print("LOBBY_RECONNECT ", checks.size(), " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
