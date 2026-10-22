extends SceneTree
# 开场运镜逐时刻取景：真实生产场景、按生产流程逐帧推进（场景未就绪时模拟照常暂停），
# 在指定时刻截图，并统计因载入而等待的帧数。截完自动退出，不留窗口。
# 用法：Godot --path . --resolution 1280x720 --audio-driver Dummy --script res://build-tools/capture_opening.gd
# 输出目录取环境变量 OPENING_CAPTURE_DIR（默认 user://opening/）；OPENING_CAPTURE_MOMENTS 为逗号分隔的秒数。
const MOMENTS := [0.6, 1.8, 3.0, 4.0, 5.2, 6.4, 7.6, 8.8, 10.0, 11.2, 12.4, 13.4, 14.2, 15.0, 15.8, 16.6]
var game
var out := ""

func _initialize() -> void:
	call_deferred("capture")

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	var error := root.get_texture().get_image().save_png(path)
	print("OPENING_CAPTURE ", path, " error=", error, " t=", snappedf(game.run.opening_age(), 0.01), " waits=", game.preparation_waits)

func capture() -> void:
	out = OS.get_environment("OPENING_CAPTURE_DIR")
	if out.is_empty(): out = ProjectSettings.globalize_path("user://opening")
	DirAccess.make_dir_recursive_absolute(out)
	var moments: Array = MOMENTS
	if not OS.get_environment("OPENING_CAPTURE_MOMENTS").is_empty():
		moments = Array(OS.get_environment("OPENING_CAPTURE_MOMENTS").split(",")).map(func(x): return float(x))
	Engine.max_fps = 60
	game = load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading = true
	game.opening_enabled = true
	game.start_chapter = 0
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	var run = game.run
	print("OPENING_START opening_at=", run.opening_at, " state=", run.state, " waits=", game.preparation_waits)
	var waits_before: int = game.preparation_waits
	game.apply_journey_primary()
	for moment in moments:
		while run.opening_age() < moment and run.state == "running":
			await process_frame
		await shot("opening_%02d_t%.1f" % [moments.find(moment) + 1, moment])
	print("OPENING_DONE waits=", game.preparation_waits - waits_before, " age=", run.opening_age(), " active=", run.opening_active())
	game.queue_free()
	for n in range(4): await process_frame
	quit(0)
