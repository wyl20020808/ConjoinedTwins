extends SceneTree
# 短绳合作避险 t01：生产场景下的移动、跳跃、绳长与高度分类验证。
# 使用明确安全布局（关闭流式生成后手工放置危险），不依赖旧生成证书。
const Run = preload("res://scripts/road_run.gd")
const DT := 1.0 / 120.0
const SCALE := 20.0
var checks: Array = []
var metrics := {}
var game
var r

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)

func fixture(rects: Array = [], kinds: Array = [], tops: Array = []) -> void:
	r.streaming = false
	r.obstacles.assign(rects)
	r.kinds.assign(kinds)
	r.obstacle_heights.assign(tops)
	var specs: Array = []
	for kind in kinds: specs.append({})
	r.hazard_specs.assign(specs)
	r.revision += 1
	r.retry()
	r.step(0)

func tick(ia: Vector2 = Vector2.ZERO, ib: Vector2 = Vector2.ZERO, ja: bool = false, jb: bool = false) -> void:
	r.step(DT, ia, ib, ja, jb)

# 按给定按键时刻表驱动某一玩家，返回每个固定步后的高度。
func heights_for(player: int, pressed: Callable, ticks: int) -> Array:
	var result: Array = []
	for n in range(1, ticks + 1):
		var down: bool = pressed.call(n)
		tick(Vector2.ZERO, Vector2.ZERO, down and player == 0, down and player == 1)
		result.append(r.heights[player])
	return result

func takeoffs(profile: Array, previous: float = 0.0) -> Array:
	var result: Array = []
	for n in range(profile.size()):
		if profile[n] > 0.0 and previous == 0.0: result.append(n + 1)
		previous = profile[n]
	return result

func landing_tick(profile: Array) -> int:
	for n in range(1, profile.size()):
		if profile[n] == 0.0 and profile[n - 1] > 0.0: return n + 1
	return -1

