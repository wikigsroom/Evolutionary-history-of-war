class_name OnlineMenu
extends Control

signal build_requested
signal resume_requested

var client: EpochNetClient
var status_label: Label
var activity_host: VBoxContainer
var server_input: LineEdit
var code_input: LineEdit
var connect_button: Button
var action_buttons = []
var activity_signature = ""
var wait_label: Label
var clock_label: Label
var build_button: Button
var connection_panel: PixelPanel
var privacy_button: LinkButton

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var connection = PixelPanel.new(); connection.heading = "联机对战 · 官方服务器" if client.endpoint == EpochNetClient.DEFAULT_ENDPOINT else "联机对战 · 自定义服务器"; add_child(connection)
	connection_panel = connection
	connection.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); connection.offset_bottom = 85
	var connection_row = HBoxContainer.new(); connection_row.add_theme_constant_override("separation", 12); connection.add_child(connection_row)
	var icon = TextureRect.new(); icon.texture = PixelTheme.icon("ally"); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.custom_minimum_size = Vector2(42,42); connection_row.add_child(icon)
	server_input = LineEdit.new(); server_input.name = "OnlineServerAddress"; server_input.placeholder_text = "https://你的对战服务器"; server_input.text = client.endpoint; server_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; server_input.custom_minimum_size.y = 40; connection_row.add_child(server_input)
	connect_button = _button(connection_row, "连接", "ally", func(): if client.set_endpoint(server_input.text): client.connect_service())
	connect_button.tooltip_text = "连接所选服务器会创建匿名对战身份，并传输构筑与对战指令；单机存档留在本机。"
	status_label = PixelTheme.label(client.status, 14, PixelTheme.MUTED); status_label.custom_minimum_size.x = 270; status_label.clip_text = true; status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; connection_row.add_child(status_label)
	var content = HBoxContainer.new(); content.add_theme_constant_override("separation", 16); add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); content.offset_top = 99
	var entry = PixelPanel.new(); entry.heading = "找人对战"; entry.custom_minimum_size.x = 322; content.add_child(entry)
	var choices = VBoxContainer.new(); choices.add_theme_constant_override("separation", 8); entry.add_child(choices)
	var quick = PixelCard.new(); quick.name = "QueueMatch"; quick.title = "自由匹配"; quick.icon_id = "sword"; quick.gold = true; quick.custom_minimum_size = Vector2(292,82); quick.tooltip_text = "寻找使用相同版本的真实玩家"; choices.add_child(quick); quick.pressed.connect(func():client.queue_match()); action_buttons.append(quick)
	choices.add_child(PixelTheme.label("六位房间码", 18, PixelTheme.AMBER))
	code_input = LineEdit.new(); code_input.name = "RoomCodeInput"; code_input.placeholder_text = "042731"; code_input.max_length = 6; code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER; code_input.add_theme_font_size_override("font_size", 30); code_input.custom_minimum_size.y = 56; choices.add_child(code_input)
	code_input.text_changed.connect(func(text):
		var clean = ""
		for character in text:
			if character >= "0" and character <= "9": clean += character
		if clean != text: code_input.text = clean; code_input.caret_column = clean.length())
	var join = _button(choices, "创建 / 加入", "ally", func():client.join_code(code_input.text)); join.name = "JoinRoomCode"; action_buttons.append(join)
	var help = PixelTheme.label("双方输入相同数字\n第一位建房，第二位加入", 15, PixelTheme.MUTED); help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; choices.add_child(help)
	var build = _button(choices, "联机构筑", "crown", func():build_requested.emit()); build.name = "OnlineLoadout"
	build_button = build
	build.tooltip_text = "六位指挥官、六点天赋；双方相同经济与时代规则"
	var privacy = LinkButton.new(); privacy.text = "隐私说明 · 匿名身份用于联机"; privacy.custom_minimum_size.y = 28; privacy.add_theme_font_size_override("font_size", 13); choices.add_child(privacy)
	privacy_button = privacy
	server_input.text_changed.connect(_address_notice)
	_address_notice(server_input.text)
	privacy.tooltip_text = "联网仅用于你选择的对战服务器；离线进度不会上传。"
	privacy.pressed.connect(func():OS.shell_open("https://jyqx.sidcloud.cn"))
	var panel = PixelPanel.new(); panel.heading = "对战大厅"; panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; content.add_child(panel)
	activity_host = VBoxContainer.new(); activity_host.add_theme_constant_override("separation", 10); panel.add_child(activity_host)
	client.status_changed.connect(_status)
	client.activity_changed.connect(_refresh)
	_refresh()
	# First-time networking starts only after the player's explicit connect action.

func _button(parent: Node, title: String, icon_id: String, callback: Callable) -> Button:
	var button = Button.new(); button.text = title; button.icon = PixelTheme.icon(icon_id); button.expand_icon = true; button.add_theme_constant_override("icon_max_width", 24); button.custom_minimum_size.y = 48; PixelTheme.apply_button(button, PixelTheme.CYAN, true); parent.add_child(button); button.pressed.connect(callback); return button

func _status() -> void: status_label.text = client.status

func _address_notice(address: String) -> void:
	var official = address.strip_edges().trim_suffix("/") == EpochNetClient.DEFAULT_ENDPOINT
	connection_panel.heading = "联机对战 · 官方服务器" if official else "联机对战 · 自定义服务器"
	connect_button.text = "同意并连接" if official else "连接"
	connect_button.tooltip_text = "同意将随机匿名身份、必要网络信息及对战数据发送至 SIDcloud 的新加坡服务器，用于匹配、战斗与断线恢复。可先阅读隐私说明；单机进度留在本机。" if official else "连接所选服务器会创建匿名对战身份，并传输构筑与对战指令；请确认其运营者和隐私规则。"
	privacy_button.text = "隐私说明 · 官方数据存于新加坡" if official else "隐私说明 · 请确认服务器运营者"

