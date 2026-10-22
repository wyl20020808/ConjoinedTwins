extends SceneTree
# Boss 入场动画逐时刻取景：真实生产场景里触发开战，按入场时间轴在关键时刻截图，检查运镜、破土、咆哮与黑边标题。
# 只通过 build-tools/capture_hidden.py 在隐藏窗口中运行：
#   python build-tools/capture_hidden.py res://build-tools/boss/capture_intro.gd
# 输出目录取环境变量 BOSS_CAPTURE_DIR（默认 user://boss-intro/），不写入工程。
const Boss = preload("res://scripts/journey_boss.gd")
const MOMENTS := [1.2, 2.45, 3.4, 4.4, 5.4, 6.2, 7.0, 7.9, 10.0, 12.4]
var game
var out := ""

func _initialize() -> void:
	call_deferred("capture")

func place(y: float) -> void:
	var run = game.run
	run.a.position = Vector2(-42, y)
	run.b.position = Vector2(42, y)
	run.distance = y
	run.rope.reset(run.a.position, run.b.position)

func settle() -> void:
	var waits := 0
	while waits < 3000:
		var ready: bool = game.prepare_journey_frame()
		if ready and game.chunk_jobs.is_empty() and game.chunk_assets.pending.is_empty() and game.chunk_assets.active.is_empty(): break
		waits += 1
		await process_frame

func shot(name: String) -> void:
	await settle()
	game.sync_view()
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	var error := root.get_texture().get_image().save_png(path)
	var boss: Dictionary = Boss.boss(game.run)
	print("INTRO_CAPTURE ", path, " error=", error, " phase=", boss.phase, " t=", snappedf(game.run.elapsed-boss.state_at, 0.01))

func capture() -> void:
	out = OS.get_environment("BOSS_CAPTURE_DIR")
	if out.is_empty(): out = ProjectSettings.globalize_path("user://boss-intro")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading = true
	game.start_chapter = 0
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.set_physics_process(false)
	var run = game.run
	run.random_seed = false
	run.seed_value = 20261021
	run.retry()
	run.state = "running"
	for gate in run.charge_gates:
		gate.open = true
		gate.opened_at = -10.0
	run.select_charge_gate()
	var boss: Dictionary = Boss.boss(run)
	place(boss.arena + 200)
	run.step(run.FIXED_STEP)
	await shot("intro_00_dormant")
	place(boss.arena + 320)
	run.step(run.FIXED_STEP)
	var start: float = boss.state_at
	# 每渲染一帧推进 1/60 秒模拟，粒子按真实帧时间运动，与正常游玩的节奏一致。
	Engine.max_fps = 60
	for moment in MOMENTS:
		while run.elapsed - start < moment - 0.0001:
			run.step(run.FIXED_STEP)
			run.step(run.FIXED_STEP)
			game.sync_view()
			await process_frame
		await shot("intro_%02d_t%.1f" % [MOMENTS.find(moment) + 1, moment])
	game.queue_free()
	for n in range(4): await process_frame
	quit(0)
