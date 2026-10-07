class_name PixelPanel
extends PanelContainer
var heading = ""
var tone = "navy"
var padding = 14.0
func _ready() -> void:
	var box = PixelTheme.frame(tone, padding)
	if not heading.is_empty(): box.content_margin_top = 34.0
	add_theme_stylebox_override("panel", box)
func _draw() -> void:
	if heading.is_empty(): return
	var font = PixelTheme.font()
	var width = font.get_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 32
	draw_style_box(PixelTheme.frame("tab", 0), Rect2(12, -5, width, 31))
	draw_string(font, Vector2(28, 16), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PixelTheme.INK)
