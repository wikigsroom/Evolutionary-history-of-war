extends SceneTree

var checks = []
var failures = 0

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks.append({"name":label,"passed":value})
	if not value:
		failures += 1
		push_error(label)

func fixture(difficulty: String = "D02", era: String = "A1") -> GameModel:
	var m = GameModel.new()
	m.reset_battle({"difficultyId":difficulty,"startingEraId":era,"aiEnabled":false,"heroEnabled":false,"randomEvents":false})
	return m

func run() -> void:
	for row in [["D01",0.8,0.85],["D02",1.25,1.35],["D03",1.5,1.65]]:
		for age in ["A1","A5","A10"]:
			var m = fixture(row[0],age)
			var ordinary_gold = float(m.db.rules["resources"]["startingGold"]) * float(m.db.era(age)["costMultiplier"])
			expect(is_equal_approx(float(m.sides[0]["gold"]),ordinary_gold),"Player initial gold unchanged "+row[0]+age)
			expect(is_equal_approx(float(m.sides[1]["gold"]),ordinary_gold*row[1]),"Enemy initial gold multiplier "+row[0]+age)
			var starting = [m.sides[0]["gold"],m.sides[1]["gold"]]
			m.step_ticks(300)
			var income = float(m.db.rules["resources"]["goldPerSec"]) * float(m.db.era(age)["incomeMultiplier"])*10.0
			expect(is_equal_approx(float(m.sides[0]["gold"])-starting[0],income),"Player passive income unchanged "+row[0]+age)
			expect(is_equal_approx(float(m.sides[1]["gold"])-starting[1],income*row[2]),"Enemy passive income multiplier "+row[0]+age)
			expect(m.enemy_era==int(age.trim_prefix("A")) and float(m.sides[1]["knowledge"])==0.0,"Economy does not grant experience or automatic era "+row[0]+age)
			var restored = GameModel.new()
			expect(restored.restore(m.snapshot()),"Economy snapshot loads "+row[0]+age)
			expect(is_equal_approx(float(restored.sides[1]["gold"]),float(m.sides[1]["gold"])),"Restore does not reapply starting bonus "+row[0]+age)
			m.step_ticks(30);restored.step_ticks(30)
			expect(is_equal_approx(float(restored.sides[1]["gold"]),float(m.sides[1]["gold"])),"Income continues consistently after restore "+row[0]+age)
			m.free();restored.free()
	for side in range(2):
		var m = fixture()
		m.base(1-side)["hp"] = float(m.base(1-side)["maxHp"])*0.41
		for age in range(2,11):
			var own = m.base(side)
			var opposite = m.base(1-side).duplicate(true)
			var previous_max = float(own["maxHp"])
			own["hp"] = previous_max*0.23
			var damaged = own["hp"]
			m.sides[side]["knowledge"] = 0.0
			expect(not m.act({"type":"evolve","side":side})["ok"] and own["hp"]==damaged,"Failed evolution does not heal side %d age %d"%[side,age])
			m.sides[side]["knowledge"] = m.era_cost(side)
			expect(m.act({"type":"evolve","side":side})["ok"] and float(m.sides[side]["knowledge"])==0.0,"Paid independent evolution side %d age %d"%[side,age])
			var ratio = m.db.hp_multiplier("A%d"%age)/m.db.hp_multiplier("A%d"%(age-1))
			expect(is_equal_approx(float(own["maxHp"])/previous_max,ratio),"Capital growth follows unit HP ratio side %d age %d"%[side,age])
			expect(own["hp"]==own["maxHp"],"Capital fully healed side %d age %d"%[side,age])
			expect(m.base(1-side)==opposite,"Opponent capital stays unchanged side %d age %d"%[side,age])
			var direct = fixture("D02","A%d"%age)
			expect(direct.base(side)["maxHp"]==own["maxHp"],"Direct start and evolved capital agree side %d age %d"%[side,age])
			direct.free()
		m.free()
	var bonus_model = fixture()
	var loadout = bonus_model.db.default_loadout()
	var base_relics = bonus_model.db.rows["relics"].filter(func(row):return row.get("effects",{}).has("baseHpBonus"))
	loadout["relicIds"] = [base_relics[0]["id"]]
	bonus_model.db.tables["missions"]["QA-CAPITAL"] = {"id":"QA-CAPITAL","enemyProfileId":"AP01","bossParameters":{"enemyBaseHpBonus":0.25}}
	bonus_model.reset_battle({"missionId":"QA-CAPITAL","loadout":loadout,"heroEnabled":false,"aiEnabled":false,"randomEvents":false})
	var relic_bonus = float(base_relics[0]["effects"]["baseHpBonus"])
	expect(bonus_model.base(0)["maxHp"]==floorf(2400.0*(1.0+relic_bonus)),"Initial capital retains equipped relic HP bonus")
	expect(bonus_model.base(1)["maxHp"]==3000.0,"Initial enemy capital retains mission HP bonus")
	for side in range(2):
		bonus_model.base(side)["hp"] = 1.0
		bonus_model.sides[side]["knowledge"] = bonus_model.era_cost(side)
		bonus_model.act({"type":"evolve","side":side})
		var expected = floorf(12000.0*(1.0+relic_bonus)) if side==0 else 15000.0
		expect(bonus_model.base(side)["maxHp"]==expected and bonus_model.base(side)["hp"]==expected,"Evolution heals with relic / mission HP bonus side "+str(side))
	bonus_model.base(0)["hp"] = 12.0
	var loaded = GameModel.new()
	loaded.db.tables["missions"]["QA-CAPITAL"] = bonus_model.db.tables["missions"]["QA-CAPITAL"].duplicate(true)
	expect(loaded.restore(bonus_model.snapshot()) and loaded.base(0)["hp"]==12.0,"Loading a damaged capital does not grant an evolution heal")
	bonus_model.free();loaded.free()
	var dead = fixture()
	dead.base(1)["hp"] = 0.0
	dead.sides[1]["knowledge"] = 99999.0
	expect(not dead.act({"type":"evolve","side":1})["ok"] and dead.base(1)["hp"]==0.0,"Destroyed capital cannot be revived by evolution")
	dead.free()
	var cap = fixture("D02","A10")
	cap.base(0)["hp"] = 100.0;cap.sides[0]["knowledge"] = 99999.0
	expect(not cap.act({"type":"evolve","side":0})["ok"] and cap.base(0)["hp"]==100.0,"Maximum era cannot be exploited for healing")
	cap.free()
	var folder = OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../output/qa/2026-10-10-balance")
	DirAccess.make_dir_recursive_absolute(folder)
	var file = FileAccess.open(folder+"/difficulty-capital.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures==0,"checks":checks},"\t"));file.close()
	print("DIFFICULTY / CAPITAL: ",checks.size()-failures,"/",checks.size()," passed")
	quit(0 if failures==0 else 1)
