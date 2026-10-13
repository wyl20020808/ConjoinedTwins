extends SceneTree
# 通过生产场景驱动真实固定步，不修改历史检查。
const Run = preload("res://scripts/road_run.gd")
const DT := 1.0 / 120.0
var checks: Array = []
var metrics := {}
var game
var r

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)

func fixture(kind: String, center: Vector2, size: Vector2 = Vector2.ZERO) -> void:
	r.streaming = false
	var config: Dictionary = Run.Threats.CONFIG[kind]
	var shape: Vector2 = config.size if size == Vector2.ZERO else size
	r.obstacles.assign([Rect2(center - shape * 0.5, shape)])
	r.kinds.assign([kind])
	r.obstacle_heights.assign([config.top])
	r.hazard_specs.assign([Run.Threats.spec(kind, 2.0)])
	r.obstacle_ids.clear()
	r.revision += 1
	r.retry()
	r.step(0)
	r.assign_obstacle_ids()

func verify() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.capture_mode = true
	r = game.run
	var grazing := Run.Threats.circle_contact_fraction(Vector2(-10, 0), Vector2(10, 0), Vector2(-0.5, 9.99), Vector2(0.5, 9.99), 10)
	# 球心轨迹平行绳段且全程相交由普通接触负责；端点擦入再离开用解析时刻。
	grazing = Run.Threats.circle_contact_fraction(Vector2.ZERO, Vector2.ZERO, Vector2(-0.5, 9.99), Vector2(0.5, 9.99), 10)
	check("球体跨步擦边解析接触（两端均未命中）", grazing > 0 and grazing < 1 and Vector2(-0.5, 9.99).length() > 10 and Vector2(0.5, 9.99).length() > 10)
	for player in range(2):
		fixture("fly_low", Vector2(-42 if player == 0 else 42, 96), Vector2(20, 24))
		for tick in range(80): r.step(DT, Vector2.ZERO, Vector2.ZERO, tick == 0 and player == 0, tick == 0 and player == 1)
		check("迎面低空独立跳跃 P%d" % (player + 1), r.state == "running" and r.heights[1 - player] == 0)
		fixture("fly_body", Vector2(-42 if player == 0 else 42, 96), Vector2(20, 24))
		for tick in range(80): r.step(DT, Vector2.ZERO, Vector2.ZERO, tick == 0 and player == 0, tick == 0 and player == 1)
		check("身体高度物不能用同一跳跃越过 P%d" % (player + 1), r.state == "failed")
		fixture("fly_body", Vector2(-42 if player == 0 else 42, 200), Vector2(20, 24))
		r.hazard_specs[0].velocity = Vector2(0, -108000)
		r.step(DT)
		check("高速迎面角色跨步命中 P%d" % (player + 1), r.state == "failed")
	fixture("fly_body", Vector2(0, 200), Vector2(12, 12))
	r.hazard_specs[0].velocity = Vector2(0, -108000)
	r.step(DT)
	check("高速飞行物只命中两人中间绳段", r.state == "failed" and r.reason.begins_with("绳段"))
	for kind in ["fly_low", "fly_body", "stone_ball", "iron_ball"]:
		fixture(kind, Vector2(0, 900))
		var first: Vector2 = r.hazard_specs[0].velocity
		var warning := {}
		for tick in range(480):
			var input := Vector2(-1, 0) if r.hazard_specs[0].locked and r.b.position.x > -100 else Vector2.ZERO
			r.step(DT, input, input)
			if r.hazard_specs[0].locked and warning.is_empty(): warning = r.hazard_specs[0].warning_evidence.duplicate(true)
		check(kind + "共同同侧避让成功", r.state == "running")
		check(kind + "预警 TTC/相对速度/换边证据", not warning.is_empty() and warning.ttc >= warning.joint_change_time + 0.35 - DT * 3 and absf(warning.ttc - warning.required_lead) < DT * 3 and warning.relative_speed[0] > 0)
		check(kind + "预警锁定后不追踪改道", r.hazard_specs[0].velocity == first and absf(r.hazard_sample(0, r.elapsed).rect.get_center().x) < 0.01)
		metrics[kind + "_warning"] = warning
		var offset: Vector2 = r.hazard_specs[0].offset
		var time: float = r.elapsed
		r.pause()
		r.step(0.2, Vector2.RIGHT, Vector2.RIGHT)
		check(kind + "暂停冻结动态状态", r.elapsed == time and r.hazard_specs[0].offset == offset)
		r.pause()
		r.retry()
		check(kind + "重试清除锁定和运动接触", r.hazard_specs[0].offset == Vector2.ZERO and not r.hazard_specs[0].locked and r.rope.contacts.is_empty() and r.hazard_specs[0].blocked_time == 0)
	for kind in ["stone_ball", "iron_ball"]:
		fixture(kind, Vector2(0, 400))
		r.a.position.x = -65
		r.b.position.x = 65
		r.hazard_specs[0].velocity = Vector2(0, -108000)
		r.step(DT)
		check(kind + "高速球跨步建立稳定绳接触", r.state == "running" and r.rope.touching() > 0 and r.rope.required <= Run.LINK_LIMIT + 0.01 and r.hazard_sample(0, 0).rect.get_center().y > -50)
		var paused_path: PackedVector2Array = r.rope.path.duplicate()
		var paused_offset: Vector2 = r.hazard_specs[0].offset
		r.pause()
		r.step(0.25)
		check(kind + "暂停保留真实接触及路径", r.rope.path == paused_path and r.hazard_specs[0].offset == paused_offset)
		r.pause()
		r.retry()
		check(kind + "接触后重试无残留", r.rope.contacts.is_empty() and r.hazard_specs[0].blocked_time == 0 and r.hazard_specs[0].offset == Vector2.ZERO)
		fixture(kind, Vector2(0, 220))
		r.a.position.x = -65
		r.b.position.x = 65
		r.rope.reset(r.a.position, r.b.position)
		var touched := false
		var changed := false
		var max_length := 0.0
		var max_move := 0.0
		var first_center := Vector2.ZERO
		var first_tension := 0.0
		var sides := {}
		var flip := false
		for tick in range(600):
			var before_a: Vector2 = r.a.position
			var before_b: Vector2 = r.b.position
			r.step(DT)
			max_length = maxf(max_length, r.rope.length)
			max_move = maxf(max_move, maxf(before_a.distance_to(r.a.position), before_b.distance_to(r.b.position)))
			for contact in r.rope.contacts:
				if contact.loose != 0: continue
				if not touched:
					first_center = contact.center
					first_tension = r.rope_tension()
					touched = true
				elif contact.center.distance_to(first_center) > 1 and r.rope_tension() > first_tension + 0.005: changed = true
				if sides.has(contact.id) and sides[contact.id] != contact.side: flip = true
				sides[contact.id] = contact.side
			if r.state == "failed": break
		check(kind + "运动接触改变真实路径及张力", touched and changed and not flip)
		check(kind + "持续接触耗尽约束才失败", r.state == "failed" and r.rope_failed and r.rope.required >= Run.LINK_LIMIT - 0.02 and r.rope.touching() > 0)
		check(kind + "硬绳长及无瞬移", max_length <= Run.LINK_LIMIT + Run.ROPE_LENGTH_TOLERANCE and max_move <= Run.FORWARD * DT + 0.02)
		metrics[kind + "_contact"] = {"max_length": max_length, "required": r.rope.required, "max_move": max_move, "reason": r.reason, "block_time": r.hazard_specs[0].blocked_time, "static_block_time": r.rope_block_time()}
		# 同样分侧站位，球还在远处：不能只按左右站位失败。
		fixture(kind, Vector2(0, 2000))
		r.a.position.x = -65
		r.b.position.x = 65
		for tick in range(120): r.step(DT)
		check(kind + "仅分侧无接触不失败", r.state == "running" and r.hazard_specs[0].blocked_time == 0)
		# 松绳首次接触后共同靠近球的来向回撤，球与绳连续脱离。
		fixture(kind, Vector2(0, 280))
		r.a.position = Vector2(-65, 100)
		r.b.position = Vector2(65, 100)
		var saw_contact := false
		for tick in range(240):
			r.step(DT)
			if r.rope.touching() > 0:
				saw_contact = true
				break
		# 双方后撤，利用停下的自动推进和前后活动范围连续解绕。
		for tick in range(600):
			r.step(DT, Vector2(0, -1), Vector2(0, -1))
			if r.rope.contacts.is_empty(): break
		check(kind + "接触解围回归", saw_contact and r.state == "running" and r.rope.contacts.is_empty())
		metrics[kind + "_release"] = {"state": r.state, "reason": r.reason, "contacts": r.rope.contacts.size()}
		var jump_lengths := true
		var surface_clear := true
		var jump_max := 0.0
		for delay in [0, 12, 24, 36]:
			fixture(kind, Vector2(0, 180))
			r.a.position.x = -65
			r.b.position.x = 65
			for tick in range(180):
				r.step(DT, Vector2.ZERO, Vector2.ZERO, tick == 50, tick == 50 + delay)
				jump_max = maxf(jump_max, maxf(r.rope.length, r.rope.required))
				jump_lengths = jump_lengths and r.rope.required <= Run.LINK_LIMIT + 0.01
				var center: Vector2 = r.hazard_sample(0, r.elapsed).rect.get_center()
				var radius: float = r.obstacles[0].size.x * 0.5
				var z: PackedFloat32Array = r.rope.path_heights()
				for n in range(1, r.rope.path.size()):
					var p: Vector2 = r.rope.path[n - 1]
					var q: Vector2 = r.rope.path[n]
					var first := Vector3(p.x - center.x, p.y - center.y, z[n - 1] - radius)
					var delta := Vector3(q.x - center.x, q.y - center.y, z[n] - radius) - first
					var closest := first + delta * clampf(-first.dot(delta) / maxf(delta.length_squared(), 0.000001), 0, 1)
					surface_clear = surface_clear and closest.length() >= radius - 0.001
				if r.state == "failed": break
		check(kind + "错时跳跃截面变化不超长", jump_lengths)
		check(kind + "实际三维绳段不穿球", surface_clear)
		metrics[kind + "_jump_max_required"] = jump_max
	# 重定位保持相对位置、运动偏移、锁定证据和接触关系。
	fixture("stone_ball", Vector2(0, 6150))
	r.distance = 6000
	r.a.position = Vector2(-65, 6000)
	r.b.position = Vector2(65, 6000)
	r.rope.reset(r.a.position, r.b.position)
	r.hazard_specs[0].locked = true
	r.hazard_specs[0].offset = Vector2(0, -10)
	var relative: Vector2 = r.hazard_sample(0, 0).rect.get_center() - r.a.position
	r.next_segment = 100
	r.update_stream()
	check("重定位保持动态相对位置及锁定", r.hazard_sample(0, 0).rect.get_center() - r.a.position == relative and r.hazard_specs[0].locked and r.hazard_specs[0].offset == Vector2(0, -10) and r.rebases == 1)
	for kind in ["stone_ball", "iron_ball"]:
		fixture(kind, Vector2(0, 180))
		r.a.position.x = -65
		r.b.position.x = 65
		for tick in range(180):
			r.step(DT)
			if r.rope.touching() > 0: break
		var before_path: PackedVector2Array = r.rope.path.duplicate()
		var before_contact: Array = r.rope.contact_ids()
		var before_center: Vector2 = r.hazard_sample(0, 0).rect.get_center() - r.a.position
		var before_required: float = r.rope.required
		r.distance += 6000
		r.a.position.y += 6000
		r.b.position.y += 6000
		r.obstacles[0].position.y += 6000
		r.rope.shift(Vector2(0, 6000))
		r.next_segment = 100
		r.update_stream()
		check(kind + "带绳重定位保存接触与路径", not before_contact.is_empty() and r.rope.contact_ids() == before_contact and absf(r.rope.required - before_required) < 0.001 and (r.hazard_sample(0, 0).rect.get_center() - r.a.position).distance_to(before_center) < 0.001 and (r.rope.path[0] - before_path[0]).distance_to(Vector2(0, 1200)) < 0.001)
	# 节点池、球模型尺寸、滚动和生产场景同步。
	for kind in ["stone_ball", "iron_ball", "fly_low", "fly_body"]:
		fixture(kind, Vector2(0, 900))
		game.sync_view()
		var view = game.hazard_views[0]
		if Run.Threats.is_ball(kind):
			check(kind + "模型危险体同尺度", view.get_node("BallBody").mesh.radius * 20 == r.obstacles[0].size.x * 0.5)
		else:
			check(kind + "前方始终显示模型阴影", view.get_node("DangerVolume").visible and view.get_node("ThreatShadow").visible)
		r.step(DT)
		game.sync_view()
		if Run.Threats.is_ball(kind):
			check(kind + "滚动角度由真实位移驱动", is_equal_approx(view.get_node("BallBody").rotation.x, r.hazard_specs[0].travel / (r.obstacles[0].size.x * 0.5)) and view.get_node("BallBody").rotation.x > 0)
		r.revision += 1
		game.sync_view()
		check(kind + "节点池复用", game.hazard_views[0] == view)
	var failed := 0
	for item in checks:
		if not item.passed: failed += 1
	FileAccess.open("res://tests/short-rope-t03-result.json", FileAccess.WRITE).store_string(JSON.stringify({"passed": failed == 0, "checks": checks, "metrics": metrics}, "\t"))
	game.queue_free()
	await process_frame
	quit(0 if failed == 0 else 1)
