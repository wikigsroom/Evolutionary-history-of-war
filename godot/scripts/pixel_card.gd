class_name PixelCard
extends Button

var title = ""
var icon_id = ""
var art_path = ""
var value = ""
var value_icon = "gold"
var hint = ""
var compact = false
var paper = false
var gold = false
var locked = false
var selected = false
var progress = -1.0
var cooldown = 0.0
var charges = -1
var hotkey = ""
var active_progress = -1.0

func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	PixelTheme.apply_button(self, PixelTheme.AMBER if gold else PixelTheme.CYAN, compact)
	if paper:
		add_theme_stylebox_override("normal", PixelTheme.frame("paper"))
		add_theme_stylebox_override("hover", PixelTheme.frame("paper-hover"))
		add_theme_stylebox_override("disabled", PixelTheme.frame("paper"))

func _draw() -> void:
	if selected: draw_style_box(PixelTheme.frame("hover"), Rect2(Vector2.ZERO, size))
	var pressed_offset = Vector2(0, 2) if is_pressed() else Vector2.ZERO
	var ink = PixelTheme.PAPER_INK if paper else PixelTheme.INK
	var image = PixelTheme.texture(art_path) if not art_path.is_empty() else PixelTheme.icon(icon_id)
	var picture = Rect2(8, 8, size.x - 16, size.y - 16)
	if compact and not title.is_empty(): picture = Rect2(8, 6, size.x - 16, size.y - 29)
	if not compact:
		picture = Rect2(9, 22, size.x - 18, maxf(20.0, size.y - 65))
	if image:
		var ratio = minf(picture.size.x / image.get_width(), picture.size.y / image.get_height())
		var dims = image.get_size() * ratio
		draw_texture_rect(image, Rect2(picture.position + (picture.size - dims) / 2.0 + pressed_offset, dims), false, Color(0.6, 0.6, 0.6, 0.75) if locked else Color.WHITE)
	if not title.is_empty():
		var y = size.y - 12 if compact else 19.0
		draw_string(PixelTheme.font(), Vector2(8, y) + pressed_offset, title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 13 if compact else 15, ink)
	if not value.is_empty():
		var width = PixelTheme.font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var start = (size.x - width - 20.0) / 2.0
		var coin = PixelTheme.icon(value_icon)
		if coin: draw_texture_rect(coin, Rect2(start - 2, size.y - 32, 21, 21), false)
		draw_string(PixelTheme.font(), Vector2(start + 21, size.y - 14), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ink)
	if not hotkey.is_empty(): draw_string(PixelTheme.font(), Vector2(9, size.y - 8), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink.darkened(0.2))
	if charges >= 0:
		draw_style_box(PixelTheme.frame("red", 0), Rect2(size.x - 28, 5, 24, 24))
		draw_string(PixelTheme.font(), Vector2(size.x - 25, 22), str(charges), HORIZONTAL_ALIGNMENT_CENTER, 18, 14, PixelTheme.INK)
	if progress >= 0.0:
		draw_rect(Rect2(8, size.y - 8, size.x - 16, 4), Color("#3c4e60"))
		draw_rect(Rect2(8, size.y - 8, (size.x - 16) * clampf(progress, 0.0, 1.0), 4), PixelTheme.AMBER if gold else PixelTheme.CYAN)
	if cooldown > 0.0:
		draw_rect(Rect2(6, 6, size.x - 12, size.y - 12), Color(0.02, 0.05, 0.1, 0.63))
		draw_string(PixelTheme.font(), Vector2(8, size.y * 0.58), str(ceili(cooldown)), HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 23, PixelTheme.INK)
	if locked:
		draw_rect(Rect2(6, 6, size.x - 12, size.y - 12), Color(0.05, 0.09, 0.14, 0.55))
		var lock = PixelTheme.icon("lock")
		if lock: draw_texture_rect(lock, Rect2((size.x - 35) / 2, (size.y - 40) / 2, 35, 35), false)
	if active_progress >= 0.0:
		draw_rect(Rect2(8,size.y-19,size.x-16,5),PixelTheme.NAVY)
		draw_rect(Rect2(8,size.y-19,(size.x-16)*clampf(active_progress,0,1),5),PixelTheme.GREEN)

func update_visual() -> void: queue_redraw()
