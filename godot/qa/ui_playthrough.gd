extends SceneTree
var app
var failures = []
var directory = "res://../output/qa/godot-polish/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, description: String) -> void:
	if not value: failures.append(description); push_error(description)
func settle() -> void:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	await settle()
	root.get_texture().get_image().save_png(directory + name + ".png")
func key(code: int) -> void:
	var event = InputEventKey.new(); event.keycode = code; event.pressed = true; Input.parse_input_event(event)
	await process_frame
	var release = InputEventKey.new(); release.keycode = code; release.pressed = false; Input.parse_input_event(release)
func click(control: Control) -> void:
	var point = control.get_global_rect().get_center()
	var down = InputEventMouseButton.new(); down.position = point; down.global_position = point; down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; Input.parse_input_event(down)
	await process_frame
	var up = InputEventMouseButton.new(); up.position = point; up.global_position = point; up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; Input.parse_input_event(up)
	await settle()
func run() -> void:
	root.size = Vector2i(1280,720)
	app = preload("res://scenes/Main.tscn").instantiate(); root.add_child(app)
	await settle()
	app.store = EpochStore.new(app.model.db, "user://qa-ui-polish/")
	app.store.profile["cleared"] = []; app.store.profile["wins"] = 0; app.store.profile["unlocked_heroes"] = ["H01","H03"]
	app.show_menu("home")
	await capture("01-home")
	var start = app.current_view.find_child("StartBattle",true,false)
	await click(start)
	check(app.current_view is BattleScreen, "主菜单点击开始进入对战")
	await key(KEY_1); await key(KEY_2); await key(KEY_3)
	check(app.model.sides[0]["queue"].size() >= 2, "键盘真实输入进入招募队列")
	app.model.step_ticks(400)
	await capture("02-battle-scheme1")
	await click(app.current_view.commander)
	check(is_instance_valid(app.current_view.tray), "指挥官头像展开技能托盘")
	await capture("03-commander")
	await key(KEY_ESCAPE)
	app.current_view._research_menu(); await capture("04-research")
	app.current_view._close_modal()
	app.current_view._turret_menu(); await capture("05-turrets")
	app.current_view._close_modal()
	app.model.sides[0]["knowledge"] = 1000.0
	app.current_view._evolve_menu(); await capture("06-evolution-choice")
	var before = app.model.enemy_era
	app.current_view._dispatch({"type":"evolve","upgradeId":"R21"}); app.current_view._close_modal()
	check(app.model.ally_era == 2 and app.model.enemy_era == before, "对战UI进化保持双方时代独立")
	await capture("07-bronze")
	app.current_view._pause_menu(); await capture("08-pause")
	app.store.save_match(app.model.snapshot()); var tick = app.model.tick
	app.show_menu("home"); app.resume_battle()
	check(app.model.tick >= tick and app.model.tick < tick + 10, "继续对局恢复真实进度")
	app.show_menu("campaign"); await capture("09-campaign")
	app.show_menu("loadout"); await capture("10-loadout")
	app.show_menu("encyclopedia"); await capture("11-encyclopedia")
	app.show_menu("settings"); await capture("12-settings")
	var file = FileAccess.open(directory + "ui-checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"screenshots":12,"viewport":[1280,720]},"\t"));file.close()
	print("UI_PLAYTHROUGH ",JSON.stringify(failures))
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
