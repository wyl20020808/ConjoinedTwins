extends RefCounted

const CHARGE_TIME := 0.8
var charge := 0.0
var plate_occupied: Array[bool] = []
var checkpoint_active := false

func reset() -> void:
	charge = 0.0
	checkpoint_active = false
	plate_occupied.clear()

static func hazard_phase(time: float, offset: float) -> int:
	var phase := fposmod(time + offset, 6.0)
	if phase < 3.6:
		return 0
	if phase < 4.4:
		return 1
	return 2

static func hits(rect: Rect2, p: Vector2) -> bool:
	return rect.grow(12.0).has_point(p)

func update(level: Dictionary, a: Vector2, b: Vector2, delta: float, time: float) -> String:
	plate_occupied.clear()
	for plate: Vector2 in level.plates:
		plate_occupied.append(a.distance_to(plate) < 24.0 or b.distance_to(plate) < 24.0)
	var both_plates := plate_occupied.size() == 2 and plate_occupied[0] and plate_occupied[1]
	var receiver: Vector2 = level.receiver
	var valid := receiver != Vector2.ZERO and a.distance_to(b) >= 187.0 and Geometry2D.get_closest_point_to_segment(receiver, a, b).distance_to(receiver) <= 18.0
	charge = minf(CHARGE_TIME, charge + delta) if valid else 0.0
	for gate: Dictionary in level.gates:
		if (gate.kind == "plates" and both_plates) or (gate.kind == "receiver" and charge >= CHARGE_TIME - 0.000001):
			gate.open = true
	for hazard: Dictionary in level.hazards:
		if hazard_phase(time, hazard.offset) == 2 and (hits(hazard.rect, a) or hits(hazard.rect, b)):
			return "death"
	if level.checkpoint.has_point(a) and level.checkpoint.has_point(b):
		checkpoint_active = true
	if level.exit.has_point(a) and level.exit.has_point(b):
		return "exit"
	return ""
