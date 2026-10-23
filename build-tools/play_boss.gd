extends "res://build-tools/dragon/play_dragon.gd"
# 复用生产场景和魔龙预览的加载、入场流程；用户参数为章节编号 1～3。
func play() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["1", "2", "3"]:
		push_error("Expected chapter number 1, 2 or 3")
		quit(1)
		return
	var chapter := int(args[0]) - 1
	game = load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading = true
	game.start_chapter = chapter
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.set_physics_process(false)
	var run = game.run
	run.level_index = chapter
	run.retry()
	run.state = "running"
	for gate in run.charge_gates:
		gate.open = true
		gate.opened_at = -10.0
	run.select_charge_gate()
	var boss: Dictionary = Boss.boss(run)
	place(boss.arena + 200)
	run.step(run.FIXED_STEP)
	await settle()
	game.sync_view()
	for n in range(90): await process_frame
	place(boss.arena + 320)
	game.set_physics_process(true)
	print("BOSS_PLAY_READY chapter=", chapter + 1, " species=", boss.get("species", "root"))
	var quit_after := OS.get_environment("DRAGON_PLAY_QUIT")
	if not quit_after.is_empty():
		await create_timer(float(quit_after)).timeout
		game.queue_free()
		for n in range(4): await process_frame
		quit(0)
