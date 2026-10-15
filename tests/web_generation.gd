extends SceneTree
const Run = preload("res://scripts/road_run.gd")
const NoThreads = preload("res://tests/fixtures/no_threads_run.gd")
const Job = preload("res://scripts/road_generation_job.gd")
var checks := 0
var failures := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func _initialize() -> void:
	call_deferred("verify")
func verify() -> void:
	# 同一批候选分别走原 worker 和不同切片大小，完整 block 必须完全一致。
	for route in ["steam", "stone_ball", "narrow", "charge_cargo", "charge_sync_relay"]:
		var generator = Run.Templates.new()
		generator.reset(4242)
		var candidates: Array = []
		for index in range(3): candidates.append(generator.candidate_of(route, 0))
		var request := {"epoch": 1, "number": 0, "difficulty": "普通", "level": 0, "candidates": candidates}
		var expected: Dictionary = Run.verification_worker(request, Run.Templates.Cancellation.new())
		for budget in [1, 32, 256]:
			var job = Job.new(request, Run.Templates.Cancellation.new())
			var polls := 0
			while not job.done and polls < 100000:
				job.advance(budget)
				polls += 1
			check("%s 切片 %d 与原 worker 完整布局一致" % [route, budget], job.done and var_to_str(job.result.block) == var_to_str(expected.block) and job.result.canceled == expected.canceled)
			job.dispose()
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.dispose()
	game.run = NoThreads.new(true, true)
	var run = game.run
	run.charge_tutorial = true
	run.lockstep = true
	run.seed_value = 4242
	run.retry()
	var peer = Run.new(true, true)
	peer.charge_tutorial = true
	peer.lockstep = true
	peer.seed_value = 4242
	peer.retry()
	# 首段包含真实障碍，确保测试不因随机抽到纯机关段而误判。
	for instance in [run, peer]:
		instance.generator.bag = ["stone_ball"]
		instance.generator.bag_level = 0
	var equal := true
	var illegal := false
	var seen_hazards := 0
	var seen_views := 0
	var sources: Array = []
	var opened: Array = []
	var segments := 0
	for tick in range(3600):
		var input: Array = Run.Templates.existing_route_input(run)
		if run.charge_gate.active and not run.charge_gate.open and run.charge_gate.id == "tutorial":
			input = [Vector2.ZERO, Vector2.ZERO, false, false]
			if run.distance >= 60:
				input[0] = Vector2.LEFT if run.a.position.x > -64 else Vector2.ZERO
				input[1] = Vector2.RIGHT if run.b.position.x < 64 else Vector2.ZERO
		illegal = illegal or not Run.Templates.keyboard_legal(input[0]) or not Run.Templates.keyboard_legal(input[1])
		for instance in [run, peer]: instance.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
		equal = equal and run.sync_hash() == peer.sync_hash()
		game.sync_view()
		seen_hazards = maxi(seen_hazards, run.obstacles.size())
		seen_views = maxi(seen_views, game.hazard_views.size())
		segments = maxi(segments, run.next_segment)
		for event in run.async_events:
			if not sources.has(event.source): sources.append(event.source)
		for event in run.gate_events:
			if event.event == "opened" and not opened.has(event.id): opened.append(event.id)
		if run.state != "running" or (segments >= 4 and run.total_distance() > 1500): break
	check("无线程路径未创建 Thread", run.async_thread == null)
	check("合法输入完成充能门和踏板教学", not illegal and opened.has("tutorial") and opened.has("sync_tutorial"))
	check("开门后至少生成四段真实地图", segments >= 4 and seen_hazards > 0)
	check("生产场景为障碍创建展示节点", seen_views > 0)
	check("未因线程不可用安装空路", sources.has("proven") and not sources.has("safe_thread_unavailable"))
	check("无线程与原生 worker 逐帧指纹一致", equal)
	check("通过首个障碍后保持运行且未吸收碰撞", run.state == "running" and run.total_distance() > 1500 and run.shield_uses == 0)
	print("WEB_GENERATION opened=",opened," segments=",segments," hazards=",seen_hazards," views=",seen_views," sources=",sources," equal=",equal," state=",run.state," reason=",run.reason)
	peer.dispose()
	run.retry()
	check("重试取消任务并重置教学", run.cooperative_job == null and run.async_thread == null and run.next_segment == 0 and run.charge_gates.size() == 2)
	var canceled = NoThreads.new(true, true)
	check("无教学入口创建可暂停任务", canceled.cooperative_job != null)
	var pending = canceled.cooperative_job
	canceled.dispose()
	check("dispose 清理未完成验证克隆", canceled.cooperative_job == null and pending.done and pending.validation == null)
	# 本地单机也必须走同一条无线程路径，不能只在 lockstep 下恢复障碍。
	run.lockstep = false
	run.seed_value = 4242
	run.retry()
	run.generator.bag = ["stone_ball"]
	run.generator.bag_level = 0
	for tick in range(3600):
		var input: Array = Run.Templates.existing_route_input(run)
		if run.charge_gate.active and not run.charge_gate.open and run.charge_gate.id == "tutorial":
			input = [Vector2.ZERO, Vector2.ZERO, false, false]
			if run.distance >= 60:
				input[0] = Vector2.LEFT if run.a.position.x > -64 else Vector2.ZERO
				input[1] = Vector2.RIGHT if run.b.position.x < 64 else Vector2.ZERO
		run.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
		if run.state != "running" or (run.next_segment >= 4 and run.total_distance() > 1500): break
	check("本地单机开门后持续生成并安全通过障碍", run.state == "running" and run.next_segment >= 4 and run.obstacles.size() > 0 and run.total_distance() > 1500 and run.shield_uses == 0)
	for player in game.sfx.players:
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	print("RESULT %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
