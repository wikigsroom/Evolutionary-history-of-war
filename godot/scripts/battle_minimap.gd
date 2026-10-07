class_name BattleMinimap
extends Control
var world: BattleWorld
var pressed_pointer=false
func _ready() -> void:
	custom_minimum_size=Vector2(218,32);mouse_filter=Control.MOUSE_FILTER_STOP
	tooltip_text="拖动战场左右移动；点击地图定位"
	gui_input.connect(_navigate)
func _process(_delta: float) -> void: queue_redraw()
func _draw() -> void:
	if world==null or world.model==null:return
	draw_style_box(PixelTheme.frame("navy",0),Rect2(Vector2.ZERO,size))
	var span=world.MAP_RIGHT-world.MAP_LEFT;var width=size.x-16.0
	var left=8+(world.camera_x-world.MAP_LEFT)/span*width
	draw_rect(Rect2(left,5,world.visible_width/span*width,size.y-10),Color(PixelTheme.CYAN,0.16))
	draw_rect(Rect2(left,5,world.visible_width/span*width,size.y-10),PixelTheme.CYAN,false,1)
	for actor in world.model.living():
		var x=8+(float(actor["x"])-world.MAP_LEFT)/span*width
		var color=PixelTheme.CYAN if actor["side"]==0 else PixelTheme.RED
		if actor["kind"]=="base":draw_rect(Rect2(x-4,10,8,12),color)
		elif actor["kind"]=="hero":draw_circle(Vector2(x,15),3,color)
		else:draw_rect(Rect2(x-1,19,2,5),color)
func _navigate(event: InputEvent) -> void:
	if world.model.paused:return
	var point=Vector2.ZERO;var move=false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:pressed_pointer=event.pressed;point=event.position;move=event.pressed
	elif event is InputEventMouseMotion and pressed_pointer:point=event.position;move=true
	elif event is InputEventScreenTouch:pressed_pointer=event.pressed;point=event.position;move=event.pressed
	elif event is InputEventScreenDrag and pressed_pointer:point=event.position;move=true
	if move:
		world.tracking="free";world.focus_world(world.MAP_LEFT+clampf((point.x-8)/maxf(1,size.x-16),0,1)*(world.MAP_RIGHT-world.MAP_LEFT))
