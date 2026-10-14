extends SceneTree

const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
var metrics := {}

func _initialize() -> void:
	output_path = OS.get_environment("SPEED_GUIDANCE_EVIDENCE").replace("\\", "/").simplify_path()
	var project_path := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").to_lower()
	if output_path.is_empty() or not output_path.is_absolute_path() or output_path.begins_with("res://") or output_path.begins_with("user://") or not output_path.to_lower().ends_with(".json") or output_path.to_lower() == project_path or output_path.to_lower().begins_with(project_path + "/") or FileAccess.file_exists(output_path):
		push_error("SPEED_GUIDANCE_EVIDENCE 必须指定项目外任务目录中尚不存在的绝对 JSON 文件路径；未运行检查或写入历史结果。")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_path.get_base_dir()) != OK:
		push_error("无法创建任务证据目录：" + output_path.get_base_dir())
		quit(2)
		return
	call_deferred("verify")

var output_path := ""

func check(name: String, ok: bool) -> void:
	checks.append({"name": name, "passed": ok})
	print("PASS " if ok else "FAIL ", name)

func verify() -> void:
	check("石球实际配置提速", -Run.Threats.CONFIG.stone_ball.velocity.y > 60)
	check("铁球实际配置提速", -Run.Threats.CONFIG.iron_ball.velocity.y > 80)
	check("独立火箭类型", Run.Threats.CONFIG.has("rocket"))
	var speeds := {}
	for difficulty in Run.Templates.DIFFICULTIES:
		for level in range(3):
			var r = Run.new(false)
			r.difficulty = difficulty
			r.level_index = level
			r.retry()
			r.step(0)
			r.step(1.0 / 120.0)
			var expected: float = {"简单": 140.0, "普通": 160.0, "困难": 180.0}[difficulty] * Run.Levels.LEVELS[level].speed_scale
			check("实际推进与终点 %s/%d" % [difficulty, level + 1], is_equal_approx(r.speed(), expected) and is_equal_approx(r.distance, expected / 120) and is_equal_approx(r.finish_distance(), expected * 100))
			speeds["%s/%d" % [difficulty, level + 1]] = [r.speed() / 20, r.finish_distance() / 20]
			r.dispose()
	metrics.speeds = speeds
	if Run.Threats.CONFIG.has("rocket"):
		check("火箭速度超过旧身体高度物", -Run.Threats.CONFIG.rocket.velocity.y > 220)
		var generator = Run.Templates.new()
		for difficulty in Run.Templates.DIFFICULTIES:
			for level in range(3):
				for route in Run.Templates.LEVEL_ROUTES[level]:
					for side in [-1.0, 1.0]:
						var ok: bool = generator.validate_block(generator.make_block(route, side, level), difficulty, level)
						check("全教学生产路线 %s/%d/%s/%s" % [difficulty, level, route, side], ok)
						if not ok: print(generator.last_evidence.reason, " ", generator.last_evidence.exit)
		for difficulty in Run.Templates.DIFFICULTIES:
			for level in [1, 2]:
				for side in [-1.0, 1.0]:
					var block: Dictionary = generator.make_block("rocket", side, level)
					check("火箭生产双人路线 %s/%d/%s" % [difficulty, level, side], generator.validate_block(block, difficulty, level) and block.hazards[0].kind == "rocket")
					if not generator.last_evidence.accepted: print(generator.last_evidence.reason, " ", generator.last_evidence.exit)
		for player in [-1, 0, 1]:
			var r = Run.new(false)
			r.streaming = false
			r.install_block({"hazards": [{"kind": "rocket", "rect": Rect2((-42 if player == 0 else 42 if player == 1 else 0) - 6, 200, 12, 12)}], "rewards": []}, 0, "hit")
			r.retry()
			r.step(0)
			r.hazard_specs[0].velocity = Vector2(0, -108000)
			r.step(Run.FIXED_STEP)
			check("火箭连续命中 %d" % player, r.state == "failed" and (player >= 0 or r.reason.begins_with("绳段")))
			r.retry()
			check("重试清空火箭触发状态", r.hazard_specs[0].trigger == -1 and not r.hazard_specs[0].locked)
			r.dispose()
		var game = load("res://scenes/road_demo.tscn").instantiate()
		root.add_child(game)
		game.set_physics_process(false)
		game.capture_mode = true
		var r = game.run
		r.generation_enabled = false
		r.retry()
		r.obstacles.clear()
		r.kinds.clear()
		r.obstacle_ids.clear()
		r.obstacle_heights.clear()
		r.hazard_specs.clear()
		r.rewards.clear()
		r.install_block(Run.Templates.make_block("rocket", -1, 1), 0, "rocket_view")
		r.revision += 1
		game.sync_view()
		var view = game.hazard_views[0]
		check("火箭独立模型和同源危险盒", view.has_node("RocketBody") and view.get_node("DangerVolume").mesh.size == Vector3(2, 1, 3.2) and view.has_node("FlightRoute") and view.has_node("ThreatShadow"))
		r.streaming = false
		r.step(0)
		var warning := {}
		for tick in range(240):
			var direction := Vector2.LEFT if r.hazard_specs[0].locked and r.b.position.x > -100 else Vector2.ZERO
			r.step(Run.FIXED_STEP, direction, direction)
			if r.hazard_specs[0].locked and warning.is_empty(): warning = r.hazard_specs[0].warning_evidence.duplicate(true)
		check("火箭按预警共同合法换边且不追踪", r.state == "running" and not warning.is_empty() and warning.ttc >= warning.joint_change_time + 0.35 - Run.FIXED_STEP and r.hazard_specs[0].velocity == Vector2(0, -360))
		metrics.rocket_warning = warning
		var frozen := var_to_str([r.elapsed, r.hazard_specs, r.rope.path, r.a.position, r.b.position])
		r.pause()
		r.step(0.25, Vector2.RIGHT, Vector2.RIGHT, true, true)
		check("火箭暂停冻结", frozen == var_to_str([r.elapsed, r.hazard_specs, r.rope.path, r.a.position, r.b.position]))
		r.pause()
		game.sync_view()
		r.revision += 1
		game.sync_view()
		check("火箭节点按类型复用", view == game.hazard_views[0])
		var relative: Vector2 = r.hazard_sample(0, r.elapsed).rect.get_center() - r.a.position
		r.distance += 6000
		r.a.position.y += 6000
		r.b.position.y += 6000
		r.obstacles[0].position.y += 6000
		r.hazard_specs[0].start_distance += 6000
		r.rope.shift(Vector2(0, 6000))
		r.streaming = true
		r.update_stream()
		check("火箭重定位保留相对轨迹与锁定", r.rebases == 1 and r.hazard_specs[0].locked and relative.is_equal_approx(r.hazard_sample(0, r.elapsed).rect.get_center() - r.a.position))
		r.obstacles[0].position.y -= 10000
		r.update_stream()
		check("火箭回收清空活动状态", r.hazard_specs.is_empty() and r.kinds.is_empty())
		game.queue_free()
		await process_frame
	var failed := checks.filter(func(c): return not c.passed).size()
	var result := FileAccess.open(output_path, FileAccess.WRITE)
	if result == null:
		push_error("无法写入任务证据文件：" + output_path)
		quit(2)
		return
	result.store_string(JSON.stringify({"passed": failed == 0, "checks": checks, "metrics": metrics}, "\t"))
	result.close()
	print("SPEED_GUIDANCE checks=%d failures=%d output=%s" % [checks.size(), failed, output_path])
	quit(0 if failed == 0 else 1)
