extends SceneTree
var reports = []
var actions = []
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
	var directory=OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	if directory.is_empty():directory=ProjectSettings.globalize_path("res://../output/qa/ten-eras/full-matches/")
	if not directory.ends_with("/"):directory+="/"
	DirAccess.make_dir_recursive_absolute(directory)
	for specification in [[42571,"balanced","", "H01"],[27183,"fortify","","H03"],[3107,"race","","H01"],[48711,"balanced","M01","H01"],[98173,"balanced","M06","H04"],[31597,"race","M15","H05"],[51373,"balanced","M19","H02"],[81731,"fortify","M20","H06"]]:
		var selected=OS.get_environment("EPOCH_RUSH_QA_MISSION")
		if not selected.is_empty() and specification[2]!=selected:continue
		var m=GameModel.new()
		var config={"seed":specification[0],"difficultyId":"D02","missionId":specification[2],"mode":"standard" if specification[2]=="" else "campaign","loadout":m.db.default_loadout(specification[3])}
		m.reset_battle(config);actions=[]
		var peak=0;var overlaps=0;var route_jumps=0;var eras=[m.ally_era];var era_timeline=[]
		var last_eras=[m.ally_era,m.enemy_era]
		var started=Time.get_ticks_msec()
		var maximum_ticks=(int(m.db.rules["overtime"]["burnStartsSec"])+125)*m.HZ
		for i in range(maximum_ticks):
			if m.winner!=-1:break
			if m.tick%30==0:
				player(m,specification[1]);m.consume_events()
				if not eras.has(m.ally_era):eras.append(m.ally_era)
			var charging=m.living(-1,false).filter(func(u):return u.has("charge")).map(func(u):return u["id"])
			m.step_tick()
			for side in range(2):
				var current_era=m.ally_era if side==0 else m.enemy_era
				if current_era!=last_eras[side]:
					era_timeline.append({"side":side,"from":last_eras[side],"to":current_era,"seconds":m.elapsed,"remainingXp":m.sides[side]["knowledge"]})
					last_eras[side]=current_era
			var fighters=m.combat.grounded();peak=maxi(peak,fighters.size())
			fighters.sort_custom(func(a,b):return float(a["x"])<float(b["x"]))
			for index in range(1,fighters.size()):
				var a=fighters[index-1];var b=fighters[index]
				if float(b["x"])-float(a["x"])<float(a["radius"])+float(b["radius"])+3.9:overlaps+=1
			for actor in m.living(-1,false):
				if actor.has("charge") or charging.has(actor["id"]) or int(actor["hitAt"])==m.tick:continue
				if absf(float(actor["x"])-float(actor["previousX"]))>float(actor["speed"])*1.7/30.0+m.BODY_GAP+0.1:
					route_jumps+=1
					if OS.get_environment("EPOCH_RUSH_QA_TRACE")=="1":
						print("ROUTE_JUMP ",JSON.stringify({"tick":m.tick,"contentId":actor["contentId"],"side":actor["side"],"kind":actor["kind"],"bornTick":actor["bornTick"],"phase":actor["phase"],"x":actor["x"],"previousX":actor["previousX"],"speed":actor["speed"],"yield":actor.get("yield",{}),"charge":actor.get("charge",{})}))
						m.free();quit();return
		var report={"seed":specification[0],"strategy":specification[1],"mission":specification[2],"winner":m.winner,"seconds":m.elapsed,"eras":eras,"enemy_era":m.enemy_era,"eraTimeline":era_timeline,"kills":[m.sides[0]["kills"],m.sides[1]["kills"]],"base_hp":[m.ally_base_hp,m.enemy_base_hp],"peak":peak,"ground_overlaps":overlaps,"normal_route_jumps":route_jumps,"simulation_ms":Time.get_ticks_msec()-started,"actions":actions.size(),"occupancy_checked_every_tick":true}
		reports.append(report);print(JSON.stringify(report))
		var file=FileAccess.open(directory+"replay-%s-%d.json"%[specification[1],int(specification[0])],FileAccess.WRITE)
		file.store_string(JSON.stringify({"config":m.config,"actions":actions,"result":report},"\t",true,true));file.close();m.free()
	var file=FileAccess.open(directory+"full-battles.json",FileAccess.WRITE);file.store_string(JSON.stringify(reports,"\t"));file.close()
	quit(0 if reports.all(func(r):return r["winner"]>=0 and r["ground_overlaps"]==0 and r["normal_route_jumps"]==0) else 1)
