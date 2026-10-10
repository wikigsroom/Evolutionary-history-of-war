extends SceneTree

const NetProjection = preload("res://server/network_projection.gd")
const Router = preload("res://server/command_router.gd")
var checks = []
var failures = 0

func _initialize() -> void: call_deferred("run")
func expect(value: bool, label: String) -> void:
	checks.append({"name":label,"passed":value})
	if not value: failures += 1; push_error(label)

func run() -> void:
	for difficulty in ["D01","D02","D03"]:
		var m = GameModel.new(); root.add_child(m)
		m.reset_battle({"mode":"online","difficultyId":difficulty,"controlTypes":["human","human"],"aiEnabled":false,"randomEvents":false,"loadout":m.db.default_loadout("H03"),"enemyLoadout":m.db.default_loadout("H03")})
		expect(m.sides[0]["gold"] == m.sides[1]["gold"] and m.sides[1]["gold"] == 240, "Equal human initial gold " + difficulty)
		m.step_ticks(300)
		expect(is_equal_approx(float(m.sides[0]["gold"]),float(m.sides[1]["gold"])), "Equal human income " + difficulty)
		expect(m.sides[0]["queue"].is_empty() and m.sides[1]["queue"].is_empty(), "No AI actions " + difficulty)
		m.free()
	var m = GameModel.new(); root.add_child(m)
	m.reset_battle({"mode":"online","controlTypes":["human","human"],"aiEnabled":false,"randomEvents":false,"heroEnabled":false})
	expect(Router.validate(m,{"type":"evolve","upgradeId":"R101"},0)=="INVALID_UPGRADE", "Wrong-era upgrade rejected before spending")
	expect(Router.validate(m,{"type":"train","unitId":"U11","side":1},0)=="INVALID_FIELD", "Untrusted side rejected")
	expect(Router.validate(m,{"type":"restore","hp":999999},0)=="INVALID_ACTION", "No authority setters")
	expect(Router.validate(m,{"type":"cast","skillId":"S01","x":INF},0)=="INVALID_TARGET", "Nonfinite target rejected")
	for side in range(2):
		expect(m.act({"type":"train","unitId":"U11","side":side})["ok"], "Both human sides can recruit")
	var projections = [NetProjection.make(m,0,m.consume_events()),NetProjection.make(m,1,[])]
	for side in range(2):
		expect(not projections[side]["enemy"].has("gold") and not projections[side]["enemy"].has("queue") and not projections[side]["enemy"].has("cooldowns"), "Enemy private state absent side %d" % side)
		var replica = OnlineBattleState.new(); root.add_child(replica)
		replica.match_id = "qa"; replica.mark_connection(true,"qa")
		expect(replica.apply_projection(projections[side],true), "Projection renders without full restore side %d" % side)
		expect(replica.base(0)["side"]==0 and is_equal_approx(float(replica.base(0)["x"]),80.0), "Own capital left for both seats %d" % side)
		expect(replica.sides[0]["queue"].size()==1, "Own private queue visible side %d" % side)
		var before=replica.sides[0]["gold"];var tick=replica.tick
		replica.advance(1.0)
		expect(replica.tick==tick and replica.sides[0]["gold"]==before,"Replica never simulates money or combat side %d"%side)
		replica.set_paused(true)
		expect(not replica.paused,"Local popup cannot pause online side %d"%side)
		var clicked = {"type":"item","itemId":"smoke-bomb","x":250.0}
		var canonical=BattlePerspective.server_action(clicked,side)
		expect(is_equal_approx(float(canonical["x"]),250.0 if side==0 else 1350.0),"Aim maps to server world side %d"%side)
		replica.free()
	m.sides[0]["knowledge"]=m.era_cost(0);m.base(0)["hp"]=100
	var enemy=m.base(1).duplicate(true)
	expect(m.act({"type":"evolve","side":0,"upgradeId":"R21"})["ok"],"PvP evolution allowed with own experience")
	expect(m.base(0)["hp"]==m.base(0)["maxHp"] and m.base(1)==enemy,"Own capital heals; opposite capital independent")
	var legacy=m.snapshot();var restored=GameModel.new();root.add_child(restored)
	expect(restored.restore(legacy),"Human controls survive snapshot")
	expect(not restored.side_is_ai(1),"Restored right side remains human")
	m.free();restored.free()
	var credentials=SessionCredentials.new();root.add_child(credentials)
	var key=await credentials.installation_key("http://127.0.0.1:8787/qa-identity")
	expect(key.length()==64,"Windows DPAPI creates a CSPRNG credential")
	var same=await credentials.installation_key("http://127.0.0.1:8787/qa-identity")
	expect(same==key and not key.is_empty(),"Windows DPAPI restores the same identity")
	credentials.free()
	var directory=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("output/qa/online")
	DirAccess.make_dir_recursive_absolute(directory)
	var file=FileAccess.open(directory.path_join("core-contract.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failures},"\t",true,true));file.close()
	print("ONLINE_CORE: %d checks, %d failures"%[checks.size(),failures])
	quit(0 if failures==0 else 1)
