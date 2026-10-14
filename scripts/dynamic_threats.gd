extends RefCounted

# 生产动态威胁。地面单位仍为 20/米；轨迹一经预警即锁定，不读取玩家位置修正方向。
const CONFIG := {
	"fly_low": {"size": Vector2(56, 24), "velocity": Vector2(0, -300), "bottom": 0.0, "top": 10.0},
	"fly_body": {"size": Vector2(56, 24), "velocity": Vector2(0, -480), "bottom": 18.0, "top": 38.0},
	"rocket": {"size": Vector2(40, 64), "velocity": Vector2(0, -860), "bottom": 18.0, "top": 38.0},
	"stone_ball": {"size": Vector2(90, 90), "velocity": Vector2(0, -350), "bottom": 0.0, "top": 90.0},
	"iron_ball": {"size": Vector2(80, 80), "velocity": Vector2(0, -400), "bottom": 0.0, "top": 80.0}}

static func is_ball(kind: String) -> bool:
	return kind in ["stone_ball", "iron_ball"]

static func spec(kind: String, warning: float) -> Dictionary:
	var result: Dictionary = CONFIG[kind].duplicate()
	result.merge({"front": true, "offset": Vector2.ZERO, "locked": false, "warning": warning,
		"warning_evidence": {}, "blocked": false, "blocked_time": 0.0, "travel": 0.0, "trigger": -1.0})
	return result

# 从两人的当前位置共同换到危险左/右侧，计入角色半径与 0.35 秒输入余量。
# 使用当前实际前向输入估算相对速度；证据同时保存速度、TTC 和共同换边时间。
static func warn(data: Dictionary, rect: Rect2, players: Array, velocities: Array, lateral: float, edge: float, radius: float, now: float, maximum_forward: float = -INF) -> void:
	if data.locked: return
	var left := rect.position.x - radius - 2.0
	var right := rect.end.x + radius + 2.0
	var left_time := INF
	var right_time := INF
	if left >= -edge: left_time = maxf(maxf(0, players[0].x - left), maxf(0, players[1].x - left)) / lateral
	if right <= edge: right_time = maxf(maxf(0, right - players[0].x), maxf(0, right - players[1].x)) / lateral
	var change_time := minf(left_time, right_time)
	var ttc := INF
	var possible_ttc := INF
	var relative: Array = []
	for i in range(2):
		var closing: float = velocities[i].y - data.velocity.y
		relative.append(closing)
		if closing > 0: ttc = minf(ttc, maxf(0, (rect.position.y - radius - players[i].y) / closing))
		var possible_closing: float = maxf(velocities[i].y, maximum_forward) - data.velocity.y
		if possible_closing > 0: possible_ttc = minf(possible_ttc, maxf(0, (rect.position.y - radius - players[i].y) / possible_closing))
	var lead := maxf(data.warning, change_time + 0.35)
	# 纵向轴可在下一固定步反向；按合法最大前速提前锁定，仍保存当帧实际 TTC。
	if possible_ttc <= lead + 1.0 / 120.0:
		data.locked = true
		data.trigger = now
		data.warning_evidence = {"relative_speed": relative, "ttc": ttc, "joint_change_time": change_time,
			"required_lead": lead, "velocity": data.velocity, "time": now, "left_time": left_time, "right_time": right_time, "possible_ttc": possible_ttc}

