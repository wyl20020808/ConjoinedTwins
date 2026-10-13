extends SceneTree

# 随机关卡截图：沿已证明路线推进，在摆锤段、每隔几秒和金币飞行中各拍一张，供人工查看。
# 用法：Godot --path . -s res://tests/random_capture.gd -- <输出目录> [关卡 0-2]
const Templates = preload("res://scripts/road_templates.gd")
var game
var folder := "res://build-tools/random-20261013/shots"

func _initialize() -> void:
	var args: Array = OS.get_cmdline_user_args()
	if args.size() > 0: folder = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	call_deferred("capture", int(args[1]) if args.size() > 1 else 0)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(folder + "/" + name + ".png")
	print("CAPTURE ", name, " ", error, " d=", snappedf(game.run.distance / 20.0, 0.1))

func capture(level: int) -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var run = game.run
	for n in range(20): await process_frame
	await shot("L%d-00-start" % level)
	run.level_index = level
	game.primary_action()
	var hammer_shots := 0
	var flyer_shots := 0
	for tick in range(60 * 110):
		while run.async_thread != null and run.async_thread.is_alive(): OS.delay_msec(1)
		var input: Array = Templates.existing_route_input(run)
		var previous: String = run.state
		var before := {"heights": run.heights.duplicate(), "shield": run.shield, "shield_uses": run.shield_uses, "locked": game.locked_threats()}
		run.step(1.0 / 60, input[0], input[1], input[2], input[3])
		game.play_events(before, previous)
		game.frame_delta = 1.0 / 60
		game.sync_view()
		await process_frame
		if run.state != "running": break
		var near_hammer := false
		for i in range(run.kinds.size()):
			if run.kinds[i] == "hammer" and run.obstacles[i].position.y - run.distance < 380 and run.obstacles[i].position.y - run.distance > 150: near_hammer = true
		if near_hammer and hammer_shots < 4 and tick % 12 == 0:
			hammer_shots += 1
			await shot("L%d-hammer-%d" % [level, hammer_shots])
		if game.flying >= 3 and flyer_shots < 2 and tick % 30 == 0:
			flyer_shots += 1
			await shot("L%d-coins-%d" % [level, flyer_shots])
		if tick % 600 == 300: await shot("L%d-t%03d" % [level, tick / 60])
	await shot("L%d-99-%s" % [level, run.state])
	print("END state=", run.state, " reason=", run.reason)
	game.queue_free()
	await process_frame
	quit(0)
