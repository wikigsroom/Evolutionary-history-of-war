class_name BattleScreen
extends Control
signal back_to_menu
signal replay_requested
var model
var store: EpochStore
var audio: BattleAudio
var world: BattleWorld
var unit_cards = []
var item_cards = {}
var evolve_card: PixelCard
var age_card: PixelCard
var commander: CommanderButton
var queue_label: Label
var training_queue: TrainingQueue
var minimap: BattleMinimap
var target_label: Label
var target_cancel: BaseButton
var toast_label: Label
var overlay: Control
var tray: PixelPanel
var tray_cards = []
var target_action = {}
var autosave = 0.0
var result_delay = -1.0
var result_shown = false
var toast_time = 0.0
var sequence = 0

func setup(simulation, persistence: EpochStore, sound: BattleAudio) -> void:
	model = simulation; store = persistence; audio = sound
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world = BattleWorld.new(); world.setup(model,audio,store.settings); add_child(world); world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.field_clicked.connect(_select_field)
	world.cancel_requested.connect(_clear_target)
	var readout = BattleReadout.new(); readout.model = model; add_child(readout); readout.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); readout.offset_bottom = 78
	var pause = PixelTheme.icon_button("pause","暂停 / Esc")
	add_child(pause); pause.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT); pause.offset_left=-66;pause.offset_right=-17;pause.offset_top=15;pause.offset_bottom=61;pause.pressed.connect(_pause_menu)
	var utilities = HBoxContainer.new(); utilities.add_theme_constant_override("separation",7); add_child(utilities); utilities.position = Vector2(15,91)
	world.field_blockers.append(utilities)
	for item in [["research","战况与时代地图",_battle_map],["target","显示攻击距离",_toggle_ranges],["queue","训练队列 / 取消招募",_queue_menu],["population","兵种图鉴与克制",_unit_info]]:
		var button = PixelTheme.icon_button(item[0],item[1]); utilities.add_child(button); button.pressed.connect(item[2])
	var navigation=VBoxContainer.new();navigation.add_theme_constant_override("separation",5);add_child(navigation);navigation.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);navigation.offset_left=-239;navigation.offset_right=-16;navigation.offset_top=89;navigation.offset_bottom=179
	world.field_blockers.append(navigation)
	minimap=BattleMinimap.new();minimap.world=world;navigation.add_child(minimap)
	var jumps=HBoxContainer.new();jumps.add_theme_constant_override("separation",7);navigation.add_child(jumps)
	for entry in [["ally","shield","定位我方基地"],["front","sword","跟随前线"],["hero","crown","跟随指挥官"],["enemy","target","定位敌方基地"]]:
		var jump_button=PixelTheme.icon_button(entry[1],entry[2]);jumps.add_child(jump_button);jump_button.pressed.connect(func():world.jump(entry[0]))
	var deck = HBoxContainer.new(); deck.name = "BattleDeck"; add_child(deck); deck.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE); deck.offset_left=12;deck.offset_right=-12;deck.offset_top=-218;deck.offset_bottom=-12
	world.field_blockers.append(deck)
	deck.add_theme_constant_override("separation",8)
	var recruit = PixelPanel.new(); recruit.heading="招募";recruit.custom_minimum_size.x=486;recruit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;deck.add_child(recruit)
	var recruit_body = VBoxContainer.new();recruit_body.add_theme_constant_override("separation",5);recruit.add_child(recruit_body)
	var recruit_row = HBoxContainer.new();recruit_row.add_theme_constant_override("separation",7);recruit_body.add_child(recruit_row)
	for i in range(5):
		var card = PixelCard.new();card.paper=true;card.custom_minimum_size=Vector2(78,110);card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.hotkey=str(i+1);recruit_row.add_child(card);unit_cards.append(card)
		card.pressed.connect(func(): _recruit(i))
	training_queue=TrainingQueue.new();recruit_body.add_child(training_queue);queue_label=training_queue.status_label;training_queue.order_selected.connect(func(_id):_queue_menu())
	var items = PixelPanel.new();items.heading="战术道具";items.custom_minimum_size.x=237;deck.add_child(items)
	var item_row=HBoxContainer.new();item_row.add_theme_constant_override("separation",7);items.add_child(item_row)
	for item_id in EpochData.ITEMS.keys():
		var card=PixelCard.new();card.icon_id=EpochData.ITEMS[item_id]["icon"];card.custom_minimum_size=Vector2(62,127);card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.tooltip_text=EpochData.ITEMS[item_id]["name"]+"\n"+EpochData.ITEMS[item_id]["description"];item_row.add_child(card);item_cards[item_id]=card
		card.title={"war-drum":"战鼓","smoke-bomb":"烟幕","chrono-crate":"补给"}[item_id];card.hotkey={"war-drum":"Z","smoke-bomb":"X","chrono-crate":"C"}[item_id]
		card.pressed.connect(func(): _use_item(item_id))
	var command=PixelPanel.new();command.heading="战略";command.custom_minimum_size.x=341;deck.add_child(command)
	var command_row=HBoxContainer.new();command_row.add_theme_constant_override("separation",7);command.add_child(command_row)
	var buttons=VBoxContainer.new();buttons.add_theme_constant_override("separation",7);command_row.add_child(buttons)
	var utility_row=HBoxContainer.new();utility_row.add_theme_constant_override("separation",7);buttons.add_child(utility_row)
	var research=PixelTheme.icon_button("research","同代研究与重型解锁");utility_row.add_child(research);research.pressed.connect(_research_menu)
	var tower=PixelTheme.icon_button("tower","基地炮塔与插槽");utility_row.add_child(tower);tower.pressed.connect(_turret_menu)
	age_card=PixelCard.new();age_card.icon_id="meteor";age_card.title="奇袭";age_card.custom_minimum_size=Vector2(54,52);age_card.compact=true;utility_row.add_child(age_card);age_card.pressed.connect(_age_special)
	var note=PixelTheme.label("交战积累经验\n进化或释放奇袭",12,PixelTheme.MUTED);note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;buttons.add_child(note)
	evolve_card=PixelCard.new();evolve_card.gold=true;evolve_card.icon_id="evolve";evolve_card.title="进化";evolve_card.value_icon="xp";evolve_card.custom_minimum_size=Vector2(112,127);command_row.add_child(evolve_card);evolve_card.pressed.connect(_evolve_menu)
	commander=CommanderButton.new();commander.hero_id=model.sides[0]["loadout"]["heroId"];commander.tooltip_text="指挥官：技能与站位 / Q";deck.add_child(commander);commander.pressed.connect(_toggle_tray)
	target_label=PixelTheme.label("",17,PixelTheme.AMBER);target_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(target_label);target_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);target_label.offset_left=275;target_label.offset_right=-275;target_label.offset_top=84;target_label.offset_bottom=110;target_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	target_cancel=PixelTheme.icon_button("back","取消施放");add_child(target_cancel);target_cancel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);target_cancel.offset_left=-300;target_cancel.offset_right=-248;target_cancel.offset_top=114;target_cancel.offset_bottom=166;target_cancel.visible=false;target_cancel.pressed.connect(_clear_target)
	world.field_blockers.append(target_cancel)
	toast_label=PixelTheme.label("",15,PixelTheme.INK);toast_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(toast_label);toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);toast_label.offset_left=275;toast_label.offset_right=-310;toast_label.offset_top=115;toast_label.offset_bottom=140;toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	audio.play_era_music(model.ally_era);sequence=int(model.last_action_sequence)+1
	for child in get_children():
		if child is CanvasItem and child!=world:child.z_index=100
	_refresh_hud()
	if model.tick == 0: notify("拖动战场 · 1–5 招募 · Z/X/C 道具",6.0)
