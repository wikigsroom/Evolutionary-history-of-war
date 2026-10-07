class_name PixelIcon
extends TextureRect

## Scheme 1 icons are real pixel art from the approved HUD atlas.
## Procedural glyphs made the HUD look like a generic web UI, so every icon now
## comes from the same pixel-art source of truth.
var kind: String = "star":
	set(value):
		kind = value
		if is_inside_tree():
			_refresh()
var tint: Color = Color.WHITE

const ATLAS_PATH := "res://assets/ui/epoch-rush-pixel-hud-atlas.png"

func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate = Color.WHITE
	_refresh()

func _refresh() -> void:
	var atlas_image := load(ATLAS_PATH) as Texture2D
	if atlas_image == null:
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = atlas_image
	atlas.region = _region_for_kind(kind)
	texture = atlas

func _region_for_kind(value: String) -> Rect2:
	match value:
		"coin", "gold": return Rect2(328, 650, 310, 300)
		"xp": return Rect2(24, 330, 300, 300)
		"sword": return Rect2(320, 20, 305, 310)
		"shield": return Rect2(635, 20, 305, 325)
		"map": return Rect2(930, 900, 320, 350)
		"book": return Rect2(925, 20, 325, 315)
		"gear": return Rect2(320, 325, 315, 320)
		"tower": return Rect2(20, 900, 330, 350)
		"upgrade": return Rect2(625, 650, 325, 310)
		"items": return Rect2(625, 900, 325, 350)
		"pause": return Rect2(950, 325, 280, 300)
		"play": return Rect2(20, 640, 300, 280)
		"back": return Rect2(320, 900, 315, 350)
		"check": return Rect2(320, 20, 305, 310)
		"star": return Rect2(315, 640, 325, 315)
		"skull": return Rect2(0, 0, 300, 320)
		_: return Rect2(315, 640, 325, 315)

