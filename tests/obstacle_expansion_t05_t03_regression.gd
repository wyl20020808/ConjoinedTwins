extends SceneTree

const Run = preload("res://scripts/road_run.gd")
var checks: Array = []

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)

func verify() -> void:
	var supported: bool = Run.SURFACE_TOPS.has("drone") and Run.SURFACE_TOPS.has("forklift") and Run.SURFACE_TOPS.has("press")
	check("生产包含无人机、叉车和压机", supported)
	if supported:
		if not "--quick" in OS.get_cmdline_user_args(): verify_routes()
		verify_geometry()
		verify_boundaries()
		verify_tight_routes()
		verify_lifecycle()
		if not "--quick" in OS.get_cmdline_user_args(): verify_production()
		await verify_scene()
	var failed := 0
	for row in checks:
		if not row.passed: failed += 1
	var file := FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t05/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failed": failed}, "\t"))
	file.close()
	quit(1 if failed else 0)

func record(name: String, data: Dictionary) -> void:
	var file := FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t05/" + name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func verify_routes() -> void:
	var generator = Run.Templates.new()
	var number := 0
	for difficulty in Run.Templates.DIFFICULTIES:
		for level in range(3):
			for side in [-1, 1]:
				for route in ["drone", "forklift", "press"]:
					var block: Dictionary = Run.Templates.make_block(route, side, level)
					var passed: bool = generator.validate_block(block, difficulty, level)
					check("独立教学 %s/%d/%d/%s" % [difficulty, level, side, route], passed)
					if not passed: print("诊断 ", generator.last_evidence.reason, " ", generator.last_evidence.exit)
					record("route-%03d" % number, generator.last_evidence)
					number += 1

func fixture(kind: String, rect: Rect2, elapsed: float = 0.0):
	var run = Run.new(false)
	run.retry()
	run.install_block({"hazards": [{"kind": kind, "rect": rect, "side": 1.0}], "rewards": []}, 0, "fixture")
	run.step(0)
	run.elapsed = elapsed
	run.hazard_specs[0].trigger = 0.0
	return run

func place(run, first: Vector2, last: Vector2, h0: float = 0.0, h1: float = 0.0) -> void:
	run.a.position = first
	run.b.position = last
	run.heights = [h0, h1]
	run.rope.straight(first, last, Run.ROPE_HEIGHT + h0, Run.ROPE_HEIGHT + h1)

func detect(run, start: float, end: float, first: Vector2, last: Vector2, h0: float = 0.0, h1: float = 0.0) -> Dictionary:
	place(run, first, last, h0, h1)
	return run.industrial_hits(0, start, end, first, first, last, last, [h0, h1], run.rope.path, run.rope.path_heights())

