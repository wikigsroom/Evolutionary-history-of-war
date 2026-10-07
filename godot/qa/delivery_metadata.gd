extends SceneTree
func _initialize() -> void:
	var output=OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	var license_file=FileAccess.open(output+"/Godot-LICENSE.txt",FileAccess.WRITE)
	license_file.store_string(Engine.get_license_text());license_file.close()
	var third_party=FileAccess.open(output+"/Godot-third-party-notices.txt",FileAccess.WRITE)
	third_party.store_string(JSON.stringify(Engine.get_copyright_info(),"\t")+"\n"+JSON.stringify(Engine.get_license_info(),"\t"));third_party.close()
	quit()
