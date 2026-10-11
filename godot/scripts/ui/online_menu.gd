class_name OnlineMenu
extends Control

signal build_requested
signal resume_requested

var client: EpochNetClient
var status_label: Label
var status_icon: TextureRect
var activity_host: VBoxContainer
var code_input: LineEdit
var code_hint: Label
var join_button: Button
var action_buttons = []
var context_buttons = []
var activity_signature = ""
var wait_label: Label
var clock_label: Label
var build_button: Button
var privacy_button: Button
var db = EpochData.new()
var connection_signature = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_connection_bar(layout)
	var content = HBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(content)
	_entry_panel(content)
	var panel = PixelPanel.new()
	panel.heading = "对战大厅"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(panel)
	# Keep characters and actions together instead of stretching them across tablets.
	var center = CenterContainer.new()
	panel.add_child(center)
	activity_host = VBoxContainer.new()
	activity_host.custom_minimum_size.x = 648
	activity_host.add_theme_constant_override("separation", 12)
	center.add_child(activity_host)
	client.status_changed.connect(_status)
	client.activity_changed.connect(_refresh)
	_refresh()
	_status()
	client.request_connection()

func _connection_bar(parent: Node) -> void:
	var panel = PixelPanel.new()
	panel.padding = 8
	parent.add_child(panel)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	_icon(row, "ally", 32)
	var title = PixelTheme.label("联机对战", 22, PixelTheme.AMBER)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	status_icon = _icon(row, "check", 24)
	status_label = PixelTheme.label("", 16)
	status_label.custom_minimum_size.x = 256
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.clip_text = true
	row.add_child(status_label)
	privacy_button = _button(row, "隐私说明", "lock", func(): OS.shell_open("https://jyqx.sidcloud.cn"))
	privacy_button.name = "OnlinePrivacy"
	privacy_button.custom_minimum_size.x = 132
	privacy_button.tooltip_text = "SIDcloud 运营；联机数据在新加坡处理。进入本页自动连接，单机进度保留在本机。"

func _entry_panel(parent: Node) -> void:
	var panel = PixelPanel.new()
	panel.heading = "选择对战"
	panel.custom_minimum_size.x = 328
	parent.add_child(panel)
	var choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 12)
	panel.add_child(choices)
	var quick = _button(choices, "自由匹配", "sword", func(): client.queue_match(), true)
	quick.name = "QueueMatch"
	quick.custom_minimum_size.y = 72
	quick.add_theme_font_size_override("font_size", 22)
	quick.add_theme_constant_override("icon_max_width", 32)
	quick.tooltip_text = "寻找使用相同版本的真实玩家"
	action_buttons.append(quick)
	choices.add_child(PixelTheme.label("六位房间码", 18, PixelTheme.AMBER))
	code_input = LineEdit.new()
	code_input.name = "RoomCodeInput"
	code_input.placeholder_text = "输入 6 位数字"
	code_input.max_length = 6
	code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_input.custom_minimum_size.y = 56
	code_input.add_theme_font_size_override("font_size", 28)
	code_input.add_theme_color_override("font_color", PixelTheme.INK)
	code_input.add_theme_color_override("font_placeholder_color", PixelTheme.MUTED)
	code_input.add_theme_stylebox_override("normal", PixelTheme.frame("pressed", 10))
	code_input.add_theme_stylebox_override("read_only", PixelTheme.frame("disabled", 10))
	code_input.add_theme_stylebox_override("focus", _focus_frame())
	code_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	code_input.tooltip_text = "双方输入相同的六位数字；第一位建房，第二位加入。"
	choices.add_child(code_input)
	code_input.text_changed.connect(_code_changed)
	code_input.text_submitted.connect(func(_text): if not join_button.disabled: client.join_code(code_input.text))
	join_button = _button(choices, "创建 / 加入", "ally", func(): client.join_code(code_input.text))
	join_button.name = "JoinRoomCode"
	action_buttons.append(join_button)
	code_hint = PixelTheme.label("双方输入同一码，即可进入房间", 14, PixelTheme.MUTED)
	code_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choices.add_child(code_hint)
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.add_child(spacer)
	build_button = _button(choices, "联机构筑", "crown", func(): build_requested.emit())
	build_button.name = "OnlineLoadout"
	build_button.tooltip_text = "选择指挥官、天赋、技能与道具；在房间内更改构筑会取消准备。"
	var hint = PixelTheme.label("进入即连接 · 断开自动重连", 14, PixelTheme.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choices.add_child(hint)

func _code_changed(text: String) -> void:
	var clean = ""
	for character in text:
		if character >= "0" and character <= "9": clean += character
	if clean != text:
		code_input.text = clean
		code_input.caret_column = clean.length()
	code_hint.text = "还需输入 %d 位数字" % (6 - clean.length()) if clean.length() in range(1, 6) else "双方输入同一码，即可进入房间"

func _focus_frame() -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = PixelTheme.CYAN
	box.set_border_width_all(2)
	return box

func _button(parent: Node, title: String, icon_id: String, callback: Callable, gold: bool = false) -> Button:
	var button = Button.new()
	button.text = title
	button.icon = PixelTheme.icon(icon_id)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 24)
	button.add_theme_constant_override("h_separation", 10)
	button.custom_minimum_size.y = 52
	PixelTheme.apply_button(button, PixelTheme.AMBER if gold else PixelTheme.CYAN, true)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("focus", _focus_frame())
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _icon(parent: Node, id: String, extent: int) -> TextureRect:
	var image = TextureRect.new()
	image.texture = PixelTheme.icon(id)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(extent, extent)
	image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func _portrait(parent: Node, hero_id: String, extent: int) -> TextureRect:
	var path = "res://assets/ui/heroes/" + hero_id + "-A1.png"
	var cache_key = "online-portrait:" + path
	if not PixelTheme.cache.has(cache_key):
		var original = PixelTheme.texture(path)
		var image = original.get_image()
		var cropped = AtlasTexture.new()
		cropped.atlas = original
		# Trim transparent padding; keep every visible pixel and the original proportions.
		cropped.region = Rect2(image.get_used_rect().grow(2).intersection(Rect2i(Vector2i.ZERO, image.get_size())))
		PixelTheme.cache[cache_key] = cropped
	var portrait = TextureRect.new()
	portrait.name = "CommanderPortrait"
	portrait.texture = PixelTheme.cache[cache_key]
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2(extent, extent)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(portrait)
	return portrait

