class_name TrainingQueue
extends HBoxContainer
signal order_selected(order_id: int)
var slots=[]
var status_label: Label
var population_label: Label
func _ready() -> void:
	add_theme_constant_override("separation",5);custom_minimum_size.y=38
	var population=TextureRect.new();population.texture=PixelTheme.icon("population");population.custom_minimum_size=Vector2(22,22);population.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;population.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;population.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(population)
	population_label=PixelTheme.label("0/29",12);population_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;add_child(population_label)
	for i in range(5):
		var slot=TrainingSlot.new();slot.index=i;slot.order_selected.connect(func(id):order_selected.emit(id));add_child(slot);slots.append(slot)
	status_label=PixelTheme.label("",12,PixelTheme.MUTED);status_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;status_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;status_label.clip_text=true;add_child(status_label)
func refresh(model) -> void:
	var orders=model.sides[0]["queue"]
	population_label.text="%d/29"%model.population(0)
	for i in range(5):
		var slot=slots[i];slot.order=orders[i] if i<orders.size() else {};slot.blocked=i==0 and not slot.order.is_empty() and int(slot.order["remaining"])==0;slot.disabled=slot.order.is_empty()
		slot.tooltip_text="待命" if slot.order.is_empty() else "%s · 时代%s\n%s\n点击查看与取消"%[model.db.get_row("units",slot.order["unitId"])["name"],EpochData.ROMAN[model.db.era_index(slot.order["eraId"])],"等待出口" if slot.blocked else "%.1f 秒"%(float(slot.order["remaining"])/30.0)]
		slot.queue_redraw()
	status_label.text="" if orders.is_empty() else ("出口堵塞" if int(orders[0]["remaining"])==0 else "%.1fs"%(float(orders[0]["remaining"])/30.0))
	status_label.add_theme_color_override("font_color",PixelTheme.AMBER if not orders.is_empty() and int(orders[0]["remaining"])==0 else PixelTheme.CYAN)
