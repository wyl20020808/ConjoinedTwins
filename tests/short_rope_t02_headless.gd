extends SceneTree
# 短绳合作避险 t02：生产场景下的静态圆柱绳索求解、受阻、解围与失败反馈验证。
# 使用明确安全布局（关闭流式生成后手工放置高柱），每个固定步都审计长度上限、穿柱、绕行侧和位移。
const Run = preload("res://scripts/road_run.gd")
const Rope = preload("res://scripts/rope_solver.gd")
const DT := 1.0 / 120.0
const SCALE := 20.0
const PILLAR := 12.0
const BLOCK_TICKS := 96
var checks: Array = []
var metrics := {}
var game
var r
var audit := {}

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)

func reset_audit() -> void:
	audit = {"max_length": 0.0, "min_rope_clearance": INF, "min_body_clearance": INF, "side_flips": 0, "attaches": 0, "detaches": 0,
		"max_move": 0.0, "ends_ok": true, "max_polyline_gap": 0.0, "sides": {}, "ticks": 0,
		"penetrations": 0, "worst_penetration": 0.0, "over_ticks": 0, "over_growth": 0, "max_over": 0.0, "last_length": 0.0, "last_heights": [0.0, 0.0]}

func fixture(centers: Array, top: float = 100.0, start_y: float = 0.0, keep_audit: bool = false) -> void:
	r.streaming = false
	var rects: Array = []
	var kinds: Array = []
	var tops: Array = []
	var specs: Array = []
	for center: Vector2 in centers:
		rects.append(Rect2(center - Vector2(PILLAR, PILLAR), Vector2(PILLAR, PILLAR) * 2))
		kinds.append("pillar")
		tops.append(top)
		specs.append({})
	r.obstacles.assign(rects)
	r.kinds.assign(kinds)
	r.obstacle_heights.assign(tops)
	r.hazard_specs.assign(specs)
	r.obstacle_ids.clear()
	r.revision += 1
	r.retry()
	if start_y != 0.0:
		r.a.position.y = start_y
		r.b.position.y = start_y
		r.distance = start_y
		r.rope.reset(r.a.position, r.b.position)
	r.step(0)
	if not keep_audit: reset_audit()
	audit.sides = {}
	audit.last_length = r.rope.length
	audit.last_heights = r.heights.duplicate()

# 路径上某一段与柱体的独立几何判定：返回 [最近距离, 进入位置, 离开位置]（位置为沿该段的长度）。
func chord(p: Vector2, q: Vector2, center: Vector2, radius: float) -> Array:
	var d := q - p
	var span := d.length()
	if span < 0.000001: return [p.distance_to(center), 0.0, 0.0, 0.0]
	var along: float = (center - p).dot(d) / span
	var nearest := clampf(along, 0.0, span)
	var gap: float = center.distance_to(p + d / span * nearest)
	var half := sqrt(maxf(0.0, radius * radius - ((center - p).length_squared() - along * along)))
	return [gap, clampf(along - half, 0.0, span), clampf(along + half, 0.0, span), nearest]

# 每个固定步之后的独立审计：不依赖求解器自己报告的结论（不读取 lifted、接触列表里的高度或路径高度）。
func inspect(previous_a: Vector2, previous_b: Vector2, moved: bool = true) -> void:
	audit.ticks += 1
	var path: PackedVector2Array = r.rope.path
	var polyline := 0.0
	for n in range(1, path.size()): polyline += path[n - 1].distance_to(path[n])
	audit.max_length = maxf(audit.max_length, maxf(r.rope.length, polyline))
	audit.max_polyline_gap = maxf(audit.max_polyline_gap, absf(r.rope.length - polyline))
	if r.state == "running":
		audit.ends_ok = audit.ends_ok and path.size() >= 2 and path[0] == r.a.position and path[path.size() - 1] == r.b.position
	for index in range(r.obstacles.size()):
		if r.kinds[index] != "pillar": continue
		var center: Vector2 = r.obstacles[index].get_center()
		var radius: float = r.obstacles[index].size.x * 0.5
		# 真实路径加当前高度：绳索高度由角色当前跳跃高度和挂点高度直接算出，沿路径长度线性插值。
		# 某段进入物理柱体（半径不含间隙）时，只有它在柱体占地范围内的两端都不低于柱顶才算从上方越过，否则记为穿柱。
		var hang_a: float = Run.ROPE_HEIGHT + r.heights[0]
		var hang_b: float = Run.ROPE_HEIGHT + r.heights[1]
		var top: float = r.obstacle_heights[index]
		var travelled := 0.0
		for n in range(1, path.size()):
			var piece: float = path[n - 1].distance_to(path[n])
			var hit := chord(path[n - 1], path[n], center, radius)
			if hit[0] < radius - 0.01:
				var enter := lerpf(hang_a, hang_b, (travelled + hit[1]) / maxf(polyline, 0.000001))
				var leave := lerpf(hang_a, hang_b, (travelled + hit[2]) / maxf(polyline, 0.000001))
				if minf(enter, leave) < top:
					audit.penetrations += 1
					audit.worst_penetration = maxf(audit.worst_penetration, radius - hit[0])
			elif lerpf(hang_a, hang_b, (travelled + hit[3]) / maxf(polyline, 0.000001)) < top:
				audit.min_rope_clearance = minf(audit.min_rope_clearance, hit[0] - radius)
			travelled += piece
		if r.state == "running" and r.obstacle_heights[index] > Run.JUMP_APEX:
			audit.min_body_clearance = minf(audit.min_body_clearance, minf(center.distance_to(r.a.position), center.distance_to(r.b.position)) - radius - Run.Motion.RADIUS)
	var current := {}
	for contact in r.rope.contacts: current[contact.id] = contact.side
	for id in current:
		if audit.sides.has(id):
			if audit.sides[id] != current[id]: audit.side_flips += 1
		else:
			audit.attaches += 1
	for id in audit.sides:
		if not current.has(id): audit.detaches += 1
	audit.sides = current
	# 固定硬上限：任何固定步超出都计数，没有例外情形。
	if maxf(r.rope.length, polyline) > Run.LINK_LIMIT + Run.ROPE_LENGTH_TOLERANCE: audit.over_ticks += 1
	if moved:
		audit.max_move = maxf(audit.max_move, maxf(r.a.position.distance_to(previous_a), r.b.position.distance_to(previous_b)))

func tick(ia: Vector2 = Vector2.ZERO, ib: Vector2 = Vector2.ZERO, ja: bool = false, jb: bool = false) -> void:
	var previous_a: Vector2 = r.a.position
	var previous_b: Vector2 = r.b.position
	r.step(DT, ia, ib, ja, jb)
	inspect(previous_a, previous_b)

