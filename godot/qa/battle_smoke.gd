extends SceneTree

var elapsed := 0.0

func _init() -> void:
	var model := GameModel.new()
	root.add_child(model)
	model.reset_battle()
	var view := BattleScreen.new()
	view.setup(model)
	root.add_child(view)
	model.ally_xp = 999.0
	model.evolve_ally()
	model.train_unit(0)
	model.use_item("war_drum")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	elapsed += 1.0 / 60.0
	if elapsed > 0.45:
		print("BATTLE_VIEW_SMOKE_PASS")
		quit(0)