func _refresh() -> void:
	if activity_host == null: return
	var state = client.activity.duplicate(true); state.erase("wait_seconds")
	var signature = JSON.stringify(state, "", true)
	if activity_signature == signature: return
	activity_signature = signature
	for child in activity_host.get_children(): activity_host.remove_child(child); child.queue_free()
	wait_label = null; clock_label = null
	match client.activity.get("kind", ""):
		"queue":
			_title("正在寻找对手", "target"); wait_label = _label("", 26, PixelTheme.AMBER)
			_label("匹配只寻找真实玩家。", 16)
			_button(activity_host, "取消匹配", "back", func():client.cancel_queue())
		"room": _room(client.activity.get("room", {}))
		"match":
			if client.activity.get("phase") == "FINISHED":
				_title("对战已结束", "crown")
				var result = client.activity.get("result", {})
				var winner = int(result.get("winner", -1)); var seat = int(client.activity.get("seat", 0))
				_label("胜利" if winner == seat else ("平局" if winner == 2 else ("本局已关闭" if winner < 0 else "重整军旗")), 38, PixelTheme.AMBER)
				_button(activity_host, "返回大厅 · 新的对战", "sword", func():client.acknowledge_result())
			else:
				_title("你的原对局仍在进行", "ally"); _label("重连保留原席位、军队和时代。", 18)
				_button(activity_host, "返回对战", "sword", func():resume_requested.emit())
		_:
			_title("旗帜集结，时代竞速", "crown")
			var art = TextureRect.new(); art.texture = PixelTheme.texture("res://assets/ui/heroes/" + String(client.loadout.get("heroId","H03")) + "-A1.png"); art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; art.custom_minimum_size.y = 210; activity_host.add_child(art)
			_label("自由匹配，或与朋友输入同一个六位码。", 19)
			_label("双方准备后开战 · 各自决定何时进化\n连接中断时自动回到原局，未执行的旧点击不会补发。", 15, PixelTheme.MUTED)

func _title(text: String, icon_id: String) -> void:
	var row = HBoxContainer.new(); row.add_theme_constant_override("separation", 13); activity_host.add_child(row)
	var icon = TextureRect.new(); icon.texture = PixelTheme.icon(icon_id); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.custom_minimum_size = Vector2(48,48); row.add_child(icon)
	var title = PixelTheme.label(text, 27, PixelTheme.AMBER); title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; row.add_child(title)

func _label(text: String, size_: int, color: Color = PixelTheme.INK) -> Label:
	var label = PixelTheme.label(text, size_, color); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; activity_host.add_child(label); return label

func _room(room: Dictionary) -> void:
	var offer = room.get("phase") == "OFFER"
	_title("已找到对手" if offer else "房间  " + String(room.get("code", "")), "sword" if offer else "ally")
	var roster = HBoxContainer.new(); roster.add_theme_constant_override("separation", 18); activity_host.add_child(roster)
	var own_ready = false
	for seat in range(2):
		var member = {}
		for row in room.get("roster", []):
			if int(row["seat"]) == seat: member = row
		var column = VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; roster.add_child(column)
		var card = PixelCard.new(); card.custom_minimum_size = Vector2(230,150); column.add_child(card)
		if member.is_empty(): card.icon_id = "population"; card.title = "等待加入"; card.disabled = true
		else:
			card.art_path = "res://assets/ui/heroes/" + String(member["loadout"]["heroId"]) + "-A1.png"; card.title = "你" if member["is_you"] else "对手"; card.selected = bool(member["ready"])
			if member["is_you"]: own_ready = bool(member["ready"])
		var label = PixelTheme.label("已准备" if member.get("ready", false) else ("空席位" if member.is_empty() else "未准备"), 16, PixelTheme.GREEN if member.get("ready", false) else PixelTheme.MUTED); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; column.add_child(label)
	clock_label = _label("", 14, PixelTheme.MUTED)
	if offer:
		_button(activity_host, "接受对战", "sword", func():client.accept_offer(true)).disabled = own_ready
		_button(activity_host, "拒绝", "back", func():client.accept_offer(false))
	else:
		_button(activity_host, "取消准备" if own_ready else "准备出战", "sword", func():client.room_ready(not own_ready))
		_button(activity_host, "离开房间", "back", func():client.leave_room())
	_label("构筑变更会取消双方准备。", 13, PixelTheme.MUTED)

func _process(_delta: float) -> void:
	connect_button.disabled = client.busy
	build_button.disabled = client.busy or client.activity.get("kind", "") in ["queue", "match"] or client.activity.get("room",{}).get("phase") == "OFFER"
	for button in action_buttons: button.disabled = not client.authenticated or client.busy or client.activity.get("kind", "") != ""
	if is_instance_valid(wait_label):
		var wait = int(client.activity.get("wait_seconds", 0)); wait_label.text = "%02d:%02d" % [wait/60, wait%60]
		if wait >= 75: wait_label.text += " · 暂无对手，可继续等待"
	if is_instance_valid(clock_label):
		var seconds = maxi(0, ceili(float(client.activity.get("room", {}).get("expires_at_ms", 0))/1000.0 - Time.get_unix_time_from_system()))
		clock_label.text = "等待剩余 %d 秒" % seconds
