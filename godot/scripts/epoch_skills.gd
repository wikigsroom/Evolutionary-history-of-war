class_name EpochSkills
extends RefCounted

var m
func _init(model) -> void: m = model

func add_status(target: Dictionary, id: String, seconds: float, data: Dictionary) -> void:
	if target["kind"] == "base" or float(target["hp"]) <= 0.0: return
	if id == "ST09":
		if m.tick < int(target.get("staggerImmuneUntil", 0)): return
		target["staggerUntil"] = m.tick + ceili(seconds * 30.0)
		target["staggerImmuneUntil"] = int(target["staggerUntil"]) + 60
		target["releaseAt"] = -1
	var status = data.duplicate(true)
	status["id"] = id; status["until"] = m.tick + ceili(seconds * 30.0)
	for old in target["statuses"]:
		if old["id"] != id or (id == "ST08" and old.get("sourceId", -1) != status.get("sourceId", -1)): continue
		var expiration = maxi(int(old["until"]), int(status["until"]))
		var next_tick = old.get("nextTick")
		var stronger = true
		for field in ["slow","armorBreak","suppression","attackSpeedBonus","damage","projectileReduction"]:
			if old.has(field) and float(old[field])>float(status.get(field,0.0)): stronger=false
		if stronger: old.merge(status, true)
		old["until"] = expiration
		if id == "ST06" and next_tick != null: old["nextTick"] = next_tick
		return
	target["statuses"].append(status)

func claim_sustain(target: Dictionary, requested: float) -> float:
	if requested <= 0.0 or float(target["hp"]) <= 0.0: return 0.0
	var rules = m.db.rules["support"]
	var window = ceili(float(rules["pressureWindowSec"]) * m.HZ)
	var history = target.get("sustainHistory", []).filter(func(record): return int(record["at"]) > m.tick - window)
	var pressure = target.get("pressureHistory", []).filter(func(record): return int(record["at"]) > m.tick - window)
	var spent = 0.0
	for record in history: spent += float(record["amount"])
	var under_fire = not pressure.is_empty()
	var rate = float(rules["combatRecoveryRatioPerSec"] if under_fire else rules["outOfCombatRecoveryRatioPerSec"])
	var available = float(target["maxHp"]) * rate * float(rules["pressureWindowSec"])
	if under_fire:
		var incoming = 0.0
		for record in pressure: incoming += float(record["amount"])
		available = minf(available, incoming * float(rules["combatSustainFractionOfPressure"]))
	var received = minf(requested, maxf(0.0, available - spent))
	if received > 0.0: history.append({"at": m.tick, "amount": received})
	target["sustainHistory"] = history
	target["pressureHistory"] = pressure
	return received

func heal(target: Dictionary, requested: float, source_id: int = -1) -> float:
	if target["kind"] == "base" or float(target["hp"]) <= 0.0: return 0.0
	var amount = claim_sustain(target, minf(requested, maxf(0.0, float(target["maxHp"]) - float(target["hp"]))))
	if amount <= 0.0: return 0.0
	target["hp"] = minf(float(target["maxHp"]), float(target["hp"]) + amount)
	m.emit_event("heal", float(target["x"]), int(target["side"]), {"targetId": target["id"], "sourceId": source_id, "amount": amount})
	return amount

func add_shield(target: Dictionary, ratio: float, seconds: float, passive: bool = false) -> void:
	if float(target["hp"]) <= 0.0: return
	target["shields"] = target["shields"].filter(func(batch): return int(batch["until"]) > m.tick and float(batch["hp"]) > 0.0)
	var current = 0.0
	for batch in target["shields"]: current += float(batch["hp"])
	var received = 1.0 + (float(m.specification(int(target["side"])).get("shieldReceivedBonus", 0.0)) if target["kind"] == "hero" else 0.0)
	var cap = float(m.db.rules["support"]["passiveShieldCapRatio"] if passive else m.db.rules["support"]["totalShieldCapRatio"])
	var amount = minf(float(target["maxHp"]) * maxf(0.0, ratio) * received, float(target["maxHp"]) * cap - current)
	if passive: amount = claim_sustain(target, amount)
	if amount <= 0.0: return
	var merged = false
	if passive:
		for batch in target["shields"]:
			if batch.get("passive", false):
				batch["hp"] = float(batch["hp"]) + amount
				batch["until"] = m.tick + ceili(seconds * m.HZ)
				merged = true
				break
	if not merged: target["shields"].append({"hp": amount, "until": m.tick + ceili(seconds * m.HZ), "passive": passive})
	m.emit_event("shield", float(target["x"]), int(target["side"]), {"targetId": target["id"], "amount": amount})

