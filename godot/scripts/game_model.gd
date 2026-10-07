class_name GameModel
extends Node

signal changed
signal event_emitted(event: Dictionary)

const HZ = 30
const STEP = 1.0 / HZ
const BASE_POSITIONS = [80.0, 1520.0]
const BODY_GAP = 4.0

var db: EpochData
var combat
var abilities
var environment
var config = {}
var sides = []
var entities = []
var projectiles = []
var scheduled = []
var fields = []
var pending_hits = []
var pending_events = []
var tick = 0
var next_id = 1
var rng = 1
var paused = false
var winner = -1
var accumulator = 0.0
var boss_thresholds = []
var cast_targets = {}
var last_action_sequence = -1
var max_era = "A10"
var modifier_cache = [{}, {}]
var last_restore_error = ""

var elapsed: float:
	get: return float(tick) / HZ
var interpolation: float:
	get: return clampf(accumulator / STEP, 0.0, 1.0)
var ally_era: int:
	get: return db.era_index(sides[0]["eraId"]) + 1
var enemy_era: int:
	get: return db.era_index(sides[1]["eraId"]) + 1
var ally_base_hp: float:
	get: return float(base(0).get("hp", 0))
var enemy_base_hp: float:
	get: return float(base(1).get("hp", 0))
var units: Array:
	get: return entities.filter(func(u): return u["kind"] != "base")

func _init() -> void:
	db = EpochData.new()
	combat = EpochCombat.new(self)
	abilities = EpochSkills.new(self)
	environment = EpochEnvironment.new(self)
	reset_battle()

func reset_battle(options: Dictionary = {}) -> void:
	config = {"mode": "standard", "missionId": "", "difficultyId": "D02", "seed": 42571,
		"loadout": db.default_loadout(), "enemyLoadout": db.default_loadout("H03"), "heroEnabled": true}
	config.merge(options.duplicate(true), true)
	for key in ["loadout", "enemyLoadout"]:
		if not db.valid_loadout(config[key]): config[key] = db.default_loadout()
	var mission = db.get_row("missions", String(config["missionId"]))
	if not mission.is_empty():
		var opponent = db.get_row("enemy-profiles", mission["enemyProfileId"])
		var build = db.get_row("builds", opponent.get("buildId", ""))
		if not build.is_empty():
			config["enemyLoadout"] = {"heroId": build["heroId"], "specializationId": build["specializationId"], "commonSkillIds": build["commonSkillIds"].duplicate(), "relicIds": [], "talentIds": config["loadout"]["talentIds"].duplicate()}
		config["enemyProfileId"] = mission["enemyProfileId"]
	var starting_era = String(config.get("startingEraId", mission.get("startingEraId", "A1")))
	max_era = String(config.get("maximumEraId", mission.get("maximumEraId", db.last_era())))
	tick = 0
	next_id = 1
	rng = int(config["seed"]) if int(config["seed"]) != 0 else 42571
	paused = false
	winner = -1
	accumulator = 0.0
	last_action_sequence = -1
	entities = []
	projectiles = []
	scheduled = []
	fields = []
	pending_hits = []
	pending_events = []
	boss_thresholds = []
	cast_targets = {}
	sides = []
	for side in range(2):
		var loadout = config["loadout" if side == 0 else "enemyLoadout"].duplicate(true)
		var gold = float(mission.get("playerStartingGold" if side == 0 else "enemyStartingGold", 240.0 * float(db.era(starting_era)["costMultiplier"])))
		sides.append({"eraId": starting_era, "gold": gold, "knowledge": 0.0, "command": 50.0,
			"loadout": loadout, "stance": "cover", "stanceReadyAt": 0, "queue": [], "cooldowns": {},
			"upgrades": [], "research": {}, "unlockedSlots": 1, "turrets": [], "heroRespawnAt": 0,
			"rushDeadline": 0, "rushSpawns": 0, "kills": 0, "ageSpecialReadyAt": 0, "aiNext": 75,
			"activeItems": {"war-drum": 2, "smoke-bomb": 2, "chrono-crate": 3}, "itemCooldowns": {}, "damageDealt": 0.0})
		var bonus = float(modifiers(side).get("baseHpBonus", 0.0))
		if side == 1: bonus += float(mission.get("bossParameters", {}).get("enemyBaseHpBonus", 0.0))
		var hp = floorf(float(db.era(starting_era)["baseHp"]) * (1.0 + bonus))
		entities.append({"id": id(), "contentId": "base-%d" % side, "side": side, "kind": "base", "eraId": starting_era,
			"x": BASE_POSITIONS[side], "previousX": BASE_POSITIONS[side], "hp": hp, "maxHp": hp, "radius": 55.0,
			"armor": 20.0, "energyResistance": 0.1, "phase": "idle", "shields": [], "statuses": [], "role": "base",
			"heavy": true, "bornTick": 0, "hitAt": -100, "releasedAt": -100, "deathAt": -1})
		if bool(config.get("heroEnabled", true)):
			spawn(side, String(loadout["heroId"]), starting_era, "hero")
	var prebuilt = mission.get("bossParameters", {}).get("prebuiltTurretId")
	if prebuilt != null: act({"type": "turret", "side": 1, "turretId": prebuilt, "slot": 0})
	environment.reset(int(config["seed"]))
	changed.emit()