func audit_clean(name: String) -> void:
	# 数值容限：有效路径长度不超过绳长 + ROPE_LENGTH_TOLERANCE（0.01 单位 = 0.5 毫米）。
	check(name + "：每个固定步的有效路径长度都不超过固定上限（容限 0.5 毫米）", audit.max_length <= Run.LINK_LIMIT + Run.ROPE_LENGTH_TOLERANCE and audit.over_ticks == 0)
	check(name + "：绳段不穿柱（真实路径与当前高度独立判定）、绕行侧不翻转、端点与角色一致", audit.penetrations == 0 and audit.min_rope_clearance >= 0.5 and audit.side_flips == 0 and audit.ends_ok)
	# 上界 = 一个固定步的移动加推进，再加一个子步的推进量：贴着后边界时整步推进量在首个子步生效，
	# 离开后边界的那一步会多出不到一个子步的推进（约 0.33 单位，t01 既有行为，与绳索无关）。
	check(name + "：无瞬移（单步位移不超过移动加推进速度）", audit.max_move <= (Run.FORWARD + Run.LATERAL) * DT + Run.FORWARD * DT / 3.0 + 0.01)

func toward(position: Vector2, target: Vector2) -> Vector2:
	var offset := target - position
	return offset.normalized() if offset.length() > 1.0 else Vector2.ZERO

func verify_same_side() -> void:
	# 同侧通过：02 提前靠到 01 一侧（左侧），两人从柱子左边通过。
	fixture([Vector2(0, 400)])
	var contact := false
	var bound := false
	for n in range(600):
		tick(Vector2.ZERO, Vector2.LEFT if r.b.position.x > -30 else Vector2.ZERO)
		contact = contact or not r.rope.contacts.is_empty()
		bound = bound or r.rope_bound
	check("同侧通过：无接触、无受阻、继续前进", r.state == "running" and not contact and not bound and r.rope_block_substeps == 0 and r.a.position.y > 520 and r.b.position.x < -24)
	audit_clean("同侧通过")
	# 改走同侧：原本分侧，接近柱子前 01 才横穿到 02 一侧（右侧）。
	fixture([Vector2(0, 400)])
	contact = false
	for n in range(600):
		tick(Vector2.RIGHT if n > 150 and r.a.position.x < 34 else Vector2.ZERO)
		contact = contact or not r.rope.contacts.is_empty()
	check("改走同侧：接近前换边后无接触通过", r.state == "running" and not contact and r.rope_block_substeps == 0 and r.a.position.x > 24 and r.a.position.y > 520)
	audit_clean("改走同侧")

# 分侧过柱不做任何解围，返回关键时刻。
func split_run(inward_before_block: bool = false) -> Dictionary:
	fixture([Vector2(0, 400)])
	var result := {"contact": -1, "bound": -1, "fail": -1, "premature": false, "side": 0, "bound_distance": 0.0, "bound_a": Vector2.ZERO, "contact_tension": 0.0}
	for n in range(1, 1500):
		var ia := Vector2.ZERO
		var ib := Vector2.ZERO
		if inward_before_block and result.contact > 0:
			ia = Vector2.RIGHT if r.a.position.x < -28 else Vector2.ZERO
			ib = Vector2.LEFT if r.b.position.x > 28 else Vector2.ZERO
		tick(ia, ib)
		if result.contact < 0 and not r.rope.contacts.is_empty():
			result.contact = n
			result.side = r.rope.contacts[0].side
			result.contact_tension = r.rope_tension()
		if result.bound < 0:
			if r.rope_block_substeps > 0 and not r.rope_bound: result.premature = true
			if r.rope_bound:
				result.bound = n
				result.bound_distance = r.distance
				result.bound_a = r.a.position
		if r.state == "failed":
			result.fail = n
			break
	return result

func verify_split() -> void:
	var plain := split_run()
	var stalled: float = absf(r.distance - plain.bound_distance)
	metrics["split"] = {"contact_tick": plain.contact, "bound_tick": plain.bound, "fail_tick": plain.fail, "block_s": (plain.fail - plain.bound + 1) * DT,
		"contact_to_bound_s": (plain.bound - plain.contact) * DT, "stall_drift_units": stalled, "bound_ahead_of_pillar_m": (plain.bound_a.y - 400) / SCALE, "wrap_rad": r.rope.total_wrap}
	check("分侧绕柱：绳索挂上柱子并保持同一绕行侧", plain.contact > 0 and plain.side == 1 and audit.attaches == 1 and audit.detaches == 0)
	check("分侧绕柱：仅接触未耗尽时不计时", not plain.premature and plain.bound > plain.contact + 30 and plain.contact_tension < 0.75)
	check("分侧绕柱：受阻约 0.8 秒共同失败", plain.fail > 0 and absi(plain.fail - plain.bound + 1 - BLOCK_TICKS) <= 1 and r.rope_failed and "绳索" in r.reason and r.actions == ["Hit", "Hit"])
	check("分侧绕柱：受阻期间自动推进与前后边界停住，角色不被推过柱子", stalled < 0.5 and r.a.position.distance_to(plain.bound_a) < 0.5 and r.a.position.x < -24 and r.b.position.x > 24)
	check("分侧绕柱：失败状态反馈", r.rope_status() == "failed" and r.rope_tension() > 0.99)
	audit_clean("分侧绕柱")
	# 靠拢：挂柱后两人向柱子收拢，路径变短，受阻推迟且位置更靠前；仍在两侧，最终同样失败。
	var inward := split_run(true)
	metrics["converge_before_block"] = {"bound_tick": inward.bound, "fail_tick": inward.fail, "bound_delay_s": (inward.bound - plain.bound) * DT, "extra_advance_m": (inward.bound_distance - plain.bound_distance) / SCALE}
	check("靠拢：挂柱后收拢推迟受阻并多前进一段，不误判失败", inward.bound >= plain.bound + 4 and inward.bound_distance > plain.bound_distance + 5 and not inward.premature)
	check("靠拢：仍在两侧时最终受阻失败", inward.fail > 0 and r.rope_failed and absi(inward.fail - inward.bound + 1 - BLOCK_TICKS) <= 1)
	audit_clean("靠拢（受阻前）")
	# 受阻后再靠拢：产生余量期间不累计，停止后继续累计，计时不清零。
	fixture([Vector2(0, 400)])
	var bound_tick := -1
	var fail_tick := -1
	var before := 0
	var after := 0
	var inward_ticks := 0
	var distance_before := 0.0
	var distance_after := 0.0
	for n in range(1, 1500):
		var moving: bool = bound_tick > 0 and n > bound_tick + 30 and (r.a.position.x < -28 or r.b.position.x > 28)
		if moving and inward_ticks == 0:
			before = r.rope_block_substeps
			distance_before = r.distance
		tick(Vector2.RIGHT if moving and r.a.position.x < -28 else Vector2.ZERO, Vector2.LEFT if moving and r.b.position.x > 28 else Vector2.ZERO)
		if moving:
			inward_ticks += 1
			after = r.rope_block_substeps
			distance_after = r.distance
		if bound_tick < 0 and r.rope_bound: bound_tick = n
		if r.state == "failed":
			fail_tick = n
			break
	metrics["converge_after_block"] = {"inward_ticks": inward_ticks, "timer_substeps_during_inward": after - before, "total_block_window_s": (fail_tick - bound_tick + 1) * DT, "advance_during_inward_units": distance_after - distance_before}
	check("靠拢（受阻后）：收拢期间计时基本不累计且不清零", inward_ticks >= 8 and after - before <= 6 and before >= 80 and after >= before)
	check("靠拢（受阻后）：停止收拢后继续累计至失败", fail_tick > bound_tick + BLOCK_TICKS + inward_ticks - 4 and r.rope_failed)
	audit_clean("靠拢（受阻后）")