func cost(side: int, skill_id: String) -> float:
	var skill = m.db.get_row("skills", skill_id)
	if skill.is_empty(): return 99999.0
	var mods = m.modifiers(side)
	var result = float(skill["commandCost"])
	if skill["category"] == "signature": result += float(mods.get("signatureCostAdd", 0.0)) + float(m.specification(side).get("signatureCostAdd", 0.0))
	elif skill["damageType"] == "energy": result += float(mods.get("energyCommonCostAdd", 0.0))
	result += float(mods.get("skillCostAdd", {}).get(skill_id, 0.0))
	return result

func cast(side: int, skill_id: String, x: float = -1.0, target_id: int = -1) -> Dictionary:
	var hero = m.hero(side, false)
	if hero.is_empty(): return m.fail("指挥官尚未归队")
	var skill = m.db.get_row("skills", skill_id)
	var player = m.sides[side]
	var hero_row = m.db.get_row("heroes", player["loadout"]["heroId"])
	var variant = m.db.hero_form(hero["contentId"], hero["eraId"]).get("skillVariant", {})
	if skill.is_empty() or (hero_row["signatureSkillId"] != skill_id and not player["loadout"]["commonSkillIds"].has(skill_id)): return m.fail("技能未装备")
	if m.tick < int(player["cooldowns"].get(skill_id, 0)): return m.fail("技能冷却中")
	if float(player["command"]) < cost(side, skill_id): return m.fail("军令不足")
	var mode = String(skill["targetMode"])
	var target = m.entity_by_id(target_id)
	if mode in ["self", "direction_self"]: x = float(hero["x"])
	elif mode == "enemy_entity":
		if target.is_empty() or target["side"] == side or float(target["hp"]) <= 0.0 or target.get("garrisoned", false): return m.fail("请选择敌方目标")
		if target["kind"] == "base" and not skill["canDamageBase"]: return m.fail("该技能不能选择基地")
		x = float(target["x"])
	elif x < 0.0: x = float(hero["x"])
	var cast_range = float(skill["castRange"]) + (float(m.modifiers(side).get("commonCastRangeAdd", 0.0)) if skill["category"] == "common" else 0.0)
	if absf(x - float(hero["x"])) > cast_range: return m.fail("目标超出指挥官施法范围")
	x = clampf(x, 80.0, 1520.0)
	var summon_x = NAN
	if skill_id == "HS04":
		if m.population(side) >= 29 or not m.living(side, false).filter(func(u): return u["kind"] == "summon").is_empty(): return m.fail("炮台已部署或人口已满")
		var front = float(hero["x"])
		for ally in m.living(side, false): front = maxf(front, float(ally["x"])) if side == 0 else minf(front, float(ally["x"]))
		if (x - front) * (1.0 if side == 0 else -1.0) > 100.0: return m.fail("请在己方阵线附近部署")
		summon_x = m.combat.nearest_space(x, 27.0)
		if is_nan(summon_x) or absf(summon_x - x) > 90.0: return m.fail("部署位置被占用")
	var cast_id = m.id()
	player["command"] = float(player["command"]) - cost(side, skill_id)
	var cooldown = float(skill["cooldownSec"])
	if skill["category"] == "signature": cooldown = (cooldown + float(m.specification(side).get("signatureCooldownAddSec", 0.0))) * (1.0 - clampf(float(m.modifiers(side).get("signatureCooldownReduction", 0.0)), 0.0, 0.25))
	player["cooldowns"][skill_id] = m.tick + ceili(cooldown * 30.0)
	hero["skillAt"] = m.tick
	m.emit_event("skill", x, side, {"skillId": skill_id, "sourceId": hero["id"], "radius": skill["radius"], "castId": cast_id, "eraId": hero["eraId"], "signatureName": m.db.skill_name(skill_id, hero["contentId"], hero["eraId"])})
	if skill_id == "HS01":
		var direction = 1.0 if side == 0 else -1.0
		hero["facing"] = direction
		var destination = clampf(float(hero["x"]) + direction * (float(variant.get("chargeRange", 150.0)) + float(m.specification(side).get("chargeRangeAdd", 0.0))), 139.0 + float(hero["radius"]), 1461.0 - float(hero["radius"]))
		hero["releaseAt"] = -1
		hero["charge"] = {"from": hero["x"], "to": destination, "at": m.tick, "until": m.tick + 18, "hitIds": [], "castId": cast_id, "variant": variant.duplicate(true)}
	elif skill_id == "HS04":
		var summon = m.spawn(side,"summon-H04",hero["eraId"],"summon",summon_x)
		var spec = m.specification(side)
		var stats = skill["effects"]["summon"]
		var multiplier = m.db.hp_multiplier(hero["eraId"])
		summon.merge({"radius": 27.0, "windup":hero["windup"],
			"hp": floorf(220.0 * multiplier * (1.0 + float(spec.get("summonHpBonus", 0.0)))), "attack": 18.0 * m.db.attack_multiplier(hero["eraId"]) * (1.0 + float(spec.get("summonAttackBonus", 0.0))),
			"armor": 8.0, "range": float(variant.get("summonRange", 200.0)), "speed": 0.0, "period": ceili(30.0 * (1.0 + float(spec.get("summonAttackPeriodBonus", 0.0)))),
			"weaponId": variant.get("summonWeapon", "W01"), "damageType": "physical", "heavy": false, "role": "ranged", "bornTick": m.tick, "phase": "idle", "nextAttack": m.tick + 6,
			"visualId": "SUM-" + hero["eraId"], "releaseAt": -1, "statuses": [], "shields": [], "expiresAt": m.tick + ceili((float(variant.get("summonDuration", 14.0)) + float(spec.get("summonDurationAddSec", 0.0))) * 30.0)}, true)
		summon["maxHp"] = summon["hp"]
		m.emit_event("build", summon_x, side, {"targetId": summon["id"], "kind": "summon"})
	else:
		var due = m.tick + 1
		if skill_id == "S05":
			var extra_warning = float(m.db.get_row("missions", String(m.config["missionId"])).get("bossParameters", {}).get("extraEnemyClusterWarningSec", 0.0)) if side == 1 else 0.0
			due = m.tick + ceili((0.5 + extra_warning) * 30.0)
			m.emit_event("warning", x, side, {"radius": skill["radius"], "until": due, "skillId": skill_id})
		m.scheduled.append({"due": due, "kind": "skill", "source": hero.duplicate(true), "skillId": skill_id, "x": x, "targetId": target_id, "castId": cast_id, "pulse": 0})
	return {"ok": true}

