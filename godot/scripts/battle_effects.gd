class_name BattleEffects
extends Node2D
var model
var ground = 512.0
var ratio = 0.8
var camera_offset = 0.0
var effects = []
var audio: BattleAudio
var reduced_motion = false
var shake = 0.0
var shake_until = 0
var event_count = 0
var render_tick = 0
var native_bursts = []
var carrier_foot_offsets = {}
func _ready() -> void:
	for i in range(8):
		var burst = preload("res://scenes/ImpactBurst.tscn").instantiate();add_child(burst);native_bursts.append(burst)
func native_burst(x: float, y: float, color: Color, intensity: float=1.0) -> void:
	if reduced_motion: return
	for burst in native_bursts:
		if burst.emitting: continue
		burst.position=Vector2(x,y);burst.color=color;burst.initial_velocity_max=130.0*intensity;burst.restart();return

func configure(simulation, sound: BattleAudio) -> void: model = simulation; audio = sound; z_index = 50

func push(kind: String, x: float, y: float, color: Color, seconds: float = 0.4, data: Dictionary = {}) -> void:
	if effects.size() >= 420: effects.pop_front()
	effects.append({"kind": kind, "x": x, "y": y, "color": color, "at": model.tick, "duration": maxf(1.0, seconds * 30.0), "data": data})

func particles(x: float, y: float, color: Color, count: int, seed_id: int, strength: float = 1.0) -> void:
	for i in range(mini(count, 4) if reduced_motion else count):
		var angle = float((seed_id * 31 + i * 73) % 360) / 180.0 * PI
		var speed = (26.0 + (seed_id + i * 23) % 55) * strength
		push("particle", x, y, color, 0.25 + (i % 4) * 0.07, {"vx": cos(angle) * speed, "vy": -absf(sin(angle) * speed) - 12.0, "size": 2.0 + i % 2})

