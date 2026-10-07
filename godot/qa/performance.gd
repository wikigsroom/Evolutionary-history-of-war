extends SceneTree
var app
var samples=[]
var frame=0
var previous=0
var stage=0
var frames=[]
var cpu_samples=[]
var longest_frame={}
func _initialize() -> void:call_deferred("start")
func start() -> void:
	root.size=Vector2i(1280,720)
	app=preload("res://scenes/Main.tscn").instantiate();root.add_child(app)
	app.store=EpochStore.new(app.model.db,"user://qa-performance/")
	fixture(24)
	previous=Time.get_ticks_usec();process_frame.connect(update)
func fixture(amount: int) -> void:
	app.show_battle({"aiEnabled":false,"heroEnabled":false,"startingEraId":"A10","randomEvents":false})
	var m=app.model
	var cursor=148.0
	for i in range(amount):
		var content="U102" if amount==24 and i==23 else "U10%d"%(i%5+1);var side=0 if i<amount/2 else 1
		var radius=float(m.db.profile(content)["radius"])
		var x=cursor+radius if amount==24 else 180.0+i*1250.0/amount
		var u=m.spawn(side,content,"A10","unit",x)
		cursor=x+radius+4.0
		u["speed"]=0.0
	app.current_view.world.focus_world(800.0)
	app.current_view.toast_time=0;app.current_view.toast_label.visible=false
func update() -> void:
	frame+=1
	var now=Time.get_ticks_usec();var ms=(now-previous)/1000.0;previous=now
	if frame>60:
		samples.append(ms);cpu_samples.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		if longest_frame.is_empty() or ms>float(longest_frame["ms"]):longest_frame={"frame":frame,"ms":ms,"reported_process_monitor_ms":cpu_samples[-1],"simulation_tick":app.model.tick,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	if frame%2==0:
		var world=app.current_view.world
		world.effects.particles(400+(frame*19)%450,world.ground-50,PixelTheme.AMBER,12,frame)
	if frame%120==0:
		# Deliberately overlap real raid casts for rendering stress; ordinary matches retain cooldowns.
		for side in range(2):
			app.model.sides[side]["knowledge"]=100000.0
			app.model.sides[side]["ageSpecialReadyAt"]=0
			app.model.abilities.use_age(side,800.0)
	if frame in [660,1260]:
		samples.sort()
		cpu_samples.sort()
		var visible_actors=0;var world=app.current_view.world
		for actor in app.model.living(-1,false):
			if float(actor["x"])>=world.camera_x and float(actor["x"])<=world.camera_x+world.visible_width:visible_actors+=1
		var report={"actors":24 if stage==0 else 60,"visible_actors":visible_actors,"camera_x":world.camera_x,"visible_world_width":world.visible_width,"kind":"representative" if stage==0 else "synthetic_render_stress","frames":samples.size(),"p50_ms":samples[int(samples.size()*.5)],"p95_ms":samples[int(samples.size()*.95)],"max_ms":samples[-1],"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"static_memory_mib":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0}
		report["era"]="A10";report["living_actors"]=app.model.living(-1,false).size();report["repeated_raids_are_synthetic_stress"]=true
		# Built-in monitor readings are snapshots; use wall-clock intervals for frame budgets.
		report["process_monitor_snapshot_p95_ms"]=cpu_samples[int(cpu_samples.size()*.95)];report["longest_frame"]=longest_frame
		report["includes_scene_setup_interval"]=stage==1
		frames.append(report);print(JSON.stringify(report))
		if frame==660:stage=1;fixture(60);samples=[];cpu_samples=[];longest_frame={};frame=720
		else:
			var output=OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
			if output.is_empty():output=ProjectSettings.globalize_path("res://../output/qa/godot-fixes")
			DirAccess.make_dir_recursive_absolute(output)
			var file=FileAccess.open(output+"/performance.json",FileAccess.WRITE);file.store_string(JSON.stringify(frames,"\t"));file.close();app.queue_free();quit()
