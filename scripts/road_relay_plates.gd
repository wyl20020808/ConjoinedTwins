extends RefCounted

# 接力踏板：门前一块、门后一块，同侧相邻，绳长内可同时够到。
# - 任一人落地站在门前踏板上时，闸门暂时打开（ajar），另一人可穿过；
# - 有人正处在门洞里时闸门保持打开，不会夹人；
# - 任一人落地站在门后踏板上连续 HOLD_TIME 秒，闸门永久打开，先前守板的人随后通过。
const HOLD_TIME := 0.35
const PLATE_RADIUS := 26.0

static func make(y: float, side: float, edge: float) -> Dictionary:
	# 门在接收点前 5 米；门前踏板在门前 3 米，门后踏板在门后 2.5 米、横向错开 4 米。
	var door := Rect2(-edge - 20, y + 100, edge * 2 + 40, 12)
	return {"id": "relay", "kind": "relay", "active": true, "open": false, "ajar": false,
		"charge": 0.0, "occupied": [false, false], "receiver": Vector2(0, y),
		"near": Rect2(side * -40 - PLATE_RADIUS, y + 40 - PLATE_RADIUS, PLATE_RADIUS * 2, PLATE_RADIUS * 2),
		"far": Rect2(side * 40 - PLATE_RADIUS, y + 150 - PLATE_RADIUS, PLATE_RADIUS * 2, PLATE_RADIUS * 2),
		"door": door, "opened_at": -1.0}

static func on_plate(point: Vector2, plate: Rect2) -> bool:
	return point.distance_squared_to(plate.get_center()) <= PLATE_RADIUS * PLATE_RADIUS

static func advance(gate: Dictionary, a: Vector2, b: Vector2, grounded_a: bool, grounded_b: bool,
		body_radius: float, delta: float) -> void:
	if not gate.active: return
	var near_held := (grounded_a and on_plate(a, gate.near)) or (grounded_b and on_plate(b, gate.near))
	var far_held := (grounded_a and on_plate(a, gate.far)) or (grounded_b and on_plate(b, gate.far))
	var door: Rect2 = gate.door.grow(body_radius)
	var in_door := door.has_point(a) or door.has_point(b)
	gate.occupied = [near_held, far_held]
	gate.conditions = {"near": near_held, "far": far_held, "in_door": in_door}
	if gate.open:
		gate.ajar = false
		return
	gate.ajar = near_held or (gate.ajar and in_door)
	gate.charge = minf(HOLD_TIME, gate.charge + maxf(0.0, delta)) if far_held else 0.0
	if gate.charge >= HOLD_TIME - 0.000001:
		gate.open = true
		gate.ajar = false

# 自动路线（测试与队友参考）：一人去门前踏板，另一人在门开后穿门去门后踏板。
static func route_input(run, gate: Dictionary) -> Array:
	var near: Vector2 = gate.near.get_center()
	var far: Vector2 = gate.far.get_center()
	var a_target: Vector2 = near
	var b_target: Vector2 = far if gate.ajar or gate.open else Vector2(far.x, gate.door.position.y - 30)
	return [run.Templates.keyboard_direction(a_target - run.a.position),
		run.Templates.keyboard_direction(b_target - run.b.position), false, false]
