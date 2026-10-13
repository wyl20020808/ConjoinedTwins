extends SceneTree

# 生产场景运行截图：沿已证明路线推进，每遇到一种新障碍在其前方拍一张。
# 用法：Godot --path . -s res://tests/playfix_capture.gd -- <输出目录> [关卡 0-2]
const Templates = preload("res://scripts/road_templates.gd")
var game
var folder := "res://build-tools/playfix-20261013/shots"

func _initialize() -> void:
	var args: Array = OS.get_cmdline_user_args()
	if args.size() > 0: folder = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	call_deferred("capture", int(args[1]) if args.size() > 1 else 0)

func shot(name: String) -> void:
	game.sync_view()
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(folder + "/" + name + ".png")
	print("CAPTURE ", name, " ", error, " d=", snappedf(game.run.distance / 20.0, 0.1))

func capture(level: int) -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var run = game.run
	await shot("L%d-00-start" % level)
	run.level_index = level
	game.primary_action()
	var seen := {}
	var count := 0
	for tick in range(120 * 110):
		while run.async_thread != null and run.async_thread.is_alive(): OS.delay_msec(1)
		var input: Array = Templates.existing_route_input(run)
		run.step(1.0 / 120, input[0], input[1], input[2], input[3])
		if run.state != "running": break
		for segment in run.route_segments:
			var route: String = segment.block.route
			# 进入该段 2.2 秒后拍摄：预警已出现、障碍在前方中距离。
			if seen.has(route) or run.total_distance() < segment.base + run.speed() * 2.2: continue
			seen[route] = true
			count += 1
			await shot("L%d-%02d-%s" % [level, count, route])
	await shot("L%d-99-%s" % [level, run.state])
	print("END state=", run.state, " reason=", run.reason, " routes=", seen.keys())
	game.queue_free()
	await process_frame
	quit(0)