func _process(delta: float) -> void:
	model.advance(delta)
	_refresh_hud()
	if toast_time>0:toast_time-=delta;toast_label.visible=toast_time>0
	if not model.paused and model.winner==-1:
		autosave+=delta
		if autosave>=5.0:autosave=0;save_current()
	if model.winner>=0 and result_delay<0 and not result_shown:result_delay=1.4;_clear_target();_close_tray();world.jump("enemy" if model.winner==0 else "ally")
	if result_delay>0:
		result_delay-=delta
		if result_delay<=0:_result_menu()
func notify(message: String, seconds: float=2.0) -> void:
	toast_label.text=message;toast_label.visible=true;toast_time=seconds
func save_current() -> void:
	var saved=model.snapshot();saved["view"]={"cameraX":world.camera_x,"tracking":world.tracking};store.save_match(saved)
func restore_view(state: Dictionary) -> void:
	var x=float(state.get("cameraX",world.MAP_LEFT))
	if is_finite(x):world.camera_x=x
	world.tracking=state.get("tracking","free") if state.get("tracking","free") in ["free","hero","front"] else "free"
func _dispatch(action: Dictionary) -> bool:
	sequence+=1
	var result=model.act(action,sequence)
	if not result["ok"]:notify(result.get("reason","指令未生效"));audio.sfx("ui_error");return false
	if String(action.get("type","")) == "stance":audio.sfx("rush_flag" if action.get("stance")=="rush" else "ui_confirm",.7)
	elif String(action.get("type","")) not in ["train","evolve","research","turret","cast","item","ageSpecial"]:audio.sfx("ui_confirm",.45)
	_refresh_hud();return true
