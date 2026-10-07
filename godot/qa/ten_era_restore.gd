extends SceneTree
var failures=[]
var checks=0
func _initialize() -> void:call_deferred("run")
func expect(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);print("FAIL ",label)
func canonical_state(model: GameModel):
	return JSON.parse_string(JSON.stringify(model.snapshot()))
func run() -> void:
	for age in range(1,6):
		var path="res://qa/fixtures/legacy-age-%d.json"%age
		var data=JSON.parse_string(FileAccess.get_file_as_string(path))
		var m=GameModel.new()
		if not data is Dictionary:expect(false,"Authentic legacy fixture exists age "+str(age));m.free();continue
		var loaded=m.restore(data)
		expect(loaded,"Legacy restore age "+str(age)+" "+m.last_restore_error)
		if loaded:
			var new_era=[1,2,4,6,10][age-1]
			expect(m.sides[0]["eraId"]=="A"+str(new_era) and m.max_era=="A10","Legacy historical era maps correctly "+str(age))
			expect(absf(float(m.hero(0)["hp"])/float(m.hero(0)["maxHp"])-0.6)<0.02,"Legacy hero keeps HP fraction "+str(age))
			expect(m.hero(0)["visualId"]=="H02-A"+str(new_era),"Legacy hero receives era form "+str(age))
			expect(not m.sides[0]["queue"].is_empty() and m.sides[0]["queue"][0]["unitId"]=="U%d2"%new_era,"Legacy paid order keeps original era "+str(age))
			expect(int(m.sides[0]["cooldowns"]["HS02"])==int(data["sides"][0]["cooldowns"]["HS02"]),"Legacy cooldown cannot reset "+str(age))
			expect(float(m.base(0)["maxHp"])==float(m.db.era(m.sides[0]["eraId"])["baseHp"]),"Legacy base uses current HP scale "+str(age))
			m.step_ticks(60)
			expect(m.winner==-1 and m.projectiles.is_empty(),"Migrated in-flight volley settles "+str(age))
		m.free()
	var model=GameModel.new();model.reset_battle({"aiEnabled":false,"startingEraId":"A8"})
	model.environment.spawn_event("plane",800)
	var store=EpochStore.new(model.db,"user://qa-ten-era-save-%d/"%Time.get_ticks_usec())
	expect(store.save_match(model.snapshot()),"Version two snapshot is saved to disk")
	var saved=store.load_match()
	expect(not saved.is_empty(),"Continue button sees version two disk snapshot")
	var resumed=GameModel.new()
	expect(resumed.restore(saved),"Version two disk snapshot is playable")
	expect(canonical_state(resumed)==canonical_state(model),"Disk restore retains all simulation state")
	model.step_ticks(80);resumed.step_ticks(80)
	expect(canonical_state(resumed)==canonical_state(model),"Resumed event executes deterministically once")
	store.clear_match();model.free();resumed.free()
	FileAccess.open("res://../output/qa/ten-eras/restore-regression.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures},"\t"))
	print("TEN ERA RESTORE ",checks-failures.size(),"/",checks)
	quit(1 if not failures.is_empty() else 0)
