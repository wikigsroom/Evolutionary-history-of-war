extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var original_environment = OS.get_environment("EPOCH_ONLINE_URL")
	OS.set_environment("EPOCH_ONLINE_URL", "")
	var directory = "user://qa-fixed-endpoint-%d/" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var loadout = EpochData.new().default_loadout("H04")
	var file = FileAccess.open(directory + "online-session.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"endpoint":"http://127.0.0.1:9", "loadout":loadout, "match_id":"", "pending":{}}))
	file.close()
	var client = EpochNetClient.new()
	client.session_directory = directory
	root.add_child(client)
	await process_frame
	var checks = [
		{"name":"Official endpoint overrides a legacy editable preference after upgrading", "passed":client.endpoint == EpochNetClient.DEFAULT_ENDPOINT},
		{"name":"Connection editing API has been removed", "passed":not client.has_method("set_endpoint")},
		{"name":"Existing loadout survives endpoint migration", "passed":client.loadout == loadout},
		{"name":"Offline start without an active match does not request a connection", "passed":not client.service_requested and not client.authenticated}
	]
	client.update_loadout(loadout)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(directory + "online-session.json"))
	checks.append({"name":"Saved preferences have no editable endpoint", "passed":saved is Dictionary and not saved.has("endpoint")})
	var failures = checks.filter(func(row):return not row["passed"])
	file = FileAccess.open(OS.get_environment("EPOCH_QA_OUTPUT").trim_suffix("/") + "/endpoint-lock.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures}, "  "))
	file.close()
	client.queue_free()
	await process_frame
	OS.set_environment("EPOCH_ONLINE_URL", original_environment)
	print("ENDPOINT_LOCK ", checks.size(), " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
