class_name BattleAudio
extends Node

const VOICES = 18
const MAX_FRAME_CUES = 8
const ERA_MUSIC = ["age1","age2","age2","age3","age4","age4","age4","age4","age5","age5"]
const SKILL_CAST_CUES = {
	"S01":"support_pulse","S02":"item_drum","S03":"arrow_fire","S04":"musket_fire",
	"S05":"skill_cast","S06":"support_pulse","S07":"arc_fire","S08":"stone_throw",
	"S09":"spear_swing","S10":"skill_ready","S11":"item_smoke","S12":"rush_flag",
	"HS01":"rush_flag","HS02":"arrow_fire","HS03":"support_pulse","HS04":"build",
	"HS05":"skill_cast","HS06":"item_supply"
}
var settings: Dictionary = {}
var catalog: Dictionary = {}
var streams: Dictionary = {}
var music_players: Array = []
var channels: Array = []
var current_music = ""
var music_gains: Array = [0.0, 0.0]
var active_music = 0
var fade_from = 1
var fade_time = 1.0
var fade_length = 0.85
var fade_start_gain = 0.0
var duck_time = 0.0
var duck_gain = 1.0
var battle_paused = false
var suspended = false
var listener_left = 0.0
var listener_width = 1280.0
var pending: Dictionary = {}
var last: Dictionary = {}
var variant_counters: Dictionary = {}
var bus_names: Dictionary = {}
var owned_buses: Array = []
var danger_clock = 0.0
var ready_skills: Dictionary = {}
var played: Array = []
var stats: Dictionary = {"started":0, "merged":0, "culled":0, "preempted":0, "missing":0}

func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/catalog.json"))
	if parsed is Dictionary: catalog = parsed
	else: push_error("Audio catalog missing"); return
	var prefix = "Epoch%d" % get_instance_id()
	bus_names["Mix"] = prefix + "Mix"; _make_bus(bus_names["Mix"],"Master")
	for role in ["Music", "Battle", "UI"]:
		bus_names[role] = prefix + role; _make_bus(bus_names[role], bus_names["Mix"])
	var master = AudioServer.get_bus_index(bus_names["Mix"])
	var has_limiter = false
	for i in range(AudioServer.get_bus_effect_count(master)):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter: has_limiter = true
	if not has_limiter:
		var limiter = AudioEffectHardLimiter.new(); limiter.ceiling_db = -1.0; limiter.release = 0.08
		AudioServer.add_bus_effect(master, limiter)
	for i in range(2):
		var player = AudioStreamPlayer.new(); player.bus = bus_names["Music"]; add_child(player); music_players.append(player)
	for i in range(VOICES):
		var role = "UI" if i >= 15 else "Battle"
		var bus = prefix + "Voice%d" % i; _make_bus(bus, bus_names[role])
		var panner = AudioEffectPanner.new(); AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), panner)
		var player = AudioStreamPlayer.new(); player.bus = bus; add_child(player)
		channels.append({"player":player,"panner":panner,"cue":"","priority":0,"started":0})
	for cue in catalog.get("cues", {}).values():
		for path in cue["variants"]: _stream(path)
	apply_settings()

func _make_bus(bus: String, parent: String) -> void:
	AudioServer.add_bus(); var index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus); AudioServer.set_bus_send(index, parent); owned_buses.append(bus)

func _exit_tree() -> void:
	for player in music_players: player.stop(); player.stream = null
	for channel in channels: channel["player"].stop(); channel["player"].stream = null
	streams.clear()
	for i in range(owned_buses.size()-1,-1,-1):
		var bus: String = owned_buses[i]
		var index = AudioServer.get_bus_index(bus)
		if index >= 0: AudioServer.remove_bus(index)

func _stream(path: String) -> AudioStream:
	if not streams.has(path):
		streams[path] = load(path) if ResourceLoader.exists(path) else null
		if streams[path] == null: stats["missing"] += 1; push_error("Missing sound: " + path)
	return streams[path]

func _bus_level(role: String, gain: float, enabled: bool = true) -> void:
	var index = AudioServer.get_bus_index(bus_names[role])
	AudioServer.set_bus_mute(index, not enabled or gain <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.00001, gain)))

