extends SceneTree

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var failures=[]
	var db=EpochData.new()
	var version=String(ProjectSettings.get_setting("application/config/version"))
	if version!="0.7.0":failures.append("Wrong embedded application version")
	for pair in [["eras",10],["units",50],["hero-evolutions",60],["missions",20]]:
		if db.rows[pair[0]].size()!=pair[1]:failures.append("Wrong embedded table count: "+pair[0])
	var source=OS.get_environment("EPOCH_RUSH_QA_SOURCE_DATA")
	var checked=[]
	for name in DirAccess.get_files_at(source):
		if not name.ends_with(".json"):continue
		var embedded=FileAccess.get_file_as_bytes("res://assets/data/"+name)
		var original=FileAccess.get_file_as_bytes(source+"/"+name)
		if embedded!=original:failures.append("Embedded data differs: "+name)
		checked.append(name)
	var textures=0
	for actor in db.animations.values():
		for key in ["path","enemyPath"]:
			var texture=load("res://assets/"+actor[key])
			if not texture is Texture2D:failures.append("Embedded atlas missing: "+actor[key])
			elif texture.get_width()!=int(actor["frameWidth"])*int(actor.get("columns",6)) or texture.get_height()!=int(actor["frameHeight"])*int(actor.get("rows",5)):failures.append("Embedded atlas dimensions: "+actor[key])
			textures+=1
	var out=OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	DirAccess.make_dir_recursive_absolute(out)
	var report={"passed":failures.is_empty(),"version":version,"executable":OS.get_executable_path(),"checkedData":checked,"atlasesLoaded":textures,"failures":failures}
	FileAccess.open(out+"/embedded-content.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
