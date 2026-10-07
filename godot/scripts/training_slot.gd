class_name TrainingSlot
extends Button
signal order_selected(order_id: int)
var order = {}
var index = 0
var blocked = false
func _ready() -> void:
	text="";custom_minimum_size=Vector2(48,38);focus_mode=Control.FOCUS_NONE
	PixelTheme.apply_button(self,PixelTheme.CYAN,true);custom_minimum_size.y=38
	pressed.connect(func():if not order.is_empty():order_selected.emit(int(order["id"])))
func _draw() -> void:
	if order.is_empty():
		draw_texture_rect(PixelTheme.icon("queue"),Rect2(15,5,18,18),false,Color(1,1,1,0.18));return
	var image=PixelTheme.texture("res://assets/ui/units/"+order["unitId"]+".png")
	if image:draw_texture_rect(image,Rect2(11,2,26,26),false)
	var progress=1.0-float(order["remaining"])/maxf(1.0,float(order["duration"]))
	draw_rect(Rect2(5,size.y-9,size.x-10,6),Color("#041021"))
	draw_rect(Rect2(6,size.y-8,(size.x-12)*progress,4),PixelTheme.AMBER if blocked else PixelTheme.CYAN)
	draw_string(PixelTheme.font(),Vector2(5,12),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,10,PixelTheme.AMBER if index==0 else PixelTheme.MUTED)
	if blocked:draw_texture_rect(PixelTheme.icon("warning"),Rect2(size.x-16,2,12,12),false)
