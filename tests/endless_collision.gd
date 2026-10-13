extends SceneTree
const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
func _initialize() -> void:
	call_deferred("verify")
func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)
func verify() -> void:
	for player in range(2):
		var r = Run.new()
		# 无限生成与明确碰撞夹具分离；使用相同生产固定步碰撞。
		r.streaming = false
		r.obstacles.assign([Rect2(-55 if player == 0 else 29, 149.333333333333, 26, 8)])
		r.kinds.assign(["active_spikes"])
		r.obstacle_heights.assign([16.0])
		r.hazard_specs.assign([{"period": 4.0, "warning": 1.0, "active": 1.5, "phase": 0.0}])
		r.retry()
		r.step(0)
		for frame in range(120): r.step(1.0 / 60, Vector2.ZERO, Vector2.ZERO, frame >= 63 and player == 0, frame >= 63 and player == 1)
		check("动态刺高合法跳跃 P" + str(player + 1), r.state == "running")
		r.obstacles[0] = Rect2(-205 if player == 0 else 179, 35, 26, 8)
		r.kinds[0] = "fly_body"
		r.obstacle_heights[0] = 38
		r.hazard_specs[0] = {"bottom": 18.0, "trigger": 0.25, "flight_duration": 1.0, "velocity": Vector2(108000 if player == 0 else -108000, 0)}
		r.retry()
		r.step(0)
		for frame in range(30): r.step(1.0 / 60, Vector2(0, -1) if player == 1 else Vector2.ZERO)
		check("高速飞行扫掠 P" + str(player + 1), r.state == "failed" and r.reason.begins_with("%02d" % (player + 1)))
		r.retry()
		r.step(0)
		check("重试双人合法状态", r.a.position.distance_to(r.b.position) <= Run.LINK_LIMIT + 0.001 and r.heights == [0.0, 0.0] and r.state == "running")
		r.dispose()
	var failures := 0
	for item in checks:
		if not item.passed: failures += 1
	var file := FileAccess.open("res://tests/endless-collision-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": failures == 0}, "\t"))
	quit(0 if failures == 0 else 1)
