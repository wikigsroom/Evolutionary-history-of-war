class_name MenuScreen
extends Control
signal page_requested(page: String)
signal start_battle(options: Dictionary)
signal resume_battle
var page = "home"
var store: EpochStore
var audio: BattleAudio
var body: Control
var difficulty = "D02"
var encyclopedia_era = "A1"
var message: Label
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	audio.set_battle_paused(false)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var header=HBoxContainer.new();add_child(header);header.position=Vector2(24,15);header.add_theme_constant_override("separation",13)
	var crest=TextureRect.new();crest.name="BrandKnight";crest.texture=PixelTheme.texture("res://assets/ui/pixel/app-icon.png");crest.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;crest.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;crest.custom_minimum_size=Vector2(50,50);header.add_child(crest)
	_brand_logo(header,Vector2(230,50),"HeaderLogo")
	var nav=HBoxContainer.new();add_child(nav);nav.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);nav.offset_left=-658;nav.offset_right=-24;nav.offset_top=14;nav.offset_bottom=74;nav.add_theme_constant_override("separation",7)
	for entry in [["home","出征","sword"],["campaign","战役","research"],["loadout","整军","crown"],["encyclopedia","图鉴","population"],["settings","设置","sound"]]:
		var card=PixelCard.new();card.compact=true;card.icon_id=entry[2];card.title=entry[1];card.selected=page==entry[0];card.custom_minimum_size=Vector2(118,58);card.tooltip_text=entry[1];nav.add_child(card)
		card.pressed.connect(func():audio.sfx("ui_confirm",0.5);page_requested.emit(entry[0]))
	var host=Control.new();add_child(host);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.offset_left=28;host.offset_right=-28;host.offset_top=101;host.offset_bottom=-42;body=host
	message=PixelTheme.label("",16,PixelTheme.AMBER);add_child(message);message.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);message.offset_left=28;message.offset_top=-30;message.offset_bottom=-8
	match page:
		"home":_home()
		"campaign":_campaign()
		"loadout":_loadout()
		"encyclopedia":_encyclopedia()
		"settings":_settings()
	audio.play_music("menu")
	queue_redraw()
func _draw() -> void:
	var background=PixelTheme.texture("res://assets/environment/eras/A1-1.png")
	if background:draw_texture_rect(background,Rect2(0,0,size.x,size.y),false)
	draw_rect(Rect2(0,0,size.x,84),Color(PixelTheme.NAVY,0.97))
	draw_rect(Rect2(0,84,size.x,size.y-84),Color(PixelTheme.NAVY,0.22 if page=="home" else 0.64))
	if page=="home":
		var base=PixelTheme.texture("res://assets/base/A1.png")
		if base:draw_texture_rect(base,Rect2(-35,size.y-412,480,320),false)
		for i in range(6):
			var id=["U11","U21","H01-A4","U54","U71","U101"][i]
			var image=PixelTheme.texture("res://assets/ui/units/"+id+".png")
			if id.begins_with("H"):
				image=PixelTheme.texture("res://assets/ui/heroes/"+id+".png")
			if image:
				var height=120.0 if i!=3 else 153.0
				var width=image.get_width()*height/image.get_height()
				draw_texture_rect(image,Rect2(200+i*68,size.y-107-height,width,height),false)
func _panel(parent: Control,title: String="") -> PixelPanel:
	var panel=PixelPanel.new();panel.heading=title;parent.add_child(panel);return panel
func _text(parent: Control,text: String,size_: int=17,color: Color=PixelTheme.INK) -> Label:
	var label=PixelTheme.label(text,size_,color);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(label);return label
func _button(parent: Control,title: String,callable: Callable,gold: bool=false) -> Button:
	var button=Button.new();button.text=title;PixelTheme.apply_button(button,PixelTheme.AMBER if gold else PixelTheme.CYAN);parent.add_child(button);button.pressed.connect(func():audio.sfx("ui_confirm",.65);callable.call());return button
func _scroll(parent: Control) -> VBoxContainer:
	var scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;parent.add_child(scroll);scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var box=VBoxContainer.new();box.add_theme_constant_override("separation",12);box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(box);return box
