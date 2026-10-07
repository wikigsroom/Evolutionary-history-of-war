class_name CommanderButton
extends Button
var hero_id = "H01"
var health = 1.0
var respawn = 0.0
var selected = false
func _ready() -> void:
	for style in ["normal","hover","pressed","focus","disabled"]: add_theme_stylebox_override(style, StyleBoxEmpty.new())
	custom_minimum_size = Vector2(94,140)
func _draw() -> void:
	var center = Vector2(size.x / 2, size.y * 0.55)
	var radius = minf(size.x*0.43,43)
	var points = PackedVector2Array()
	for i in range(16): points.append((center+Vector2(cos(i/16.0*TAU),sin(i/16.0*TAU))*radius).snapped(Vector2(2,2)))
	draw_colored_polygon(points,PixelTheme.PANEL)
	points.append(points[0]); draw_polyline(points,PixelTheme.AMBER if selected or is_hovered() else PixelTheme.CYAN_DARK,4)
	var portrait = PixelTheme.texture("res://assets/ui/heroes/"+hero_id+".png")
	if portrait: draw_texture_rect(portrait,Rect2(center-Vector2(31,36),Vector2(62,70)),false)
	draw_texture_rect(PixelTheme.icon("crown"),Rect2(center.x-19,center.y-radius-23,38,30),false)
	draw_rect(Rect2(center.x-30,center.y+radius+7,60,5),Color("#081122"))
	draw_rect(Rect2(center.x-30,center.y+radius+7,60*health,5),PixelTheme.GREEN)
	if respawn>0:
		draw_circle(center,radius,Color(0.03,0.06,0.1,0.8))
		draw_string(PixelTheme.font(),Vector2(center.x-20,center.y+7),str(ceili(respawn)),HORIZONTAL_ALIGNMENT_CENTER,40,24,PixelTheme.INK)
