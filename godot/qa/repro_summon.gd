extends SceneTree
func _initialize() -> void:
	var m=GameModel.new();m.reset_battle({"heroEnabled":false,"aiEnabled":false,"loadout":EpochData.new().default_loadout("H04")})
	var hero=m.spawn(0,"H04","A1","hero",600.0)
	hero["yield"]={"from":600.0,"to":500.0,"at":0,"duration":30}
	m.sides[0]["command"]=110
	var result=m.act({"type":"cast","skillId":"HS04","x":700.0})
	var deployed=m.living(0,false).filter(func(u):return u["kind"]=="summon")
	if not deployed.is_empty():
		var cannon=deployed[0];var origin=float(cannon["x"]);var inherited=cannon.has("yield")
		m.step_ticks(1)
		print(JSON.stringify({"cast":result,"spawn_x":origin,"after_one_tick":cannon["x"],"inherited_hero_yield":inherited}))
	m.free();quit()
