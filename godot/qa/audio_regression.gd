extends SceneTree

var app
var audio: BattleAudio
var capture: AudioEffectCapture
var recorded = PackedByteArray()
var checks = 0
var failures: Array = []
var directory = ""
var capture_slices: Array = []

func _initialize() -> void:
	directory=OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	if directory.is_empty():directory=ProjectSettings.globalize_path("res://../output/qa/godot-audio/native")
	DirAccess.make_dir_recursive_absolute(directory);call_deferred("run")

func check(value: bool, label: String) -> void:
	checks+=1
	if not value:failures.append(label);push_error(label)

func collect() -> void:
	if capture==null:return
	var frames=capture.get_frames_available()
	if frames>0:recorded.append_array(capture.get_buffer(frames).to_byte_array())

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout;collect()

func signal_after(start: int) -> Dictionary:
	var bytes=recorded.slice(start);var samples=bytes.to_float32_array()
	var peak=0.0;var left=0.0;var right=0.0
	for i in range(samples.size()):
		peak=maxf(peak,absf(samples[i]))
		if i%2==0:left+=samples[i]*samples[i]
		else:right+=samples[i]*samples[i]
	return {"peak":peak,"left_energy":left,"right_energy":right,"samples":samples.size()}

func cue_seen(cue: String, start: int) -> bool:
	for i in range(start,audio.played.size()):
		if audio.played[i]["cue"]==cue:return true
	return false

func find_slider(node: Node, name_: String):
	if node is HSlider and node.name==name_:return node
	for child in node.get_children():
		var found=find_slider(child,name_)
		if found!=null:return found
	return null

func hit(source: Dictionary, target: Dictionary, kind: String, extra: Dictionary) -> Array:
	var start=audio.played.size();audio.last.clear()
	app.model.combat.hit(source,target,10,kind,extra);app.model.combat.apply_hits();await wait_seconds(.13)
	var cues: Array=[]
	for i in range(start,audio.played.size()):cues.append(audio.played[i]["cue"])
	return cues