func id() -> int:
	var result = next_id
	next_id += 1
	return result

func random_index(bound: int) -> int:
	rng = int((int(rng) * 1664525 + 1013904223) & 0xffffffff)
	return int(rng % maxi(1, bound))

func base(side: int) -> Dictionary:
	for entity in entities:
		if entity["kind"] == "base" and int(entity["side"]) == side: return entity
	return {}

func entity_by_id(entity_id: int) -> Dictionary:
	for entity in entities:
		if int(entity["id"]) == entity_id: return entity
	return {}

func hero(side: int, include_garrison: bool = true) -> Dictionary:
	for entity in entities:
		if entity["kind"] == "hero" and int(entity["side"]) == side and float(entity["hp"]) > 0.0:
			if include_garrison or not bool(entity.get("garrisoned", false)): return entity
	return {}

func living(side: int = -1, include_base: bool = true) -> Array:
	return entities.filter(func(u): return float(u["hp"]) > 0.0 and not bool(u.get("garrisoned", false)) and (side == -1 or int(u["side"]) == side) and (include_base or u["kind"] != "base"))

func population(side: int) -> int:
	return living(side, false).filter(func(u): return u["kind"] != "hero").size()

func modifiers(side: int) -> Dictionary:
	var signature = [sides[side]["loadout"].hash(), sides[side]["upgrades"].hash()]
	if modifier_cache[side].get("signature", []) != signature:
		modifier_cache[side] = {"signature": signature, "value": db.modifiers(sides[side]["loadout"], sides[side]["upgrades"])}
	return modifier_cache[side]["value"]

func specification(side: int) -> Dictionary:
	return db.get_row("specializations", sides[side]["loadout"]["specializationId"]).get("effects", {})

func command_max(side: int) -> float:
	return minf(110.0, 100.0 + float(modifiers(side).get("commandMaxAdd", 0.0)))

func era_cost(side: int) -> float:
	var cost = db.era(sides[side]["eraId"])["nextEvolutionKnowledge"]
	return 0.0 if cost == null else float(cost)

func unit_cost(side: int, unit_id: String) -> int:
	var unit = db.get_row("units", unit_id)
	return int(ceil(float(unit["costBase"]) * float(db.era(unit["eraId"])["costMultiplier"]) * (1.0 - clampf(float(modifiers(side).get("unitCostReduction", 0.0)), 0.0, 0.2))))

func research_level(side: int, key: String) -> int:
	return int(sides[side]["research"].get(key, 0))

func research_cost(side: int, key: String) -> int:
	var row = db.research(key)
	return int(ceil(float(row.get("price", 0)) * (1.0 + research_level(side, key) * 0.65) * float(db.era(sides[side]["eraId"])["costMultiplier"])))

func heavy_unlocked(side: int) -> bool:
	return config["mode"] == "trial" or research_level(side, "heavy-unlock") > 0

func spawn_x(side: int, content_id: String) -> float:
	var sign_direction = 1.0 if side == 0 else -1.0
	return BASE_POSITIONS[side] + sign_direction * (55.0 + float(db.profile(content_id)["radius"]) + BODY_GAP)

func spawn_blocked(side: int, content_id: String) -> String:
	if population(side) >= 29: return "人口已满"
	return "出口堵塞" if not combat.space_free(spawn_x(side, content_id), float(db.profile(content_id)["radius"])) else ""

