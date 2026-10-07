class_name EpochCombat
extends RefCounted

var m
func _init(model) -> void: m = model

func grounded() -> Array:
	return m.living(-1, false).filter(func(u): return not u.has("charge") and not u.has("yield"))

func space_free(x: float, radius: float, ignored_id: int = -1) -> bool:
	if x - radius < 139.0 or x + radius > 1461.0: return false
	for unit in grounded():
		if int(unit["id"]) != ignored_id and absf(x - float(unit["x"])) < radius + float(unit["radius"]) + m.BODY_GAP - 0.01: return false
	return true

func nearest_space(x: float, radius: float, ignored_id: int = -1) -> float:
	x = clampf(x, 139.0 + radius, 1461.0 - radius)
	if space_free(x, radius, ignored_id): return x
	var blockers = grounded().filter(func(u): return int(u["id"]) != ignored_id)
	blockers.sort_custom(func(a, b): return float(a["x"]) - float(a["radius"]) < float(b["x"]) - float(b["radius"]))
	var cursor = 139.0 + radius
	var limit = 1461.0 - radius
	var best = NAN
	var closest = INF
	for unit in blockers:
		var left = float(unit["x"]) - float(unit["radius"]) - radius - m.BODY_GAP
		if left >= cursor - 0.001:
			var candidate = clampf(x, cursor, minf(left, limit))
			if absf(candidate - x) < closest: best = candidate; closest = absf(candidate - x)
		cursor = maxf(cursor, float(unit["x"]) + float(unit["radius"]) + radius + m.BODY_GAP)
		if cursor > limit: break
	if cursor <= limit:
		var candidate = clampf(x, cursor, limit)
		if absf(candidate - x) < closest: best = candidate
	return best

func constrained_x(unit: Dictionary, destination: float) -> float:
	var origin = float(unit["x"])
	var result = clampf(destination, 139.0 + float(unit["radius"]), 1461.0 - float(unit["radius"]))
	var direction = signf(result - origin)
	for other in grounded():
		if other["id"] == unit["id"] or (float(other["x"]) - origin) * direction <= 0.0: continue
		var boundary = float(other["x"]) - direction * (float(other["radius"]) + float(unit["radius"]) + m.BODY_GAP)
		if direction > 0.0: result = minf(result, maxf(origin, boundary))
		else: result = maxf(result, minf(origin, boundary))
	return result

func distance(a: Dictionary, b: Dictionary) -> float:
	return absf(float(a["x"]) - float(b["x"])) - float(a["radius"]) - float(b["radius"])

func nearest_enemy(unit: Dictionary) -> Dictionary:
	var direction = 1.0 if int(unit["side"]) == 0 else -1.0
	var closest = INF
	var result = {}
	for candidate in m.living(1 - int(unit["side"])):
		if (float(candidate["x"]) - float(unit["x"])) * direction < -float(candidate["radius"]) - float(unit["radius"]): continue
		var gap = distance(unit, candidate)
		if gap < closest - 0.001 or (absf(gap - closest) <= 0.001 and (result.is_empty() or int(candidate["id"]) < int(result["id"]))):
			result = candidate; closest = gap
	return result

func legal_contact(unit: Dictionary, target: Dictionary) -> bool:
	var over_shoulder = m.db.profile(unit.get("visualId", unit["contentId"]))["over_shoulder"]
	if float(unit["range"]) >= 100.0 and not over_shoulder: return true
	var allies_between = 0
	var left = minf(float(unit["x"]), float(target["x"]))
	var right = maxf(float(unit["x"]), float(target["x"]))
	for ally in grounded():
		if ally["id"] != unit["id"] and ally["side"] == unit["side"] and float(ally["x"]) > left and float(ally["x"]) < right: allies_between += 1
	return allies_between == 0 or (over_shoulder and allies_between == 1)

func status(unit: Dictionary, id: String) -> Dictionary:
	for effect in unit["statuses"]:
		if effect["id"] == id: return effect
	return {}