func verify_retreat() -> void:
	# 回撤解围：受阻 0.3 秒后，01 向后退并从柱子后方绕到 02 一侧。
	fixture([Vector2(0, 400)])
	var bound_tick := -1
	var clear_tick := -1
	var peak := 0
	var phase := 0
	var hold_ticks := 0
	var stalled_distance := 0.0
	var cleared_ok := false
	var resumed_slow := false
	for n in range(1, 1500):
		var ia := Vector2.ZERO
		if bound_tick > 0 and n > bound_tick + 36 and clear_tick < 0 or phase == 2:
			if phase == 0: phase = 1
			if phase == 1:
				ia = toward(r.a.position, Vector2(-34, 362))
				if ia == Vector2.ZERO: phase = 2
			if phase == 2:
				ia = Vector2.RIGHT if r.a.position.x < 40 else Vector2.ZERO
		tick(ia)
		if bound_tick < 0 and r.rope_bound:
			bound_tick = n
			stalled_distance = r.distance
		if bound_tick > 0 and clear_tick < 0:
			peak = maxi(peak, r.rope_block_substeps)
			if r.rope_status() == "unwinding": hold_ticks += 1
			if r.rope.contacts.is_empty():
				clear_tick = n
				cleared_ok = r.rope_block_substeps == 0 and not r.rope_bound
				resumed_slow = r.distance - stalled_distance < 1.0
		if r.state != "running": break
	metrics["retreat"] = {"bound_tick": bound_tick, "clear_tick": clear_tick, "peak_timer_s": peak / 360.0, "unwinding_ticks": hold_ticks, "stall_to_clear_s": (clear_tick - bound_tick) * DT,
		"final_state": r.state, "final_a_m": [r.a.position.x / SCALE, r.a.position.y / SCALE], "resume_scale": r.rope_resume}
	check("回撤解围：解绕期间计时暂停，接触解除后清零", bound_tick > 0 and clear_tick > bound_tick and cleared_ok and peak < Run.ROPE_BLOCK_SUBSTEPS and peak >= 100 and hold_ticks > 40)
	check("回撤解围：解围前道路保持停滞", resumed_slow)
	check("回撤解围：两人改走同侧后继续前进，无陈旧接触", r.state == "running" and r.rope.contacts.is_empty() and r.rope_block_substeps == 0 and not r.rope_bound and r.a.position.x > 24 and r.b.position.x > 24 and r.a.position.y > 520 and r.rope_resume == 1.0)
	check("回撤解围：全程未触碰柱子", audit.min_body_clearance > 0.0)
	audit_clean("回撤解围")

func verify_taut() -> void:
	# 普通拉紧：附近没有柱子，两人向两侧拉到绳长上限。
	fixture([Vector2(0, 3000)])
	var bound := false
	var timer := 0
	for n in range(300):
		tick(Vector2.LEFT, Vector2.RIGHT)
		bound = bound or r.rope_bound
		timer = maxi(timer, r.rope_block_substeps)
	metrics["taut_far_link_m"] = r.rope.length / SCALE
	check("普通拉紧（无柱）：到达绳长上限但不受阻、不计时", r.state == "running" and not bound and timer == 0 and r.rope.length > Run.LINK_LIMIT - 0.01 and r.rope_status() == "taut")
	audit_clean("普通拉紧（无柱）")
	# 柱子在绳长可及范围内但未接触：同样只是拉紧。
	fixture([Vector2(0, 330)])
	bound = false
	timer = 0
	var contact := false
	for n in range(180):
		tick(Vector2.LEFT, Vector2.RIGHT)
		bound = bound or r.rope_bound
		timer = maxi(timer, r.rope_block_substeps)
		contact = contact or not r.rope.contacts.is_empty()
	check("普通拉紧（柱子在附近未接触）：不受阻、不计时", r.state == "running" and not bound and timer == 0 and not contact and not r.rope_circles().is_empty() and r.rope.length > Run.LINK_LIMIT - 0.01)
	# 一人腾空时仍按地面距离约束。
	fixture([Vector2(0, 3000)])
	var peak_height := 0.0
	for n in range(200):
		tick(Vector2.LEFT, Vector2.RIGHT, n == 100, false)
		peak_height = maxf(peak_height, r.heights[0])
	check("独立跳跃保留地面连接约束", peak_height > 35.0 and r.state == "running" and audit.max_length <= Run.LINK_LIMIT + Run.ROPE_LENGTH_TOLERANCE)