func verify_geometry() -> void:
	var run = fixture("drone", Rect2(-18, 300, 36, 36), 3.0)
	var sample: Dictionary = run.hazard_sample(0, 3.0)
	var velocity: Vector2 = run.hazard_specs[0].velocity
	var center: Vector2 = sample.parts[0].rect.get_center()
	place(run, Vector2(-100, 100), Vector2(-90, 210))
	var first: Dictionary = run.hazard_sample(0, 3.0)
	place(run, Vector2(130, -100), Vector2(140, -210))
	var second: Dictionary = run.hazard_sample(0, 3.0)
	check("无人机锁定后交换位置不追踪", first.parts == second.parts and run.hazard_specs[0].velocity == velocity)
	check("无人机连续固定斜向速度", run.hazard_sample(0, 3.5).parts[0].rect.get_center().is_equal_approx(center + velocity * 0.5))
	for swap in [false, true]:
		var hit := detect(run, 3, 3, center, center + Vector2(0, 65)) if not swap else detect(run, 3, 3, center + Vector2(0, 65), center)
		check("无人机双方前后错位角色命中 " + str(swap), hit.get("actor") == ("02" if swap else "01"))
	var rope_hit := detect(run, 3, 3, center + Vector2(-70, 0), center + Vector2(70, 0))
	check("无人机两人避开但实际绳段独立命中", rope_hit.get("actor") == "绳段")
	check("无人机真实升高绳段可避过", detect(run, 3, 3, center + Vector2(-70, 0), center + Vector2(70, 0), 30, 30).is_empty())
	var slanted := detect(run, 3, 3, center + Vector2(-70, 0), center + Vector2(70, 0), 0, 30)
	check("无人机实际斜绳高度相交命中", slanted.get("actor") == "绳段")
	check("无人机不以两端高度包络误判远端低绳", detect(run, 3, 3, center + Vector2(-110, 0), center + Vector2(35, 0), 0, 36).is_empty())
	place(run, center + Vector2(50, 0), center + Vector2(50, 65))
	var old_path := PackedVector2Array([center + Vector2(-50, 0), center + Vector2(-50, 65)])
	var swept := run.industrial_hits(0, 3, 3, old_path[0], run.a.position, old_path[1], run.b.position, [0.0, 0.0], old_path, PackedFloat32Array([28.0, 28.0]))
	check("无人机两端未重叠仍捕获跨步扫掠", swept.get("actor") == "01")
	place(run, center + Vector2(-70, 0), center + Vector2(70, 0))
	run.distance = center.y
	run.shield = true
	run.invulnerable_until = 100
	run.step(Run.FIXED_STEP)
	check("生产无人机割绳共同失败且不消耗护盾", run.state == "failed" and "绳段" in run.reason and run.shield_uses == 0)
	record("drone-counterexamples", {"locked": first, "after_exchange": second, "rope_hit": rope_hit, "slanted": slanted, "failure": run.reason})
	run.dispose()
	run = fixture("forklift", Rect2(-30, 300, 60, 48), 2.4)
	for part_name in ["vehicle", "fork_-1", "fork_1", "load"]:
		var p: Dictionary = {}
		for value in run.hazard_sample(0, 2.4).parts:
			if value.name == part_name: p = value
		var point: Vector2 = p.rect.get_center()
		if part_name.begins_with("fork"): point.x = 69.0
		var h: float = 30.0 if part_name == "load" else 0.0
		var hit := detect(run, 2.4, 2.4, point, point + Vector2(0, 100), h, h)
		check("叉车分部角色碰撞 " + part_name, hit.get("part") == part_name)
		place(run, point, point + Vector2(0, 100), h, h)
		run.distance = point.y + 50
		run.elapsed = 2.4
		run.shield = true
		run.invulnerable_until = 100
		run.state = "running"
		run.step(Run.FIXED_STEP)
		check("护盾不可穿叉车 " + part_name, run.state == "failed" and run.shield_uses == 0)
	var cross := detect(run, 2.4, 2.4, Vector2(-65, 318), Vector2(75, 318))
	check("叉车双方避开车体但错位绳段命中", cross.get("actor") == "绳段")
	record("forklift-parts", {"sample": run.hazard_sample(0, 2.4), "rope_hit": cross})
	run.dispose()
	run = fixture("press", Rect2(-80, 300, 160, 50))
	for time in [2.65, 3.0, 3.65]:
		var hit := detect(run, time, time + Run.FIXED_STEP, Vector2(-30, 325), Vector2(30, 325))
		check("压机完整下压停留回升危险 " + str(time), hit.get("part") == "plate")
	check("压机真正回升离开后可通行", detect(run, 4.2, 4.21, Vector2(-30, 325), Vector2(30, 325)).is_empty())
	check("压机升高绳段和低绳段各自判定", detect(run, 2.65, 2.65, Vector2(-70, 325), Vector2(70, 325), 30, 30).get("actor") == "01")
	check("压机两人前后避开但升高绳段撞下降板", detect(run, 2.65, 2.65, Vector2(0, 255), Vector2(0, 395), 20, 20).get("actor") == "绳段")
	check("压机同一布局低绳按真实高度通过", detect(run, 2.65, 2.65, Vector2(0, 255), Vector2(0, 395)).is_empty())
	run.dispose()
	verify_press_window()
	var block: Dictionary = Run.Templates.make_block("press", 1, 0)
	block.hazards[0].rect = Rect2(-246, 560, 492, 50)
	var generator = Run.Templates.new()
	check("无等待区无旁路全宽压机被拒绝", not generator.validate_block(block, "困难", 2))
	record("press-fullwidth-rejected", generator.last_evidence)