func apply_settings() -> void:
	if music_players.is_empty(): return
	var gain = clampf(float(settings.get("volume", 0.65)), 0.0, 1.0)
	_bus_level("Mix",gain)
	_bus_level("Music", clampf(float(settings.get("music_volume", 0.80)),0,1), bool(settings.get("music",true)))
	_bus_level("Battle", clampf(float(settings.get("sfx_volume", 0.85)),0,1), bool(settings.get("sfx",true)))
	_bus_level("UI", clampf(float(settings.get("ui_volume", 0.75)),0,1), bool(settings.get("sfx",true)))
	for player in music_players: player.stream_paused = suspended or not settings.get("music",true)
	if not settings.get("sfx", true) or gain == 0:
		pending.clear()
		for channel in channels: channel["player"].stop()

func _process(delta: float) -> void:
	if suspended or music_players.is_empty(): return
	if fade_time < fade_length:
		fade_time = minf(fade_length, fade_time + delta)
		var t = fade_time / fade_length
		music_gains[active_music] = sin(t * PI * 0.5)
		music_gains[fade_from] = fade_start_gain * cos(t * PI * 0.5)
		if t >= 1.0: music_players[fade_from].stop(); music_gains[fade_from] = 0.0
	duck_time = maxf(0.0, duck_time - delta)
	var looped = bool(catalog.get("music",{}).get(current_music,{}).get("loop",true))
	var desired = 0.58 if duck_time > 0 else (0.48 if battle_paused and looped else 1.0)
	duck_gain = lerpf(duck_gain, desired, 1.0-exp(-delta*(18 if desired < duck_gain else 4)))
	for i in range(2): music_players[i].volume_db = linear_to_db(maxf(0.00001, float(music_gains[i])*duck_gain))

func play_music(track: String) -> void:
	if current_music == track or not catalog.get("music",{}).has(track): return
	var meta: Dictionary = catalog["music"][track]
	var source = _stream(meta["path"])
	if source == null: return
	# Duplicate before setting loop, so a cached imported resource stays immutable.
	var stream: AudioStreamOggVorbis = source.duplicate(); stream.loop = bool(meta["loop"])
	active_music = 1 if float(music_gains[1]) > float(music_gains[0]) else 0
	fade_from = active_music; active_music = 1-active_music
	music_players[active_music].stop(); music_players[active_music].stream = stream
	music_gains[active_music] = 0.0; music_players[active_music].volume_db = -100.0
	fade_start_gain = float(music_gains[fade_from]); fade_time = 0.0
	fade_length = 0.18 if not meta["loop"] else 0.85
	current_music = track; music_players[active_music].play()
	music_players[active_music].stream_paused = suspended or not settings.get("music",true)

func play_era_music(era_number: int) -> void:
	play_music(ERA_MUSIC[clampi(era_number-1,0,ERA_MUSIC.size()-1)])

func begin_battle() -> void:
	last.clear(); pending.clear(); ready_skills.clear(); danger_clock = 0.0; battle_paused = false
	for i in range(mini(15,channels.size())): channels[i]["player"].stop()

func set_listener(left: float, width: float) -> void:
	listener_left = left; listener_width = maxf(1.0,width)

func set_battle_paused(value: bool) -> void:
	if battle_paused == value: return
	battle_paused = value
	if value:
		pending.clear()
		for i in range(15): channels[i]["player"].stop()

func set_suspended(value: bool) -> void:
	suspended = value
	if value:
		pending.clear()
		for channel in channels: channel["player"].stop()
	apply_settings()

func sfx(cue: String, intensity: float = 1.0) -> void:
	_emit(cue, intensity, NAN, 1.0)

func queue_sfx(cue: String, intensity: float, x: float, pitch: float = 1.0) -> void:
	if not catalog.get("cues",{}).has(cue): stats["missing"] += 1; return
	if pending.has(cue):
		stats["merged"] += 1; pending[cue]["count"] += 1
		pending[cue]["intensity"] = maxf(float(pending[cue]["intensity"]), intensity)
		if not is_nan(x) and absf(x-listener_left-listener_width/2) < absf(float(pending[cue]["x"])-listener_left-listener_width/2): pending[cue]["x"] = x
	else:
		pending[cue] = {"cue":cue,"intensity":intensity,"x":x,"pitch":pitch,"count":1}
		if pending.size() == 1: call_deferred("_flush")

func _flush() -> void:
	var batch = pending.values(); pending.clear()
	batch.sort_custom(func(a,b):return int(catalog["cues"][a["cue"]]["priority"]) > int(catalog["cues"][b["cue"]]["priority"]))
	for i in range(batch.size()):
		if i >= MAX_FRAME_CUES: stats["culled"] += 1; continue
		var row: Dictionary = batch[i]
		_emit(row["cue"], float(row["intensity"])*minf(1.15,1.0+log(float(row["count"]))*0.04), float(row["x"]), float(row["pitch"]))

