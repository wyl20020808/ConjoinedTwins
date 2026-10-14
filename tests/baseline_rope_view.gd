extends SceneTree

# 独立检查生产显示是否沿真实绕柱路径，并核对暂停与重试。
var failures := 0

func check(label: String, passed: bool) -> void:
	print("PASS " if passed else "FAIL ", label)
	if not passed: failures += 1

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var run = game.run
	run.cancel_generation()
	run.streaming = false
	run.obstacles.assign([Rect2(-12, 288, 24, 24)])
	run.kinds.assign(["pillar"])
	run.obstacle_heights.assign([100.0])
	run.hazard_specs.assign([{}])
	run.obstacle_ids.clear()
	run.retry()
	var wrapped := false
	var follows := true
	var clear := true
	for tick in range(500):
		run.step(1.0 / 120.0, Vector2.ZERO, Vector2.ZERO)
		game.sync_view()
		if run.rope.path.size() > 2:
			wrapped = true
			var path: PackedVector2Array = run.rope.path
			for point: Vector3 in game.rope_view.points:
				var ground := Vector2(point.x * 20.0, (run.distance / 20.0 - point.z) * 20.0)
				var gap := INF
				for n in range(1, path.size()):
					gap = minf(gap, ground.distance_to(Geometry2D.get_closest_point_to_segment(ground, path[n - 1], path[n])))
				follows = follows and gap < 0.02
				clear = clear and ground.distance_to(Vector2(0, 300)) >= 11.99
			break
	check("合法零轴输入确实产生绕柱路径", wrapped)
	check("可见绳索质点贴合生产绕障折线", wrapped and follows and clear)
	check("两端贴合双方腰部", game.rope_view.points[0].distance_to(game.robots[0].position + Vector3(0, 1.4, 0)) < 0.01 and game.rope_view.points[-1].distance_to(game.robots[1].position + Vector3(0, 1.4, 0)) < 0.01)
	var before: PackedVector3Array = game.rope_view.points.duplicate()
	game.apply_command("pause")
	game.sync_view()
	check("暂停定格真实绳索", before == game.rope_view.points)
	game.apply_command("retry")
	game.sync_view()
	check("重试清除绕柱接触并恢复两端", run.rope.contacts.is_empty() and run.rope.path.size() == 2 and game.rope_view.points[0].distance_to(game.robots[0].position + Vector3(0, 1.4, 0)) < 0.01)
	# 顶部装饰不能高于碰撞体，也不能与本体顶面共面闪烁。
	run.obstacles[0] = Rect2(-40, 0, 80, 65)
	run.obstacle_heights[0] = 60.0
	var cargo := Node3D.new()
	game.add_child(cargo)
	game.build_rock_block(cargo, 0)
	var tops: Array[float] = []
	for child in cargo.get_children():
		if child is MeshInstance3D:
			var bounds: AABB = child.mesh.get_aabb()
			tops.append(child.position.y + bounds.end.y)
	tops.sort()
	check("货箱总高度与碰撞一致且顶部避免共面", tops.size() == 3 and absf(tops[-1] - 3.0) < 0.001 and tops[1] - tops[0] > 0.005 and tops[2] - tops[1] > 0.005)
	run.obstacles.clear()
	run.kinds.clear()
	run.obstacle_heights.clear()
	run.hazard_specs.clear()
	run.retry()
	run.step(1.0 / 120.0)
	for tick in range(36):
		run.step(1.0 / 120.0, Vector2.ZERO, Vector2.ZERO, tick == 0, tick == 0)
	game.sync_view()
	for i in range(2):
		var player: AnimationPlayer = game.animation_players[i]
		check("跳跃顶点动画到达半程 P%d" % (i + 1), absf(run.heights[i] / 20.0 - 1.8) < 0.001 and player.is_playing() and absf(player.current_animation_position / player.current_animation_length - 0.5) < 0.02)
	game.queue_free()
	await process_frame
	print("BASELINE_ROPE_VIEW failures=", failures)
	quit(1 if failures else 0)