func _brand_logo(parent: Control,minimum: Vector2,node_name: String) -> TextureRect:
	var logo=TextureRect.new();logo.name=node_name;logo.texture=PixelTheme.texture("res://assets/ui/brand/game-logo.png");logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;logo.custom_minimum_size=minimum;logo.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;parent.add_child(logo);return logo
func _home() -> void:
	var title=_brand_logo(body,Vector2(560,175),"HomeLogo");title.position=Vector2(29,7)
	var tagline=PixelTheme.label("十个时代 · 一条战线 · 每一次进化都改变战局",17,PixelTheme.MUTED);body.add_child(tagline);tagline.position=Vector2(32,192)
	var panel=_panel(body,"出征");panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);panel.offset_left=-395;panel.offset_right=-8;panel.offset_top=20;panel.offset_bottom=480
	var box=VBoxContainer.new();box.add_theme_constant_override("separation",14);panel.add_child(box)
	_text(box,"摧毁敌方基地，赢下这场时代竞速。",20,PixelTheme.AMBER)
	var difficulty_row=HBoxContainer.new();difficulty_row.add_theme_constant_override("separation",7);box.add_child(difficulty_row)
	for option in store.db.rules["difficulty"]:
		var button=_button(difficulty_row,option["name"],func():difficulty=option["id"];for sibling in difficulty_row.get_children():sibling.modulate=Color.WHITE if sibling.get_meta("difficulty")==difficulty else Color(0.7,0.8,0.9))
		button.custom_minimum_size.x=111;button.set_meta("difficulty",option["id"]);button.modulate=Color.WHITE if option["id"]==difficulty else Color(0.7,0.8,0.9)
		button.tooltip_text="AI 金币：开局 ×%.2f，持续收入 ×%.2f"%[float(option.get("startingGoldMultiplier",1.0)),float(option.get("incomeMultiplier",1.0))]
	var play=_button(box,"开始对战",func():start_battle.emit({"mode":"standard","difficultyId":difficulty}),true);play.name="StartBattle";play.custom_minimum_size.y=69
	var saved=store.load_match()
	var continue_button=_button(box,"继续对局",func():resume_battle.emit());continue_button.name="ContinueBattle";continue_button.disabled=saved.is_empty()
	_button(box,"战役远征",func():page_requested.emit("campaign"))
	var hero=store.db.get_row("heroes",store.profile["loadout"]["heroId"])
	_text(box,"指挥官  "+hero["name"]+"  ·  "+store.db.get_row("specializations",store.profile["loadout"]["specializationId"])["name"],15,PixelTheme.MUTED)
	_text(box,"胜场 %d  ·  战役 %d/20"%[int(store.profile["wins"]),store.profile["cleared"].size()],14,PixelTheme.MUTED)
func _campaign() -> void:
	var panel=_panel(body,"战役 · 完成前一关，推进远征路线");panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll=_scroll(panel)
	var grid=GridContainer.new();grid.columns=5;grid.add_theme_constant_override("h_separation",13);grid.add_theme_constant_override("v_separation",13);scroll.add_child(grid)
	for mission in store.db.rows["missions"]:
		var cell=VBoxContainer.new();cell.custom_minimum_size.x=224;cell.add_theme_constant_override("separation",5);grid.add_child(cell)
		var card=PixelCard.new();card.paper=true;card.gold=bool(mission["boss"]);card.title=mission["id"].trim_prefix("M")+" · "+mission["name"];card.art_path="res://assets/ui/units/U%d1.png"%(store.db.era_index(mission["maximumEraId"])+1);card.value=EpochData.ROMAN[store.db.era_index(mission["startingEraId"])]+" → "+EpochData.ROMAN[store.db.era_index(mission["maximumEraId"])];card.value_icon="evolve";card.custom_minimum_size=Vector2(224,137);card.locked=not store.mission_unlocked(mission["id"]);card.disabled=card.locked;card.selected=store.profile["cleared"].has(mission["id"]);card.tooltip_text=mission["teaching"];cell.add_child(card)
		card.pressed.connect(func():_mission_brief(mission))
		_text(cell,"已通关" if card.selected else ("首领战" if mission["boss"] else "远征 · 第%d章"%int(mission["chapter"])),12,PixelTheme.GREEN if card.selected else PixelTheme.MUTED)
