extends SceneTree

# 单人人机专项：01 用生成器验证路线（模拟熟练真人），02 由 road_buddy_ai 驱动。
const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")
const BuddyAI = preload("res://scripts/road_buddy_ai.gd")

var failures := 0

func check(passed: bool, label: String) -> void:
	if not passed: failures += 1
	print("PASS " if passed else "FAIL ", label)

# 01 在救援中也按真人节奏连按（每 0.1 秒一次）。
func simulate(seed_value: int, miss: float, seconds: float, force: bool) -> Dictionary:
	var run = Run.new(true, true)
	run.seed_value = seed_value
	run.retry()
	var buddy = BuddyAI.new()
	buddy.miss_chance = miss
	buddy.reset(seed_value)
	var stats := {"buddy_rescues": 0, "rescued": 0, "fails": 0, "misses": 0, "progress": 0.0, "state": ""}
	var was_rescue := false
	for tick in range(int(seconds * 120)):
		while run.async_thread != null and run.async_thread.is_alive(): OS.delay_msec(1)
		if force and run.state == "running": buddy.force_miss = true
		var route: Array = Templates.existing_route_input(run) if run.state == "running" else [Vector2.ZERO, Vector2.ZERO, false, false]
		var decision: Dictionary = buddy.think(run, Run.FIXED_STEP)
		var human_jump: bool = route[2] if run.state == "running" else (tick % 12 == 0)
		if run.state == "rescue" and not was_rescue and run.rescue.role == 1: stats.buddy_rescues += 1
		if was_rescue and run.state == "running": stats.rescued += 1
		was_rescue = run.state == "rescue"
		if run.state == "failed":
			stats.fails += 1
			print("  fail: ", run.reason, " a=", run.a.position, " b=", run.b.position, " h=", run.heights, " support=", run.ground_support)
			run.retry(true)
			continue
		if run.state not in ["running", "rescue"]: break
		run.step(Run.FIXED_STEP, route[0], decision.move, human_jump, decision.jump)
		stats.progress = maxf(stats.progress, run.progress())
	stats.misses = buddy.misses
	stats.state = run.state
	run.dispose()
	return stats

func _initialize() -> void:
	# 1. 不失误：人机跟着验证路线，能正常推进且不触发救援。
	var careful := simulate(4242, 0.0, 40.0, false)
	print("careful ", careful)
	check(careful.buddy_rescues == 0 and careful.fails == 0 and careful.progress > 3000.0, "不失误时跟随推进 progress=%.0f" % careful.progress)
	# 2. 强制失误：遇到断崖不跳 → 掉下去触发救援 → 两人连按拉上来。
	var clumsy := simulate(4242, 0.0, 40.0, true)
	print("forced ", clumsy)
	check(clumsy.misses >= 1 and clumsy.buddy_rescues >= 1, "强制失误会掉下去并进入救援 misses=%d rescues=%d" % [clumsy.misses, clumsy.buddy_rescues])
	check(clumsy.rescued >= 1, "人机在救援中参与连按并被拉上来 rescued=%d" % clumsy.rescued)
	# 3. 默认概率：有失误但不至于一直失败。
	var normal := simulate(7, 0.3, 60.0, false)
	print("default ", normal)
	check(normal.progress > 3000.0, "默认失误率仍能持续前进 progress=%.0f" % normal.progress)
	print("BUDDY_AI failures=%d" % failures)
	quit(1 if failures > 0 else 0)
