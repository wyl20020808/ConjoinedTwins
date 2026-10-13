extends SceneTree
const Run = preload("res://scripts/road_run.gd")
var game
var checks: Array = []

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)

# 场景夹具将生产危险移至出生附近，仍走完整生产固定步与危险采样。
func fixture(kind: String, player: int, y: float = 45):
	var r = game.run
	r.retry()
	var index: int = r.kinds.find(kind)
	var spec: Dictionary = r.hazard_specs[index].duplicate()
	var top: float = r.obstacle_heights[index]
	r.obstacles.assign([Rect2(-55 if player == 0 else 29, y, 26, 8)])
	r.kinds.assign([kind])
	r.obstacle_heights.assign([top])
	r.hazard_specs.assign([spec])
	r.step(1.0 / 60)
	return r

func ticks(r, count: int, ja: bool = false, jb: bool = false, first := Vector2.ZERO, second := Vector2.ZERO) -> void:
	for i in range(count): r.step(1.0 / 60, first, second, ja, jb)

func restore(rects: Array, kinds: Array, tops: Array, specs: Array) -> void:
	game.run.obstacles.assign(rects)
	game.run.kinds.assign(kinds)
	game.run.obstacle_heights.assign(tops)
	game.run.hazard_specs.assign(specs)

func verify() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var r = game.run
	var rects: Array = r.obstacles.duplicate()
	var kinds: Array = r.kinds.duplicate()
	var tops: Array = r.obstacle_heights.duplicate()
	var specs: Array = r.hazard_specs.duplicate(true)
	for kind in ["cargo", "rail", "spikes", "active_spikes", "scanner", "fly_low", "fly_body", "fly_tall"]:
		check("生产危险及视图 " + kind, kinds.has(kind) and game.hazard_views.size() == rects.size())
		for player in range(2):
			restore(rects, kinds, tops, specs)
			r = fixture(kind, player)
			if kind in ["active_spikes", "scanner"]: r.hazard_specs[0].phase = 1.0
			if kind.begins_with("fly_"):
				r.hazard_specs[0].trigger = 0.0
				r.hazard_specs[0].velocity = Vector2.ZERO
			ticks(r, 35)
			check("双方致命命中 " + kind + " P" + str(player + 1), r.state == "failed" and r.reason.begins_with("%02d" % (player + 1)) and r.actions == ["Hit", "Hit"])
	for kind in ["rail", "spikes", "fly_low"]:
		for player in range(2):
			restore(rects, kinds, tops, specs)
			r = fixture(kind, player)
			if kind == "fly_low":
				r.hazard_specs[0].trigger = 0.0
				r.hazard_specs[0].velocity = Vector2.ZERO
			ticks(r, 35, player == 0, player == 1)
			check("腾空跨越 " + kind + " P" + str(player + 1), r.state == "running")
	for y in [4.0, 108.0]:
		restore(rects, kinds, tops, specs)
		r = fixture("spikes", 0, y)
		ticks(r, 70, true)
		check("地刺覆盖起跳或落地位置 " + str(y), r.state == "failed")
	restore(rects, kinds, tops, specs)
	r = fixture("active_spikes", 0)
	check("活动地刺预警不致命", r.hazard_sample(0, 0.5).warning and not r.hazard_sample(0, 0.5).active)
	check("活动地刺伸出阶段", r.hazard_sample(0, 1.1).stage == "extend" and r.hazard_sample(0, 1.1).top > 0)
	check("活动地刺完整伸出", r.hazard_sample(0, 1.5).top == 16)
	check("活动地刺回落阶段", r.hazard_sample(0, 2.4).stage == "retract" and r.hazard_sample(0, 2.4).top < 16)
	check("活动地刺收回安全", not r.hazard_sample(0, 3).active and r.hazard_sample(0, 3).top == 0)
	ticks(r, 35)
	check("生产预警窗口实际可通行", r.state == "running")
	restore(rects, kinds, tops, specs)
	r = fixture("scanner", 0)
	ticks(r, 35)
	check("扫描束安全时窗通行", r.state == "running")
	for player in range(2):
		restore(rects, kinds, tops, specs)
		r = fixture("fly_body", player, 35)
		r.obstacles[0].position.x -= 150
		r.hazard_specs[0].trigger = 0.25
		r.hazard_specs[0].velocity = Vector2(108000, 0)
		ticks(r, 30)
		check("高速飞行物单子步穿越捕获 P" + str(player + 1), r.state == "failed")
	for direction in [-1, 1]:
		restore(rects, kinds, tops, specs)
		r = fixture("fly_body", 0, 42)
		r.hazard_specs[0].trigger = 0.3
		r.hazard_specs[0].flight_duration = 0.05
		r.hazard_specs[0].velocity = Vector2.ZERO
		ticks(r, 30, false, false, Vector2(0, direction), Vector2(0, direction))
		check("飞行物前后避让 " + str(direction), r.state == "running")
	check("同一时刻求交避免高度与平面错时误判", not Run.swept_body_hits(Vector2(-100, 0), Vector2(100, 0), 0, 100, Rect2(80, -2, 5, 4), 0, 10))
	restore(rects, kinds, tops, specs)
	r.retry()
	for time in [0.5, 1.1, 2.4, 3.0]:
		r.elapsed = time
		game.sync_view()
		var sample: Dictionary = r.hazard_sample(3, time)
		var view: Node3D = game.hazard_views[3]
		var volume: MeshInstance3D = view.get_node("DangerVolume")
		var matches: bool = volume.visible == sample.active and is_equal_approx(volume.mesh.size.y, maxf(0.001, sample.top / 20))
		for child in view.get_children():
			if child.has_meta("spike"):
				matches = matches and is_equal_approx(child.position.y, sample.top / 40)
		check("地刺视觉高度和周期同步 " + str(time), matches)
	r.retry()
	r.step(1.0 / 60)
	var initial: Dictionary = r.hazard_sample(3, r.elapsed)
	ticks(r, 20, true)
	r.retry()
	game.sync_view()
	check("重试恢复周期高度动作输入", r.elapsed == 0 and r.heights == [0.0, 0.0] and r.actions == ["Idle", "Idle"] and r.clear_input and r.hazard_sample(3, 0).stage == initial.stage)
	check("重试恢复动画连线合法", game.animation_players[0].current_animation.ends_with("Run") and is_equal_approx(game.cable.position.y, 1.4) and not game.failed_animation_started[0])
	var failures := 0
	for item in checks:
		if not item.passed: failures += 1
	var file := FileAccess.open("res://tests/obstacles-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures == 0, "checks": checks, "failures": failures, "scope": "生产场景及明确危险夹具，执行者自测"}, "\t"))
	print("OBSTACLES ", checks.size(), " checks ", failures, " failures")
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