func bonus(unit: Dictionary, field: String) -> float:
	var result = 0.0
	var encouragement = 0.0
	for effect in unit["statuses"]:
		if effect["id"] == "ST08": encouragement = maxf(encouragement, float(effect.get(field, 0.0)))
		else: result += float(effect.get(field, 0.0))
	return result + encouragement

func move_actor(unit: Dictionary, destination: float, turn: bool = true) -> void:
	var movement = destination - float(unit["x"])
	unit["x"] = destination
	unit["runDistance"] = float(unit.get("runDistance", 0.0)) + absf(movement)
	if turn and absf(movement) > 0.001: unit["facing"] = signf(movement)

func yield_ticks(unit: Dictionary, from_x: float, to_x: float) -> int:
	return maxi(15, ceili(absf(to_x - from_x) / maxf(1.0, float(unit["speed"])) * 30.0))

func update_statuses() -> void:
	for unit in m.entities.filter(func(u):return float(u["hp"])>0.0):
		if unit.has("expiresAt") and m.tick >= int(unit["expiresAt"]): kill(unit, true); continue
		unit["shields"] = unit["shields"].filter(func(s): return int(s["until"]) > m.tick and float(s["hp"]) > 0.0)
		for effect in unit["statuses"]:
			if effect["id"] == "ST06" and m.tick >= int(effect.get("nextTick", m.tick + 1)) and m.tick <= int(effect["until"]):
				var source = effect["source"]
				hit(source, unit, float(effect["damage"]), "blast", {"skillId": "S08", "canDamageBase": true, "dot": true})
				effect["nextTick"] = int(effect["nextTick"]) + 30
		unit["statuses"] = unit["statuses"].filter(func(s): return int(s["until"]) > m.tick)
		if unit["kind"] == "base": continue
		if unit.get("garrisoned", false):
			if m.tick % m.HZ == int(unit["id"]) % m.HZ:m.abilities.heal(unit, float(unit["maxHp"]) * 0.025, int(unit["id"]))
			continue
		var special = unit.get("special", {})
		var radius = float(special.get("auraRadius", 0.0))
		if radius <= 0.0: continue
		var allies = m.living(int(unit["side"]), false).filter(func(ally): return absf(float(ally["x"]) - float(unit["x"])) <= radius)
		allies.sort_custom(func(a, b): return float(a["hp"]) / float(a["maxHp"]) < float(b["hp"]) / float(b["maxHp"]) if absf(float(a["hp"]) / float(a["maxHp"]) - float(b["hp"]) / float(b["maxHp"])) > 0.001 else int(a["id"]) < int(b["id"]))
		var pulse = m.tick >= int(unit.get("supportReadyAt", 0))
		if pulse: unit["supportReadyAt"] = m.tick + ceili(float(special.get("supportPulseSec", 1.5)) * m.HZ)
		for ally in allies.slice(0, int(special.get("supportTargetCap", 3))):
			if special.has("auraAttackSpeedBonus"):
				m.abilities.add_status(ally, "ST08", 0.2, {"attackSpeedBonus": special["auraAttackSpeedBonus"], "sourceId": unit["id"]})
			if pulse and special.has("auraHealHpRatio"):
				var generation_factor = minf(1.0, m.db.hp_multiplier(unit["eraId"]) / m.db.hp_multiplier(ally["eraId"]))
				m.abilities.heal(ally, float(ally["maxHp"]) * float(special["auraHealHpRatio"]) * generation_factor, int(unit["id"]))
			if pulse and special.has("auraShieldRatio"):
				var generation_factor = minf(1.0, m.db.hp_multiplier(unit["eraId"]) / m.db.hp_multiplier(ally["eraId"]))
				m.abilities.add_shield(ally, float(special["auraShieldRatio"]) * generation_factor, 4.0, true)