func _refresh_hud() -> void:
	if not is_instance_valid(evolve_card):return
	var player=model.sides[0]
	var rows=model.db.unit_slots(player["eraId"])
	for i in range(5):
		var row=rows[i];var card=unit_cards[i]
		card.title=row["name"];card.art_path="res://assets/ui/units/"+row["id"]+".png";card.value=str(model.unit_cost(0,row["id"]))
		card.locked=bool(row["heavy"]) and not model.heavy_unlocked(0)
		card.disabled=(float(player["gold"])<model.unit_cost(0,row["id"]) or player["queue"].size()>=5 or model.winner!=-1) and not card.locked
		var multiplier=float(model.db.era(row["eraId"])["hpAttackMultiplier"])
		card.tooltip_text="%s · %s\n生命 %s / 攻击 %s / 射程 %d\n%s" % [row["name"],EpochData.ROLES.get(row["role"],"特种"),PixelTheme.number(float(row["hpBase"])*multiplier),PixelTheme.number(float(row["attackBase"])*multiplier),int(row["range"]),"先研究重型军团" if card.locked else row.get("special",{}).get("auraLabel","点击招募，按队列依次出营")]
		card.update_visual()
	training_queue.refresh(model)
	for id in item_cards.keys():
		var card=item_cards[id];card.charges=int(player["activeItems"][id]);card.cooldown=maxf(0.0,float(int(player["itemCooldowns"].get(id,0))-model.tick)/30.0);card.disabled=card.charges<=0 or card.cooldown>0 or model.winner!=-1;card.update_visual()
		card.selected=target_action.get("itemId","")==id
		var active=int(player.get("itemActiveUntil",{}).get(id,0))-model.tick
		card.active_progress=float(active)/(150.0 if id=="smoke-bomb" else 240.0) if active>0 else -1.0
		card.tooltip_text=EpochData.ITEMS[id]["name"]+"\n"+EpochData.ITEMS[id]["description"]+("\n点击道具，再点战场；拖动只移动镜头" if EpochData.ITEMS[id]["target"] else "\n点击立即使用")
	var special=model.db.age_special(player["eraId"])
	age_card.cooldown=maxf(0.0,float(int(player["ageSpecialReadyAt"])-model.tick)/30.0);age_card.disabled=age_card.cooldown>0 or float(player["knowledge"])<float(special["cost"]) or model.winner!=-1
	age_card.tooltip_text="%s\n消耗 %d 战斗经验；与进化共用经验\n%d 秒冷却" % [special["name"],int(special["cost"]),int(special["cooldown"])];age_card.update_visual()
	var cost=model.era_cost(0)
	var maxed=player["eraId"]==model.max_era or cost<=0
	evolve_card.value="终代" if maxed else "%d/%d" % [floori(float(player["knowledge"])),int(cost)]
	evolve_card.progress=1.0 if maxed else float(player["knowledge"])/cost
	evolve_card.disabled=maxed or float(player["knowledge"])<cost or model.winner!=-1
	evolve_card.tooltip_text="已达本局时代上限" if maxed else "进化到 "+model.db.era("A%d"%(model.ally_era+1))["name"]+"\n首都生命上限按兵种比例增长，进化后回满；指挥官保留生命比例；原有兵与训练订单保留原时代"
	evolve_card.update_visual()
	var hero=model.hero(0)
	commander.hero_id=model.db.visual_id(player["loadout"]["heroId"],player["eraId"])
	commander.health=float(hero["hp"])/float(hero["maxHp"]) if not hero.is_empty() else 0.0;commander.respawn=maxf(0.0,float(int(player["heroRespawnAt"])-model.tick)/30.0);commander.queue_redraw()
	for card in tray_cards:
		card.title=model.db.skill_name(card.get_meta("skill"),player["loadout"]["heroId"],player["eraId"])
		if model.db.get_row("skills",card.get_meta("skill"))["category"]=="signature":
			card.art_path="res://assets/ui/heroes/"+model.db.visual_id(player["loadout"]["heroId"],player["eraId"])+".png"
			card.tooltip_text=card.title+" · "+model.db.era(player["eraId"])["name"]+"\n"+model.db.get_row("skills",card.get_meta("skill"))["description"]
		card.cooldown=maxf(0.0,float(int(player["cooldowns"].get(card.get_meta("skill"),0))-model.tick)/30.0)
		card.disabled=hero.is_empty() or hero.get("garrisoned",false) or card.cooldown>0 or float(player["command"])<model.abilities.cost(0,card.get_meta("skill"));card.update_visual()
