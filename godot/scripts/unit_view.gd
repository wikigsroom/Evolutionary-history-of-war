class_name UnitView
extends Node2D

var actor = {}
var metadata = {}
var model
var sprite: Sprite2D
var player: AnimationPlayer
var light: ShaderMaterial
var last_hit = -100
var visual_scale = 1.0
var ui_scale = 0.8
var current_visual = ""

func configure(simulation, entity: Dictionary, scale_factor: float) -> void:
	model = simulation; actor = entity; ui_scale = scale_factor
	current_visual = String(actor.get("visualId", model.db.visual_id(actor["contentId"], actor["eraId"])))
	metadata = model.db.animations.get(current_visual, model.db.animations.get(actor["contentId"], model.db.animations.get("U44", {})))
	if sprite == null:
		sprite = Sprite2D.new(); sprite.name = "Actor"; add_child(sprite)
		var shader = preload("res://assets/shaders/unit_flash.gdshader")
		light = ShaderMaterial.new(); light.shader = shader; sprite.material = light
		player = AnimationPlayer.new(); player.name = "Timeline"; add_child(player)
		var library = AnimationLibrary.new()
		var animation = Animation.new(); animation.length = 0.16
		var track = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, NodePath("Actor:material:shader_parameter/flash"))
		animation.track_insert_key(track, 0.0, 0.78); animation.track_insert_key(track, 0.05, 0.4); animation.track_insert_key(track, 0.16, 0.0)
		library.add_animation("hit", animation); player.add_animation_library("", library)
	var path = metadata["path"] if actor["side"] == 0 else metadata["enemyPath"]
	sprite.texture = PixelTheme.texture("res://assets/" + path)
	sprite.hframes = int(metadata.get("columns", 6)); sprite.vframes = int(metadata.get("rows", 5)); sprite.centered = false
	var height = float(model.db.profile(current_visual)["height"]) * ui_scale
	visual_scale = height / float(metadata["bodyHeight"])
	sprite.scale = Vector2.ONE * visual_scale
	_place_sprite(Vector2.ZERO)
	z_index = 12 if actor["kind"] == "hero" else 10
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func refresh(ground: float, reduced_motion: bool, time_override: float = -1.0) -> void:
	if current_visual != String(actor.get("visualId", model.db.visual_id(actor["contentId"], actor["eraId"]))): configure(model, actor, ui_scale)
	var phase = String(actor["phase"])
	var time = float(model.tick) + model.interpolation if time_override < 0.0 else time_override + model.interpolation
	position = Vector2(lerpf(float(actor["previousX"]), float(actor["x"]), model.interpolation) * ui_scale, ground)
	var frame = 0
	var offset = Vector2.ZERO
	var profile = model.db.profile(current_visual)
	if phase == "dead":
		frame = 24 + clampi(int((time - float(actor["deathAt"])) / 4.0), 0, 5)
		modulate.a = clampf(1.0 - maxf(0.0, time - float(actor["deathAt"]) - 16.0) / 14.0, 0.0, 1.0)
	elif phase == "windup":
		var progress = clampf((time - float(actor["attackStartedAt"])) / maxf(1.0, float(actor["windup"])), 0.0, 1.0)
		frame = 12 + mini(2, int(progress * 3.0))
		if not reduced_motion: offset.x = -(1.0 if actor["side"] == 0 else -1.0) * sin(progress * PI) * 2.0
	elif phase == "charge":
		frame = 14 + int(time / 3.0) % 3
	elif phase == "recover":
		frame = 14 + clampi(int((time - float(actor["releasedAt"])) / 3.0), 0, 3)
	elif phase == "walk":
		var stride = 28.0 if profile["family"] not in ["mounted", "cannon", "mech"] else 52.0
		frame = 6 + int(float(actor["runDistance"]) / stride * 6.0) % 6
		if not reduced_motion and profile["family"] not in ["cannon", "mech"]: offset.y = -absf(sin(float(frame - 6) / 6.0 * TAU)) * 1.7
	else: frame = int((time - float(actor["bornTick"])) / 8.0) % 6
	if phase != "dead" and time - float(actor["hitAt"]) < 6.0:
		if phase not in ["windup", "recover", "charge"]: frame = 18 + clampi(int(time - float(actor["hitAt"])), 0, 5)
		if not reduced_motion: offset.x += float(actor["hitDirection"]) * 2.0 * maxf(0.0, 1.0 - (time - float(actor["hitAt"])) / 6.0)
	if int(actor["hitAt"]) > last_hit:
		last_hit = int(actor["hitAt"])
		if last_hit > 0: player.play("hit")
	player.speed_scale = 0.0 if model.paused else 1.0
	if actor.has("yield"): offset.y -= 12.0
	_place_sprite(offset)
	sprite.frame = clampi(frame, 0, sprite.hframes * sprite.vframes - 1)
	visible = not actor.get("garrisoned", false)
	queue_redraw()

