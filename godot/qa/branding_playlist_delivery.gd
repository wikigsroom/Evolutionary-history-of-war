extends SceneTree

var app
var failures: Array = []
var checks = 0
var directory = ""
var screens: Array = []
var assets: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func settle() -> void:
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw

func check_import(path: String) -> void:
	var config = ConfigFile.new()
	check(config.load(path+".import") == OK, "Imported resource exists: "+path)
	var imported: String = config.get_value("remap", "path", "")
	var bytes = FileAccess.get_file_as_bytes(imported)
	var source_root = OS.get_environment("EPOCH_RUSH_QA_SOURCE_PROJECT")
	if not source_root.is_empty():
		var original = FileAccess.get_file_as_bytes(source_root.path_join(imported.trim_prefix("res://")))
		check(not bytes.is_empty() and bytes == original, "Embedded resource equals approved source import: "+path)
	assets.append({"resource":path, "import":imported, "bytes":bytes.size()})

func run() -> void:
	directory = OS.get_environment("EPOCH_RUSH_QA_OUTPUT")
	if directory.is_empty(): directory = ProjectSettings.globalize_path("res://../output/qa/v0.7.1/branding/source")
	DirAccess.make_dir_recursive_absolute(directory)
	check(ProjectSettings.get_setting("application/config/version") == "0.7.1", "Application version 0.7.1")
	app = preload("res://scenes/Main.tscn").instantiate(); root.add_child(app)
	app.store = EpochStore.new(app.model.db,"user://qa-branding-%d/"%Time.get_ticks_usec())
	app.audio.settings = app.store.settings; app.audio.apply_settings()
	check(app.audio.playlist_tracks.size() == 4, "Four embedded playlist tracks")
	for key in app.audio.playlist_tracks:
		var meta: Dictionary = app.audio.catalog["music"][key]
		var stream: AudioStreamOggVorbis = load(meta["path"])
		check(stream != null and absf(stream.get_length()-float(meta["duration"])) < .05, "Full-length embedded Yourset song: "+key)
		check_import(meta["path"])
	for path in ["res://assets/ui/brand/game-logo.png","res://assets/ui/pixel/app-icon.png", "res://assets/ui/pixel/launcher-foreground.png", "res://assets/ui/pixel/launcher-background.png", "res://assets/ui/pixel/launcher-monochrome.png"]:
		check_import(path)
	var icon = PixelTheme.texture("res://assets/ui/pixel/app-icon.png").get_image()
	if icon.is_compressed(): icon.decompress()
	check(not icon.detect_alpha(), "Knight application icon is fully opaque")
	var logo = PixelTheme.texture("res://assets/ui/brand/game-logo.png").get_image()
	if logo.is_compressed(): logo.decompress()
	check(logo.detect_alpha() and logo.get_pixel(0,0).a == 0, "Wordmark has a real transparent background")
	check(logo.get_size() == Vector2i(1340,431), "Approved wordmark crop and padding")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		for page in ["home","campaign","loadout","encyclopedia","settings"]:
			app.show_menu(page); await settle()
			var header_logo = app.current_view.find_child("HeaderLogo",true,false)
			var knight = app.current_view.find_child("BrandKnight",true,false)
			check(header_logo != null and knight != null, "Latest branding visible in "+page)
			var header_rect: Rect2 = header_logo.get_global_rect()
			var nav: HBoxContainer = app.current_view.get_child(1)
			check(header_rect.end.x < nav.get_global_rect().position.x, "Logo and navigation do not overlap: "+page+str(dimensions))
			check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(header_rect), "Wordmark remains inside viewport: "+page)
			if page in ["home","settings"]:
				var name = "%s-%dx%d.png"%[page,dimensions.x,dimensions.y]
				check(root.get_texture().get_image().save_png(directory.path_join(name)) == OK, "Rendered screenshot: "+name)
				screens.append(name)
	app.show_battle({"aiEnabled":false,"randomEvents":false,"seed":771,"startingEraId":"A4"})
	app.model.paused = true; await settle()
	var before = app.audio.current_music
	check(app.audio.playlist_tracks.has(before), "Battle uses the same Yourset playlist")
	app.show_menu("home"); await settle()
	check(app.audio.current_music == before, "Returning to camp continues the current song")
	var report = {"passed":failures.is_empty(),"version":"0.7.1","checks":checks,"failures":failures,
		"executable":OS.get_executable_path(),"screenshots":screens,"resources":assets,"playlist":app.audio.playlist_tracks}
	FileAccess.open(directory.path_join("branding-playlist.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BRANDING_PLAYLIST ",JSON.stringify({"passed":report["passed"],"checks":checks,"failures":failures}))
	app.queue_free(); await process_frame; await process_frame; quit(0 if failures.is_empty() else 1)
