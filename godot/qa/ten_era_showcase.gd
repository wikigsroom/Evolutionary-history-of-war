extends SceneTree

var app
var frame=0
var fixtures=[]
var failures=[]
var output=""

func _initialize() -> void:call_deferred("start")
func start() -> void:
	output=OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	app=preload("res://scenes/Main.tscn").instantiate();root.add_child(app)
	app.store=EpochStore.new(app.model.db,"user://qa-ten-era-showcase/")
	app.audio.settings=app.store.settings;app.audio.apply_settings()
	app.show_menu("home")
	process_frame.connect(update)
func fixture(age: int) -> void:
	var era="A"+str(age)
	var hero_id="H0%d"%((age-1)%6+1)
	app.show_battle({"aiEnabled":false,"randomEvents":false,"startingEraId":era,"seed":63131+age,"loadout":app.model.db.default_loadout(hero_id),"enemyLoadout":app.model.db.default_loadout(hero_id)})
	var m=app.model
	for side in range(2):
		var hero=m.hero(side);hero["x"]=230.0 if side==0 else 1370.0;hero["previousX"]=hero["x"]
		m.sides[side]["research"]["heavy-unlock"]=1;m.sides[side]["knowledge"]=float(m.db.age_special(era)["cost"])+500;m.sides[side]["command"]=110.0
		var cursor=750.0 if side==0 else 825.0
		var previous_radius=0.0
		for slot in [1,3,4,2,5]:
			var id="U%d%d"%[age,slot];var radius=float(m.db.profile(id)["radius"])
			if previous_radius>0:cursor+=(previous_radius+radius+8)*(-1.0 if side==0 else 1.0)
			m.spawn(side,id,era,"unit",cursor);previous_radius=radius
	app.current_view.world.jump("ally")
	fixtures.append({"era":era,"hero":hero_id,"raid":false,"neutral":false,"effectsPeak":0})
func update() -> void:
	frame+=1
	if frame<90:return
	var index=floori(float(frame-90)/480.0)
	if index>=10:
		var report={"passed":failures.is_empty() and fixtures.size()==10,"frames":frame,"fps":60,"source":"Native rendering of shipped Windows embedded PCK with real simulation, animation and audio","eras":fixtures,"failures":failures}
		FileAccess.open(output+"/showcase-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		app.queue_free();quit(0 if report["passed"] else 1);return
	var local=(frame-90)%480
	if local==0:fixture(index+1)
	var m=app.model
	if local==80:app.current_view.world.focus_world(800.0)
	if local==125:
		var result=m.act({"type":"ageSpecial","side":0,"x":870.0})
		fixtures[-1]["raid"]=result["ok"]
		if not result["ok"]:failures.append("Raid failed "+str(index+1))
	if local==290:
		m.environment.spawn_event(["dinosaur","meteor","rockfall","storm","rockfall","plane","plane","plane","drone","debris"][index],760.0)
		fixtures[-1]["neutral"]=true
	var effects=app.current_view.world.effects.effects.size()
	fixtures[-1]["effectsPeak"]=maxi(int(fixtures[-1]["effectsPeak"]),effects)
	if effects>420:failures.append("Particle budget exceeded")