# 球体与角色竖直胶囊的连续相对运动检测。高度跨球心处切段，避免包围盒角落误判。
static func sphere_body(from: Vector2, to: Vector2, h0: float, h1: float, c0: Vector2, c1: Vector2, radius: float, body: float, player_radius: float) -> bool:
	var cuts: Array = [0.0, 1.0]
	if absf(h1 - h0) > 0.000001:
		for height in [radius, radius - body]:
			var t: float = (height - h0) / (h1 - h0)
			if t > 0 and t < 1: cuts.append(t)
	cuts.sort()
	for i in range(cuts.size() - 1):
		var l: float = cuts[i]
		var r: float = cuts[i + 1]
		var p := from.lerp(to, l) - c0.lerp(c1, l)
		var q := from.lerp(to, r) - c0.lerp(c1, r)
		var z0 := lerpf(h0, h1, l)
		var z1 := lerpf(h0, h1, r)
		var mid := (z0 + z1) * 0.5
		var dz0 := z0 - radius if mid > radius else (z0 + body - radius if mid + body < radius else 0.0)
		var dz1 := z1 - radius if mid > radius else (z1 + body - radius if mid + body < radius else 0.0)
		var v := Vector3(p.x, p.y, dz0)
		var d := Vector3(q.x, q.y, dz1) - v
		var t := clampf(-v.dot(d) / maxf(d.length_squared(), 0.000001), 0, 1)
		if (v + d * t).length() <= radius + player_radius: return true
	return false

# 球心扫过静止绳段：在最近点投影越过两个端点处切段，每段解析求最小距离时刻。
# 若两端时刻都没碰撞但中间擦入，返回内部接触时刻供固定步提交接触，再继续余下运动。
static func circle_contact_fraction(p: Vector2, q: Vector2, c0: Vector2, c1: Vector2, radius: float) -> float:
	var line := q - p
	var velocity := c1 - c0
	var squared := line.length_squared()
	var cuts: Array = [0.0, 1.0]
	var rate := velocity.dot(line)
	if squared > 0.000001 and absf(rate) > 0.000001:
		for boundary in [0.0, squared]:
			var t: float = (boundary - (c0 - p).dot(line)) / rate
			if t > 0 and t < 1: cuts.append(t)
	cuts.sort()
	for i in range(cuts.size() - 1):
		var l: float = cuts[i]
		var r: float = cuts[i + 1]
		var mid := c0.lerp(c1, (l + r) * 0.5)
		var u := (mid - p).dot(line) / maxf(squared, 0.000001)
		var first := c0 - (p if u <= 0 else q)
		var delta := velocity
		if u > 0 and u < 1:
			first = c0 - p - line * ((c0 - p).dot(line) / squared)
			delta -= line * (velocity.dot(line) / squared)
		var t := clampf(-first.dot(delta) / maxf(delta.length_squared(), 0.000001), l, r)
		if t > 0.000001 and t < 0.999999 and (first + delta * t).length() < radius: return t
	return 1.0

# 运动绳段与飞行危险长方体的连续检测，包含沿绳的高度变化。
static func rope_box_sweep(p0: Vector3, q0: Vector3, p1: Vector3, q1: Vector3, minimum: Vector3, maximum: Vector3, depth: int = 0) -> bool:
	var pm := (p0 + p1) * 0.5
	var qm := (q0 + q1) * 0.5
	var motion := Vector3(maxf(absf(p0.x - p1.x), absf(q0.x - q1.x)), maxf(absf(p0.y - p1.y), absf(q0.y - q1.y)), maxf(absf(p0.z - p1.z), absf(q0.z - q1.z))) * 0.5
	if not line_box(pm, qm, minimum - motion, maximum + motion): return false
	if line_box(pm, qm, minimum, maximum): return true
	if depth >= 24 or motion.length() < 0.002: return true
	return rope_box_sweep(p0, q0, pm, qm, minimum, maximum, depth + 1) or rope_box_sweep(pm, qm, p1, q1, minimum, maximum, depth + 1)

static func line_box(p: Vector3, q: Vector3, minimum: Vector3, maximum: Vector3) -> bool:
	var low := 0.0
	var high := 1.0
	for axis in range(3):
		var delta := q[axis] - p[axis]
		if absf(delta) < 0.000001:
			if p[axis] < minimum[axis] or p[axis] > maximum[axis]: return false
		else:
			var first := (minimum[axis] - p[axis]) / delta
			var last := (maximum[axis] - p[axis]) / delta
			low = maxf(low, minf(first, last))
			high = minf(high, maxf(first, last))
			if low > high: return false
	return true