func queue_advance(side: int, ratio: float, cast_id: int, original: bool = false) -> void:
	var queue = m.sides[side]["queue"]
	if queue.is_empty(): return
	var order = queue[0]
	if order["advancedBy"].has(cast_id): return
	order["advancedBy"].append(cast_id)
	var reduction = mini(floori(float(order["duration"] if original else order["remaining"]) * ratio), floori(float(order["duration"]) * 0.5) - int(order["progressUsed"]))
	reduction = maxi(0, mini(reduction, int(order["remaining"])))
	order["progressUsed"] = int(order["progressUsed"]) + reduction
	order["remaining"] = int(order["remaining"]) - reduction

func use_item(side: int, item_id: String, x: float) -> Dictionary:
	if not EpochData.ITEMS.has(item_id): return m.fail("无效道具")
	var player = m.sides[side]
	if int(player["activeItems"].get(item_id, 0)) <= 0: return m.fail("道具已经用完")
	if m.tick < int(player["itemCooldowns"].get(item_id, 0)): return m.fail("道具冷却中")
	var item = EpochData.ITEMS[item_id]
	if item["target"] and (not is_finite(x) or x < 80.0 or x > 1520.0): return m.fail("请选择战场内的目标位置")
	var cast_id = m.id()
	player["activeItems"][item_id] = int(player["activeItems"][item_id]) - 1
	player["itemCooldowns"][item_id] = m.tick + ceili(float(item["cooldown"]) * 30.0)
	if not player.has("itemActiveUntil"): player["itemActiveUntil"]={}
	if item_id in ["war-drum","smoke-bomb"]: player["itemActiveUntil"][item_id]=m.tick+(240 if item_id=="war-drum" else 150)
	if item_id == "war-drum":
		for ally in m.living(side, false): add_status(ally, "item-drum", 8.0, {"attackBonus": 0.18, "moveBonus": 0.12})
		queue_advance(side, 0.35, cast_id, true)
		x = float(m.hero(side).get("x", m.BASE_POSITIONS[side]))
	elif item_id == "chrono-crate":
		player["gold"] = float(player["gold"]) + 65.0 * float(m.db.era(player["eraId"])["costMultiplier"])
		player["command"] = minf(m.command_max(side), float(player["command"]) + 15.0)
		queue_advance(side, 0.45, cast_id, true)
		x = m.BASE_POSITIONS[side]
	else:
		x = clampf(x, 80.0, 1520.0)
		m.fields.append({"id": cast_id, "kind": "smoke", "side": side, "x": x, "radius": 135.0, "until": m.tick + 150, "nextTick": m.tick})
	m.emit_event("item", x, side, {"itemId": item_id, "radius": 135.0 if item_id == "smoke-bomb" else 100.0,"targets":m.living(side,false).map(func(u):return u["id"]),"gold":65.0*float(m.db.era(player["eraId"])["costMultiplier"])})
	return {"ok": true}