func update_units() -> void:
	var fighters = m.living(-1, false)
	fighters.sort_custom(func(a, b):
		if a["side"] != b["side"]: return int(a["side"]) < int(b["side"])
		if absf(float(a["x"]) - float(b["x"])) < 0.001: return int(a["id"]) < int(b["id"])
		return float(a["x"]) > float(b["x"]) if a["side"] == 0 else float(a["x"]) < float(b["x"]))
	for unit in fighters:
		if unit.get("garrisoned", false): continue
		if unit.has("charge"): continue
		if unit.has("yield"):
			var reservation = unit["yield"]
			var duration = float(reservation.get("duration", yield_ticks(unit, float(reservation["from"]), float(reservation["to"]))))
			move_actor(unit, lerpf(float(reservation["from"]), float(reservation["to"]), minf(1.0, float(m.tick - int(reservation["at"])) / duration)))
			unit["phase"] = "walk" if absf(float(unit["x"]) - float(unit["previousX"])) > 0.001 else "idle"
			if m.tick >= int(reservation["at"]) + int(duration):
				if reservation.get("retreat", false):
					unit["garrisoned"] = true; unit["phase"] = "garrison"; unit.erase("yield"); continue
				var settled = nearest_space(float(reservation["to"]), float(unit["radius"]), int(unit["id"]))
				if not is_nan(settled) and absf(settled - float(reservation["to"])) <= m.BODY_GAP:
					move_actor(unit, settled, false); unit.erase("yield")
			continue
		if unit["kind"] == "hero" and m.sides[int(unit["side"])]["stance"] == "cover":
			var direction = 1.0 if unit["side"] == 0 else -1.0
			var allies = m.living(int(unit["side"]), false).filter(func(u): return u["kind"] == "unit" and float(u["range"]) < 100.0 and not u.has("yield"))
			allies.sort_custom(func(a, b): return float(a["x"]) > float(b["x"]) if unit["side"] == 0 else float(a["x"]) < float(b["x"]))
			if not allies.is_empty():
				var front = allies[0]
				var rear = float(front["x"]) - direction * (float(unit["radius"]) + float(front["radius"]) + 9.0)
				if (float(unit["x"]) - float(front["x"])) * direction > -float(unit["radius"]) and space_free(rear, float(unit["radius"]), int(unit["id"])):
					unit["yield"] = {"from": unit["x"], "to": rear, "at": m.tick, "duration": yield_ticks(unit, float(unit["x"]), rear)}; unit["releaseAt"] = -1; continue
		if m.tick < int(unit["staggerUntil"]): unit["phase"] = "idle"; continue
		if unit["kind"] == "hero" and m.sides[int(unit["side"])]["stance"] == "retreat":
			unit["releaseAt"] = -1
			var home = m.spawn_x(int(unit["side"]), unit["contentId"])
			var desired = move_toward(float(unit["x"]), home, float(unit["speed"]) / 30.0)
			move_actor(unit, constrained_x(unit, desired))
			unit["phase"] = "walk" if absf(float(unit["x"]) - float(unit["previousX"])) > 0.01 else "idle"
			if absf(float(unit["x"]) - home) < 2.0:
				unit["garrisoned"] = true; unit["phase"] = "garrison"
			continue
		var target = nearest_enemy(unit)
		if target.is_empty(): unit["phase"] = "idle"; continue
		var in_range = distance(unit, target) <= float(unit["range"]) and legal_contact(unit, target)
		if int(unit["releaseAt"]) >= 0:
			var locked = m.entity_by_id(int(unit["targetId"]))
			if locked.is_empty() or float(locked["hp"]) <= 0.0 or locked.get("garrisoned", false) or distance(unit, locked) > float(unit["range"]) + 8.0 or not legal_contact(unit, locked):
				unit["releaseAt"] = -1; unit["phase"] = "idle"
			elif m.tick >= int(unit["releaseAt"]):
				release(unit, locked)
			else:
				unit["facing"] = signf(float(locked["x"]) - float(unit["x"]))
				unit["phase"] = "windup"
			continue
		if in_range:
			unit["facing"] = signf(float(target["x"]) - float(unit["x"]))
			unit["phase"] = "recover" if m.tick - int(unit["releasedAt"]) < 12 else "idle"
			if m.tick >= int(unit["nextAttack"]):
				unit["targetId"] = target["id"]
				unit["releaseAt"] = m.tick + int(unit["windup"])
				unit["attackStartedAt"] = m.tick
				unit["phase"] = "windup"
			continue
		var direction = 1.0 if unit["side"] == 0 else -1.0
		var movement = float(unit["speed"]) * (1.0 + clampf(bonus(unit, "moveBonus"), 0.0, 0.35)) * (1.0 - clampf(bonus(unit, "slow"), 0.0, 0.7)) / 30.0
		if int(unit.get("rushUntil", 0)) > m.tick: movement *= 1.25
		if unit.get("rushArmed", false):
			unit["rushArmed"] = false
			unit["rushUntil"] = m.tick + ceili((8.0 + float(m.modifiers(int(unit["side"])).get("rushBuffAddSec", 0.0))) * 30.0)
		var desired = float(unit["x"]) + direction * minf(movement, maxf(0.0, distance(unit, target) - float(unit["range"]) + 1.0))
		move_actor(unit, constrained_x(unit, desired))
		var moved = absf(float(unit["x"]) - float(unit["previousX"]))
		unit["phase"] = "walk" if moved > 0.01 else "idle"
		# Support soldiers deliberately step into a rear rank to let short weapons reach the front.
		if moved <= 0.01 and float(unit["range"]) < 100.0:
			for ally in grounded():
				if ally["side"] != unit["side"] or ally["id"] == unit["id"] or float(ally["range"]) < 100.0 or float(ally["speed"]) <= 0.0: continue
				if (float(ally["x"]) - float(unit["x"])) * direction < 0.0 or distance(unit, ally) > m.BODY_GAP + 2.0: continue
				var rear = float(unit["x"]) - direction * (float(unit["radius"]) + float(ally["radius"]) + m.BODY_GAP)
				if space_free(rear, float(ally["radius"]), int(ally["id"])):
					ally["yield"] = {"from": ally["x"], "to": rear, "at": m.tick, "duration": yield_ticks(ally, float(ally["x"]), rear)}; ally["releaseAt"] = -1
				break