func _recruit(index: int) -> void:
	if unit_cards[index].locked:_research_menu();return
	_dispatch({"type":"train","unitId":model.db.unit_slots(model.sides[0]["eraId"])[index]["id"]})
func _toggle_ranges() -> void:world.show_ranges=not world.show_ranges
func _use_item(id: String) -> void:
	if model.paused or model.winner!=-1:return
	if item_cards[id].disabled:notify("道具冷却中或已经用完");return
	if target_action.get("itemId","")==id:_clear_target();return
	_clear_target()
	if EpochData.ITEMS[id]["target"]:_arm({"type":"item","itemId":id},EpochData.ITEMS[id]["name"],135.0,1600.0)
	elif _dispatch({"type":"item","itemId":id}):notify("战鼓令 · 全军强化 8 秒" if id=="war-drum" else "补给 +%s 金币 · +15 军令 · 加速训练" % PixelTheme.number(65.0*float(model.db.era(model.sides[0]["eraId"])["costMultiplier"])))
func _age_special() -> void:_arm({"type":"ageSpecial"},model.db.age_special(model.sides[0]["eraId"])["name"],float(model.db.age_special(model.sides[0]["eraId"])["radius"]),1600)
func _arm(action: Dictionary,title: String,radius: float,cast_range: float) -> void:
	_clear_target();target_action=action;world.target_preview={"radius":radius,"range":cast_range,"heroRange":action["type"]=="cast"};target_label.text=title+" · 点战场施放 · 拖动移动镜头";target_cancel.visible=true;_close_tray();_refresh_hud()
func _clear_target() -> void:
	target_action={};world.target_preview={};target_label.text="";target_cancel.visible=false
	for card in item_cards.values():card.selected=false;card.update_visual()
func _select_field(x: float,target_id: int) -> void:
	if target_action.is_empty() or model.paused:return
	var action=target_action.duplicate(true);action["x"]=x;action["targetId"]=target_id
	if _dispatch(action):
		_clear_target()
		if action.get("itemId")=="smoke-bomb":notify("烟幕已部署 · 范围减速 5 秒")
func _toggle_tray() -> void:
	if is_instance_valid(tray):_close_tray();return
	_clear_target()
	tray=PixelPanel.new();tray.heading="指挥官";add_child(tray);tray.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);tray.offset_left=-340;tray.offset_right=-16;tray.offset_top=-385;tray.offset_bottom=-205
	tray.z_index=110
	world.field_blockers.append(tray)
	var body=VBoxContainer.new();body.add_theme_constant_override("separation",7);tray.add_child(body)
	var skills=HBoxContainer.new();skills.add_theme_constant_override("separation",7);body.add_child(skills)
	var loadout=model.sides[0]["loadout"]
	var hero=model.db.get_row("heroes",loadout["heroId"])
	for skill_id in [hero["signatureSkillId"]]+loadout["commonSkillIds"]:
		var row=model.db.get_row("skills",skill_id);var card=PixelCard.new();card.art_path="res://assets/ui/skills/"+skill_id+".png";card.title=row["name"];card.value=str(int(model.abilities.cost(0,skill_id)));card.value_icon="command";card.custom_minimum_size=Vector2(92,104);card.set_meta("skill",skill_id);card.tooltip_text=row["description"];skills.add_child(card);tray_cards.append(card)
		card.pressed.connect(func():_skill(skill_id))
	var stances=HBoxContainer.new();stances.add_theme_constant_override("separation",7);body.add_child(stances)
	for entry in [["retreat","撤退","back"],["cover","护阵","shield"],["rush","突击","sword"]]:
		var button=Button.new();button.text=entry[1];button.icon=PixelTheme.icon(entry[2]);button.expand_icon=true;button.add_theme_constant_override("icon_max_width",19);PixelTheme.apply_button(button,PixelTheme.CYAN,true);button.custom_minimum_size.x=92;stances.add_child(button)
		button.pressed.connect(func():_dispatch({"type":"stance","stance":entry[0]}))
	commander.selected=true;_refresh_hud()