func spawn(side: int, content_id: String, era_id: String, kind: String = "unit", spawn_position: float = NAN) -> Dictionary:
	var content = db.actor_content(content_id, era_id, kind)
	var profile = db.profile(db.visual_id(content_id, era_id))
	var x = spawn_x(side, content_id) if is_nan(spawn_position) else spawn_position
	var entity = {"id": id(), "contentId": content_id, "side": side, "kind": kind, "eraId": era_id,
		"x": x, "previousX": x, "hp": 1.0, "maxHp": 1.0, "radius": profile["radius"], "armor": content.get("armor", 0),
		"energyResistance": content.get("energyResistance", 0), "attack": 0.0, "range": content.get("range", 50),
		"speed": content.get("moveSpeed", 0), "weaponId": content.get("weaponId", "W02"), "damageType": content.get("damageType", "physical"),
		"heavy": bool(content.get("heavy", false)), "role": content.get("role", "hero"), "period": ceili(float(content.get("attackPeriodSec", 1.0)) * HZ),
		"windup": ceili(float(content.get("windupSec", 0.3)) * HZ), "nextAttack": tick, "releaseAt": -1, "targetId": -1,
		"phase": "idle", "facing": 1.0 if side == 0 else -1.0, "shields": [], "statuses": [], "bornTick": tick, "runDistance": 0.0, "attackStartedAt": -100,
		"releasedAt": -100, "hitAt": -100, "hitDirection": 0.0, "deathAt": -1, "skillAt": -100,
		"garrisoned": false, "rushArmed": false, "rushFirstHit": false, "rushUntil": 0, "staggerUntil": 0,
		"counterReadyAt": 0, "special": content.get("special", {}).duplicate(true)}
	entity["visualId"] = db.visual_id(content_id, era_id)
	refresh(entity, false)
	if kind == "unit" and era_id == sides[side]["eraId"] and tick < int(sides[side]["rushDeadline"]) and int(sides[side]["rushSpawns"]) > 0:
		entity["rushArmed"] = true
		entity["rushFirstHit"] = true
		sides[side]["rushSpawns"] = int(sides[side]["rushSpawns"]) - 1
	entities.append(entity)
	emit_event("spawn", x, side, {"targetId": entity["id"], "kind": kind})
	return entity

func refresh(entity: Dictionary, preserve: bool = true) -> void:
	if not ["hero", "unit"].has(entity["kind"]): return
	var side = int(entity["side"])
	var content = db.actor_content(entity["contentId"], entity["eraId"], entity["kind"])
	var mods = modifiers(side)
	var spec = specification(side) if entity["kind"] == "hero" else {}
	var multiplier = db.hp_multiplier(entity["eraId"])
	var hp_bonus = float(mods.get("heroHpBonus", 0.0)) + float(spec.get("heroHpBonus", 0.0)) if entity["kind"] == "hero" else float(mods.get("unitHpBonus", 0.0)) + (float(mods.get("frontHpBonus", 0.0)) if entity["role"] == "front" else 0.0)
	var ratio = float(entity["hp"]) / maxf(1.0, float(entity["maxHp"])) if preserve else 1.0
	entity["maxHp"] = floorf(float(content["hpBase"]) * multiplier * (1.0 + hp_bonus))
	entity["hp"] = clampf(floorf(float(entity["maxHp"]) * ratio), 1.0 if float(entity["hp"]) > 0.0 else 0.0, float(entity["maxHp"]))
	var role = "anti" if entity["role"] == "anti_armor" else String(entity["role"])
	var attack_bonus = float(spec.get("heroAttackBonus", 0.0)) if entity["kind"] == "hero" else float(mods.get("unitAttackBonus", 0.0)) + research_level(side, role + "-attack") * 0.15
	if entity["role"] == "front": attack_bonus += float(mods.get("frontAttackBonus", 0.0))
	entity["attack"] = float(content["attackBase"]) * db.attack_multiplier(entity["eraId"]) * (1.0 + clampf(attack_bonus, -0.9, 0.3))
	entity["range"] = float(content["range"]) + float(spec.get("rangeAdd", 0.0))
	if entity["role"] == "ranged": entity["range"] += research_level(side, "ranged-range") * 25.0 + float(mods.get("rangedRangeAdd", 0.0))
	entity["armor"] = float(content["armor"]) + (research_level(side, "front-armor") * 10.0 if entity["role"] == "front" else 0.0)
	entity["speed"] = float(content["moveSpeed"]) * (1.0 + float(spec.get("heroMoveBonus", 0.0)))
	entity["weaponId"] = content.get("weaponId", "W02")
	entity["damageType"] = content.get("damageType", "physical")
	entity["visualId"] = db.visual_id(entity["contentId"], entity["eraId"])
	entity["period"] = ceili(float(content.get("attackPeriodSec", 1.0)) * HZ)
	entity["signatureName"] = String(content.get("signatureName", ""))

