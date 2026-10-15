extends RefCounted

# 历史白盒的连续充能、失效清零、锁存开门规则；道路使用真实求解路径。
# 道路交互使用较宽的站位和接收范围，历史白盒参数保持原样。
const CHARGE_TIME := 0.8
const TENSION := 0.70
const RECEIVER_RADIUS := 30.0
const RECEIVER_HEIGHT := 28.0
const HEIGHT_TOLERANCE := 4.0
const HOLD_DISTANCE := 60.0
# 内缘间距 104 已满足 70% 张力；接收半径覆盖绿区全部纵深。
const ZONE_INNER := 52.0
const ZONE_OUTER := 94.0

static func make_tutorial() -> Dictionary:
	return {"active": true, "open": false, "charge": 0.0,
		"receiver": Vector2(0, HOLD_DISTANCE),
		"left": Rect2(-ZONE_OUTER, 30, ZONE_OUTER - ZONE_INNER, 60),
		"right": Rect2(ZONE_INNER, 30, ZONE_OUTER - ZONE_INNER, 60),
		"door": Rect2(-380, 150, 760, 12)}

static func relocate(gate: Dictionary, offset: float) -> void:
	gate.receiver.y += offset
	gate.left.position.y += offset
	gate.right.position.y += offset
	gate.door.position.y += offset

static func route_input(run, gate: Dictionary) -> Array:
	# 合法按键逼近 ±65（绿区内缘外侧），半步死区仍落在绿区内，不吸附角色位置。
	return [run.Templates.keyboard_direction(Vector2(-65, gate.receiver.y) - run.a.position),
		run.Templates.keyboard_direction(Vector2(65, gate.receiver.y) - run.b.position), false, false]

static func advance(gate: Dictionary, path: PackedVector2Array, heights: PackedFloat32Array,
		tension: float, clear: bool, delta: float) -> void:
	if not gate.active or gate.open: return
	var result := conditions(gate, path, heights, tension, clear)
	gate.conditions = result
	gate.charge = minf(CHARGE_TIME, gate.charge + maxf(0,delta)) if result.ready else 0.0
	if gate.charge >= CHARGE_TIME - 0.000001: gate.open = true

# 开门和提示共用同一次真实绳路判定，显示不自行重算门条件。
static func conditions(gate: Dictionary, path: PackedVector2Array, heights: PackedFloat32Array,
		tension: float, clear: bool) -> Dictionary:
	var geometry := path.size() >= 2 and path.size() == heights.size()
	var positioned := false
	var side_present := [false, false]
	if geometry:
		var a := path[0]
		var b := path[path.size()-1]
		side_present = [gate.left.has_point(a) or gate.left.has_point(b),
			gate.right.has_point(a) or gate.right.has_point(b)]
		positioned = (gate.left.has_point(a) and gate.right.has_point(b)) or (gate.right.has_point(a) and gate.left.has_point(b))
	var crosses := false
	var at_height := false
	if geometry:
		for i in range(1, path.size()):
			var from := path[i-1]
			var to := path[i]
			if segment_crosses_receiver(from, to, RECEIVER_HEIGHT, RECEIVER_HEIGHT, gate.receiver):
				crosses = true
			if segment_crosses_receiver(from, to, heights[i-1], heights[i], gate.receiver):
				at_height = true
	return {"positioned": positioned, "side_present": side_present, "taut": tension >= TENSION, "clear": clear,
		"crosses": crosses, "at_height": at_height,
		"ready": clear and tension >= TENSION and positioned and at_height}

static func segment_crosses_receiver(from: Vector2, to: Vector2, h0: float, h1: float, receiver: Vector2) -> bool:
	# 先取绳段位于接收圆盘内的区间，再与有效绳高区间求交。
	var direction := to - from
	var offset := from - receiver
	var squared := direction.length_squared()
	var low := 0.0
	var high := 1.0
	if squared < 0.000001:
		if offset.length_squared() > RECEIVER_RADIUS * RECEIVER_RADIUS: return false
	else:
		var projection := offset.dot(direction)
		var discriminant := projection * projection - squared * (offset.length_squared() - RECEIVER_RADIUS * RECEIVER_RADIUS)
		if discriminant < 0: return false
		var root := sqrt(discriminant)
		low = maxf(low, (-projection - root) / squared)
		high = minf(high, (-projection + root) / squared)
	var rise := h1 - h0
	if absf(rise) < 0.000001:
		if absf(h0 - RECEIVER_HEIGHT) > HEIGHT_TOLERANCE: return false
	else:
		var first := (RECEIVER_HEIGHT - HEIGHT_TOLERANCE - h0) / rise
		var last := (RECEIVER_HEIGHT + HEIGHT_TOLERANCE - h0) / rise
		low = maxf(low, minf(first, last))
		high = minf(high, maxf(first, last))
	return low <= high