func handle(event: Dictionary) -> void:
	event_count += 1
	audio.handle_event(event,model)
	var type = String(event["type"])
	var data = event["data"]
	var side = int(event["side"])
	var x = float(event["x"]) * ratio
	var y = ground - 45.0
	var color = PixelTheme.CYAN if side == 0 else PixelTheme.RED if side == 1 else PixelTheme.AMBER
	var target = model.entity_by_id(int(data.get("targetId", -1)))
	if not target.is_empty(): y = ground - float(model.db.profile(target.get("visualId",target["contentId"]))["hit"][1]) * ratio if target["kind"] != "base" else ground - 105.0
	match type:
		"release":
			y = ground - float(data.get("muzzleY", 50.0)) * ratio
			var weapon = String(data.get("weaponId", "W02"))
			if weapon in ["W02", "W06"]:
				push("slash", x, y, PixelTheme.AMBER, 0.16, {"direction": 1.0 if side == 0 else -1.0, "heavy": weapon == "W06"})
			elif weapon == "W07":
				push("arc", x, y, PixelTheme.CYAN, 0.18, {"toX": float(data["toX"]) * ratio, "seed": event["id"]})
			elif weapon == "W08": push("ring", x, y, PixelTheme.AMBER, 0.3, {"radius": 30.0})
			else:
				push("texture", x, y, Color.WHITE, 0.12, {"texture": "muzzle", "size": 25.0 if weapon != "W05" else 46.0, "flip": side == 1})

		"hit":
			var weapon = String(data.get("weaponId", "W02"))
			var material = "metal" if not target.is_empty() and model.db.profile(target.get("visualId",target["contentId"]))["material"] == "metal" else "stone"
			var heavy = weapon == "W05" or data.get("heavy", false) or String(data.get("skillId", "")) in ["S05", "HS01"]
			if int(data.get("absorbed", 0)) > 0:
				push("texture", x, y, Color.WHITE, 0.22, {"texture": "shield_ring", "size": 56.0})
			if int(data.get("amount", 0)) > 0:
				var effect = "cannon_shock" if weapon == "W05" else ("arc_spark" if data.get("damageType") == "energy" else material + "_impact")
				push("texture", x, y, Color.WHITE, 0.2 if not heavy else 0.35, {"texture": effect, "size": 35.0 if not heavy else 88.0})
				particles(x, y, PixelTheme.AMBER if material == "metal" else Color("#d6b597"), 6 if not heavy else 14, int(event["id"]), 1.0 if not heavy else 1.7)
				push("text", x + float(int(event["id"]) % 15 - 7), y - 8, Color("#fff0c5"), 0.55, {"text": PixelTheme.number(float(data["amount"])), "large": heavy})

				if heavy and not reduced_motion: shake = 3.0; shake_until = model.tick + 6;native_burst(x,y,PixelTheme.AMBER,1.3)
		"chain": push("arc", x, y, PixelTheme.CYAN, 0.2, {"toX": float(data["toX"]) * ratio, "seed": event["id"]})
		"shield": push("ring", x, y, PixelTheme.CYAN, 0.45, {"radius": 33.0})
		"shieldBreak":
			particles(x, y, PixelTheme.CYAN, 12, int(event["id"]), 1.5);native_burst(x,y,PixelTheme.CYAN)
		"spawn":
			push("texture", x, ground - 3, Color.WHITE, 0.3, {"texture": "dust", "size": 44.0})

		"death":
			if data.get("kind") == "base":
				push("collapse", x, ground - 100, PixelTheme.AMBER, 1.4, {"radius": 165.0}); particles(x, ground - 80, Color("#bea388"), 34, int(event["id"]), 3.0)
				shake = 5.0; shake_until = model.tick + 30
			else: push("texture", x, ground - 4, Color.WHITE, 0.45, {"texture": "dust", "size": 45.0})
		"reward": push("reward", x, y, PixelTheme.AMBER, 0.9, {"amount": data["amount"]})
		"heal": push("text", x, y - 10, PixelTheme.GREEN, 0.7, {"text": "+" + PixelTheme.number(float(data["amount"]))}); particles(x, y, PixelTheme.GREEN, 5, int(event["id"]))
		"warning": push("warning", x, ground - 2, color, maxf(0.1, float(int(data["until"]) - model.tick) / 30.0), {"radius": float(data["radius"]) * ratio})
		"ageLaunch":
			var row = model.db.age_special(data["eraId"])
			var duration = float(data["warningSec"]) + int(data["pulses"]) * float(data["pulseIntervalSec"]) + 0.5
			push("raid", x, ground - 18, color, duration, {"eraId":data["eraId"],"fromX":float(data["fromX"])*ratio,"side":side,"radius":float(data["radius"])*ratio,
				"warning":data["warningSec"],"interval":data["pulseIntervalSec"],"pulses":data["pulses"],"count":row["projectileCount"],"name":row["name"]})
		"ageImpact":
			var era_id = String(data["eraId"])
			var extent = float(data["radius"]) * ratio * 1.8
			var tint = PixelTheme.CYAN if model.db.era_index(era_id) >= 8 else PixelTheme.AMBER
			var point = x + (int(data["pulse"]) % 3 - 1) * 36.0 * ratio
			push("eraTexture", x, ground - 7, Color.WHITE, 0.8, {"path":"res://assets/fx/eras/"+era_id+"-shock.png","size":extent,"flat":true})
			push("eraTexture", point, ground - 55 * ratio, Color.WHITE, 0.48, {"path":"res://assets/fx/eras/"+era_id+"-impact.png","size":150*ratio})
			push("eraTexture", point, ground - 40 * ratio, Color.WHITE, 1.8, {"path":"res://assets/fx/eras/"+era_id+"-smoke.png","size":160*ratio,"rise":70.0})
			push("eraTexture", point, ground - 40 * ratio, Color.WHITE, 0.65, {"path":"res://assets/fx/eras/"+era_id+"-sparks.png","size":170*ratio})
			particles(point, ground - 35 * ratio, tint, 30, int(event["id"]), 2.8)
			native_burst(point,ground-30*ratio,tint,2.4)
			if not reduced_motion: shake = 5.0; shake_until = model.tick + 8
		"eventWarning":
			var duration = maxf(0.1,float(int(data["until"]) - model.tick) / 30.0)
			push("warning", x, ground - 2, PixelTheme.AMBER, duration, {"radius":float(data["radius"])*ratio,"neutral":true})
			push("eventFall", x, ground - 14, PixelTheme.AMBER, duration, {"kind":data["eventKind"],"eraId":data["eraId"],"name":EpochEnvironment.EVENT_NAMES.get(data["eventKind"],"天空异变")})
		"eventImpact":
			var era_id = String(data["eraId"])
			push("eraTexture", x, ground - 25, Color.WHITE, 0.42, {"path":"res://assets/fx/eras/"+era_id+"-impact.png","size":92*ratio})
			push("eraTexture", x, ground - 3, Color.WHITE, 0.6, {"path":"res://assets/fx/eras/"+era_id+"-shock.png","size":float(data["radius"])*ratio*1.7,"flat":true})
			push("eraTexture", x, ground - 20, Color.WHITE, 1.15, {"path":"res://assets/fx/eras/"+era_id+"-smoke.png","size":94*ratio,"rise":38.0})
			particles(x,ground-22,PixelTheme.AMBER,15,int(event["id"]),1.6)
			if not reduced_motion: shake=2.5;shake_until=model.tick+5
		"evolve":
			push("evolve", x, ground - 100, PixelTheme.AMBER, 1.3, {"name": data["name"]}); particles(x, ground - 140, PixelTheme.AMBER, 30, int(event["id"]), 2.4)
			native_burst(x,ground-100,PixelTheme.AMBER,2.3)
		"item":
			var item_id=String(data["itemId"])
			if item_id=="war-drum":
				for id in data.get("targets",[]):
					var ally=model.entity_by_id(int(id))
					if not ally.is_empty():push("ring",float(ally["x"])*ratio,ground-8,PixelTheme.AMBER,0.7,{"radius":35.0})
				push("text",x,ground-130,PixelTheme.AMBER,1.0,{"text":"全军强化"})
			elif item_id=="chrono-crate":
				push("text",x,ground-120,PixelTheme.AMBER,1.1,{"text":"+"+PixelTheme.number(float(data.get("gold",65.0)))});particles(x,ground-50,PixelTheme.CYAN,14,int(event["id"]))
			else:
				push("ring",x,ground-12,PixelTheme.MUTED,0.65,{"radius":float(data["radius"])*ratio});particles(x,ground-25,PixelTheme.MUTED,18,int(event["id"]))
		"skill", "build":
			push("ring", x, ground - 15, color, 0.45, {"radius": 55.0})
		"skillImpact":
			var skill = String(data.get("skillId", ""))
			if skill in ["S05", "S08"]: push("meteor", x, ground - 30, PixelTheme.AMBER, 0.45, {"radius": float(data["radius"]) * ratio})
			elif skill == "HS02":
				if data.get("weaponId")=="W03": push("arrows", x, ground - 60, PixelTheme.INK, 0.3, {"radius": 55.0})
				else:push("eraTexture",x,ground-45,Color.WHITE,0.28,{"path":"res://assets/fx/eras/"+String(data.get("eraId","A1"))+"-sparks.png","size":80*ratio})
			elif skill == "S03": push("arrows", x, ground - 60, PixelTheme.INK, 0.3, {"radius": 55.0})
			elif skill in ["S06", "S07", "HS05"]: push("ring", x, ground - 30, PixelTheme.CYAN, 0.5, {"radius": float(data["radius"]) * ratio})

