extends SceneTree
var app
var checks=0
var failures=[]
var directory="res://../output/qa/godot-fixes/"
func _initialize() -> void:
	var output=OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	directory=output.trim_suffix("/")+"/" if not output.is_empty() else ProjectSettings.globalize_path(directory)
	DirAccess.make_dir_recursive_absolute(directory);call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func settle() -> void:
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
func physical(point: Vector2) -> Vector2:return app.current_view.get_viewport_transform()*point
func button(node: Node,prefix: String):
	if node is Button and node.text.begins_with(prefix):return node
	for child in node.get_children():
		var found=button(child,prefix)
		if found!=null:return found
	return null
func icon(node: Node,tooltip: String):
	if node is BaseButton and node.tooltip_text==tooltip:return node
	for child in node.get_children():
		var found=icon(child,tooltip)
		if found!=null:return found
	return null
func pointer(point: Vector2,pressed: bool,touch: bool,index: int=0,canceled: bool=false) -> void:
	var pos=physical(point)
	if touch:
		var e=InputEventScreenTouch.new();e.position=pos;e.pressed=pressed;e.index=index;e.canceled=canceled;Input.parse_input_event(e)
	else:
		var e=InputEventMouseButton.new();e.position=pos;e.global_position=pos;e.pressed=pressed;e.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(e)
	await process_frame
func click(control: Control,touch: bool=false) -> void:
	check(is_instance_valid(control),"操作按钮存在")
	if not is_instance_valid(control):return
	var point=control.get_global_rect().get_center();await pointer(point,true,touch);await pointer(point,false,touch);await settle()
func tap(point: Vector2,touch: bool) -> void:
	await pointer(point,true,touch);await pointer(point,false,touch);await settle()
func drag(from: Vector2,to: Vector2,touch: bool) -> void:
	await pointer(from,true,touch)
	for i in range(1,6):
		var point=from.lerp(to,float(i)/5)
		if touch:
			var e=InputEventScreenDrag.new();e.index=0;e.position=physical(point);e.relative=physical(to-from)/5;Input.parse_input_event(e)
		else:
			var e=InputEventMouseMotion.new();e.position=physical(point);e.global_position=e.position;e.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(e)
		await process_frame
	await pointer(to,false,touch);await settle()
func capture(name: String) -> void:
	await settle();root.get_texture().get_image().save_png(directory+name+".png")
func fixture() -> void:
	app.show_battle({"aiEnabled":false});await settle()
	for unit in app.model.db.rows["units"]:unit["trainSec"]=20.0
	app.model.sides[0]["gold"]=1500;app.model.sides[0]["command"]=10;await settle()