func act(action: Dictionary, sequence: int = -1) -> Dictionary:
	var side = int(action.get("side", 0))
	if side < 0 or side > 1: return {"ok": false, "reason": "无效阵营"}
	if winner != -1: return {"ok": false, "reason": "对局已结束"}
	if sequence >= 0:
		if sequence <= last_action_sequence: return {"ok": false, "reason": "重复指令"}
		last_action_sequence = sequence
	var player = sides[side]
	var kind = String(action.get("type", ""))
	if paused and kind in ["train", "cast", "item", "ageSpecial", "stance"]: return fail("战斗已暂停")
	var result = {"ok": true}
	match kind:
		"train":
			var unit = db.get_row("units", String(action.get("unitId", "")))
			if unit.is_empty() or unit["eraId"] != player["eraId"]: return fail("只能招募当前时代兵种")
			if bool(unit["heavy"]) and not heavy_unlocked(side): return fail("先开放重型军团")
			if player["queue"].size() >= 5: return fail("训练队列已满")
			var cost = unit_cost(side, unit["id"])
			if float(player["gold"]) < cost: return fail("金币不足")
			var duration = ceili(float(unit["trainSec"]) * (1.0 - clampf(float(modifiers(side).get("trainingReduction", 0.0)), 0.0, 0.25)) * HZ)
			player["gold"] = float(player["gold"]) - cost
			player["queue"].append({"id": id(), "unitId": unit["id"], "eraId": player["eraId"], "paid": cost, "duration": duration, "remaining": duration, "advancedBy": [], "progressUsed": 0})
			emit_event("queue", BASE_POSITIONS[side], side, {"unitId": unit["id"]})
		"cancel":
			var found = false
			for index in range(player["queue"].size()):
				var order = player["queue"][index]
				if int(order["id"]) != int(action.get("queueId", -1)): continue
				player["gold"] = float(player["gold"]) + floorf(float(order["paid"]) * (1.0 if index > 0 or order["remaining"] == order["duration"] else 0.75))
				player["queue"].remove_at(index)
				found = true
				break
			if not found: return fail("训练项目已出营")
		"evolve":
			if player["eraId"] == max_era or era_cost(side) <= 0.0: return fail("已达本局时代上限")
			if float(player["knowledge"]) < era_cost(side): return fail("战斗经验不足")
			player["knowledge"] = float(player["knowledge"]) - era_cost(side)
			player["eraId"] = "A%d" % (db.era_index(player["eraId"]) + 2)
			var own_base = base(side)
			var ratio = float(own_base["hp"]) / float(own_base["maxHp"])
			var mission = db.get_row("missions", String(config["missionId"]))
			var bonus = float(modifiers(side).get("baseHpBonus", 0.0)) + (float(mission.get("bossParameters", {}).get("enemyBaseHpBonus", 0.0)) if side == 1 else 0.0)
			own_base["maxHp"] = floorf(float(db.era(player["eraId"])["baseHp"]) * (1.0 + bonus))
			own_base["hp"] = floorf(float(own_base["maxHp"]) * ratio)
			own_base["eraId"] = player["eraId"]
			var own_hero = hero(side)
			if not own_hero.is_empty():
				own_hero["eraId"] = player["eraId"]
				refresh(own_hero)
			player["rushDeadline"] = tick + ceili((30.0 + float(modifiers(side).get("rushEligibleAddSec", 0.0))) * HZ)
			player["rushSpawns"] = 3
			var upgrade_id = String(action.get("upgradeId", ""))
			if db.get_row("run-upgrades", upgrade_id).get("eraId") == player["eraId"]:
				player["upgrades"].append(upgrade_id)
				for actor in living(side,false):refresh(actor)
			environment.on_evolve()
			emit_event("evolve", BASE_POSITIONS[side], side, {"eraId": player["eraId"], "name": db.era(player["eraId"])["name"]})
		"research":
			var key = String(action.get("researchId", ""))
			var row = db.research(key)
			if row.is_empty() or research_level(side, key) >= int(row["max"]): return fail("强化已达上限")
			if key == "heavy-attack" and not heavy_unlocked(side): return fail("先开放重型军团")
			var cost = research_cost(side, key)
			if float(player["gold"]) < cost: return fail("金币不足")
			player["gold"] = float(player["gold"]) - cost
			player["research"][key] = research_level(side, key) + 1
			for unit in living(side, false): refresh(unit)
			emit_event("research", BASE_POSITIONS[side], side, {"name": row["name"]})
		"turret":
			var turret = db.get_row("turrets", String(action.get("turretId", "")))
			var slot = int(action.get("slot", -1))
			if turret.is_empty() or turret["eraId"] != player["eraId"] or slot < 0 or slot >= int(player["unlockedSlots"]): return fail("炮塔位置或时代无效")
			for existing in player["turrets"]:
				if int(existing["slot"]) == slot: return fail("先出售原有炮塔")
			var cost = ceili(float(turret["costBase"]) * float(db.era(turret["eraId"])["costMultiplier"]))
			if float(player["gold"]) < cost: return fail("金币不足")
			player["gold"] = float(player["gold"]) - cost
			var tower_id = id()
			player["turrets"].append({"id": tower_id, "contentId": turret["id"], "paid": cost, "slot": slot, "nextAttack": tick + 18})
			emit_event("build", BASE_POSITIONS[side], side, {"sourceId": tower_id, "turretId": turret["id"]})
		"sell":
			var found = false
			for i in range(player["turrets"].size()):
				if int(player["turrets"][i]["slot"]) == int(action.get("slot", -1)):
					player["gold"] = float(player["gold"]) + floorf(float(player["turrets"][i]["paid"]) * 0.6)
					player["turrets"].remove_at(i)
					found = true
					break
			if not found: return fail("该插槽没有炮塔")
		"unlockSlot":
			if int(player["unlockedSlots"]) >= 3: return fail("插槽已全部开放")
			var cost = [90, 180][int(player["unlockedSlots"]) - 1]
			if float(player["gold"]) < cost: return fail("金币不足")
			player["gold"] = float(player["gold"]) - cost
			player["unlockedSlots"] = int(player["unlockedSlots"]) + 1
		"stance":
			var own_hero = hero(side)
			if own_hero.is_empty(): return fail("指挥官正在重建")
			if tick < int(player["stanceReadyAt"]): return fail("站位指令间隔中")
			var stance = String(action.get("stance", "cover"))
			if not ["cover", "rush", "retreat"].has(stance): return fail("无效站位")
			if own_hero.get("garrisoned", false) and stance != "retreat":
				var free_x = combat.nearest_space(spawn_x(side, own_hero["contentId"]), float(own_hero["radius"]), int(own_hero["id"]))
				if is_nan(free_x): return fail("出口堵塞，稍后归队")
				own_hero["x"] = free_x
				own_hero["previousX"] = free_x
				own_hero["garrisoned"] = false
				own_hero["phase"] = "idle"
				own_hero["facing"] = 1.0 if side == 0 else -1.0
				emit_event("spawn", free_x, side, {"targetId": own_hero["id"]})
			if stance == "retreat" and not own_hero.get("garrisoned", false):
				var home = spawn_x(side, own_hero["contentId"])
				own_hero["yield"] = {"from": own_hero["x"], "to": home, "at": tick, "duration": maxi(15, ceili(absf(float(own_hero["x"]) - home) / (float(own_hero["speed"]) * 1.25) * HZ)), "retreat": true}
				own_hero["releaseAt"] = -1
			player["stance"] = stance
			player["stanceReadyAt"] = tick + 15
		"item": result = abilities.use_item(side, String(action.get("itemId", "")), float(action.get("x", BASE_POSITIONS[side])))
		"ageSpecial": result = abilities.use_age(side, float(action.get("x", -1.0)))
		"cast": result = abilities.cast(side, String(action.get("skillId", "")), float(action.get("x", -1.0)), int(action.get("targetId", -1)))
		_: return fail("未知指令")
	changed.emit()
	return result

func fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

func advance(delta: float) -> void:
	if paused or winner != -1: return
	accumulator += clampf(delta, 0.0, 0.25)
	while accumulator >= STEP and winner == -1:
		accumulator -= STEP
		step_tick()

func step_ticks(count: int) -> void:
	for i in range(count):
		if paused or winner != -1: break
		step_tick()

func step_tick() -> void:
	tick += 1
	for unit in entities: unit["previousX"] = unit["x"]
	for side in range(2):
		var player = sides[side]
		var mods = modifiers(side)
		player["gold"] = minf(99999.0, float(player["gold"]) + 2.5 * float(db.era(player["eraId"])["incomeMultiplier"]) * (1.0 + clampf(float(mods.get("incomeBonus", 0.0)), 0.0, 0.25)) / HZ)
		player["command"] = minf(command_max(side), float(player["command"]) + 3.0 / HZ)
		if not player["queue"].is_empty():
			var order = player["queue"][0]
			order["remaining"] = maxi(0, int(order["remaining"]) - 1)
			if int(order["remaining"]) == 0 and spawn_blocked(side, order["unitId"]).is_empty():
				player["queue"].pop_front()
				spawn(side, order["unitId"], order["eraId"])
		if int(player["heroRespawnAt"]) > 0 and tick >= int(player["heroRespawnAt"]) and combat.space_free(spawn_x(side, player["loadout"]["heroId"]), float(db.profile(player["loadout"]["heroId"])["radius"])):
			spawn(side, player["loadout"]["heroId"], player["eraId"], "hero")
			player["heroRespawnAt"] = 0
			player["stance"] = "cover"
	combat.update_statuses()
	abilities.update()
	environment.update()
	combat.update_units()
	combat.update_turrets()
	combat.update_projectiles()
	combat.apply_hits()
	for key in cast_targets.keys():
		if int(cast_targets[key]["until"]) <= tick: cast_targets.erase(key)
	_check_boss()
	if bool(config.get("aiEnabled", true)) and tick >= int(sides[1]["aiNext"]): _decide_enemy()
	if tick >= int(db.rules["overtime"]["burnStartsSec"]) * HZ and tick % HZ == 0:
		for side in range(2):
			var own_base = base(side)
			own_base["hp"] = maxf(0.0, float(own_base["hp"]) - float(own_base["maxHp"]) * 0.01)
	var left_down = float(base(0)["hp"]) <= 0.0
	var right_down = float(base(1)["hp"]) <= 0.0
	if left_down or right_down:
		winner = 2 if left_down and right_down else (0 if right_down else 1)
		emit_event("result", 800.0, winner, {"winner": winner, "elapsed": elapsed})
	entities = entities.filter(func(u): return float(u["hp"]) > 0.0 or u["kind"] == "base" or tick - int(u.get("deathAt", tick)) < 30)
	if tick % 3 == 0: changed.emit()

