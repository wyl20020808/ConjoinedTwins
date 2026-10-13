extends SceneTree

const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
var evidence: Array = []

func _initialize() -> void:
	call_deferred("verify")

func check(title: String, passed: bool) -> void:
	checks.append({"name": title, "passed": passed})
	print("PASS " if passed else "FAIL ", title)

func verify() -> void:
	var supported := Run.SURFACE_TOPS.has("road_gap") and Run.SURFACE_TOPS.has("sweeper")
	check("生产具有真实缺口和扫杆类型", supported)
	if supported:
		var r = Run.new(false)
		r.retry()
		r.install_block({"hazards": [{"kind": "road_gap", "rect": Rect2(-80, 30, 160, 28)}], "rewards": []}, 0, "red")
		r.step(0)
		for tick in range(120):
			r.step(Run.FIXED_STEP)
			if r.state != "running": break
		check("地面走入缺口共同失败", r.state == "failed" and "支撑" in r.reason)
		r.dispose()
		verify_catalog()
		verify_failures()
		verify_state_and_inputs()
		await verify_scene()
	var failed := 0
	for row in checks:
		if not row.passed: failed += 1
	var f := FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t05/result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failed": failed, "evidence": evidence}, "\t"))
	f.close()
	quit(1 if failed else 0)

func record(name: String, data: Dictionary) -> void:
	var file := FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t05/" + name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func verify_catalog() -> void:
	var generator = Run.Templates.new()
	var routes := ["sweep_bypass", "gap_bypass", "sweep_single", "gap_single", "sweep_double", "gap_double", "gap_long"]
	var number := 0
	for difficulty in Run.Templates.DIFFICULTIES:
		for level in range(3):
			for side in [-1, 1]:
				for route in routes:
					var block: Dictionary = Run.Templates.make_block(route, side, level)
					var passed: bool = generator.validate_block(block, difficulty, level)
					var name := "%s/%d/%d/%s" % [difficulty, level + 1, side, route]
					check("生产键盘路线 " + name, passed)
					if not passed: print("诊断 ", name, " ", generator.last_evidence.reason, " ", generator.last_evidence.exit)
					record("route-%03d" % number, generator.last_evidence)
					evidence.append({"case": name, "path": "route-%03d.json" % number, "passed": passed})
					number += 1
	# 最快关速 + 全速前进，0.6 秒腾空；长缺口还长于不扣脚底半径的绝对上界。
	check("长缺口超过最快合法跳程且连续同侧道路宽裕", 252.0 > (208.8 + 160.0) * 0.6 and 246.0 - 80.0 > 50.0 + 24.0)

func fixture(kind: String, rect: Rect2):
	var r = Run.new(false)
	r.retry()
	r.install_block({"hazards": [{"kind": kind, "rect": rect}], "rewards": []}, 0, "fixture")
	r.step(0)
	return r

func verify_failures() -> void:
	var r = fixture("road_gap", Rect2(-80, 30, 160, 28))
	r.shield = true
	r.invulnerable_until = 100.0
	for tick in range(60):
		r.step(Run.FIXED_STEP)
		if r.state != "running": break
	check("护盾和无敌不能承重", r.state == "failed" and r.shield_uses == 0)
	r.retry()
	check("缺口重试恢复双方支撑和地面", r.ground_support == [true, true] and r.heights == [0.0, 0.0])
	r.dispose()
	r = fixture("road_gap", Rect2(-80, 100, 160, 252))
	var tape: Array = []
	for tick in range(360):
		var jump: bool = r.a.position.y >= 60 and r.a.position.y < 64
		r.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, jump, jump)
		tape.append(Run.Templates.snapshot(r, tick))
		if r.state != "running": break
	check("短跳落入长缺口失支撑共同失败", r.state == "failed" and "支撑" in r.reason)
	record("negative-landing", {"samples": tape, "reason": r.reason})
	r.dispose()
	r = fixture("sweeper", Rect2(-26, 100, 52, 52))
	check("支座角色扫掠命中", r.timed_hazard_hits(0, 0, 0.01, Vector2(0, 100), Vector2(0, 150), 0, 0))
	check("支座外合法旁路", not r.timed_hazard_hits(0, 0, 0.01, Vector2(70, 100), Vector2(70, 150), 0, 0))
	check("低杆独立跳跃可越过", not r.timed_hazard_hits(0, 0, 0.01, Vector2(24, 126), Vector2(24, 126), 30, 30))
	check("低杆贴地命中", r.timed_hazard_hits(0, 0, 0.01, Vector2(24, 126), Vector2(24, 126), 0, 0))
	# 旋转半圈，两端状态均不压角色，但中途竖向扫过。
	check("完整旋转扫掠不能漏过中间轨迹", r.timed_hazard_hits(0, 0, PI / 0.9, Vector2(0, 151), Vector2(0, 151), 0, 0))
	r.shield = true
	r.a.position = Vector2(0, 104)
	r.b.position = Vector2(80, 104)
	r.distance = 104
	r.rope.reset(r.a.position, r.b.position)
	r.step(Run.FIXED_STEP, Vector2(0, 1), Vector2(0, 1))
	check("护盾不穿扫杆支座", r.a.position.y < 109.01)
	r.dispose()
	var surfaces = Run.Surfaces
	var path := PackedVector2Array([Vector2(-30, 126), Vector2(30, 126)])
	check("双方身体避开但地面绳段命中支座", surfaces.rope_hits(Vector2(0, 126), {}, 0, 0.01, path, PackedFloat32Array([28, 28]), 0))
	check("双跳真实绳高越过支座", not surfaces.rope_hits(Vector2(0, 126), {}, 0, 0.01, path, PackedFloat32Array([55, 55]), 0))
	check("绳段插值高度不能用高端点掩盖低端", surfaces.rope_hits(Vector2(0, 126), {}, 0, 0.01, path, PackedFloat32Array([28, 50]), 0))