func _emit(cue: String, intensity: float, world_x: float, pitch: float) -> void:
	if suspended or not settings.get("sfx",true) or float(settings.get("volume",0.65)) <= 0: return
	if not catalog.get("cues",{}).has(cue): stats["missing"] += 1; return
	var meta: Dictionary = catalog["cues"][cue]; var ui = meta["bus"] == "UI"
	if (not ui and battle_paused) or float(settings.get("ui_volume" if ui else "sfx_volume",1)) <= 0: return
	var now = Time.get_ticks_msec()
	if now - int(last.get(cue,-100000)) < int(meta["cooldown_ms"]): return
	var pan = 0.0; var attenuation = 1.0
	if not ui and not is_nan(world_x):
		var position = (world_x-listener_left)/listener_width
		pan = clampf((position-.5)*.7,-.45,.45)
		attenuation = 1.0/(1.0+maxf(0.0,absf(position-.5)-.5)*2.5)
		if attenuation < 0.22 and int(meta["priority"]) < 80: stats["culled"] += 1; return
	var candidates: Array = range(15,18) if ui else (range(15) if int(meta["priority"])>=85 else range(4,15))
	var selected = -1; var active_same: Array = []
	for i in candidates:
		var channel: Dictionary = channels[i]
		if channel["player"].playing and channel["cue"] == cue: active_same.append(i)
		if not channel["player"].playing and selected < 0: selected = i
	var cap = 2 if int(meta["priority"]) >= 70 else 4
	if active_same.size() >= cap:
		selected = int(active_same[0])
		for i in active_same:
			if int(channels[i]["started"]) < int(channels[selected]["started"]): selected = i
	if selected < 0:
		for i in candidates:
			if int(channels[i]["priority"]) > int(meta["priority"]): continue
			if selected < 0 or int(channels[i]["priority"]) < int(channels[selected]["priority"]) or (int(channels[i]["priority"]) == int(channels[selected]["priority"]) and int(channels[i]["started"]) < int(channels[selected]["started"])): selected = i
	if selected < 0: stats["culled"] += 1; return
	var voice: Dictionary = channels[selected]
	if voice["player"].playing: voice["player"].stop(); stats["preempted"] += 1
	var count = int(variant_counters.get(cue,0)); variant_counters[cue] = count+1
	var variants: Array = meta["variants"]; var path: String = variants[count % variants.size()]
	voice["player"].stream = _stream(path)
	if voice["player"].stream == null: return
	var gain = float(meta["gain"])*clampf(intensity,0.05,1.25)*attenuation
	voice["player"].volume_db = linear_to_db(maxf(.00001,gain))
	voice["player"].pitch_scale = clampf(pitch * [1.0, .982, 1.018][count%3], .85, 1.15)
	voice["panner"].pan = pan; voice["cue"] = cue; voice["priority"] = meta["priority"]; voice["started"] = now
	voice["player"].play(); last[cue] = now; stats["started"] += 1
	if int(meta["priority"]) >= 85 and not ui: duck_time = maxf(duck_time,.65)
	played.append({"cue":cue,"path":path,"pan":pan,"gain":gain,"pitch":voice["player"].pitch_scale,"voice":selected})
	if played.size() > 256: played.pop_front()