func _mission_brief(mission: Dictionary) -> void:
	for child in body.get_children():child.queue_free()
	var panel=_panel(body,"远征任务");panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER);panel.offset_left=-405;panel.offset_right=405;panel.offset_top=-218;panel.offset_bottom=218
	var box=VBoxContainer.new();box.add_theme_constant_override("separation",17);panel.add_child(box)
	_text(box,mission["name"],32,PixelTheme.AMBER)
	_text(box,mission["teaching"],19)
	var profile=store.db.get_row("enemy-profiles",mission["enemyProfileId"])
	_text(box,"敌军  "+profile["name"]+" · 指挥官 "+store.db.get_row("heroes",profile["heroId"])["name"],18,PixelTheme.RED)
	_text(box,"%s → %s · %d 波增援 · 摧毁基地获胜"%[store.db.era(mission["startingEraId"])["name"],store.db.era(mission["maximumEraId"])["name"],int(mission["reinforcements"]["waves"])],17,PixelTheme.MUTED)
	_button(box,"出征",func():start_battle.emit({"mode":"campaign","missionId":mission["id"],"difficultyId":difficulty}),true)
	_button(box,"返回路线",func():page_requested.emit("campaign"))
func _loadout() -> void:
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",12);body.add_child(row);row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hero_panel=_panel(row,"指挥官");hero_panel.custom_minimum_size.x=283
	var hero_box=VBoxContainer.new();hero_box.add_theme_constant_override("separation",9);hero_panel.add_child(hero_box)
	var hero_grid=GridContainer.new();hero_grid.columns=2;hero_grid.add_theme_constant_override("h_separation",7);hero_grid.add_theme_constant_override("v_separation",9);hero_box.add_child(hero_grid)
	var loadout=store.profile["loadout"]
	for hero in store.db.rows["heroes"]:
		var card=PixelCard.new();card.art_path="res://assets/ui/heroes/"+hero["id"]+"-A1.png";card.title=hero["name"];card.custom_minimum_size=Vector2(124,132);card.locked=not store.profile["unlocked_heroes"].has(hero["id"]);card.disabled=card.locked;card.selected=loadout["heroId"]==hero["id"];card.tooltip_text=hero.get("identity",hero.get("description",hero["name"]))+"\n"+("完成战役 "+str(hero.get("unlockMissionId",""))+" 解锁" if card.locked else "点击装备指挥官；战斗中随时代换装");hero_grid.add_child(card)
		card.pressed.connect(func():store.profile["loadout"]=store.db.default_loadout(hero["id"]);store.profile["loadout"]["relicIds"]=loadout["relicIds"].duplicate();store.profile["loadout"]["talentIds"]=loadout["talentIds"].duplicate();_save_refresh())
	var skills_panel=_panel(row,"专精与技能");skills_panel.custom_minimum_size.x=408;skills_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var skill_box=VBoxContainer.new();skill_box.add_theme_constant_override("separation",12);skills_panel.add_child(skill_box)
	var selected_hero=store.db.get_row("heroes",loadout["heroId"])
	_text(skill_box,selected_hero["name"]+" · "+store.db.get_row("skills",selected_hero["signatureSkillId"])["name"],23,PixelTheme.AMBER)
	var specs=HBoxContainer.new();specs.add_theme_constant_override("separation",7);skill_box.add_child(specs)
	for id in selected_hero["specializationIds"]:
		var spec=store.db.get_row("specializations",id);var button=_button(specs,spec["name"],func():loadout["specializationId"]=id;_save_refresh());button.custom_minimum_size.x=117;button.tooltip_text=spec["description"];button.modulate=PixelTheme.AMBER if loadout["specializationId"]==id else Color.WHITE
	_text(skill_box,store.db.get_row("specializations",loadout["specializationId"])["description"],15,PixelTheme.MUTED)
	_text(skill_box,"通用技能 · 点击换装，装备两项",16)
	var skills=GridContainer.new();skills.columns=4;skills.add_theme_constant_override("h_separation",6);skills.add_theme_constant_override("v_separation",8);skill_box.add_child(skills)
	for skill in store.db.rows["skills"].filter(func(s):return s["category"]=="common"):
		var card=PixelCard.new();card.compact=true;card.title=skill["name"];card.art_path="res://assets/ui/skills/"+skill["id"]+".png";card.custom_minimum_size=Vector2(91,81);card.selected=loadout["commonSkillIds"].has(skill["id"]);card.tooltip_text=skill["description"];skills.add_child(card)
		card.pressed.connect(func():_toggle_slot("commonSkillIds",skill["id"],2,false))
	var gear_panel=_panel(row,"遗物与天赋");gear_panel.custom_minimum_size.x=455
	var gear=VBoxContainer.new();gear.add_theme_constant_override("separation",10);gear_panel.add_child(gear)
	_text(gear,"遗物 · 装备两项",16)
	var relic_grid=GridContainer.new();relic_grid.columns=6;relic_grid.add_theme_constant_override("h_separation",5);relic_grid.add_theme_constant_override("v_separation",7);gear.add_child(relic_grid)
	for relic in store.db.rows["relics"]:
		var card=PixelCard.new();card.compact=true;card.art_path="res://assets/ui/relics/"+relic["id"]+".png";card.custom_minimum_size=Vector2(66,70);card.locked=not store.profile["relics"].has(relic["id"]);card.selected=loadout["relicIds"].has(relic["id"]);card.tooltip_text=relic["name"]+"\n"+relic["description"]+("\n可用4碎片打造" if card.locked else "");relic_grid.add_child(card)
		card.pressed.connect(func():
			if not store.profile["relics"].has(relic["id"]):
				if int(store.profile["fragments"])<4:message.text="碎片不足 · 战役胜利与重复遗物获得";return
				store.profile["fragments"]=int(store.profile["fragments"])-4;store.profile["relics"].append(relic["id"])
			_toggle_slot("relicIds",relic["id"],2,true))
	_text(gear,"天赋 · %d/%d 掌握点"%[loadout["talentIds"].size(),int(store.profile["mastery"])],16,PixelTheme.AMBER)
	var talent_grid=GridContainer.new();talent_grid.columns=6;talent_grid.add_theme_constant_override("h_separation",5);talent_grid.add_theme_constant_override("v_separation",7);gear.add_child(talent_grid)
	for talent in store.db.rows["talents"]:
		var card=PixelCard.new();card.compact=true;card.icon_id={"先锋":"sword","守城":"shield","远征":"research"}[talent["branch"]];card.title=talent["name"];card.custom_minimum_size=Vector2(66,71);card.selected=loadout["talentIds"].has(talent["id"]);card.tooltip_text=talent["description"]+"\n第%d阶 · 已用掌握点需达到%d"%[int(talent["tier"]),(int(talent["tier"])-1)*2];talent_grid.add_child(card)
		card.pressed.connect(func():
			var ids=loadout["talentIds"]
			if ids.has(talent["id"]):ids.erase(talent["id"])
			elif ids.size()>=int(store.profile["mastery"]) or store.db.fit_talents(ids+[talent["id"]],int(store.profile["mastery"])).size()!=ids.size()+1:message.text="掌握点不足，或需要同路线前层天赋";return
			else:ids.append(talent["id"])
			loadout["talentIds"]=store.db.fit_talents(ids,int(store.profile["mastery"]))
			_save_refresh())
	_text(gear,"碎片 %d · 战役首通增加掌握点并解锁指挥官"%int(store.profile["fragments"]),13,PixelTheme.MUTED)
