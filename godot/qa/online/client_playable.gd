extends SceneTree

var app
var first: EpochNetClient
var second: EpochNetClient
var checks = []
var directory = ""

func _initialize() -> void:
	directory = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir() + "/output/qa/online/"
	if not OS.get_environment("EPOCH_QA_OUTPUT").is_empty(): directory = OS.get_environment("EPOCH_QA_OUTPUT").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(directory)
	call_deferred("run")

func check(value: bool, title: String) -> void:
	checks.append({"name":title,"passed":value})
	print("CLIENT_CHECK ", checks.size(), " ", value, " ", title)
	if not value: push_error(title)

func wait_for(predicate: Callable, seconds: float = 30.0) -> bool:
	var until = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if predicate.call(): return true
		await process_frame
	return false

func settle() -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw

func capture(name_: String) -> void:
	await settle()
	root.get_texture().get_image().save_png(directory + name_ + ".png")

func controls_inside(node: Node, rectangle: Rect2) -> bool:
	if node is Control and node.is_visible_in_tree() and (node is BaseButton or node is LineEdit):
		if not rectangle.encloses(node.get_global_rect()):
			push_error("Control outside safe layout: " + str(node.get_path()))
			return false
	for child in node.get_children():
		if not controls_inside(child, rectangle): return false
	return true

func run() -> void:
	root.size = Vector2i(1280,720)
	app = preload("res://scenes/Main.tscn").instantiate(); root.add_child(app)
	app.online.queue_free()
	first = EpochNetClient.new(); first.session_directory = "user://qa-online-a-%d/" % Time.get_ticks_usec(); app.add_child(first)
	second = EpochNetClient.new(); second.session_directory = "user://qa-online-b-%d/" % Time.get_ticks_usec(); app.add_child(second)
	app.online = first; first.battle_available.connect(app.show_online_battle)
	await settle()
	first.set_endpoint("http://127.0.0.1:28187"); second.set_endpoint("http://127.0.0.1:28187")
	check(await first.connect_service(), "Native client A authenticates using Windows protected identity")
	check(await second.connect_service(), "Native client B authenticates using separate protected identity")
	check(first.player_id != second.player_id, "Two clients have independent player identities")
	app.show_menu("online"); await capture("native-online-hall")
	check(controls_inside(app.current_view, app.current_view.get_global_rect()), "Hall buttons fit 1280×720 safe layout")
	var code = "%06d" % (randi() % 1000000)
	await first.join_code(code); await second.join_code(code); await first.refresh_activity()
	app.show_menu("online"); await capture("native-online-room")
	check(first.activity.get("room",{}).get("roster",[]).size()==2, "Both native clients occupy the same room")
	var changed = first.loadout.duplicate(true)
	changed["relicIds"] = ["I02", "I04"]
	first.update_loadout(changed)
	changed = changed.duplicate(true); changed["relicIds"] = ["I01", "I04"]
	first.update_loadout(changed)
	check(await wait_for(func():return not first.loadout_dirty and not first.loadout_flushing and first.activity.get("room",{}).get("roster",[]).any(func(row):return row["is_you"] and row["loadout"]["relicIds"]==["I01","I04"]), 12), "Rapid build edits synchronize the latest selection before ready")
	check(controls_inside(app.current_view, app.current_view.get_global_rect()), "Room buttons fit 1280×720 safe layout")
	for size_ in [Vector2i(1600,720), Vector2i(2400,1080)]:
		root.size = size_; await settle()
		check(controls_inside(app.current_view, app.current_view.get_global_rect()), "Room fits long screen %s" % size_)
	root.size = Vector2i(1280,720)
	await first.room_ready(true); await second.refresh_activity(); await second.room_ready(true)
	check(await wait_for(func():return first.battle_state != null and second.battle_state != null and first.battle_state.connected and second.battle_state.connected and not first.battle_state.paused and not second.battle_state.paused), "Both native Godot clients enter one authoritative battle")
	if not app.current_view is BattleScreen:
		print("CLIENT_DEBUG ",JSON.stringify({"first_status":first.status,"second_status":second.status,"first_activity":first.activity,"second_activity":second.activity,"first_epoch":first.connection_epoch,"second_epoch":second.connection_epoch,"first_pending_sync":first.syncing,"second_pending_sync":second.syncing}))
		finish(); return
	check(first.battle_state.sides[0]["eraId"]=="A1" and second.battle_state.sides[0]["eraId"]=="A1", "Each client displays its own faction on the left")
	var before_modal = second.battle_state.tick
	app.current_view._pause_menu()
	await create_timer(0.8).timeout
	check(second.battle_state.tick > before_modal + 9 and not first.battle_state.paused, "Online settings overlay leaves the shared battle running")
	app.current_view._close_modal()
	await capture("native-online-battle")
	var button = app.current_view.unit_cards[0]
	button.pressed.emit()
	second.battle_state.act({"type":"train","unitId":"U11"})
	check(await wait_for(func():return first.pending.is_empty() and second.pending.is_empty() and first.battle_state.sides[0]["queue"].size()==1 and second.battle_state.sides[0]["queue"].size()==1, 8), "Battle button and opponent action both recruit through the server")
	var previous_epoch = first.connection_epoch
	first._lose_connection()
	check(await wait_for(func():return first.connection_epoch>previous_epoch and first.battle_state.connected and not first.syncing, 15), "Native client reconnects automatically to the same match")
	check(first.next_seq==2 and first.pending.is_empty(), "Native reconnect keeps command cursor and clears old pending click")
	var original_player = first.player_id
	var original_match = first.match_id
	var original_directory = first.session_directory
	app._clear_view()
	first._lose_connection(); app.remove_child(first); first.queue_free()
	await process_frame
	first = EpochNetClient.new(); first.session_directory = original_directory
	first.battle_available.connect(app.show_online_battle); app.online = first; app.add_child(first)
	app.show_menu("online")
	check(await wait_for(func():return first.battle_state!=null and first.battle_state.connected and not first.syncing, 15), "A fresh client node automatically resumes the saved active match")
	check(first.player_id==original_player and first.match_id==original_match and first.next_seq==2, "Protected identity, original seat and durable cursor survive client restart")
	await first.surrender()
	check(await wait_for(func():return first.finished and second.finished, 8), "Both native clients receive authoritative final result")
	await create_timer(1.8).timeout
	await capture("native-online-result")
	await first.acknowledge_result(); await second.acknowledge_result()
	check(first.activity.get("kind","")=="" and second.activity.get("kind","")=="", "Both native clients can leave result and create another match")
	finish()

func finish() -> void:
	var failed = checks.filter(func(row):return not row["passed"])
	var file = FileAccess.open(directory + "native-client-playable.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failed}, "  ")); file.close()
	print("NATIVE_CLIENT_PLAYABLE %d checks, %d failures" % [checks.size(),failed.size()])
	quit(0 if failed.is_empty() else 1)
