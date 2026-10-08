extends RefCounted

var model
var actions = []
var next_decision = 0
var allow_evolution = true
var allow_raid = true
var recruited = 0

func attach(simulation, evolve: bool = true, raid: bool = true) -> void:
	model = simulation
	allow_evolution = evolve
	allow_raid = raid
	next_decision = 0
	recruited = 0
	actions = []

func dispatch(action: Dictionary) -> bool:
	action["side"] = 0
	var before = {"era": model.sides[0]["eraId"], "gold": model.sides[0]["gold"], "xp": model.sides[0]["knowledge"]}
	var result = model.act(action)
	if result["ok"]:
		actions.append({"tick":model.tick,"action":action.duplicate(true),"before":before,"after":{"era":model.sides[0]["eraId"],"gold":model.sides[0]["gold"],"xp":model.sides[0]["knowledge"]}})
	return bool(result["ok"])

func update() -> void:
	if model.winner != -1 or model.paused or model.tick < next_decision:
		return
	next_decision = model.tick + 15
	var player = model.sides[0]
	var army = model.living(0,false).filter(func(u):return u["kind"]=="unit")
	var enemies = model.living(1,false)
	var front = army.filter(func(u):return u["role"]=="front")
	var ranged = army.filter(func(u):return u["role"]=="ranged")
	var support = army.filter(func(u):return u["role"]=="support")
	# Pay for heavy research up front, then reserve real income for the first
	# heavy unit instead of spending every new coin on another cheap recruit.
	if not model.heavy_unlocked(0) and float(player["gold"])>=model.research_cost(0,"heavy-unlock"):
		dispatch({"type":"research","researchId":"heavy-unlock"})
	if allow_evolution and player["eraId"] != model.max_era and model.era_cost(0)>0 and float(player["knowledge"])>=model.era_cost(0):
		dispatch({"type":"evolve","upgradeId":"R%d1"%(model.ally_era+1)})
	var hero = model.hero(0,false)
	if not hero.is_empty() and not enemies.is_empty():
		var target = enemies.reduce(func(a,b):return a if float(a["x"])<float(b["x"]) else b)
		if absf(float(target["x"])-float(hero["x"]))<460:
			var signature = model.db.get_row("heroes",player["loadout"]["heroId"])["signatureSkillId"]
			dispatch({"type":"cast","skillId":signature,"x":float(target["x"]),"targetId":int(target["id"])})
			for skill in player["loadout"]["commonSkillIds"]:
				dispatch({"type":"cast","skillId":skill,"x":float(target["x"]),"targetId":int(target["id"])})
		if army.size()>=3 and model.tick>=22*30 and absf(float(target["x"])-float(hero["x"]))<350:
			dispatch({"type":"item","itemId":"war-drum"})
		if enemies.size()>=3 and float(target["x"])<850 and model.tick>=30*30:
			dispatch({"type":"item","itemId":"smoke-bomb","x":float(target["x"])+80})
		var raid_cost = float(model.db.age_special(player["eraId"])["cost"])
		if allow_raid and enemies.size()>=3 and float(player["knowledge"])>=raid_cost+(model.era_cost(0)*0.45 if allow_evolution else 0.0):
			dispatch({"type":"ageSpecial","x":float(target["x"])+75})
	if not player["queue"].is_empty() and model.tick>=6*30:
		dispatch({"type":"item","itemId":"chrono-crate"})
	if player["queue"].size()>=3 or model.population(0)>=27:
		return
	var slots = model.db.unit_slots(player["eraId"])
	if army.size()>=3 and not model.heavy_unlocked(0) and float(player["gold"])>=model.research_cost(0,"heavy-unlock")+model.unit_cost(0,slots[0]["id"]):
		dispatch({"type":"research","researchId":"heavy-unlock"})
	var chosen = 0 if front.size()<maxi(1,ranged.size()) else 1
	if recruited == 0:
		chosen = 0
	elif recruited == 1:
		chosen = 1
	elif recruited == 2 and model.heavy_unlocked(0):
		chosen = 3
		if float(player["gold"])<model.unit_cost(0,slots[3]["id"]):
			return
	if army.size()>=3:
		if support.size()==0:
			chosen=4
		elif model.heavy_unlocked(0) and recruited%5==3:
			chosen=3
		elif recruited%4==2:
			chosen=2
	if float(player["gold"])>=model.unit_cost(0,slots[chosen]["id"]):
		if dispatch({"type":"train","unitId":slots[chosen]["id"]}):
			recruited+=1
	elif float(player["gold"])>=model.unit_cost(0,slots[0]["id"]):
		if dispatch({"type":"train","unitId":slots[0]["id"]}):
			recruited+=1

func battle_state() -> Dictionary:
	return {"tick":model.tick,"elapsed":model.elapsed,"winner":model.winner,"eras":[model.sides[0]["eraId"],model.sides[1]["eraId"]],"gold":[model.sides[0]["gold"],model.sides[1]["gold"]],"xp":[model.sides[0]["knowledge"],model.sides[1]["knowledge"]],"living":model.living(-1,false).size(),"kills":[model.sides[0]["kills"],model.sides[1]["kills"]],"base_hp":[model.base(0)["hp"],model.base(1)["hp"]],"heavy_unlocked":model.heavy_unlocked(0),"player_units":model.living(0,false).filter(func(u):return u["kind"]=="unit").map(func(u):return u["contentId"])}
