extends SceneTree

class PreviewClient extends EpochNetClient:
	func _ready() -> void:
		loadout = EpochData.new().default_loadout("H03")
		endpoint = DEFAULT_ENDPOINT
		authenticated = true
		service_state = "connected"
		status = "已连接 · 真人对战"
	func request_connection() -> void: pass
	func _process(_delta: float) -> void: pass

var app
var client: PreviewClient
var checks = []
var directory = ""

func _initialize() -> void:
	directory = OS.get_environment("EPOCH_QA_OUTPUT").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(directory)
	call_deferred("run")

func check(value: bool, title: String) -> void:
	checks.append({"name":title, "passed":value})
	if not value: push_error(title)

func settle() -> void:
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw

func find_lobby(node: Node) -> OnlineMenu:
	if node is OnlineMenu: return node
	for child in node.get_children():
		var found = find_lobby(child)
		if found != null: return found
	return null

func inspect(node: Node, bounds: Rect2) -> bool:
	var valid = true
	if node is Control and node.is_visible_in_tree():
		if node is BaseButton or node is LineEdit or node is Label or node is TextureRect:
			if not bounds.grow(1).encloses(node.get_global_rect()):
				print("LAYOUT_OUTSIDE ", node.get_path(), " ", node.get_global_rect(), " ", bounds)
				valid = false
		if node is BaseButton and (node.size.x < 48 or node.size.y < 48): valid = false
		if node is Button and node.icon != null and node.get_theme_constant("icon_max_width") > 32: valid = false
		if node is LineEdit: valid = valid and node.get_theme_stylebox("read_only") is StyleBoxTexture
		if node is TextureRect and node.name == "CommanderPortrait":
			valid = valid and node.texture is AtlasTexture and node.size.y >= 144 and node.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if node is Label:
			valid = valid and not node.text.contains("jyqx-server") and not node.text.contains("https://")
	for child in node.get_children(): valid = inspect(child, bounds) and valid
	return valid

func room(offer: bool = false, ready: bool = false, two: bool = true) -> Dictionary:
	var roster = [{"seat":0, "is_you":true, "ready":ready, "loadout":client.loadout}]
	if two: roster.append({"seat":1, "is_you":false, "ready":false, "loadout":EpochData.new().default_loadout("H04")})
	return {"kind":"room", "id":"visual-room", "room":{"phase":"OFFER" if offer else "WAITING", "code":"042731", "revision":1, "expires_at_ms":Time.get_unix_time_from_system() * 1000 + 90000, "roster":roster}}

func run() -> void:
	root.size = Vector2i(1280,720)
	app = preload("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.online.queue_free()
	client = PreviewClient.new()
	app.add_child(client)
	app.online = client
	var states = [
		["hall", {"kind":"", "id":""}],
		["queue", {"kind":"queue", "id":"visual-queue", "wait_seconds":86}],
		["room-waiting", room(false, false, false)],
		["room", room()],
		["room-ready", room(false, true)],
		["offer", room(true)],
		["offer-accepted", room(true, true)],
		["resume", {"kind":"match", "id":"visual-match", "phase":"RUNNING"}],
		["result", {"kind":"match", "id":"visual-match", "phase":"FINISHED", "seat":0, "result":{"winner":0}}]
	]
	for item in states:
		client.activity = item[1]
		app.show_menu("online")
		await settle()
		var lobby = find_lobby(app.current_view)
		check(lobby != null and lobby.find_child("OnlineServerAddress", true, false) == null, item[0] + " has no endpoint editor")
		check(inspect(lobby, lobby.get_global_rect()), item[0] + " controls and images fit the page with consistent icon and touch sizes")
		if item[0] in ["hall", "room", "offer", "queue", "room-waiting"]:
			root.get_texture().get_image().save_png(directory + "lobby-" + item[0] + ".png")
		for window_size in [Vector2i(1600,720), Vector2i(2400,1080), Vector2i(960,540), Vector2i(800,450)]:
			root.size = window_size
			app.current_view.safe_ui.test_insets = Vector4(32, 12, 24, 16)
			await settle()
			check(inspect(lobby, lobby.get_global_rect()), item[0] + " fits window %s including safe insets" % window_size)
		root.size = Vector2i(1280,720)
		app.current_view.safe_ui.test_insets = Vector4.ZERO
	for hero_id in ["H01", "H02", "H03", "H04", "H05", "H06"]:
		client.activity = {"kind":"", "id":""}
		client.loadout = EpochData.new().default_loadout(hero_id)
		app.show_menu("online")
		await settle()
		var hero_lobby = find_lobby(app.current_view)
		check(inspect(hero_lobby, hero_lobby.get_global_rect()), "Commander %s fits without distorting or clipping its portrait" % hero_id)
	client.activity = {"kind":"", "id":""}
	app.show_menu("online")
	await settle()
	var lobby = find_lobby(app.current_view)
	check(lobby.join_button.disabled, "Room admission disabled for an empty code")
	lobby.code_input.text = "123"
	lobby.code_input.text_changed.emit("123")
	await settle()
	check(lobby.join_button.disabled and lobby.code_hint.text.contains("3"), "Incomplete code has a nearby hint and cannot be submitted")
	lobby.code_input.text = "a12 3"
	lobby.code_input.text_changed.emit("a12 3")
	check(lobby.code_input.text == "123", "Room input strips letters and spaces")
	lobby.code_input.text = "042731"
	lobby.code_input.text_changed.emit("042731")
	await settle()
	check(not lobby.join_button.disabled, "Six digits enable room admission and preserve a leading zero")
	client.authenticated = false
	client.service_state = "retrying"
	client.service_retry_at = Time.get_ticks_msec() / 1000.0 + 8
	await settle()
	check(lobby.action_buttons.all(func(button):return button.disabled) and lobby.status_label.text.contains("秒"), "Disconnected page locks network actions and displays the automatic retry countdown")
	root.get_texture().get_image().save_png(directory + "lobby-retrying.png")
	var failures = checks.filter(func(row):return not row["passed"])
	var file = FileAccess.open(directory + "lobby-layout.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures}, "  "))
	file.close()
	print("LOBBY_LAYOUT ", checks.size(), " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
