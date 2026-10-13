extends SceneTree

const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
var metrics: Array = []
var game
var r

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)

# 独立地面几何审计，不用被测实现的实体安全判定作为通过依据。
func body_clear(from: Vector2, to: Vector2) -> bool:
	var shape: Rect2 = r.obstacles[0]
	if r.kinds[0] == "cargo": return not Run.segment_hits(from, to, shape.grow(Run.Motion.RADIUS - 0.002))
	return Run.Rope.segment_distance(from, to, shape.get_center()) >= shape.size.x * 0.5 + Run.Motion.RADIUS - 0.002

func fixture(kind: String, swapped: bool, taut: bool) -> void:
	r.streaming = false
	r.state = "running"
	r.obstacles.clear()
	r.kinds.clear()
	r.obstacle_heights.clear()
	r.hazard_specs.clear()
	r.obstacle_ids.clear()
	r.retry()
	r.step(0)
	# 起点 y=0 禁止后退；在已推进的路段测试回撤，原 y=0 缺陷另由决策探针复现。
	var front := Vector2(-42, 300)
	var back := Vector2(42, 300 + sqrt(Run.LINK_LIMIT * Run.LINK_LIMIT - 84 * 84) - (0.0002 if taut else 15))
	r.a.position = back if swapped else front
	r.b.position = front if swapped else back
	r.distance = (front.y + back.y) * 0.5
	r.rope.reset(r.a.position, r.b.position)
	var shape := Rect2(-65, 12, 46, 60) if kind == "cargo" else Rect2(-54, 12, 24, 24)
	shape.position.y += 300
	r.obstacles.assign([shape])
	r.kinds.assign([kind])
	r.obstacle_heights.assign([60.0 if kind == "cargo" else 100.0])
	r.hazard_specs.assign([{}])
	r.shield = true

func verify() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.capture_mode = true
	r = game.run
	for kind in ["cargo", "pillar"]:
		for swapped in [false, true]:
			for taut in [false, true]:
				fixture(kind, swapped, taut)
				var legal := true
				var movement := true
				var bounds := true
				var max_length := 0.0
				for tick in range(125):
					var pa: Vector2 = r.a.position
					var pb: Vector2 = r.b.position
					r.step(Run.FIXED_STEP)
					legal = legal and body_clear(pa, r.a.position) and body_clear(pb, r.b.position)
					movement = movement and pa.distance_to(r.a.position) <= (Run.FORWARD + Run.LATERAL) * Run.FIXED_STEP + 0.01 and pb.distance_to(r.b.position) <= (Run.FORWARD + Run.LATERAL) * Run.FIXED_STEP + 0.01
					bounds = bounds and absf(r.a.position.y - r.distance) <= Run.RELATIVE_RANGE + 0.01 and absf(r.b.position.y - r.distance) <= Run.RELATIVE_RANGE + 0.01
					max_length = maxf(max_length, r.rope.required)
				var name := "%s 交换%s 拉满%s" % [kind, swapped, taut]
				check(name + "每步实体扫掠不穿入", legal)
				check(name + "硬绳长/边界/位移同时合法", max_length <= Run.LINK_LIMIT + 0.01 and bounds and movement)
				check(name + "护盾只消耗一次且到期失败", r.shield_uses == 1 and r.state == "failed")
				metrics.append({"case": name, "maximum_link_units": max_length, "a": [r.a.position.x, r.a.position.y], "b": [r.b.position.x, r.b.position.y], "distance": r.distance})
				fixture(kind, swapped, taut)
				for tick in range(5): r.step(Run.FIXED_STEP)
				# 先受击，再以真实输入滑行与回撤；角色交换也必须可解围。
				var before: Vector2 = r.b.position if swapped else r.a.position
				legal = true
				for tick in range(30):
					var pa: Vector2 = r.a.position
					var pb: Vector2 = r.b.position
					r.step(Run.FIXED_STEP, Vector2.RIGHT, Vector2.RIGHT)
					legal = legal and body_clear(pa, r.a.position) and body_clear(pb, r.b.position) and r.rope.required <= Run.LINK_LIMIT + 0.01
				var after: Vector2 = r.b.position if swapped else r.a.position
				check(name + "沿面滑行不穿障碍", legal and after.x > before.x + 10 and r.state == "running")
				fixture(kind, swapped, taut)
				for tick in range(5): r.step(Run.FIXED_STEP)
				before = r.b.position if swapped else r.a.position
				for tick in range(20): r.step(Run.FIXED_STEP, Vector2(0, -1), Vector2(0, -1))
				after = r.b.position if swapped else r.a.position
				check(name + "回撤可离开接触面", r.state == "running" and after.y < before.y and r.rope.required <= Run.LINK_LIMIT + 0.01)
	# 前后站位判据；中心进入判据与显示圈半径一致。
	var center := Vector2(154, 100)
	var cases := [
		["同点", center, center, false],
		["同一个前圈", center + Vector2(0, 30), center + Vector2(1, 30), false],
		["仅一人到位", center + Vector2(0, 30), center + Vector2(80, -30), false],
		["中线两侧不足分站", center + Vector2(0, 0.5), center - Vector2(0, 0.5), false],
		["真实前后站位", center + Vector2(0, 30), center - Vector2(0, 30), true],
		["交换角色站位", center - Vector2(0, 30), center + Vector2(0, 30), true],
		["光圈边缘合法", center + Vector2(25, 30), center + Vector2(-25, -30), true]
	]
	for entry in cases:
		r.prizes = 0
		r.claimed_rewards.clear()
		r.a.position = entry[1]
		r.b.position = entry[2]
		r.rewards.assign([{"id": "edge", "kind": "prize", "position": center, "radius": 26.0, "staggered": true, "claimed": false}])
		for repeat in range(5): r.collect_rewards(r.a.position, r.b.position)
		check("前后奖品：" + entry[0], r.prizes == (1 if entry[3] else 0) and r.rewards[0].claimed == entry[3])
	r.prizes = 0
	r.claimed_rewards.clear()
	r.a.position = center
	r.b.position = center
	r.rewards[0].claimed = false
	r.rewards[0].radius = 100.0
	r.collect_rewards(center, center)
	game.sync_rewards()
	check("超大配置仍禁止圈重叠且表现半径同源", r.prizes == 0 and is_equal_approx(game.reward_views[0].get_node("Socket0").mesh.top_radius, Run.Levels.PRIZE_SOCKET_MAX_RADIUS / game.SCALE))
	var failed := 0
	for entry in checks:
		if not entry.passed: failed += 1
	var file := FileAccess.open("res://tests/short-rope-t04-edges-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failed == 0, "failed": failed, "checks": checks, "metrics": metrics}, "\t"))
	file.close()
	game.queue_free()
	quit(0 if failed == 0 else 1)