func release(source: Dictionary, target: Dictionary) -> void:
	var side = int(source["side"])
	var mods = m.modifiers(side)
	var haste = bonus(source, "attackSpeedBonus") + (float(mods.get("unitAttackSpeedBonus", 0.0)) if source["kind"] == "unit" else 0.0) - bonus(source, "suppression")
	source["nextAttack"] = m.tick + ceili(float(source["period"]) / (1.0 + clampf(haste, -0.8, 0.3)))
	source["releaseAt"] = -1; source["releasedAt"] = m.tick; source["phase"] = "recover"
	var raw = float(source["attack"]) * (1.0 + clampf(bonus(source, "attackBonus"), 0.0, 0.3))
	var extra = {"weaponId": source["weaponId"], "canDamageBase": true}
	var special = source.get("special", {})
	if special.has("firstContactBonus") and not source.get("firstContactUsed", false) and float(source["runDistance"]) >= float(special.get("minRunDistance", 100.0)):
		extra["conditionalBonus"] = special["firstContactBonus"]; source["firstContactUsed"] = true
	if source.get("rushFirstHit", false):
		extra["conditionalBonus"] = float(extra.get("conditionalBonus", 0.0)) + 0.2 + float(mods.get("rushFirstAttackBonus", 0.0)); source["rushFirstHit"] = false
	for key in ["splashRadius", "maxTargets", "suppressionMagnitude", "suppressionDurationSec"]:
		if special.has(key): extra[key] = special[key]
	if special.has("suppressStatusId"): extra["suppressionMagnitude"] = 0.2; extra["suppressionDurationSec"] = special["suppressDurationSec"]
	fire(source, target, raw, source["damageType"], extra)

