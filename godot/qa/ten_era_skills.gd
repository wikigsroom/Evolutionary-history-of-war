extends SceneTree

var checks=[]
var failures=0
var cases=[]
func _initialize() -> void: call_deferred("run")
func expect(value: bool,label: String,detail=null) -> void:
	checks.append({"passed":value,"name":label,"detail":detail})
	if not value: failures+=1;print("FAIL ",label," ",detail)
func fixture(age: int,identity: String) -> GameModel:
	var m=GameModel.new()
	m.reset_battle({"startingEraId":"A"+str(age),"aiEnabled":false,"heroEnabled":false,"randomEvents":false,"loadout":m.db.default_loadout(identity)})
	var hero=m.spawn(0,identity,"A"+str(age),"hero",600.0);hero["speed"]=0.0;hero["nextAttack"]=100000
	m.sides[0]["command"]=100.0
	return m
func stand(m: GameModel,side: int,x: float) -> Dictionary:
	var entity=m.spawn(side,"U%d1"%m.ally_era,m.sides[side]["eraId"],"unit",x)
	entity["speed"]=0.0;entity["nextAttack"]=100000
	return entity
func run() -> void:
	for age in range(1,11):
		for identity in ["H01","H02","H03","H04","H05","H06"]:
			var m=fixture(age,identity)
			var hero=m.hero(0);var skill=m.db.get_row("heroes",identity)["signatureSkillId"]
			var form=m.db.hero_form(identity,"A"+str(age));var variant=form["skillVariant"]
			var enemy=stand(m,1,730.0 if identity=="H01" else 835.0)
			enemy["hp"]=enemy["maxHp"]*1000;enemy["maxHp"]=enemy["hp"]
			var ally=stand(m,0,520.0);ally["hp"]=ally["maxHp"]*0.55
			hero["hp"]=hero["maxHp"]*0.55
			var original_hp=float(enemy["hp"]);var original_gold=float(m.sides[0]["gold"])
			var target_x=835.0 if identity in ["H02","H05"] else 700.0 if identity=="H04" else 600.0
			var result=m.act({"type":"cast","skillId":skill,"side":0,"x":target_x,"targetId":enemy["id"]})
			expect(result["ok"],"Cast "+form["id"],result)
			m.step_ticks(2)
			var detail={"form":form["id"],"skill":form["signatureName"],"attack":hero["attack"],"maxHp":hero["maxHp"]}
			match identity:
				"H01":
					m.step_ticks(19)
					expect(float(enemy["hp"])<original_hp,"Charge actually hits "+form["id"])
					expect(float(hero["x"])>600.0 and not hero.has("charge"),"Charge ends in legal occupied lane "+form["id"])
					detail["displacement"]=float(enemy["x"])-730.0
				"H02":
					var releases=m.pending_events.filter(func(e):return e["type"]=="release" and e["data"].get("sourceId")==hero["id"])
					expect(not releases.is_empty() and releases[0]["data"]["weaponId"]==variant["projectileWeapon"],"Volley uses era weapon "+form["id"])
					var moving=float(m.db.get_row("weapons",variant["projectileWeapon"]).get("projectileSpeed",0))>0.0
					expect((not m.projectiles.is_empty() and float(enemy["hp"])==original_hp) if moving else float(enemy["hp"])<original_hp,"Volley distinguishes projectile travel from instant beam "+form["id"])
					m.step_ticks(100)
					expect(float(enemy["hp"])<original_hp,"Volley deals damage "+form["id"])
					detail["damage"]=original_hp-float(enemy["hp"])
				"H03":
					var shield=0.0
					for batch in ally["shields"]:shield+=float(batch["hp"])
					expect(shield>0 and shield<=float(ally["maxHp"])*0.20001,"Shield skill is finite "+form["id"],shield)
					expect(age==1 or m.combat.bonus(ally,"projectileReduction")>0,"Era cover applies "+form["id"])
					detail["shieldRatio"]=shield/float(ally["maxHp"])
				"H04":
					var summons=m.living(0,false).filter(func(u):return u["kind"]=="summon")
					expect(summons.size()==1,"One legal era turret is deployed "+form["id"])
					if not summons.is_empty():
						var turret=summons[0]
						expect(turret["weaponId"]==variant["summonWeapon"] and turret["visualId"]=="SUM-A"+str(age),"Summon art and weapon evolve "+form["id"])
						detail["range"]=turret["range"];detail["lifetime"]=int(turret["expiresAt"])/30.0
						m.step_ticks(int(turret["expiresAt"])+1)
						expect(float(turret["hp"])==0.0,"Summon expires without infinite stack "+form["id"])
				"H05":
					expect(m.fields.size()==1 and float(m.fields[0]["radius"])==float(variant["fieldRadius"]),"Field uses era radius "+form["id"])
					m.step_ticks(31)
					expect(float(enemy["hp"])<original_hp and m.combat.bonus(enemy,"slow")>0,"Field pulse damages and slows "+form["id"])
					detail["duration"]=variant["fieldDuration"];detail["radius"]=variant["fieldRadius"]
				"H06":
					var difference=float(m.sides[0]["gold"])-original_gold
					expect(difference>=35.0*float(m.db.era(hero["eraId"])["costMultiplier"])-1.0,"Supply scales with era economy "+form["id"],difference)
					expect(float(ally["hp"])/float(ally["maxHp"])<=0.70001,"Supply heal shares recovery cap "+form["id"])
					detail["gold"]=difference
			cases.append(detail)
			m.free()
	var original=fixture(1,"H03")
	var saved=original.snapshot();var hp_before=original.ally_base_hp
	saved["environment"]["scene"]["variant"]=12
	expect(not original.restore(saved) and original.ally_base_hp==hp_before and int(original.environment.scene["variant"]) in [1,2,3],"Invalid environmental save is rejected without partial mutation")
	var foe=stand(original,1,800);var target=stand(original,0,700)
	target["shields"]=[{"hp":0.5,"until":100}]
	original.combat.hit(foe,target,10,"physical",{});original.combat.apply_hits()
	expect(target["shields"].is_empty(),"Fractional residual shield is fully broken")
	var resting=original.hero(0);resting["garrisoned"]=true;resting["hp"]=resting["maxHp"]*0.3
	original.step_ticks(120)
	expect(float(resting["hp"])/float(resting["maxHp"])>=0.3999 and float(resting["hp"])/float(resting["maxHp"])<=0.4001,"Garrisoned commander heals in bounded one-second pulses")
	original.free()
	var folder=ProjectSettings.globalize_path("res://../output/qa/ten-eras")
	FileAccess.open(folder+"/skills-regression.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":failures==0,"checks":checks,"forms":cases},"\t"))
	print("TEN ERA SKILLS ",checks.size()-failures,"/",checks.size())
	quit(1 if failures else 0)
