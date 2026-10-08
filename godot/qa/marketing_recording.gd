extends SceneTree

var app
var director
var frame = 0
var destination = ""
var samples = []
var battle_started = false
var finishing = false

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	destination = OS.get_environment("EPOCH_MARKETING_OUTPUT")
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	app = preload("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.store = EpochStore.new(app.model.db,"user://marketing-recording-20261008/")
	app.store.profile["loadout"] = app.model.db.default_loadout("H03")
	app.store.profile["loadout"]["commonSkillIds"] = ["S06","S07"]
	app.audio.settings = app.store.settings
	app.audio.apply_settings()
	director = load(OS.get_environment("EPOCH_MARKETING_DIRECTOR")).new()
	app.show_menu("home")
	process_frame.connect(update)

func update() -> void:
	if finishing:
		return
	frame += 1
	if frame == 90:
		app.show_menu("loadout")
	if frame == 150:
		app.show_menu("encyclopedia")
	if frame == 165:
		var era_button = find_button(app.current_view,"中世纪王国")
		if era_button != null:
			era_button.pressed.emit()
	if frame == 210:
		app.show_battle({"startingEraId":"A4","seed":781726,"loadout":app.store.profile["loadout"].duplicate(true),"aiEnabled":true,"randomEvents":true,"difficultyId":"D02"})
		director.attach(app.model,true,true)
		battle_started = true
		app.current_view.world.jump("ally")
	if battle_started and app.model.winner == -1:
		director.update()
		if frame == 240:
			director.dispatch({"type":"stance","stance":"rush"})
		if frame == 570:
			app.current_view.world.jump("front")
		if frame == 1450:
			app.current_view._toggle_tray()
		if frame == 1540:
			app.current_view._close_tray()
		if frame == 2150:
			app.current_view.world.jump("ally")
		if frame == 2250:
			app.current_view.world.jump("front")
		if frame%30 == 0:
			var state = director.battle_state()
			state["video_time"] = float(frame)/30.0
			samples.append(state)
	if frame == 1800 or frame == 2700:
		print("MARKETING_RECORD_PROGRESS frame=",frame," state=",JSON.stringify(director.battle_state()))
	if frame >= 3601:
		finishing = true
		process_frame.disconnect(update)
		var report = {"frames":frame,"fps":30,"target_seconds":120,"source":"native Windows release embedded PCK; continuous uncut capture","control":"automated legal model.act commands; normal economy, normal training, production opponent AI; no injected money, XP or entities","menus_seconds":7,"startingEraId":"A4","battle":director.battle_state(),"samples":samples,"actions":director.actions,"audio_missing":app.audio.stats["missing"]}
		FileAccess.open(destination+"/recording-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		app.queue_free()
		await process_frame
		quit()

func find_button(node: Node, text: String):
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found = find_button(child,text)
		if found != null:
			return found
	return null