func _close_tray() -> void:
	if is_instance_valid(tray):tray.queue_free()
	tray=null;tray_cards=[]
	if is_instance_valid(commander):commander.selected=false
func _skill(id: String) -> void:
	var row=model.db.get_row("skills",id)
	if row["targetMode"] in ["self","direction_self"]:_dispatch({"type":"cast","skillId":id})
	else:_arm({"type":"cast","skillId":id},model.db.skill_name(id,model.sides[0]["loadout"]["heroId"],model.sides[0]["eraId"]),float(row["radius"]),float(row["castRange"])+(float(model.modifiers(0).get("commonCastRangeAdd",0.0)) if row["category"]=="common" else 0.0))
func _modal(title: String,width: float=690.0,height: float=390.0) -> VBoxContainer:
	_close_modal();_clear_target();_close_tray();model.set_paused(true)
	audio.set_battle_paused(true)
	overlay=Control.new();add_child(overlay);overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index=200
	var shade=ColorRect.new();shade.color=Color(0.015,0.025,0.05,0.82);overlay.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel=PixelPanel.new();panel.heading=title;overlay.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER);panel.offset_left=-width/2;panel.offset_right=width/2;panel.offset_top=-height/2;panel.offset_bottom=height/2
	var body=VBoxContainer.new();body.add_theme_constant_override("separation",12);panel.add_child(body)
	var close=PixelTheme.icon_button("back","返回");overlay.add_child(close);close.set_anchors_and_offsets_preset(Control.PRESET_CENTER);close.offset_left=width/2-45;close.offset_right=width/2+7;close.offset_top=-height/2-28;close.offset_bottom=-height/2+24;close.pressed.connect(go_back)
	return body
func _close_modal() -> void:
	if is_instance_valid(overlay):overlay.queue_free()
	overlay=null
	world.cancel_pointer()
	if model!=null and model.winner==-1:model.set_paused(false);audio.set_battle_paused(false)
func _button(parent: Control,text: String,callable: Callable,gold: bool=false) -> Button:
	var button=Button.new();button.text=text;PixelTheme.apply_button(button,PixelTheme.AMBER if gold else PixelTheme.CYAN,true);parent.add_child(button);button.pressed.connect(func():audio.sfx("ui_confirm",.6);callable.call());return button
func _research_menu() -> void:
	var body=_modal("同代研究 · 强化跨时代保留",760,390)
	var grid=GridContainer.new();grid.columns=4;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",12);body.add_child(grid)
	for row in EpochData.RESEARCH:
		var card=PixelCard.new();card.icon_id=row["icon"];card.title=row["name"];card.value=str(model.research_cost(0,row["id"]));card.custom_minimum_size=Vector2(172,132);card.tooltip_text=row["description"];card.progress=float(model.research_level(0,row["id"]))/float(row["max"]);card.locked=model.research_level(0,row["id"])>=int(row["max"]);card.disabled=card.locked or float(model.sides[0]["gold"])<model.research_cost(0,row["id"]);grid.add_child(card)
		card.pressed.connect(func():if _dispatch({"type":"research","researchId":row["id"]}):_research_menu())
	body.add_child(PixelTheme.label("强化增加真实属性；重型兵和炮塔由军资支付。",14,PixelTheme.MUTED))
