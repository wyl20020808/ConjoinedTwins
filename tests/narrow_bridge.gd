extends SceneTree

# 窄桥与双人身体阻挡专项：生产 road_run 固定步，不改物理参数。
const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")

var failures := 0

func check(passed: bool, label: String) -> void:
	if not passed: failures += 1
	print("PASS " if passed else "FAIL ", label)

func fresh(difficulty: String, level: int):
	var run = Run.new(false)
	run.difficulty = difficulty
	run.level_index = level
	run.retry()
	run.a.position = Vector2(-25, 0)
	run.b.position = Vector2(25, 0)
	run.rope.reset(run.a.position, run.b.position)
	run.step(0)
	return run

func _initialize() -> void:
	# 1. 所有难度、关卡、左右变体的窄桥段都能被合法键盘路线通过并回到段尾中心。
	var generator := Templates.new()
	for difficulty in Templates.DIFFICULTIES:
		for level in range(3):
			for side in [-1.0, 1.0]:
				var block := Templates.make_block("narrow", side, level)
				var ok := generator.validate_block(block, difficulty, level)
				check(ok, "窄桥可通过 %s level=%d side=%d reason=%s" % [difficulty, level + 1, side, generator.last_evidence.get("reason", "")])

	# 2. 两人迎面相撞：中心间距始终不小于 BODY_GAP，且不会互相穿过。
	var run = fresh("普通", 0)
	run.streaming = false
	var closest := INF
	for tick in range(240):
		run.step(Run.FIXED_STEP, Vector2(1, 0), Vector2(-1, 0), false, false)
		closest = minf(closest, run.a.position.distance_to(run.b.position))
		if run.state != "running": break
	check(closest >= Run.BODY_GAP - 0.01 and run.a.position.x < run.b.position.x, "迎面相撞不穿透 closest=%.3f" % closest)
	run.dispose()

	# 3. 一人静止、一人撞上：静止的一方不被推动。
	run = fresh("普通", 0)
	var still: Vector2 = run.b.position
	for tick in range(120):
		run.step(Run.FIXED_STEP, Vector2(1, 0), Vector2.ZERO, false, false)
	check(absf(run.b.position.x - still.x) < 0.01 and run.b.position.distance_to(run.a.position) >= Run.BODY_GAP - 0.01, "不推动静止队友 dx=%.3f" % (run.b.position.x - still.x))
	run.dispose()

	# 4. 并排上桥：两人无法同时站在桥面上，必有一人坠落。
	for side in [-1.0, 1.0]:
		run = fresh("普通", 0)
		run.install_block(Templates.make_block("narrow", side, 0), 0.0, "narrow-side-by-side")
		var plank: float = side * 40.0
		for tick in range(120 * 4):
			var target_a: Vector2 = Vector2(plank - 6, 0) - run.a.position
			var target_b: Vector2 = Vector2(plank + 6, 0) - run.b.position
			run.step(Run.FIXED_STEP, Vector2(signf(target_a.x) if absf(target_a.x) > 1.5 else 0.0, 0), Vector2(signf(target_b.x) if absf(target_b.x) > 1.5 else 0.0, 0), false, false)
			if run.state != "running": break
		# 一人掉下、队友站在桥上：先进入救援；无人按键 3 秒后共同坠落。
		var hung: bool = run.state == "rescue"
		for tick in range(120 * 4):
			if run.state != "rescue": break
			run.step(Run.FIXED_STEP)
		check(hung and run.state == "failed", "并排上桥必坠落 side=%d hung=%s state=%s reason=%s" % [side, hung, run.state, run.reason])
		run.dispose()

	# 5. 最高关速下两人在桥头外侧全力前冲并起跳，跳不过 22 米断崖。
	run = fresh("困难", 2)
	run.install_block(Templates.make_block("narrow", 1.0, 2), 0.0, "narrow-jump")
	var jumped := false
	for tick in range(120 * 6):
		var leading: float = maxf(run.a.position.y, run.b.position.y)
		var jump: bool = not jumped and leading >= Templates.NARROW_START - Run.Motion.RADIUS - 6.0
		if jump: jumped = true
		run.step(Run.FIXED_STEP, Vector2(-0.0, 1), Vector2(0.0, 1), jump, jump)
		if run.state != "running": break
	check(run.state == "failed", "全速起跳越不过窄桥断崖 state=%s reason=%s" % [run.state, run.reason])
	run.dispose()

	print("NARROW_BRIDGE failures=", failures)
	quit(1 if failures else 0)
