extends SceneTree

const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
const OUT := "res://build-tools/obstacle-expansion-6377e8b8/t04/"

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)

func record(name: String, data: Dictionary) -> void:
	var file := FileAccess.open(OUT + name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func verify() -> void:
	var supported := true
	for kind in ["hammer", "collapse", "steam"]:
		var present: bool = Run.SURFACE_TOPS.has(kind)
		check("生产接入 " + kind, present)
		supported = supported and present
	if supported:
		verify_geometry()
		verify_collapse()
		verify_collapse_windows()
		verify_windows()
		verify_lifecycle()
		if not "--quick" in OS.get_cmdline_user_args():
			verify_routes()
			verify_production()
		await verify_scene()
	var failed := 0
	for row in checks:
		if not row.passed: failed += 1
	record("result", {"checks": checks, "failed": failed})
	quit(1 if failed else 0)

func fixture(kind: String, rect: Rect2, time: float = 0.0):
	var run = Run.new(false)
	run.retry()
	run.install_block({"hazards": [{"kind": kind, "rect": rect, "side": 1.0}], "rewards": []}, 0, "fixture")
	run.step(0)
	run.elapsed = time
	run.hazard_specs[0].trigger = 0.0
	return run

func place(run, a: Vector2, b: Vector2, h0: float = 0.0, h1: float = 0.0) -> void:
	run.a.position = a
	run.b.position = b
	run.heights = [h0, h1]
	run.rope.straight(a, b, 28 + h0, 28 + h1)

func detect(run, start: float, end: float, a: Vector2, b: Vector2, h0: float = 0.0, h1: float = 0.0) -> Dictionary:
	place(run, a, b, h0, h1)
	return run.industrial_hits(0, start, end, a, a, b, b, [h0, h1], run.rope.path, run.rope.path_heights())

func verify_geometry() -> void:
	var run = fixture("hammer", Rect2(90, 500, 12, 12), 3.0)
	# 抬起后的正常地面通行；柄必须参与碰撞，不能仅用锤头。
	check("巨锤开放窗口低位绳可通行", detect(run, 0.5, 0.51, Vector2(155, 470), Vector2(155, 540)).is_empty())
	var hit := detect(run, 2.85, 2.85, Vector2(200, 470), Vector2(200, 540))
	check("锤头离路但柄命中实际绳段", hit.get("actor") == "绳段" and hit.get("part") == "handle")
	for swap in [false, true]:
		var first := Vector2(200, 506)
		var last := Vector2(200, 560)
		var body := detect(run, 2.85, 2.85, last if swap else first, first if swap else last)
		check("巨锤柄角色碰撞交换 " + str(swap), body.get("actor") == ("02" if swap else "01"))
	check("巨锤支架持续实体碰撞", detect(run, 0.2, 0.21, Vector2(96, 506), Vector2(96, 570)).get("part") == "stand")
	check("巨锤整个摆动跨时段命中", not detect(run, 2.85, 4.85, Vector2(165, 605), Vector2(165, 675)).is_empty())
	record("hammer-counterexamples", {"sample": run.hazard_sample(0, 2.85), "rope_hit": hit})
	run.dispose()
	run = fixture("steam", Rect2(-15, 300, 30, 30))
	for row in [[0.2, "warning", false], [2.5, "pressure", false], [3.0, "jet", true], [3.7, "fade", true], [4.0, "safe", false]]:
		var sample: Dictionary = run.hazard_sample(0, row[0])
		check("蒸汽阶段 " + row[1], sample.stage == row[1] and sample.parts[1].active == row[2])
	var crossed := detect(run, 3.0, 3.0, Vector2(-60, 315), Vector2(60, 315))
	check("蒸汽脚下安全但真实绳跨喷口命中", crossed.get("actor") == "绳段")
	check("蒸汽单跳斜绳仍危险", detect(run, 3.0, 3.0, Vector2(-60, 315), Vector2(60, 315), 0, 36).get("actor") == "绳段")
	check("蒸汽双跳不能穿高压喷流", detect(run, 3.0, 3.0, Vector2(-60, 315), Vector2(60, 315), 36, 36).get("actor") == "绳段")
	check("蒸汽消退后无隐形伤害", detect(run, 4.0, 4.01, Vector2(-60, 315), Vector2(60, 315)).is_empty())
	check("蒸汽消退末尾跨安全边界不恢复满高伤害", detect(run, 3.898, 3.902, Vector2(-60, 315), Vector2(60, 315)).is_empty())
	place(run, Vector2(-60, 315), Vector2(60, 315))
	run.distance = 315
	run.elapsed = 3.0
	run.shield = true
	run.step(Run.FIXED_STEP)
	check("生产喷流割绳共同失败且护盾不消除", run.state == "failed" and "绳段" in run.reason and run.shield_uses == 0)
	record("steam-counterexamples", {"hit": crossed, "failure": run.reason})
	run.dispose()

func verify_collapse() -> void:
	for swap in [false, true]:
		for jump in [0, 1, 2]:
			var run = fixture("collapse", Rect2(-80, 200, 160, 60))
			run.hazard_specs[0].trigger = -1.0
			place(run, Vector2(0, 189) if not swap else Vector2(0, 55), Vector2(0, 55) if not swap else Vector2(0, 189))
			run.distance = 120
			var valid := true
			var exited := false
			var trigger := -1.0
			var jumps := [false, false]
			for tick in range(350):
				var lead_y: float = maxf(run.a.position.y, run.b.position.y)
				if lead_y >= 220 and lead_y < 224:
					jumps = [jump > 0 and not swap, jump > 0 and swap]
					if jump == 2: jumps = [true, true]
				else: jumps = [false, false]
				run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, jumps[0], jumps[1])
				valid = valid and run.state == "running" and run.rope.required <= 146.61
				if run.hazard_specs[0].trigger >= 0:
					if trigger < 0: trigger = run.hazard_specs[0].trigger
					valid = valid and run.hazard_specs[0].trigger == trigger
				if minf(run.a.position.y, run.b.position.y) > 273:
					exited = run.hazard_sample(0, run.elapsed).stage != "collapsed"
					break
			check("塌陷双人及绳段退出余量 交换%s 跳%d" % [swap, jump], valid and exited and trigger >= 0)
			record("collapse-exit-%s-%d" % [swap, jump], {"state": run.state, "trigger": trigger, "spec": run.hazard_specs[0], "exit": Run.Templates.snapshot(run, 0)})
			run.elapsed = trigger + run.hazard_specs[0].grace + 0.01
			check("塌后真实失去支撑", not run.has_ground_support(Vector2(0, 230)) and run.ground_gaps().size() == 1)
			place(run, Vector2(0, 230), Vector2(0, 290))
			run.distance = 260
			run.step(Run.FIXED_STEP)
			check("塌后落地共同失败绳索不承重", run.state == "failed" and "支撑" in run.reason)
			run.retry()
			run.install_block({"hazards": [{"kind": "collapse", "rect": Rect2(-80, 200, 160, 60)}], "rewards": []}, 0, "retry")
			check("重试恢复完整地板", run.has_ground_support(Vector2(0, 230)) and run.hazard_specs[0].trigger < 0)
			run.dispose()