func fire(source: Dictionary, target: Dictionary, raw: float, damage_type: String, extra: Dictionary = {}) -> void:
	var weapon = String(extra.get("weaponId", source.get("weaponId", "W02")))
	var metadata = m.db.get_row("weapons", weapon)
	var profile = m.db.profile(source.get("visualId", source.get("contentId", "")))
	if source.get("kind") == "turret":
		profile = profile.duplicate()
		var port = EpochData.turret_muzzle(int(source["slot"]))
		profile["muzzle"] = [port.x, port.y]
	var direction = 1.0 if int(source["side"]) == 0 else -1.0
	var x = float(source["x"]) + direction * minf(float(profile["muzzle"][0]), maxf(0.0, absf(float(target["x"]) - float(source["x"])) - float(target["radius"]) - 1.0))
	m.emit_event("release", x, int(source["side"]), {"sourceId": source["id"], "targetId": target["id"], "weaponId": weapon, "fromX": source["x"], "toX": target["x"], "muzzleY": profile["muzzle"][1]})
	if float(metadata.get("projectileSpeed", 0)) > 0.0:
		m.projectiles.append({"id": m.id(), "x": x, "previousX": x, "direction": direction, "speed": metadata["projectileSpeed"],
			"source": source.duplicate(true), "damage": raw, "damageType": damage_type, "weaponId": weapon, "extra": extra.duplicate(true),
			"muzzleY": profile["muzzle"][1], "originX": x, "targetX": target["x"],
			"targetHeight": 131.25 if target["kind"] == "base" else m.db.profile(target.get("visualId", target["contentId"]))["hit"][1],
			"bornTick": m.tick, "hitIds": [], "remaining": int(extra.get("pierceTargets", 1)), "targetId": target["id"]})
	else:
		hit(source, target, raw, damage_type, extra)
		if weapon == "W07":
			var visited = [target["id"]]
			var previous = target
			for i in range(1, int(source.get("special", {}).get("chainTargets", 1))):
				var candidates = m.living(1 - int(source["side"]), false).filter(func(u): return not visited.has(u["id"]) and absf(float(u["x"]) - float(previous["x"])) < 170.0)
				if candidates.is_empty(): break
				candidates.sort_custom(func(a, b): return absf(float(a["x"]) - float(previous["x"])) < absf(float(b["x"]) - float(previous["x"])))
				var next = candidates[0]; visited.append(next["id"])
				hit(source, next, raw * pow(float(source["special"].get("chainFalloff", 0.6)), i), damage_type, extra)
				m.emit_event("chain", float(previous["x"]), int(source["side"]), {"toX": next["x"], "targetId": next["id"]}); previous = next

func update_turrets() -> void:
	for side in range(2):
		for tower in m.sides[side]["turrets"]:
			if m.tick < int(tower["nextAttack"]): continue
			var row = m.db.get_row("turrets", tower["contentId"])
			var targets = m.living(1 - side, false).filter(func(u): return absf(float(u["x"]) - m.BASE_POSITIONS[side]) <= float(row["range"]) + float(u["radius"]))
			if targets.is_empty(): continue
			targets.sort_custom(func(a, b): return absf(float(a["x"]) - m.BASE_POSITIONS[side]) < absf(float(b["x"]) - m.BASE_POSITIONS[side]))
			var weapon = "W05" if row["mode"] == "siege" else "W04"
			var source = {"id": tower["id"], "contentId": tower["contentId"], "side": side, "x": m.BASE_POSITIONS[side], "kind": "turret", "slot": tower["slot"], "weaponId": weapon, "eraId": row["eraId"], "role": "turret"}
			var damage = float(row["attackBase"]) * float(m.db.era(row["eraId"])["hpAttackMultiplier"]) * (1.0 + clampf(float(m.modifiers(side).get("turretAttackBonus", 0.0)) + m.research_level(side, "tower-attack") * 0.15, 0.0, 0.3))
			fire(source, targets[0], damage, row["damageType"], {"weaponId": weapon, "splashRadius": row["splashRadius"], "maxTargets": row["maxTargets"], "canDamageBase": false})
			tower["nextAttack"] = m.tick + ceili(float(row["attackPeriodSec"]) * 30)

