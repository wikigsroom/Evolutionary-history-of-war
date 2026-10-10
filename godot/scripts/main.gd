extends Node
var model: GameModel
var store: EpochStore
var audio: BattleAudio
var online: EpochNetClient
var host: Control
var current_view: Control
var last_back_request = -1000
func _ready() -> void:
	model=GameModel.new();add_child(model)
	store=EpochStore.new(model.db)
	audio=BattleAudio.new();audio.settings=store.settings;add_child(audio)
	online=EpochNetClient.new();online.name="OnlineClient";add_child(online)
	online.battle_available.connect(show_online_battle)
	host=Control.new();host.name="ViewHost";host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.theme=PixelTheme.make_theme();add_child(host)
	get_tree().auto_accept_quit=false
	if OS.has_feature("android") or store.settings["fullscreen"]:DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	show_menu("home")
func _clear_view() -> void:
	if is_instance_valid(current_view):host.remove_child(current_view);current_view.queue_free()
	current_view=null
func show_menu(page: String="home") -> void:
	_clear_view()
	var view=MenuScreen.new();view.name="MenuScreen";view.page=page;view.store=store;view.audio=audio;view.online=online
	if page=="online-loadout":
		var build_store=EpochStore.new(model.db,"user://online-build/")
		build_store.profile["unlocked_heroes"]=model.db.tables["heroes"].keys()
		build_store.profile["relics"]=model.db.tables["relics"].keys()
		build_store.profile["mastery"]=6
		build_store.profile["loadout"]=online.loadout.duplicate(true)
		view.store=build_store
	view.page_requested.connect(show_menu);view.start_battle.connect(show_battle);view.resume_battle.connect(resume_battle)
	view.resume_online.connect(func():if online.battle_state!=null:show_online_battle(online.battle_state))
	host.add_child(view);current_view=view
func show_battle(options: Dictionary={}) -> void:
	if online.battle_state!=null and not online.finished:show_online_battle(online.battle_state);return
	var config=store.next_match_config(options.get("mode","standard"),options.get("missionId",""),options.get("difficultyId","D02"))
	config.merge(options,true)
	model.reset_battle(config)
	store.save_match(model.snapshot())
	_show_battle_view()
func resume_battle() -> void:
	if online.battle_state!=null and not online.finished:show_online_battle(online.battle_state);return
	var saved=store.load_match()
	if not model.restore(saved):show_menu("home");return
	_show_battle_view(saved.get("view",{}))
func _show_battle_view(view_state: Dictionary = {}) -> void:
	_clear_view()
	var view=BattleScreen.new();view.name="BattleScreen";view.setup(model,store,audio)
	view.back_to_menu.connect(func():show_menu("home"))
	view.replay_requested.connect(func():show_battle({"mode":model.config["mode"],"missionId":model.config["missionId"],"difficultyId":model.config["difficultyId"]}))
	host.add_child(view);current_view=view
	view.restore_view(view_state)

func show_online_battle(state) -> void:
	if is_instance_valid(current_view) and current_view is BattleScreen and current_view.model==state:return
	_clear_view()
	var view=BattleScreen.new();view.name="BattleScreen";view.setup(state,store,audio);view.online_client=online
	view.back_to_menu.connect(func():show_menu("online"))
	view.replay_requested.connect(func():await online.acknowledge_result();show_menu("online"))
	host.add_child(view);current_view=view
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_PAUSED and is_instance_valid(audio):audio.set_suspended(true)
	if what==NOTIFICATION_APPLICATION_RESUMED:
		if is_instance_valid(audio):audio.set_suspended(false)
		if OS.has_feature("android"):DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:
		var now=Time.get_ticks_msec()
		if now-last_back_request<200:return
		last_back_request=now
		if is_instance_valid(current_view) and current_view is BattleScreen:current_view.go_back()
		elif is_instance_valid(current_view) and current_view.page!="home":show_menu("home")
		else:get_tree().quit()
	if what in [NOTIFICATION_WM_CLOSE_REQUEST,NOTIFICATION_APPLICATION_PAUSED]:
		if is_instance_valid(current_view) and current_view is BattleScreen and model.winner==-1:current_view.save_current()
		if what==NOTIFICATION_WM_CLOSE_REQUEST:get_tree().quit()