func verify_jump() -> void:
	var landing := [0, 0]
	for player in range(2):
		fixture()
		var other_grounded := true
		var profile: Array = []
		for n in range(1, 121):
			tick(Vector2.ZERO, Vector2.ZERO, n == 1 and player == 0, n == 1 and player == 1)
			profile.append(r.heights[player])
			other_grounded = other_grounded and r.heights[1 - player] == 0.0 and r.vertical_speed[1 - player] == 0.0
		var peak := 0.0
		var peak_tick := 0
		for n in range(profile.size()):
			if profile[n] > peak:
				peak = profile[n]
				peak_tick = n + 1
		landing[player] = landing_tick(profile)
		var apex_time: float = peak_tick * DT
		var air_time: float = landing[player] * DT
		metrics["jump_p%d" % (player + 1)] = {"peak_m": peak / SCALE, "apex_s": apex_time, "air_s": air_time, "apex_fixed_steps": peak_tick, "air_fixed_steps": landing[player],
			"peak_error_m": peak / SCALE - 1.8, "apex_error_s": apex_time - 0.30, "air_error_s": air_time - 0.60}
		check("跳跃最高约 1.8 米 P%d" % (player + 1), absf(peak / SCALE - 1.8) <= 0.005)
		check("0.30 秒到顶 P%d（误差不超过一个固定步）" % (player + 1), absf(apex_time - 0.30) <= DT + 0.000001)
		check("0.60 秒腾空 P%d（误差不超过一个固定步）" % (player + 1), absf(air_time - 0.60) <= DT + 0.000001)
		check("独立跳跃：队友保持地面 P%d" % (player + 1), other_grounded and takeoffs(profile) == [1])
		# 60 帧调用（每帧两个固定步）得到同一抛物线。
		fixture()
		var coarse: Array = []
		for n in range(60):
			r.step(1.0 / 60, Vector2.ZERO, Vector2.ZERO, n == 0 and player == 0, n == 0 and player == 1)
			coarse.append(r.heights[player])
		var same := true
		for n in range(60): same = same and coarse[n] == profile[n * 2 + 1]
		check("帧率无关：60 帧与 120 帧抛物线一致 P%d" % (player + 1), same)
		var land: int = landing[player]
		fixture()
		var held: Array = heights_for(player, func(n): return true, 300)
		check("长按不重复触发 P%d" % (player + 1), takeoffs(held).size() == 1)
		fixture()
		var double: Array = heights_for(player, func(n): return n == 1 or n == 20, 300)
		check("无二段跳：空中再按不改变轨迹 P%d" % (player + 1), takeoffs(double) == [1] and double.slice(0, 120) == profile)
		fixture()
		var buffered: Array = heights_for(player, func(n): return n == 1 or n == land - 11, 300)
		check("缓冲窗口 0.10 秒内落地后起跳 P%d" % (player + 1), takeoffs(buffered) == [1, land + 1])
		fixture()
		var expired: Array = heights_for(player, func(n): return n == 1 or n == land - 12, 300)
		check("过期输入不起跳 P%d" % (player + 1), takeoffs(expired) == [1])
		fixture()
		var buffered_hold: Array = heights_for(player, func(n): return n == 1 or n >= land - 5, 400)
		check("缓冲起跳后长按不再重复 P%d" % (player + 1), takeoffs(buffered_hold) == [1, land + 1])
		# 暂停清除缓冲；恢复时仍按住的键不触发。
		fixture()
		heights_for(player, func(n): return n == 1 or n == land - 5, land - 3)
		var armed: bool = r.jump_buffer[player] > 0
		r.pause()
		var frozen := [r.elapsed, r.heights.duplicate(), r.vertical_speed.duplicate()]
		for n in range(20): tick(Vector2.ZERO, Vector2.ZERO, true, true)
		var still: bool = frozen == [r.elapsed, r.heights, r.vertical_speed] and r.jump_buffer == [0, 0]
		r.pause()
		var airborne_height: float = r.heights[player]
		var resumed: Array = heights_for(player, func(n): return n < 40, 300)
		check("暂停冻结并清除残留跳跃输入 P%d" % (player + 1), armed and still and airborne_height > 0 and takeoffs(resumed, airborne_height).is_empty() and r.heights == [0.0, 0.0])
		# 重试清除缓冲与空中状态；生产场景的 clear_controls 同样清除。
		fixture()
		heights_for(player, func(n): return n == 1 or n == land - 5, land - 3)
		armed = r.jump_buffer[player] > 0
		r.retry()
		var clean: bool = r.jump_buffer == [0, 0] and r.heights == [0.0, 0.0] and r.vertical_speed == [0.0, 0.0]
		var after: Array = heights_for(player, func(n): return n < 40, 300)
		check("重试清除残留跳跃输入 P%d" % (player + 1), armed and clean and takeoffs(after).is_empty())
		fixture()
		heights_for(player, func(n): return n == 1 or n == land - 5, land - 3)
		game.clear_controls()
		check("生产入口清除按键同时清除缓冲 P%d" % (player + 1), r.jump_buffer == [0, 0] and game.blocked_keys.size() == game.MOVE_KEYS.size())
	check("双方跳跃固定步数一致", landing[0] == landing[1])
	metrics["fixed_step_s"] = Run.FIXED_STEP
	metrics["substep_s"] = Run.FIXED_STEP / 3.0
	metrics["jump_buffer_s"] = Run.JUMP_BUFFER_STEPS * Run.FIXED_STEP

func mirror(v: Vector2) -> Vector2:
	return Vector2(-v.x, v.y)

func scripted(frame: int) -> Array:
	var ia := Vector2(sin(frame * 0.05), cos(frame * 0.031))
	var ib := Vector2(-cos(frame * 0.043), sin(frame * 0.027))
	if frame >= 200 and frame < 420:
		ia = Vector2(-1, 1)
		ib = Vector2(1, -1)
	elif frame >= 420 and frame < 600:
		ia = Vector2(1, -1)
		ib = Vector2(1, 1)
	return [ia, ib, frame % 90 >= 10 and frame % 90 < 14, frame % 70 >= 30 and frame % 70 < 33]