func verify_speed() -> void:
	# 大步长调用（每次 0.25 秒，内部仍按固定子步推进）加满速横向输入。
	fixture([Vector2(0, 400)])
	var directions := [Vector2.LEFT, Vector2.RIGHT, Vector2(-1, 1), Vector2(1, -1), Vector2.UP, Vector2.DOWN]
	for n in range(40):
		var previous_a: Vector2 = r.a.position
		var previous_b: Vector2 = r.b.position
		r.step(0.25, directions[n % 6], directions[(n + 3) % 6])
		inspect(previous_a, previous_b, false)
		if r.state != "running": fixture([Vector2(0, 400)], 100.0, 0.0, true)
	check("大步长调用：长度上限、不穿柱、绕行侧不翻转", audit.max_length <= Run.LINK_LIMIT + Run.ROPE_LENGTH_TOLERANCE and audit.penetrations == 0 and audit.min_rope_clearance >= 0.5 and audit.side_flips == 0)
	# 求解模块直接以 5 倍生产子步位移（约 36 米/秒）扫过并缠绕柱子。
	var rope = Rope.new()
	var circles := [{"id": 7, "center": Vector2.ZERO, "radius": PILLAR + Run.ROPE_CLEARANCE, "top": 100.0, "bottom": 0.0}]
	var a := Vector2(-42, -100)
	var b := Vector2(42, -100)
	rope.reset(a, b)
	var clearance := INF
	var flips := 0
	var side := 0
	var jump := 0.0
	var last: float = rope.length
	var peak_wrap := 0.0
	var attaches := 0
	var motions: Array = []
	for n in range(80): motions.append([Vector2(0, 2), Vector2(0, 2)])
	# 01 顺着缠绕方向绕柱近两圈再原路退回：最短路径早已在另一侧，绕行侧必须保持。
	for n in range(400): motions.append([Vector2.ZERO, Vector2.ZERO, -0.03])
	for n in range(400): motions.append([Vector2.ZERO, Vector2.ZERO, 0.03])
	for n in range(80): motions.append([Vector2(0, -2), Vector2(0, -2)])
	for motion in motions:
		if motion.size() == 3:
			a = a.rotated(motion[2])
		else:
			a += motion[0]
			b += motion[1]
		var had: bool = not rope.contacts.is_empty()
		rope.solve(a, b, 28.0, 28.0, circles, true)
		if not rope.contacts.is_empty():
			if not had: attaches += 1
			if side != 0 and had and rope.contacts[0].side != side: flips += 1
			side = rope.contacts[0].side
			peak_wrap = maxf(peak_wrap, rope.contacts[0].wrap)
		for i in range(1, rope.path.size()):
			clearance = minf(clearance, Rope.segment_distance(rope.path[i - 1], rope.path[i], Vector2.ZERO) - PILLAR)
		jump = maxf(jump, absf(rope.length - last))
		last = rope.length
	metrics["solver_fast"] = {"min_clearance_units": clearance, "peak_wrap_rad": peak_wrap, "max_length_jump_units": jump, "attaches": attaches}
	check("求解模块高速扫掠：不穿柱、长度连续", clearance >= 0.5 and jump <= 4.5)
	check("求解模块：缠绕超过一圈仍保持绕行侧，原路退回后只解除一次", flips == 0 and peak_wrap > TAU and attaches == 1 and rope.contacts.is_empty() and is_equal_approx(rope.length, a.distance_to(b)))

func verify_fuzz() -> void:
	# 多种子随机双人输入穿过一串柱子：失败后重试继续，累计审计。
	reset_audit()
	var centers := [Vector2(0, 300), Vector2(-50, 620), Vector2(60, 940), Vector2(0, 1260)]
	var directions := [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]
	var outcomes := {"rope": 0, "hit": 0, "passed": 0}
	var contact_ticks := 0
	var bound_ticks := 0
	for seed_value in range(1, 13):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		fixture(centers, 100.0, 0.0, true)
		var ia := Vector2.ZERO
		var ib := Vector2.ZERO
		for n in range(1500):
			if n % 18 == 0:
				ia = directions[rng.randi_range(0, 8)]
				ib = directions[rng.randi_range(0, 8)]
			tick(ia, ib, rng.randf() < 0.02, rng.randf() < 0.02)
			if not r.rope.contacts.is_empty(): contact_ticks += 1
			if r.rope_bound: bound_ticks += 1
			if r.state == "failed":
				outcomes["rope" if r.rope_failed else "hit"] += 1
				break
		if r.state == "running": outcomes.passed += 1
	metrics["fuzz"] = {"seeds": 12, "ticks": audit.ticks, "contact_ticks": contact_ticks, "bound_ticks": bound_ticks, "outcomes": outcomes, "max_length_units": audit.max_length,
		"min_rope_clearance_units": audit.min_rope_clearance, "max_move_units": audit.max_move, "attaches": audit.attaches, "detaches": audit.detaches, "max_polyline_gap_units": audit.max_polyline_gap}
	check("随机输入：覆盖到接触与受阻状态", contact_ticks > 200 and bound_ticks > 50)
	audit_clean("随机输入 12 种子")
	check("随机输入：运行中角色不进入柱体", audit.min_body_clearance > -0.001)

func verify_height() -> void:
	# 矮桩（2 米）夹具：站立时绳索挂点 1.4 米会被挂住，绳段抬过桩顶则越过。
	fixture([Vector2(0, 300)], 40.0)
	var contact := false
	for n in range(330):
		tick()
		contact = contact or not r.rope.contacts.is_empty()
	check("绳段高度：站立分侧通过矮桩会挂住", contact)
	fixture([Vector2(0, 300)], 40.0)
	contact = false
	var lifted := false
	for n in range(1, 420):
		tick(Vector2.ZERO, Vector2.ZERO, n == 264, n == 264)
		contact = contact or not r.rope.contacts.is_empty()
		lifted = lifted or not r.rope.lifted.is_empty()
	check("绳段高度：两人同时起跳把绳索抬过矮桩，不产生接触", not contact and lifted and r.rope.lifted.is_empty() and r.state == "running" and r.a.position.y > 380)
	# 单人起跳：另一端挂点仍在 1.4 米，靠近未起跳一侧的绳段最低。只有最高点恰好落在过桩中段时
	# 低端一侧才略高于桩顶（余量约 0.4 单位）；时机偏早或偏晚都会被挂住。
	fixture([Vector2(0, 300)], 40.0, 0.0, true)
	contact = false
	for n in range(1, 420):
		tick(Vector2.ZERO, Vector2.ZERO, n == 264, false)
		contact = contact or r.rope.touching() > 0
	check("绳段高度：单人起跳时机恰好时整段高过桩顶，可以越过", not contact and r.state == "running")
	var single_hooked := 0
	var single_cases := 0
	for jump_tick in [228, 246, 252, 276, 282]:
		fixture([Vector2(0, 300)], 40.0, 0.0, true)
		contact = false
		for n in range(1, 330):
			tick(Vector2.ZERO, Vector2.ZERO, n == jump_tick, false)
			contact = contact or r.rope.touching() > 0
		single_cases += 1
		if contact: single_hooked += 1
	check("绳段高度：单人起跳时机偏早或偏晚，斜绳低端一侧低于桩顶，被挂住", single_hooked == single_cases)
	# 被矮桩挂住并受阻后，两人起跳把绳索甩过桩顶即解除。
	fixture([Vector2(0, 300)], 40.0)
	var bound_tick := -1
	var released := false
	for n in range(1, 900):
		var jump: bool = bound_tick > 0 and n == bound_tick + 24
		tick(Vector2.ZERO, Vector2.ZERO, jump, jump)
		if bound_tick < 0 and r.rope_bound: bound_tick = n
		if bound_tick > 0 and r.rope.contacts.is_empty(): released = true
	check("绳段高度：受阻后起跳抬过矮桩解除接触并清除计时", bound_tick > 0 and released and r.state == "running" and r.rope_block_substeps == 0 and r.rope.contacts.is_empty() and r.rope.lifted.is_empty())
	audit_clean("矮桩高度")
	# 5 米高柱：起跳后绳索最高约 3.2 米，仍被挂住。
	fixture([Vector2(0, 300)])
	contact = false
	for n in range(1, 330):
		tick(Vector2.ZERO, Vector2.ZERO, n == 264, n == 264)
		contact = contact or not r.rope.contacts.is_empty()
	check("绳段高度：5 米高柱不能靠起跳越过", contact and Run.HAZARD_TOPS.pillar == 100.0 and not Run.jump_clearable("pillar"))

