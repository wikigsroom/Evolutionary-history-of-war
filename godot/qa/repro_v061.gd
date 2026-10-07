extends SceneTree
var app
var output = "res://../output/qa/godot-fixes/"
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
func click(point: Vector2, touch: bool = false) -> void:
	for pressed in [true,false]:
		if touch:
			var e=InputEventScreenTouch.new();e.index=0;e.position=point;e.pressed=pressed;Input.parse_input_event(e)
		else:
			var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;Input.parse_input_event(e)
		await process_frame
	await settle()
func run() -> void:
	root.size=Vector2i(1280,720)
	app=preload("res://scenes/Main.tscn").instantiate();root.add_child(app);await settle()
	app.store=EpochStore.new(app.model.db,"user://qa-v061-repro/")
	app.audio.settings=app.store.settings
	var reports=[]
	for touch in [false,true]:
		app.show_battle({"aiEnabled":false});await settle()
		var m=app.model;var view=app.current_view
		m.sides[0]["gold"]=800;m.sides[0]["command"]=20
		m.act({"type":"train","unitId":"U11"})
		var enemy=m.spawn(1,"U11","A1","unit",700.0);enemy["speed"]=0
		await settle()
		for id in ["war-drum","smoke-bomb","chrono-crate"]:
			var before=m.sides[0]["activeItems"].duplicate(true)
			await click(view.item_cards[id].get_global_rect().get_center(),touch)
			var armed=view.target_action.duplicate(true)
			if id=="smoke-bomb":await click(Vector2(700.0*view.world.world_scale,view.world.ground-35),touch)
			m.step_ticks(2);await settle()
			reports.append({"touch":touch,"item":id,"before":before,"after":m.sides[0]["activeItems"].duplicate(true),"armed":armed,"fields":m.fields.duplicate(true),"enemy_statuses":enemy["statuses"].duplicate(true),"hero_statuses":m.hero(0)["statuses"].duplicate(true)})
		root.get_texture().get_image().save_png(output+"baseline-items-%s.png"%("touch" if touch else "mouse"))
	var file=FileAccess.open(output+"baseline-items.json",FileAccess.WRITE);file.store_string(JSON.stringify(reports,"\t"));file.close()
	for report in reports:print(JSON.stringify({"item":report["item"],"touch":report["touch"],"after":report["after"],"armed":report["armed"],"fields":report["fields"].size()}))
	app.queue_free();await process_frame;quit()