func _status() -> void:
	var text = client.status
	var connected = client.authenticated and client.service_state == "connected"
	if client.service_state == "retrying":
		text = "自动重连 · %d 秒后重试" % maxi(0, ceili(client.service_retry_at - Time.get_ticks_msec() / 1000.0)) if not client.authenticated else "连接中断 · 正在恢复原局"
	var signature = text + client.status + str(connected)
	if signature == connection_signature: return
	connection_signature = signature
	status_label.text = text
	status_icon.texture = PixelTheme.icon("check" if connected else "queue")
	status_icon.modulate = PixelTheme.GREEN if connected else PixelTheme.AMBER
	status_label.add_theme_color_override("font_color", PixelTheme.GREEN if connected else PixelTheme.AMBER)
	status_label.tooltip_text = client.status

func _refresh() -> void:
	if activity_host == null: return
	var state = client.activity.duplicate(true)
	state.erase("wait_seconds")
	if state.get("kind", "") == "": state["hero"] = client.loadout.get("heroId", "H03")
	var signature = JSON.stringify(state, "", true)
	if activity_signature == signature: return
	activity_signature = signature
	for child in activity_host.get_children():
		activity_host.remove_child(child)
		child.queue_free()
	context_buttons.clear()
	wait_label = null
	clock_label = null
	match client.activity.get("kind", ""):
		"queue":
			_title("正在寻找对手", "target")
			_icon(activity_host, "sword", 88).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			wait_label = _label("", 32, PixelTheme.AMBER)
			_label("匹配真实玩家，请稍候", 18)
			_context_action("取消匹配", "back", func(): client.cancel_queue())
		"room": _room(client.activity.get("room", {}))
		"match":
			if client.activity.get("phase") == "FINISHED":
				_title("对战已结束", "crown")
				_icon(activity_host, "crown", 88).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				var result = client.activity.get("result", {})
				var winner = int(result.get("winner", -1))
				var seat = int(client.activity.get("seat", 0))
				_label("胜利" if winner == seat else ("平局" if winner == 2 else ("本局已关闭" if winner < 0 else "重整军旗")), 38, PixelTheme.AMBER)
				_context_action("返回大厅", "back", func(): client.acknowledge_result())
			else:
				_title("原对局仍在进行", "ally")
				_label("席位、军队与时代均已保留", 18)
				_context_action("返回对战", "sword", func(): resume_requested.emit())
		_: _hall()