# 决策者首轮审查指出的三处边界，加上落到矮桩时的长度处理。求解模块部分直接驱动模块，
# 判定只用路径坐标和给定高度。
func path_min_gap(rope, center: Vector2) -> float:
	var gap := INF
	for i in range(1, rope.path.size()): gap = minf(gap, chord(rope.path[i - 1], rope.path[i], center, PILLAR)[0])
	return gap

func verify_edges() -> void:
	var circles := [{"id": 1, "center": Vector2.ZERO, "radius": PILLAR + Run.ROPE_CLEARANCE, "top": 100.0, "bottom": 0.0}]
	# 一、端点重合：零长度直绳有效。
	var rope = Rope.new()
	var same := Vector2(-42, -100)
	rope.reset(same, same)
	var length: float = rope.solve(same, same, 28.0, 28.0, circles, true)
	check("端点重合：零长度直绳有效", rope.solved_valid and length == 0.0 and rope.contacts.is_empty() and rope.path.size() == 2)
	# 已绕柱时两端点走到同一位置：接触、绕行侧保留，长度为绕柱一圈的真实路径。
	rope = Rope.new()
	var a := Vector2(-30, -40)
	var b := Vector2(30, -40)
	rope.reset(a, b)
	for n in range(100):
		a.y += 1.0
		b.y += 1.0
		rope.solve(a, b, 28.0, 28.0, circles, true)
	var side: int = rope.contacts[0].side
	var meet := Vector2(0, 60)
	var kept := true
	var worst := INF
	for n in range(60):
		a = a.move_toward(meet, 0.5)
		b = b.move_toward(meet, 0.5)
		rope.solve(a, b, 28.0, 28.0, circles, true)
		kept = kept and rope.solved_valid and rope.touching() == 1 and rope.contacts[0].side == side
		worst = minf(worst, path_min_gap(rope, Vector2.ZERO))
	var loop_length: float = 2.0 * sqrt(60.0 * 60.0 - 13.0 * 13.0) + 13.0 * (TAU - 2.0 * acos(13.0 / 60.0))
	metrics["coincident_wrapped"] = {"length_units": rope.length, "expected_units": loop_length, "wrap_rad": rope.total_wrap}
	check("端点重合（已绕柱）：保留接触与绕行侧，长度为绕柱闭环", a == b and kept and absf(rope.length - loop_length) < 0.01 and worst >= PILLAR + 0.5)
	# 生产固定步：两人重合在柱子附近时照常随道路推进。
	fixture([Vector2(0, 400)])
	r.a.position = Vector2(-42, 300)
	r.b.position = Vector2(-42, 300)
	r.distance = 300.0
	r.rope.reset(r.a.position, r.b.position)
	for n in range(120): tick()
	check("端点重合（生产）：角色随道路推进 120 单位", r.state == "running" and absf(r.a.position.y - 420.0) < 0.01 and absf(r.distance - 420.0) < 0.01 and r.rope.solved_valid and r.rope.length == 0.0)
	# 二、真实高度：斜绳中点高过矮桩，但低端一侧在柱面处低于桩顶，必须挂住。
	circles[0].top = 40.0
	rope = Rope.new()
	var p := Vector2(-30, 0)
	var q := Vector2(30, 0)
	rope.reset(p, q)
	rope.solve(p, q, 28.0, 64.0, circles, true)
	check("真实高度：斜绳低端一侧低于桩顶时挂住，路径不穿柱", rope.touching() == 1 and not rope.lifted.has(1) and path_min_gap(rope, Vector2.ZERO) >= PILLAR + 0.5)
	rope = Rope.new()
	rope.reset(p, q)
	rope.solve(p, q, 52.0, 64.0, circles, true)
	check("真实高度：占地范围内整段高过桩顶时越过", rope.contacts.is_empty() and rope.lifted.has(1))
	# 原地下降：高度降到桩顶以下的那一次求解就必须挂住，历史越过状态不豁免；再升高则抬离。
	rope = Rope.new()
	p = Vector2(-30, 3)
	q = Vector2(30, 3)
	rope.reset(p, q)
	var hooked_at := -1.0
	var early := false
	var crossing_low := false
	for step in range(23):
		var height := 50.0 - step
		rope.solve(p, q, height, height, circles, true)
		if rope.touching() > 0 and hooked_at < 0.0: hooked_at = height
		if height >= 40.0 and rope.touching() > 0: early = true
		if height < 40.0 and path_min_gap(rope, Vector2.ZERO) < PILLAR: crossing_low = true
	var landed_side: int = rope.contacts[0].side if not rope.contacts.is_empty() else 0
	var far_side := -INF
	for point in rope.path: far_side = maxf(far_side, point.y)
	rope.solve(p, q, 45.0, 45.0, circles, true)
	metrics["descent"] = {"hooked_at_height": hooked_at, "side": landed_side, "length_after_landing": rope.length}
	check("真实高度：下降到桩顶以下立即挂住，不留穿柱直绳", hooked_at == 39.0 and not early and not crossing_low)
	check("真实高度：落下时取圆心所在一侧（较短一侧）并可重新抬离", landed_side == -1 and far_side > 12.0 and rope.contacts.is_empty() and rope.lifted.has(1))
	# 三、持续脱离：相切附近 0.002 单位抖动不反复建立/解除接触。
	circles[0].top = 100.0
	rope = Rope.new()
	rope.reset(Vector2(-42, 13.001), Vector2(42, 13.001))
	var attaches := 0
	var detaches := 0
	var flips := 0
	var jump := 0.0
	var last: float = rope.length
	side = 0
	for n in range(40):
		var had: bool = not rope.contacts.is_empty()
		var y := 12.999 if n % 2 == 0 else 13.001
		rope.solve(Vector2(-42, y), Vector2(42, y), 28.0, 28.0, circles, true)
		var has: bool = not rope.contacts.is_empty()
		if has and not had: attaches += 1
		if had and not has: detaches += 1
		if has:
			if side != 0 and rope.contacts[0].side != side: flips += 1
			side = rope.contacts[0].side
		jump = maxf(jump, absf(rope.length - last))
		last = rope.length
	metrics["tangent_jitter"] = {"samples": 40, "attaches": attaches, "detaches": detaches, "max_length_jump_units": jump}
	check("持续脱离：相切抖动 40 次只建立一次接触、不解除，绕行侧与长度连续", attaches == 1 and detaches == 0 and flips == 0 and jump < 0.001)
	# 短暂离开（间隙 0.3 单位）后返回：仍是原接触；离开期间不计长度。
	var loose_ok := true
	for n in range(10):
		rope.solve(Vector2(-42, 13.3), Vector2(42, 13.3), 28.0, 28.0, circles, true)
		loose_ok = loose_ok and rope.contacts.size() == 1 and rope.touching() == 0 and rope.contacts[0].side == side and is_equal_approx(rope.length, 84.0) and rope.path.size() == 2
	rope.solve(Vector2(-42, 12.9), Vector2(42, 12.9), 28.0, 28.0, circles, true)
	check("持续脱离：短暂离开后返回恢复原接触与绕行侧", loose_ok and rope.touching() == 1 and rope.contacts[0].side == side and rope.total_wrap > 0.0)
	# 离开但一直停在间隙内：连续 36 次求解没有压回后解除。
	var released_after := -1
	for n in range(1, 60):
		rope.solve(Vector2(-42, 13.3), Vector2(42, 13.3), 28.0, 28.0, circles, true)
		if rope.contacts.is_empty():
			released_after = n
			break
	check("持续脱离：停在间隙内连续 36 次求解未压回后解除", released_after == Rope.RELEASE_SOLVES + 1)
	# 真正退回：离开表面超过 0.5 单位即解除；再压回是新的接触。
	rope.solve(Vector2(-42, 12.9), Vector2(42, 12.9), 28.0, 28.0, circles, true)
	rope.solve(Vector2(-42, 13.2), Vector2(42, 13.2), 28.0, 28.0, circles, true)
	var pending: bool = rope.contacts.size() == 1 and rope.touching() == 0
	rope.solve(Vector2(-42, 13.6), Vector2(42, 13.6), 28.0, 28.0, circles, true)
	check("持续脱离：真正退回同侧（间隙超过 0.5 单位）后解除", pending and rope.contacts.is_empty() and rope.length == 84.0)
	metrics["release"] = {"distance_units": Rope.RELEASE_DISTANCE, "solves": Rope.RELEASE_SOLVES, "released_after_solves": released_after}
	verify_landing()

