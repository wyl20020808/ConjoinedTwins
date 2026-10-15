extends RefCounted

# 独立绳索求解模块（首轮）：两端点之间一条贴地拉紧的折线/弧线路径。
# 保存端点、接触障碍的稳定标识、连续绕行侧和接触路径；有效长度按地面绕障路径计算，
# 绳段实际高度决定能否挂上或越过障碍。
# 几何部分处理圆形障碍的切线与表面弧段；松绳、弯曲和接触物理由 rope_physics 统一推进，不模拟复杂打结。
# 绕行侧一旦建立就保持不变，不会逐帧改选另一侧的更短路径。解除接触只有两条途径：
# 一、连续缠绕角退回零后进入“松脱待定”，绳段离开表面超过 RELEASE_DISTANCE，
#     或连续 RELEASE_SOLVES 次求解都没有再压回，才真正解除；期间压回即恢复原接触。
# 二、绳段在障碍占地范围内的实际高度全部高过顶部（或低于底部）。
const DETACH := 0.0000001
const PENETRATION := 0.0001
const RELEASE_DISTANCE := 0.5
const RELEASE_SOLVES := 36
const MAX_PASSES := 12
const ARC_STEP := 0.3

const Physics = preload("res://scripts/rope_physics.gd")
var physical := {}

var a := Vector2.ZERO
var b := Vector2.ZERO
var height_a := 0.0
var height_b := 0.0
# 接触按 a 到 b 的顺序保存：{id, center, radius, side, wrap, top, bottom, loose}。
# side = +1 表示圆心在绳索行进方向左侧（逆时针绕行），-1 为右侧；wrap 为连续缠绕角（弧度）。
# loose = 0 为压在表面上的有效接触；大于 0 为松脱待定已持续的求解次数，此时不参与路径与长度。
var contacts: Array = []
# 当前被绳段从上方（或下方）越过的障碍，仅为本次求解的几何结论，不豁免之后的碰撞。
var lifted := {}
# length 是当前真实路径的长度。required 是约束长度：越过矮障碍的绳段按“此刻落下会被挂住”的
# 绕障路径计长（取圆心所在一侧，与落下时实际建立的接触一致）。调用方用 required 约束位移，
# 腾空期间就不会走进落下后超出绳长的位置，落下时路径长度不突变、不需要任何事后修正。
var length := 0.0
var required := 0.0
var total_wrap := 0.0
var path := PackedVector2Array()
# 最近一次求解（含试算）的结果，供调用方判断受阻原因；solved_contacts 只计有效接触，
# solved_blocking 另外计入被越过、落下即挂住的障碍。
var solved_contacts := 0
var solved_blocking := 0
var solved_valid := true

func reset(start: Vector2, end: Vector2) -> void:
	a = start
	b = end
	height_a = 0.0
	height_b = 0.0
	physical = {}
	contacts.clear()
	lifted.clear()
	length = start.distance_to(end)
	required = length
	total_wrap = 0.0
	path = PackedVector2Array([start, end])
	solved_contacts = 0
	solved_blocking = 0
	solved_valid = true

# 附近没有可挂住绳索的障碍时的直线状态。
func straight(start: Vector2, end: Vector2, rope_a: float, rope_b: float) -> void:
	a = start
	b = end
	height_a = rope_a
	height_b = rope_b
	contacts.clear()
	lifted.clear()
	length = start.distance_to(end)
	required = length
	total_wrap = 0.0
	path = PackedVector2Array([start, end])

# 坐标重定位：端点、接触圆心和路径整体平移，接触关系不变。
func shift(offset: Vector2) -> void:
	Physics.shift(physical, Vector3(offset.x, 0, offset.y))
	a += offset
	b += offset
	for contact in contacts: contact.center += offset
	for i in range(path.size()): path[i] += offset

# 含松脱待定的接触：用于回收保护等“仍与该障碍有关”的判断。
func has_contact(id: int) -> bool:
	for contact in contacts:
		if contact.id == id: return true
	return false

# 只看压在表面上的有效接触。
func touches(id: int) -> bool:
	for contact in contacts:
		if contact.id == id and contact.loose == 0: return true
	return false

func touching() -> int:
	var count := 0
	for contact in contacts:
		if contact.loose == 0: count += 1
	return count

