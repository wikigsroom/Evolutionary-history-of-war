extends SceneTree

func _initialize() -> void:
	var files = {}
	var failed = false
	for path in ["scripts/net/net_client.gdc", "scripts/ui/online_menu.gdc", ".godot/imported/resource-rounded.woff2-402ae7f15b29f5fe9d2f60f56ad514cf.fontdata", ".godot/imported/smiley.woff2-88d7ccea732b7120fb320f70da68e2fe.fontdata"]:
		var bytes = FileAccess.get_file_as_bytes("res://" + path)
		if bytes.is_empty(): failed = true
		var hash = HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
		files[path] = hash.finish().hex_encode()
	var output = OS.get_environment("EPOCH_QA_OUTPUT").path_join("windows-online-content.json")
	var file = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":not failed,"version":ProjectSettings.get_setting("application/config/version"),"files":files},"  ")); file.close()
	print("WINDOWS_PACK_CONTRACT ", not failed, " ", files.size(), " resources")
	quit(1 if failed else 0)
