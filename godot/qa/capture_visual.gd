extends SceneTree

var frames: int = 0
var capture_model: GameModel

func _init() -> void:
	capture_model = GameModel.new()
	root.add_child(capture_model)
	var scene := BattleScreen.new()
	scene.setup(capture_model)
	root.add_child(scene)
	process_frame.connect(_capture)

func _capture() -> void:
	frames += 1
	if frames == 2:
		capture_model.reset_battle()
		for i in range(5):
			capture_model.train_unit(i)
	if frames < 150:
		return
	var texture: ViewportTexture = get_root().get_texture()
	if texture == null:
		print("VISUAL_CAPTURE_FAIL no viewport texture")
		quit(1)
		return
	var image: Image = texture.get_image()
	var err := image.save_png("res://qa/battle-visual.png")
	var battle_view := root.get_child(root.get_child_count() - 1) as BattleScreen
	var report := "units=%d actors=%d queue=%d\\n" % [battle_view.model.units.size(), battle_view.world.actor_nodes.size(), battle_view.model.recruit_queue.size()]
	for unit in battle_view.model.units:
		report += "%s x=%s y=%s state=%s\\n" % [unit["id"], unit["x"], unit["y"], unit["state"]]
	FileAccess.open("res://qa/battle-visual-report.txt", FileAccess.WRITE).store_string(report)
	print("VISUAL_CAPTURE_PASS err=%d size=%dx%d" % [err, image.get_width(), image.get_height()])
	quit(0)
