extends SceneTree

var app
var director
var frame = 0
var scene_index = -1
var local_frame = 0
var destination = ""
var clips = []
var current_clip = {}
var ages = [1,2,3,4,5,6,7,8,9,10]
var finishing = false

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	destination = OS.get_environment("EPOCH_MARKETING_OUTPUT")
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	app = preload("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.store = EpochStore.new(app.model.db,"user://marketing-showcase-20261008/")
	app.store.settings["music"] = false
	app.audio.settings = app.store.settings
	app.audio.apply_settings()
	director = load(OS.get_environment("EPOCH_MARKETING_DIRECTOR")).new()
	process_frame.connect(update)

func begin_scene() -> void:
	scene_index += 1
	local_frame = 0
	var era = "A%d"%ages[scene_index]
	var loadout = app.model.db.default_loadout("H03")
	loadout["commonSkillIds"] = ["S06","S07"]
	app.show_battle({"startingEraId":era,"maximumEraId":era,"seed":84621+ages[scene_index],"loadout":loadout,"aiEnabled":true,"randomEvents":true})
	app.current_view.set_process(false)
	app.current_view.toast_time = 0
	app.current_view.toast_label.visible = false
	director.attach(app.model,false,false)
	current_clip = {"era":era,"hero":"H03","scene_index":scene_index,"frame_start":frame,"starting_seed":84621+ages[scene_index]}

func update() -> void:
	if finishing:
		return
	frame += 1
	if scene_index < 0:
		begin_scene()
	local_frame += 1
	if local_frame <= 84:
		# Pre-roll only: normal paid commands, accelerated simulation preparation.
		# These frames are explicitly excluded from all trailer edit ranges.
		director.update()
		app.model.step_ticks(30)
		app.current_view._refresh_hud()
		app.current_view.world.jump("front")
	elif local_frame <= 84+270:
		if local_frame == 85:
			current_clip["normal_frame_start"] = frame
			current_clip["normal_start_seconds"] = float(frame-1)/30.0
			current_clip["initial_battle"] = director.battle_state()
			director.dispatch({"type":"item","itemId":"war-drum"})
			director.dispatch({"type":"item","itemId":"smoke-bomb","x":850.0})
		if local_frame == 114:
			var enemies = app.model.living(1,false)
			if not enemies.is_empty():
				var target = enemies.reduce(func(a,b):return a if float(a["x"])<float(b["x"]) else b)
				current_clip["raid"] = director.dispatch({"type":"ageSpecial","x":float(target["x"])+50})
		director.update()
		app.model.step_ticks(1)
		app.current_view._refresh_hud()
		app.current_view.world.jump("front")
	else:
		current_clip["normal_duration"] = 9.0
		current_clip["normal_frame_end_exclusive"] = frame
		current_clip["final_battle"] = director.battle_state()
		current_clip["successful_actions"] = director.actions.size()
		clips.append(current_clip.duplicate(true))
		print("MARKETING_CLIP ",JSON.stringify(current_clip))
		if scene_index >= ages.size()-1:
			finishing = true
			process_frame.disconnect(update)
			FileAccess.open(destination+"/showcase-report.json",FileAccess.WRITE).store_string(JSON.stringify({"frames":frame,"fps":30,"clips":clips,"source":"Native rendering of Windows embedded release PCK; normal-rate 9-second clips after excluded accelerated pre-roll; no injected troops or resources","audio_missing":app.audio.stats["missing"]},"\t"))
			app.queue_free()
			await process_frame
			quit()
		else:
			begin_scene()
