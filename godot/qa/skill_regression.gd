extends SceneTree
var errors = []
var checks = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: errors.append(message); push_error(message)
func fixture(hero_id: String="H01") -> GameModel:
	var m=GameModel.new();m.reset_battle({"aiEnabled":false,"heroEnabled":false})
	m.sides[0]["loadout"]=m.db.default_loadout(hero_id)
	m.spawn(0,hero_id,"A1","hero",600.0)["speed"]=0.0
	m.sides[0]["command"]=110.0
	return m
func foe(m: GameModel,x: float) -> Dictionary:
	var entity=m.spawn(1,"U11","A1","unit",x);entity["speed"]=0.0;entity["hp"]=1000.0;entity["maxHp"]=1000.0;return entity
func run() -> void:
	var m=fixture()
	m.sides[0]["loadout"]["commonSkillIds"]=["S04","S05"]
	var enemy=foe(m,850.0)
	check(m.abilities.cast(0,"S04",850.0,int(enemy["id"]))["ok"],"破甲弹可释放")
	m.step_ticks(2)
	check(float(enemy["hp"])==1000.0 and m.combat.status(enemy,"ST01").is_empty(),"破甲弹未抵达前无伤害或状态")
	m.step_ticks(10)
	check(float(enemy["hp"])<1000.0 and not m.combat.status(enemy,"ST01").is_empty(),"破甲弹抵达后施加状态")
	var n=fixture("H05");n.sides[0]["loadout"]["commonSkillIds"]=["S06","S07"]
	var targets=[foe(n,840),foe(n,895),foe(n,950)]
	n.abilities.cast(0,"S06",895)
	n.step_ticks(1)
	check(targets.all(func(t):return not n.combat.status(t,"ST05").is_empty()),"共振网状态在伤害后生效且不被同次伤害消费")
	n.abilities.cast(0,"S07",840);n.step_ticks(1)
	check(n.pending_events.any(func(e):return e["type"]=="chain") or targets.all(func(t):return n.combat.status(t,"ST05").is_empty()),"能量命中消费导电状态")
	var r=fixture("H05");r.sides[0]["loadout"]["specializationId"]="P053"
	foe(r,800);foe(r,860)
	r.abilities.cast(0,"HS05",830)
	r.step_ticks(200)
	check(absf(float(r.sides[0]["command"])-78.0)<0.001,"裂隙场只返还一次8军令")
	var burn=fixture();burn.sides[0]["loadout"]["commonSkillIds"]=["S08","S02"]
	var burned=foe(burn,920)
	burn.abilities.cast(0,"S08",920);burn.step_ticks(1)
	var immediate=float(burned["hp"]);burn.step_ticks(120)
	var per_tick=burn.combat.damage_for(burn.hero(0),burned,12.0,"blast",{"skillId":"S08","canDamageBase":true})
	check(absf(float(burned["hp"])-(immediate-4*per_tick))<0.01,"燃烧到期前完整结算四次")
	burn.abilities.add_status(burned,"ST03",3,{"slow":0.45})
	burn.abilities.add_status(burned,"ST03",6,{"slow":0.2})
	check(burn.combat.status(burned,"ST03")["slow"]==0.45,"更弱减速只刷新持续时间")
	burn.abilities.add_status(burned,"ST08",3,{"attackSpeedBonus":0.12,"sourceId":11});burn.abilities.add_status(burned,"ST08",3,{"attackSpeedBonus":0.14,"sourceId":12})
	check(absf(burn.combat.bonus(burned,"attackSpeedBonus")-0.14)<0.001,"光环攻速取最强值")
	var capped=fixture("H05")
	var six=[]
	for i in range(8):six.append(foe(capped,800+i*50))
	var source=capped.hero(0)
	for target in six:capped.combat.hit(source,target,10,"energy",{"castId":900,"skillId":"HS05","canDamageBase":false})
	capped.combat.apply_hits()
	check(six.filter(func(t):return float(t["hp"])<1000.0).size()==6,"同次技能总目标上限6")
	var save=fixture();var broken=save.snapshot();broken.erase("config")
	check(not save.restore(broken),"损坏存档拒绝加载")
	var invalid=save.db.default_loadout();invalid["talentIds"]=["T13","T21","T22"]
	check(not save.db.valid_loadout(invalid),"天赋要求同路线前层")
	var storage=EpochStore.new(save.db,"user://qa-skill-storage/")
	storage.save_match(save.snapshot()); storage.save_match(save.snapshot())
	check(not storage.load_match().is_empty(),"主存档与备份可读取")
	storage.clear_match()
	check(storage.load_match().is_empty() and not FileAccess.file_exists(storage.directory+"match.json.bak"),"结算清除存档及备份，旧对局不能复活")
	var instant=fixture("H05");instant.sides[0]["loadout"]["commonSkillIds"]=["S07","S06"];instant.hero(0)["nextAttack"]=100000
	var immediate_target=foe(instant,850.0)
	instant.abilities.cast(0,"S07",850.0)
	storage.save_match(instant.snapshot())
	var resumed=GameModel.new()
	check(not instant.scheduled.is_empty() and resumed.restore(storage.load_match()) and not resumed.scheduled.is_empty(),"释放后已排程的技能随磁盘存档恢复")
	instant.step_ticks(1);resumed.step_ticks(2)
	check(float(immediate_target["hp"])<1000.0 and float(resumed.entity_by_id(int(immediate_target["id"]))["hp"])==float(immediate_target["hp"]) and resumed.pending_hits.is_empty(),"恢复后已排程的技能恰好生效一次")
	var queued=fixture("H05");queued.hero(0)["nextAttack"]=100000
	var queued_target=foe(queued,850.0)
	queued.combat.hit(queued.hero(0),queued_target,54.0,"energy",{"skillId":"S07","canDamageBase":true})
	storage.save_match(queued.snapshot())
	var resumed_queue=GameModel.new()
	check(resumed_queue.restore(storage.load_match()) and not resumed_queue.pending_hits.is_empty(),"内部待结算命中随磁盘存档恢复")
	queued.step_ticks(1);resumed_queue.step_ticks(2)
	check(float(queued_target["hp"])<1000.0 and float(resumed_queue.entity_by_id(int(queued_target["id"]))["hp"])==float(queued_target["hp"]) and resumed_queue.pending_hits.is_empty(),"恢复后内部待结算命中恰好生效一次")
	storage.clear_match()
	var tower=GameModel.new();tower.reset_battle({"heroEnabled":false,"aiEnabled":false});tower.sides[0]["gold"]=1000.0
	var tower_target=tower.spawn(1,"U11","A1","unit",300.0);tower_target["speed"]=0.0
	tower.act({"type":"turret","turretId":"TR12","slot":0});tower.sides[0]["turrets"][0]["nextAttack"]=0;tower.step_ticks(1)
	check(tower.projectiles.size()==1 and absf(float(tower.projectiles[0]["originX"])-48.0)<0.001 and float(tower.projectiles[0]["muzzleY"])==260.0,"炮塔从实际挂点发射")
	check(float(tower.projectiles[0]["targetHeight"])<float(tower.projectiles[0]["muzzleY"]) and float(tower_target["hp"])==float(tower_target["maxHp"]),"高位炮塔弹道面向受击点，飞行时不提前扣血")
	for t in [m,n,r,burn,capped,save,instant,resumed,queued,resumed_queue,tower]:t.free()
	var file=FileAccess.open("res://../output/qa/godot-polish/skill-checks.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":errors},"\t"));file.close()
	print("SKILL_REGRESSION ",JSON.stringify({"checks":checks,"failures":errors}))
	quit(0 if errors.is_empty() else 1)