func run() -> void:
	root.size=Vector2i(1280,720);app=preload("res://scenes/Main.tscn").instantiate();root.add_child(app);await settle()
	app.store=EpochStore.new(app.model.db,"user://qa-repair-input-%d/"%Time.get_ticks_usec());app.audio.settings=app.store.settings
	for touch in [false,true]:
		await fixture();var view=app.current_view;var m=app.model;var w=view.world
		check(w.visible_width<w.MAP_RIGHT-w.MAP_LEFT and w.camera_max>w.MAP_LEFT+500,"地图具有真实横向浏览范围")
		check(w.world_to_screen(m.BASE_POSITIONS[0])>0 and w.world_to_screen(m.BASE_POSITIONS[1])>view.size.x,"初始我方位于左侧，敌方在远端")
		for i in range(3):await click(view.unit_cards[i],touch)
		check(m.sides[0]["queue"].size()==3 and view.training_queue.slots[0].order["unitId"]=="U11" and view.training_queue.slots[2].order["unitId"]=="U13","招募输入对应三个兵种图标")
		var order=m.sides[0]["queue"][0];order["duration"]=600;order["remaining"]=300;await settle()
		check(view.training_queue.slots[0].order["remaining"]<300 and not view.training_queue.slots[0].blocked,"首个图标显示进行中的训练")
		if not touch:await capture("01-ally-queue-progress")
		await click(view.item_cards["smoke-bomb"],touch)
		check(view.item_cards["smoke-bomb"].selected and m.sides[0]["activeItems"]["smoke-bomb"]==2,"烟幕选中时高亮且不扣次数")
		await click(view.item_cards["smoke-bomb"],touch)
		check(view.target_action.is_empty(),"重复点击选中道具可取消")
		await click(view.item_cards["smoke-bomb"],touch)
		var gold=float(m.sides[0]["gold"]);var command=float(m.sides[0]["command"])
		await click(view.item_cards["chrono-crate"],touch)
		check(view.target_action.is_empty() and m.sides[0]["activeItems"]["chrono-crate"]==2,"即时道具清除旧选点并准确扣次数")
		check(float(m.sides[0]["gold"])>=gold+65 and float(m.sides[0]["command"])>=command+15,"补给按钮增加真实资源")
		await click(view.item_cards["war-drum"],touch)
		check(m.sides[0]["activeItems"]["war-drum"]==1 and view.item_cards["war-drum"].active_progress>0 and not m.combat.status(m.hero(0),"item-drum").is_empty(),"战鼓按钮产生强化与持续条")
		await click(view.item_cards["smoke-bomb"],touch)
		await drag(Vector2(1100,320),Vector2(100,320),touch)
		check(absf(w.camera_x-w.camera_max)<0.01,"完整拖拽到敌方最右端")
		check(not view.target_action.is_empty() and m.sides[0]["activeItems"]["smoke-bomb"]==2 and m.fields.is_empty(),"拖拽地图不误施放烟幕")
		check(w.world_to_screen(m.BASE_POSITIONS[1])<view.size.x and w.world_to_screen(m.BASE_POSITIONS[0])<0,"右端显示敌方基地，左端基地离开画面")
		if not touch:await capture("02-enemy-target-preview")
		var foe=m.spawn(1,"U12","A1","unit",1200.0);foe["speed"]=0;await settle()
		await tap(Vector2(w.world_to_screen(1200),w.ground-30),touch)
		check(view.target_action.is_empty() and m.sides[0]["activeItems"]["smoke-bomb"]==1 and m.fields.size()==1,"拖拽后选点仅消耗一次")
		check(absf(float(m.fields[0]["x"])-1200)<0.01 and not m.combat.status(foe,"ST03").is_empty(),"滚动后选点转换为正确世界坐标并减速")
		check(view.item_cards["smoke-bomb"].disabled and view.item_cards["smoke-bomb"].cooldown>20 and view.item_cards["smoke-bomb"].active_progress>0,"烟幕同时显示持续效果与冷却")
		await click(view.item_cards["smoke-bomb"],touch)
		check(m.fields.size()==1 and m.sides[0]["activeItems"]["smoke-bomb"]==1,"冷却中点击不再次使用")
		if not touch:await capture("03-smoke-enemy-facing")
		await click(icon(view,"定位我方基地"),touch);check(w.camera_x==w.MAP_LEFT,"定位我方基地按钮")
		await click(icon(view,"定位敌方基地"),touch);check(absf(w.camera_x-w.camera_max)<0.01,"定位敌方基地按钮")
		await click(view.minimap,touch);check(w.camera_x>w.MAP_LEFT and w.tracking=="free","缩略地图点击可定位")
		await click(icon(view,"跟随指挥官"),touch);check(w.tracking=="hero","指挥官跟随模式")
		await drag(Vector2(850,300),Vector2(400,300),touch);check(w.tracking=="free","手动拖动退出跟随模式")
		var camera_before=w.camera_x
		await click(icon(view,"暂停 / Esc"),touch);var tick=m.tick
		await drag(Vector2(850,300),Vector2(400,300),touch)
		check(m.paused and m.tick==tick and w.camera_x==camera_before,"暂停时手势不移动镜头或推进战斗")
		await click(button(view,"保留对局"),touch);check(app.current_view is MenuScreen,"保存退出")
		await click(button(app.current_view,"继续对局"),touch);view=app.current_view;w=view.world
		check(absf(w.camera_x-camera_before)<0.01 and m.sides[0]["activeItems"]["smoke-bomb"]==1 and m.fields.size()==1,"继续对局恢复镜头与道具状态")
	await fixture();var view=app.current_view;var w=view.world;var m=app.model
	await click(view.item_cards["smoke-bomb"])
	var right=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true;right.position=physical(Vector2(600,300));Input.parse_input_event(right);await process_frame
	right=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=false;right.position=physical(Vector2(600,300));Input.parse_input_event(right);await settle()
	check(view.target_action.is_empty() and m.sides[0]["activeItems"]["smoke-bomb"]==2,"战场右键取消不消耗道具")
	await click(view.item_cards["smoke-bomb"],true)
	await pointer(Vector2(700,300),true,true);await pointer(Vector2(700,300),false,true,0,true);await settle()
	check(not view.target_action.is_empty() and m.sides[0]["activeItems"]["smoke-bomb"]==2,"取消的触摸手势不施放道具")
	await click(view.target_cancel,true);check(view.target_action.is_empty(),"触屏返回按钮取消选点")
	await click(view.unit_cards[0]);var pending=m.sides[0]["queue"][0];pending["remaining"]=0
	var blocker=m.spawn(0,"U11","A1","unit",m.spawn_x(0,"U11"));blocker["speed"]=0;await settle()
	check(view.training_queue.slots[0].blocked and view.queue_label.text=="出口堵塞","完工阻挡显示警示与满进度")
	await capture("04-queue-blocked")
	await click(view.training_queue.slots[0]);check(m.paused and is_instance_valid(button(view,"取消")),"点击队列图标打开取消面板")
	await click(button(view,"取消"));check(m.sides[0]["queue"].is_empty(),"图标取消操作实际移除订单")
	view.go_back();await settle()
	for size_ in [Vector2i(1024,576),Vector2i(2400,1080)]:
		root.size=size_;await settle()
		check(Rect2(Vector2.ZERO,view.size).encloses(view.training_queue.get_global_rect()) and Rect2(Vector2.ZERO,view.size).encloses(view.minimap.get_global_rect()),"横屏尺寸下队列与地图完整可见")
		await click(view.item_cards["smoke-bomb"],true)
		await drag(Vector2(1100,320),Vector2(100,320),true)
		check(not view.target_action.is_empty() and m.sides[0]["activeItems"]["smoke-bomb"]==2,"缩放窗口触摸拖拽不施放")
		await click(view.target_cancel,true)
		check(view.target_action.is_empty(),"缩放窗口触摸取消按钮生效")
		await capture("05-layout-%dx%d"%[size_.x,size_.y])
	var file=FileAccess.open(directory+"interaction-repairs.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"mouse_and_touch":true},"\t"));file.close()
	print("REPAIR_INTERACTION ",JSON.stringify({"checks":checks,"failures":failures}));app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
