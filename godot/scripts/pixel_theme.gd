class_name PixelTheme
extends RefCounted

const NAVY = Color("#071126")
const NAVY_2 = Color("#0d1d3b")
const PANEL = Color("#102139")
const PANEL_2 = Color("#19344e")
const INK = Color("#fff0ce")
const MUTED = Color("#8ca4be")
const CYAN = Color("#75dcf1")
const CYAN_DARK = Color("#315979")
const RED = Color("#f47579")
const RED_DARK = Color("#652d42")
const AMBER = Color("#ffd577")
const GREEN = Color("#89dba6")
const PURPLE = Color("#b49beb")
const PAPER_INK = Color("#493625")
static var cache = {}

static func number(value: float) -> String:
	if absf(value) >= 100000000.0: return "%.1f亿" % (value / 100000000.0)
	if absf(value) >= 10000.0: return "%.1f万" % (value / 10000.0)
	return str(floori(value))

static func texture(path: String) -> Texture2D:
	if not cache.has(path): cache[path] = load(path) if ResourceLoader.exists(path) else null
	return cache[path]

static func font() -> Font: return texture_font("resource-rounded")
static func texture_audio(path: String) -> AudioStream:
	if not cache.has(path): cache[path] = load(path) if ResourceLoader.exists(path) else null
	return cache[path]
static func display_font() -> Font: return texture_font("smiley")
static func texture_font(name: String) -> Font:
	var path = "res://assets/fonts/" + name + ".woff2"
	if not cache.has(path): cache[path] = load(path)
	return cache[path]

static func frame(tone: String = "navy", padding: float = 12.0) -> StyleBoxTexture:
	var box = StyleBoxTexture.new()
	box.texture = texture("res://assets/ui/pixel/frame-" + tone + ".png")
	for side in range(4):
		box.set_texture_margin(side, 18.0)
		box.set_content_margin(side, padding)
	return box

static func style(_bg: Color, _border: Color = Color.TRANSPARENT, _radius: int = 0, _width: int = 2) -> StyleBoxTexture:
	return frame("navy")

static func apply_panel(control: Control, _bg: Color = PANEL, _border: Color = CYAN_DARK, _radius: int = 0) -> void:
	control.add_theme_stylebox_override("panel", frame())

static func apply_button(button: Button, accent: Color = CYAN, compact: bool = false) -> void:
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", frame("gold" if accent == AMBER else "navy"))
	button.add_theme_stylebox_override("hover", frame("hover"))
	button.add_theme_stylebox_override("pressed", frame("pressed"))
	button.add_theme_stylebox_override("disabled", frame("disabled"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_font_size_override("font_size", 16 if compact else 18)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 48 if compact else 58)

static func label(text: String, size: int = 16, color: Color = INK) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0,0,0,0.35))
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

static func icon(kind: String) -> Texture2D:
	return texture("res://assets/ui/pixel/" + {"heavy":"sword", "arrow":"target"}.get(kind, kind) + ".png")

static func icon_button(kind: String, tooltip: String, accent: Color = CYAN) -> Button:
	var button = PixelCard.new()
	button.icon_id = kind
	button.tooltip_text = tooltip
	button.compact = true
	button.custom_minimum_size = Vector2(52, 52)
	apply_button(button, accent, true)
	return button

static func make_theme() -> Theme:
	var theme = Theme.new()
	theme.default_font = font()
	theme.default_font_size = 17
	theme.set_stylebox("panel", "PanelContainer", frame())
	theme.set_stylebox("panel", "TooltipPanel", frame("paper", 10))
	theme.set_color("font_color", "TooltipLabel", PAPER_INK)
	theme.set_font_size("font_size", "TooltipLabel", 16)
	theme.set_icon("checked", "CheckButton", texture("res://assets/ui/pixel/toggle-on.png"))
	theme.set_icon("unchecked", "CheckButton", texture("res://assets/ui/pixel/toggle-off.png"))
	theme.set_stylebox("slider", "HSlider", frame("pressed", 4))
	theme.set_stylebox("grabber_area", "HSlider", frame("gold", 4))
	theme.set_stylebox("scroll", "VScrollBar", frame("pressed", 3))
	theme.set_stylebox("grabber", "VScrollBar", frame("hover", 3))
	return theme
