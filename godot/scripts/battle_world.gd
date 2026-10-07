class_name BattleWorld
extends Control
signal field_clicked(x: float, target_id: int)
signal cancel_requested
const MAP_LEFT = -80.0
const MAP_RIGHT = 1680.0
var model
var audio: BattleAudio
var settings = {}
var actor_nodes = {}
var bases = []
var effects: BattleEffects
var scenery: Node2D
var field_canvas: Control
var ground = 496.0
var world_scale = 1.2
var camera_x = MAP_LEFT
var tracking = "free"
var target_preview = {}
var pointer_position = Vector2(640,450)
var show_ranges = false
var winner_clock = 0.0
var render_tick = 0
var pointer_kind = ""
var touch_index = -1
var drag_start = Vector2.ZERO
var drag_camera = 0.0
var dragged = false
var last_touch_frame = -100
var field_blockers = []
var pointer_emulated = false
var mouse_begin_frame = -100
var ambient_serial = -1
var ambient_items = []
var current_background = ""
var visible_width: float:
	get: return size.x / maxf(0.001,world_scale)
var camera_max: float:
	get: return maxf(MAP_LEFT, MAP_RIGHT - visible_width)
func setup(simulation, sound: BattleAudio, options: Dictionary) -> void:
	model = simulation; audio = sound; settings = options
	audio.begin_battle()
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP; clip_contents = true
	field_canvas=Control.new();field_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;field_canvas.clip_contents=true;add_child(field_canvas)
	scenery = Node2D.new(); field_canvas.add_child(scenery)
	for side in range(2):
		var base_view = preload("res://scenes/BaseView.tscn").instantiate()
		base_view.model = model; base_view.side = side; scenery.add_child(base_view); bases.append(base_view)
	effects = BattleEffects.new(); effects.configure(model, audio); scenery.add_child(effects)
	gui_input.connect(_input_field)
func world_to_screen(x: float) -> float: return (x - camera_x) * world_scale
func screen_to_world(x: float) -> float: return camera_x + x / world_scale
func pan(amount: float) -> void:
	tracking = "free"; camera_x = clampf(camera_x + amount, MAP_LEFT, camera_max)
func focus_world(x: float) -> void: camera_x = clampf(x - visible_width * 0.5, MAP_LEFT, camera_max)
func jump(anchor: String) -> void:
	tracking = anchor if anchor in ["hero","front"] else "free"
	if anchor == "ally": camera_x = MAP_LEFT
	elif anchor == "enemy": camera_x = camera_max
	else: focus_world(_tracked_position(anchor))
func _tracked_position(anchor: String) -> float:
	if anchor == "hero": return float(model.hero(0).get("x", model.BASE_POSITIONS[0]))
	var front = float(model.BASE_POSITIONS[0])
	for actor in model.living(0,false): front = maxf(front,float(actor["x"]))
	return front
func cancel_pointer() -> void: pointer_kind = ""; touch_index = -1; dragged = false
func _process(delta: float) -> void:
	if model == null or effects == null: return
	ground = size.y - 224.0
	field_canvas.position=Vector2(0,80);field_canvas.size=Vector2(size.x,maxf(1,ground+10-80))
	world_scale = minf(size.x / 1000.0, maxf(0.5,(ground - 84.0) / 340.0))
	camera_x = clampf(camera_x,MAP_LEFT,camera_max)
	if tracking != "free" and pointer_kind.is_empty():
		var destination = clampf(_tracked_position(tracking) - visible_width * 0.5,MAP_LEFT,camera_max)
		camera_x = destination if settings.get("reduced_motion",false) else lerpf(camera_x,destination,1.0-exp(-delta*8.0))
	if model.paused: cancel_pointer()
	if model.winner >= 0 and not model.paused:
		winner_clock += delta
		render_tick = model.tick + int(minf(winner_clock,1.6) * 30.0)
	else: render_tick = model.tick
	effects.ground = ground; effects.ratio = world_scale; effects.camera_offset = camera_x * world_scale; effects.reduced_motion = bool(settings.get("reduced_motion", false))
	audio.set_listener(camera_x, visible_width); audio.update_battle(model,delta)
	for event in model.consume_events(): effects.handle(event)
	var active_ids = {}
	for unit in model.units:
		active_ids[unit["id"]] = true
		if not actor_nodes.has(unit["id"]):
			var view = preload("res://scenes/UnitView.tscn").instantiate(); view.configure(model, unit, world_scale); scenery.add_child(view); actor_nodes[unit["id"]] = view
		var actor = actor_nodes[unit["id"]]; actor.actor = unit
		if absf(actor.ui_scale - world_scale) > 0.001: actor.configure(model, unit, world_scale)
		actor.refresh(ground, effects.reduced_motion, render_tick)
	for key in actor_nodes.keys():
		if not active_ids.has(key): actor_nodes[key].queue_free(); actor_nodes.erase(key)
	for base_view in bases:
		base_view.factor = world_scale; base_view.refresh(ground, effects.reduced_motion)
	effects.render_tick = render_tick; effects.refresh()
	_refresh_ambient()
	scenery.position = Vector2(-camera_x * world_scale,-80)
	if not effects.reduced_motion and model.tick < effects.shake_until: scenery.position += Vector2(sin(model.tick * 9.13) * effects.shake, cos(model.tick * 7.73) * effects.shake * 0.5)
	queue_redraw()