func _title(text: String, icon_id: String) -> void:
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	activity_host.add_child(row)
	_icon(row, icon_id, 40)
	var label = PixelTheme.label(text, 26, PixelTheme.AMBER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

func _label(text: String, extent: int, color: Color = PixelTheme.INK) -> Label:
	var label = PixelTheme.label(text, extent, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	activity_host.add_child(label)
	return label

func _hall() -> void:
	_title("军旗已备，等待出征", "crown")
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	activity_host.add_child(row)
	var portrait_panel = PixelPanel.new()
	portrait_panel.tone = "pressed"
	portrait_panel.padding = 12
	row.add_child(portrait_panel)
	var hero_id = String(client.loadout.get("heroId", "H03"))
	_portrait(portrait_panel, hero_id, 192)
	var details = VBoxContainer.new()
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details.add_theme_constant_override("separation", 12)
	row.add_child(details)
	details.add_child(PixelTheme.label("当前指挥官", 16, PixelTheme.MUTED))
	var hero = db.get_row("heroes", hero_id)
	details.add_child(PixelTheme.label(hero["name"] + " · " + hero["title"], 22, PixelTheme.AMBER))
	details.add_child(PixelTheme.label("自由匹配，迎战新的对手", 18))
	details.add_child(PixelTheme.label("同码入房，与好友一较高下", 18))
	var rules = HBoxContainer.new()
	rules.alignment = BoxContainer.ALIGNMENT_CENTER
	rules.add_theme_constant_override("separation", 20)
	activity_host.add_child(rules)
	for rule in [["gold", "公平起点"], ["evolve", "独立进化"], ["ally", "原局重连"]]:
		var item = HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		rules.add_child(item)
		_icon(item, rule[0], 24)
		var label = PixelTheme.label(rule[1], 16, PixelTheme.MUTED)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item.add_child(label)

func _context_action(title: String, icon_id: String, callback: Callable, gold: bool = false, locked: bool = false, parent: Node = null) -> Button:
	if parent == null:
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		activity_host.add_child(row)
		parent = row
	var button = _button(parent, title, icon_id, callback, gold)
	button.custom_minimum_size.x = 200
	context_buttons.append({"button":button, "locked":locked})
	return button

func _room(room: Dictionary) -> void:
	var offer = room.get("phase") == "OFFER"
	_title("已找到对手" if offer else "房间  " + String(room.get("code", "")), "sword" if offer else "ally")
	var roster = HBoxContainer.new()
	roster.name = "RoomRoster"
	roster.add_theme_constant_override("separation", 16)
	activity_host.add_child(roster)
	var own_ready = false
	for seat in range(2):
		if seat == 1:
			var versus = PixelTheme.label("VS", 24, PixelTheme.AMBER)
			versus.custom_minimum_size.x = 40
			versus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			versus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			roster.add_child(versus)
		var member = {}
		for entry in room.get("roster", []):
			if int(entry["seat"]) == seat: member = entry
		var panel = PixelPanel.new()
		panel.name = "RoomSeat%d" % seat
		panel.tone = "pressed"
		panel.padding = 12
		panel.custom_minimum_size.x = 232
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		roster.add_child(panel)
		var column = VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		panel.add_child(column)
		var ready = bool(member.get("ready", false))
		var heading = PixelTheme.label("等待加入" if member.is_empty() else ("你" if member["is_you"] else "对手"), 20, PixelTheme.CYAN if member.get("is_you", false) else PixelTheme.AMBER)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(heading)
		if member.is_empty():
			_icon(column, "population", 144).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		else:
			var hero_id = String(member["loadout"]["heroId"])
			_portrait(column, hero_id, 144)
			if member["is_you"]: own_ready = ready
		var label = PixelTheme.label("已准备" if ready else ("空席位" if member.is_empty() else "未准备"), 16, PixelTheme.GREEN if ready else PixelTheme.MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	clock_label = _label("", 14, PixelTheme.MUTED)
	var actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	activity_host.add_child(actions)
	if offer:
		_context_action("等待对手接受" if own_ready else "接受对战", "check", func(): client.accept_offer(true), true, own_ready, actions)
		_context_action("拒绝", "back", func(): client.accept_offer(false), false, false, actions)
	else:
		_context_action("取消准备" if own_ready else "准备出战", "check" if own_ready else "sword", func(): client.room_ready(not own_ready), not own_ready, false, actions)
		_context_action("离开房间", "back", func(): client.leave_room(), false, false, actions)
	_label("双方准备后开战 · 更改构筑需重新准备", 14, PixelTheme.MUTED)

func _process(_delta: float) -> void:
	var available = client.authenticated and client.service_state == "connected" and not client.busy
	var idle = client.activity.get("kind", "") == ""
	build_button.disabled = client.busy or client.activity.get("kind", "") in ["queue", "match"] or client.activity.get("room", {}).get("phase") == "OFFER"
	code_input.editable = idle and not client.busy
	for button in action_buttons:
		button.disabled = not available or not idle or (button == join_button and code_input.text.length() != 6)
	for entry in context_buttons:
		entry["button"].disabled = not available or entry["locked"]
	_status()
	if is_instance_valid(wait_label):
		var seconds = int(client.activity.get("wait_seconds", 0))
		wait_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]
		if seconds >= 75: wait_label.text += " · 可继续等待"
	if is_instance_valid(clock_label):
		var seconds = maxi(0, ceili(float(client.activity.get("room", {}).get("expires_at_ms", 0)) / 1000.0 - Time.get_unix_time_from_system()))
		clock_label.text = "等待剩余 %d 秒" % seconds