func use_age(side: int, x: float = -1.0) -> Dictionary:
	var player = m.sides[side]
	var row = m.db.age_special(player["eraId"])
	if m.tick < int(player["ageSpecialReadyAt"]): return m.fail("时代奇袭冷却中")
	if float(player["knowledge"]) < float(row["cost"]): return m.fail("战斗经验不足")
	if x < 0.0:
		var enemies = m.living(1 - side, false)
		x = float(enemies[0]["x"]) if not enemies.is_empty() else 800.0
	player["knowledge"] = float(player["knowledge"]) - float(row["cost"])
	player["ageSpecialReadyAt"] = m.tick + ceili(float(row["cooldown"]) * 30.0)
	var source = m.base(side).duplicate(true)
	var cast_id = m.id()
	var warning = ceili(float(row["warningSec"]) * m.HZ)
	for i in range(int(row["pulses"])):
		m.scheduled.append({"due": m.tick + warning + ceili(i * float(row["pulseIntervalSec"]) * m.HZ), "kind": "age", "source": source, "x": clampf(x, 150.0, 1450.0), "eraId": player["eraId"], "castId": cast_id, "pulse": i})
	m.emit_event("warning", x, side, {"radius": row["radius"], "until": m.tick + warning, "skillId": "age-" + player["eraId"], "eraId": player["eraId"]})
	m.emit_event("ageLaunch", x, side, {"eraId": player["eraId"], "radius": row["radius"], "pulses": row["pulses"], "warningSec": row["warningSec"], "pulseIntervalSec": row["pulseIntervalSec"], "castId": cast_id, "fromX": m.BASE_POSITIONS[side]})
	return {"ok": true}

func targets(side: int, x: float, radius: float, maximum: int, include_base: bool = false) -> Array:
	var candidates = m.living(side, include_base).filter(func(u): return absf(float(u["x"]) - x) <= radius + float(u["radius"]))
	candidates.sort_custom(func(a, b): return absf(float(a["x"]) - x) < absf(float(b["x"]) - x) if absf(absf(float(a["x"]) - x) - absf(float(b["x"]) - x)) > 0.001 else int(a["id"]) < int(b["id"]))
	return candidates.slice(0, maximum)

