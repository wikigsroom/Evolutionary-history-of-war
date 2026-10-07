extends SceneTree

var app
var directory=""
var reports=[]
var failures=[]

func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
func check(value: bool, description: String) -> void:
	if not value:failures.append(description);push_error(description)
func capture(name: String) -> void:
	await settle()
	root.get_texture().get_image().save_png(directory+"/"+name+".png")
func run() -> void:
	directory=OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	if directory.is_empty():directory=ProjectSettings.globalize_path("res://../output/qa/ten-eras/transitions")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size=Vector2i(1280,720)
	app=preload("res://scenes/Main.tscn").instantiate();root.add_child(app);await settle()
	app.store=EpochStore.new(app.model.db,"user://qa-ten-era-transition/")
	app.model.set_process(false)
	for identity in range(1,7):
		var hero_id="H0"+str(identity)
		app.show_battle({"aiEnabled":false,"randomEvents":false,"seed":7621+identity,
			"loadout":app.model.db.default_loadout(hero_id),"enemyLoadout":app.model.db.default_loadout(hero_id)})
		var m=app.model
		for side in range(2):
			var hero=m.hero(side);hero["x"]=390.0 if side==0 else 1210.0;hero["previousX"]=hero["x"]
			hero["hp"]=float(hero["maxHp"])*.65
		app.current_view.world.focus_world(800)
		for age in range(1,11):
			if age>1:
				var before_enemy=m.enemy_era
				var old_serial=int(m.environment.scene["serial"])
				m.sides[0]["knowledge"]=m.era_cost(0)
				check(m.act({"type":"evolve","side":0})["ok"],hero_id+": allied evolution "+str(age))
				check(m.enemy_era==before_enemy,hero_id+": enemy remains independent "+str(age))
				check(int(m.environment.scene["serial"])==old_serial+1,hero_id+": allied map change "+str(age))
				var old_variant=m.environment.scene["variant"]
				m.sides[1]["knowledge"]=m.era_cost(1)
				check(m.act({"type":"evolve","side":1})["ok"],hero_id+": enemy evolution "+str(age))
				check(m.ally_era==age,hero_id+": allied remains independent "+str(age))
				check(int(m.environment.scene["serial"])==old_serial+2 and m.environment.scene["variant"]!=old_variant,hero_id+": enemy map change "+str(age))
			# Advance presentation time without moving the display fixtures into combat.
			m.tick+=45
			await capture("%s-age-%02d"%[hero_id,age])
			for side in range(2):
				var hero=m.hero(side)
				var expected=hero_id+"-A"+str(age)
				var view=app.current_view.world.actor_nodes.get(hero["id"])
				check(view!=null and view.current_visual==expected and view.sprite.texture!=null,"Native commander texture "+expected+" side "+str(side))
				check(absf(float(hero["hp"])/float(hero["maxHp"])-.65)<.005,"Native commander HP ratio "+expected)
				reports.append({"form":expected,"side":side,"visual":view.current_visual,"texture":view.sprite.texture.resource_path,"hpRatio":float(hero["hp"])/float(hero["maxHp"]),"attack":hero["attack"],"skill":m.db.hero_form(hero_id,hero["eraId"])["signatureName"]})
		m.paused=true
		m.set_process(true)
		var tick=m.tick
		await settle()
		var render_tick=app.current_view.world.render_tick
		await create_timer(.15).timeout
		check(m.tick==tick and app.current_view.world.render_tick==render_tick,"Pause freezes live simulation and ambient "+hero_id)
		check(app.current_view.world.actor_nodes.values().all(func(v):return v.player.speed_scale==0.0),"Pause freezes actor timelines "+hero_id)
		m.set_process(false)
	FileAccess.open(directory+"/native-transition-report.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"formsRendered":reports.size(),"forms":reports,"failures":failures},"\t"))
	print("NATIVE COMMANDER TRANSITIONS: ",reports.size()," palette forms; failures ",JSON.stringify(failures))
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
