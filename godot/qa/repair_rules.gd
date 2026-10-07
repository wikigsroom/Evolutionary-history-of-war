extends SceneTree
var checks=0
var failures=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func fresh() -> GameModel:
	var m=GameModel.new();m.reset_battle({"heroEnabled":false,"aiEnabled":false});return m
func same(a,b) -> bool:
	if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<0.00000001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in range(a.size()):
			if not same(a[i],b[i]):return false
		return true
	return a==b
func run() -> void:
	for row in EpochData.new().rows["units"]:
		for side in range(2):
			var m=fresh();var sign_=1.0 if side==0 else -1.0
			var unit=m.spawn(side,row["id"],row["eraId"],"unit",200.0 if side==0 else 1400.0)
			var origin=float(unit["x"]);m.step_ticks(3)
			check((float(unit["x"])-origin)*sign_>0 and float(unit["facing"])==sign_,row["id"]+"正常行进方向"+str(side))
			check(float(unit["runDistance"])>0,row["id"]+"行走路程"+str(side));m.free()
	for side in range(2):
		for mode in ["moving", "stationary", "legacy"]:
			var line=fresh();var direction=1.0 if side==0 else -1.0
			var archer=line.spawn(side,"U22","A2","unit",650.0 if side==0 else 950.0)
			var infantry=line.spawn(side,"U21","A2","unit",float(archer["x"])-direction*(float(archer["radius"])+float(line.db.profile("U21")["radius"])+line.BODY_GAP))
			var target=line.spawn(1-side,"U21","A2","unit",float(archer["x"])+direction*(float(archer["radius"])+float(line.db.profile("U21")["radius"])+float(archer["range"])-5.0))
			target["speed"]=0.0;target["hp"]=10000.0;target["maxHp"]=10000.0
			if mode=="stationary":archer["speed"]=0.0
			line.step_ticks(1)
			if mode=="stationary":
				check(not archer.has("yield"),"固定远程单位不被强迫让位"+str(side))
				check(line.combat.distance(archer,infantry)>=line.BODY_GAP-0.01,"固定远程单位保持阻挡"+str(side))
			else:
				check(archer.has("yield"),"远程让位路线产生"+mode+str(side))
				if archer.has("yield"):
					if mode=="legacy":archer["yield"].erase("duration")
					var bounded=true
					for i in range(30):
						var previous_x=float(archer["x"]);line.step_ticks(1)
						bounded=bounded and absf(float(archer["x"])-previous_x)<=float(archer["speed"])/30.0+0.001
					check(bounded,"让位每帧位移遵守本兵种速度"+mode+str(side))
					check(float(archer["facing"])==-direction,"让位朝向与实际移动一致"+mode+str(side))
			line.free()
	for side in range(2):
		var m=fresh();var unit=m.spawn(side,"H01","A1","hero",400 if side==0 else 1200)
		m.spawn(side,"U11","A1","unit",m.spawn_x(side,"U11"))["speed"]=0
		check(m.act({"type":"stance","side":side,"stance":"retreat"})["ok"],"撤退指令"+str(side))
		var duration=int(unit["yield"]["duration"]);m.step_ticks(3)
		check(float(unit["facing"])==(-1.0 if side==0 else 1.0) and float(unit["runDistance"])>0,"撤退朝向与步幅"+str(side))
		m.step_ticks(duration+2)
		check(unit["garrisoned"] and not unit.has("yield"),"堵塞出口仍能驻防恢复"+str(side))
		m.act({"type":"stance","side":side,"stance":"rush"});m.step_ticks(2)
		check(not unit["garrisoned"] and float(unit["facing"])==(1.0 if side==0 else -1.0),"再出征恢复进攻方向"+str(side));m.free()
	var blocked=fresh();var support=blocked.spawn(0,"U12","A1","unit",650.0);support["speed"]=0
	var occupant=blocked.spawn(0,"U11","A1","unit",500.0);occupant["speed"]=0
	support["yield"]={"from":650.0,"to":500.0,"at":0,"duration":15};blocked.step_ticks(15)
	check(support.has("yield") and absf(float(support["x"])-500)<0.001,"让位终点被占时不跳到远处")
	blocked.combat.kill(occupant,true);blocked.step_ticks(1)
	check(not support.has("yield") and absf(float(support["x"])-500)<0.001,"让位空位恢复后正常归位");blocked.free()
	var deployment=fresh();deployment.sides[0]["loadout"]=deployment.db.default_loadout("H04");deployment.sides[0]["command"]=110
	var engineer=deployment.spawn(0,"H04","A1","hero",600.0)
	engineer["yield"]={"from":600.0,"to":500.0,"at":0,"duration":30};engineer["hitAt"]=0;engineer["staggerUntil"]=20
	check(deployment.act({"type":"cast","skillId":"HS04","x":700.0})["ok"],"让位期间可部署炮台")
	var deployed=deployment.living(0,false).filter(func(u):return u["kind"]=="summon")[0]
	check(not deployed.has("yield") and not deployed.has("charge") and deployed["hitAt"]==-100 and deployed["staggerUntil"]==0,"炮台不继承指挥官行进受击或硬直")
	deployment.step_ticks(30)
	check(absf(float(deployed["x"])-700.0)<0.001 and deployed["runDistance"]==0.0,"固定炮台始终停留在部署位置")
	deployment.free()
	var m=fresh();var ally=m.spawn(0,"U11","A1","unit",500.0);var enemy=m.spawn(1,"U11","A1","unit",600.0)
	var results=EpochStore.new(m.db,"user://qa-results-%d/"%Time.get_ticks_usec())
	var result_config=results.next_match_config("campaign","M01")
	check(results.record_result(result_config,2,{"elapsed":180.0,"kills":5}),"平局可提交结算")
	check(results.profile["draws"]==1 and results.profile["wins"]==0 and results.profile["losses"]==0,"平局单独计数不误记失败")
	check(results.profile["cleared"].is_empty(),"平局不发首通解锁")
	check(not results.record_result(result_config,2) and results.profile["draws"]==1,"平局账本防止重复计数")
	results.profile.erase("draws");results.save_profile()
	var old_results=EpochStore.new(m.db,results.directory)
	check(old_results.profile["draws"]==0,"旧档缺失平局字段安全补默认值")
	ally["speed"]=0;enemy["speed"]=0;enemy["hp"]=5000;enemy["maxHp"]=5000
	m.sides[0]["gold"]=1000;m.sides[0]["command"]=10;m.act({"type":"train","unitId":"U11"})
	var initial=m.snapshot()
	for value in [-1.0,1601.0,NAN,INF]:
		check(not m.act({"type":"item","itemId":"smoke-bomb","x":value})["ok"],"非法烟幕目标拒绝")
	check(m.sides[0]["activeItems"]["smoke-bomb"]==2 and m.fields.is_empty(),"非法目标不消耗次数或创建区域")
	m.combat.release(ally,enemy);var raw=float(m.pending_hits[-1]["raw"]);m.pending_hits=[]
	var remaining=int(m.sides[0]["queue"][0]["remaining"])
	check(m.act({"type":"item","itemId":"war-drum"})["ok"],"战鼓可用")
	m.combat.release(ally,enemy)
	check(float(m.pending_hits[-1]["raw"])>raw*1.17 and not m.combat.status(ally,"item-drum").is_empty(),"战鼓真实提高攻击")
	check(int(m.sides[0]["queue"][0]["remaining"])<remaining,"战鼓真实推进训练")
	var charges=int(m.sides[0]["activeItems"]["war-drum"])
	check(not m.act({"type":"item","itemId":"war-drum"})["ok"] and int(m.sides[0]["activeItems"]["war-drum"])==charges,"冷却拒绝重复扣次数")
	var gold=float(m.sides[0]["gold"]);var command=float(m.sides[0]["command"])
	check(m.act({"type":"item","itemId":"chrono-crate"})["ok"],"补给可用")
	check(float(m.sides[0]["gold"])==gold+65 and float(m.sides[0]["command"])==command+15,"补给资源准确增加")
	check(int(m.sides[0]["queue"][0]["progressUsed"])<=floori(float(m.sides[0]["queue"][0]["duration"])*0.5),"道具连用保持训练推进上限")
	check(m.act({"type":"item","itemId":"smoke-bomb","x":600.0})["ok"],"烟幕可用")
	m.step_ticks(1)
	check(absf(float(m.combat.status(enemy,"ST03")["slow"])-0.35)<0.001,"烟幕真实减速敌军")
	var storage=EpochStore.new(m.db,"user://qa-repairs/");storage.save_match(m.snapshot())
	var resumed=fresh();check(resumed.restore(storage.load_match()),"道具状态从磁盘恢复")
	check(same(resumed.sides[0]["activeItems"],m.sides[0]["activeItems"]) and same(resumed.fields,m.fields) and same(resumed.sides[0]["itemCooldowns"],m.sides[0]["itemCooldowns"]),"次数冷却与烟幕区域恢复一致")
	m.set_paused(true);var saved=m.snapshot()
	for action in [{"type":"item","itemId":"chrono-crate"},{"type":"ageSpecial","x":600},{"type":"train","unitId":"U11"},{"type":"stance","stance":"rush"},{"type":"cast","skillId":"S01"}]:
		check(not m.act(action)["ok"],"暂停时战斗指令拒绝"+action["type"])
	check(m.snapshot()==saved,"暂停输入不改变战斗状态")
	m.set_paused(false);m.step_ticks(149)
	check(m.fields.is_empty() and m.combat.status(enemy,"ST03").is_empty(),"烟幕五秒到期移除区域和减速")
	var legacy=initial.duplicate(true)
	for actor in legacy["entities"]:actor.erase("facing")
	var old=fresh();check(old.restore(legacy),"旧版无朝向字段存档仍可恢复")
	old.step_ticks(1);check(float(old.entity_by_id(int(enemy["id"]))["facing"])==-1.0,"旧存档敌军重新确定朝向")
	for fault in ["cooldowns","queue","actor"]:
		var damaged=initial.duplicate(true)
		if fault=="cooldowns":damaged["sides"][0]["cooldowns"]=[]
		elif fault=="queue":damaged["sides"][0]["queue"][0].erase("duration")
		else:damaged["entities"][-1].erase("bornTick")
		check(not old.restore(damaged),"损坏的"+fault+"存档拒绝恢复")
	storage.clear_match()
	for node in [m,resumed,old]:node.free()
	var file=FileAccess.open("res://../output/qa/godot-fixes/rules-repairs.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));file.close()
	print("REPAIR_RULES ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