func _toggle_slot(key: String,id: String,maximum: int,allow_empty: bool) -> void:
	var ids=store.profile["loadout"][key]
	if ids.has(id):
		if allow_empty:ids.erase(id)
		else:message.text="保持两个技能；选择新技能即可替换最早的一项";return
	else:
		if ids.size()>=maximum:ids.pop_front()
		ids.append(id)
	_save_refresh()
func _save_refresh() -> void:
	store.save_profile();audio.sfx("ui_confirm",0.5);page_requested.emit(page)
func _encyclopedia() -> void:
	var panel=_panel(body,"兵种图鉴 · 前排 · 远程 · 破甲 · 重型 · 支援");panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box=VBoxContainer.new();box.add_theme_constant_override("separation",14);panel.add_child(box)
	var tabs=GridContainer.new();tabs.columns=5;tabs.add_theme_constant_override("h_separation",8);tabs.add_theme_constant_override("v_separation",5);box.add_child(tabs)
	var practice_row=HBoxContainer.new();practice_row.add_theme_constant_override("separation",9);box.add_child(practice_row)
	var practice=PixelTheme.icon_button("sword","以所选时代开始自由演练");practice.size_flags_vertical=Control.SIZE_SHRINK_CENTER;practice_row.add_child(practice)
	practice.pressed.connect(func():start_battle.emit({"mode":"standard","startingEraId":encyclopedia_era,"difficultyId":difficulty}))
	var instruction=_text(practice_row,"点击交叉剑，按所选时代开始同代演练。",15,PixelTheme.MUTED)
	instruction.size_flags_horizontal=Control.SIZE_EXPAND_FILL;instruction.custom_minimum_size.x=400
	var details=VBoxContainer.new();details.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(details)
	for era in store.db.rows["eras"]:
		var button=_button(tabs,era["name"],func():encyclopedia_era=era["id"];_encyclopedia_cards(details));button.custom_minimum_size.x=225
	_encyclopedia_cards(details)
