extends SceneTree

var app
var directory = ""
var captures = []

func _initialize() -> void: call_deferred("run")

func settle() -> void:
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw

func capture(name: String) -> void:
	await settle()
	var file = directory.path_join(name+".png")
	var error = root.get_texture().get_image().save_png(file)
	if error != OK: push_error("Cannot capture README screen: "+name);quit(1);return
	captures.append(name+".png")

func find_button(node: Node, text: String):
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found = find_button(child,text)
		if found != null: return found
	return null

func run() -> void:
	directory = OS.get_environment("EPOCH_RUSH_README_MEDIA")
	if directory.is_empty(): directory = ProjectSettings.globalize_path("res://../docs/media/v0.7.0")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280,720)
	app = preload("res://scenes/Main.tscn").instantiate();root.add_child(app)
	await settle()
	app.store = EpochStore.new(app.model.db,"user://qa-readme-v070/")
	app.audio.settings = app.store.settings;app.audio.apply_settings()
	for pair in [["home","menu-home"],["campaign","menu-campaign"],["loadout","menu-loadout"],["encyclopedia","menu-codex"],["settings","menu-settings"]]:
		app.show_menu(pair[0]);await settle()
		if pair[0] == "encyclopedia":
			var modern = find_button(app.current_view,"现代机械化")
			if modern != null: modern.pressed.emit()
		await capture(pair[1])
	var report = {"version":ProjectSettings.get_setting("application/config/version"),"viewport":[1280,720],
		"source":"Native Godot UI rendered from shipped Windows embedded PCK", "screenshots":captures}
	FileAccess.open(directory.path_join("capture-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("README_MEDIA_CAPTURE ",JSON.stringify(report))
	app.queue_free();await process_frame;quit()