func _decide_enemy() -> void:
	var player = sides[1]
	var difficulty = db.rules["difficulty"][clampi(int(String(config["difficultyId"]).right(1)) - 1, 0, 2)]
	player["aiNext"] = tick + ceili(float(difficulty["decisionSec"]) * HZ)
	if random_index(1000) < int(float(difficulty["mistakeProbability"]) * 1000): return
	var mission = db.get_row("missions", String(config["missionId"]))
	var wave = mission.get("reinforcements", {})
	var deploying = true
	if not wave.is_empty():
		var wave_period = float(wave["periodSec"])
		deploying = elapsed < wave_period * int(wave["waves"]) and fmod(elapsed, wave_period) < float(wave["deploySec"])
	if player["eraId"] != max_era and era_cost(1) > 0 and float(player["knowledge"]) >= era_cost(1):
		act({"type": "evolve", "side": 1, "upgradeId": "R%d1" % (db.era_index(player["eraId"]) + 2)})
	var enemies = living(0, false)
	if not enemies.is_empty():
		var target = enemies.reduce(func(a, b): return a if float(a["x"]) > float(b["x"]) else b)
		if float(target["x"]) > 1110.0 and tick % 120 < 60:
			abilities.use_item(1, "smoke-bomb", float(target["x"]))
		var raid = db.age_special(player["eraId"])
		var research_reserve = era_cost(1) if player["eraId"] != max_era else 0.0
		var threatened = float(base(1)["hp"])/float(base(1)["maxHp"]) < 0.3
		var behind = enemy_era < ally_era
		if enemies.size() >= 3 and not behind and (float(player["knowledge"]) >= float(raid["cost"])+research_reserve or threatened):
			abilities.use_age(1,float(target["x"]))
		var own_hero = hero(1, false)
		if not own_hero.is_empty() and absf(float(own_hero["x"]) - float(target["x"])) < 550.0:
			var skill_id = db.get_row("heroes", player["loadout"]["heroId"])["signatureSkillId"]
			abilities.cast(1, skill_id, float(target["x"]), int(target["id"]))
			for common_id in player["loadout"]["commonSkillIds"]:
				abilities.cast(1, common_id, float(target["x"]), int(target["id"]))
	if not deploying: return
	if player["queue"].size() >= 3: return
	var own_army = living(1, false).filter(func(u): return u["kind"] == "unit")
	var profile_id = String(config.get("enemyProfileId", "AP01"))
	if own_army.size() >= 3 and not heavy_unlocked(1) and float(player["gold"]) >= research_cost(1, "heavy-unlock") + 45.0:
		act({"type": "research", "side": 1, "researchId": "heavy-unlock"})
	var slots = db.unit_slots(player["eraId"])
	var front_count = own_army.filter(func(u): return u["role"] == "front").size()
	var ranged_count = own_army.filter(func(u): return u["role"] == "ranged").size()
	var selection = 0 if front_count < maxi(1, ranged_count) else 1
	if own_army.size() >= 3:
		var roll = random_index(100)
		var heavy_threshold = 58 if profile_id == "AP04" else 78
		selection = 3 if roll > heavy_threshold and heavy_unlocked(1) else (2 if roll > 58 else (4 if roll > 44 else selection))
	if float(player["gold"]) >= unit_cost(1, slots[selection]["id"]): act({"type": "train", "side": 1, "unitId": slots[selection]["id"]})
	elif float(player["gold"]) >= unit_cost(1, slots[0]["id"]): act({"type": "train", "side": 1, "unitId": slots[0]["id"]})
	if own_army.size() >= (3 if profile_id == "AP03" else 5) and player["turrets"].is_empty() and float(player["gold"]) > (145.0 if profile_id == "AP03" else 220.0) * float(db.era(player["eraId"])["costMultiplier"]):
		act({"type": "turret", "side": 1, "slot": 0, "turretId": "TR%d1" % (db.era_index(player["eraId"]) + 1)})

