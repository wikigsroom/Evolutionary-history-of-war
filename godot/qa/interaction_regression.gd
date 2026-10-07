extends SceneTree

var app
var checks = 0
var failures = []
var window_measurements = []
var directory = "res://../output/qa/godot-polish/"

func _initialize() -> void:
	var output = OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	if not output.is_empty(): directory = output.trim_suffix("/") + "/"
	else:directory=ProjectSettings.globalize_path(directory)
	DirAccess.make_dir_recursive_absolute(directory)
	call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func settle() -> void:
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
func find_control(node: Node, predicate: Callable):
	if node is Control and predicate.call(node): return node
	for child in node.get_children():
		var found = find_control(child, predicate)
		if found != null: return found
	return null
func button(text: String):
	return find_control(app.current_view, func(c): return c is Button and c.text.begins_with(text))
func card(title: String):
	return find_control(app.current_view, func(c): return c is PixelCard and c.title == title)
func icon(tooltip: String):
	return find_control(app.current_view, func(c): return c is BaseButton and c.tooltip_text == tooltip)
func point_input(point: Vector2, touch: bool = false) -> void:
	for pressed in [true, false]:
		if touch:
			var event = InputEventScreenTouch.new(); event.position = point; event.index = 0; event.pressed = pressed; Input.parse_input_event(event)
		else:
			var event = InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; Input.parse_input_event(event)
		await process_frame
	await settle()
func click(control: Control, touch: bool = false) -> void:
	check(is_instance_valid(control), "交互目标存在")
	if not is_instance_valid(control): return
	await point_input(control.get_global_rect().get_center(), touch)
func escape() -> void:
	var event = InputEventKey.new(); event.keycode = KEY_ESCAPE; event.pressed = true; Input.parse_input_event(event); await settle()
	event = InputEventKey.new(); event.keycode = KEY_ESCAPE; event.pressed = false; Input.parse_input_event(event); await process_frame
func capture(name: String) -> void:
	await settle(); root.get_texture().get_image().save_png(directory + name + ".png")
func visible_bounds(control: Control) -> bool:
	return Rect2(Vector2.ZERO, app.current_view.size).encloses(control.get_global_rect())
func record_window(requested: Vector2i, captured_file: String = "") -> void:
	var rendered = root.get_texture().get_image().get_size() if captured_file.is_empty() else Image.load_from_file(directory + captured_file + ".png").get_size()
	window_measurements.append({"requested":[requested.x,requested.y],"reported_window":[root.size.x,root.size.y],"captured_pixels":[rendered.x,rendered.y]})

