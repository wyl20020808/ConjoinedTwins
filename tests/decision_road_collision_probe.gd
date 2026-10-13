extends SceneTree

# 决策者的隔离碰撞夹具：核对屏障可视表面与生产碰撞范围，不作为通关证据。
func _initialize() -> void:
	var run = load("res://scripts/road_run.gd").new()
	var index: int = run.kinds.find("energy")
	var obstacle: Rect2 = run.obstacles[index]
	run.retry()
	run.set_duo(true)
	run.a.position = Vector2(obstacle.get_center().x, obstacle.position.y - run.Motion.RADIUS - 1.0)
	run.b.position = Vector2(-42, run.a.position.y)
	run.clear_input = false
	var legal_start: bool = run.Motion.free_at(run.a.position, run.obstacles) and run.Motion.free_at(run.b.position, run.obstacles)
	run.step(1.0 / 60, 0.0, 0.0)
	# road_demo.gd 的能量面显示厚度为 0.2 米，位于障碍矩形中心。
	var visible_near_surface: float = obstacle.get_center().y / 20.0 - 0.1
	var report := {
		"fixture_not_completion_route": true,
		"legal_start": legal_start,
		"state_after_one_normal_step": run.state,
		"collision_depth_m": obstacle.size.y / 20.0,
		"visible_energy_plane_depth_m": 0.2,
		"visible_post_depth_m": 0.7,
		"robot_collision_front_m": (run.a.position.y + run.Motion.RADIUS) / 20.0,
		"invisible_gap_to_energy_plane_m": visible_near_surface - (run.a.position.y + run.Motion.RADIUS) / 20.0
	}
	var output := FileAccess.open("res://build-tools/art-demo/decision-review/collision-probe.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	run.dispose()
	quit(0 if legal_start else 1)
