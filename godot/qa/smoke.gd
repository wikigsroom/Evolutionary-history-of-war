extends SceneTree

func _init() -> void:
	var model := GameModel.new()
	root.add_child(model)
	model.reset_battle()
	_assert(model.ally_era == 1 and model.enemy_era == 1, "初始时代应独立且同为 I")
	var enemy_before: int = model.enemy_era
	model.ally_xp = 999.0
	_assert(model.evolve_ally(), "我方时代升级应成功")
	_assert(model.ally_era == 2, "我方应进入 II 时代")
	_assert(model.enemy_era == enemy_before, "我方升级不能自动升级敌方")
	_assert(model.train_unit(0), "单位应能加入攻击排队")
	_assert(model.recruit_queue.size() == 1, "攻击排队长度应为 1")
	model.step(1.0)
	_assert(model.units.size() > 0, "生产计时后应生成我方单位")
	var charges_before: int = model.item_charges["war_drum"]
	_assert(model.use_item("war_drum"), "主动道具应能触发")
	_assert(model.item_charges["war_drum"] == charges_before - 1, "道具消耗应减少一格")
	model.enemy_evolve_timer = 0.01
	model.step(0.1)
	_assert(model.enemy_era == 2, "敌方应按自己的计时器独立升级")
	print("GODOT_SMOKE_PASS ally_era=%d enemy_era=%d units=%d" % [model.ally_era, model.enemy_era, model.units.size()])
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("GODOT_SMOKE_FAIL: " + message)
		quit(1)
