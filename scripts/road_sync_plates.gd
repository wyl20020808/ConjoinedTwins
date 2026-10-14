extends RefCounted

# 道路独立教学：角色可以交换板位，开门前必须连续地面占用。
const HOLD_TIME := 0.35
const PLATE_RADIUS := 18.0
const HOLD_DISTANCE := 290.0

static func make_tutorial() -> Dictionary:
	return {"id": "sync_tutorial", "kind": "sync_plates", "active": true,
		"open": false, "charge": 0.0, "occupied": [false, false],
		"receiver": Vector2(0, HOLD_DISTANCE),
		"left": Rect2(-63, 272, 36, 36), "right": Rect2(27, 272, 36, 36),
		"door": Rect2(-250, 380, 500, 12)}

static func advance(gate: Dictionary, a: Vector2, b: Vector2,
		grounded_a: bool, grounded_b: bool, delta: float) -> void:
	if not gate.active: return
	var result := conditions(gate, a, b, grounded_a, grounded_b)
	gate.occupied = result.occupied
	if gate.open: return
	gate.conditions = result
	gate.charge = minf(HOLD_TIME, gate.charge + maxf(0, delta)) if result.ready else 0.0
	if gate.charge >= HOLD_TIME - 0.000001: gate.open = true

static func conditions(gate: Dictionary, a: Vector2, b: Vector2,
		grounded_a: bool, grounded_b: bool) -> Dictionary:
	var left: Vector2 = gate.left.get_center()
	var right: Vector2 = gate.right.get_center()
	var a_left := a.distance_squared_to(left) <= PLATE_RADIUS * PLATE_RADIUS
	var a_right := a.distance_squared_to(right) <= PLATE_RADIUS * PLATE_RADIUS
	var b_left := b.distance_squared_to(left) <= PLATE_RADIUS * PLATE_RADIUS
	var b_right := b.distance_squared_to(right) <= PLATE_RADIUS * PLATE_RADIUS
	var al := grounded_a and a_left
	var ar := grounded_a and a_right
	var bl := grounded_b and b_left
	var br := grounded_b and b_right
	return {"occupied": [al or bl, ar or br], "grounded": [grounded_a, grounded_b],
		"side_present": [a_left or b_left, a_right or b_right],
		"airborne": [(a_left and not grounded_a) or (b_left and not grounded_b),
			(a_right and not grounded_a) or (b_right and not grounded_b)],
		"ready": (al and br) or (ar and bl)}

static func route_input(run, gate: Dictionary) -> Array:
	return [run.Templates.keyboard_direction(gate.left.get_center() - run.a.position),
		run.Templates.keyboard_direction(gate.right.get_center() - run.b.position), false, false]
