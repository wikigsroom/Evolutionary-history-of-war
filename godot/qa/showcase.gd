extends SceneTree
var app
var frame = 0
var stage = 0
var report_path = "res://../output/qa/godot-polish/showcase-report.json"
func _initialize() -> void:
	var output = OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	if not output.is_empty(): report_path = output.trim_suffix("/") + "/showcase-report.json"
	call_deferred("start")
func start() -> void:
	root.size=Vector2i(1280,720)
	app=preload("res://scenes/Main.tscn").instantiate();root.add_child(app)
	app.store=EpochStore.new(app.model.db,"user://qa-showcase/")
	app.audio.settings=app.store.settings
	app.audio.apply_settings()
	app.show_menu("home")
	process_frame.connect(update)
func show(age: int, hero_id: String) -> void:
	app.show_battle({"aiEnabled":false,"seed":43271,"startingEraId":"A%d"%age,"loadout":app.model.db.default_loadout(hero_id)})
	var m=app.model
	for side in range(2):
		var hero=m.hero(side);hero["x"]=360.0 if side==0 else 1090.0;hero["previousX"]=hero["x"]
		for slot in range(1,5):
			var x=[650.0,440.0,590.0,515.0][slot-1] if side==0 else [740.0,1000.0,820.0,910.0][slot-1]
			m.spawn(side,"U%d%d"%[age,slot],"A%d"%age,"unit",x)
		m.sides[side]["gold"]=700.0*float(m.db.era(m.sides[side]["eraId"])["costMultiplier"])
		m.sides[side]["knowledge"]=2000.0;m.sides[side]["command"]=110.0
		m.sides[side]["research"]["heavy-unlock"]=1
	if age==4:
		m.hero(0)["x"]=250.0;m.hero(0)["previousX"]=250.0
		m.spawn(1,"U41","A4","unit",390.0)
		m.act({"type":"turret","side":0,"turretId":"TR42","slot":0})
	app.current_view.toast_time=0;app.current_view.toast_label.visible=false
func update() -> void:
	frame+=1
	if frame==90:show(1,"H01")
	elif frame==150:app.current_view.world.jump("front")
	elif frame==180:app.model.abilities.cast(0,"HS01")
	elif frame==240:
		var target=app.model.living(1,false)[0];app.model.abilities.cast(0,"S04",float(target["x"]),int(target["id"]))
	elif frame==300:
		app.current_view.world.jump("ally");app.model.act({"type":"evolve","upgradeId":"R21"})
	elif frame==330:app.model.act({"type":"train","unitId":"U21"});app.model.act({"type":"train","unitId":"U22"})
	elif frame==390:
		app.current_view.world.jump("front");app.model.abilities.use_age(0,800)
	elif frame==480:show(3,"H04")
	elif frame==540:app.model.abilities.cast(0,"HS04",290)
	elif frame==600:app.model.abilities.use_item(0,"war-drum",600)
	elif frame==660:app.model.abilities.use_item(0,"smoke-bomb",820)
	elif frame==720:app.current_view.world.jump("front")
	elif frame==750:show(4,"H04")
	elif frame==840:app.model.abilities.use_age(0,810)
	elif frame==930:show(5,"H05")
	elif frame==945:app.current_view.world.jump("front")
	elif frame==960:app.model.abilities.cast(0,"S06",780)
	elif frame==1050:
		app.model.sides[0]["command"]=110.0;app.model.abilities.cast(0,"S07",780)
	elif frame==1140:app.model.abilities.use_age(0,820)
	elif frame==1200:
		app.model.sides[0]["command"]=110.0;app.model.abilities.cast(0,"HS05",900)
	elif frame==1280:
		var source=app.model.living(0,false)[0];app.model.combat.hit(source,app.model.base(1),50000,"blast",{"canDamageBase":true,"weaponId":"W05"})
	elif frame==1435:
		var file=FileAccess.open(report_path,FileAccess.WRITE)
		file.store_string(JSON.stringify({"frames":frame,"rate":60,"winner":app.model.winner,"coverage":"five eras / melee / arrows / gunfire / cannon / arc / shields / items / evolution / collapse"}));file.close()
		app.queue_free();quit()