func update() -> void:
	for hero in m.living(-1, false).filter(func(u): return u.has("charge")):
		var charge = hero["charge"]
		var variant = charge.get("variant", {})
		m.combat.move_actor(hero, lerpf(float(charge["from"]), float(charge["to"]), clampf(float(m.tick - int(charge["at"])) / 18.0, 0.0, 1.0)))
		hero["phase"] = "charge"
		var side = int(hero["side"])
		for target in m.living(1 - side):
			if charge["hitIds"].size() >= int(variant.get("chargeTargets", 2)) or charge["hitIds"].has(target["id"]): continue
			if target["x"] < minf(float(hero["previousX"]), float(hero["x"])) - float(hero["radius"]) - float(target["radius"]) or target["x"] > maxf(float(hero["previousX"]), float(hero["x"])) + float(hero["radius"]) + float(target["radius"]): continue
			charge["hitIds"].append(target["id"])
			var extra = {"skillId": "HS01", "castId": charge["castId"], "weaponId": "W06", "canDamageBase": true,
				"conditionalBonus": float(m.specification(side).get("heavyConditionalBonus", 0.0)) if target.get("heavy", false) else 0.0,
				"displace": (1.0 if side == 0 else -1.0) * float(variant.get("knockback", 30.0)) * float(m.specification(side).get("knockbackMultiplier", 1.0))}
			m.combat.hit(hero, target, scaled_damage(hero, "HS01"), "physical", extra)
		if m.tick >= int(charge["until"]):
			var settlement = m.combat.nearest_space(float(hero["x"]), float(hero["radius"]), int(hero["id"]))
			if not is_nan(settlement):
				m.combat.move_actor(hero, settlement, false); hero.erase("charge"); hero["releasedAt"] = m.tick
				if m.specification(side).has("allyAttackBonus"):
					for ally in targets(side, settlement, 160.0, 8): add_status(ally, "charge-formation", 5.0, {"attackBonus": 0.1})
	var due = m.scheduled.filter(func(e): return int(e["due"]) <= m.tick)
	m.scheduled = m.scheduled.filter(func(e): return int(e["due"]) > m.tick)
	for event in due:
		if event["kind"] == "skill": resolve_skill(event)
		elif event["kind"] == "age":
			var row = m.db.age_special(event["eraId"])
			var raw = float(row["damage"]) * m.db.attack_multiplier(event["eraId"])
			for target in targets(1 - int(event["source"]["side"]), float(event["x"]), float(row["radius"]), 6):
				m.combat.hit(event["source"], target, raw, row["damageType"], {"skillId": "age-" + event["eraId"], "castId": event["castId"], "canDamageBase": false})
			m.emit_event("ageImpact", float(event["x"]), int(event["source"]["side"]), {"eraId": event["eraId"], "radius": row["radius"], "pulse": event["pulse"], "fx": row["fx"]})
		elif event["kind"] == "environment": m.environment.resolve(event)
		elif event["kind"] == "counter":
			for target in targets(1 - int(event["source"]["side"]), float(event["x"]), 100.0, 3): m.combat.hit(event["source"], target, float(event["damage"]), "physical", {"skillId": "shield-counter", "canDamageBase": false})
	var retained = []
	for field in m.fields:
		if int(field["until"]) < m.tick: continue
		if field["kind"] == "smoke":
			if int(field["until"])<=m.tick:continue
			for target in targets(1 - int(field["side"]), float(field["x"]), float(field["radius"]), 30): add_status(target, "ST03", minf(0.2,float(int(field["until"])-m.tick)/30.0), {"slow": 0.35})
		elif field["kind"] == "burn":
			for target in targets(1 - int(field["side"]), float(field["x"]), float(field["radius"]), 4):
				if not field["hitIds"].has(target["id"]):
					field["hitIds"].append(target["id"]); add_status(target, "ST06", float(field["duration"]), {"damage": field["damage"], "source": field["source"], "nextTick": m.tick + 30})
		elif field["kind"] == "rift" and m.tick >= int(field["nextTick"]):
			var event = field["event"].duplicate(true); event["pulse"] = int(event.get("pulse", 0)) + 1
			resolve_skill(event, true); field["event"] = event; field["nextTick"] = int(field["nextTick"]) + 30
		retained.append(field)
	m.fields = retained