func refresh() -> void:
	for burst in native_bursts: burst.speed_scale=0.0 if model.paused else 1.0
	effects = effects.filter(func(e): return float(render_tick - int(e["at"])) <= float(e["duration"]))
	queue_redraw()

func _draw() -> void:
	if model == null: return
	for projectile in model.projectiles:
		var world_x = lerpf(float(projectile["previousX"]), float(projectile["x"]), model.interpolation)
		var target = model.entity_by_id(int(projectile["targetId"]))
		var target_x = float(target.get("x", projectile.get("targetX", world_x)))
		var origin = float(projectile.get("originX", world_x))
		var span = maxf(1.0, absf(target_x - origin))
		var progress = clampf(absf(world_x - origin) / span, 0.0, 1.0)
		var start_height = float(projectile["muzzleY"])
		var end_height = float(projectile.get("targetHeight", start_height))
		var x = world_x * ratio
		var y = ground - lerpf(start_height, end_height, progress) * ratio
		var direction = float(projectile["direction"])
		var travel = Vector2(direction,(start_height - end_height) / span).normalized()
		var point = Vector2(x,y)
		match projectile["weaponId"]:
			"W01":
				point.y -= sin(minf(PI, float(model.tick-int(projectile["bornTick"]))/24.0*PI))*18
				draw_circle(point,3.5,Color("#a79883")); draw_circle(point-Vector2(1,1),1.2,Color("#f0d4ae"))
			"W03":
				draw_line(point-travel*15,point,PixelTheme.INK,2)
				var normal=Vector2(-travel.y,travel.x)*3
				draw_colored_polygon(PackedVector2Array([point+travel*3,point-travel*3+normal,point-travel*3-normal]),PixelTheme.INK)
			"W04": draw_line(point-travel*19,point,PixelTheme.AMBER,2); draw_line(point-travel*26,point-travel*19,Color(PixelTheme.AMBER,0.2),1)
			"W05": draw_circle(point,5,Color("#532731"));draw_circle(point-Vector2(direction*2,1),3,PixelTheme.AMBER);draw_line(point-travel*18,point,Color(PixelTheme.RED,0.35),4)
	for field in model.fields:
		var color = Color("#7292b1") if field["kind"] == "smoke" else (PixelTheme.CYAN if field["kind"] == "rift" else PixelTheme.AMBER)
		var x = float(field["x"]) * ratio
		for i in range(6):
			var phase = float(model.tick % 90) / 90.0 + i * 0.17
			var center = Vector2(x + sin(phase * TAU + i) * float(field["radius"]) * ratio * 0.7, ground - 15 - fmod(phase, 1.0) * 65)
			draw_circle(center, 23.0 if field["kind"] == "smoke" else 4.0, Color(color, 0.24 if field["kind"] == "smoke" else 0.42))
		if field["kind"]=="smoke":pixel_ring(Vector2(x,ground-8),float(field["radius"])*ratio,Color(PixelTheme.MUTED,0.6),2)
	for effect in effects:
		var progress = clampf((float(render_tick) + model.interpolation - int(effect["at"])) / float(effect["duration"]), 0.0, 1.0)
		var origin = Vector2(float(effect["x"]), float(effect["y"]))
		var color = Color(effect["color"], 1.0 - progress)
		var details = effect["data"]
		match effect["kind"]:
			"particle":
				var t = progress * float(effect["duration"]) / 30.0
				var position = origin + Vector2(float(details["vx"]) * t, float(details["vy"]) * t + 80 * t * t)
				draw_rect(Rect2(position.round(), Vector2.ONE * float(details["size"])), color)
			"texture":
				var texture = PixelTheme.texture("res://assets/fx/" + details["texture"] + ".png")
				var extent = float(details["size"]) * (0.65 + progress * 0.45)
				if texture:
					draw_set_transform(origin,0,Vector2(-1.0 if details.get("flip",false) else 1.0,1.0))
					draw_texture_rect(texture,Rect2(-Vector2.ONE*extent/2.0,Vector2.ONE*extent),false,Color(1,1,1,1.0-progress));draw_set_transform(Vector2.ZERO)
			"text": draw_string(PixelTheme.font(), origin - Vector2(12, progress * 22), details["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 19 if details.get("large", false) else 14, color)
			"reward":
				var end = Vector2(405 + camera_offset, 28)
				var point = origin.lerp(end, progress * progress)
				draw_texture_rect(PixelTheme.icon("gold"), Rect2(point - Vector2(10,10), Vector2(20,20)), false, color)
			"ring", "collapse":
				var radius = float(details["radius"]) * (0.4 + progress * 0.65)
				pixel_ring(origin, radius, color, 2.0)
			"warning":
				var radius = float(details["radius"])
				var pulse = 0.4 + absf(sin(progress * TAU * 3)) * 0.4
				draw_line(origin - Vector2(radius,0), origin + Vector2(radius,0), Color(effect["color"], pulse), 3.0)
				pixel_ring(origin, radius, Color(effect["color"],pulse * 0.7), 2.0)
				draw_texture_rect(PixelTheme.icon("warning"), Rect2(origin.x - 12, origin.y - 28, 24,24), false, Color(1,1,1,pulse))
			"eraTexture":
				var extent = float(details["size"]) * (0.55 + progress * 0.8)
				var point = origin - Vector2(0,progress * float(details.get("rise",0.0)))
				_draw_bitmap(String(details["path"]),point,extent,0,1,Color(1,1,1,pow(1.0-progress,0.7)),0.32 if details.get("flat",false) else 1.0)
			"raid": _draw_raid(origin,details,progress * float(effect["duration"]) / 30.0)
			"eventFall": _draw_event_fall(origin,details,progress)
			"slash":
				var points = PackedVector2Array()
				for i in range(8):
					var angle = -1.3 + i * 0.3 + progress * 0.4
					points.append(origin + Vector2(cos(angle) * 30 * float(details["direction"]), sin(angle) * 24))
				draw_polyline(points, color, 3.0)
			"arc":
				var destination = Vector2(float(details["toX"]), origin.y + 3)
				var points = PackedVector2Array([origin])
				for i in range(1,7): points.append(origin.lerp(destination, i / 7.0) + Vector2(0,float((int(details["seed"]) + i * 19) % 17 - 8)))
				points.append(destination); draw_polyline(points, Color(color, color.a * 0.35), 6.0); draw_polyline(points, color, 2.0)
			"meteor":
				if details.get("orbital", false): draw_rect(Rect2(origin.x - (1 - progress) * 18, 70, (1 - progress) * 36, origin.y - 70), Color(color, (1.0 - progress) * 0.4))
				else: draw_line(origin - Vector2(60, 190) * (1 - progress), origin, Color(color, (1.0 - progress) * 0.6), maxf(2.0, 14.0 * (1.0 - progress)))
				pixel_ring(origin, float(details["radius"]) * progress, color, 3.0)
			"arrows":
				for i in range(7):
					var point = origin + Vector2(-float(details["radius"]) + i * 17, -90 * (1 - progress) + i % 3 * 7)
					draw_line(point - Vector2(5,18), point, color, 2.0)
			"evolve":
				var width = 145 * (1 - progress)
				draw_rect(Rect2(origin.x - width / 2.0, 170, width, ground - 170), Color(color, 0.13 * (1 - progress)))
				draw_string(PixelTheme.display_font(), Vector2(maxf(14, origin.x - 120), 180 - progress * 8), details["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color)

func pixel_ring(origin: Vector2, radius: float, color: Color, thickness: float) -> void:
	var points = PackedVector2Array()
	for i in range(17): points.append((origin + Vector2(cos(i / 16.0 * TAU), sin(i / 16.0 * TAU) * 0.35) * radius).snapped(Vector2(2,2)))
	draw_polyline(points, color, thickness)

func _draw_bitmap(path: String, center: Vector2, extent: float, angle: float = 0.0, facing: float = 1.0, tint: Color = Color.WHITE, flatten: float = 1.0) -> void:
	var texture = PixelTheme.texture(path)
	if texture == null: return
	var dimensions = texture.get_size() * (extent / maxf(texture.get_width(),texture.get_height()))
	dimensions.y *= flatten
	draw_set_transform(center,angle,Vector2(facing,1))
	draw_texture_rect(texture,Rect2(-dimensions/2,dimensions),false,tint)
	draw_set_transform(Vector2.ZERO)

func raid_carrier_pose(origin: Vector2, details: Dictionary, elapsed: float) -> Dictionary:
	var era = model.db.era_index(details["eraId"]) + 1
	var direction = 1.0 if int(details["side"]) == 0 else -1.0
	var path = "res://assets/fx/eras/" + details["eraId"] + "-carrier.png"
	var sky = maxf(95.0,ground-310.0*ratio)
	var grounded = era not in [7,10]
	var extent = (145.0 if era in [8,9] else 120.0 if grounded else 170.0 if era==7 else 150.0)*ratio
	var center = Vector2(origin.x,sky)
	var foot_offset = 0.0
	if grounded:
		if not carrier_foot_offsets.has(path):
			var texture = PixelTheme.texture(path)
			var image = texture.get_image() if texture else null
			var bottom = 0
			if image:
				for y in range(image.get_height()-1,-1,-1):
					for x in range(image.get_width()):
						if image.get_pixel(x,y).a >= 160.0/255.0:
							bottom = y+1;break
					if bottom>0:break
				carrier_foot_offsets[path] = (float(bottom)-image.get_height()*0.5)/maxf(image.get_width(),image.get_height())
			else:carrier_foot_offsets[path] = 0.5
		foot_offset = float(carrier_foot_offsets[path])*extent
		center = Vector2(float(details["fromX"])+direction*180.0*ratio,ground-foot_offset)
	elif era==7:
		center = Vector2(origin.x+direction*lerpf(-310,310,clampf(elapsed/(float(details["warning"])+0.8),0,1))*ratio,sky+22)
	var muzzle = center+Vector2(direction*extent*0.28,-extent*0.18) if grounded else center+Vector2(0,16*ratio)
	return {"center":center,"extent":extent,"grounded":grounded,"contactY":center.y+foot_offset,"muzzle":muzzle,"path":path,"direction":direction}

func _draw_raid(origin: Vector2, details: Dictionary, elapsed: float) -> void:
	var era = model.db.era_index(details["eraId"]) + 1
	var prefix = "res://assets/fx/eras/" + details["eraId"] + "-"
	var direction = 1.0 if int(details["side"]) == 0 else -1.0
	var warning = float(details["warning"])
	var radius = float(details["radius"])
	var sky = maxf(95.0,ground-310.0*ratio)
	if elapsed < warning:
		var text_x = clampf(origin.x, camera_offset+110, camera_offset+model.get_viewport().get_visible_rect().size.x-180)
		draw_string(PixelTheme.font(),Vector2(text_x-48,sky-10),details["name"],HORIZONTAL_ALIGNMENT_LEFT,-1,17,PixelTheme.AMBER)
	var pose = raid_carrier_pose(origin,details,elapsed)
	var fade = clampf((warning+int(details["pulses"])*float(details["interval"])+0.35-elapsed)*2,0,1)
	_draw_bitmap(pose["path"],pose["center"],pose["extent"],0,direction,Color(1,1,1,fade))
	for pulse in range(int(details["pulses"])):
		var arrival = warning + pulse * float(details["interval"])
		var flight = minf(0.8,warning-0.12)
		var t = (elapsed-(arrival-flight))/flight
		if t < 0.0 or t > 1.0: continue
		var count = int(details["count"])
		if reduced_motion: count = mini(count,3)
		for i in range(count):
			var spread = (float(i)/maxi(1,count-1)-0.5)*radius*1.2
			var end = origin+Vector2(spread,0)
			var launch_pose = raid_carrier_pose(origin,details,arrival-flight)
			var start = Vector2(launch_pose["muzzle"])
			var point = start.lerp(end,t)
			var velocity = end-start
			if pose["grounded"]:
				var control = Vector2(lerpf(start.x,end.x,0.45),maxf(100.0,ground-(290.0 if era in [1,6,8,9] else 230.0)*ratio))
				point = start.lerp(control,t).lerp(control.lerp(end,t),t)
				velocity = (control-start)*(1.0-t)+(end-control)*t
			elif era==7:
				point.y = lerpf(start.y,end.y,t*t)
				velocity = Vector2(end.x-start.x,(end.y-start.y)*2.0*t)
			else:
				start = Vector2(end.x,sky+25);point = start.lerp(end,t);velocity = end-start
			var angle = velocity.angle()-PI/4
			var extent = (72.0 if era==1 else 43.0 if era in [2,3,4] else 35.0)*ratio
			var tint = PixelTheme.CYAN if era>=9 else PixelTheme.AMBER
			if era == 10:
				var beam_width=(6.0+sin(t*PI)*16.0)*ratio
				draw_rect(Rect2(end.x-beam_width*2,sky,beam_width*4,end.y-sky),Color(tint,0.12))
				draw_rect(Rect2(end.x-beam_width/2,sky,beam_width,end.y-sky),Color(tint,0.8))
			else:
				var trail = velocity.normalized() * (30 if era in [2,3,4] else 45)*ratio
				draw_line(point-trail,point,Color(tint,0.27),8 if era==1 else 4)
				draw_line(point-trail*0.6,point,Color(tint,0.65),3 if era==1 else 1)
			_draw_bitmap(prefix+"projectile.png",point,extent,angle,1)

func _draw_event_fall(origin: Vector2, details: Dictionary, progress: float) -> void:
	var kind = String(details["kind"])
	var sky = maxf(92,ground-300*ratio)
	var text_x = clampf(origin.x,camera_offset+110,camera_offset+model.get_viewport().get_visible_rect().size.x-170)
	draw_string(PixelTheme.font(),Vector2(text_x-46,sky-8),details["name"],HORIZONTAL_ALIGNMENT_LEFT,-1,16,PixelTheme.AMBER)
	if kind == "storm":
		_draw_bitmap("res://assets/fx/eras/"+details["eraId"]+"-smoke.png",Vector2(origin.x,sky+24),170*ratio,0,1,Color(0.65,0.72,0.87,0.75))
		if progress > 0.84:
			var points = PackedVector2Array([Vector2(origin.x,sky+30),Vector2(origin.x-35,sky+110),Vector2(origin.x+14,sky+90),origin])
			draw_polyline(points,Color(PixelTheme.CYAN,0.35),9);draw_polyline(points,PixelTheme.INK,3)
		return
	var fall = clampf((progress-0.28)/0.72,0,1)
	var point = Vector2(origin.x-130*ratio*(1-fall),lerpf(sky,origin.y,fall*fall))
	var angle = -0.18+fall*0.65 if kind in ["plane","drone","debris"] else sin(fall*PI)*0.25
	if not reduced_motion:
		draw_line(point-Vector2(20,48)*ratio,point,Color(PixelTheme.AMBER,0.24),10*ratio)
	_draw_bitmap("res://assets/fx/events/"+kind+".png",point,(105 if kind=="plane" else 75)*ratio,angle,1)