# 一次落到矮桩的生产运行：两人先向两侧拉开到 spread 个固定步，再按给定时机起跳。
# 返回是否被挂住、腾空期间道路是否被落点约束停住、腾空停住期间是否误计时、结束状态。
func landing_run(spread_ticks: int, jump_tick: int, both: bool, inward_after_jump: bool, partner_delay: int = 0) -> Dictionary:
	fixture([Vector2(0, 300)], 40.0, 0.0, true)
	var result := {"hooked": false, "air_stall": 0, "air_timer": 0, "landed_in_footprint": false, "state": "", "rope_failed": false, "max_length": 0.0, "over_ticks": 0, "partner_peak": 0.0}
	for n in range(1, 620):
		var spreading: bool = n < spread_ticks
		var inward: bool = inward_after_jump and n >= jump_tick and r.a.position.x < -40.0
		var airborne: bool = r.heights[0] > 0.0 or r.heights[1] > 0.0
		tick(Vector2.LEFT if spreading else (Vector2.RIGHT if inward else Vector2.ZERO), Vector2.RIGHT if spreading else (Vector2.LEFT if inward else Vector2.ZERO), n == jump_tick, both and n == jump_tick + partner_delay)
		result.max_length = maxf(result.max_length, r.rope.length)
		if r.rope.length > Run.LINK_LIMIT + Run.ROPE_LENGTH_TOLERANCE: result.over_ticks += 1
		result.partner_peak = maxf(result.partner_peak, r.heights[1])
		if r.rope.touching() > 0:
			# 首次挂住时绳段两端连线是否已在桩的占地范围内（即从上方落到桩上）。
			if not result.hooked and airborne and chord(r.a.position, r.b.position, Vector2(0, 300), PILLAR)[0] < PILLAR - 1.0: result.landed_in_footprint = true
			result.hooked = true
		elif r.rope_bound and airborne:
			result.air_stall += 1
			result.air_timer = maxi(result.air_timer, r.rope_block_substeps)
		if r.state != "running": break
	result.state = r.state
	result.rope_failed = r.rope_failed
	return result

# 落到矮桩：有效长度在每个固定步都必须满足固定上限，不存在“超长后再收回”。
func verify_landing() -> void:
	var timings := [226, 230, 234, 238, 242, 246]
	# 拉满绳长、之后不做任何操作：腾空时道路在桩前停住，落下后受阻约 0.8 秒共同失败。
	reset_audit()
	var stalled := 0
	var failed := 0
	var air_timer := 0
	for jump_tick in timings:
		var outcome := landing_run(150, jump_tick, true, false)
		if outcome.air_stall > 0: stalled += 1
		if outcome.rope_failed: failed += 1
		air_timer = maxi(air_timer, outcome.air_timer)
	metrics["landing_taut_idle"] = {"cases": 6, "air_stalled_cases": stalled, "rope_failed_cases": failed, "max_length_units": audit.max_length, "penetrations": audit.penetrations, "timer_substeps_while_airborne": air_timer}
	check("落到矮桩（拉满、无收拢）：腾空期间被落点约束停住且不计时，落下后受阻共同失败", stalled == 6 and failed == 6 and air_timer == 0)
	audit_clean("落到矮桩（拉满、无收拢）")
	# 拉满绳长、起跳后立即收拢：有了余量才允许越到桩的上方。
	reset_audit()
	var hooked := 0
	var running := 0
	for jump_tick in timings:
		var outcome := landing_run(150, jump_tick, true, true)
		if outcome.hooked: hooked += 1
		if outcome.state == "running": running += 1
	metrics["landing_taut_inward"] = {"cases": 6, "hooked_cases": hooked, "running_cases": running, "max_length_units": audit.max_length, "penetrations": audit.penetrations}
	audit_clean("落到矮桩（拉满、立即收拢）")
	# 留有余量（初始 4.2 米，加 14 步分离后约 5.72 米）：不同时机起跳，绳段从上方落到桩上被挂住。
	reset_audit()
	var landed := 0
	hooked = 0
	for jump_tick in timings:
		var outcome := landing_run(15, jump_tick, true, false)
		if outcome.hooked: hooked += 1
		if outcome.landed_in_footprint: landed += 1
	metrics["landing_slack"] = {"cases": 6, "hooked_cases": hooked, "landed_on_post_cases": landed, "max_length_units": audit.max_length, "penetrations": audit.penetrations}
	check("落到矮桩（有余量）：绳段从桩的上方落下时当即挂住", landed >= 3 and hooked >= landed)
	audit_clean("落到矮桩（有余量）")
	# 单人起跳（队友不跳）：拉满与有余量两种间距、各个时机。
	reset_audit()
	var single_hooked := 0
	var partner_grounded := true
	for spread in [150, 15]:
		for jump_tick in timings:
			var outcome := landing_run(spread, jump_tick, false, false)
			if outcome.hooked: single_hooked += 1
			partner_grounded = partner_grounded and outcome.partner_peak == 0.0
	metrics["landing_single"] = {"cases": 12, "hooked_cases": single_hooked, "max_length_units": audit.max_length, "penetrations": audit.penetrations}
	check("落到矮桩（单人起跳）：不强制队友起跳，绳索按真实高度被挂住", single_hooked >= 6 and partner_grounded)
	audit_clean("落到矮桩（单人起跳）")
	# 双方错时起跳：高度转接不依赖同跳，正负错时都审计完整生产运行。
	reset_audit()
	var staggered_cases := []
	for spread in [150, 15]:
		for delay in [-12, 12, 24]:
			for jump_tick in timings:
				var outcome := landing_run(spread, jump_tick, true, false, delay)
				staggered_cases.append({"spread_ticks": spread, "jump_tick": jump_tick, "partner_delay_ticks": delay, "max_length_units": outcome.max_length, "over_ticks": outcome.over_ticks, "state": outcome.state})
	metrics["landing_staggered"] = {"cases": staggered_cases, "max_length_units": audit.max_length, "penetrations": audit.penetrations}
	audit_clean("落到矮桩（双方错时起跳 36 例）")
	# 拉满绳长后分侧遇到 5 米高柱：绳索再前进就压上柱子，同样按前向受阻计时并失败，不会无限停住。
	fixture([Vector2(0, 400)])
	var bound_tick := -1
	var fail_tick := -1
	for n in range(1, 900):
		tick(Vector2.LEFT if n < 150 else Vector2.ZERO, Vector2.RIGHT if n < 150 else Vector2.ZERO)
		if bound_tick < 0 and r.rope_bound: bound_tick = n
		if r.state == "failed":
			fail_tick = n
			break
	metrics["taut_into_pillar"] = {"bound_tick": bound_tick, "fail_tick": fail_tick, "block_s": (fail_tick - bound_tick + 1) * DT, "wrap_rad": r.rope.total_wrap}
	check("拉满绳长分侧遇柱：约 0.8 秒受阻失败，不无限停住", bound_tick > 0 and r.rope_failed and absi(fail_tick - bound_tick + 1 - BLOCK_TICKS) <= 1)
	audit_clean("拉满绳长分侧遇柱")