func _check_boss() -> void:
	var mission = db.get_row("missions", String(config["missionId"]))
	var params = mission.get("bossParameters", {})
	if not params.has("thresholds"): return
	for threshold in params["thresholds"]:
		if boss_thresholds.has(threshold): continue
		if float(base(1)["hp"]) / float(base(1)["maxHp"]) <= float(threshold) and float(sides[1]["command"]) >= 20.0:
			sides[1]["command"] = float(sides[1]["command"]) - 20.0
			abilities.add_shield(base(1), 0.1, 4.0)
			boss_thresholds.append(threshold)

func emit_event(type: String, x: float, side: int, data: Dictionary = {}) -> void:
	var event = {"id": id(), "type": type, "tick": tick, "x": x, "side": side, "data": data.duplicate(true)}
	pending_events.append(event)
	if pending_events.size() > 4096: pending_events.pop_front()
	event_emitted.emit(event)

func consume_events() -> Array:
	var result = pending_events
	pending_events = []
	return result

func set_paused(value: bool) -> void:
	paused = value
	accumulator = 0.0
	changed.emit()

func snapshot() -> Dictionary:
	return {"version": 2, "contentVersion": "0.7.0", "environment": environment.snapshot(), "config": config.duplicate(true), "sides": sides.duplicate(true), "entities": entities.duplicate(true),
		"projectiles": projectiles.duplicate(true), "scheduled": scheduled.duplicate(true), "fields": fields.duplicate(true),
		"pending_hits": pending_hits.duplicate(true),
		"tick": tick, "next_id": next_id, "rng": rng, "winner": winner, "boss_thresholds": boss_thresholds.duplicate(),
		"last_action_sequence": last_action_sequence, "max_era": max_era, "cast_targets": cast_targets.duplicate(true)}

func reject_restore(reason: String) -> bool:
	last_restore_error = reason
	return false

