extends SceneTree
const Run = preload("res://scripts/road_run.gd")
const NoThreads = preload("res://tests/fixtures/no_threads_run.gd")
# 只关闭新增预计算，作为原调度的逐帧/布局对照；生产验证规则完全相同。
class LateRun extends "res://scripts/road_run.gd":
	func supports_background_generation() -> bool: return false
	func warm_tutorial_generation() -> void: pass
var checks := 0
var failures := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func _initialize() -> void: call_deferred("verify")
func verify() -> void:
	var early = NoThreads.new(true, true)
	var late = LateRun.new(true, true)
	for run in [early, late]:
		run.charge_tutorial = true
		run.lockstep = true
		run.seed_value = 4242
		run.retry()
		run.generator.bag = ["stone_ball"]
		run.generator.bag_level = 0
	var equal := true
	var preloading_seen := false
	var ready_behind_gate := 0
	var both_open := false
	var early_gate_catchup := 0
	var late_gate_catchup := 0
	var layouts_equal := true
	var early_peak := 0
	var late_peak := 0
	for tick in range(3600):
		var input: Array = Run.Templates.existing_route_input(early)
		if early.charge_gate.active and not early.charge_gate.open and early.charge_gate.id == "tutorial":
			input = [Vector2.ZERO, Vector2.ZERO, false, false]
			if early.distance >= 60:
				input[0] = Vector2.LEFT if early.a.position.x > -64 else Vector2.ZERO
				input[1] = Vector2.RIGHT if early.b.position.x < 64 else Vector2.ZERO
		for run in [early, late]:
			var started := Time.get_ticks_usec()
			run.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
			if run == early: early_peak = maxi(early_peak, Time.get_ticks_usec()-started)
			else: late_peak = maxi(late_peak, Time.get_ticks_usec()-started)
		equal = equal and early.sync_hash() == late.sync_hash()
		if early.charge_gates.any(func(gate): return gate.id in ["tutorial", "sync_tutorial"] and not gate.open):
			preloading_seen = preloading_seen or not early.async_preload_tasks.is_empty()
			var ready := 0
			for task in early.async_preload_tasks.values():
				if task.done: ready += 1
			ready_behind_gate = maxi(ready_behind_gate, ready)
		if early.gate_events.any(func(event): return event.id == "sync_tutorial" and event.event == "opened"):
			both_open = true
		if both_open and early.next_segment >= 3:
			early_gate_catchup = early.async_deadline_steps
			late_gate_catchup = late.async_deadline_steps
		if early.next_segment >= 4 and early.total_distance() > 1500: break
	for number in early.block_history:
		layouts_equal = layouts_equal and late.block_history.has(number) and var_to_str(early.block_history[number]) == var_to_str(late.block_history[number])
	check("教学期间已经开始预计算", preloading_seen)
	check("第二道门打开前已证明至少三段", ready_behind_gate >= 3)
	check("教学结束后安装首批段落无需集中补算", both_open and early.next_segment >= 4 and early_gate_catchup == 0)
	check("原调度对照确实存在集中补算", late_gate_catchup > 0)
	check("提前计算不改变逐帧模拟状态", equal)
	check("提前计算不改变完整关卡布局及随机序列", layouts_equal)
	check("真实障碍出现且继续推进", early.obstacles.size() > 0 and early.state == "running" and early.total_distance() > 1500)
	print("PRELOAD ready_behind_gate=",ready_behind_gate," early_catchup_steps=",early_gate_catchup," late_catchup_steps=",late_gate_catchup," step_peak_usec=",early_peak," late_step_peak_usec=",late_peak," slice_peak_usec=",early.async_preload_peak_usec)
	# 未完成任务必须释放，重试仍保留教学门且无提前安装的障碍。
	early.retry()
	check("重试清理预加载任务与结果", early.async_preload_requests.is_empty() and early.async_preload_tasks.is_empty() and early.cooperative_job == null and early.obstacles.is_empty() and early.charge_gates.size() == 2)
	early.step(0)
	var pending: Array = early.async_preload_tasks.values()
	early.dispose()
	check("销毁释放预计算验证克隆", early.async_preload_tasks.is_empty() and pending.all(func(task): return task.done and task.validation == null))
	late.dispose()
	# 不同种子和难度均须命中同一批正式候选，不能靠改变随机布局降低耗时。
	for mode_seed in [["简单", 777], ["困难", 20261014]]:
		var run = NoThreads.new(true, true)
		run.charge_tutorial = true
		run.lockstep = true
		run.difficulty = mode_seed[0]
		run.seed_value = mode_seed[1]
		run.retry()
		for poll in range(30000):
			run.warm_tutorial_generation()
			if run.async_preload_order.is_empty(): break
		check("%s 种子%d 教学预计算全部完成" % mode_seed, run.async_preload_tasks.size() == 4 and run.async_preload_order.is_empty())
		for number in range(4):
			var request: Dictionary = run.generation_request(run.generator, number, Run.Templates.START_DISTANCE + number * Run.Templates.SEGMENT)
			var key := str(number) + ":" + str(request.key)
			var expected: Dictionary = Run.verification_worker(request, Run.Templates.Cancellation.new())
			var task = run.async_preload_tasks.get(key)
			check("%s 种子%d 第%d段完整布局与原 worker 一致" % [mode_seed[0], mode_seed[1], number], task != null and task.done and var_to_str(task.result.block) == var_to_str(expected.block))
		run.dispose()
	print("RESULT %d/%d passed" % [checks-failures, checks])
	quit(1 if failures else 0)
