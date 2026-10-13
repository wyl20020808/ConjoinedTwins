extends SceneTree

const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
var failed := 0
var route_constraints := true
var maximum_link := 0.0

func check(condition: bool, name: String) -> void:
	checks.append({"name": name, "pass": condition})
	if not condition:
		failed += 1
		push_error(name)

func drive(r, frames: int) -> void:
	for i in range(frames):
		var target: float = r.safe_target(r.a.position, -42.0)
		r.step(1.0 / 60, r.steering(r.a.position, target))
		maximum_link = maxf(maximum_link, r.a.position.distance_to(r.b.position))
		route_constraints = route_constraints and r.a.position.distance_to(r.b.position) <= 220.001
		route_constraints = route_constraints and Run.Motion.free_at(r.a.position, r.obstacles) and Run.Motion.free_at(r.b.position, r.obstacles)
		if r.state != "running":
			break

func _initialize() -> void:
	call_deferred("test")

func test() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var r = game.run
	var camera_transform: Transform3D = game.camera.transform
	check(r.state == "start", "生产入口开始页，不自动启动")
	game.primary_action()
	var before: Vector2 = r.a.position
	drive(r, 60)
	check(r.a.position.y > before.y + 110 and r.b.position.y > 110, "双方自动推进")
	r.pause()
	var frozen: Vector2 = r.a.position
	var time: float = r.elapsed
	r.step(1.0, 1, -1)
	check(r.a.position == frozen and r.elapsed == time, "暂停冻结位置与计时")
	r.pause()
	var mode_a: Vector2 = r.a.position
	var mode_b: Vector2 = r.b.position
	r.set_duo(true)
	check(r.a.position == mode_a and r.b.position == mode_b, "模式切换无瞬移")
	for i in range(100):
		r.step(1.0 / 60, -1, 1)
	check(r.a.position.distance_to(r.b.position) <= 220.001, "反向输入达到连线极限仍受约束")
	check(r.a.position.x < mode_a.x - 40 and r.b.position.x > mode_b.x + 40, "本地双人方向分别生效且保留切换位置")
	r.retry()
	for i in range(160):
		r.step(1.0 / 60, -1, -1)
	check(r.a.position.x >= -156.001 and r.b.position.x >= -156.001, "双方受道路边界约束")
	r.retry()
	r.set_duo(false)
	drive(r, 6000)
	check(r.state == "finished", "正常横向输入与生产离线 AI 完成三段道路")
	check(r.elapsed >= 60 and r.elapsed <= 90, "无失败通关用时 60—90 秒")
	check(r.a.position.y >= 9000 and r.b.position.y >= 9000, "双方共同终点")
	check(route_constraints, "通关路线每步检查碰撞与连接合法性")
	game.sync_view()
	check(game.robots.size() == 2 and game.camera.transform == camera_transform, "生产入口建立双角色且全程镜头变换固定")
	var final_a: Vector2 = r.a.position
	var final_b: Vector2 = r.b.position
	var final_time: float = r.elapsed
	r.retry()
	drive(r, 6000)
	check(r.a.position == final_a and r.b.position == final_b and r.elapsed == final_time, "相同输入下 AI 和结局确定性")
	# 失败路线也只发送普通方向，未设置生产角色位置。
	r.retry()
	r.set_duo(true)
	for i in range(600):
		r.step(1.0 / 60, -0.12, 0.0)
		if r.state == "failed": break
	check(r.state == "failed", "玩家一触碰障碍共同失败")
	check(not Run.Motion.free_at(r.a.position + Vector2(0, 2), r.obstacles), "碰撞扫掠停在障碍前，无穿透")
	r.retry(true)
	check(r.a.position == Vector2(-42, 0) and r.b.position == Vector2(42, 0) and r.elapsed == 0, "失败后双方共同重试恢复合法出生点")
	for i in range(600):
		r.step(1.0 / 60, 0, -0.30)
		if r.state == "failed": break
	check(r.state == "failed", "玩家二触碰障碍同样共同失败")
	var solo = Run.new()
	solo.retry()
	# 专项终点条件隔离：设置夹具位置，不作为通关路线证据。
	solo.a.position = Vector2(-42, 9001)
	solo.b.position = Vector2(42, 8990)
	solo.clear_input = false
	solo.step(1.0 / 60, 0)
	check(solo.state == "running", "单人先到终点不能提前完成")
	solo.dispose()
	# 屏障专项合法位置夹具，不作为通关路线证据。
	var energy_index: int = r.kinds.find("energy")
	var rect: Rect2 = r.obstacles[energy_index]
	var visual_matches := false
	for chunk in game.scenery:
		if chunk.get_meta("energy_index", -1) == energy_index:
			var volume = chunk.get_node("DangerVolume")
			var footprint = chunk.get_node("DangerFootprint")
			visual_matches = is_equal_approx(volume.mesh.size.x * game.SCALE, rect.size.x) and is_equal_approx(volume.mesh.size.z * game.SCALE, rect.size.y)
			visual_matches = visual_matches and is_equal_approx(footprint.mesh.size.x, volume.mesh.size.x) and is_equal_approx(footprint.mesh.size.z, volume.mesh.size.z)
			visual_matches = visual_matches and is_equal_approx(-chunk.position.z * game.SCALE, rect.get_center().y)
	check(visual_matches, "能量屏障可见体积与地面投影覆盖真实碰撞矩形")
	for actor in range(2):
		var probe = Run.new()
		probe.retry()
		probe.set_duo(true)
		probe.clear_input = false
		probe.a.position = Vector2(0, rect.position.y - 50)
		probe.b.position = Vector2(0, rect.position.y - 50)
		var subject = probe.a if actor == 0 else probe.b
		subject.position = Vector2(rect.get_center().x, rect.position.y - Run.Motion.RADIUS - 32)
		probe.step(1.0 / 60, 0, 0)
		check(probe.state == "running", "角色%d 尚未接触可见屏障前缘时不提前失败" % (actor + 1))
		subject.position.y = rect.position.y - Run.Motion.RADIUS - 1.0
		probe.step(1.0 / 60, 0, 0)
		check(probe.state == "failed", "角色%d 接触可见屏障前缘共同失败" % (actor + 1))
		probe.retry(true)
		check(probe.a.position == Vector2(-42, 0) and probe.b.position == Vector2(42, 0) and probe.elapsed == 0 and probe.failures == 1, "角色%d 屏障失败后双方合法共同重试" % (actor + 1))
		for side in [-1, 1]:
			probe.retry()
			probe.clear_input = false
			probe.a.position = Vector2(0, rect.position.y - 50)
			probe.b.position = Vector2(0, rect.position.y - 50)
			var edge: float = rect.position.x if side == -1 else rect.end.x
			subject.position = Vector2(edge + side * (Run.Motion.RADIUS + 0.1), rect.position.y - 20)
			probe.step(0.1, 0, 0)
			check(probe.state == "running", "角色%d 屏障%s边界外擦边可通过" % [actor + 1, "左" if side == -1 else "右"])
			subject.position = Vector2(edge + side * (Run.Motion.RADIUS - 0.1), rect.position.y - 20)
			probe.step(0.1, 0, 0)
			check(probe.state == "failed", "角色%d 屏障%s边界内擦碰共同失败" % [actor + 1, "左" if side == -1 else "右"])
		probe.dispose()
	var hashes := {}
	for file in ["scripts/road_run.gd", "scripts/road_demo.gd", "scripts/link_motion.gd", "scenes/road_demo.tscn", "project.godot"]:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(FileAccess.get_file_as_bytes("res://" + file))
		hashes[file] = context.finish().hex_encode()
	var report := {"self_test": "pass" if failed == 0 else "failed", "checks": checks, "count": checks.size(), "failures": failed,
		"finish_seconds": final_time, "maximum_route_link": maximum_link, "source_sha256": hashes, "controller_tests": [], "decision_review": "pending", "user_playtest": "pending"}
	var output := FileAccess.open("res://tests/road_result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	game.queue_free()
	await process_frame
	quit(0 if failed == 0 else 1)
