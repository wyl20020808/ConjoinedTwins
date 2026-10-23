extends SceneTree
# 实时播放第二章魔龙入场：把两人放到开战线前，等场地加载完后越线触发，之后正常游玩（可直接接着打魔龙）。
# 用法：Godot --path . --resolution 1600x900 --script res://build-tools/dragon/play_dragon.gd
# 环境变量 DRAGON_PLAY_QUIT=秒数 时，播放这么多秒后自动退出（只看入场时用，例如 18）。
const Boss = preload("res://scripts/journey_boss.gd")
var game

func _initialize() -> void:
	call_deferred("play")

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

func play() -> void:
	game = load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading = true
	game.start_chapter = 1
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.set_physics_process(false)
	var run = game.run
	run.level_index = 1
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
	# 停在冒烟的巢穴前 1.5 秒，再越线触发入场。
	for n in range(90): await process_frame
	place(boss.arena + 320)
	game.set_physics_process(true)
	var quit_after := OS.get_environment("DRAGON_PLAY_QUIT")
	if not quit_after.is_empty():
		await create_timer(float(quit_after)).timeout
		game.queue_free()
		for n in range(4): await process_frame
		quit(0)
