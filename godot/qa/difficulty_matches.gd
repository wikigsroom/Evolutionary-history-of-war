extends SceneTree
var actions = []
var reports = []
func _initialize() -> void: call_deferred("run")
func submit(m: GameModel, action: Dictionary) -> void:
	var result = m.act(action)
	if result["ok"]: actions.append({"tick":m.tick,"action":action.duplicate(true)})
func player(m: GameModel, strategy: String) -> void:
	var p = m.sides[0]
	var army = m.living(0,false).filter(func(u):return u["kind"]=="unit")
	if p["eraId"] != m.max_era and m.era_cost(0)>0 and float(p["knowledge"])>=m.era_cost(0): submit(m,{"type":"evolve","upgradeId":"R%d%d"%[m.ally_era+1,2 if strategy=="fortify" else 1]})
	if strategy=="fortify" and army.size()>=3 and p["turrets"].is_empty() and float(p["gold"])>200*float(m.db.era(p["eraId"])["costMultiplier"]): submit(m,{"type":"turret","slot":0,"turretId":"TR%d1"%m.ally_era})
	if army.size()>=4 and not m.heavy_unlocked(0) and float(p["gold"])>=m.research_cost(0,"heavy-unlock")+m.unit_cost(0,"U%d1"%m.ally_era): submit(m,{"type":"research","researchId":"heavy-unlock"})
	if p["queue"].size()<3:
		var front=army.filter(func(u):return u["role"]=="front").size()
		var ranged=army.filter(func(u):return u["role"]=="ranged").size()
		var slot=1 if front<maxi(1,ranged) else 2
		if army.size()>4 and m.tick%150==0 and m.heavy_unlocked(0): slot=4
		elif army.size()>3 and m.tick%120==0:slot=3
		var id="U%d%d"%[m.ally_era,slot]
		if float(p["gold"])>=m.unit_cost(0,id):submit(m,{"type":"train","unitId":id})
	var hero=m.hero(0,false)
	if not hero.is_empty():
		var target=m.combat.nearest_enemy(hero)
		if not target.is_empty() and m.combat.distance(hero,target)<400:
			for skill_id in [m.db.get_row("heroes",p["loadout"]["heroId"])["signatureSkillId"]]+p["loadout"]["commonSkillIds"]:
				var row=m.db.get_row("skills",skill_id)
				var x=float(hero["x"]) if row["targetMode"]=="ally_area" else float(target["x"])
				submit(m,{"type":"cast","skillId":skill_id,"x":x,"targetId":int(target["id"])})
	if m.tick>900 and m.tick%600==0:submit(m,{"type":"item","itemId":"war-drum"})
	if float(p["gold"])<30 and m.tick>900:submit(m,{"type":"item","itemId":"chrono-crate"})
func run() -> void:
	var label=OS.get_environment("EPOCH_BALANCE_PHASE")
	if label.is_empty(): label="updated"
	var maximum_seconds = 600
	if not OS.get_environment("EPOCH_BALANCE_SECONDS").is_empty(): maximum_seconds = maxi(60,int(OS.get_environment("EPOCH_BALANCE_SECONDS")))
	for difficulty in ["D01","D02","D03"]:
		var selected = OS.get_environment("EPOCH_BALANCE_DIFFICULTY")
		if not selected.is_empty() and difficulty != selected: continue
		for seed_value in [42571,27183,3107]:
			if not OS.get_environment("EPOCH_BALANCE_SEED").is_empty() and seed_value!=int(OS.get_environment("EPOCH_BALANCE_SEED")): continue
			var m=GameModel.new()
			m.reset_battle({"seed":seed_value,"difficultyId":difficulty,"randomEvents":false})
			actions=[]
			var timeline=[]
			var previous=[1,1]
			var started=Time.get_ticks_msec()
			for i in range(maximum_seconds*m.HZ):
				if m.winner!=-1: break
				if m.tick%30==0:
					player(m,"balanced")
					m.consume_events()
				m.step_tick()
				for side in range(2):
					var age=m.ally_era if side==0 else m.enemy_era
					if age!=previous[side]:
						timeline.append({"side":side,"era":age,"seconds":m.elapsed})
						previous[side]=age
			var report={"difficulty":difficulty,"seed":seed_value,"winner":m.winner,"seconds":m.elapsed,"player_era":m.ally_era,"enemy_era":m.enemy_era,"kills":[m.sides[0]["kills"],m.sides[1]["kills"]],"era_timeline":timeline,"simulation_ms":Time.get_ticks_msec()-started}
			reports.append(report)
			print(JSON.stringify(report))
			m.free()
	var folder=ProjectSettings.globalize_path("res://../output/qa/2026-10-10-balance")
	DirAccess.make_dir_recursive_absolute(folder)
	var file=FileAccess.open(folder+"/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"\t"));file.close()
	quit()
