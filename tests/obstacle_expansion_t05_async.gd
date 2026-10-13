extends SceneTree
const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
func _initialize() -> void:
	call_deferred("verify")
func check(name: String, ok: bool) -> void:
	checks.append({"name": name, "passed": ok})
	print("PASS " if ok else "FAIL ", name)
func verify() -> void:
	verify_binding()
	verify_diagonal_admission()
	var probe = Run.new(false)
	check("具备生产后台验证与取消接口", probe.has_method("poll_generation") and probe.has_method("cancel_generation"))
	probe.dispose()
	if probe.has_method("poll_generation"):
		await displaced_entry()
		if not "--entry-only" in OS.get_cmdline_user_args(): await lifecycle()
	var failed := 0
	for item in checks:
		if not item.passed: failed += 1
	FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t05/async-result.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "passed": failed == 0, "failed": failed}, "\t"))
	quit(1 if failed else 0)

func verify_diagonal_admission() -> void:
	var run = Run.new(false)
	run.a.position = Vector2(-80, 40)
	run.b.position = Vector2(-30, 40)
	var block := {"lane": 0.0}
	var lateral := 55.0 / Run.LATERAL
	var regroup := 40.0 / Run.LATERAL
	var available := maxf(lateral, regroup) + 0.325 + regroup * 0.5
	var base := 40.0 + Run.Motion.RADIUS + available * (run.level_speed() + Run.LATERAL)
	var admission: Dictionary = run.installation_admission(block, base)
	check("对角归一化与共同前偏移串行归队上界拒绝不足余量", not admission.permitted and admission.joint_change_time >= lateral + regroup and admission.reaction_margin < 0.325)
	run.dispose()

func verify_binding() -> void:
	var path := "res://scripts/t05_binding_fixture.gd"
	var same_second := false
	var different := false
	var peak := 0
	for attempt in range(3):
		FileAccess.open(path, FileAccess.WRITE).store_string("extends RefCounted\n#AAAA\n")
		var stamp := FileAccess.get_modified_time(path)
		var before := Run.Templates.source_binding(true)
		FileAccess.open(path, FileAccess.WRITE).store_string("extends RefCounted\n#BBBB\n")
		var started := Time.get_ticks_usec()
		var after := Run.Templates.source_binding(true)
		peak = maxi(peak, Time.get_ticks_usec() - started)
		same_second = stamp == FileAccess.get_modified_time(path)
		different = before != after
		if same_second: break
	DirAccess.remove_absolute(path)
	Run.Templates.source_binding(true)
	check("等长同秒mtime改写强制字节绑定变化", same_second and different)
	print("SOURCE BINDING peak_usec=", peak)

func displaced_entry() -> void:
	var run = Run.new(true, true)
	run.retry()
	run.step(0)
	for tick in range(24):
		run.step(Run.FIXED_STEP, Vector2(-1, 1), Vector2(-1, 0), tick == 1, tick == 1)
	for tick in range(10000):
		run.poll_generation()
		if run.async_thread == null: break
		OS.delay_msec(1)
	var installed: bool = not run.async_events.is_empty() and run.async_events[0].event == "installed"
	var displaced := false
	if installed:
		var event: Dictionary = run.async_events[0]
		displaced = event.source_hash != event.actual_install_entry_hash and event.actual_install_entry.run.heights[0] > 0 and absf(event.actual_install_entry.a.y - event.actual_install_entry.b.y) > 10 and event.admission.reaction_margin >= 0.325
	check("真实worker期间横移跳跃前后错位以实际共同时间域安装", installed and displaced and run.state == "running")
	var through := false
	for tick in range(2000):
		var input: Array = Run.Templates.existing_route_input(run)
		run.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
		if run.total_distance() > Run.Templates.START_DISTANCE + Run.Templates.SEGMENT:
			through = run.state == "running" and run.shield_uses == 0
			break
		if run.state != "running": break
		OS.delay_msec(2)
	check("从交接真实空中错位状态按生产输入通过首段", through)
	FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t05/async-displaced-entry.json", FileAccess.WRITE).store_string(JSON.stringify({"events": run.async_events, "state": run.state, "reason": run.reason, "passed": installed and displaced and through}, "\t"))
	run.dispose()