func scaled_damage(source: Dictionary, skill_id: String) -> float:
	var skill = m.db.get_row("skills", skill_id)
	var bonus = clampf(float(m.modifiers(int(source["side"])).get("skillPowerBonus", 0.0)), 0.0, 0.2)
	if skill["category"] == "signature": bonus += float(m.specification(int(source["side"])).get("signatureDamageBonus", 0.0))
	return float(skill["damageBase"]) * m.db.attack_multiplier(source["eraId"]) * (1.0 + bonus)

func resolve_skill(event: Dictionary, field_tick: bool = false) -> void:
	var skill_id = String(event["skillId"])
	var skill = m.db.get_row("skills", skill_id)
	var source = event["source"]
	var variant = m.db.hero_form(source["contentId"], source["eraId"]).get("skillVariant", {})
	var side = int(source["side"])
	var x = float(event["x"])
	var mods = m.modifiers(side)
	var spec = m.specification(side)
	var ally = String(skill["targetMode"]) in ["ally_area", "self"]
	var effect_radius = float(variant.get("fieldRadius",skill["radius"])) if skill_id == "HS05" else float(skill["radius"])
	var affected = targets(side if ally else 1 - side, x, effect_radius, int(skill["maxTargets"]), bool(skill["canDamageBase"]) and not ally)
	if String(skill["targetMode"]) == "enemy_entity":
		var selected = m.entity_by_id(int(event["targetId"]))
		affected = [selected] if not selected.is_empty() and float(selected["hp"]) > 0.0 and not selected.get("garrisoned", false) else []
	if skill_id in ["S01", "HS03"]:
		var ratio = float(skill["effects"]["shieldHpRatio"]) + float(mods.get("shieldHpRatioAdd", 0.0)) + (float(spec.get("shieldHpRatioAdd", 0.0)) if skill_id == "HS03" else 0.0)
		if skill_id == "HS03" and spec.get("shieldPriority") == "lowest_health_3":
			affected = affected.filter(func(u): return u["kind"] == "unit")
			affected.sort_custom(func(a, b): return float(a["hp"]) / float(a["maxHp"]) < float(b["hp"]) / float(b["maxHp"]))
			affected = affected.slice(0, 3)
			var current_hero = m.hero(side)
			if not current_hero.is_empty(): add_shield(current_hero, ratio * 0.8, 6.0 + float(mods.get("shieldDurationAddSec", 0.0)))
		for target in affected:
			add_shield(target, ratio, 6.0 + float(mods.get("shieldDurationAddSec", 0.0)))
			if skill_id == "HS03" and float(variant.get("shieldReduction", 0.0)) > 0.0:
				add_status(target, "era-cover", 3.0, {"projectileReduction": variant["shieldReduction"]})
	elif skill_id in ["S02", "S11", "S12"]:
		for target in affected:
			if skill_id == "S02": add_status(target, "ST08", 5.0, {"attackSpeedBonus": 0.15, "sourceId": source["id"]})
			elif skill_id == "S11": add_status(target, "ST10", 5.0, {"projectileReduction": 0.2})
			else: add_status(target, "march", 5.0, {"moveBonus": 0.2})
		if skill_id == "S12": queue_advance(side, 0.15, int(event["castId"]))
	elif skill_id == "HS06":
		var supplied_gold = float(spec["signatureGold"]) * float(m.db.era(source["eraId"])["costMultiplier"]) if spec.has("signatureGold") else float(variant.get("supplyGold", 35.0))
		m.sides[side]["gold"] = float(m.sides[side]["gold"]) + supplied_gold
		m.sides[side]["command"] = minf(m.command_max(side), float(m.sides[side]["command"]) + float(variant.get("supplyCommand", 5.0)))
		queue_advance(side, float(spec.get("queueProgressRatio", 0.25)), int(event["castId"]))
		for target in affected:
			var amount = float(target["maxHp"]) * float(spec.get("healHpRatio", 0.15))
			heal(target, amount, int(source["id"]))
	elif skill_id == "S10":
		for target in affected: add_status(target, "ST04", 4.0 + float(spec.get("markDurationAddSec", 0.0)), {"charges": 4, "conditionalBonus": 0.15 + float(mods.get("markConditionalBonus", 0.0))})
	elif skill_id == "HS05" and not field_tick:
		m.fields.append({"id": event["castId"], "kind": "rift", "side": side, "x": x, "radius": float(variant.get("fieldRadius", 85.0)), "until": m.tick + ceili(float(variant.get("fieldDuration", 3.0)) * m.HZ), "nextTick": m.tick + 30, "event": event.duplicate(true)})
	else:
		var raw = scaled_damage(source, skill_id)
		var extra = {"skillId": skill_id, "castId": event["castId"], "canDamageBase": skill["canDamageBase"], "statuses": []}
		if skill_id == "S04": extra["statuses"] = [{"id": "ST01", "duration": 4.0, "data": {"armorBreak": 0.25}}]
		elif skill_id == "S05": extra["brokenArmorBonus"] = 0.2
		elif skill_id == "S06": extra["statuses"] = [{"id": "ST03", "duration": 3.0, "data": {"slow": 0.3}}, {"id": "ST05", "duration": 6.0, "data": {}}]
		elif skill_id == "S08": extra["statuses"] = [{"id": "ST06", "duration": 4.0 + float(mods.get("burnDurationAddSec", 0.0)), "data": {"damage": 12.0 * float(m.db.era(source["eraId"])["hpAttackMultiplier"]), "nextTick": m.tick + 30, "source": source.duplicate(true)}}]
		elif skill_id == "HS05":
			extra["statuses"] = [{"id": "ST03", "duration": 1.1, "data": {"slow": float(spec.get("signatureSlowMagnitude", variant.get("fieldSlow", 0.18)))}}]
			if spec.get("signatureAddsConductive", false): extra["statuses"].append({"id": "ST05", "duration": 6.0, "data": {}})
		if skill_id == "S07":
			affected = []
			var origin = x
			for i in range(3):
				var candidates = targets(1 - side, origin, 80.0 if i == 0 else 150.0, 60, true).filter(func(u):return not affected.has(u))
				if candidates.is_empty():break
				affected.append(candidates[0]);origin=float(candidates[0]["x"])
		for i in range(affected.size()):
			var target = affected[i]
			var details = extra.duplicate(true)
			if skill_id == "S09": details["displace"] = signf(x - float(target["x"])) * minf(70.0, absf(x - float(target["x"])))
			if skill_id in ["HS02","S04"]:
				details["weaponId"] = variant.get("projectileWeapon", "W01") if skill_id == "HS02" else "W04"; details["pierceTargets"] = int(spec.get("pierceTargets", variant.get("pierceTargets", 1))) if skill_id == "HS02" else 1
				m.combat.fire(source, target, raw, skill["damageType"], details)
			else: m.combat.hit(source, target, raw * (pow(0.7, i) if skill_id == "S07" else 1.0), skill["damageType"], details)
		if skill_id == "S08": m.fields.append({"id": event["castId"], "kind": "burn", "x": x, "side": side, "radius": 75.0, "until": m.tick + 120, "source": source, "duration": 4.0 + float(mods.get("burnDurationAddSec", 0.0)), "damage": 12.0 * float(m.db.era(source["eraId"])["hpAttackMultiplier"]), "hitIds": affected.map(func(t): return t["id"])})
		if skill_id == "HS05" and affected.size() >= 2 and spec.has("refundCommandOnTwoHits") and not event.get("refunded", false):
			m.sides[side]["command"] = minf(m.command_max(side), float(m.sides[side]["command"]) + 8.0); event["refunded"] = true
		if skill_id in ["S03", "HS02"] and int(event["pulse"]) + 1 < (int(variant.get("pulses", 2)) if skill_id == "HS02" else 3):
			var next = event.duplicate(true); next["due"] = m.tick + 6; next["pulse"] = int(event["pulse"]) + 1; m.scheduled.append(next)
	m.emit_event("skillImpact", x, side, {"skillId": skill_id, "radius": variant.get("fieldRadius",skill["radius"]) if skill_id=="HS05" else skill["radius"], "targets": affected.map(func(t): return t["id"]), "fieldTick": field_tick,"eraId":source["eraId"],"weaponId":variant.get("projectileWeapon","W01") if skill_id=="HS02" else source["weaponId"]})