func contact_ids() -> Array:
	var result: Array = []
	for contact in contacts: result.append(contact.id)
	return result

# 两个带绕行侧的圆（端点半径为零）之间的切线段；返回 [起点, 终点, 切线法向角]，无解返回空。
static func tangent(c1: Vector2, r1: float, s1: int, c2: Vector2, r2: float, s2: int) -> Array:
	var d := c2 - c1
	# 两个端点之间是普通直线段，重合时长度为零，同样有效。
	if r1 == 0.0 and r2 == 0.0: return [c1, c2, d.angle() + PI * 0.5]
	var span := d.length()
	var k := s2 * r2 - s1 * r1
	if span <= absf(k) + 0.000001: return []
	var phi := d.angle() + acos(k / span)
	var normal := Vector2(cos(phi), sin(phi))
	return [c1 - normal * (s1 * r1), c2 - normal * (s2 * r2), phi]

static func segment_distance(p: Vector2, q: Vector2, c: Vector2) -> float:
	var d := q - p
	var squared := d.length_squared()
	if squared < 0.000000000001: return p.distance_to(c)
	return c.distance_to(p + d * clampf((c - p).dot(d) / squared, 0.0, 1.0))

# 有效接触链的几何：各切线段、每段起点的累计路径长度和总长；同时把缠绕角更新为
# 与上一状态最接近的连续表示（允许超过一圈，也能可靠识别退回零）。
static func chain(nodes: Array, end_a: Vector2, end_b: Vector2) -> Dictionary:
	var segments: Array = []
	var count := nodes.size()
	for i in range(count + 1):
		var from_center: Vector2 = end_a if i == 0 else nodes[i - 1].center
		var from_radius: float = 0.0 if i == 0 else nodes[i - 1].radius
		var from_side: int = 0 if i == 0 else nodes[i - 1].side
		var to_center: Vector2 = end_b if i == count else nodes[i].center
		var to_radius: float = 0.0 if i == count else nodes[i].radius
		var to_side: int = 0 if i == count else nodes[i].side
		var segment := tangent(from_center, from_radius, from_side, to_center, to_radius, to_side)
		if segment.is_empty(): return {"valid": false}
		segments.append(segment)
	var starts: Array = []
	var total := 0.0
	for i in range(count + 1):
		starts.append(total)
		total += segments[i][0].distance_to(segments[i][1])
		if i < count:
			var node: Dictionary = nodes[i]
			var raw: float = node.side * (segments[i + 1][2] - segments[i][2])
			node.wrap = raw + TAU * roundf((node.wrap - raw) / TAU)
			total += node.radius * maxf(0.0, node.wrap)
	return {"valid": true, "segments": segments, "starts": starts, "total": total}

# 第 index 段与圆的关系：0 未穿入；1 穿入且绳段高度与障碍高度范围重叠（必须挂住）；
# 2 穿入但占地范围内的绳段全部高过顶部或低于底部（越过）。高度沿路径长度在两端挂点间线性变化，
# 因此只需检查绳段进入和离开占地圆的两个位置。
static func crossing(geometry: Dictionary, index: int, circle: Dictionary, rope_a: float, rope_b: float) -> int:
	var p: Vector2 = geometry.segments[index][0]
	var q: Vector2 = geometry.segments[index][1]
	if segment_distance(p, q, circle.center) >= circle.radius - PENETRATION: return 0
	var d := q - p
	var span := d.length()
	var enter := 0.0
	var leave := span
	if span > 0.000001:
		var along: float = (circle.center - p).dot(d) / span
		var half := sqrt(maxf(0.0, circle.radius * circle.radius - ((circle.center - p).length_squared() - along * along)))
		enter = clampf(along - half, 0.0, span)
		leave = clampf(along + half, 0.0, span)
	var total: float = maxf(geometry.total, 0.000001)
	var first := lerpf(rope_a, rope_b, (geometry.starts[index] + enter) / total)
	var last := lerpf(rope_a, rope_b, (geometry.starts[index] + leave) / total)
	if minf(first, last) >= circle.top or maxf(first, last) <= circle.bottom: return 2
	return 1

static func active(list: Array) -> Array:
	var result: Array = []
	for contact in list:
		if contact.loose == 0: result.append(contact)
	return result