func _place_sprite(offset: Vector2) -> void:
	# Both palette atlases face right. Reflect the foot anchor along with the image.
	var facing = float(actor.get("facing", 1.0 if actor["side"] == 0 else -1.0))
	sprite.flip_h = facing < 0.0
	var anchor = metadata["anchor"]
	var foot_x = 1.0 - float(anchor[0]) if sprite.flip_h else float(anchor[0])
	sprite.position = -Vector2(float(metadata["frameWidth"]) * foot_x, float(metadata["frameHeight"]) * float(anchor[1])) * visual_scale + offset

func _draw() -> void:
	if actor.is_empty() or float(actor["hp"]) <= 0.0: return
	var radius = float(actor["radius"]) * ui_scale
	draw_ellipse_shadow(radius)
	var height = float(model.db.profile(current_visual)["height"]) * ui_scale
	var width = 47.0 if actor["kind"] == "hero" else 34.0
	var color = PixelTheme.CYAN if actor["side"] == 0 else PixelTheme.RED
	if actor["kind"] == "hero" or float(actor["hp"]) < float(actor["maxHp"]) or not actor["shields"].is_empty():
		draw_rect(Rect2(-width / 2.0 - 1, -height - 11, width + 2, 5), Color("#081020"))
		draw_rect(Rect2(-width / 2.0, -height - 10, width * float(actor["hp"]) / float(actor["maxHp"]), 3), color)
		var shield = 0.0
		for batch in actor["shields"]: shield += float(batch["hp"])
		if shield > 0.0:
			draw_rect(Rect2(-width / 2.0 - 1, -height - 15, width + 2, 4), Color("#081020"))
			draw_rect(Rect2(-width / 2.0, -height - 14, width * clampf(shield / (float(actor["maxHp"]) * float(model.db.rules["support"]["totalShieldCapRatio"])), 0.0, 1.0), 2), PixelTheme.AMBER)
	if actor["kind"] == "hero":
		draw_texture_rect(PixelTheme.icon("crown"), Rect2(-9, -height - 34, 18, 18), false)
	var status_x = -10.0
	for effect in actor["statuses"]:
		if effect["id"] == "item-drum":
			draw_texture_rect(PixelTheme.icon("drum"), Rect2(status_x, -height - 26, 14, 14), false); status_x += 15.0; continue
		if not String(effect["id"]).begins_with("ST") or effect["id"] == "ST08" and int(effect["until"]) - model.tick < 10: continue
		var texture = PixelTheme.texture("res://assets/ui/status/" + effect["id"] + ".png")
		if texture: draw_texture_rect(texture, Rect2(status_x, -height - 26, 12, 12), false); status_x += 13.0

func draw_ellipse_shadow(radius: float) -> void:
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1, 0.22))
	draw_circle(Vector2.ZERO, radius * 0.9, Color(0.01, 0.025, 0.05, 0.55))
	draw_set_transform(Vector2.ZERO)