func verify_symmetry() -> void:
	fixture()
	var first: Array = []
	var legal := true
	var max_link := 0.0
	var max_offset := 0.0
	for frame in range(900):
		var input: Array = scripted(frame)
		r.step(1.0 / 60, input[0], input[1], input[2], input[3])
		first.append([r.a.position, r.b.position, r.heights[0], r.heights[1]])
		var link: float = r.a.position.distance_to(r.b.position)
		max_link = maxf(max_link, link)
		for p in [r.a.position, r.b.position]:
			max_offset = maxf(max_offset, absf(p.y - r.distance))
			legal = legal and absf(p.x) <= Run.EDGE and absf(p.y - r.distance) <= Run.RELATIVE_RANGE + 0.001
		legal = legal and link <= Run.LINK_LIMIT + 0.001
	check("混合输入全程：间距不超过 7.33 米且前后不超过 ±5 米", legal and r.state == "running")
	check("混合输入曾拉紧到新绳长", max_link > Run.LINK_LIMIT - 0.01)
	fixture()
	var deviation := 0.0
	for frame in range(900):
		var input: Array = scripted(frame)
		r.step(1.0 / 60, mirror(input[1]), mirror(input[0]), input[3], input[2])
		deviation = maxf(deviation, r.a.position.distance_to(mirror(first[frame][1])))
		deviation = maxf(deviation, r.b.position.distance_to(mirror(first[frame][0])))
		deviation = maxf(deviation, absf(r.heights[0] - first[frame][3]))
		deviation = maxf(deviation, absf(r.heights[1] - first[frame][2]))
	metrics["symmetry_max_deviation_units"] = deviation
	metrics["mixed_max_link_m"] = max_link / SCALE
	metrics["mixed_max_offset_m"] = max_offset / SCALE
	check("双方交换输入得到镜像对称结果", deviation <= 0.000001)

func hold(seconds: float, ia: Vector2, ib: Vector2) -> float:
	var worst := 0.0
	for n in range(int(seconds * 120)):
		tick(ia, ib)
		worst = maxf(worst, r.a.position.distance_to(r.b.position))
	return worst

func verify_range() -> void:
	fixture()
	hold(2.5, Vector2.ZERO, Vector2.ZERO)
	var link := hold(3, Vector2(0, 1), Vector2(0, 1))
	var front := [r.a.position.y - r.distance, r.b.position.y - r.distance]
	link = maxf(link, hold(4, Vector2(0, -1), Vector2(0, -1)))
	var back := [r.a.position.y - r.distance, r.b.position.y - r.distance]
	metrics["range_front_m"] = [front[0] / SCALE, front[1] / SCALE]
	metrics["range_back_m"] = [back[0] / SCALE, back[1] / SCALE]
	check("前后范围各 ±5 米（双方一致）", absf(front[0] - 100) < 0.001 and absf(front[1] - 100) < 0.001 and absf(back[0] + 100) < 0.001 and absf(back[1] + 100) < 0.001)
	# 一前一后：±5 米范围合计 10 米，大于绳长，实际间距由绳索约束。
	link = maxf(link, hold(4, Vector2(0, 1), Vector2(0, -1)))
	var split_ab: float = r.a.position.distance_to(r.b.position)
	var gap_ab: float = r.a.position.y - r.b.position.y
	link = maxf(link, hold(5, Vector2(0, -1), Vector2(0, 1)))
	var split_ba: float = r.a.position.distance_to(r.b.position)
	var gap_ba: float = r.b.position.y - r.a.position.y
	link = maxf(link, hold(4, Vector2(-1, 0), Vector2(1, 0)))
	var wide: float = r.a.position.distance_to(r.b.position)
	metrics["split_link_m"] = [split_ab / SCALE, split_ba / SCALE, wide / SCALE]
	metrics["split_longitudinal_gap_m"] = [gap_ab / SCALE, gap_ba / SCALE]
	metrics["range_max_link_m"] = link / SCALE
	check("前后错位被新绳长约束（两种站位对称）", absf(split_ab - Run.LINK_LIMIT) < 0.01 and absf(split_ba - Run.LINK_LIMIT) < 0.01 and absf(gap_ab - gap_ba) < 0.01 and gap_ab < 2 * Run.RELATIVE_RANGE)
	check("横向拉开被新绳长约束", absf(wide - Run.LINK_LIMIT) < 0.01)
	check("地面间距始终不超过 7.33 米", link <= Run.LINK_LIMIT + 0.001 and Run.LINK_LIMIT < Run.Motion.LIMIT)
	check("历史白盒共用绳长常量未改动", Run.Motion.LIMIT == 220.0 and Run.Motion.RADIUS == 12.0 and Run.Motion.SPEED == 180.0)

