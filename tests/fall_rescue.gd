extends SceneTree

# 坠落救援专项：生产 road_run 固定步，按键只给原始跳跃键按下状态。
const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")

var failures := 0

func check(passed: bool, label: String) -> void:
	if not passed: failures += 1
	print("PASS " if passed else "FAIL ", label)

# 01 从左侧路边走出，02 站在路面内。
func hang(difficulty: String = "普通"):
	var run = Run.new(false)
	run.difficulty = difficulty
	run.retry()
	run.a.position = Vector2(-Run.EDGE + 4, 0)
	run.b.position = Vector2(-Run.EDGE + 70, 0)
	run.rope.reset(run.a.position, run.b.position)
	for tick in range(120):
		if run.state != "running": break
		run.step(Run.FIXED_STEP, Vector2(-1, 0), Vector2.ZERO)
	return run

# 按给定频率连按；每次按下保持 1 个固定步再松开。返回结束时的状态。
func mash(run, holder_rate: float, faller_rate: float = 0.0, seconds: float = Run.RESCUE_TIME + Run.RESCUE_CLIMB_TIME + 0.5) -> String:
	if run.state != "rescue": return run.state
	var role: int = run.rescue.role
	for tick in range(int(seconds * 120)):
		if run.state != "rescue": break
		var holder_down := holder_rate > 0 and tick % maxi(2, int(round(120.0 / holder_rate))) == 0
		var faller_down := faller_rate > 0 and tick % maxi(2, int(round(120.0 / faller_rate))) == 0
		var jumps := [false, false]
		jumps[1 - role] = holder_down
		jumps[role] = faller_down
		run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, jumps[0], jumps[1])
	return run.state

