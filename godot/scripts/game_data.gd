class_name EpochData
extends RefCounted

const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
const ROLES = {"front": "前排", "ranged": "远程", "anti_armor": "破甲", "heavy": "重型", "hero": "指挥官"}
const TOWER_SPACING = 60.0
const TOWER_TOP = 285.0
const TOWER_STEP = 15.0
const BASE_FOOT_OFFSET = 6.25
static func turret_muzzle(slot: int) -> Vector2:
	return Vector2((slot - 1) * TOWER_SPACING + 28.0, TOWER_TOP + (slot % 2) * TOWER_STEP - BASE_FOOT_OFFSET - 18.75)

const RESEARCH = [
	{"id": "heavy-unlock", "name": "重型军团", "price": 105, "max": 1, "icon": "heavy", "description": "开放本时代的重型单位"},
	{"id": "front-attack", "name": "步兵锋刃", "price": 75, "max": 2, "icon": "sword", "description": "前排攻击 +15%"},
	{"id": "front-armor", "name": "步兵甲胄", "price": 60, "max": 3, "icon": "shield", "description": "前排护甲 +10"},
	{"id": "ranged-attack", "name": "支援火力", "price": 85, "max": 2, "icon": "target", "description": "远程攻击 +15%"},
	{"id": "anti-attack", "name": "破甲技术", "price": 85, "max": 2, "icon": "arrow", "description": "破甲兵攻击 +15%"},
	{"id": "heavy-attack", "name": "重型冲击", "price": 115, "max": 2, "icon": "tower", "description": "重型攻击 +15%"},
	{"id": "ranged-range", "name": "远程校准", "price": 70, "max": 3, "icon": "target", "description": "远程射程 +25"},
	{"id": "tower-attack", "name": "炮塔强化", "price": 95, "max": 2, "icon": "tower", "description": "基地炮塔攻击 +15%"}
]
const ITEMS = {
	"war-drum": {"name": "战鼓令", "cooldown": 22.0, "charges": 2, "icon": "drum", "target": false, "description": "全军攻击+18%、移速+12%，推进训练"},
	"smoke-bomb": {"name": "烟幕罐", "cooldown": 28.0, "charges": 2, "icon": "smoke", "target": true, "radius": 135.0, "description": "范围内敌军减速35%，持续5秒"},
	"chrono-crate": {"name": "时序补给", "cooldown": 30.0, "charges": 3, "icon": "crystal", "target": false, "description": "获得65金币、15军令并推进训练"}
}
var tables = {}
var rows = {}
var rules = {}
var loot = {}
var animations = {}

func _init() -> void:
	for name in ["eras", "heroes", "hero-evolutions", "era-specials", "units", "skills", "specializations", "talents", "relics", "run-upgrades", "turrets", "weapons", "missions", "builds", "enemy-profiles", "statuses"]:
		var parsed = _json(name)
		rows[name] = parsed if parsed is Array else []
		var index = {}
		for row in rows[name]:
			index[String(row["id"])] = row
		tables[name] = index
	rules = _json("rules")
	loot = _json("loot")
	animations = _json("animations")

func _json(name: String):
	var file = FileAccess.open("res://assets/data/%s.json" % name, FileAccess.READ)
	if file == null:
		push_error("Missing content table: " + name)
		return {}
	return JSON.parse_string(file.get_as_text())

func get_row(table: String, id: String) -> Dictionary:
	return tables.get(table, {}).get(id, {})

func era_index(id: String) -> int:
	return clampi(int(id.trim_prefix("A")) - 1, 0, rows.get("eras", []).size() - 1)

func era(id: String) -> Dictionary:
	return get_row("eras", id)

func attack_multiplier(id: String) -> float: return float(era(id).get("attackMultiplier", 1.0))
func hp_multiplier(id: String) -> float: return float(era(id).get("hpMultiplier", 1.0))
func knowledge_multiplier(id: String) -> float: return float(era(id).get("knowledgeMultiplier", 1.0))
func last_era() -> String: return String(rows["eras"][-1]["id"])
func age_special(id: String) -> Dictionary: return get_row("era-specials", id)
func hero_form(hero_id: String, era_id: String) -> Dictionary: return get_row("hero-evolutions", hero_id + "-" + era_id)
func visual_id(content_id: String, era_id: String) -> String:
	return content_id + "-" + era_id if content_id.begins_with("H") else content_id
func actor_content(content_id: String, era_id: String, kind: String) -> Dictionary:
	var content = get_row("heroes" if kind == "hero" else "units", content_id).duplicate(true)
	if kind == "hero": content.merge(hero_form(content_id, era_id), true)
	return content
func skill_name(skill_id: String, hero_id: String, era_id: String) -> String:
	if get_row("skills", skill_id).get("category") == "signature":
		return String(hero_form(hero_id, era_id).get("signatureName", get_row("skills", skill_id).get("name", "")))
	return String(get_row("skills", skill_id).get("name", ""))

