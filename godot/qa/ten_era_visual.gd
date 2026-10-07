extends SceneTree

var app
var directory = ""
var report = []
var failure_count = 0

func _initialize() -> void: call_deferred("run")

func settle(frames: int = 5) -> void:
	for i in range(frames): await process_frame
	await RenderingServer.frame_post_draw

func capture(name: String) -> void:
	await settle(2)
	root.get_texture().get_image().save_png(directory+"/"+name+".png")

func advance(ticks: int) -> void:
	for i in range(ticks):
		app.model.step_ticks(1)
		await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	directory = OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	if directory.is_empty(): directory = ProjectSettings.globalize_path("res://../output/qa/ten-eras/native")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size=Vector2i(1280,720)
	app=preload("res://scenes/Main.tscn").instantiate();root.add_child(app)
	await settle()
	app.store=EpochStore.new(app.model.db,"user://qa-ten-era-visual/")
	app.audio.settings=app.store.settings;app.audio.apply_settings()
	app.model.set_process(false)
	var selected = OS.get_environment("EPOCH_RUSH_QA_ERA")
	for age in range(1,11):
		if not selected.is_empty() and age!=int(selected): continue
		var era="A"+str(age)
		app.show_battle({"aiEnabled":false,"randomEvents":false,"startingEraId":era,"seed":4921+age,
			"loadout":app.model.db.default_loadout("H0%d"%((age-1)%6+1))})
		var m=app.model
		for side in range(2):
			var hero=m.hero(side);hero["x"]=230.0 if side==0 else 1370.0;hero["previousX"]=hero["x"]
			m.sides[side]["research"]["heavy-unlock"]=1;m.sides[side]["gold"]=1500*float(m.db.era(era)["costMultiplier"])
			m.sides[side]["knowledge"]=m.era_cost(side)+float(m.db.age_special(era)["cost"])+500
			m.sides[side]["command"]=100.0
			var cursor=750.0 if side==0 else 825.0
			var previous_radius=0.0
			for slot in [1,3,4,2,5]:
				var content="U%d%d"%[age,slot]
				var radius=float(m.db.profile(content)["radius"])
				if previous_radius>0:cursor+=(previous_radius+radius+8.0)*(-1.0 if side==0 else 1.0)
				m.spawn(side,content,era,"unit",cursor)
				previous_radius=radius
		await settle()
		app.current_view.world.focus_world(800)
		await advance(12)
		await capture("age-%02d-field"%age)
		var variants=[]
		for variant in range(1,4):
			m.environment.scene["variant"]=variant;m.environment.scene["serial"]+=1;m.environment.scene["changedAt"]=m.tick-90
			await capture("age-%02d-map-%d"%[age,variant])
			var path="res://assets/environment/eras/%s-%d.png"%[era,variant]
			variants.append({"variant":variant,"loaded":PixelTheme.texture(path)!=null,"renderedPath":app.current_view.world.current_background,"correctPath":path==app.current_view.world.current_background})
		var cast=m.act({"type":"ageSpecial","side":0,"x":870.0})
		await advance(23)
		app.current_view.world.jump("ally")
		await capture("age-%02d-launch-camp"%age)
		app.current_view.world.focus_world(800)
		await capture("age-%02d-flight"%age)
		var carrier_checks=[]
		for side in range(2):
			var effects=app.current_view.world.effects
			var pose=effects.raid_carrier_pose(Vector2(870.0*effects.ratio,effects.ground-18),{"eraId":era,"side":side,"fromX":m.BASE_POSITIONS[side]*effects.ratio,"warning":1.15},0.77)
			var grounded=age not in [7,10]
			carrier_checks.append({"side":side,"grounded":pose["grounded"],"correctType":pose["grounded"]==grounded,"groundContact":absf(float(pose["contactY"])-effects.ground)<0.01 if grounded else Vector2(pose["center"]).y<effects.ground-150*effects.ratio})
		await advance(18)
		await capture("age-%02d-impact"%age)
		var base_hp=float(m.base(0)["hp"])
		var event_kind=["dinosaur","meteor","rockfall","storm","rockfall","plane","plane","plane","drone","debris"][age-1]
		m.environment.spawn_event(event_kind,760.0,era)
		await advance(48)
		await capture("age-%02d-random-event"%age)
		await advance(25)
		await capture("age-%02d-random-impact"%age)
		var actors=[]
		for actor in app.current_view.world.actor_nodes.values():
			actors.append({"id":actor.current_visual,"textureLoaded":actor.sprite.texture!=null})
		var state=m.environment.scene
		var background="res://assets/environment/eras/%s-%d.png"%[era,int(state["variant"])]
		var ambient_loaded=app.current_view.world.ambient_items.all(func(i):return PixelTheme.texture("res://assets/environment/ambient/"+i["kind"]+".png")!=null)
		var item={"age":age,"map":background,"mapLoaded":PixelTheme.texture(background)!=null,"raidCast":cast["ok"],"ambientLoaded":ambient_loaded,"eventKind":event_kind,
			"actors":actors,"maps":variants,"carriers":carrier_checks,"baseUnaffectedByNeutralEvent":absf(float(m.base(0)["hp"])-base_hp)<0.1,"cuesMissing":app.audio.stats["missing"],"effectsBounded":app.current_view.world.effects.effects.size()<=420}
		report.append(item)
		if not item["mapLoaded"] or not item["raidCast"] or not item["ambientLoaded"] or not item["effectsBounded"] or not item["baseUnaffectedByNeutralEvent"] or item["cuesMissing"]!=0 or not actors.all(func(a):return a["textureLoaded"]) or not variants.all(func(v):return v["loaded"] and v["correctPath"]) or not carrier_checks.all(func(c):return c["correctType"] and c["groundContact"]): failure_count+=1
		print("NATIVE AGE ",age," ",JSON.stringify(item))
	FileAccess.open(directory+"/native-visual-report.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":failure_count==0,"eras":report},"\t"))
	app.queue_free();await process_frame
	quit(1 if failure_count else 0)