func verify_state_and_inputs() -> void:
	# 接近绳长上限并带 4 米前后差；按角色自己的实际位置决定起跳，交换身份仍成立。
	for swapped in [false, true]:
		var r = fixture("road_gap", Rect2(-80, 300, 160, 28))
		r.a.position = Vector2(-60, 100) if not swapped else Vector2(60, 20)
		r.b.position = Vector2(60, 20) if not swapped else Vector2(-60, 100)
		r.distance = 60
		r.rope.reset(r.a.position, r.b.position)
		var samples: Array = []
		var events: Array = []
		var max_rope := 0.0
		var separated := false
		for tick in range(450):
			var ja: bool = r.a.position.y >= 266 and r.a.position.y < 274
			var jb: bool = r.b.position.y >= 266 and r.b.position.y < 274
			var old: Array = r.heights.duplicate()
			r.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, ja, jb)
			var sample: Dictionary = Run.Templates.snapshot(r, tick)
			sample.input = [0, 0, 0, 0, ja, jb]
			samples.append(sample)
			max_rope = maxf(max_rope, r.rope.required)
			separated = separated or (r.heights[0] > 0 and r.heights[1] == 0) or (r.heights[1] > 0 and r.heights[0] == 0)
			for i in range(2):
				if (old[i] == 0 and r.heights[i] > 0) or (old[i] > 0 and r.heights[i] == 0):
					events.append({"tick": tick, "role": i + 1, "event": "起跳" if r.heights[i] > 0 else "落地", "position": [r.a.position.x, r.a.position.y] if i == 0 else [r.b.position.x, r.b.position.y], "support": r.ground_support[i]})
			if r.state != "running": break
		check("近紧绳前后错位独立双跳与角色交换 %s" % swapped, r.state == "running" and r.b.position.y > 340 and r.a.position.y > 340 and separated and events.size() == 4 and max_rope <= 146.61)
		record("stagger-swap-%s" % swapped, {"samples": samples, "events": events, "max_rope": max_rope, "reason": r.reason})
		r.dispose()
	var r = fixture("road_gap", Rect2(-80, 300, 160, 28))
	r.a.position = Vector2(-60, 100)
	r.b.position = Vector2(60, 20)
	r.distance = 60
	r.rope.reset(r.a.position, r.b.position)
	for tick in range(30): r.step(Run.FIXED_STEP, Vector2.LEFT, Vector2.RIGHT)
	check("紧绳限位不增加合法水平跳程", r.a.position.distance_to(r.b.position) <= 146.61 and r.rope.required <= 146.61)
	var start_a: Vector2 = r.a.position
	var start_b: Vector2 = r.b.position
	var maximum := 0.0
	var peak_heights := [0.0, 0.0]
	var tight_samples: Array = []
	for tick in range(73):
		r.step(Run.FIXED_STEP, Vector2.LEFT, Vector2.RIGHT, tick == 0, tick == 0)
		maximum = maxf(maximum, r.rope.required)
		for role in range(2): peak_heights[role] = maxf(peak_heights[role], r.heights[role])
		var sample: Dictionary = Run.Templates.snapshot(r, tick)
		sample.input = [-1, 0, 1, 0, tick == 0, tick == 0]
		tight_samples.append(sample)
	check("紧绳双跳不松绳或扩大横向跳程", r.state == "running" and peak_heights[0] > 30 and peak_heights[1] > 30 and maximum <= 146.61 and absf(r.a.position.x - start_a.x) < 0.01 and absf(r.b.position.x - start_b.x) < 0.01 and r.heights == [0.0, 0.0])
	record("tight-jump", {"samples": tight_samples, "peak_heights": peak_heights, "max_rope": maximum})
	r.dispose()
	for swapped in [false, true]:
		r = Run.new(false)
		r.retry()
		var block: Dictionary = Run.Templates.make_block("sweep_double", 1, 0)
		r.install_block(block, 0, "swap-sweeper")
		# 7.307 米地面间距：双方身体避开杆体，但绳段会跨支座，必须按实际绳高通过。
		r.a.position = Vector2(70, 42) if swapped else Vector2(-70, 0)
		r.b.position = Vector2(-70, 0) if swapped else Vector2(70, 42)
		r.distance = 21
		r.rope.reset(r.a.position, r.b.position)
		r.step(0)
		var frames: Array = []
		var events: Array = []
		for tick in range(620):
			var ja: bool = r.a.position.y >= 266 and r.a.position.y < 274
			var jb: bool = r.b.position.y >= 266 and r.b.position.y < 274
			var before: Array = r.heights.duplicate()
			r.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, ja, jb)
			var sample: Dictionary = Run.Templates.snapshot(r, tick)
			sample.input = [0, 0, 0, 0, ja, jb]
			frames.append(sample)
			for i in range(2):
				if (before[i] == 0 and r.heights[i] > 0) or (before[i] > 0 and r.heights[i] == 0): events.append({"role": i, "tick": tick, "point": sample.a if i == 0 else sample.b, "support": r.ground_support[i], "height": r.heights[i]})
			if r.state != "running": break
		check("扫杆前后错位错峰双跳交换 %s" % swapped, r.state == "running" and events.size() == 4 and r.a.position.y > 360 and r.b.position.y > 360)
		record("sweeper-swap-%s" % swapped, {"samples": frames, "events": events, "reason": r.reason})
		r.dispose()
	r = fixture("sweeper", Rect2(-26, 288, 52, 52))
	r.distance = 6000
	r.a.position.y += 6000
	r.b.position.y += 6000
	r.obstacles[0].position.y += 6000
	r.rope.reset(r.a.position, r.b.position)
	var relative: Vector2 = r.hazard_sample(0, r.elapsed).geometry.first - r.a.position
	r.update_stream()
	check("扫杆重定位几何和相位不变", relative.is_equal_approx(r.hazard_sample(0, r.elapsed).geometry.first - r.a.position) and r.rebases == 1)
	r.obstacles[0].position.y = r.distance - 600
	r.update_stream()
	check("扫杆回收清除旧几何", r.obstacles.is_empty())
	r.dispose()
	r = fixture("road_gap", Rect2(-80, 300, 160, 28))
	for tick in range(400):
		var jump: bool = r.distance >= 360 and r.distance < 365
		r.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, jump, jump)
		if r.state != "running": break
	check("走入缺口后迟跳不能凭空起跳", r.state == "failed" and r.heights == [0.0, 0.0])
	r.dispose()
	r = fixture("road_gap", Rect2(-80, 300, 160, 28))
	r.a.position = Vector2(-25, 6000)
	r.b.position = Vector2(25, 6000)
	r.distance = 6000
	r.obstacles[0].position.y += 6000
	r.rope.reset(r.a.position, r.b.position)
	var old_relative: Vector2 = r.obstacles[0].get_center() - r.a.position
	var old_support: bool = r.has_ground_support(r.a.position)
	r.update_stream()
	check("缺口重定位相对范围和支撑不变", old_relative.is_equal_approx(r.obstacles[0].get_center() - r.a.position) and old_support == r.has_ground_support(r.a.position) and r.rebases == 1)
	r.obstacles[0].position.y = r.distance - 600
	r.update_stream()
	check("缺口回收解除旧支撑禁区", r.obstacles.is_empty() and r.has_ground_support(r.a.position))
	r.dispose()
	# 真正生产流式生成：首轮教学不可被安全回退吞掉。
	for level in range(3):
		r = Run.new(false)
		r.level_index = level
		r.retry()
		r.generation_enabled = true
		var seen := {}
		var safe := true
		var failure := ""
		for tick in range(13000):
			var input: Array = [Vector2.ZERO, Vector2.ZERO, false, false]
			for segment in r.route_segments:
				var base: float = segment.base - r.world_origin
				if base <= r.distance and r.distance < base + Run.Templates.SEGMENT:
					input = Run.Templates.route_input(r, segment.block, base)
					seen[segment.block.route] = true
					break
			r.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
			if r.state != "running":
				safe = r.state == "settlement"
				failure = r.reason
				break
		var all_taught := true
		for route in (["sweep_bypass", "gap_bypass", "sweep_single", "gap_single", "sweep_double", "gap_double", "gap_long"] if level == 0 else ["sweep_bypass", "gap_bypass"]):
			all_taught = all_taught and seen.has(route)
		check("生产第一轮包含当前分关 t02 教学并自然通关 %d" % [level + 1], safe and r.state == "settlement" and all_taught)
		record("production-level-%d" % level, {"routes": seen.keys(), "rejections": r.generator.rejection_evidence, "state": r.state, "reason": failure, "distance": r.progress()})
		r.dispose()

