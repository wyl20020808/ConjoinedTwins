extends SceneTree
const Run = preload("res://scripts/road_run.gd")
const NoThreads = preload("res://tests/fixtures/no_threads_run.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1
func _initialize() -> void: call_deferred("verify")
func verify() -> void:
	# 操作区角落和偏前后位置均可充能，且保留跳跃高度和真实绳路限制。
	for y in [31.0, 45.0, 60.0, 79.0, 89.0]:
		var gate := Run.ChargeGate.make_tutorial()
		Run.ChargeGate.advance(gate, PackedVector2Array([Vector2(-54, y), Vector2(54, y)]), PackedFloat32Array([28,28]), 108.0 / Run.LINK_LIMIT, true, 0.8)
		check(gate.open, "充能绿区纵深 y=%.0f 无需对准中心" % y)
	var plate := Run.SyncPlates.make_tutorial()
	Run.SyncPlates.advance(plate, Vector2(-69,290), Vector2(69,290), true, true, 0.35)
	check(plate.open, "踏板边缘向外 1.2 米仍能检测")
	# 小缺口位于旧 5 点采样间隙；全线段检测必须拒绝。
	var gaps: Array[Rect2] = [Rect2(-10,88,20,28)]
	check(not Run.Surfaces.supported_sweep(Vector2(0,-32), Vector2(0,298), 16, gaps), "连续支撑检查不漏过短矩形缺口")
	for role in [0,1]:
		var run = Run.new(false)
		run.retry()
		run.install_block({"hazards": [{"kind":"road_gap", "rect":gaps[0]}, {"kind":"cargo", "rect":Rect2(30,88,40,28)}], "rewards":[]}, 0, "small-gap")
		var points := [Vector2(0,100), Vector2(-24,0)]
		run.a.position = points[role]
		run.b.position = points[1-role]
		run.last_support[role] = Vector2(0,70)
		run.rope.reset(run.a.position, run.b.position)
		run.begin_fall(role, points[0])
		for tick in range(480):
			if run.state != "rescue": break
			var pressed := tick % 10 == 0
			run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, pressed if role == 1 else false, pressed if role == 0 else false)
		check(run.state == "running" and run.rescue_count == 1, "角色 %d 从货箱旁短缺口救起" % role)
		for tick in range(120): run.step(Run.FIXED_STEP)
		check(run.state == "running" and run.ground_support[role], "角色 %d 救起后自动推进 1 秒不再坠落 state=%s a=%s b=%s" % [role,run.state,run.a.position,run.b.position])
		run.dispose()
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.dispose()
	game.run = NoThreads.new(true,true)
	game.run.charge_tutorial = true
	game.run.seed_value = 4242
	game.run.retry()
	var hash_before: int = game.run.sync_hash()
	var started := Time.get_ticks_msec()
	var polls := 0
	var saw_progress := false
	var ready := false
	for poll in range(10000):
		polls += 1
		ready = game.prepare_game_frame()
		game.update_ui()
		var progress: float = game.run.startup_progress()
		saw_progress = saw_progress or (progress > 0 and progress < 1 and game.loading_box.visible)
		if ready: break
	check(ready and saw_progress and not game.loading_box.visible, "开局真实加载进度结束后隐藏")
	check(game.run.sync_hash() == hash_before and game.run.elapsed == 0, "加载期间不消费模拟时间、不推进角色")
	check(game.run.async_preload_tasks.size() == 4 and game.run.async_preload_order.is_empty(), "出发前四段全部完成证明")
	print("STARTUP polls=",polls," wall_ms=",Time.get_ticks_msec()-started)
	game.run.retry()
	check(game.run.async_startup_pending and game.run.startup_progress() == 0, "重开清空旧进度重新加载")
	game.run.pause()
	game.prepare_game_frame()
	check(game.run.async_preload_tasks.is_empty(), "加载中暂停不继续生成")
	game.run.pause()
	# 临近终点已经没有可生成段落，不能因总任务数为零卡在加载页。
	game.run.cancel_generation()
	game.run.next_segment = int(ceil(game.run.finish_distance() / Run.Templates.SEGMENT))
	game.run.async_startup_pending = true
	check(game.prepare_game_frame() and not game.run.async_startup_pending, "临近终点空加载窗口正常结束")
	game.queue_free()
	await process_frame
	print("INTERACTION_LOADING_RESCUE failures=",failures)
	quit(1 if failures else 0)