func run() -> void:
	root.size=Vector2i(1280,720)
	app=preload("res://scenes/Main.tscn").instantiate();root.add_child(app)
	app.store=EpochStore.new(app.model.db,"user://qa-audio-%d/"%Time.get_ticks_usec());audio=app.audio;audio.settings=app.store.settings;audio.apply_settings()
	capture=AudioEffectCapture.new();capture.buffer_length=1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"),capture)
	process_frame.connect(collect)
	await wait_seconds(1)
	check(recorded.size()>10000,"实际音频驱动产生可捕获的 PCM")
	check(audio.stats["missing"]==0,"音效缓存全部加载")
	for meta in audio.catalog["cues"].values():
		for path in meta["variants"]:
			var stream: AudioStreamWAV=audio.streams[path]
			check(stream!=null and stream.get_length()>.03,"声音样本可播放："+path.get_file())
	for track in ["menu","age1","age2","age3","age4","age5"]:
		audio.play_music(track);await wait_seconds(.95)
		var player: AudioStreamPlayer=audio.music_players[audio.active_music]
		check(player.playing and player.stream.loop,"配乐正在循环："+track)
		player.seek(player.stream.get_length()-.15);await wait_seconds(.35)
		check(player.playing and player.get_playback_position()<1.1,"原生循环跨过结尾："+track)
		check(audio.music_players.filter(func(p):return p.playing).size()==1,"淡出完成仅保留一首："+track)
	for age in range(1,11):
		audio.play_era_music(age);await wait_seconds(.95)
		check(audio.current_music==BattleAudio.ERA_MUSIC[age-1],"十时代配乐路由：A"+str(age))
		check(audio.music_players[audio.active_music].playing,"十时代配乐实际播放：A"+str(age))
	# Rapid screen/era changes must finish on the newest track without orphaned music.
	for track in ["age1","age4","menu","age2"]:audio.play_music(track);await wait_seconds(.07)
	await wait_seconds(.95)
	check(audio.current_music=="age2" and audio.music_players.filter(func(p):return p.playing).size()==1,"快速切换收敛到最后一首")
	for track in ["victory","defeat","draw"]:
		audio.play_music(track);await wait_seconds(1.55)
		check(not audio.music_players[audio.active_music].playing,"结算短曲只播一次："+track)
		audio.apply_settings();await wait_seconds(.1)
		check(not audio.music_players[audio.active_music].playing,"修改音量不会重播结算："+track)
	app.show_battle({"aiEnabled":false,"seed":28287,"startingEraId":"A1"})
	app.model.set_process(false);app.model.set_physics_process(false);app.current_view.set_process(false);await wait_seconds(.3)
	var model=app.model;audio.set_listener(300,1000)
	var source: Dictionary=model.spawn(0,"U11","A1","unit",680)
	var flesh: Dictionary=model.spawn(1,"U11","A1","unit",790)
	var metal: Dictionary=model.spawn(1,"U71","A7","unit",1000)
	var wood: Dictionary=model.spawn(1,"U25","A2","unit",1100)
	await wait_seconds(.3)
	check((await hit(source,flesh,"physical",{"weaponId":"W02"})).has("flesh_hit"),"肉体命中使用钝击而非石块")
	check((await hit(source,metal,"physical",{"weaponId":"W02"})).has("metal_hit"),"金属装甲独立反馈")
	check((await hit(source,wood,"physical",{"weaponId":"W02"})).has("wood_hit"),"木盾独立反馈")
	check((await hit(source,flesh,"physical",{"weaponId":"W03"})).has("arrow_hit"),"箭矢命中独立反馈")
	check((await hit(source,metal,"energy",{"weaponId":"W07"})).has("energy_hit"),"能量命中独立反馈")
	check((await hit(source,model.base(1),"physical",{"weaponId":"W02","canDamageBase":true})).has("stone_hit"),"早期基地石质命中")
	model.abilities.add_shield(flesh,.30,4);await wait_seconds(.2)
	var absorbed: Array=await hit(source,flesh,"physical",{"weaponId":"W02"})
	check(absorbed.has("shield_hit") and not absorbed.has("flesh_hit"),"完全吸收不会产生肉体命中声音")
	check((await hit(source,metal,"blast",{"weaponId":"W02"})).has("cannon_hit"),"反击爆炸按伤害类别表现重量")
	check((await hit(model.hero(0),metal,"physical",{"weaponId":"W02","skillId":"HS01"})).has("cannon_hit"),"贯阵冲锋命中有重击层")
	# Trigger all skills through the real ability system, not hand-authored cast events.
	for skill in model.db.rows["skills"]:
		var hero_id="H"+String(skill["id"]).trim_prefix("HS") if skill["category"]=="signature" else "H01"
		var loadout: Dictionary=model.db.default_loadout(hero_id)
		if skill["category"]=="common":loadout["commonSkillIds"]=[skill["id"],"S02" if skill["id"]=="S01" else "S01"]
		var fixture=GameModel.new();fixture.reset_battle({"aiEnabled":false,"startingEraId":"A5","loadout":loadout})
		var hero: Dictionary=fixture.hero(0);hero["x"]=400.0;hero["previousX"]=400.0
		var opponent: Dictionary=fixture.spawn(1,"U51","A5","unit",520.0)
		fixture.sides[0]["command"]=110.0;fixture.consume_events();audio.last.clear()
		var start_cast=audio.played.size()
		var result: Dictionary=fixture.abilities.cast(0,skill["id"],480.0,int(opponent["id"]))
		check(result["ok"],"真实技能施放成功："+skill["id"])
		for event in fixture.consume_events():audio.handle_event(event,fixture)
		await wait_seconds(.10)
		check(audio.played.size()>start_cast,"每项技能施放都有声音："+skill["id"])
		fixture.free()
	var prior=audio.played.size();audio.last.clear()
	model.emit_event("skillImpact",750,0,{"skillId":"S06","radius":100,"fieldTick":false});await wait_seconds(.12)
	check(cue_seen("support_pulse",prior) and not cue_seen("orbital_impact",prior),"共振网命中使用共振脉冲")
	prior=audio.played.size();audio.last.clear();model.emit_event("skillImpact",750,0,{"skillId":"S07","radius":100,"fieldTick":false});await wait_seconds(.12)
	check(cue_seen("arc_fire",prior) and not cue_seen("orbital_impact",prior),"脉冲链命中使用电弧")
	prior=audio.played.size();audio.last.clear();model.emit_event("skillImpact",750,0,{"skillId":"HS05","radius":100,"fieldTick":false});await wait_seconds(.12)
	check(cue_seen("skill_cast",prior) and not cue_seen("orbital_impact",prior),"裂隙场展开使用能量场")
	for weapon in ["W01","W02","W03","W04","W05","W06","W07","W08"]:
		var expected={"W01":"stone_throw","W02":"sword_swing","W03":"arrow_fire","W04":"musket_fire","W05":"cannon_fire","W06":"spear_swing","W07":"arc_fire","W08":"support_pulse"}[weapon]
		var start=audio.played.size();audio.last.clear()
		model.emit_event("release",680,0,{"weaponId":weapon,"sourceId":source["id"],"targetId":metal["id"],"muzzleY":50,"toX":1000})
		await wait_seconds(.12);check(cue_seen(expected,start),"所有八种攻击模组有声音："+weapon)
	var music_before=audio.current_music
	model.sides[1]["eraId"]="A2";model.emit_event("evolve",model.BASE_POSITIONS[1],1,{"eraId":"A2","name":"军阵"})
	await wait_seconds(.13);check(audio.current_music==music_before,"敌方进化不切换我方时代配乐")
	model.sides[0]["eraId"]="A3";model.emit_event("evolve",model.BASE_POSITIONS[0],0,{"eraId":"A3","name":"王国"})
	await wait_seconds(.13);check(audio.current_music=="age2","我方古典时代进化更新配乐家族")
	await wait_seconds(.85)
	var start=audio.played.size();model.emit_event("queue",1500,1,{"unitId":"U11"});await wait_seconds(.13)
	check(audio.played.size()==start,"敌人招募不触发玩家界面提示")
	for item in ["war-drum","smoke-bomb","chrono-crate"]:
		start=audio.played.size();audio.last.clear();model.emit_event("item",750,0,{"itemId":item,"radius":100,"targets":[]});await wait_seconds(.13)
		check(cue_seen({"war-drum":"item_drum","smoke-bomb":"item_smoke","chrono-crate":"item_supply"}[item],start),"道具声音可区分："+item)
	# Capture actual stereo energy with other sources silent, including zero-volume behavior.
	audio.settings["music"]=false;audio.apply_settings();audio.begin_battle();await wait_seconds(1.0)
	app.current_view.world.camera_x=300;app.current_view.world.tracking="free";await wait_seconds(.1)
	var edges: Array=[audio.listener_left,audio.listener_left+audio.listener_width]
	for position in edges:
		start=recorded.size();audio.last.clear();audio.queue_sfx("flesh_hit",1,position);await wait_seconds(.6)
		var measured=signal_after(start);capture_slices.append({"test":"pan","x":position,"signal":measured,"voice":audio.played[-1],"listener":[audio.listener_left,audio.listener_width]})
		check(measured["left_energy"]>measured["right_energy"]*1.5 if position==edges[0] else measured["right_energy"]>measured["left_energy"]*1.5,"左右战场在实际混音中定位")
	audio.settings["volume"]=0;audio.apply_settings();await wait_seconds(.3);start=recorded.size()
	audio.sfx("cannon_fire");await wait_seconds(.4)
	var silence=signal_after(start);capture_slices.append({"test":"master_zero","signal":silence});check(silence["peak"]<.000001,"总音量 0 产生真实静音")
	audio.settings["volume"]=1;audio.settings["sfx_volume"]=0;audio.apply_settings();start=audio.played.size();audio.sfx("metal_hit")
	check(audio.played.size()==start,"战斗音量 0 拒绝战斗声音")
	audio.sfx("ui_confirm");check(audio.played.size()==start+1,"战斗静音后界面提示仍可用")
	audio.settings["sfx_volume"]=1;audio.settings["ui_volume"]=0;audio.apply_settings();start=audio.played.size();audio.sfx("ui_error")
	check(audio.played.size()==start,"界面音量 0 单独静音")
	audio.settings["ui_volume"]=1;audio.apply_settings();await wait_seconds(.6)
	# Ordinary attacks fill their pool; evolution and UI feedback retain reserved voices.
	audio.last.clear()
	for cue in ["cannon_hit","cannon_fire","musket_fire","shield_hit","metal_hit","wood_hit","flesh_hit","stone_hit","arrow_rain","arc_fire","energy_hit"]:audio.sfx(cue,1.15)
	start=audio.played.size();audio.sfx("evolve");audio.sfx("ui_error")
	check(cue_seen("evolve",start) and cue_seen("ui_error",start),"满载攻击中进化与界面仍能播放")
	await wait_seconds(.15);check(audio.duck_gain<.85,"关键演出自动降低配乐")
	start=int(audio.stats["started"]);audio.last.clear()
	for i in range(50):audio.queue_sfx("flesh_hit",.9,800+i)
	await wait_seconds(.15);check(int(audio.stats["started"])-start==1,"同帧 50 次同类命中合并一次")
	await wait_seconds(1.2)
	audio.last.clear();var variants: Array=[]
	for i in range(4):
		audio.sfx("metal_hit");variants.append(audio.played[-1]["path"]);await wait_seconds(.1)
	check(variants[0]!=variants[1] and variants[1]!=variants[2] and variants[0]==variants[3],"连续攻击轮换变体")
	audio.set_battle_paused(true);start=audio.played.size();audio.sfx("cannon_fire")
	check(audio.played.size()==start,"暂停清理并拒绝战斗尾音")
	audio.last.clear();audio.sfx("ui_confirm");check(audio.played.size()==start+1,"暂停界面仍有操作反馈")
	audio.set_battle_paused(false);audio.set_suspended(true);start=audio.played.size();audio.sfx("ui_error")
	check(audio.played.size()==start,"应用后台不播放声音")
	audio.set_suspended(false);audio.settings["music"]=true;audio.apply_settings();audio.play_music("age2");await wait_seconds(.95)
	check(audio.music_players[audio.active_music].playing and not audio.music_players[audio.active_music].stream_paused,"回到前台恢复配乐")
	model.base(0)["hp"]=float(model.base(0)["maxHp"])*.20;start=audio.played.size();audio.last.clear();audio.danger_clock=0;audio.update_battle(model,.016);await wait_seconds(.12)
	check(cue_seen("base_danger",start),"基地低生命主动预警")
	start=audio.played.size();audio.update_battle(model,.1);await wait_seconds(.12);check(audio.played.size()==start,"基地预警不会每帧重复")
	model.sides[0]["cooldowns"]["S05"]=model.tick+2;audio.update_battle(model,.016);model.tick+=3;start=audio.played.size();audio.update_battle(model,.016);await wait_seconds(.15)
	check(cue_seen("skill_ready",start),"技能冷却完成发出提示")
	app.show_menu("settings");await wait_seconds(.3)
	for key in ["volume","music_volume","sfx_volume","ui_volume"]:
		var slider=find_slider(app.current_view,"Audio_"+key);check(slider!=null,"设置提供独立音量："+key)
		if slider!=null:
			check(Rect2(Vector2.ZERO,root.size).encloses(slider.get_global_rect()),"音量控件处于画面内："+key)
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/audio-settings.png")
	check(audio.stats["missing"]==0,"战斗声音没有缺失引用")
	check(capture.get_discarded_frames()==0,"捕获没有缓冲丢帧")
	collect();var pcm=FileAccess.open(directory+"/native-mix.wav",FileAccess.WRITE)
	pcm.store_buffer("RIFF".to_ascii_buffer());pcm.store_32(36+recorded.size());pcm.store_buffer("WAVEfmt ".to_ascii_buffer());pcm.store_32(16);pcm.store_16(3);pcm.store_16(2);pcm.store_32(int(AudioServer.get_mix_rate()));pcm.store_32(int(AudioServer.get_mix_rate())*8);pcm.store_16(8);pcm.store_16(32);pcm.store_buffer("data".to_ascii_buffer());pcm.store_32(recorded.size());pcm.store_buffer(recorded);pcm.close()
	var report={"checks":checks,"passed":failures.is_empty(),"failures":failures,"driver_setting":ProjectSettings.get_setting("audio/driver/driver","Default Windows driver"),"sample_rate":AudioServer.get_mix_rate(),"stats":audio.stats,"capture_slices":capture_slices,"mix_bytes":recorded.size()}
	var file=FileAccess.open(directory+"/audio-regression.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close();print(JSON.stringify(report))
	process_frame.disconnect(collect);AudioServer.remove_bus_effect(AudioServer.get_bus_index("Master"),0);capture=null
	app.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