func update_projectiles() -> void:
	var surviving = []
	for p in m.projectiles:
		p["previousX"] = p["x"]
		p["x"] = float(p["x"]) + float(p["direction"]) * float(p["speed"]) / 30.0
		var low = minf(float(p["x"]), float(p["previousX"]))
		var high = maxf(float(p["x"]), float(p["previousX"]))
		var targets = m.living(1 - int(p["source"]["side"])).filter(func(u): return not p["hitIds"].has(u["id"]) and float(u["x"]) + float(u["radius"]) >= low and float(u["x"]) - float(u["radius"]) <= high)
		targets.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]) if float(p["direction"]) > 0.0 else float(a["x"]) > float(b["x"]))
		for target in targets:
			p["hitIds"].append(target["id"])
			hit(p["source"], target, float(p["damage"]), p["damageType"], p["extra"])
			var radius = float(p["extra"].get("splashRadius", 0))
			if radius > 0:
				var splash = m.living(1 - int(p["source"]["side"]), false).filter(func(u): return u["id"] != target["id"] and absf(float(u["x"]) - float(target["x"])) <= radius)
				for secondary in splash.slice(0, maxi(0, int(p["extra"].get("maxTargets", 3)) - 1)): hit(p["source"], secondary, float(p["damage"]), p["damageType"], p["extra"])
			p["remaining"] = int(p["remaining"]) - 1
			if int(p["remaining"]) <= 0: break
		if int(p["remaining"]) > 0 and float(p["x"]) > 20.0 and float(p["x"]) < 1580.0 and m.tick - int(p["bornTick"]) < 180: surviving.append(p)
	m.projectiles = surviving

func hit(source: Dictionary, target: Dictionary, raw: float, damage_type: String, extra: Dictionary = {}) -> void:
	m.pending_hits.append({"source": source.duplicate(true), "targetId": target["id"], "raw": raw, "type": damage_type, "extra": extra.duplicate(true)})

func damage_for(source: Dictionary, target: Dictionary, raw: float, damage_type: String, extra: Dictionary) -> int:
	if raw <= 0.0: return 0
	if source.get("neutral", false):
		if target["kind"] == "base": return 0
		return maxi(0, floori(minf(raw, float(target["maxHp"]) * float(m.db.rules["randomEvents"]["maximumDamageHpRatioPerEvent"]))))
	var skill = extra.has("skillId")
	if target["kind"] == "base" and skill and not bool(extra.get("canDamageBase", false)): return 0
	var mods = m.modifiers(int(source["side"]))
	var conditional = float(extra.get("conditionalBonus", 0.0))
	if target["kind"] != "base" and target.get("heavy", false): conditional += float(mods.get("heavyConditionalBonus", 0.0))
	if not status(target, "ST01").is_empty(): conditional += float(extra.get("brokenArmorBonus", 0.0))
	var mark = status(target, "ST04")
	var weapon_id = String(extra.get("weaponId", source.get("weaponId", "W02")))
	var projectile_speed = float(m.db.get_row("weapons", weapon_id).get("projectileSpeed", 0))
	if not mark.is_empty() and ["physical", "pierce"].has(damage_type) and int(mark.get("charges", 0)) > 0 and projectile_speed > 0.0:
		conditional += float(mark["conditionalBonus"]); mark["charges"] = int(mark["charges"]) - 1
	var armor = maxf(0.0, float(target.get("armor", 0.0)))
	armor *= (1.0 - float(status(target, "ST01").get("armorBreak", 0.0))) * (0.65 if damage_type == "pierce" else 1.0)
	var mitigation = 1.0 - float(target.get("energyResistance", 0.0)) if damage_type == "energy" else 100.0 / (100.0 + armor)
	var category = "base" if target["kind"] == "base" else ("heavy" if target.get("heavy", false) else "light")
	var counter = float(m.db.rules["damage"]["counter"][damage_type][category])
	var role_counter = {"front": "ranged", "ranged": "anti_armor", "anti_armor": "heavy", "heavy": "front"}
	if not skill and source.get("kind") == "unit" and target["kind"] == "unit" and role_counter.get(source.get("role")) == target["role"]: counter *= 1.3
	var value = raw * (1.0 + clampf(conditional, 0.0, 0.35)) * mitigation * counter
	if extra.get("weaponId", "W02") in ["W01", "W03", "W04", "W05"]: value *= 1.0 - clampf(bonus(target, "projectileReduction"), 0.0, 0.35)
	if target["kind"] == "base":
		if skill: value *= 0.35
		elif source.get("role") == "heavy": value *= 2.6
		if m.elapsed >= float(m.db.rules["overtime"]["secondSec"]): value *= 2.0
		elif m.elapsed >= float(m.db.rules["overtime"]["firstSec"]): value *= 1.5
	return maxi(1, floori(value))