func _turret_menu() -> void:
	var body=_modal("基地防御",750,390)
	var row_box=HBoxContainer.new();row_box.add_theme_constant_override("separation",12);body.add_child(row_box)
	var player=model.sides[0]
	for slot in range(3):
		var column=VBoxContainer.new();column.custom_minimum_size.x=227;column.add_theme_constant_override("separation",10);row_box.add_child(column)
		column.add_child(PixelTheme.label("炮位 %d"%(slot+1),18,PixelTheme.AMBER))
		if slot>=int(player["unlockedSlots"]):
			var unlock=_button(column,"开放插槽 · %d"%[90,180][int(player["unlockedSlots"])-1],func():if _dispatch({"type":"unlockSlot"}):_turret_menu())
			unlock.disabled=slot!=int(player["unlockedSlots"]) or float(player["gold"])<[90,180][int(player["unlockedSlots"])-1]
			continue
		var installed={}
		for tower in player["turrets"]:
			if int(tower["slot"])==slot:installed=tower
		if not installed.is_empty():
			var image=TextureRect.new();image.texture=PixelTheme.texture("res://assets/environment/turrets/"+installed["contentId"]+".png");image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image.custom_minimum_size.y=130;column.add_child(image)
			column.add_child(PixelTheme.label(model.db.get_row("turrets",installed["contentId"])["name"],13))
			_button(column,"出售 · 返还 %d"%floori(float(installed["paid"])*0.6),func():if _dispatch({"type":"sell","slot":slot}):_turret_menu())
		else:
			for type in range(1,3):
				var id="TR%d%d"%[model.ally_era,type];var tower=model.db.get_row("turrets",id);var cost=ceili(float(tower["costBase"])*float(model.db.era(player["eraId"])["costMultiplier"]))
				var button=_button(column,("近防" if type==1 else "远轰")+"炮塔 · "+str(cost),func():if _dispatch({"type":"turret","slot":slot,"turretId":id}):_turret_menu())
				button.disabled=float(player["gold"])<cost;button.tooltip_text="射程 %d · %s"%[int(tower["range"]),"单体速射" if type==1 else "范围溅射"]
	body.add_child(PixelTheme.label("已建炮塔保留原时代。出售后可换装本时代炮塔。",14,PixelTheme.MUTED))
func _evolve_menu() -> void:
	var next_era="A%d"%(model.ally_era+1)
	if model.sides[0]["eraId"]==model.max_era:return
	var body=_modal("进化 · "+model.db.era(next_era)["name"],680,340)
	body.add_child(PixelTheme.label("选择本次进化的军备方向",20,PixelTheme.AMBER))
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",12);body.add_child(row)
	for index in range(1,4):
		var id="R%d%d"%[model.ally_era+1,index];var upgrade=model.db.get_row("run-upgrades",id)
		var card=PixelCard.new();card.gold=index==1;card.icon_id=["sword","shield","research"][index-1];card.title=upgrade["name"].split("·")[0];card.value=str(int(model.era_cost(0)));card.value_icon="xp";card.custom_minimum_size=Vector2(208,160);card.tooltip_text=upgrade["description"];row.add_child(card)
		card.pressed.connect(func():if _dispatch({"type":"evolve","upgradeId":id}):_close_modal())
	body.add_child(PixelTheme.label("基地 / 指挥官保持生命比例；新兵获得换代冲锋加成。",14,PixelTheme.MUTED))
func _queue_menu() -> void:
	var body=_modal("训练队列",640,390)
	var queue=model.sides[0]["queue"]
	if queue.is_empty():body.add_child(PixelTheme.label("队列为空 · 从下方兵卡招募",20));return
	for order in queue:
		var row=HBoxContainer.new();row.add_theme_constant_override("separation",12);body.add_child(row)
		var label=PixelTheme.label("%s · 时代%s · %.1fs"%[model.db.get_row("units",order["unitId"])["name"],EpochData.ROMAN[model.db.era_index(order["eraId"])],float(order["remaining"])/30.0],17);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(label)
		_button(row,"取消",func():if _dispatch({"type":"cancel","queueId":int(order["id"])}):_queue_menu())
	body.add_child(PixelTheme.label("未开始全额退款；已开始退75%；出口堵塞保留完工兵。",14,PixelTheme.MUTED))
