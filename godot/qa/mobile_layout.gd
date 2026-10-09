extends SceneTree
var failures = []
var samples = []
var directory = "res://../output/qa/mobile-layout/"
var app
var checks = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label);push_error(label)
func settle() -> void:
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
func tap(control: Control) -> void:
	for pressed in [true,false]:
		var event=InputEventScreenTouch.new()
		event.position=control.get_global_rect().get_center();event.index=0;event.pressed=pressed
		root.push_input(event,true)
		await process_frame
	await settle()
func run() -> void:
	directory=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("output/qa/mobile-layout/")
	var custom_output=OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	if not custom_output.is_empty():directory=custom_output.trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(directory)
	check(ProjectSettings.get_setting("display/window/stretch/aspect")=="expand","actual project uses expand")
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	var mapped=SafeUI.physical_to_logical(Rect2(145,50,2280,1050),Transform2D(Vector2(1.5,0),Vector2(0,1.5),Vector2(100,50)),Rect2(0,0,1600,720))
	check(mapped.is_equal_approx(Rect2(30,0,1520,700)),"physical safe area converts including window offset and scale")
	app=preload("res://scenes/Main.tscn").instantiate();root.add_child(app)
	await settle()
	app.store=EpochStore.new(app.model.db,"user://qa-mobile-layout/")
	for dimensions in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(2400,1080),Vector2i(1680,720),Vector2i(1280,960)]:
		root.size=dimensions
		await settle()
		var logical=root.get_visible_rect().size
		check(is_equal_approx(logical.x/logical.y,float(root.size.x)/root.size.y),"viewport fills %s"%dimensions)
		for page in ["home","campaign","loadout","encyclopedia","settings"]:
			app.show_menu(page)
			app.current_view.safe_ui.test_insets=Vector4(32,0,24,12)
			await settle()
			var safe=app.current_view.safe_ui
			check(safe.get_global_rect().position.x>=31.9,"menu inset %s %s"%[dimensions,page])
			check(safe.get_global_rect().end.x<=logical.x-23.9,"menu right inset")
			root.get_texture().get_image().save_png(directory+"%dx%d-%s.png"%[dimensions.x,dimensions.y,page])
		app.show_battle()
		var battle=app.current_view
		battle.safe_ui.test_insets=Vector4(32,0,24,12)
		await settle()
		check(battle.world.size.is_equal_approx(logical),"world fills screen")
		var deck=battle.find_child("BattleDeck",true,false)
		check(battle.safe_ui.get_global_rect().encloses(deck.get_global_rect()),"deck contained in safe area")
		check(not battle.world._uncovered(battle.commander.get_global_rect().get_center()),"touch blocker follows scaled HUD")
		await tap(battle.commander)
		check(is_instance_valid(battle.tray),"touch opens commander tray within transformed safe UI")
		battle._close_tray()
		await tap(battle.unit_cards[0])
		check(not app.model.sides[0]["queue"].is_empty(),"touch recruits through transformed safe UI")
		var x=battle.world.screen_to_world(logical.x*0.61)
		check(is_equal_approx(battle.world.world_to_screen(x),logical.x*0.61),"field aim roundtrip")
		root.get_texture().get_image().save_png(directory+"%dx%d-battle.png"%[dimensions.x,dimensions.y])
		battle._research_menu();await settle()
		check(battle.safe_ui.get_global_rect().encloses(battle.overlay.get_global_rect()),"modal safe bounds")
		root.get_texture().get_image().save_png(directory+"%dx%d-research.png"%[dimensions.x,dimensions.y])
		samples.append({"window":str(root.size),"viewport":str(logical),"safe":str(battle.safe_ui.get_global_rect())})
	FileAccess.open(directory+"report.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"samples":samples},"\t"))
	print("MOBILE_LAYOUT ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"samples":samples}))
	quit(0 if failures.is_empty() else 1)
