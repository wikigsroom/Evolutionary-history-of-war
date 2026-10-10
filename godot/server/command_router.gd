extends RefCounted

const FIELDS = {
	"train": {"unitId": "units"}, "cancel": {"queueId": "integer"},
	"evolve": {"upgradeId": "run-upgrades"}, "research": {"researchId": "research"},
	"turret": {"turretId": "turrets", "slot": "slot"}, "sell": {"slot": "slot"},
	"unlockSlot": {}, "stance": {"stance": "stance"},
	"item": {"itemId": "item"}, "ageSpecial": {}, "cast": {"skillId": "skills"}
}

static func validate(model, action: Dictionary, side: int) -> String:
	var kind = action.get("type")
	if not kind is String or not FIELDS.has(kind): return "INVALID_ACTION"
	for key in action:
		if key != "type" and not FIELDS[kind].has(key) and key not in ["x", "targetId"]: return "INVALID_FIELD"
	for key in FIELDS[kind]:
		if not action.has(key): return "MISSING_FIELD"
		var value = action[key]
		var table = FIELDS[kind][key]
		if table in ["integer", "slot"]:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != int(value): return "INVALID_NUMBER"
			if int(value) < 0 or int(value) > (3 if table == "slot" else 100000000): return "INVALID_NUMBER"
		elif not value is String: return "INVALID_ID"
		elif table == "research":
			if model.db.research(value).is_empty(): return "INVALID_ID"
		elif table == "item":
			if not EpochData.ITEMS.has(value): return "INVALID_ID"
		elif table == "stance":
			if value not in ["retreat", "cover", "rush"]: return "INVALID_ID"
		elif model.db.get_row(table, value).is_empty(): return "INVALID_ID"
	if action.has("x"):
		var number = action["x"]
		if not (number is float or number is int) or not is_finite(float(number)) or float(number) < 80.0 or float(number) > 1520.0: return "INVALID_TARGET"
	if action.has("targetId"):
		var number = action["targetId"]
		if not (number is float or number is int) or not is_finite(float(number)) or float(number) != int(number) or int(number) < -1 or int(number) > 100000000: return "INVALID_TARGET"
	if kind == "evolve":
		var row = model.db.get_row("run-upgrades", action["upgradeId"])
		if row.get("eraId", "") != "A%d" % (model.db.era_index(model.sides[side]["eraId"]) + 2): return "INVALID_UPGRADE"
	return ""
