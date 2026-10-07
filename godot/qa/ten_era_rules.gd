extends SceneTree

var checks = []
var failure_count = 0
var matrix = []
var support_cases = []

func expect(condition: bool, name: String, detail = null) -> void:
	checks.append({"name": name, "passed": condition, "detail": detail})
	if not condition:
		failure_count += 1
		print("FAIL: ", name, " ", detail)

func fixture(era_id: String = "A1", hero_id: String = "H01", heroes: bool = false) -> GameModel:
	var model = GameModel.new()
	model.reset_battle({"startingEraId": era_id, "aiEnabled": false, "randomEvents": false, "heroEnabled": heroes,
		"loadout": model.db.default_loadout(hero_id), "enemyLoadout": model.db.default_loadout("H03"), "seed": 127})
	return model

func _init() -> void: call_deferred("run")

func run() -> void:
	content_and_damage()
	healing_and_shields()
	evolution_and_maps()
	environment_and_restore()
	hero_evolution()
	var folder = ProjectSettings.globalize_path("res://../output/qa/ten-eras")
	DirAccess.make_dir_recursive_absolute(folder)
	var file = FileAccess.open(folder + "/rules-regression.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failure_count == 0, "checks": checks, "damageMatrix": matrix, "supportCases": support_cases}, "\t"))
	print("TEN ERA RULES: ", checks.size() - failure_count, "/", checks.size(), " passed")
	quit(1 if failure_count else 0)

func content_and_damage() -> void:
	var m = fixture()
	expect(m.db.rows["eras"].size() == 10, "Ten usable eras")
	expect(m.db.rows["units"].size() == 50, "Fifty recruitable units")
	expect(m.db.rows["hero-evolutions"].size() == 60, "Sixty commander forms")
	expect(m.db.rows["missions"].size() == 20, "Twenty campaign missions")
	expect(m.max_era == "A10", "Free battle reaches era ten")
	var target = m.spawn(1, "U11", "A1", "unit", 1300.0)
	for index in range(1, 10):
		for slot in range(1, 6):
			var old = m.spawn(0, "U%d%d" % [index, slot], "A%d" % index, "unit", 300.0)
			var newer = m.spawn(0, "U%d%d" % [index + 1, slot], "A%d" % (index + 1), "unit", 500.0)
			var old_damage = m.combat.damage_for(old, target, float(old["attack"]), old["damageType"], {})
			var new_damage = m.combat.damage_for(newer, target, float(newer["attack"]), newer["damageType"], {})
			var raw_ratio = float(newer["attack"]) / float(old["attack"])
			var hit_ratio = float(new_damage) / maxi(1, old_damage)
			var dps_ratio = raw_ratio * float(old["period"]) / float(newer["period"])
			matrix.append({"from": old["contentId"], "to": newer["contentId"], "oldAttack": old["attack"], "newAttack": newer["attack"], "rawRatio": raw_ratio, "sameTargetHitRatio": hit_ratio, "dpsRatio": dps_ratio})
			expect(raw_ratio >= 5.0 - 0.000001, "Fivefold attack " + newer["contentId"], raw_ratio)
			expect(hit_ratio >= 5.0, "Fivefold same-target damage " + newer["contentId"], hit_ratio)
			expect(dps_ratio >= 5.0 - 0.000001, "Fivefold DPS " + newer["contentId"], dps_ratio)
			m.entities.erase(old); m.entities.erase(newer)
	for index in range(1, 11):
		var era = m.db.era("A%d" % index)
		expect(m.db.unit_slots(era["id"]).all(func(unit): return not unit.is_empty() and unit["eraId"] == era["id"]), "Era recruit catalog " + era["id"])
		expect(not m.db.age_special(era["id"]).is_empty(), "Era-specific raid " + era["id"])
		if index < 10: expect(float(era["nextEvolutionKnowledge"]) > 0.0, "Era XP gate " + era["id"])
		if index > 1: expect(float(era["knowledgeMultiplier"]) < float(era["attackMultiplier"]), "XP separate from power " + era["id"])
	var unit = m.spawn(1, "U101", "A10", "unit", 1200.0)
	var before = float(m.sides[0]["knowledge"])
	m.combat.kill(unit)
	expect(float(m.sides[0]["knowledge"]) - before < 300.0, "Late-era kill cannot skip many ages", float(m.sides[0]["knowledge"]) - before)
	var final_guard = m.spawn(0,"U101","A10","unit",600.0)
	expect(m.db.era_index(final_guard["eraId"]) == 9 and float(final_guard["attack"]) >= 14.0 * pow(5,9) and m.db.profile("U101")["family"] == "shield", "Era ten ID, power and approved sword-guard art agree")
	m.free()

func support_fight(medics: int, shielders: int, armor_level: int) -> Dictionary:
	var m = fixture("A7")
	m.sides[0]["research"]["front-armor"] = armor_level
	var target = m.spawn(0, "U71", "A7", "unit", 730.0)
	var maximum = float(target["maxHp"])
	target["hp"] = maximum * 0.55; target["attack"] = 0.0
	var enemy = m.spawn(1, "U71", "A7", "unit", 790.0)
	enemy["hp"] = maximum * 100000.0; enemy["maxHp"] = enemy["hp"]
	for i in range(medics):
		var medic = m.spawn(0, "U75", "A7", "unit", 685.0 - i * 32.0)
		medic["speed"] = 0.0; medic["attack"] = 0.0
	for i in range(shielders):
		var shielder = m.spawn(0, "U105", "A10", "unit", 680.0 - i * 31.0)
		shielder["speed"] = 0.0; shielder["attack"] = 0.0
	var healed = 0.0
	var largest_shield = 0.0
	for step in range(1800):
		m.step_ticks(1)
		for event in m.consume_events():
			if event["type"] == "heal" and int(event["data"]["targetId"]) == int(target["id"]): healed += float(event["data"]["amount"])
		var shield = 0.0
		for batch in target["shields"]: shield += float(batch["hp"])
		largest_shield = maxf(largest_shield, shield)
		if float(target["hp"]) <= 0.0: break
	var result = {"medics": medics, "shielders": shielders, "armorLevel": armor_level, "died": float(target["hp"]) <= 0.0, "seconds": m.elapsed, "healedHpRatio": healed / maximum, "peakShieldHpRatio": largest_shield / maximum}
	m.free()
	return result

func healing_and_shields() -> void:
	for combination in [[0,0,0], [1,0,0], [4,0,0], [4,4,0], [4,4,3]]:
		var result = support_fight(combination[0], combination[1], combination[2])
		support_cases.append(result)
		expect(result["died"], "Sustained contact kills supported front " + str(combination), result)
		expect(float(result["peakShieldHpRatio"]) <= 0.12001, "Passive shields remain bounded " + str(combination), result)
	var m = fixture("A8")
	var target = m.spawn(0, "U81", "A8", "unit", 700.0)
	var enemy = m.spawn(1, "U81", "A8", "unit", 760.0)
	target["hp"] = float(target["maxHp"]) * 0.5
	m.combat.hit(enemy, target, 100.0, "physical", {})
	m.combat.apply_hits()
	var damaged = float(target["hp"])
	var recovered = m.abilities.heal(target, float(target["maxHp"]))
	expect(recovered <= 35.001, "Healing under weak attack uses incoming-pressure budget", recovered)
	expect(float(target["hp"]) < float(target["maxHp"]), "Combat healing cannot instantly fill a large health pool")
	m.abilities.add_shield(target, 0.5, 3.0)
	var shield_total = 0.0
	for batch in target["shields"]: shield_total += float(batch["hp"])
	expect(shield_total <= float(target["maxHp"]) * 0.20001, "Active shield plus health respects separate shield cap")
	var hp_before = float(target["hp"])
	m.abilities.add_shield(target, 0.5, 3.0)
	expect(float(target["hp"]) == hp_before, "Granting a shield never increases health")
	target["hp"] = 0.0
	expect(m.abilities.heal(target, 100000000.0) == 0.0 and float(target["hp"]) == 0.0, "Medics cannot revive dead units")
	m.free()

func evolution_and_maps() -> void:
	var m = fixture()
	var initial = m.environment.scene.duplicate(true)
	m.sides[0]["knowledge"] = 85.0
	expect(not m.act({"type":"evolve", "side":0})["ok"], "Old 85 XP cannot rush the first evolution")
	for era in range(1, 10):
		m.sides[0]["knowledge"] = m.era_cost(0)
		expect(m.act({"type":"evolve", "side":0})["ok"], "Evolve through age " + str(era + 1))
		expect(m.enemy_era == 1, "Enemy age stays independent at age " + str(era + 1))
		expect(m.environment.scene["eraId"] == m.sides[0]["eraId"], "Leader evolution changes background era " + str(era + 1))
	var selected = m.environment.scene.duplicate(true)
	m.sides[1]["knowledge"] = m.era_cost(1)
	expect(m.act({"type":"evolve", "side":1})["ok"], "Trailing side can evolve independently")
	expect(m.environment.scene["eraId"] == "A10" and int(m.environment.scene["variant"]) != int(selected["variant"]), "Trailing-side evolution also selects another dominant-era map")
	var seen = {}
	for seed_value in range(1, 61):
		m.reset_battle({"startingEraId":"A6", "seed":seed_value, "aiEnabled":false, "randomEvents":false, "heroEnabled":false})
		seen[m.environment.scene["variant"]] = true
	expect(seen.size() == 3, "All three map candidates are selectable", seen)
	m.free()

func environment_and_restore() -> void:
	var m = fixture("A8")
	var left = m.spawn(0, "U81", "A8", "unit", 720.0)
	var right = m.spawn(1, "U81", "A8", "unit", 790.0)
	var health = [float(left["hp"]), float(right["hp"])]
	var gold = [m.sides[0]["gold"], m.sides[1]["gold"]]
	var rng_before = m.rng
	m.environment.spawn_event("plane", 755.0)
	expect(m.rng == rng_before, "Random events do not advance combat RNG")
	var scheduled = m.scheduled[-1]
	m.environment.resolve(scheduled)
	m.combat.apply_hits()
	expect(float(left["hp"]) >= health[0] * 0.8999 and float(right["hp"]) >= health[1] * 0.8999, "Neutral event damage is bounded on both sides")
	expect(float(m.base(0)["hp"]) == float(m.base(0)["maxHp"]) and float(m.base(1)["hp"]) == float(m.base(1)["maxHp"]), "Random events cannot damage bases")
	expect(m.sides[0]["gold"] == gold[0] and m.sides[1]["gold"] == gold[1], "Environment damage grants no bounty")
	left["hp"] = 1.0
	m.environment.resolve(scheduled); m.combat.apply_hits()
	expect(m.sides[1]["knowledge"] == 0.0 and m.sides[1]["gold"] == gold[1], "Neutral lethal damage grants no opponent XP or gold")
	var snap = JSON.parse_string(JSON.stringify(m.snapshot()))
	var restored = fixture()
	var loaded = restored.restore(snap)
	expect(loaded, "Ten-era snapshot with neutral scheduled effects restores", restored.last_restore_error)
	expect(restored.environment.snapshot() == m.environment.snapshot(), "Map and event RNG persist exactly")
	m.set_paused(true)
	var at = m.tick; m.step_ticks(90)
	expect(m.tick == at, "Pause freezes events and world simulation")
	m.free(); restored.free()

func hero_evolution() -> void:
	for identity in ["H01", "H02", "H03", "H04", "H05", "H06"]:
		var m = fixture("A1", identity, true)
		var hero = m.hero(0)
		hero["hp"] = float(hero["maxHp"]) * 0.6
		var skill = m.db.get_row("heroes", identity)["signatureSkillId"]
		m.sides[0]["cooldowns"][skill] = 600
		var names = {}
		for era in range(1, 11):
			if era > 1:
				m.sides[0]["knowledge"] = m.era_cost(0)
				m.act({"type":"evolve", "side":0})
			var form = m.db.hero_form(identity, "A%d" % era)
			names[form["signatureName"]] = true
			expect(hero["visualId"] == identity + "-A" + str(era), "Commander changes form " + identity + " age " + str(era))
			expect(absf(float(hero["hp"]) / float(hero["maxHp"]) - 0.6) < 0.015, "Commander preserves health ratio " + identity + " age " + str(era))
			expect(int(m.sides[0]["cooldowns"][skill]) == 600, "Evolution cannot reset skill cooldown " + identity + " age " + str(era))
		expect(names.size() == 10, "Commander has ten named skill variants " + identity)
		m.free()