func _draw() -> void:
	if model == null: return
	var state = model.environment.scene
	var blend = 1.0 if settings.get("reduced_motion", false) else clampf((model.tick + model.interpolation - int(state.get("changedAt", -90))) / 38.0, 0.0, 1.0)
	if blend < 1.0 and state.has("previousEraId"):
		_draw_background(String(state["previousEraId"]), int(state["previousVariant"]), 1.0)
	_draw_background(String(state["eraId"]), int(state["variant"]), blend)
	_draw_ambient()
	draw_rect(Rect2(0,0,size.x,80),PixelTheme.NAVY)
	if show_ranges:
		for unit in model.living(0, false):
			var start = Vector2(world_to_screen(float(unit["x"])), ground + 8)
			draw_line(start,start+Vector2(float(unit["range"])*world_scale*float(unit.get("facing",1.0)),0),Color(PixelTheme.CYAN,0.4),2)
	if not target_preview.is_empty():
		var radius = float(target_preview.get("radius",100.0))*world_scale
		var x = world_to_screen(clampf(screen_to_world(pointer_position.x),80.0,1520.0))
		draw_arc(Vector2(x,ground-18),radius,0,TAU,48,Color(PixelTheme.AMBER,0.85),3)
		draw_line(Vector2(x,150),Vector2(x,ground),Color(PixelTheme.AMBER,0.3),2)
		if target_preview.get("heroRange",false):
			var hero = model.hero(0,false)
			if not hero.is_empty():
				var hero_x = world_to_screen(float(hero["x"]));var distance = float(target_preview["range"])*world_scale
				draw_line(Vector2(maxf(0,hero_x-distance),ground+9),Vector2(minf(size.x,hero_x+distance),ground+9),PixelTheme.CYAN,3)

func _draw_background(era_id: String, variant: int, opacity: float) -> void:
	var path = "res://assets/environment/eras/%s-%d.png" % [era_id, variant]
	var background = PixelTheme.texture(path)
	if background == null: background = PixelTheme.texture("res://assets/environment/night-frontier.png")
	if background == null: return
	current_background = path
	var height = maxf(1.0, ground - 80.0) / 0.92
	var width = maxf(size.x, height * background.get_width() / float(background.get_height()))
	var travel = minf(width - size.x, maxf(0, (MAP_RIGHT - MAP_LEFT) * world_scale - size.x) * 0.4)
	var camera_progress = (camera_x - MAP_LEFT) / maxf(1.0, camera_max - MAP_LEFT)
	draw_texture_rect(background, Rect2(-camera_progress * travel, 80, width, height), false, Color(1,1,1,opacity))

func _refresh_ambient() -> void:
	var state = model.environment.scene
	if ambient_serial == int(state["serial"]): return
	ambient_serial = int(state["serial"]); ambient_items.clear()
	var pool = model.db.era(state["eraId"]).get("ambient", [])
	if pool.is_empty(): return
	# Presentation-only arithmetic: never consume either simulation RNG stream.
	var seed_value = int(model.config.get("seed", 1)) + ambient_serial * 137
	for i in range(5):
		var kind = String(pool[(seed_value + i * 7) % pool.size()])
		ambient_items.append({"kind":kind, "offset":fposmod(seed_value * 0.031 + i * 0.193, 1.0), "period":28.0 + (seed_value + i * 11) % 35,
			"altitude":0.08 + i * 0.105, "direction":1 if i % 3 != 0 else -1,
			"extent":28.0 if kind in ["bat","bird"] else 48.0 if kind in ["pterosaur","drone","balloon"] else 78.0})