func _battle_map() -> void:
	var body=_modal("战况",660,330)
	for side in range(2):
		var player=model.sides[side]
		body.add_child(PixelTheme.label(("我方" if side==0 else "敌方")+" · "+model.db.era(player["eraId"])["name"],24,PixelTheme.CYAN if side==0 else PixelTheme.RED))
		body.add_child(PixelTheme.label("击破 %d   ·   兵力 %d   ·   炮塔 %d"%[int(player["kills"]),model.population(side),player["turrets"].size()],17))
	body.add_child(PixelTheme.label("双方通过各自的交战积累经验，独立决定进化。摧毁敌方基地获胜。",14,PixelTheme.MUTED))
func _unit_info() -> void:
	var body=_modal("兵种克制",670,330)
	body.add_child(PixelTheme.label("前排 → 远程 → 破甲 → 重型 → 前排",25,PixelTheme.AMBER))
	body.add_child(PixelTheme.label("短兵只由队首接敌；矛兵可隔一名友军支援。\n远程在后排开火，弹道抵达后造成伤害。\n特种兵提供光环、治疗、护盾或首击强化。\n重型兵需研究开放，攻城伤害更高。\n战鼓强化全军；烟幕减速；时序补给推进训练。",18))
func _pause_menu() -> void:
	if model.winner!=-1:return
	audio.sfx("ui_confirm",.6)
	save_current()
	var body=_modal("暂停",540,455)
	_button(body,"继续战斗",_close_modal,true)
	_button(body,"保留对局 · 返回菜单",func():save_current();back_to_menu.emit())
	var reduced=CheckButton.new();reduced.text="降低镜头动态";reduced.button_pressed=store.settings["reduced_motion"];body.add_child(reduced);reduced.toggled.connect(func(value):store.settings["reduced_motion"]=value;store.save_settings())
	AudioSettings.add_rows(body,store,audio)
func _result_menu() -> void:
	result_shown=true;result_delay=-1.0
	store.record_result(model.config,model.winner,{"elapsed":model.elapsed,"kills":int(model.sides[0]["kills"])})
	audio.play_music("victory" if model.winner==0 else ("draw" if model.winner==2 else "defeat"))
	var body=_modal("战斗结束",540,350)
	body.add_child(PixelTheme.label("胜利" if model.winner==0 else ("平局" if model.winner==2 else "再整军旗"),44,PixelTheme.AMBER if model.winner==0 else PixelTheme.RED))
	body.add_child(PixelTheme.label("%02d:%02d · 击破%d · 时代%s"%[int(model.elapsed)/60,int(model.elapsed)%60,int(model.sides[0]["kills"]),EpochData.ROMAN[model.ally_era-1]],18))
	if model.winner==0 and not String(model.config["missionId"]).is_empty():body.add_child(PixelTheme.label("战役奖励与解锁已保存",16,PixelTheme.GREEN))
	if not store.last_rewards.is_empty():
		var rewards=PixelTheme.label("遗物："+" · ".join(store.last_rewards),15,PixelTheme.AMBER);rewards.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(rewards)
	_button(body,"再次出征",func():replay_requested.emit(),true)
	_button(body,"返回菜单",func():back_to_menu.emit())
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:_clear_target()
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_ESCAPE:go_back();get_viewport().set_input_as_handled();return
	if model.paused or model.winner!=-1:return
	if event.keycode>=KEY_1 and event.keycode<=KEY_5:_recruit(event.keycode-KEY_1)
	elif event.keycode==KEY_Q:_toggle_tray()
	elif event.keycode==KEY_E and not evolve_card.disabled:_evolve_menu()
	elif event.keycode==KEY_Z:_use_item("war-drum")
	elif event.keycode==KEY_X:_use_item("smoke-bomb")
	elif event.keycode==KEY_C:_use_item("chrono-crate")
	elif event.keycode in [KEY_A,KEY_LEFT]:world.pan(-140)
	elif event.keycode in [KEY_D,KEY_RIGHT]:world.pan(140)
	elif event.keycode==KEY_HOME:world.jump("ally")
	elif event.keycode==KEY_END:world.jump("enemy")
func go_back() -> void:
	if not target_action.is_empty() or is_instance_valid(overlay) or is_instance_valid(tray):audio.sfx("ui_cancel",.65)
	if model.winner>=0:
		if result_shown:back_to_menu.emit()
		else:_result_menu()
	elif not target_action.is_empty():_clear_target()
	elif is_instance_valid(overlay):_close_modal()
	elif is_instance_valid(tray):_close_tray()
	else:_pause_menu()