func run_to_contact(extra: int) -> void:
	fixture([Vector2(0, 400)])
	for n in range(1500):
		tick()
		if not r.rope.contacts.is_empty(): break
	for n in range(extra): tick()

func verify_state() -> void:
	# 暂停：接触、路径、计时全部冻结；恢复后从原值继续。
	fixture([Vector2(0, 400)])
	var bound_tick := -1
	for n in range(1, 1500):
		tick()
		if r.rope_bound:
			bound_tick = n
			break
	for n in range(30): tick()
	var snapshot := [r.rope.contacts.duplicate(true), r.rope.path, r.rope.length, r.rope_block_substeps, r.rope_bound, r.distance, r.a.position, r.b.position]
	r.pause()
	for n in range(240): r.step(DT, Vector2.LEFT, Vector2.RIGHT, true, true)
	var frozen: bool = r.state == "paused" and snapshot == [r.rope.contacts.duplicate(true), r.rope.path, r.rope.length, r.rope_block_substeps, r.rope_bound, r.distance, r.a.position, r.b.position]
	r.pause()
	var resumed := 0
	for n in range(1, 300):
		tick()
		resumed = n
		if r.state == "failed": break
	metrics["pause"] = {"block_ticks_before_pause": 31, "ticks_after_resume_to_fail": resumed}
	check("暂停：接触、路径与受阻计时冻结", frozen)
	check("暂停：恢复后计时接续，合计仍约 0.8 秒失败", r.rope_failed and absi(31 + resumed - BLOCK_TICKS) <= 1)
	# 重试：失败后与接触中途两种情况都不留陈旧接触。
	r.retry(true)
	var clean_after_fail: bool = r.rope.contacts.is_empty() and not r.rope_bound and not r.rope_failed and r.rope_block_substeps == 0 and r.rope_resume == 1.0 and r.rope.path == PackedVector2Array([r.a.position, r.b.position]) and r.rope_status() == "free"
	run_to_contact(40)
	var had_contact: bool = not r.rope.contacts.is_empty()
	r.retry()
	check("重试：清除接触、受阻状态、计时和路径", clean_after_fail and had_contact and r.rope.contacts.is_empty() and r.rope.lifted.is_empty() and not r.rope_bound and r.rope_block_substeps == 0 and r.rope.length == r.a.position.distance_to(r.b.position))
	for n in range(120): tick()
	check("重试后重新开始：无残留接触影响", r.state == "running" and r.rope.contacts.is_empty() and r.rope_block_substeps == 0)
	# 坐标重定位：接触期间整体平移 4800 单位，接触关系与后续时序不变。
	var reference := split_run()
	fixture([Vector2(0, 5960)], 100.0, 5560.0)
	r.next_segment = 100000
	var rebased := false
	var consistent := false
	var fail_tick := -1
	var bound_at := -1
	for n in range(1, 1500):
		tick()
		if bound_at < 0 and r.rope_bound: bound_at = n
		if r.state == "failed":
			fail_tick = n
			break
		if not rebased and r.distance >= 6000 and not r.rope.contacts.is_empty():
			var length_before: float = r.rope.length
			var side_before: int = r.rope.contacts[0].side
			var wrap_before: float = r.rope.contacts[0].wrap
			r.update_stream()
			rebased = r.rebases == 1 and r.distance < 6000
			consistent = r.rope.contacts.size() == 1 and r.rope.contacts[0].center == r.obstacles[0].get_center() and r.rope.contacts[0].side == side_before and r.rope.contacts[0].wrap == wrap_before \
				and r.rope.a == r.a.position and r.rope.b == r.b.position and r.rope.path[0] == r.a.position and absf(r.rope.length - length_before) < 0.001 and r.rope.has_contact(r.obstacle_ids[0])
	metrics["rebase"] = {"reference_contact_to_fail_ticks": reference.fail - reference.contact, "rebased_bound_tick": bound_at, "rebased_fail_tick": fail_tick, "world_origin": r.world_origin}
	check("重定位：接触随坐标平移，绕行侧、缠绕角与长度不变", rebased and consistent)
	check("重定位：之后仍按同一时序受阻失败，无陈旧接触", fail_tick > 0 and r.rope_failed and absi((fail_tick - bound_at) - (reference.fail - reference.bound)) <= 1)
	audit_clean("重定位")
	# 回收：同侧通过后柱子落到身后被回收；接触中的柱子不回收；障碍消失时接触随之失效。
	fixture([Vector2(0, 400)])
	r.next_segment = 100000
	for n in range(900):
		tick(Vector2.ZERO, Vector2.LEFT if r.b.position.x > -30 else Vector2.ZERO)
		r.update_stream()
	check("回收：通过后的柱子被回收，标识表同步，无接触残留", r.obstacles.is_empty() and r.obstacle_ids.is_empty() and r.recycled == 1 and r.rope.contacts.is_empty() and r.state == "running")
	run_to_contact(20)
	r.next_segment = 100000
	var saved_distance: float = r.distance
	r.distance = saved_distance + 2000.0
	r.update_stream()
	var kept: bool = r.obstacles.size() == 1 and r.rope.has_contact(r.obstacle_ids[0])
	r.distance = saved_distance
	check("回收：仍被绳索挂住的柱子不会被回收", kept)
	r.obstacles.clear()
	r.kinds.clear()
	r.obstacle_heights.clear()
	r.hazard_specs.clear()
	r.obstacle_ids.clear()
	tick()
	check("回收：障碍消失后接触立即失效并清除计时", r.rope.contacts.is_empty() and not r.rope_bound and r.rope_block_substeps == 0 and r.rope.path.size() == 2 and r.state == "running")
	# 切换难度等同重试。
	run_to_contact(40)
	r.set_difficulty("困难")
	check("切换难度：清除接触与受阻状态", r.state == "start" and r.rope.contacts.is_empty() and not r.rope_bound and r.rope_block_substeps == 0)
	r.set_difficulty("普通")