func lifecycle() -> void:
	var run = Run.new(true, true)
	var initial_thread: Thread = run.async_thread
	var old_epoch: int = run.async_epoch
	check("构造立即启动真实后台线程", initial_thread != null and initial_thread.is_started())
	var canceled_at := Time.get_ticks_usec()
	run.cancel_generation()
	check("取消真实worker后join且无残留", run.async_thread == null and not initial_thread.is_started() and Time.get_ticks_usec() - canceled_at < 1000000)
	run.retry()
	check("重试新epoch不复用旧线程", run.async_epoch > old_epoch and run.next_segment == 0 and run.async_thread != null)
	run.step(0)
	var seen := {}
	var combos := {}
	var max_step := 0
	var coins_before := 0
	var valid := true
	for tick in range(13000):
		if tick % 1200 == 0: print("ASYNC PROGRESS tick=", tick, " installed=", run.next_segment)
		var input: Array = Run.Templates.existing_route_input(run)
		var started := Time.get_ticks_usec()
		run.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
		max_step = maxi(max_step, Time.get_ticks_usec() - started)
		valid = valid and run.rope.required <= Run.LINK_LIMIT + 0.01 and run.shield_uses == 0 and run.coins >= coins_before
		coins_before = run.coins
		for segment in run.route_segments:
			if run.total_distance() < segment.base: continue
			for hazard in segment.block.hazards: seen[hazard.kind] = true
			if segment.block.has("combination"): combos[segment.block.combination] = true
		if run.state != "running": break
		# 模拟约两倍实时 headless 帧，让真正的后台线程与前台物理并行运行。
		OS.delay_msec(4)
		if tick % 120 == 0: await process_frame
	check("后台生产八类独立教学与两组合实际通过", valid and run.state == "settlement" and seen.has("sweeper") and seen.has("road_gap") and seen.has("drone") and seen.has("forklift") and seen.has("press") and seen.has("hammer") and seen.has("collapse") and seen.has("steam") and combos.has("pillar_press") and combos.has("low_steam"))
	check("后台金币真实领取且无护盾抵伤", run.coins >= 60 and run.shield_uses == 0)
	var handoffs := true
	var warnings := true
	for event in run.async_events:
		if event.event != "installed": continue
		handoffs = handoffs and event.leading < event.base and not event.source_hash.is_empty() and not event.layout_hash.is_empty()
		for evidence in event.warning.values():
			if evidence.has("earliest_approach"): warnings = warnings and evidence.reaction_margin >= 0.325
			else: warnings = warnings and evidence.ttc >= evidence.joint_change_time + 0.325
	check("后台主线程入口源码布局交接及共同预警有效", handoffs and warnings and run.async_events.size() >= 16)
	check("普通固定帧无同步验证长卡顿", max_step < 100000)
	check("结算取消并join全部worker", run.async_thread == null)
	print("ASYNC FRAME peak_usec=", max_step, " state=", run.state, " reason=", run.reason)
	FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t05/async-events.json", FileAccess.WRITE).store_string(JSON.stringify({"events": run.async_events, "peak_step_usec": max_step, "seen": seen.keys(), "combos": combos.keys(), "state": run.state, "reason": run.reason}, "\t"))
	run.dispose()
	var late = Run.new(true, true)
	var late_thread: Thread = late.async_thread
	late.a.position.y = late.async_job.base
	late.poll_generation()
	check("真实worker迟到拒绝安装并停止生成", late.generation_halted and late.state == "failed" and late.next_segment == 0 and late.route_segments.is_empty() and late.async_events[-1].reason.contains("迟到"))
	check("迟到停止无worker残留", late.async_thread == null and not late_thread.is_started())
	late.dispose()
	var narrow = Run.new(true, true)
	var narrow_thread: Thread = narrow.async_thread
	narrow.a.position.y = narrow.async_job.base - 20
	narrow.b.position.y = narrow.async_job.base - 20
	for tick in range(10000):
		narrow.poll_generation()
		if narrow.async_thread == null: break
		OS.delay_msec(1)
	check("仍在入口前但实际共同归队窗口不足拒绝安装", narrow.generation_halted and narrow.state == "failed" and narrow.next_segment == 0 and narrow.async_events[-1].reason.contains("窗口不足") and not narrow_thread.is_started())
	narrow.dispose()
	var closing = Run.new(true, true)
	var closing_thread: Thread = closing.async_thread
	closing.dispose()
	check("dispose合作取消并join真实worker", closing.async_thread == null and not closing_thread.is_started())