func apply_hits() -> void:
	var losses = {}
	var seen_casts = {}
	var delayed_statuses = []
	var normal_damage_targets = {}
	var neutral_damage_targets = {}
	for entry in m.pending_hits:
		if not entry["extra"].has("castId"): continue
		var key = str(int(entry["extra"]["castId"]))
		if not m.cast_targets.has(key): m.cast_targets[key] = {"until": m.tick + 300, "ids": []}
		var group = m.cast_targets[key]["ids"]
		if not group.has(entry["targetId"]) and group.size() < 6: group.append(entry["targetId"])
	var index = 0
	while index < m.pending_hits.size() and index < 800:
		var entry = m.pending_hits[index]; index += 1
		var target = m.entity_by_id(int(entry["targetId"]))
		if target.is_empty() or float(target["hp"]) <= 0.0: continue
		var source = entry["source"]
		var extra = entry["extra"]
		var cast_group = m.cast_targets.get(str(int(extra.get("castId", -1))), {})
		if not cast_group.is_empty() and not cast_group["ids"].has(target["id"]): continue
		var amount = float(damage_for(source, target, float(entry["raw"]), entry["type"], extra))
		var absorbed = 0.0
		var had_shield = not target["shields"].is_empty()
		target["shields"].sort_custom(func(a,b):return int(a["until"])<int(b["until"]))
		for shield in target["shields"]:
			var part = minf(amount, float(shield["hp"])); shield["hp"] = float(shield["hp"]) - part; amount -= part; absorbed += part
		target["shields"] = target["shields"].filter(func(s): return float(s["hp"]) > 0.0)
		losses[target["id"]] = float(losses.get(target["id"], 0.0)) + amount
		if amount > 0 or absorbed > 0:
			var pressure = target.get("pressureHistory", []).filter(func(record): return int(record["at"]) > m.tick - 90)
			pressure.append({"at": m.tick, "amount": amount + absorbed})
			target["pressureHistory"] = pressure
			target["hitAt"] = m.tick; target["hitDirection"] = signf(float(target["x"]) - float(source["x"]))
			if source.get("neutral", false): neutral_damage_targets[target["id"]] = true
			else:
				normal_damage_targets[target["id"]] = true
				m.sides[int(source["side"])]["damageDealt"] = float(m.sides[int(source["side"])]["damageDealt"]) + amount
			m.emit_event("hit", float(target["x"]), int(source["side"]), {"sourceId": source["id"], "targetId": target["id"], "amount": amount, "absorbed": absorbed, "weaponId": extra.get("weaponId", source.get("weaponId", "W02")), "damageType": entry["type"], "skillId": extra.get("skillId", ""), "fromX": source["x"], "heavy": source.get("heavy", false)})
		if had_shield and target["shields"].all(func(s): return float(s["hp"]) <= 0.0):
			m.emit_event("shieldBreak", float(target["x"]), int(target["side"]), {"targetId": target["id"]})
			var spec = m.specification(int(target["side"]))
			if target["kind"] == "hero" and spec.has("shieldBreakDamageBase") and m.tick >= int(target["counterReadyAt"]):
				target["counterReadyAt"] = m.tick + 240
				m.scheduled.append({"due": m.tick + 1, "kind": "counter", "source": target.duplicate(true), "x": target["x"], "damage": float(spec["shieldBreakDamageBase"]) * float(m.db.era(target["eraId"])["hpAttackMultiplier"])})
		if target["kind"] != "base":
			for effect in extra.get("statuses", []): delayed_statuses.append({"target":target,"effect":effect})
			if extra.has("suppressionMagnitude"): m.abilities.add_status(target, "ST02", float(extra.get("suppressionDurationSec", 4.0)), {"suppression": float(extra["suppressionMagnitude"])})
			if extra.has("displace"):
				var multiplier = 0.2 if target.get("heavy", false) else (0.5 if target["kind"] == "hero" else 1.0)
				var movement = float(extra["displace"]) * multiplier * (1.0 - clampf(float(m.modifiers(int(target["side"])).get("displacementResistance", 0.0)), 0.0, 0.8))
				target["x"] = constrained_x(target, float(target["x"]) + movement)
				m.abilities.add_status(target, "ST09", 0.1, {})
		var conductive = status(target, "ST05")
		var cast_id = int(extra.get("castId", source["id"]))
		if amount + absorbed > 0 and entry["type"] == "energy" and not conductive.is_empty() and not extra.get("branch", false):
			target["statuses"] = target["statuses"].filter(func(s):return s["id"] != "ST05")
			var visited = cast_group["ids"] if not cast_group.is_empty() else seen_casts.get(cast_id, [])
			if not visited.has(target["id"]): visited.append(target["id"])
			var neighbors = m.living(int(target["side"]), false).filter(func(u): return not visited.has(u["id"]) and absf(float(u["x"]) - float(target["x"])) <= 150.0)
			if not neighbors.is_empty() and visited.size() < 6:
				var next = neighbors[0]; visited.append(next["id"])
				var branch = extra.duplicate(true); branch["branch"] = true
				branch["statuses"] = [];branch.erase("displace")
				hit(source, next, float(entry["raw"]) * float(m.modifiers(int(source["side"])).get("conductiveChainRatio", 0.4)), "energy", branch)
				m.emit_event("chain", float(target["x"]), int(source["side"]), {"toX": next["x"], "targetId": next["id"]})
			seen_casts[cast_id] = visited
	for target_id in losses.keys():
		var target = m.entity_by_id(int(target_id)); target["hp"] = maxf(0.0, float(target["hp"]) - float(losses[target_id]))
	for record in delayed_statuses:
		if float(record["target"]["hp"]) > 0.0:
			var effect = record["effect"];m.abilities.add_status(record["target"],effect["id"],float(effect["duration"]),effect.get("data",{}))
	for target in m.entities:
		if float(target["hp"]) <= 0.0 and target.get("phase") != "dead": kill(target, neutral_damage_targets.has(target["id"]) and not normal_damage_targets.has(target["id"]))
	m.pending_hits = []