func verify_collapse_windows() -> void:
	for difficulty in Run.Templates.DIFFICULTIES:
		for level in range(3):
			for swap in [false, true]:
				for jump in range(3):
					var run = Run.new(false)
					run.difficulty = difficulty
					run.level_index = level
					run.retry()
					run.install_block({"hazards": [{"kind": "collapse", "rect": Rect2(-80, 200, 160, 60)}], "rewards": []}, 0, "window")
					place(run, Vector2(0, 41.7) if swap else Vector2(0, 188.1), Vector2(0, 188.1) if swap else Vector2(0, 41.7))
					run.distance = 114.9
					var valid := true
					var history: Array = []
					for tick in range(360):
						var lead_y: float = maxf(run.a.position.y, run.b.position.y)
						var jumping: bool = lead_y >= 220 and lead_y < 224
						var j0: bool = jumping and (jump == 2 or (jump == 1 and not swap))
						var j1: bool = jumping and (jump == 2 or (jump == 1 and swap))
						run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, j0, j1)
						valid = valid and run.state == "running" and run.rope.required <= 146.61
						history.append({"input": [0, 0, j0, j1], "state": Run.Templates.snapshot(run, tick)})
						if minf(run.a.position.y, run.b.position.y) > 274: break
					var spec: Dictionary = run.hazard_specs[0]
					var name := "%s-%d-%s-%d" % [difficulty, level, swap, jump]
					check("最终关速塌陷最大前后差退出 " + name, valid and minf(run.a.position.y, run.b.position.y) > 274 and spec.trigger >= 0 and spec.warning_evidence.permitted_entry and run.hazard_sample(0, run.elapsed).supported)
					record("collapse-window-" + name, {"entry": spec.warning_evidence, "grace": spec.grace, "steps": history})
					run.dispose()

