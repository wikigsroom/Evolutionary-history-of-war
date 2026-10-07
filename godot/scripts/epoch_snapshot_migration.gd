class_name EpochSnapshotMigration
extends RefCounted

const ERA_MAP = {"A1":"A1","A2":"A2","A3":"A4","A4":"A6","A5":"A10"}
const OLD_POWER = {"A1":1.0,"A2":1.6,"A3":2.55,"A4":4.05,"A5":6.4}

static func mission_id(old_id: String) -> String:
	if not old_id.begins_with("M"): return old_id
	var index=int(old_id.trim_prefix("M"))
	if index<1 or index>15:return old_id
	var old_era="A"+str((index-1)/3+1)
	var era=int(String(ERA_MAP[old_era]).trim_prefix("A"))
	return "M%02d"%((era-1)*2+(2 if index%3==0 else 1))

static func content_id(value: String) -> String:
	for prefix in ["TR","U","R"]:
		if not value.begins_with(prefix):continue
		var tail=value.substr(prefix.length())
		if tail.length()!=2 or not tail.is_valid_int():return value
		var old_era="A"+tail.left(1)
		return prefix+String(ERA_MAP[old_era]).trim_prefix("A")+tail.right(1) if ERA_MAP.has(old_era) else value
	return value

static func translate(value,db: EpochData):
	if value is Array:
		for i in range(value.size()):value[i]=translate(value[i],db)
	elif value is Dictionary:
		var previous=String(value.get("eraId",""))
		for key in value.keys():
			if key in ["eraId","startingEraId","maximumEraId","max_era"]:
				value[key]=ERA_MAP.get(value[key],value[key])
			elif key=="missionId":value[key]=mission_id(String(value[key]))
			else:value[key]=translate(value[key],db)
		var source=value.get("source",{})
		if source is Dictionary and source.has("migrationPowerFactor"):
			for key in ["damage","raw"]:
				if value.has(key) and (value[key] is float or value[key] is int):value[key]=float(value[key])*float(source["migrationPowerFactor"])
		if OLD_POWER.has(previous) and value.has("kind"):
			value["migrationPowerFactor"]=db.attack_multiplier(value["eraId"])/float(OLD_POWER[previous])
	elif value is String:return content_id(value)
	return value

static func migrate(data: Dictionary,db: EpochData) -> Dictionary:
	var result=translate(data.duplicate(true),db)
	result["version"]=2;result["contentVersion"]="0.7.0";result["migratedFrom"]="0.6.2"
	return result

static func refresh_legacy(model) -> void:
	for entity in model.entities:
		var old_max=float(entity["maxHp"])
		var ratio=float(entity["hp"])/old_max
		if entity["kind"]=="base":
			var max_hp=float(model.db.era(entity["eraId"])["baseHp"])*(1.0+float(model.modifiers(int(entity["side"])).get("baseHpBonus",0.0)))
			entity["maxHp"]=floorf(max_hp);entity["hp"]=floorf(float(entity["maxHp"])*ratio)
		elif entity["kind"] in ["unit","hero"]:
			var row=model.db.actor_content(entity["contentId"],entity["eraId"],entity["kind"])
			for pair in [["role","role"],["heavy","heavy"],["special","special"],["energyResistance","energyResistance"]]:
				if row.has(pair[1]):entity[pair[0]]=row[pair[1]].duplicate(true) if row[pair[1]] is Dictionary else row[pair[1]]
			model.refresh(entity)
		else:
			var scale=float(entity.get("migrationPowerFactor",1.0))
			entity["maxHp"]=old_max*scale;entity["hp"]=float(entity["maxHp"])*ratio;entity["attack"]=float(entity["attack"])*scale
			entity["visualId"]="SUM-"+entity["eraId"]
		var shield_scale=float(entity["maxHp"])/old_max
		var shield_total=0.0
		for batch in entity["shields"]:batch["hp"]=float(batch["hp"])*shield_scale;shield_total+=float(batch["hp"])
		var shield_cap=float(entity["maxHp"])*float(model.db.rules["support"]["totalShieldCapRatio"])
		if shield_total>shield_cap:
			for batch in entity["shields"]:batch["hp"]=float(batch["hp"])*shield_cap/shield_total
		entity.erase("migrationPowerFactor")
	model.modifier_cache=[{},{}]
