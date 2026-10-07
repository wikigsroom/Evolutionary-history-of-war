class_name BaseView
extends Node2D
var model
var side = 0
var factor = 0.8
var castle: Sprite2D
var pulse: Node2D
var player: AnimationPlayer
var last_era = ""
var current_path = ""
var turret_nodes = {}
func _ready() -> void:
	pulse = Node2D.new(); pulse.name = "Pulse"; add_child(pulse)
	castle = Sprite2D.new(); castle.name = "Castle"; castle.centered = false; pulse.add_child(castle)
	player = AnimationPlayer.new(); player.name = "Timeline"; add_child(player)
	var library = AnimationLibrary.new()
	var evolve = Animation.new(); evolve.length = 0.85
	var track = evolve.add_track(Animation.TYPE_VALUE); evolve.track_set_path(track, NodePath("Pulse:scale"))
	evolve.track_insert_key(track, 0.0, Vector2(0.96, 0.92)); evolve.track_insert_key(track, 0.2, Vector2(1.035,1.04)); evolve.track_insert_key(track, 0.85, Vector2.ONE)
	track = evolve.add_track(Animation.TYPE_VALUE); evolve.track_set_path(track, NodePath("Pulse/Castle:modulate"))
	evolve.track_insert_key(track, 0.0, Color(1.8,1.6,1.1)); evolve.track_insert_key(track, 0.85, Color.WHITE)
	library.add_animation("evolve", evolve)
	var collapse = Animation.new(); collapse.length = 1.2
	track = collapse.add_track(Animation.TYPE_VALUE); collapse.track_set_path(track, NodePath("Pulse:rotation"))
	collapse.track_insert_key(track, 0.0, 0.0); collapse.track_insert_key(track, 0.2, 0.03 if side == 0 else -0.03); collapse.track_insert_key(track, 1.2, 0.0)
	library.add_animation("collapse", collapse); player.add_animation_library("", library)
	z_index = 3
func refresh(ground: float, reduced: bool) -> void:
	var entity = model.base(side)
	var era = String(entity["eraId"])
	var hp_ratio = float(entity["hp"]) / float(entity["maxHp"])
	var state = "-ruin" if hp_ratio <= 0.0 else ("-critical" if hp_ratio < 0.32 else ("-worn" if hp_ratio < 0.67 else ""))
	var path = "res://assets/base/" + era + state + ("-enemy" if side == 1 else "") + ".png"
	if path != current_path: castle.texture = PixelTheme.texture(path); current_path = path
	# Reused bases have a baked left-facing enemy texture; new ones only recolor it.
	# Apply exactly one mirror overall, including worn, critical and ruined states.
	castle.flip_h=side==1 and not bool(model.db.era(era).get("enemyBaseMirrored",false))
	if era != last_era and not last_era.is_empty() and not reduced: player.play("evolve")
	last_era = era
	if entity["phase"] == "dead" and not get_meta("collapsed", false): player.play("collapse"); set_meta("collapsed", true)
	position = Vector2(model.BASE_POSITIONS[side] * factor, ground + EpochData.BASE_FOOT_OFFSET * factor)
	var height = (320.0 + model.db.era_index(era) * 5.0) * factor
	var width = 325.0 * factor / 0.8
	if castle.texture:
		castle.scale = Vector2(width / castle.texture.get_width(), height / castle.texture.get_height())
		castle.position = Vector2(-width * (0.35 if side == 0 else 0.65), -height)
	player.speed_scale = 0.0 if model.paused else 1.0
	var existing = {}
	for tower in model.sides[side]["turrets"]:
		var key=int(tower["id"]);existing[key]=true
		if not turret_nodes.has(key):
			var gun=Sprite2D.new();add_child(gun);turret_nodes[key]=gun
		var gun=turret_nodes[key]
		gun.texture=PixelTheme.texture("res://assets/environment/turrets/"+tower["contentId"]+("-enemy" if side==1 else "")+".png")
		if gun.texture:
			gun.scale=Vector2(68.75*factor/gun.texture.get_width(),81.25*factor/gun.texture.get_height())
			gun.flip_h=side==1
			gun.position=Vector2((1 if side==0 else -1)*(int(tower["slot"])-1)*EpochData.TOWER_SPACING*factor,(-EpochData.TOWER_TOP-int(tower["slot"])%2*EpochData.TOWER_STEP+40.625)*factor)
		gun.visible=float(entity["hp"])>0.0
	for key in turret_nodes.keys():
		if not existing.has(key):turret_nodes[key].queue_free();turret_nodes.erase(key)
	queue_redraw()
func _draw() -> void:
	if model == null: return
	var side_color = PixelTheme.CYAN if side == 0 else PixelTheme.RED
	var sign_direction = 1.0 if side == 0 else -1.0
	var entity = model.base(side)
	if float(entity["hp"]) <= 0.0: return
	if float(entity["hp"]) / float(entity["maxHp"]) < 0.32:
		for i in range(3):
			var p = Vector2(sign_direction * (i * 32 + 7), -100 - fmod(model.tick + i * 12, 45) * 1.7)
			draw_circle(p, 8 + i * 2, Color("#ec8841", 0.4))
	draw_string(PixelTheme.font(), Vector2(-20, -310), EpochData.ROMAN[model.db.era_index(entity["eraId"])], HORIZONTAL_ALIGNMENT_CENTER, 40, 17, side_color)
