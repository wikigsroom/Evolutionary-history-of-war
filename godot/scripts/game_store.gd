class_name EpochStore
extends RefCounted

var db: EpochData
var profile = {}
var settings = {"volume": 0.65, "music_volume": 0.80, "sfx_volume": 0.85, "ui_volume": 0.75, "music": true, "sfx": true, "reduced_motion": false, "fullscreen": false}
var directory = "user://"
var last_rewards = []

func _init(content: EpochData, storage_directory: String = "user://") -> void:
	db = content
	directory = storage_directory
	DirAccess.make_dir_recursive_absolute(directory)
	profile = {"version": 2, "contentVersion":"0.7.0", "campaignFrontier":1,"loadout": db.default_loadout(), "cleared": [], "unlocked_heroes": ["H01", "H03"],
		"relics": ["I01", "I03"], "mastery": 2, "fragments": 0, "reward_ids": [], "last_reward_sequence": 0, "next_sequence": 1, "wins": 0, "losses": 0, "draws": 0,
		"chests": 0, "rare_pity": 0, "epic_pity": 0, "loot_rng": 182737, "proficiency": {"H01": 0,"H02": 0,"H03": 0,"H04": 0,"H05": 0,"H06": 0}}
	var loaded = _read("profile.json")
	if loaded is Dictionary and db.valid_loadout(loaded.get("loadout", {})):
		for key in profile.keys():
			if loaded.has(key):
				profile[key] = loaded[key]
		if not String(loaded.get("contentVersion","")).begins_with("0.7"):
			profile["cleared"]=[]
			for old_id in loaded.get("cleared",[]):
				var id=preload("res://scripts/epoch_snapshot_migration.gd").mission_id(String(old_id))
				if not profile["cleared"].has(id):profile["cleared"].append(id)
				profile["campaignFrontier"]=maxi(int(profile["campaignFrontier"]),mini(20,int(id.trim_prefix("M"))+1))
		profile["version"]=2;profile["contentVersion"]="0.7.0"
	profile["mastery"] = clampi(int(profile["mastery"]), 2, 6)
	profile["next_sequence"] = maxi(int(profile["next_sequence"]), int(profile["last_reward_sequence"]) + 1)
	var options = _read("settings.json")
	if options is Dictionary:
		for key in settings.keys():
			if options.has(key):
				settings[key] = options[key]
	for key in ["volume", "music_volume", "sfx_volume", "ui_volume"]:
		settings[key] = clampf(float(settings[key]), 0.0, 1.0)

func _read(name: String):
	for suffix in ["", ".bak"]:
		if not FileAccess.file_exists(directory + name + suffix): continue
		var file = FileAccess.open(directory + name + suffix, FileAccess.READ)
		if file == null or file.get_length() > 8000000: continue
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary: return parsed
	return null

func _write(name: String, data: Dictionary) -> bool:
	var path = directory + name
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "", true, true))
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

func save_profile() -> bool:
	return _write("profile.json", profile)

func save_settings() -> bool:
	return _write("settings.json", settings)

func next_match_config(mode: String = "standard", mission_id: String = "", difficulty: String = "D02") -> Dictionary:
	var sequence = int(profile["next_sequence"])
	profile["next_sequence"] = sequence + 1
	save_profile()
	return {"mode": mode, "missionId": mission_id, "difficultyId": difficulty, "loadout": profile["loadout"].duplicate(true),
		"enemyLoadout": db.default_loadout("H03"), "seed": int(Time.get_unix_time_from_system()) % 2147483647,
		"matchId": "%d-%d" % [int(Time.get_unix_time_from_system()), sequence], "rewardSequence": sequence, "heroEnabled": true}

func mission_unlocked(id: String) -> bool:
	var index = int(id.trim_prefix("M"))
	return index <= int(profile.get("campaignFrontier",1)) or profile["cleared"].has("M%02d" % (index - 1))

