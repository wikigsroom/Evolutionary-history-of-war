class_name BattleReadout
extends Control
var model
func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
func _process(_delta: float) -> void: queue_redraw()
func _draw() -> void:
	if model == null: return
	draw_style_box(PixelTheme.frame("navy",0), Rect2(5,5,size.x-10,70))
	var ally = model.base(0)
	var enemy = model.base(1)
	var left = Rect2(14,12,280,47)
	var right = Rect2(size.x - 357,12,280,47)
	health(left, ally, "ally", PixelTheme.CYAN, false)
	health(right, enemy, "enemy", PixelTheme.RED, true)
	var middle = left.end.x + 14
	var available = right.position.x - middle - 12
	var chip_width = available * 0.235
	for item in [["gold", str(floori(float(model.sides[0]["gold"])))], ["xp", str(floori(float(model.sides[0]["knowledge"])))], ["command", str(floori(float(model.sides[0]["command"])) )]]:
		draw_style_box(PixelTheme.frame("pressed",0), Rect2(middle,17,chip_width,37))
		draw_texture_rect(PixelTheme.icon(item[0]), Rect2(middle + 7,19,33,33), false)
		draw_string(PixelTheme.font(),Vector2(middle+44,44),item[1],HORIZONTAL_ALIGNMENT_LEFT,-1,21,PixelTheme.AMBER if item[0] == "gold" else PixelTheme.INK)
		middle += chip_width + 7
	var minutes = floori(model.elapsed / 60.0)
	var seconds = int(model.elapsed) % 60
	draw_string(PixelTheme.font(), Vector2(middle+3,38), "%02d:%02d" % [minutes,seconds], HORIZONTAL_ALIGNMENT_LEFT,-1,18,PixelTheme.INK)
	var mission = model.db.get_row("missions", String(model.config["missionId"]))
	var text = "自由对战"
	if not mission.is_empty():
		var waves = mission["reinforcements"]
		text = "第%d/%d波" % [mini(int(waves["waves"]),floori(model.elapsed / float(waves["periodSec"]))+1),int(waves["waves"])]
	draw_string(PixelTheme.font(), Vector2(middle+3,57),text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,PixelTheme.MUTED)
func health(rect: Rect2, entity: Dictionary, crest: String, color: Color, reversed: bool) -> void:
	var icon_x = rect.end.x - 47 if reversed else rect.position.x
	var bar_x = rect.position.x if reversed else rect.position.x + 53
	draw_texture_rect(PixelTheme.icon(crest),Rect2(icon_x,rect.position.y-1,47,47),false)
	draw_style_box(PixelTheme.frame("pressed",0),Rect2(bar_x,rect.position.y+3,rect.size.x-55,25))
	var width = rect.size.x - 65
	var ratio = clampf(float(entity["hp"])/float(entity["maxHp"]),0.0,1.0)
	draw_rect(Rect2(bar_x+5+(width*(1-ratio) if reversed else 0.0),rect.position.y+8,width*ratio,15),color.darkened(0.28))
	draw_rect(Rect2(bar_x+5+(width*(1-ratio) if reversed else 0.0),rect.position.y+8,width*ratio,3),color.lightened(0.3))
	draw_string(PixelTheme.font(),Vector2(bar_x+8,rect.position.y+23),PixelTheme.number(float(entity["hp"])),HORIZONTAL_ALIGNMENT_CENTER,width-6,15,Color.WHITE)
	var shield=0.0
	for batch in entity["shields"]:shield+=float(batch["hp"])
	if shield>0.0:
		var fill=clampf(shield/(float(entity["maxHp"])*float(model.db.rules["support"]["totalShieldCapRatio"])),0,1)
		draw_rect(Rect2(bar_x+5,rect.position.y+29,width,3),PixelTheme.NAVY)
		draw_rect(Rect2(bar_x+5+(width*(1-fill) if reversed else 0),rect.position.y+29,width*fill,3),PixelTheme.AMBER)
	draw_string(PixelTheme.font(),Vector2(bar_x+6,rect.position.y+43),EpochData.ROMAN[model.db.era_index(entity["eraId"])] + "  " + model.db.era(entity["eraId"])["name"],HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)