func verify_boundaries() -> void:
	var run = fixture("drone", Rect2(-18, 300, 36, 36))
	for ending in [false, true]:
		var time := 7.4 if ending else 2.4
		var center: Vector2 = run.hazard_sample(0, time).parts[0].rect.get_center()
		var edge: float = 18 + Run.Motion.RADIUS
		var pa := center + Vector2(edge + 0.12 if ending else edge - 0.04, 0)
		var ca := center + Vector2(edge - 0.04 if ending else edge + 0.12, 0)
		var pb := pa + Vector2(60, 0)
		var cb := ca + Vector2(60, 0)
		place(run, ca, cb)
		var hit: Dictionary = run.industrial_hits(0, time - 0.001, time + 0.001, pa, ca, pb, cb, [0.0, 0.0], PackedVector2Array([pa, pb]), PackedFloat32Array([28.0, 28.0]))
		check("无人机激活/失活跨步不误算非活动接触 " + str(ending), hit.is_empty())
	run.dispose()
	run = fixture("press", Rect2(-80, 300, 160, 50))
	for time in [2.4, 2.85, 3.45, 4.15, 6.95]:
		var hit := detect(run, time - 0.001, time + 0.001, Vector2(-30, 325), Vector2(30, 325))
		check("压机阶段转折连续检测 " + str(time), not hit.is_empty() if time in [2.85, 3.45] else hit.is_empty())
	run.dispose()

func verify_tight_routes() -> void:
	for kind in ["drone", "forklift", "press"]:
		for side in [-1, 1]:
			for swap in [false, true]:
				var run = Run.new(false)
				run.difficulty = "困难"
				run.level_index = 2
				run.retry()
				var block: Dictionary = Run.Templates.make_block(kind, side, 2)
				run.install_block(block, 0, "tight")
				place(run, Vector2(-5, -73 if swap else 73), Vector2(5, 73 if swap else -73))
				run.step(0)
				var samples: Array = []
				var peak: float = run.rope.required
				var safe := true
				for tick in range(1000):
					var controls := Run.Templates.route_input(run, block, 0)
					run.step(Run.FIXED_STEP, controls[0], controls[1], controls[2], controls[3])
					peak = maxf(peak, run.rope.required)
					safe = safe and run.rope.required <= Run.LINK_LIMIT + 0.01 and run.shield_uses == 0
					if tick % 15 == 0: samples.append(Run.Templates.snapshot(run, tick))
					if run.state != "running" or run.distance >= Run.Templates.SEGMENT: break
				check("镜像交换近绳限共同通过 %s/%d/%s" % [kind, side, str(swap)], safe and run.state == "running" and peak >= Run.LINK_LIMIT - 0.5)
				record("tight-%s-%d-%s" % [kind, side, str(swap)], {"samples": samples, "peak": peak, "state": run.state, "reason": run.reason})
				run.dispose()

func verify_press_window() -> void:
	for late in [false, true]:
		var run = fixture("press", Rect2(-80, 300, 160, 50), 8.8 if late else 4.2)
		place(run, Vector2(0, 280), Vector2(0, 134))
		run.distance = 207
		var samples: Array = []
		for tick in range(260):
			run.step(Run.FIXED_STEP)
			if tick % 15 == 0: samples.append(Run.Templates.snapshot(run, tick))
			if run.state != "running" or minf(run.a.position.y, run.b.position.y) > 365: break
		check("压机近绳限完整后角色与绳段退出 " + str(late), (run.state == "failed" if late else run.state == "running" and minf(run.a.position.y, run.b.position.y) > 365 and run.rope.required <= Run.LINK_LIMIT))
		record("press-window-" + str(late), {"samples": samples, "reason": run.reason, "state": run.state, "rope": run.rope.required})
		run.dispose()