# 在全部起跳时机上尝试越过正前方危险，返回成功通过的次数。
func clear_count(player: int, rect: Rect2, kind: String, top: float, rush: bool) -> int:
	var passed := 0
	for press in range(60, 360):
		fixture([rect], [kind], [top])
		for n in range(1, 480):
			var move := Vector2.ZERO
			if rush: move = Vector2(0, -1) if n < press else Vector2(0, 1)
			tick(move if player == 0 else Vector2.ZERO, move if player == 1 else Vector2.ZERO, n == press and player == 0, n == press and player == 1)
			if r.state != "running": break
		if r.state == "running": passed += 1
	return passed

func verify_heights() -> void:
	var expected := {"pillar": false, "cargo": false, "rail": true, "spikes": true, "active_spikes": true, "scanner": false, "fly_low": true, "fly_body": false, "fly_tall": false}
	var table := true
	for kind in expected: table = table and Run.jump_clearable(kind) == expected[kind]
	check("高度分类表：低矮贴地可跳，其余必须绕行", table and Run.HAZARD_TOPS.size() == expected.size())
	check("高货箱高于跳跃最高点", Run.HAZARD_TOPS.cargo > Run.JUMP_APEX and is_equal_approx(Run.JUMP_APEX, 36.0))
	metrics["jump_apex_m"] = Run.JUMP_APEX / SCALE
	metrics["cargo_top_m"] = Run.HAZARD_TOPS.cargo / SCALE
	var counts := {}
	for player in range(2):
		var x := -62.0 if player == 0 else 22.0
		var tag := "p%d" % (player + 1)
		counts["cargo_" + tag] = clear_count(player, Rect2(x, 200, 40, 65), "cargo", Run.HAZARD_TOPS.cargo, false)
		counts["cargo_rush_" + tag] = clear_count(player, Rect2(x, 200, 40, 65), "cargo", Run.HAZARD_TOPS.cargo, true)
		counts["thin_cargo_height_" + tag] = clear_count(player, Rect2(x, 200, 40, 12), "cargo", Run.HAZARD_TOPS.cargo, true)
		counts["pillar_5m_" + tag] = clear_count(player, Rect2(x, 200, 40, 12), "cargo", 100.0, true)
		counts["rail_" + tag] = clear_count(player, Rect2(x, 200, 40, 12), "rail", Run.HAZARD_TOPS.rail, false)
	metrics["jump_over_successes_of_300_timings"] = counts
	check("高货箱任何起跳时机都不能越过（含冲刺起跳）", counts.cargo_p1 == 0 and counts.cargo_p2 == 0 and counts.cargo_rush_p1 == 0 and counts.cargo_rush_p2 == 0)
	check("货箱高度的薄墙同样不能越过（由高度而非厚度决定）", counts.thin_cargo_height_p1 == 0 and counts.thin_cargo_height_p2 == 0)
	check("5 米高柱夹具不能越过", counts.pillar_5m_p1 == 0 and counts.pillar_5m_p2 == 0)
	check("低栏可跳过且双方可行时机数一致", counts.rail_p1 > 0 and counts.rail_p1 == counts.rail_p2)
	fixture([Rect2(-62, 200, 40, 12)], ["rail"], [Run.HAZARD_TOPS.rail])
	for n in range(480): tick()
	check("不跳会撞低栏并共同失败", r.state == "failed" and r.actions == ["Hit", "Hit"])

