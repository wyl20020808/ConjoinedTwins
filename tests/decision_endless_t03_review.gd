extends SceneTree
const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
var peak_hazards := 0
var peak_nodes := 0
var live_game
func count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children(): count += count_nodes(child)
	return count
func _initialize() -> void:
	call_deferred("verify")
func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)
func drive(r, seconds: float) -> void:
	for frame in range(int(seconds * 60)):
		# 联合证书中心；先以合法横移到达，再维持前后错位。
		var ia := Vector2(clampf((175 - r.a.position.x) / 10, -1, 1), clampf((r.distance + 35 - r.a.position.y) / 15, -1, 1))
		var ib := Vector2(clampf((215 - r.b.position.x) / 10, -1, 1), clampf((r.distance - 35 - r.b.position.y) / 15, -1, 1))
		r.step(1.0 / 60, ia, ib, frame > 180 and frame % 120 < 30, frame > 180 and frame % 120 >= 60 and frame % 120 < 90)
		peak_hazards = maxi(peak_hazards, r.obstacles.size())
		if frame % 300 == 0:
			live_game.sync_view()
			peak_nodes = maxi(peak_nodes, count_nodes(live_game))
		if r.state != "running": return
func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	live_game = game
	check("生产默认普通、三种难度可选", game.run.difficulty == "普通" and game.difficulty_buttons.size() == 3)
	var base_nodes: int = game.get_child_count()
	for difficulty in Run.Templates.DIFFICULTIES:
		for seed_value in [11, 42, 20261012]:
			var r = game.run
			r.difficulty = difficulty
			r.seed_value = seed_value
			r.retry()
			var start_layout: Array = r.obstacles.duplicate()
			drive(r, 110)
			game.sync_view()
			var snapshot := [r.a.position, r.b.position, r.total_distance(), r.kinds.duplicate(), r.obstacles.duplicate()]
			check("联合通路/前后错位/跨段 " + difficulty + str(seed_value), r.state == "running" and r.a.position.distance_to(r.b.position) <= Run.Motion.LIMIT and r.a.position.y > r.b.position.y + 50 and r.total_distance() > 9000)
			check("回收与坐标重定位 " + difficulty + str(seed_value), r.rebases >= 1 and r.recycled > 0 and r.distance < 6000 and r.obstacles.size() <= Run.Templates.MAX_HAZARDS and game.hazard_views.size() == r.obstacles.size() and game.get_child_count() == base_nodes)
			r.retry()
			check("重试种子布局一致 " + difficulty + str(seed_value), start_layout == r.obstacles)
			drive(r, 110)
			check("相同种子输入完整复现 " + difficulty + str(seed_value), snapshot == [r.a.position, r.b.position, r.total_distance(), r.kinds.duplicate(), r.obstacles.duplicate()])
		var r = game.run
		var frozen := [r.elapsed, r.distance, r.next_segment, r.revision, r.generator.rng.state]
		r.pause()
		drive(r, 1)
		check("暂停冻结周期生成和推进 " + difficulty, frozen == [r.elapsed, r.distance, r.next_segment, r.revision, r.generator.rng.state])
		check("速度增长不超上限 " + difficulty, r.speed() <= Run.Templates.DIFFICULTIES[difficulty].cap)
	var g = Run.Templates.new()
	g.reset(42)
	check("无解联合模板拒绝", not g.validate_joint([{"rect": Rect2(-234, 100, 468, 60), "velocity": Vector2.ZERO}]))
	for i in range(100): g.generate(i, "困难")
	check("实际生成拒绝和安全回退证据", g.rejected > 0 and g.fallbacks == g.rejected)
	var r = game.run
	r.seed_value = 42
	r.difficulty = "困难"
	r.retry()
	drive(r, 370)
	game.sync_view()
	check("长距离多次重定位且无固定终点", r.state == "running" and r.rebases >= 9 and r.recycled > 100 and r.total_distance() > 50000 and r.distance < 6000 and r.obstacles.size() <= Run.Templates.MAX_HAZARDS)
	check("累计距离及局部精度一致", is_equal_approx(r.total_distance(), r.world_origin + r.distance) and absf(r.a.position.y - r.distance) <= Run.RELATIVE_RANGE and absf(r.b.position.y - r.distance) <= Run.RELATIVE_RANGE)
	check("全程活动危险和节点数量有界", peak_hazards <= Run.Templates.MAX_HAZARDS and peak_nodes < Run.Templates.MAX_SCENE_NODES)
	var failures := 0
	for item in checks:
		if not item.passed: failures += 1
	var file := FileAccess.open("res://tests/decision-endless-t03-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures == 0, "checks": checks, "failures": failures, "fallbacks": g.fallbacks, "fallback_evidence": g.rejection_evidence, "final_distance": r.total_distance(), "rebases": r.rebases, "hazards": r.obstacles.size(), "peak_hazards": peak_hazards, "peak_nodes": peak_nodes, "road_slots": 63}, "\t"))
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
