extends SceneTree

var app
var frame = 0
var destination = ""

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	destination = OS.get_environment("EPOCH_MARKETING_OUTPUT")
	DirAccess.make_dir_recursive_absolute(destination)
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	app = preload("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.store = EpochStore.new(app.model.db,"user://marketing-probe-20261008/")
	app.audio.settings = app.store.settings
	app.audio.apply_settings()
	app.show_menu("home")
	process_frame.connect(update)

func update() -> void:
	frame += 1
	if frame == 35:
		await RenderingServer.frame_post_draw
		var image = root.get_texture().get_image()
		image.save_png(destination+"/probe-menu.png")
		FileAccess.open(destination+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"frame":frame,"texture_size":[image.get_width(),image.get_height()],"window":[root.size.x,root.size.y],"native_movie":true},"\t"))
	if frame >= 65:
		quit()