func verify_view() -> void:
	fixture([Rect2(150, 900, 80, 65)], ["cargo"], [Run.HAZARD_TOPS.cargo])
	game.sync_view()
	var view: Node3D = game.hazard_views[0]
	var bounds: AABB = game.model_bounds(view, view)
	metrics["cargo_model_height_m"] = bounds.size.y
	check("高货箱模型与碰撞高度一致且高于跳跃最高点", game.hazard_views.size() == 1 and absf(bounds.size.y - Run.HAZARD_TOPS.cargo / SCALE) < 0.05 and bounds.size.y > Run.JUMP_APEX / SCALE)
	check("界面显示新绳长", game.distance_label.text.contains("7.33"))
	for player in range(2):
		fixture()
		var synced := true
		var animated := true
		var progress := -1.0
		var min_shadow := 1.0
		for n in range(1, 100):
			tick(Vector2.ZERO, Vector2.ZERO, n == 1 and player == 0, n == 1 and player == 1)
			game.sync_view()
			var forward: float = r.distance / SCALE
			for i in range(2):
				var p: Vector2 = r.a.position if i == 0 else r.b.position
				var ground := Vector3(p.x / SCALE, 0.018, -p.y / SCALE + forward)
				synced = synced and is_equal_approx(game.robots[i].position.y, r.heights[i] / SCALE) and game.shadows[i].position.is_equal_approx(ground)
				synced = synced and is_equal_approx(game.robots[i].position.x, ground.x) and is_equal_approx(game.robots[i].position.z, ground.z)
				synced = synced and is_equal_approx(game.shadows[i].scale.x, 1.0 - 0.36 * r.heights[i] / Run.JUMP_APEX + r.land_time[i] * 1.2)
				var player_node: AnimationPlayer = game.animation_players[i]
				var airborne: bool = r.heights[i] > 0
				animated = animated and player_node.current_animation.ends_with("Jump" if airborne else "Run")
				if airborne:
					var now: float = player_node.current_animation_position / player_node.current_animation_length
					animated = animated and i == player and now >= progress and absf(now - n * DT / 0.6) < 0.02
					progress = now
					min_shadow = minf(min_shadow, game.shadows[i].scale.x)
		metrics["shadow_scale_at_apex_p%d" % (player + 1)] = min_shadow
		check("角色高度、地面阴影与碰撞状态同源 P%d" % (player + 1), synced and absf(min_shadow - 0.64) < 0.001)
		check("跳跃动画按生产抛物线进度同步 P%d" % (player + 1), animated and progress > 0.95)
	fixture()
	game.sync_view()
	var relaxed: Color = game.cable_material.albedo_color
	hold(3, Vector2(-1, 0), Vector2(1, 0))
	game.sync_view()
	check("连线在新绳长 85% 以上变金色", relaxed == Color("60e4ea") and game.cable_material.albedo_color == Color("ffc06b"))

func verify() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	r = game.run
	check("生产配置：绳长 7.33 米、前后 ±5 米、初速 12 米/秒、重力 40 米/秒²、缓冲 0.10 秒",
		is_equal_approx(Run.LINK_LIMIT / SCALE, 7.33) and Run.RELATIVE_RANGE / SCALE == 5.0 and Run.JUMP_SPEED / SCALE == 12.0 and Run.GRAVITY / SCALE == 40.0 and is_equal_approx(Run.JUMP_BUFFER_STEPS * Run.FIXED_STEP, Run.JUMP_BUFFER))
	verify_jump()
	verify_symmetry()
	verify_range()
	verify_heights()
	verify_view()
	var failures := 0
	for item in checks:
		if not item.passed: failures += 1
	var file := FileAccess.open("res://tests/short-rope-t01-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures == 0, "failures": failures, "checks": checks, "metrics": metrics}, "\t"))
	file.close()
	print("RESULT failures=", failures, " metrics=", JSON.stringify(metrics))
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