func verify_lifecycle() -> void:
	for kind in ["drone", "forklift", "press"]:
		var run = fixture(kind, Rect2(-18, 900, 36, 36), 3.0)
		run.streaming = false
		var before: Dictionary = run.hazard_sample(0, run.elapsed)
		run.pause()
		run.step(0.25)
		check(kind + " 暂停冻结运动与周期", before == run.hazard_sample(0, run.elapsed) and run.elapsed == 3.0)
		run.pause()
		run.retry()
		check(kind + " 非流式重试清空锁定预警", run.hazard_specs[0].trigger < 0 and run.hazard_specs[0].warning_evidence.is_empty())
		run.streaming = true
		run.generation_enabled = false
		run.distance = 6001
		place(run, Vector2(-25, 6001), Vector2(25, 6001))
		run.obstacles[0].position.y = 6100
		run.hazard_specs[0].start_distance = 6000
		var original: Dictionary = run.hazard_sample(0, 0)
		run.update_stream()
		check(kind + " 重定位只移动世界坐标", run.rebases == 1 and run.hazard_sample(0, 0).parts[0].rect.position.y == original.parts[0].rect.position.y - 4800 and run.hazard_specs[0].start_distance == 1200)
		run.distance += 1000
		run.update_stream()
		check(kind + " 完整分部通过后回收", run.kinds.is_empty() and run.hazard_specs.is_empty())
		run.dispose()

func verify_production() -> void:
	for difficulty in Run.Templates.DIFFICULTIES:
		for level in range(3):
			var run = Run.new(false)
			run.difficulty = difficulty
			run.level_index = level
			run.generation_enabled = true
			run.retry()
			run.step(0)
			var seen := {}
			var safe := true
			for tick in range(14000):
				var controls: Array = [Vector2.ZERO, Vector2.ZERO, false, false]
				for segment in run.route_segments:
					seen[segment.block.route] = true
					if run.total_distance() >= segment.base and run.total_distance() < segment.base + Run.Templates.SEGMENT:
						controls = Run.Templates.route_input(run, segment.block, segment.base - run.world_origin)
				run.step(Run.FIXED_STEP, controls[0], controls[1], controls[2], controls[3])
				safe = safe and run.rope.required <= Run.LINK_LIMIT + 0.01 and run.shield_uses == 0
				if run.state != "running": break
			var all_taught := true
			for route in (["drone", "forklift", "press", "sweep_bypass", "gap_bypass", "sweep_single", "gap_single", "sweep_double", "gap_double", "gap_long"] if level == 0 else ["drone", "forklift", "press", "sweep_bypass", "gap_bypass"]):
				all_taught = all_taught and seen.has(route)
			check("生产首轮新三类和 t02 当前分关独立教学 %s/%d" % [difficulty, level], safe and all_taught and run.state == "settlement")
			record("production-%s-%d" % [difficulty, level], {"routes": seen.keys(), "state": run.state, "reason": run.reason, "shield_uses": run.shield_uses, "rejections": run.generator.rejection_evidence, "seconds": run.elapsed})
			run.dispose()

func verify_scene() -> void:
	var scene = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.run.generation_enabled = false
	scene.run.obstacles.clear()
	scene.run.kinds.clear()
	scene.run.obstacle_heights.clear()
	scene.run.obstacle_ids.clear()
	scene.run.hazard_specs.clear()
	for kind in ["drone", "forklift", "press"]:
		scene.run.install_block(Run.Templates.make_block(kind, 1, 0), 0, "view")
	scene.run.revision += 1
	scene.sync_view()
	for i in range(3):
		var view: Node3D = scene.hazard_views[i]
		var sample: Dictionary = scene.run.hazard_sample(i, scene.run.elapsed)
		var parts_ok := true
		for p in sample.parts:
			parts_ok = parts_ok and view.has_node(p.name) and view.get_node(p.name).mesh.size == Vector3(p.rect.size.x / 20, (p.top - p.bottom) / 20, p.rect.size.y / 20)
		check("生产独立模型及同源分部 " + scene.run.kinds[i], parts_ok and view.has_node("WarningFootprint") and view.has_node("TrajectoryCorridor") and view.has_node("WarningLabel"))
		if scene.run.kinds[i] == "drone":
			check("无人机完整五秒轨迹走廊预告", view.get_node("TrajectoryCorridor").mesh.size.z >= scene.run.hazard_specs[i].velocity.length() * 5.0 / 20)
	scene.run.revision += 1
	scene.sync_view()
	check("三类视图池复用", scene.hazard_views.size() == 3)
	scene.queue_free()
	await process_frame