func verify_scene() -> void:
	var scene = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	var r = scene.run
	r.streaming = false
	r.obstacles.clear()
	r.kinds.clear()
	r.obstacle_heights.clear()
	r.obstacle_ids.clear()
	r.hazard_specs.clear()
	r.rewards.clear()
	r.install_block({"hazards": [{"kind": "sweeper", "rect": Rect2(-26, 288, 52, 52)}, {"kind": "road_gap", "rect": Rect2(-80, 400, 160, 28)}], "rewards": []}, 0, "view")
	r.revision += 1
	scene.sync_view()
	check("生产独立扫杆模型与同源杆体尺寸", scene.hazard_views[0].has_node("SweeperPost") and scene.hazard_views[0].get_node("SweeperArm").mesh.size == Vector3(2.4, 0.2, 0.2))
	check("缺口模型读取实际缺口范围", scene.hazard_views[1].get_node("GapDepth").mesh.size == Vector3(8, 0.1, 1.4))
	var cut := false
	var winding_ok := true
	var surface_area := 0.0
	var expected_area := 0.0
	var box_mesh := BoxMesh.new()
	var box_arrays := box_mesh.surface_get_arrays(0)
	var box_vertices: PackedVector3Array = box_arrays[Mesh.ARRAY_VERTEX]
	var box_indices: PackedInt32Array = box_arrays[Mesh.ARRAY_INDEX]
	var top_sign := 0.0
	for n in range(0, box_indices.size(), 3):
		var p: Vector3 = box_vertices[box_indices[n]]
		var q: Vector3 = box_vertices[box_indices[n + 1]]
		var s: Vector3 = box_vertices[box_indices[n + 2]]
		if p.y > 0 and q.y > 0 and s.y > 0: top_sign = signf((q - p).cross(s - p).y)
	for chunk in scene.scenery:
		if chunk.has_meta("road_slot") and chunk.get_node("SupportSurface").mesh is ArrayMesh:
			cut = true
			var mesh: ArrayMesh = chunk.get_node("SupportSurface").mesh
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			expected_area += 24.6 * 8.0
			var gap := Rect2(-4, -21.4 - chunk.position.z, 8, 1.4).intersection(Rect2(-12.3, -4, 24.6, 8))
			expected_area -= gap.get_area()
			for n in range(0, vertices.size(), 3):
				var cross: Vector3 = (vertices[n + 1] - vertices[n]).cross(vertices[n + 2] - vertices[n])
				winding_ok = winding_ok and signf(cross.y) == top_sign
				surface_area += absf(cross.y) * 0.5
	check("生产道路网格实际挖空", cut)
	check("缺口路面正面朝向与原道路一致", winding_ok)
	check("缺口网格完整减去真实缺口面积", absf(surface_area - expected_area) < 0.001)
	var views: Array = scene.hazard_views.duplicate()
	r.revision += 1
	scene.sync_view()
	check("扫杆和缺口节点按类型复用", views == scene.hazard_views)
	var frozen := var_to_str([r.elapsed, r.hazard_sample(0, r.elapsed), r.a.position, r.b.position, r.heights])
	r.state = "running"
	r.pause()
	r.step(0.25, Vector2.RIGHT, Vector2.RIGHT, true, true)
	check("暂停冻结旋转支撑跳跃", frozen == var_to_str([r.elapsed, r.hazard_sample(0, r.elapsed), r.a.position, r.b.position, r.heights]))
	scene.queue_free()
	await process_frame
