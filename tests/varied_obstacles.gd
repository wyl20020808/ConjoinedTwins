extends SceneTree
const Run = preload("res://scripts/road_run.gd")
const T = Run.Templates
var failures := 0
var checks := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", text)
func _initialize() -> void: call_deferred("verify")
func verify() -> void:
	var generator = T.new()
	generator.source_override = "varied-test"
	for route in ["shuttle", "piston", "sweep_pair", "narrow_dual", "narrow_triple", "hammer"]:
		for mode in T.DIFFICULTIES:
			for level in range(3):
				for side in [-1.0, 1.0]:
					var block := T.decorate(T.make_block(route, side, level), route, side)
					var ok: bool = generator.validate_block(block, mode, level)
					check(ok, "%s %s L%d side=%d reason=%s" % [route,mode,level+1,side,generator.last_evidence.get("reason", "")])
	for route in ["narrow_dual", "narrow_triple"]:
		var block := T.make_block(route, 1, 0)
		var run = Run.new(false)
		run.install_block(block, 0, "planks")
		var lanes := [-48.0,48.0] if route == "narrow_dual" else [-88.0,0.0,88.0]
		for x in lanes:
			check(run.has_ground_support(Vector2(x,350)) and is_equal_approx(run.plank_center(Vector2(x,350)),x), "%s 每条通道均可站立并独立回中 x=%s" % [route,x])
		for gap in run.ground_gaps(): check(not run.has_ground_support(gap.get_center()), "%s 镂空区域真实失去支撑" % route)
		# 两人也可以各选一条相邻通道，连线横跨镂空但不会提供脚底支撑。
		run.retry()
		run.install_block(block,0,"split-planks")
		run.a.position = Vector2(lanes[0],230)
		run.b.position = Vector2(lanes[1],230)
		run.distance = 230
		run.rope.reset(run.a.position,run.b.position)
		for tick in range(180): run.step(Run.FIXED_STEP)
		check(run.state == "running" and run.a.position.y > T.NARROW_START+T.NARROW_LENGTH and run.b.position.y > T.NARROW_START+T.NARROW_LENGTH, "%s 相邻通道双人分路可通过" % route)
		run.dispose()
	# 周期运动与转折切片，确保高速往复不是只检测两个同侧端点。
	for kind in ["shuttle","piston"]:
		var spec := Run.Industrial.spec(kind,1,0)
		var period: float = Run.Industrial.SHUTTLE_PERIOD if kind == "shuttle" else Run.Industrial.PISTON_PERIOD
		var rect := Rect2(-19,540,38,32)
		var first := Run.Industrial.sample(kind,rect,spec,0)
		var middle := Run.Industrial.sample(kind,rect,spec,period/2)
		var last := Run.Industrial.sample(kind,rect,spec,period)
		check(first.parts[0] == last.parts[0] and first.parts[0] != middle.parts[0], "%s 周期运动可复现" % kind)
		check(Run.Industrial.time_cuts(kind,spec,0,period).size() == 3, "%s 连续碰撞包含折返时刻" % kind)
		var run = Run.new(false)
		run.retry()
		run.install_block({"hazards":[{"kind":kind,"rect":rect,"side":1.0}],"rewards":[]},0,"sweep-contact")
		run.a.position = rect.get_center()
		run.b.position = rect.get_center() + Vector2(70,0)
		run.rope.reset(run.a.position,run.b.position)
		var hit: Dictionary = run.industrial_hits(0,0,period,run.a.position,run.a.position,run.b.position,run.b.position,[0.0,0.0],run.rope.path,run.rope.path_heights())
		check(not hit.is_empty(), "%s 整周期同端点仍检测到中间扫过身体或绳段" % kind)
		run.pause()
		var frozen := run.hazard_sample(0,run.elapsed)
		run.step(1.0)
		check(frozen == run.hazard_sample(0,run.elapsed), "%s 暂停冻结运动" % kind)
		run.dispose()
	# 实际生产场景创建和同步新机关，不启动窗口或模拟用户输入。
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.generation_enabled = false
	game.run.retry()
	game.run.charge_gates.clear()
	game.run.charge_gate = {"active":false,"open":false,"charge":0.0}
	for route in ["shuttle", "piston", "narrow_triple"]:
		game.run.install_block(T.make_block(route,1,0),0,route)
	game.run.revision += 1
	game.sync_view()
	check(game.hazard_views.size() == game.run.obstacles.size(), "生产场景完整创建新机关与镂空地形")
	game.queue_free()
	await process_frame
	print("VARIED_OBSTACLES checks=",checks," failures=",failures)
	quit(1 if failures else 0)