# circles: [{id, center, radius, top, bottom}]，radius 已含绳索与表面的间隙。
# rope_a / rope_b 为两端绳索挂点的实际高度。commit 为 false 时只试算长度，不改变已保存状态。
func solve(end_a: Vector2, end_b: Vector2, rope_a: float, rope_b: float, circles: Array, commit: bool) -> float:
	var list: Array = []
	var known := {}
	for circle in circles: known[circle.id] = circle
	for contact in contacts:
		# 障碍已不存在（被回收）时接触随之失效；运动障碍在这里刷新圆心与半径。
		if not known.has(contact.id): continue
		var copy: Dictionary = contact.duplicate()
		var source: Dictionary = known[contact.id]
		copy.center = source.center
		copy.radius = source.radius
		copy.top = source.top
		copy.bottom = source.bottom
		list.append(copy)
	var over := {}
	var nodes: Array = []
	var geometry := {"valid": false}
	for pass_index in range(MAX_PASSES):
		nodes = active(list)
		geometry = chain(nodes, end_a, end_b)
		if not geometry.valid: break
		over.clear()
		var changed := false
		var count := nodes.size()
		for i in range(count):
			var contact: Dictionary = nodes[i]
			# 缠绕角退回零：绳段与表面相切。先转为松脱待定，保留绕行侧，不立即丢弃。
			if contact.wrap <= DETACH:
				contact.wrap = 0.0
				contact.loose = 1
				changed = true
				break
			# 抬离：去掉这个接触后的绳段若不再穿入，要求弧段两端都高过顶部（或低于底部）；
			# 若仍穿入，用与新建接触完全相同的占地高度判定，避免解除后立刻又被挂上。
			var first := lerpf(rope_a, rope_b, (geometry.starts[i + 1] - contact.radius * contact.wrap) / maxf(geometry.total, 0.000001))
			var last := lerpf(rope_a, rope_b, geometry.starts[i + 1] / maxf(geometry.total, 0.000001))
			if minf(first, last) < contact.top and maxf(first, last) > contact.bottom: continue
			var rest: Array = []
			for n in range(count):
				if n != i: rest.append(nodes[n].duplicate())
			var trial := chain(rest, end_a, end_b)
			if trial.valid and crossing(trial, i, contact, rope_a, rope_b) != 1:
				list.erase(contact)
				changed = true
				break
		if changed: continue
		for i in range(count + 1):
			for circle in circles:
				if (i > 0 and nodes[i - 1].id == circle.id) or (i < count and nodes[i].id == circle.id): continue
				var state := crossing(geometry, i, circle, rope_a, rope_b)
				if state == 0: continue
				if state == 2:
					over[circle.id] = i
					continue
				# 这一段上若有同一障碍的松脱待定接触，压回即恢复原接触和原绕行侧。
				var slot := list.size()
				var seen := 0
				var pending = null
				for n in range(list.size()):
					if list[n].loose == 0:
						if seen == i:
							slot = n
							break
						seen += 1
					elif seen == i and list[n].id == circle.id:
						pending = list[n]
				if pending != null:
					pending.loose = 0
					pending.wrap = 0.0
				else:
					# 单步位移远小于半径，穿入量很小：圆心此刻所在一侧就是接触前所在一侧。
					# 绳段从上方落到障碍上时同样取圆心所在一侧，之后保持不变。
					var p: Vector2 = geometry.segments[i][0]
					var q: Vector2 = geometry.segments[i][1]
					var side := 1 if (q - p).cross(circle.center - p) >= 0.0 else -1
					list.insert(slot, {"id": circle.id, "center": circle.center, "radius": circle.radius, "side": side, "wrap": 0.0, "top": circle.top, "bottom": circle.bottom, "loose": 0})
				changed = true
				break
			if changed: break
		if not changed: break
	var valid: bool = geometry.valid
	var result := INF
	var wrap_sum := 0.0
	if valid:
		nodes = active(list)
		if nodes.is_empty():
			result = end_a.distance_to(end_b)
		else:
			result = 0.0
			for piece in geometry.segments: result += piece[0].distance_to(piece[1])
			for contact in nodes:
				result += contact.radius * contact.wrap
				wrap_sum += contact.wrap
		# 松脱待定的接触：离开表面足够远，或连续多次求解都没有压回，才真正解除。
		var seen := 0
		var index := 0
		while index < list.size():
			var contact: Dictionary = list[index]
			if contact.loose == 0:
				seen += 1
				index += 1
				continue
			var segment: Array = geometry.segments[seen]
			var clearance: float = segment_distance(segment[0], segment[1], contact.center) - contact.radius
			if clearance > RELEASE_DISTANCE or contact.loose > RELEASE_SOLVES or over.has(contact.id):
				list.remove_at(index)
			else:
				contact.loose += 1
				index += 1
	# 约束长度：把被越过的障碍当作此刻落下后的接触插入接触链重新计长。
	var demand := result
	if valid and not over.is_empty():
		var landed: Array = []
		for i in range(geometry.segments.size()):
			for circle in circles:
				if over.get(circle.id, -1) != i: continue
				var p: Vector2 = geometry.segments[i][0]
				var q: Vector2 = geometry.segments[i][1]
				landed.append({"id": circle.id, "center": circle.center, "radius": circle.radius, "side": 1 if (q - p).cross(circle.center - p) >= 0.0 else -1, "wrap": 0.0})
			if i < nodes.size(): landed.append(nodes[i].duplicate())
		var grounded := chain(landed, end_a, end_b)
		if grounded.valid: demand = maxf(result, grounded.total)
	solved_contacts = nodes.size() if valid else 0
	solved_blocking = nodes.size() + over.size() if valid else 0
	solved_valid = valid
	# 地面拓扑路径与两端高度组成三维不可伸长长度。
	result = Vector2(result, rope_b - rope_a).length()
	demand = Vector2(demand, rope_b - rope_a).length()
	# 球体截面随跳跃高度变化：预留全跳跃过程中最大的截面，避免下降时突然超长。
	# 预留只影响 required 和 blocking，不伪造真实接触，也不作为受阻失败计时依据。
	var expanded: Array = []
	var reserve := false
	for circle in circles:
		var copy: Dictionary = circle.duplicate()
		if copy.has("max_radius"):
			reserve = reserve or copy.max_radius > copy.radius + 0.000001
			copy.radius = copy.max_radius
			copy.erase("max_radius")
		expanded.append(copy)
	if valid and reserve:
		var trial = get_script().new()
		trial.contacts = list.duplicate(true)
		var reserved: float = trial.solve(end_a, end_b, rope_a, rope_b, expanded, false)
		demand = maxf(demand, reserved)
		solved_blocking = maxi(solved_blocking, trial.solved_blocking)
		solved_valid = solved_valid and trial.solved_valid
	if not commit or not solved_valid: return demand
	a = end_a
	b = end_b
	height_a = rope_a
	height_b = rope_b
	contacts = list
	lifted = over
	length = result
	required = demand
	total_wrap = wrap_sum
	path = PackedVector2Array()
	for i in range(geometry.segments.size()):
		path.append(geometry.segments[i][0])
		path.append(geometry.segments[i][1])
		if i < nodes.size():
			var contact: Dictionary = nodes[i]
			var steps := maxi(1, ceili(contact.wrap / ARC_STEP))
			for n in range(1, steps):
				var phi: float = geometry.segments[i][2] + contact.side * contact.wrap * n / steps
				path.append(contact.center - Vector2(cos(phi), sin(phi)) * (contact.side * contact.radius))
	return demand

# 路径上各点对应的绳索高度（按沿路径长度的比例在两端挂点之间插值）。
func path_heights() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var travelled := 0.0
	var total := 0.0
	for i in range(1, path.size()): total += path[i - 1].distance_to(path[i])
	for i in range(path.size()):
		if i > 0: travelled += path[i - 1].distance_to(path[i])
		result.append(lerpf(height_a, height_b, travelled / maxf(total, 0.000001)))
	return result

# 几何求解只负责接触拓扑和运动可行性；实际绳形、危险检测与渲染共用这条质点链。
func physical_path() -> PackedVector2Array:
	if physical.is_empty(): return path
	var result := PackedVector2Array()
	for p in physical.points: result.append(Vector2(p.x, p.z))
	return result

func physical_heights() -> PackedFloat32Array:
	if physical.is_empty(): return path_heights()
	var result := PackedFloat32Array()
	for p in physical.points: result.append(p.y)
	return result

func guide3d() -> PackedVector3Array:
	var result := PackedVector3Array()
	var z := path_heights()
	for i in range(path.size()): result.append(Vector3(path[i].x, z[i], path[i].y))
	return result