func _draw_ambient() -> void:
	var still = bool(settings.get("reduced_motion", false))
	var clock = float(model.tick) / model.HZ + model.interpolation / model.HZ
	for i in range(ambient_items.size()):
		if still and i > 2: break
		var item = ambient_items[i]
		var texture = PixelTheme.texture("res://assets/environment/ambient/" + item["kind"] + ".png")
		if texture == null: continue
		var progress = float(item["offset"]) if still else fposmod(clock / float(item["period"]) + float(item["offset"]), 1.0)
		if int(item["direction"]) < 0: progress = 1.0 - progress
		var extent = float(item["extent"])
		var center = Vector2(lerpf(-extent, size.x + extent, progress), 90.0 + maxf(50,ground - 180) * float(item["altitude"]))
		if not still: center.y += sin(clock * (2.3 if item["kind"] in ["bird","bat"] else 0.7) + i) * 5.0
		var dimensions = Vector2(extent, extent * texture.get_height() / float(texture.get_width()))
		draw_set_transform(center, 0, Vector2(float(item["direction"]), 1.0))
		draw_texture_rect(texture, Rect2(-dimensions/2, dimensions), false, Color(0.82,0.87,0.94,0.65))
		draw_set_transform(Vector2.ZERO)
func _field_point(point: Vector2) -> bool: return point.y >= 85.0 and point.y <= ground + 4.0
func _uncovered(point: Vector2) -> bool:
	var global_point=get_global_transform()*point
	field_blockers=field_blockers.filter(func(node):return is_instance_valid(node) and not node.is_queued_for_deletion())
	for control in field_blockers:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(global_point):return false
	return true
func _begin(point: Vector2, kind: String, index: int = -1) -> void:
	if not _field_point(point) or not pointer_kind.is_empty(): return
	pointer_kind = kind; touch_index = index; drag_start = point; drag_camera = camera_x; dragged = false; pointer_position = point
func _drag(point: Vector2) -> void:
	pointer_position = point
	if pointer_kind.is_empty(): return
	if point.distance_to(drag_start) >= 8.0: dragged = true
	if dragged: tracking = "free"; camera_x = clampf(drag_camera-(point.x-drag_start.x)/world_scale,MAP_LEFT,camera_max)
func _end(point: Vector2) -> void:
	if pointer_kind.is_empty(): return
	var tap = not dragged and _field_point(point)
	cancel_pointer()
	if not tap: return
	var x = clampf(screen_to_world(point.x),80.0,1520.0)
	var target = -1; var best = 75.0
	for unit in model.living(1):
		var distance = absf(float(unit["x"])-x)
		if distance < best: best = distance; target = int(unit["id"])
	field_clicked.emit(x,target)
func _input_field(event: InputEvent) -> void:
	if model.paused or model.winner >= 0: cancel_pointer(); return
	if event is InputEventMouseButton:
		if event.device == -1 and Engine.get_process_frames()-last_touch_frame <= 2: return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin(event.position,"mouse");pointer_emulated=event.device==-1;mouse_begin_frame=Engine.get_process_frames()
			elif pointer_kind == "mouse": _end(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed: cancel_pointer(); cancel_requested.emit()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_LEFT,MOUSE_BUTTON_WHEEL_RIGHT]:
			pan(-120.0 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_LEFT] else 120.0)
	elif event is InputEventMouseMotion:
		if event.device == -1 and Engine.get_process_frames()-last_touch_frame <= 2: return
		pointer_position = event.position
		if pointer_kind == "mouse": _drag(event.position)
func _input(event: InputEvent) -> void:
	if not event is InputEventScreenTouch and not event is InputEventScreenDrag:return
	if model==null or model.paused or model.winner>=0:return
	var local=make_input_local(event);last_touch_frame=Engine.get_process_frames()
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _field_point(local.position) or not _uncovered(local.position):return
			if pointer_kind=="mouse" and pointer_emulated and mouse_begin_frame==Engine.get_process_frames():cancel_pointer()
			_begin(local.position,"touch",event.index)
		elif pointer_kind=="touch" and event.index==touch_index:
			if event.canceled:cancel_pointer()
			else:_end(local.position)
		else:return
	elif pointer_kind=="touch" and event.index==touch_index:_drag(local.position)
	else:return
	get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: cancel_pointer()
