class_name SafeUI
extends Control
## Background/world stays full-screen; only interactive UI respects physical insets.
var test_insets = Vector4.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh_layout()

static func fit_rect(area: Rect2) -> Dictionary:
	var factor = minf(1.0, minf(area.size.x / 1280.0, area.size.y / 720.0))
	factor = maxf(factor, 0.01)
	return {"position": area.position, "size": area.size / factor, "scale": Vector2.ONE * factor}

static func physical_to_logical(physical: Rect2, screen_transform: Transform2D, viewport_rect: Rect2) -> Rect2:
	return viewport_rect.intersection(screen_transform.affine_inverse() * physical)

func _process(_delta: float) -> void:
	refresh_layout()

func refresh_layout() -> void:
	var area = get_viewport().get_visible_rect()
	if OS.has_feature("android"):
		var physical = DisplayServer.get_display_safe_area()
		if physical.size.x > 0 and physical.size.y > 0:
			area = physical_to_logical(Rect2(physical), get_viewport().get_screen_transform(), area)
	area.position += Vector2(test_insets.x, test_insets.y)
	area.size -= Vector2(test_insets.x + test_insets.z, test_insets.y + test_insets.w)
	if area.size.x <= 0 or area.size.y <= 0: return
	var layout = fit_rect(area)
	position = layout.position
	scale = layout.scale
	size = layout.size