func verify_lifecycle() -> void:
	for kind in ["hammer", "collapse", "steam"]:
		var run = fixture(kind, Rect2(-30, 6050, 60, 60), 3.0)
		place(run, Vector2(-180, 6000), Vector2(-130, 6000))
		run.distance = 6000
		run.hazard_specs[0].start_distance = 6000
		var before: Dictionary = run.hazard_sample(0, run.elapsed)
		if kind == "hammer":
			run.elapsed = 7.56
			run.distance = 6050 + Run.Templates.BEHIND + 100
			run.update_stream()
			check("巨锤回收覆盖完整摆动包络", run.kinds.size() == 1)
			run.distance = 6000
			run.elapsed = 3.0
			# 上一步已重定位，恢复相同局部测试位置。
			run.distance -= run.world_origin
			place(run, Vector2(-180, run.distance), Vector2(-130, run.distance))
			before = run.hazard_sample(0, run.elapsed)
		var trigger: float = run.hazard_specs[0].trigger
		run.pause()
		run.step(1.0, Vector2.RIGHT, Vector2.LEFT, true, true)
		check(kind + " 暂停冻结全部阶段", run.elapsed == 3.0 and run.hazard_sample(0, run.elapsed) == before)
		run.pause()
		run.update_stream()
		check(kind + " 重定位保持相位触发", run.rebases == 1 and run.hazard_specs[0].trigger == trigger and is_equal_approx(run.obstacles[0].position.y, 1250))
		run.distance += 1500
		run.update_stream()
		check(kind + " 回收不残留危险支撑", run.kinds.is_empty() and run.ground_gaps().is_empty())
		run.install_block({"hazards": [{"kind": kind, "rect": Rect2(-30, 100, 60, 60)}], "rewards": []}, 0, "reuse")
		check(kind + " 重新安装恢复未触发状态", run.hazard_specs[0].trigger < 0)
		run.dispose()