func kill(unit: Dictionary, natural: bool = false) -> void:
	if unit.get("phase") == "dead": return
	unit["hp"] = 0.0; unit["phase"] = "dead"; unit["deathAt"] = m.tick; unit["statuses"] = []; unit["shields"] = []; unit.erase("yield"); unit.erase("charge")
	m.emit_event("death", float(unit["x"]), int(unit["side"]), {"targetId": unit["id"], "kind": unit["kind"]})
	var side = int(unit["side"])
	if unit["kind"] == "unit" and not natural:
		var content = m.db.get_row("units", unit["contentId"])
		var experience = roundi(float(content["killKnowledge"]) * m.db.knowledge_multiplier(unit["eraId"]))
		var bounty = floori(float(content["bountyGold"]) * float(m.db.era(unit["eraId"])["costMultiplier"]) * (1.0 + clampf(float(m.modifiers(1 - side).get("bountyBonus", 0.0)), 0.0, 0.3)))
		m.sides[1 - side]["kills"] = int(m.sides[1 - side]["kills"]) + 1
		if m.config["mode"] != "trial":
			m.sides[1 - side]["gold"] = float(m.sides[1 - side]["gold"]) + bounty
			m.sides[1 - side]["knowledge"] = float(m.sides[1 - side]["knowledge"]) + experience
			m.sides[side]["knowledge"] = float(m.sides[side]["knowledge"]) + floori(experience * 0.65)
			m.emit_event("reward", float(unit["x"]), 1 - side, {"amount": bounty, "xp": experience})
	elif unit["kind"] == "hero": m.sides[side]["heroRespawnAt"] = m.tick + ceili((25.0 - float(m.modifiers(side).get("respawnReductionSec", 0.0))) * 30.0)
	elif unit["kind"] == "summon" and natural: m.sides[side]["gold"] = float(m.sides[side]["gold"]) + float(m.specification(side).get("naturalExpiryGold", 0.0))