func _initialize() -> void:
	# 1. 进入救援，世界冻结。
	var run = hang()
	check(run.state == "rescue" and run.rescue.role == 0, "队友站稳时进入救援 state=%s" % run.state)
	var frozen := [run.distance, run.elapsed, run.b.position]
	for tick in range(60): run.step(Run.FIXED_STEP, Vector2(1, 1), Vector2(1, 1))
	check(run.distance == frozen[0] and run.elapsed == frozen[1] and run.b.position == frozen[2], "救援期间推进、计时和队友位置冻结")
	run.dispose()

	# 2. 每个难度：略高于所需频率救起，略低于所需频率坠落。
	for difficulty in Templates.DIFFICULTIES:
		var rate: float = Run.RESCUE_RATES[difficulty]
		run = hang(difficulty)
		var state := mash(run, rate * 1.2)
		var safe: bool = state == "running" and run.has_ground_support(run.a.position) and run.a.position.distance_to(run.b.position) >= Run.BODY_GAP - 0.01
		check(safe and run.rescue_count == 1 and run.invulnerable_until > run.elapsed, "%s 频率 %.1f 救起并站回路面 state=%s a=%s" % [difficulty, rate * 1.2, state, run.a.position])
		for tick in range(120): run.step(Run.FIXED_STEP)
		check(run.state == "running", "%s 救起后继续前进" % difficulty)
		run.dispose()
		run = hang(difficulty)
		state = mash(run, rate * 0.8)
		check(state == "failed" and run.reason.contains("悬崖") and run.fallen[0], "%s 频率 %.1f 不足则坠落 reason=%s" % [difficulty, rate * 0.8, run.reason])
		run.dispose()

	# 3. 坠落者按键效果减半：单独狂按不够，配合队友可以。
	run = hang()
	check(mash(run, 0.0, Run.RESCUE_RATES["普通"] * 1.6) == "failed", "坠落者独自按键效果减半，救不起来")
	run.dispose()
	run = hang()
	check(mash(run, Run.RESCUE_RATES["普通"] * 0.6, Run.RESCUE_RATES["普通"] * 1.2) == "running", "坠落者与队友一起按可以救起")
	run.dispose()

	# 4. 按住不放不算连按。
	run = hang()
	for tick in range(int((Run.RESCUE_TIME + 1.0) * 120)):
		if run.state != "rescue": break
		run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, false, true)
	check(run.state == "failed", "按住跳跃键不放救不起来")
	run.dispose()

	# 5. 同关重复救援不再加难，同样的正常节奏始终有效。
	run = hang()
	var steady: float = Run.RESCUE_RATES["普通"] * 1.1
	mash(run, steady)
	run.a.position = Vector2(-Run.EDGE + 4, run.a.position.y)
	run.rope.reset(run.a.position, run.b.position)
	for tick in range(120):
		if run.state != "running": break
		run.step(Run.FIXED_STEP, Vector2(-1, 0), Vector2.ZERO)
	check(run.state == "rescue" and absf(run.rescue.rate - Run.RESCUE_RATES["普通"]) < 0.001, "第二次救援所需频率保持不变")
	check(mash(run, steady) == "running", "第二次用同样节奏仍能救起")
	run.dispose()

	# 6. 队友腾空时没人拉绳，直接坠落。
	run = Run.new(false)
	run.retry()
	run.a.position = Vector2(-Run.EDGE + 4, 0)
	run.b.position = Vector2(-Run.EDGE + 70, 0)
	run.rope.reset(run.a.position, run.b.position)
	for tick in range(12): run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, false, tick > 1 and tick < 6)
	for tick in range(120):
		if run.state != "running": break
		run.step(Run.FIXED_STEP, Vector2(-1, 0), Vector2.ZERO)
	check(run.heights[1] > 0.0 and run.state == "failed", "队友腾空时直接坠落 state=%s" % run.state)
	run.dispose()

	# 7. 暂停救援后恢复仍在救援。
	run = hang()
	run.pause()
	check(run.state == "paused", "救援中可暂停")
	run.pause()
	check(run.state == "rescue", "恢复后回到救援")
	run.dispose()

	# 7b. 拉满后先爬上（世界仍冻结），再站到留有余量的地面；继续按住朝坑方向也不会立刻再掉。
	run = hang()
	var role_b: int = run.rescue.role
	for tick in range(480):
		if run.rescue.has("climb") or run.state != "rescue": break
		run.step(Run.FIXED_STEP, Vector2(-1, 0), Vector2.ZERO, false, tick % 10 == 0)
	check(run.state == "rescue" and run.rescue.has("climb"), "拉满后进入爬上阶段")
	for tick in range(240):
		if run.state != "rescue": break
		run.step(Run.FIXED_STEP, Vector2(-1, 0), Vector2.ZERO)
	check(run.state == "running" and run.has_ground_support(run.a.position) and run.a.position.x > -Run.EDGE + 20, "救起后站在离崖沿有余量的地面 a=%s" % run.a.position)
	for tick in range(30): run.step(Run.FIXED_STEP, Vector2(-1, 0), Vector2.ZERO)
	check(run.state == "running" and role_b == 0, "救起后按住原方向不立刻再掉 state=%s" % run.state)
	run.dispose()

	# 8. 窄桥：掉进桥侧断崖后救起，回到桥面。
	run = Run.new(false)
	run.retry()
	run.install_block(Templates.make_block("narrow", 1.0, 0), 0.0, "rescue-narrow")
	run.a.position = Vector2(40, Templates.NARROW_START + 100)
	run.b.position = Vector2(40, Templates.NARROW_START + 30)
	run.distance = Templates.NARROW_START + 65
	run.rope.reset(run.a.position, run.b.position)
	for tick in range(120):
		if run.state != "running": break
		run.step(Run.FIXED_STEP, Vector2(-1, 0), Vector2.ZERO)
	check(run.state == "rescue", "窄桥踩空进入救援 state=%s" % run.state)
	mash(run, Run.RESCUE_RATES["普通"] * 1.3)
	check(run.state == "running" and run.has_ground_support(run.a.position), "窄桥救起后站回桥面 a=%s" % run.a.position)
	for tick in range(120): run.step(Run.FIXED_STEP)
	check(run.state == "running", "窄桥救起后继续前进不再掉 state=%s" % run.state)
	run.dispose()

	# 9. 窄桥上轻点横向键（约 0.07 秒）不会滑下桥，松手后回正中线。
	run = Run.new(false)
	run.retry()
	run.install_block(Templates.make_block("narrow", 1.0, 0), 0.0, "tap-narrow")
	run.a.position = Vector2(40, Templates.NARROW_START + 100)
	run.b.position = Vector2(40, Templates.NARROW_START + 30)
	run.distance = Templates.NARROW_START + 65
	run.rope.reset(run.a.position, run.b.position)
	for tick in range(8): run.step(Run.FIXED_STEP, Vector2(1, 0), Vector2.ZERO)
	for tick in range(60): run.step(Run.FIXED_STEP)
	check(run.state == "running" and absf(run.a.position.x - 40) < 1.0, "窄桥轻点不坠落且回正 state=%s x=%.2f" % [run.state, run.a.position.x])
	run.dispose()

	print("FALL_RESCUE failures=", failures)
	quit(1 if failures else 0)
