extends SceneTree
var failures = []
var checks = 0
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label); push_error(label)
func fresh() -> GameModel:
	var model = GameModel.new()
	model.reset_battle({"aiEnabled": false, "heroEnabled": false, "seed": 123})
	return model
func equivalent(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a) - float(b)) < 0.000000001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a.keys():
			if not b.has(key) or not equivalent(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not equivalent(a[i], b[i]): return false
		return true
	return a == b
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var m = fresh()
	m.sides[0]["knowledge"] = 2000.0
	m.act({"type": "train", "unitId": "U11"})
	m.act({"type": "evolve", "upgradeId": "R21"})
	check(m.sides[0]["eraId"] == "A2" and m.sides[1]["eraId"] == "A1", "时代不能同步升级")
	m.step_ticks(60)
	check(m.living(0, false).size() == 1 and m.living(0, false)[0]["eraId"] == "A1", "付费训练订单保留原时代")
	var old = m.living(0, false)[0]
	for age in range(3, 6): check(m.act({"type": "evolve"})["ok"], "五时代可独立晋升")
	check(old["eraId"] == "A1", "原有兵种不能被追溯进化")
	var time = m.tick
	m.set_paused(true); m.advance(1.0); m.step_ticks(20)
	check(m.tick == time, "暂停冻结模型")
	m.set_paused(false)
	var n = fresh()
	var front = n.spawn(0, "U11", "A1", "unit", 730.0)
	var rear = n.spawn(0, "U11", "A1", "unit", 682.0)
	var enemy = n.spawn(1, "U11", "A1", "unit", 800.0)
	n.step_ticks(9)
	check(front["phase"] == "windup" and rear["phase"] != "windup", "短兵队首接敌后排排队")
	check(absf(float(front["x"]) - float(rear["x"])) >= float(front["radius"]) + float(rear["radius"]) + 3.9, "体积占位无交叠")
	var p = fresh()
	var bow = p.spawn(0, "U12", "A1", "unit", 650.0)
	var target = p.spawn(1, "U11", "A1", "unit", 880.0)
	var hp = target["hp"]
	p.step_ticks(12)
	check(target["hp"] == hp and p.projectiles.size() == 1, "释放时不提前扣投射伤害")
	p.step_ticks(25)
	check(float(target["hp"]) < float(hp), "弹道抵达后结算")
	var blocked = fresh()
	blocked.spawn(0, "U11", "A1", "unit", blocked.spawn_x(0, "U11"))
	blocked.entities[-1]["speed"] = 0.0
	blocked.act({"type": "train", "unitId": "U11"}); blocked.step_ticks(60)
	check(blocked.sides[0]["queue"].size() == 1 and blocked.sides[0]["queue"][0]["remaining"] == 0, "堵塞出口保留完工订单")
	blocked.combat.kill(blocked.entities[-1]); blocked.step_ticks(1)
	check(blocked.sides[0]["queue"].is_empty(), "出口释放自动出营")
	var saved = fresh()
	saved.spawn(0, "U11", "A1", "unit", 700.0); saved.spawn(1, "U12", "A1", "unit", 820.0)
	saved.step_ticks(20)
	var loaded = fresh()
	check(loaded.restore(JSON.parse_string(JSON.stringify(saved.snapshot(), "", true, true))), "JSON存档可恢复")
	saved.step_ticks(75); loaded.step_ticks(75)
	for pair in [["restore-a", saved.snapshot()], ["restore-b", loaded.snapshot()]]:
		var file = FileAccess.open("res://qa/" + pair[0] + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify(pair[1], "", true, true)); file.close()
	check(equivalent(saved.snapshot(), loaded.snapshot()), "恢复后模型连续一致（浮点误差<1e-9）")
	for content in m.db.rows["units"]:
		var t = fresh(); t.sides[0]["eraId"] = content["eraId"]
		var fighter = t.spawn(0, content["id"], content["eraId"], "unit", 650.0)
		t.spawn(1, "U11", "A1", "unit", 740.0)
		t.step_ticks(100)
		check(m.db.animations.has(content["id"]) and fighter["maxHp"] > 0, "兵种与动作覆盖 " + content["id"])
		t.free()
	for hero_row in m.db.rows["heroes"]:
		for skill_id in [hero_row["signatureSkillId"]] + m.db.rows["skills"].filter(func(s): return s["category"] == "common").map(func(s): return s["id"]):
			var t = fresh(); t.config["heroEnabled"] = true
			t.sides[0]["loadout"] = m.db.default_loadout(hero_row["id"]); t.sides[0]["loadout"]["commonSkillIds"] = [skill_id] if String(skill_id).begins_with("S") else ["S01", "S02"]
			t.sides[0]["command"] = 110.0
			t.spawn(0, hero_row["id"], "A1", "hero", 650.0)
			var foe = t.spawn(1, "U11", "A1", "unit", 900.0)
			t.spawn(0, "U11", "A1", "unit", 590.0)
			var x = 530.0 if skill_id == "HS04" else (650.0 if m.db.get_row("skills", skill_id)["targetMode"] == "ally_area" else 900.0)
			check(t.abilities.cast(0, skill_id, x, int(foe["id"]))["ok"], "技能可实际释放 " + hero_row["id"] + "/" + skill_id)
			t.step_ticks(200); t.free()
	var s = EpochStore.new(m.db, "user://qa-regression/")
	var cfg = s.next_match_config("campaign", "M03")
	check(s.record_result(cfg, 0) and not s.record_result(cfg, 0), "奖励账本只能提交一次")
	check(s.profile["unlocked_heroes"].has("H02"), "战役英雄解锁")
	for model in [m, n, p, blocked, saved, loaded]: model.free()
	print(JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
