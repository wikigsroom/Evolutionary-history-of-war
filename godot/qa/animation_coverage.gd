extends SceneTree
var checks = 0
var failures = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); push_error(description)
func run() -> void:
	var m = GameModel.new(); root.add_child(m)
	m.reset_battle({"heroEnabled":false,"aiEnabled":false})
	for row in m.db.rows["units"] + m.db.rows["heroes"]:
		var id = String(row["id"]); var kind = "hero" if id.begins_with("H") else "unit"
		var actor = m.spawn(0,id,row.get("eraId","A1"),kind,500.0)
		var view = preload("res://scenes/UnitView.tscn").instantiate(); root.add_child(view); view.configure(m,actor,0.8)
		check(view.sprite.texture != null and view.sprite.texture.get_size() == Vector2(float(view.metadata["frameWidth"])*6,float(view.metadata["frameHeight"])*5), id + " 动作图集尺寸与加载")
		check(view.metadata["review"] == "accepted" and view.metadata["clips"].size() == 5, id + " 五动作来源已验收")
		actor["releasedAt"] = -100; actor["hitAt"] = -100; actor["phase"] = "walk"; actor["runDistance"] = 0.0
		view.refresh(515.0,false,100.0); var first = view.sprite.frame
		actor["runDistance"] = 10.0; view.refresh(515.0,false,100.0)
		check(view.metadata["clips"]["walk"].map(func(value):return int(value)).has(view.sprite.frame) and view.sprite.frame != first,id + " 行走按路程推进")
		actor["phase"] = "windup"; actor["attackStartedAt"] = 90; actor["windup"] = 12
		view.refresh(515.0,false,100.0)
		check(view.metadata["clips"]["attack"].map(func(value):return int(value)).has(view.sprite.frame), id + " 蓄力动作来自攻击图集")
		actor["phase"] = "recover"; actor["releasedAt"] = 100; view.refresh(515.0,false,106.0)
		check(view.sprite.frame == 16,id + " 释放恢复按同一tick推进")
		actor["phase"] = "idle";actor["releasedAt"] = -100;actor["hitAt"] = 100;actor["hitDirection"] = -1.0;view.refresh(515.0,false,102.0)
		check(view.metadata["clips"]["hurt"].map(func(value):return int(value)).has(view.sprite.frame), id + " 受击图集覆盖")
		actor["hitAt"] = -100;actor["phase"] = "dead";actor["deathAt"] = 100;view.refresh(515.0,false,130.0)
		check(view.sprite.frame == 29 and view.modulate.a == 0.0,id + " 死亡播放与淡出")
		actor["phase"] = "idle";actor["side"] = 1;actor["facing"]=-1.0;view.configure(m,actor,0.8)
		check(view.sprite.texture.resource_path.ends_with(id+"-enemy.png") and view.sprite.flip_h,id + " 敌方配色图集正确朝左")
		view.refresh(515.0,true,100.0)
		var foot = view.sprite.position.y + float(view.metadata["frameHeight"])*float(view.metadata["anchor"][1])*view.visual_scale
		check(absf(foot) < 0.001,id + " 脚底锚点与地面一致")
		for direction in [-1.0,1.0]:
			actor["facing"]=direction
			for phase in ["idle","walk","windup","recover","dead"]:
				actor["phase"]=phase;view.refresh(515.0,true,100.0)
				check(view.sprite.flip_h==(direction<0.0),id+" 朝向在"+phase+"阶段一致")
			var anchor_x=1.0-float(view.metadata["anchor"][0]) if direction<0 else float(view.metadata["anchor"][0])
			check(absf(view.sprite.position.x+float(view.metadata["frameWidth"])*anchor_x*view.visual_scale)<0.001,id+" 镜像保持脚底水平锚点")
		view.free()
	m.free()
	var file = FileAccess.open("res://../output/qa/godot-polish/animation-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"actors":31,"checks":checks,"failures":failures},"\t"));file.close()
	print("ANIMATION_COVERAGE ",JSON.stringify({"actors":31,"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
