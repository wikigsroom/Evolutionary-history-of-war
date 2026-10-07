extends SceneTree

var app
var directory = ""
var failures = []
var states = []
var transitions = []
var checks = 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func settle() -> void:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw

func alpha_distance(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size(): return INF
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var first = a.get_data(); var second = b.get_data(); var total = 0.0
	for i in range(3, first.size(), 4): total += absf(int(first[i]) - int(second[i]))
	return total / maxf(1, first.size() / 4)

# Infer orientation from original silhouette pixels, independently of era metadata.
func expected_enemy_flip(era: String) -> bool:
	var own = PixelTheme.texture("res://assets/base/"+era+".png").get_image()
	var enemy = PixelTheme.texture("res://assets/base/"+era+"-enemy.png").get_image()
	if own.is_compressed(): own.decompress()
	if enemy.is_compressed(): enemy.decompress()
	var direct = alpha_distance(own, enemy)
	enemy.flip_x()
	return direct < alpha_distance(own, enemy)

func capture(name: String, side: int) -> void:
	app.current_view.world.jump("ally" if side == 0 else "enemy")
	await settle()
	root.get_texture().get_image().save_png(directory+"/"+name+".png")

func run() -> void:
	directory = OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	if directory.is_empty(): directory = ProjectSettings.globalize_path("res://../output/qa/base-facing/source")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280, 720)
	app = preload("res://scenes/Main.tscn").instantiate(); root.add_child(app)
	await settle()
	app.store = EpochStore.new(app.model.db, "user://qa-base-facing-%d/" % Time.get_ticks_usec())
	app.store.settings["reduced_motion"] = true
	app.audio.settings = app.store.settings; app.audio.apply_settings()
	app.model.set_process(false)
	for age in range(1, 11):
		var era = "A"+str(age)
		var expected_flip = expected_enemy_flip(era)
		app.show_battle({"aiEnabled":false, "randomEvents":false, "startingEraId":era, "seed":900+age})
		var model = app.model
		for side in range(2):
			model.sides[side]["gold"] = 100000000.0
			for i in range(2): expect(model.act({"type":"unlockSlot", "side":side})["ok"], era+" unlock tower")
			for slot in range(3):
				expect(model.act({"type":"turret", "side":side, "slot":slot, "turretId":"TR%d%d"%[age, 1+slot%2]})["ok"], era+" build tower")
		model.paused = true
		for entry in [["healthy",1.0,""],["worn",0.5,"-worn"],["critical",0.2,"-critical"],["ruin",0.0,"-ruin"]]:
			for side in range(2):
				var base = model.base(side); base["hp"] = float(base["maxHp"])*float(entry[1]); base["phase"] = "dead" if entry[0]=="ruin" else "idle"
			await settle()
			var views = app.current_view.world.bases
			for side in range(2):
				var view = views[side]
				var expected_path = "res://assets/base/"+era+entry[2]+("-enemy" if side==1 else "")+".png"
				expect(view.current_path==expected_path and view.castle.texture!=null, era+" "+entry[0]+" texture "+str(side))
				expect(view.castle.flip_h==(expected_flip if side==1 else false), era+" "+entry[0]+" inward facing "+str(side))
				for gun in view.turret_nodes.values(): expect(gun.flip_h==(side==1), era+" tower facing "+str(side))
			states.append({"era":era,"state":entry[0],"ownFlip":views[0].castle.flip_h,"enemyFlip":views[1].castle.flip_h,"expectedEnemyFlipFromSilhouette":expected_flip,"ownTexture":views[0].current_path,"enemyTexture":views[1].current_path})
			if entry[0]=="healthy" or age in [1,8]:
				for side in range(2): await capture("%s-%s-%s"%[era,entry[0],"own" if side==0 else "enemy"],side)
	# Exercise an existing enemy base as it switches between both texture conventions.
	app.show_battle({"aiEnabled":false,"randomEvents":false,"seed":420})
	var model = app.model; model.paused = true; model.sides[1]["knowledge"] = 100000000.0
	for age in range(2,11):
		var ok = model.act({"type":"evolve","side":1})["ok"]
		await settle()
		var view = app.current_view.world.bases[1]
		var era = "A"+str(age)
		expect(ok and view.last_era==era, "Enemy base evolution "+era)
		expect(view.castle.flip_h==expected_enemy_flip(era), "Evolved enemy remains inward "+era)
		expect(model.sides[0]["eraId"]=="A1", "Independent ally era during "+era)
		transitions.append({"enemyEra":era,"allyEra":model.sides[0]["eraId"],"flip":view.castle.flip_h})
	var report = {"passed":failures.is_empty(),"checks":checks,"failures":failures,"states":states,"transitions":transitions,"version":ProjectSettings.get_setting("application/config/version")}
	FileAccess.open(directory+"/base-facing.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BASE FACING ", checks-failures.size(), "/", checks, " states=",states.size()," failures=",JSON.stringify(failures))
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