func _encyclopedia_cards(parent: Control) -> void:
	for child in parent.get_children():parent.remove_child(child);child.queue_free()
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",13);parent.add_child(row)
	for unit in store.db.unit_slots(encyclopedia_era):
		var panel=_panel(row);panel.custom_minimum_size.x=221;var box=VBoxContainer.new();box.add_theme_constant_override("separation",13);panel.add_child(box)
		var art=TextureRect.new();art.texture=PixelTheme.texture("res://assets/ui/units/"+unit["id"]+".png");art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.custom_minimum_size.y=140;box.add_child(art)
		_text(box,unit["name"],22,PixelTheme.AMBER)
		var multiplier=float(store.db.era(encyclopedia_era)["hpAttackMultiplier"])
		_text(box,"%s\n生命 %s · 攻击 %s\n射程 %d · 攻速 %.1fs"%[EpochData.ROLES.get(unit["role"],"特种"),PixelTheme.number(float(unit["hpBase"])*store.db.hp_multiplier(encyclopedia_era)),PixelTheme.number(float(unit["attackBase"])*store.db.attack_multiplier(encyclopedia_era)),int(unit["range"]),float(unit["attackPeriodSec"])],15)
		_text(box,unit.get("special",{}).get("auraLabel","需研究开放重型军团" if unit["heavy"] else "盾兵挡住战线，远程在后排输出"),14,PixelTheme.MUTED)
func _settings() -> void:
	var panel=_panel(body,"设置");panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER);panel.offset_left=-390;panel.offset_right=390;panel.offset_top=-244;panel.offset_bottom=244
	var box=VBoxContainer.new();box.add_theme_constant_override("separation",9);panel.add_child(box)
	AudioSettings.add_rows(box,store,audio)
	var toggles=GridContainer.new();toggles.columns=2;toggles.add_theme_constant_override("h_separation",25);box.add_child(toggles)
	for entry in [["music","背景音乐"],["sfx","攻击与界面音效"],["reduced_motion","降低镜头动态"],["fullscreen","全屏显示"]]:
		var checkbox=CheckButton.new();checkbox.text=entry[1];checkbox.button_pressed=store.settings[entry[0]];checkbox.custom_minimum_size=Vector2(330,43);toggles.add_child(checkbox)
		checkbox.toggled.connect(func(value):store.settings[entry[0]]=value;_save_settings();if entry[0]=="fullscreen":DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED))
	_text(box,"键盘 1–5 招募 · Q 指挥官 · E 进化 · Esc 暂停\n鼠标 / 触屏选择技能后，点战场落点；暂停后可保留对局返回。",15,PixelTheme.MUTED)
func _save_settings() -> void:store.save_settings();audio.apply_settings()