func restore(data: Dictionary) -> bool:
	last_restore_error = ""
	var version = data.get("version", 0)
	if (not version is float and not version is int) or not is_finite(float(version)) or float(version) != int(version) or int(version) not in [1,2]: return reject_restore("Unsupported snapshot version")
	var legacy=int(version)==1 and not String(data.get("contentVersion","")).begins_with("0.7")
	if legacy:data=preload("res://scripts/epoch_snapshot_migration.gd").migrate(data,db)
	if not data.get("sides") is Array or not data.get("entities") is Array: return reject_restore("Invalid snapshot collections")
	if data.has("environment") and (not data["environment"] is Dictionary or not environment.can_restore(data["environment"])): return reject_restore("Invalid environment state")
	if data["sides"].size() != 2 or data["entities"].size() < 2 or data["entities"].size() > 180 or not data.get("config") is Dictionary: return false
	for key in ["projectiles","scheduled","fields","boss_thresholds","pending_hits"]:
		if not data.get(key, []) is Array: return false
	if not data.get("cast_targets", {}) is Dictionary or data.get("pending_hits", []).size() > 4096: return false
	for hit in data.get("pending_hits", []):
		if not hit is Dictionary or not hit.get("source") is Dictionary or not hit.get("extra") is Dictionary: return false
		for key in ["id","x","side","kind","eraId"]:
			if not hit["source"].has(key):return false
		if not hit.has("targetId") or not ["physical","pierce","blast","energy"].has(hit.get("type")): return false
		if not hit.get("raw") is float and not hit.get("raw") is int: return false
		if not is_finite(float(hit["raw"])) or float(hit["raw"]) < 0.0 or (int(hit["source"].get("side", -1)) not in [0,1] and not hit["source"].get("neutral", false)): return false
	for key in ["tick","next_id","rng","max_era"]:
		if not data.has(key): return false
	if db.era(String(data["max_era"])).is_empty() or int(data["tick"])<0: return false
	for player in data["sides"]:
		if not player is Dictionary: return false
		if not player.get("loadout") is Dictionary: return false
		if db.era(String(player.get("eraId", ""))).is_empty() or not db.valid_loadout(player.get("loadout", {})): return false
		for key in ["queue","cooldowns","upgrades","research","turrets","activeItems","itemCooldowns","stance","heroRespawnAt","rushDeadline","rushSpawns","ageSpecialReadyAt","aiNext","kills","unlockedSlots","damageDealt"]:
			if not player.has(key): return false
		for key in ["gold","knowledge","command"]:
			if not player.get(key) is int and not player.get(key) is float: return false
			if not is_finite(float(player[key])) or float(player[key])<0.0: return false
		if not player["queue"] is Array or player["queue"].size()>5: return false
		for key in ["cooldowns","research","activeItems","itemCooldowns"]:
			if not player[key] is Dictionary:return false
		if not player["turrets"] is Array or not player["upgrades"] is Array:return false
		if not player.get("itemActiveUntil",{}) is Dictionary:return false
		for item_id in EpochData.ITEMS:
			if not player["activeItems"].get(item_id) is float and not player["activeItems"].get(item_id) is int:return false
			if int(player["activeItems"][item_id])<0 or int(player["activeItems"][item_id])>int(EpochData.ITEMS[item_id]["charges"]):return false
		for order in player["queue"]:
			if not order is Dictionary:return false
			for key in ["id","unitId","eraId","duration","remaining","paid","advancedBy","progressUsed"]:
				if not order.has(key):return false
			if db.get_row("units",String(order["unitId"])).get("eraId")!=order["eraId"] or not order["advancedBy"] is Array:return false
			if float(order["duration"])<=0 or float(order["remaining"])<0 or float(order["remaining"])>float(order["duration"]):return false
	var unique_ids = {}
	var bases_found = [false,false]
	for entity in data["entities"]:
		if not entity is Dictionary: return false
		for key in ["id","kind","side","contentId","eraId","x","previousX","hp","maxHp","radius","phase","shields","statuses","hitAt","deathAt"]:
			if not entity.has(key): return false
		var identifier=int(entity["id"])
		if identifier<=0 or unique_ids.has(identifier) or int(entity["side"])<0 or int(entity["side"])>1: return false
		unique_ids[identifier]=true
		if not ["base","unit","hero","summon"].has(entity["kind"]) or db.era(String(entity["eraId"])).is_empty(): return false
		for key in ["x","previousX","hp","maxHp","radius"]:
			if not entity[key] is float and not entity[key] is int: return false
			if not is_finite(float(entity[key])): return false
		if float(entity["maxHp"])<=0 or float(entity["hp"])<0 or float(entity["hp"])>float(entity["maxHp"]) or float(entity["radius"])<=0: return false
		if not entity["shields"] is Array or not entity["statuses"] is Array:return false
		if entity["kind"]!="base":
			for key in ["speed","range","armor","energyResistance","attack","weaponId","role","period","windup","nextAttack","releaseAt","targetId","bornTick","runDistance","attackStartedAt","releasedAt","hitDirection","garrisoned","staggerUntil","special"]:
				if not entity.has(key):return reject_restore("Missing actor state: " + key)
		if entity["kind"]=="base": bases_found[int(entity["side"])]=true
		elif entity["kind"]!="summon" and db.get_row("heroes" if entity["kind"]=="hero" else "units",String(entity["contentId"])).is_empty(): return false
	if not bases_found[0] or not bases_found[1]: return false
	config = data["config"].duplicate(true)
	sides = data["sides"].duplicate(true)
	entities = data["entities"].duplicate(true)
	for entity in entities:
		if entity["kind"]!="base" and not entity.has("facing"):entity["facing"]=1.0 if int(entity["side"])==0 else -1.0
	projectiles = data.get("projectiles", []).duplicate(true)
	scheduled = data.get("scheduled", []).duplicate(true)
	fields = data.get("fields", []).duplicate(true)
	tick = int(data["tick"])
	next_id = int(data["next_id"])
	rng = int(data["rng"])
	winner = int(data.get("winner", -1))
	boss_thresholds = data.get("boss_thresholds", []).duplicate()
	cast_targets = data.get("cast_targets", {}).duplicate(true)
	last_action_sequence = int(data.get("last_action_sequence", -1))
	max_era = String(data["max_era"])
	modifier_cache=[{},{}]
	if legacy:preload("res://scripts/epoch_snapshot_migration.gd").refresh_legacy(self)
	environment.reset(int(config.get("seed", 42571)))
	if data.has("environment"): environment.restore(data["environment"])
	else:environment.next_event_at+=tick
	paused = false
	accumulator = 0.0
	pending_events = []
	pending_hits = data.get("pending_hits", []).duplicate(true)
	changed.emit()
	return true
