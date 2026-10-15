extends RefCounted

# 与显示共用的地面几何，单位为 20/米。绳索不提供地面支撑。
const ARM_HALF := 24.0
const ARM_RADIUS := 2.0
const ARM_TOP := 12.0
const POST_RADIUS := 5.0
const POST_TOP := 40.0
const ANGULAR_SPEED := 3.8
const SHORT_GAP := 28.0
const LONG_GAP := 252.0

static func sweeper(center: Vector2, time: float, spec: Dictionary) -> Dictionary:
	var angle: float = spec.get("phase", 0.0) + time * spec.get("angular_speed", ANGULAR_SPEED)
	var arm := Vector2(cos(angle), sin(angle)) * ARM_HALF
	return {"center": center, "first": center - arm, "last": center + arm,
		"angle": angle, "radius": ARM_RADIUS, "top": ARM_TOP,
		"post_radius": POST_RADIUS, "post_top": POST_TOP}

static func point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	return p.distance_to(a + delta * clampf((p - a).dot(delta) / maxf(delta.length_squared(), 0.000001), 0, 1))

static func segments_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var ab := b - a
	var cd := d - c
	var cross := ab.cross(cd)
	if absf(cross) > 0.000001:
		var t := (c - a).cross(cd) / cross
		var u := (c - a).cross(ab) / cross
		if t >= 0 and t <= 1 and u >= 0 and u <= 1: return 0.0
	return minf(minf(point_segment_distance(a, c, d), point_segment_distance(b, c, d)),
		minf(point_segment_distance(c, a, b), point_segment_distance(d, a, b)))

# 在高度重叠的时间区间内分片。每片包含角色位移及旋转圆弧的最大偏离，
# 不仅采两个端点，也不把整个旋转圆盘永久判作危险。
static func body_hits(center: Vector2, spec: Dictionary, start: float, end: float,
		from: Vector2, to: Vector2, h0: float, h1: float, body_radius: float) -> bool:
	if minf(h0, h1) <= POST_TOP and point_segment_distance(center, from, to) <= POST_RADIUS + body_radius:
		return true
	var low := 0.0
	var high := 1.0
	if h0 > ARM_TOP and h1 > ARM_TOP: return false
	if h0 > ARM_TOP: low = (h0 - ARM_TOP) / (h0 - h1)
	if h1 > ARM_TOP: high = (ARM_TOP - h0) / (h1 - h0)
	var angular_speed: float = absf(spec.get("angular_speed", ANGULAR_SPEED))
	var count := maxi(1, int(ceil((end - start) * angular_speed * ARM_HALF / 0.25)))
	for i in range(count):
		var left := lerpf(low, high, float(i) / count)
		var right := lerpf(low, high, float(i + 1) / count)
		var middle := (left + right) * 0.5
		var sample := sweeper(center, lerpf(start, end, middle), spec)
		var arc_margin := angular_speed * (end - start) * (right - left) * ARM_HALF * 0.5
		if segments_distance(from.lerp(to, left), from.lerp(to, right), sample.first, sample.last) <= body_radius + ARM_RADIUS + arc_margin:
			return true
	return false

static func supported(point: Vector2, radius: float, gaps: Array[Rect2]) -> bool:
	for gap in gaps:
		var nearest := Vector2(clampf(point.x, gap.position.x, gap.end.x), clampf(point.y, gap.position.y, gap.end.y))
		if point.distance_squared_to(nearest) < radius * radius - 0.00001: return false
	return true

# 整条移动线段与缺口矩形求最短距离，短缺口也不能从稀疏采样点之间漏过。
static func supported_sweep(from: Vector2, to: Vector2, radius: float, gaps: Array[Rect2]) -> bool:
	if not supported(from, radius, gaps) or not supported(to, radius, gaps): return false
	for gap in gaps:
		var corners := [gap.position, Vector2(gap.end.x, gap.position.y), gap.end, Vector2(gap.position.x, gap.end.y)]
		for i in range(4):
			if segments_distance(from, to, corners[i], corners[(i + 1) % 4]) < radius - 0.00001: return false
	return true

static func low_segment(first: Vector2, last: Vector2, z0: float, z1: float, top: float) -> Array:
	if z0 > top and z1 > top: return []
	if z0 > top: first = first.lerp(last, (z0 - top) / (z0 - z1))
	elif z1 > top: last = first.lerp(last, (top - z0) / (z1 - z0))
	return [first, last]

static func rope_hits(center: Vector2, spec: Dictionary, start: float, end: float,
		path: PackedVector2Array, z: PackedFloat32Array, movement_margin: float) -> bool:
	var angular_speed: float = absf(spec.get("angular_speed", ANGULAR_SPEED))
	var count := maxi(1, int(ceil((end - start) * angular_speed * ARM_HALF / 0.25)))
	for n in range(1, path.size()):
		var post := low_segment(path[n - 1], path[n], z[n - 1], z[n], POST_TOP + 1.0)
		if not post.is_empty() and point_segment_distance(center, post[0], post[1]) <= POST_RADIUS + 1.0 + movement_margin: return true
		var arm := low_segment(path[n - 1], path[n], z[n - 1], z[n], ARM_TOP + 1.0)
		if arm.is_empty(): continue
		for i in range(count):
			var sample := sweeper(center, lerpf(start, end, (i + 0.5) / count), spec)
			var arc_margin := angular_speed * (end - start) * ARM_HALF / count * 0.5
			if segments_distance(arm[0], arm[1], sample.first, sample.last) <= ARM_RADIUS + 1.0 + movement_margin + arc_margin: return true
	return false
