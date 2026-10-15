extends SceneTree
const Run = preload("res://scripts/road_run.gd")
const NoThreads = preload("res://tests/fixtures/no_threads_run.gd")
var checks := 0
var failures := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func _initialize() -> void: call_deferred("verify")
func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.dispose()
	game.run = NoThreads.new(true, true)
	var live = game.run
	var reference = Run.new(true, true)
	for run in [live, reference]:
		run.charge_tutorial = true
		run.lockstep = true
		run.random_seed = false
		run.seed_value = 4242
		run.retry()
		run.generator.bag = ["sync_cargo", "charge_cargo", "charge_sync_relay", "sync_cargo", "charge_cargo", "charge_sync_relay", "sync_cargo", "charge_cargo"]
		run.generator.bag_level = 0
	var equal := true
	var late_warm := false
	var opened: Array = []
	var view_builds_during_install := 0
	var waits := 0
	var frame := 0
	var peak_prepare := 0
	var peak_step := 0
	var peak_view := 0
	var scene_nodes_peak := 0
	for pump in range(16000):
		var started := Time.get_ticks_usec()
		var before_hash: int = live.sync_hash()
		var ready: bool = game.prepare_game_frame()
		peak_prepare = maxi(peak_prepare, Time.get_ticks_usec()-started)
		if not ready:
			waits += 1
			equal = equal and before_hash == live.sync_hash()
			continue
		var input: Array = Run.Templates.existing_route_input(live)
		if live.charge_gate.active and not live.charge_gate.open and live.charge_gate.id == "tutorial":
			input = [Vector2.ZERO, Vector2.ZERO, false, false]
			if live.distance >= 60:
				input[0] = Vector2.LEFT if live.a.position.x > -64 else Vector2.ZERO
				input[1] = Vector2.RIGHT if live.b.position.x < 64 else Vector2.ZERO
		started = Time.get_ticks_usec()
		live.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
		peak_step = maxi(peak_step, Time.get_ticks_usec()-started)
		reference.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
		equal = equal and live.sync_hash() == reference.sync_hash()
		var builds: int = game.hazard_build_count
		started = Time.get_ticks_usec()
		game.sync_view()
		peak_view = maxi(peak_view, Time.get_ticks_usec()-started)
		view_builds_during_install += game.hazard_build_count - builds
		scene_nodes_peak = maxi(scene_nodes_peak, get_node_count())
		late_warm = late_warm or (live.next_segment > 4 and not live.async_preload_requests.is_empty())
		for event in live.gate_events:
			if event.event == "opened" and not opened.has(event.id): opened.append(event.id)
		frame += 1
		if live.state != "running" or (opened.size() >= 6 and live.total_distance() > 5200): break
	check("连续通过教学与至少四道后续机关", opened.size() >= 6 and live.state == "running")
	check("首批四段之后仍持续预计算", late_warm)
	check("生产路径从未触发同步整段补算", live.async_deadline_steps == 0)
	check("慢准备不推进模拟且逐帧与原生一致", equal)
	check("关卡安装时模型已备好且障碍展示完整", game.hazard_views.size() == live.obstacles.size() and view_builds_during_install == 0)
	check("模型预热保持场景节点预算", scene_nodes_peak <= Run.Templates.MAX_SCENE_NODES)
	# 一次纯表现刷新不得重建已有巨岩或改变节点绑定。
	var ids: Array = game.hazard_views.map(func(view): return view.get_instance_id())
	var built: int = game.hazard_build_count
	live.revision += 1
	game.sync_view()
	check("已有模型按稳定ID保留，刷新不重建巨岩", built == game.hazard_build_count and ids == game.hazard_views.map(func(view): return view.get_instance_id()))
	print("STREAM_GATE opened=",opened," frames=",frame," waits=",waits," distance=",live.total_distance()," state=",live.state," reason=",live.reason," catchup=",live.async_deadline_steps," builds_at_install=",view_builds_during_install," scene_nodes_peak=",scene_nodes_peak," prepare_peak_us=",peak_prepare," step_peak_us=",peak_step," view_peak_us=",peak_view)
	# 在当前任务尚未完成时强制让它到固定安装点，验证等待而非偷偷消耗模拟帧。
	live.retry()
	live.charge_tutorial = false
	live.retry()
	var same: int = live.sync_hash()
	var waiting: bool = not live.prepare_frame()
	check("极慢任务到安装点时让出帧而不是集中计算", waiting and live.sync_hash() == same and live.async_deadline_steps == 0)
	# 故意不做表现预热，验证冷模型逐个创建，未备齐时不应用当前帧。
	for poll in range(10000):
		if live.prepare_frame(): break
	game.sync_view()
	for pool in game.hazard_pool.values():
		for view in pool: view.queue_free()
	game.hazard_pool.clear()
	var model_waits := 0
	var maximum_builds := 0
	for poll in range(1000):
		var count: int = game.hazard_build_count
		var prepared: bool = game.prepare_generation_views()
		maximum_builds = maxi(maximum_builds, game.hazard_build_count-count)
		if prepared: break
		model_waits += 1
	check("冷模型每次至多创建一个并让出帧", model_waits > 0 and maximum_builds == 1)
	# 存档里已有证明也不能在update_stream里直接批量安装，必须先准备模型。
	live.cancel_generation()
	live.block_history[0] = Run.Templates.make_block("charge_cargo", 1, 0)
	live.next_segment = 0
	live.update_stream()
	var history_deferred: bool = live.next_segment == 0 and live.cooperative_job != null and live.cooperative_job.done
	for poll in range(1000):
		if game.prepare_game_frame(): break
	live.step(Run.FIXED_STEP)
	var before_view: int = game.hazard_build_count
	game.sync_view()
	check("存档历史先准备再安装且不临时批建模型", history_deferred and live.next_segment == 1 and game.hazard_build_count == before_view and live.async_events[-1].source == "checkpoint_history")
	reference.dispose()
	for player in game.sfx.players:
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	print("RESULT %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