func unit_slots(era_id: String) -> Array:
	var result = []
	for i in range(1, 6):
		result.append(get_row("units", "U%d%d" % [era_index(era_id) + 1, i]))
	return result

func profile(id: String) -> Dictionary:
	var family = "shield"
	var radius = 16.0
	var height = 96.0
	var material = "flesh"
	var muzzle = [36.0, 57.0]
	var over_shoulder = false
	if id.begins_with("U"):
		var slot = int(id.right(1))
		var content = get_row("units", id)
		var age = era_index(content.get("eraId", "A1")) + 1
		if slot == 2:
			family = "throw" if age == 1 else ("bow" if age < 4 else "gun")
			radius = 14.0
		elif slot == 3:
			family = "gun" if age == 4 else "spear"
			over_shoulder = family == "spear"
			muzzle = [65.0, 55.0]
		elif slot == 4:
			family = "mounted" if age < 4 else ("cannon" if age == 4 else "mech")
			radius = 38.0
			height = 124.0
		elif slot == 5:
			family = String(content.get("animationFamily", "gun"))
			height = 106.0
		elif age == 4:
			family = "gun"
		# Materials follow equipment, so wooden shields and unarmored archers sound distinct.
		family = String(content.get("animationFamily", family))
		material = String(content.get("material", "flesh"))
		over_shoulder = slot == 3 and family == "spear"
	elif id.begins_with("H"):
		var identity = id.split("-")[0]
		var form = get_row("hero-evolutions", id)
		var weapon = String(form.get("weaponId", get_row("heroes", identity).get("weaponId", "W02")))
		family = "gun" if weapon == "W04" else "bow" if weapon == "W03" else "throw" if weapon == "W01" else "mech" if weapon == "W07" else "shield"
		radius = 21.0
		height = 122.0
		muzzle = [42.0, 73.0]
		material = "metal" if era_index(String(form.get("eraId", "A1"))) >= 5 or identity == "H03" else "flesh"
	elif id == "summon-H04" or id.begins_with("SUM-"):
		family = "cannon"
		radius = 27.0
		height = 74.0
		material = "metal"
	var sheet = animations.get(id, {})
	return {"radius": float(sheet.get("bodyRadius", radius)), "height": height,
		"muzzle": sheet.get("muzzle", muzzle), "hit": sheet.get("hit", [0.0, height * 0.54]),
		"family": family, "material": material, "over_shoulder": over_shoulder}

func default_loadout(hero_id: String = "H01") -> Dictionary:
	var hero = get_row("heroes", hero_id)
	return {"heroId": hero_id, "specializationId": hero["specializationIds"][0],
		"commonSkillIds": hero["defaultCommonSkillIds"].duplicate(), "relicIds": ["I01", "I03"], "talentIds": ["T11", "T12"]}

func modifiers(loadout: Dictionary, upgrades: Array = []) -> Dictionary:
	var result = {}
	for group in [["relics", loadout.get("relicIds", [])], ["talents", loadout.get("talentIds", [])], ["run-upgrades", upgrades]]:
		for id in group[1]:
			for key in get_row(group[0], id).get("effects", {}).keys():
				var effect = get_row(group[0], id)["effects"][key]
				if effect is float or effect is int:
					result[key] = float(result.get(key, 0.0)) + float(effect)
				elif effect is Dictionary:
					var nested = result.get(key, {})
					for subkey in effect.keys():
						nested[subkey] = float(nested.get(subkey, 0.0)) + float(effect[subkey])
					result[key] = nested
	return result

func research(id: String) -> Dictionary:
	for row in RESEARCH:
		if row["id"] == id:
			return row
	return {}

func valid_loadout(loadout: Dictionary) -> bool:
	var hero = get_row("heroes", String(loadout.get("heroId", "")))
	if hero.is_empty() or not hero["specializationIds"].has(loadout.get("specializationId")):
		return false
	if loadout.get("commonSkillIds", []).size() != 2: return false
	for mapping in [["skills", "commonSkillIds", 2], ["relics", "relicIds", 2], ["talents", "talentIds", 6]]:
		var ids = loadout.get(mapping[1], [])
		if not ids is Array or ids.size() > int(mapping[2]):
			return false
		var seen = {}
		for id in ids:
			if get_row(mapping[0], id).is_empty() or seen.has(id):
				return false
			if mapping[0] == "skills" and get_row("skills", id).get("category") != "common":
				return false
			seen[id] = true
	return fit_talents(loadout.get("talentIds", [])).size() == loadout.get("talentIds", []).size()

func fit_talents(ids: Array, budget: int = 6) -> Array:
	var ordered = ids.duplicate()
	ordered.sort_custom(func(a,b): return int(get_row("talents",a).get("tier",1)) < int(get_row("talents",b).get("tier",1)))
	var points = {};var result = []
	for id in ordered:
		var row = get_row("talents",id)
		if row.is_empty() or result.size()>=budget: continue
		var branch = row["branch"]
		if int(points.get(branch,0)) < (int(row["tier"])-1)*2: continue
		points[branch] = int(points.get(branch,0)) + 1;result.append(id)
	return result