func record_result(config: Dictionary, winner: int, metrics: Dictionary = {}) -> bool:
	var sequence = int(config.get("rewardSequence", 0))
	var id = String(config.get("matchId", ""))
	if id.is_empty() or sequence <= int(profile["last_reward_sequence"]) or profile["reward_ids"].has(id):
		return false
	profile["last_reward_sequence"] = sequence
	profile["reward_ids"].append(id)
	last_rewards = []
	if profile["reward_ids"].size() > 200:
		profile["reward_ids"].pop_front()
	if winner == 0:
		profile["wins"] = int(profile["wins"]) + 1
		var mission_id = String(config.get("missionId", ""))
		if not mission_id.is_empty() and not profile["cleared"].has(mission_id):
			profile["cleared"].append(mission_id)
			var mission = db.get_row("missions", mission_id)
			for hero_id in mission.get("heroUnlockIds", []):
				if not profile["unlocked_heroes"].has(hero_id):
					profile["unlocked_heroes"].append(hero_id)
			var relic = mission.get("firstClearRelicId")
			if relic != null: _grant_relic(relic)
			profile["mastery"] = mini(6, int(profile["mastery"]) + int(mission.get("firstClearMasteryPoints", 0)))
			profile["fragments"] = int(profile["fragments"]) + int(db.loot["missionFirstClearFragments"].get(mission_id, 0))
		profile["fragments"] = int(profile["fragments"]) + 1
		if profile["cleared"].has("M01"):
			for i in range(2 if db.loot["chapterBossMissionIds"].has(String(config.get("missionId", ""))) else 1): _open_chest()
	elif winner == 1:
		profile["losses"] = int(profile["losses"]) + 1
	elif winner == 2:
		profile["draws"] = int(profile["draws"]) + 1
	var hero_id = String(config.get("loadout", {}).get("heroId", "H01"))
	if winner == 0 or (float(metrics.get("elapsed", 0)) >= 120.0 and int(metrics.get("kills", 0)) >= 3):
		profile["proficiency"][hero_id] = int(profile["proficiency"].get(hero_id, 0)) + (100 if winner == 0 else 50)
	save_profile()
	clear_match()
	return true

func _grant_relic(id: String) -> void:
	if profile["relics"].has(id):
		profile["fragments"] = int(profile["fragments"]) + 1
		last_rewards.append(db.get_row("relics", id)["name"] + " · 重复转为碎片")
	else:
		profile["relics"].append(id)
		last_rewards.append(db.get_row("relics", id)["name"])

func _loot_random(bound: int) -> int:
	var seed = int(profile["loot_rng"]) & 0xffffffff
	seed ^= (seed << 13) & 0xffffffff
	seed ^= seed >> 17
	seed ^= (seed << 5) & 0xffffffff
	profile["loot_rng"] = seed & 0xffffffff
	return int(profile["loot_rng"]) % maxi(1, bound)

func _open_chest() -> void:
	profile["chests"] = int(profile["chests"]) + 1
	profile["rare_pity"] = int(profile["rare_pity"]) + 1
	profile["epic_pity"] = int(profile["epic_pity"]) + 1
	var roll = _loot_random(100)
	var rarity = "common" if roll < 60 else ("rare" if roll < 90 else "epic")
	if int(profile["epic_pity"]) >= 20: rarity = "epic"
	elif int(profile["rare_pity"]) >= 5: rarity = "rare" if _loot_random(40) < 30 else "epic"
	var pool = db.rows["relics"].filter(func(r): return r["rarity"] == rarity)
	_grant_relic(pool[_loot_random(pool.size())]["id"])
	if rarity != "common": profile["rare_pity"] = 0
	if rarity == "epic": profile["epic_pity"] = 0

func save_match(snapshot: Dictionary) -> bool:
	return _write("match.json", snapshot)

func load_match() -> Dictionary:
	var data = _read("match.json")
	if data is Dictionary and int(data.get("version",0)) in [1,2] and data.get("winner", -1) == -1 and data.get("sides", []).size() == 2:
		return data
	return {}

func clear_match() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path = directory + "match.json" + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
