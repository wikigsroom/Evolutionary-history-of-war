extends SceneTree

var app
var director
var destination = ""
var screenshots = ""
var rows = []

func _initialize() -> void:
	call_deferred("run")

func settle(count: int = 5) -> void:
	for i in range(count):
		await process_frame
	await RenderingServer.frame_post_draw

func capture(name: String, context: Dictionary = {}) -> void:
	await settle(2)
	var image = root.get_texture().get_image()
	var file = screenshots.path_join(name+".png")
	var error = image.save_png(file)
	if error != OK:
		push_error("Screenshot write failed: "+file)
		quit(1)
		return
	context.merge({"file":name+".png","size":[image.get_width(),image.get_height()],"source":"unmodified native viewport from the released Windows embedded PCK"},true)
	rows.append(context)
	print("MARKETING_SCREEN ",name," ",JSON.stringify(context))

func run() -> void:
	destination = OS.get_environment("EPOCH_MARKETING_OUTPUT")
	screenshots = OS.get_environment("EPOCH_MARKETING_SCREENSHOTS")
	DirAccess.make_dir_recursive_absolute(screenshots)
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	app = preload("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.store = EpochStore.new(app.model.db,"user://marketing-screenshots-20261008/")
	app.store.profile["loadout"] = app.model.db.default_loadout("H03")
	app.audio.settings = app.store.settings
	app.audio.apply_settings()
	director = load(OS.get_environment("EPOCH_MARKETING_DIRECTOR")).new()
	app.show_menu("home")
	await capture("01-home",{"page":"home"})
	app.show_menu("loadout")
	await capture("02-commander-loadout",{"page":"loadout","hero":"H03"})
	for age in range(1,11):
		var era = "A%d"%age
		app.show_battle({"startingEraId":era,"maximumEraId":era,"seed":84621+age,"loadout":app.model.db.default_loadout("H03"),"aiEnabled":true,"randomEvents":true})
		app.current_view.set_process(false)
		app.current_view.toast_time = 0
		app.current_view.toast_label.visible = false
		director.attach(app.model,false,false)
		await settle()
		var best_score = -1.0
		var best_image: Image
		var best_state = {}
		while app.model.tick < 84*30 and app.model.winner == -1:
			director.update()
			app.model.step_ticks(4)
			app.current_view._refresh_hud()
			app.current_view.world.jump("front")
			await process_frame
			if app.model.tick >= 44*30 and app.model.tick%12==0:
				var fighting = app.model.living(-1,false).filter(func(u):return u["phase"]=="windup" or u["phase"]=="recover").size()
				var score = float(app.model.living(-1,false).size()) + fighting*1.8 + minf(80,app.current_view.world.effects.effects.size())*0.04
				if score > best_score:
					await RenderingServer.frame_post_draw
					best_score = score
					best_image = root.get_texture().get_image()
					best_state = director.battle_state()
		if best_image == null:
			await RenderingServer.frame_post_draw
			best_image = root.get_texture().get_image()
			best_state = director.battle_state()
		var name = "%02d-era-%02d"%[age+2,age]
		var error = best_image.save_png(screenshots.path_join(name+".png"))
		if error != OK:
			push_error("Cannot save era screenshot")
			quit(1)
			return
		best_state.merge({"file":name+".png","size":[best_image.get_width(),best_image.get_height()],"startingEraId":era,"maximumEraId":era,"hero":"H03","score":best_score,"actions_file":"actions-era-%02d.json"%age,"source":"native same-era practice; normal paid recruitment and production AI; no injected units or resources"},true)
		rows.append(best_state)
		FileAccess.open(destination+"/actions-era-%02d.json"%age,FileAccess.WRITE).store_string(JSON.stringify(director.actions,"\t"))
		print("MARKETING_SCREEN ",name," ",JSON.stringify(best_state))
	var report = {"version":ProjectSettings.get_setting("application/config/version"),"screenshots":rows,"count":rows.size(),"source":"Windows release embedded PCK, native GPU-rendered 1920x1080 viewport","simulation":"Still capture can advance simulation ticks between renders; screenshots are never AI-generated or painted."}
	FileAccess.open(destination+"/screenshots-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	app.queue_free()
	await process_frame
	quit(0 if rows.size()==12 else 1)