func visible_parts() -> int:
	var count := 0
	for part in game.cable_parts:
		if part.visible: count += 1
	return count

func verify_view() -> void:
	fixture([Vector2(0, 400)])
	game.sync_view()
	var ring: MeshInstance3D = game.hazard_views[0].get_node("ContactRing")
	var body: MeshInstance3D = game.hazard_views[0].get_node("PillarBody")
	var straight: bool = visible_parts() == 1 and not ring.visible and game.cable_material.albedo_color == Color("60e4ea")
	check("表现：高柱模型与碰撞一致（约 5 米高、直径 1.2 米）", is_equal_approx(body.mesh.height, 5.0) and is_equal_approx(body.mesh.top_radius, 0.6) and game.hazard_views.size() == 1)
	var contact_view := false
	var blocked_view := false
	for n in range(1500):
		tick()
		if not r.rope.contacts.is_empty() and not contact_view:
			for extra in range(20): tick()
			game.sync_view()
			contact_view = visible_parts() >= 3 and ring.visible and "绳索挂柱" in game.distance_label.text
		if r.rope_bound and not blocked_view:
			for extra in range(12): tick()
			game.sync_view()
			blocked_view = ring.visible and game.cable_material.albedo_color == Color("ff5a48") and ring.material_override.albedo_color == Color("ff5a48") and "绕柱受阻" in game.distance_label.text
		if r.state == "failed": break
	game.sync_view()
	var failed_view: bool = game.panel.visible and "绳索绕柱受阻" in game.subtitle.text and "同一侧" in game.subtitle.text and game.cable_material.albedo_color == Color("ff5a48")
	# 绘制路径贴合求解路径：每段绳索中点与柱轴的水平距离不小于柱半径。
	var outside := true
	for part in game.cable_parts:
		if part.visible:
			var flat := Vector2(part.global_position.x - game.hazard_views[0].global_position.x, part.global_position.z - game.hazard_views[0].global_position.z)
			outside = outside and flat.length() >= 0.6
	check("表现：直线状态只画一段、无接触环", straight)
	check("表现：挂柱时绳索按切线与弧段绘制并亮起接触环与张力提示", contact_view and outside)
	check("表现：受阻时绳索与接触环转红并显示受阻计时", blocked_view)
	check("表现：绕柱失败面板说明原因与解法", failed_view)
	game.primary_action()
	game.sync_view()
	check("表现：重试后恢复单段绳索、接触环隐藏", r.state == "running" and visible_parts() == 1 and not ring.visible and game.cable_material.albedo_color == Color("60e4ea") and is_equal_approx(game.cable.position.y, 1.4))

func verify_stream() -> void:
	# 生产流式生成：高柱按固定间隔出现在路中央，联合走廊检查仍然通过；流式场景建出柱子视图。
	var templates = Run.Templates.new()
	templates.reset(20261012)
	var pillars := 0
	var corridor := true
	for number in range(40):
		var template: Array = templates.generate(number, "普通")
		for hazard in template:
			if hazard.kind == "pillar":
				pillars += 1
				corridor = corridor and hazard.rect.get_center().x == 0.0 and hazard.rect.size == Vector2(24, 24)
	check("生成：高柱每 4 段一根、位于路中央", pillars >= 6 and corridor and Run.Templates.PILLAR_EVERY == 4)
	r.streaming = true
	r.seed_value = 20261012
	r.retry()
	r.step(0)
	var seen := false
	var views := false
	for n in range(120 * 60):
		# 两人沿既有右侧走廊同侧前进。
		r.step(DT, Vector2.RIGHT if r.a.position.x < 178 else Vector2.ZERO, Vector2.RIGHT if r.b.position.x < 212 else Vector2.ZERO)
		if r.state != "running": break
		if not seen and r.kinds.has("pillar"):
			seen = true
			game.sync_view()
			views = game.hazard_views[r.kinds.find("pillar")].has_node("ContactRing") and r.obstacle_ids.size() == r.obstacles.size()
	metrics["stream"] = {"pillars_in_first_40_segments": pillars, "run_distance_m": r.total_distance() / SCALE, "state": r.state, "reason": r.reason}
	check("生产流式场景：同侧沿走廊行进 60 秒经过多根高柱不受阻", r.state == "running" and seen and views and r.rope_block_substeps == 0 and r.rope.contacts.is_empty() and r.total_distance() > 7000)

func verify() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	r = game.run
	reset_audit()
	check("生产配置：高柱 5 米、受阻 0.8 秒、长度容限 0.5 毫米", Run.HAZARD_TOPS.pillar / SCALE == 5.0 and Run.ROPE_BLOCK_LIMIT == 0.8 and Run.ROPE_BLOCK_SUBSTEPS == 288 and Run.ROPE_LENGTH_TOLERANCE / SCALE == 0.0005 and is_equal_approx(Run.LINK_LIMIT / SCALE, 7.33))
	verify_same_side()
	verify_split()
	verify_retreat()
	verify_taut()
	verify_speed()
	verify_fuzz()
	verify_height()
	verify_edges()
	verify_state()
	verify_view()
	verify_stream()
	var failures := 0
	for item in checks:
		if not item.passed: failures += 1
	var file := FileAccess.open("res://tests/short-rope-t02-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures == 0, "failures": failures, "checks": checks, "metrics": metrics}, "\t"))
	file.close()
	print("RESULT failures=", failures, " metrics=", JSON.stringify(metrics))
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