func run() -> void:
	root.size = Vector2i(1280, 720)
	app = preload("res://scenes/Main.tscn").instantiate(); root.add_child(app); await settle()
	record_window(Vector2i(1280,720))
	app.store = EpochStore.new(app.model.db, "user://qa-interactions-%d/" % Time.get_ticks_usec())
	app.audio.settings = app.store.settings
	app.show_menu("home"); await settle()
	await click(card("整军"))
	check(app.current_view.page == "loadout", "导航点击进入整军")
	await click(card(app.model.db.get_row("heroes", "H03")["name"]))
	check(app.store.profile["loadout"]["heroId"] == "H03", "英雄卡实际换装")
	var spec_id = app.model.db.get_row("heroes", "H03")["specializationIds"][1]
	await click(button(app.model.db.get_row("specializations", spec_id)["name"]))
	check(app.store.profile["loadout"]["specializationId"] == spec_id, "专精按钮实际换装")
	for id in ["S04", "S05"]: await click(card(app.model.db.get_row("skills", id)["name"]))
	check(app.store.profile["loadout"]["commonSkillIds"].has("S04") and app.store.profile["loadout"]["commonSkillIds"].has("S05"), "通用技能保留两项并实际换装")
	var relic = find_control(app.current_view, func(c): return c is PixelCard and c.art_path.ends_with("/I01.png"))
	var equipped = app.store.profile["loadout"]["relicIds"].has("I01")
	await click(relic)
	check(app.store.profile["loadout"]["relicIds"].has("I01") != equipped, "遗物点击实际切换")
	var talent_id = String(app.store.profile["loadout"]["talentIds"][0])
	await click(card(app.model.db.get_row("talents", talent_id)["name"]))
	check(not app.store.profile["loadout"]["talentIds"].has(talent_id), "天赋点击实际退点")
	await click(card("设置"))
	var music = button("背景音乐"); await click(music)
	check(not app.store.settings["music"], "音乐开关生效并保存")
	var options = EpochStore.new(app.model.db, app.store.directory)
	check(not options.settings["music"], "设置从磁盘恢复")
	await click(card("出征")); await click(button("开始对战"))
	check(app.current_view is BattleScreen, "菜单进入真实对局")
	var m = app.model; var view = app.current_view
	m.config["aiEnabled"] = false; m.sides[0]["gold"] = 1800.0
	await click(view.unit_cards[0], true)
	check(m.sides[0]["queue"].size() == 1, "触屏招募进入训练队列")
	await click(icon("训练队列 / 取消招募"))
	var gold_before = float(m.sides[0]["gold"])
	await click(button("取消"))
	check(m.sides[0]["queue"].is_empty() and float(m.sides[0]["gold"]) > gold_before, "队列取消实际退款")
	await escape()
	await click(icon("同代研究与重型解锁"))
	await click(card(EpochData.RESEARCH[1]["name"]))
	check(m.research_level(0, EpochData.RESEARCH[1]["id"]) == 1, "研究购买实际升级")
	await click(card(m.db.research("heavy-unlock")["name"]))
	check(m.heavy_unlocked(0), "重型军团实际开放")
	await escape()
	await click(icon("基地炮塔与插槽"))
	await click(button("近防炮塔"))
	check(m.sides[0]["turrets"].size() == 1, "炮塔购买实际建造")
	await click(button("开放插槽"))
	check(int(m.sides[0]["unlockedSlots"]) == 2, "炮位实际开放")
	await click(button("出售"))
	check(m.sides[0]["turrets"].is_empty(), "炮塔实际出售")
	await escape()
	m.sides[0]["knowledge"] = 1000.0; await settle()
	await click(view.evolve_card)
	var upgrade = m.db.get_row("run-upgrades", "R21")
	await click(card(upgrade["name"].split("·")[0]))
	check(m.ally_era == 2 and m.enemy_era == 1, "进化选型按钮仅改变我方时代")
	check(view.unit_cards[0].art_path.ends_with("/U21.png"), "新时代兵卡实际刷新")
	await click(view.item_cards["chrono-crate"])
	check(int(m.sides[0]["activeItems"]["chrono-crate"]) == 2, "主动道具实际消耗次数")
	var hero = m.hero(0); hero["x"] = 600.0; hero["previousX"] = 600.0; hero["speed"] = 0.0
	m.sides[0]["command"] = 110.0; m.sides[0]["loadout"]["commonSkillIds"] = ["S04", "S05"]
	var enemy = m.spawn(1, "U11", "A1", "unit", 840.0); enemy["speed"] = 0.0
	await click(view.commander)
	var skill_card = view.tray_cards.filter(func(c): return c.get_meta("skill") == "S04")[0]
	await click(skill_card)
	check(view.target_action.get("skillId", "") == "S04", "技能卡进入范围选点状态")
	await click(view.target_cancel, true)
	check(view.target_action.is_empty() and not m.sides[0]["cooldowns"].has("S04"), "触屏取消选点不消耗技能")
	await click(view.commander)
	await click(view.tray_cards.filter(func(c): return c.get_meta("skill") == "S04")[0])
	await point_input(Vector2(view.world.world_to_screen(840.0), view.world.ground - 32.0), true)
	check(view.target_action.is_empty() and m.sides[0]["cooldowns"].has("S04"), "触屏战场选点实际释放技能")
	m.step_ticks(15)
	check(not m.combat.status(enemy, "ST01").is_empty(), "选点技能抵达施加破甲")
	for size_ in [Vector2i(1024,576), Vector2i(2400,1080)]:
		root.size = size_; await settle()
		check(view.unit_cards.all(func(c): return visible_bounds(c)), "横屏招募卡全部在画面内 %s" % size_)
		check(visible_bounds(view.commander) and visible_bounds(view.evolve_card), "横屏战略与指挥官在画面内 %s" % size_)
		await capture("13-battle-%dx%d" % [size_.x,size_.y])
		record_window(size_, "13-battle-%dx%d" % [size_.x,size_.y])
	root.size = Vector2i(1280,720); await settle()
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST); await settle()
	var back_panel = app.current_view.overlay
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(m.paused and app.current_view.overlay == back_panel, "重复系统返回通知不连续关闭暂停层")
	await click(button("继续战斗"))
	await click(icon("暂停 / Esc"))
	var tick = m.tick; await settle(); check(m.tick == tick, "暂停冻结真实进度")
	await click(button("保留对局"))
	check(app.current_view is MenuScreen, "保存退出返回菜单")
	await click(button("继续对局"))
	check(app.current_view is BattleScreen and m.tick >= tick and m.tick < tick + 20 and m.ally_era == 2, "继续对局恢复时代与进度")
	m.combat.hit(m.base(0),m.base(1),1000000.0,"energy",{"canDamageBase":true}); m.combat.apply_hits();m.step_ticks(1)
	await create_timer(1.6).timeout
	check(m.winner == 0 and is_instance_valid(app.current_view.overlay), "胜利打开结算界面")
	check(app.store.load_match().is_empty(), "结算后继续存档彻底清除")
	var result_panel = app.current_view.overlay
	await create_timer(1.6).timeout
	check(app.current_view.overlay == result_panel, "结算界面保持稳定，不循环重建或重复结算")
	await capture("15-result")
	var previous_id = m.config["matchId"]
	await click(button("再次出征"))
	check(m.winner == -1 and m.tick < 20 and m.config["matchId"] != previous_id, "再次出征产生独立新对局")
	app.show_menu("campaign"); await settle()
	await click(find_control(app.current_view,func(c):return c is PixelCard and c.title.begins_with("01 ·")))
	check(is_instance_valid(button("出征")), "关卡打开真实战役简报")
	await capture("16-mission-brief")
	await click(button("出征"))
	check(m.config["mode"] == "campaign" and m.config["missionId"] == "M01", "战役出征使用真实任务参数")
	check(m.db.rows["missions"].size()==20,"十章二十场战役数据")
	app.show_menu("encyclopedia"); await settle()
	for era in m.db.rows["eras"]:
		var age_button=button(era["name"])
		check(is_instance_valid(age_button) and visible_bounds(age_button),"时代图鉴按钮可达："+era["id"])
		await click(age_button)
		check(app.current_view.encyclopedia_era==era["id"],"时代图鉴实际切换："+era["id"])
		for unit in m.db.unit_slots(era["id"]):
			var description=find_control(app.current_view,func(c):return c is Label and c.text==unit["name"])
			check(is_instance_valid(description) and visible_bounds(description),"图鉴兵种资料完整可见："+unit["id"])
	var practice_control=icon("以所选时代开始自由演练")
	check(visible_bounds(practice_control) and practice_control.size.y<65,"演练入口保持紧凑且可见")
	await capture("18-ten-era-encyclopedia")
	await click(icon("以所选时代开始自由演练"),true)
	check(app.current_view is BattleScreen and m.ally_era==10 and m.enemy_era==10,"触屏由图鉴进入双方轨道时代演练")
	check(app.current_view.unit_cards[0].art_path.ends_with("/U101.png"),"轨道演练实际加载对应兵卡")
	await capture("19-age10-practice")
	app.show_menu("loadout"); root.size = Vector2i(2400,1080); await settle()
	check(visible_bounds(card("设置")), "移动横屏菜单导航在画面内")
	await capture("17-loadout-wide")
	var file = FileAccess.open(directory + "interaction-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"windows":window_measurements,"touch_input":true},"\t"));file.close()
	print("INTERACTION_REGRESSION ", JSON.stringify({"checks":checks,"failures":failures}))
	app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