func verify_windows() -> void:
	# 最高关速与最低关速均使用真实固定步；146 单位前后差逼近地面绳长上限。
	for difficulty in Run.Templates.DIFFICULTIES:
		for level in range(3):
			var run = fixture("hammer", Rect2(90, 500, 12, 12))
			run.difficulty = difficulty
			run.level_index = level
			run.elapsed = 7.56
			place(run, Vector2(200, 170), Vector2(200, 316))
			run.distance = 243
			var valid := true
			var ticks := 0
			while run.a.position.y <= 697 and ticks < 600:
				run.step(Run.FIXED_STEP)
				valid = valid and run.state == "running" and run.rope.required <= 146.61 and run.hazard_sample(0, run.elapsed).stage == "safe"
				ticks += 1
			check("巨锤窗口覆盖后方玩家和完整绳段 %s/%d" % [difficulty, level], valid and run.a.position.y > 697)
			record("hammer-window-%s-%d" % [difficulty, level], {"ticks": ticks, "exit": Run.Templates.snapshot(run, ticks)})
			run.dispose()
	var steam = Run.new(false)
	steam.retry()
	steam.install_block(Run.Templates.make_block("steam", 1, 0), 0, "phase")
	for spec in steam.hazard_specs: spec.trigger = 0.0
	var staggered := true
	var shared := false
	var stages: Array = []
	for tick in range(1800):
		var first: Dictionary = steam.hazard_sample(0, tick / 120.0)
		var second: Dictionary = steam.hazard_sample(1, tick / 120.0)
		staggered = staggered and not (first.parts[1].active and second.parts[1].active)
		shared = shared or (first.stage == "safe" and second.stage == "safe")
		if tick % 30 == 0: stages.append([tick, first.stage, second.stage])
	check("双蒸汽错峰喷射保留连续共同旁路", staggered)
	# 共同绕行无需等两个喷口同时结束；相位之间也存在共同无喷流时刻。
	var simultaneous_clear := false
	for time in [4.2, 7.2]:
		simultaneous_clear = simultaneous_clear or (not steam.hazard_sample(0, time).parts[1].active and not steam.hazard_sample(1, time).parts[1].active)
	check("蒸汽相位间提供双方及绳段共同无喷流窗口", simultaneous_clear)
	record("steam-staggered", {"stages": stages, "no_overlap": staggered, "shared_safe_stage": shared})
	steam.dispose()

func verify_routes() -> void:
	var generator = Run.Templates.new()
	var count := 0
	for difficulty in Run.Templates.DIFFICULTIES:
		for level in range(3):
			for side in [-1, 1]:
				for kind in ["hammer", "collapse", "steam"]:
					var block: Dictionary = Run.Templates.make_block(kind, side, level)
					var passed: bool = generator.validate_block(block, difficulty, level)
					check("共同旁路 %s/%d/%d/%s" % [difficulty, level, side, kind], passed)
					if not passed: print("诊断 ", generator.last_evidence.reason, " ", generator.last_evidence.exit)
					record("route-%03d" % count, generator.last_evidence)
					count += 1

func verify_production() -> void:
	for difficulty in Run.Templates.DIFFICULTIES:
		var run = Run.new(false)
		run.difficulty = difficulty
		run.generation_enabled = true
		run.retry()
		run.step(0)
		var seen := {}
		for tick in range(14000):
			var input: Array = [Vector2.ZERO, Vector2.ZERO, false, false]
			for segment in run.route_segments:
				seen[segment.block.route] = true
				if run.total_distance() >= segment.base and run.total_distance() < segment.base + Run.Templates.SEGMENT:
					input = Run.Templates.route_input(run, segment.block, segment.base - run.world_origin)
			run.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
			if run.state != "running": break
		check("生产实际出现三类独立教学 " + difficulty, seen.has("hammer") and seen.has("collapse") and seen.has("steam") and run.state == "settlement" and run.shield_uses == 0)
		record("production-" + difficulty, {"seen": seen, "state": run.state, "reason": run.reason, "rejections": run.generator.rejection_evidence})
		run.dispose()

func verify_scene() -> void:
	var scene = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.run.generation_enabled = false
	scene.run.obstacles.clear()
	scene.run.kinds.clear()
	scene.run.obstacle_ids.clear()
	scene.run.obstacle_heights.clear()
	scene.run.hazard_specs.clear()
	for kind in ["hammer", "collapse", "steam"]:
		scene.run.install_block(Run.Templates.make_block(kind, 1, 0), 0, "view")
	scene.run.revision += 1
	scene.sync_view()
	for i in range(scene.run.kinds.size()):
		var sample: Dictionary = scene.run.hazard_sample(i, scene.run.elapsed)
		var view: Node3D = scene.hazard_views[i]
		var valid := true
		for p in sample.parts:
			valid = valid and view.has_node(p.name)
		check("生产独立模型和提示 " + str(i), valid and view.has_node("WarningLabel"))
	scene.queue_free()
	await process_frame