func handle_event(event: Dictionary, model) -> void:
	var data: Dictionary = event["data"]; var side = int(event["side"]); var x = float(event["x"])
	var target: Dictionary = model.entity_by_id(int(data.get("targetId",-1)))
	var weapon = String(data.get("weaponId","W02"))
	match event["type"]:
		"release": queue_sfx({"W01":"stone_throw","W02":"sword_swing","W03":"arrow_fire","W04":"musket_fire","W05":"cannon_fire","W06":"spear_swing","W07":"arc_fire","W08":"support_pulse"}.get(weapon,"sword_swing"),.85,x)
		"hit":
			if int(data.get("absorbed",0))>0: queue_sfx("shield_hit",.85,x)
			if int(data.get("amount",0)) <= 0: return
			var material = "flesh"
			if not target.is_empty():
				if target["kind"] == "base": material = "stone" if model.db.era_index(target["eraId"]) < 3 else "metal"
				else: material = String(model.db.profile(target.get("visualId",target["contentId"]))["material"])
			var cue = material + "_hit" if material in ["stone","wood","metal"] else "flesh_hit"
			if data.get("damageType") == "energy": cue = "energy_hit"
			elif (weapon == "W05" or data.get("damageType") == "blast") and String(data.get("skillId","")).is_empty(): cue = "cannon_hit"
			elif weapon == "W03" and material == "flesh": cue = "arrow_hit"
			queue_sfx(cue,1.05 if data.get("heavy",false) else .9,x)
			if String(data.get("skillId","")) == "HS01": queue_sfx("cannon_hit",.85,x)
		"shieldBreak": queue_sfx("shield_break",1,x)
		"shield": queue_sfx("support_pulse",.42,x)
		"spawn": queue_sfx("hero_respawn" if data.get("kind",target.get("kind","")) == "hero" else "unit_spawn",.8,x)
		"death": queue_sfx("base_destroyed" if data.get("kind") == "base" else ("hero_death" if data.get("kind") == "hero" else "unit_death"),.95,x)
		"heal": queue_sfx("heal",.55,x)
		"reward":
			if side == 0: queue_sfx("loot_collect",.55,NAN,1.0+minf(.08,float(data.get("amount",0))*.0003))
		"queue":
			if side == 0: queue_sfx("queue_add",.85,NAN)
		"research":
			if side == 0: queue_sfx("research_complete",.8,NAN)
		"build": queue_sfx("build",.85,x)
		"skill":
			var source=model.entity_by_id(int(data.get("sourceId",-1)))
			var skill_id=String(data.get("skillId",""))
			var cue=String(SKILL_CAST_CUES.get(skill_id,"skill_cast"))
			if skill_id=="HS02": cue={"W01":"stone_throw","W03":"arrow_fire","W04":"musket_fire","W07":"arc_fire"}.get(source.get("weaponId"),cue)
			queue_sfx(cue,.85,float(source.get("x",x)))
		"warning":
			if side == 1: queue_sfx("danger_warning",.85,x)
		"skillImpact":
			if data.get("fieldTick",false): return
			var skill = String(data.get("skillId",""))
			if skill=="HS02": queue_sfx("arrow_rain" if data.get("weaponId")=="W03" else "musket_fire" if data.get("weaponId")=="W04" else "arc_fire" if data.get("weaponId")=="W07" else "stone_hit",.9,x)
			elif skill=="S03": queue_sfx("arrow_rain",.9,x)
			elif skill in ["S05","S08","HS01"]: queue_sfx("meteor_impact",1,x)
			elif skill == "S06": queue_sfx("support_pulse",.9,x)
			elif skill == "S07": queue_sfx("arc_fire",.95,x)
			elif skill == "HS05": queue_sfx("skill_cast",.9,x)
		"ageLaunch":
			var era = model.db.era_index(data["eraId"])+1
			queue_sfx("arrow_fire" if era in [2,3,4] else "cannon_fire" if era in [5,6] else "airstrike" if era in [7,8] else "arc_fire" if era>=9 else "stone_throw",.85,x)
		"ageImpact": queue_sfx(String(model.db.age_special(data["eraId"])["sfx"]),1,x)
		"eventWarning": queue_sfx("danger_warning",.75,x)
		"eventImpact": queue_sfx("meteor_impact" if data["eventKind"] in ["meteor","dinosaur","rockfall"] else "airstrike" if data["eventKind"]=="plane" else "energy_hit",.78,x)
		"item": queue_sfx({"war-drum":"item_drum","smoke-bomb":"item_smoke","chrono-crate":"item_supply"}.get(data["itemId"],"skill_cast"),.95,x)
		"evolve":
			queue_sfx("evolve",1,x)
			if side == 0: play_era_music(model.ally_era)

func update_battle(model, delta: float) -> void:
	set_battle_paused(model.paused)
	if model.paused or model.winner >= 0: return
	danger_clock = maxf(0.0,danger_clock-delta)
	var base: Dictionary = model.base(0)
	var health = float(base["hp"])/maxf(1.0,float(base["maxHp"]))
	if health <= .28 and danger_clock <= 0:
		queue_sfx("base_danger",.75+(.28-health),NAN,.94+(.28-health)*.3); danger_clock=6.2
	for key in model.sides[0]["cooldowns"]:
		var until = int(model.sides[0]["cooldowns"][key])
		if until > model.tick: ready_skills[key] = until
		elif ready_skills.has(key): ready_skills.erase(key); queue_sfx("skill_ready",.7,NAN)
