extends RefCounted

# 三维质点链，单位与道路模拟一致（20 单位/米）。纯数据状态可以存档、克隆和联机复放。
const COUNT := 24
const RADIUS := 1.0
const ITERATIONS := 12
const COMPLIANCE := 0.00000002
const GRAVITY := Vector3(0, -800, 0)

static func create(a: Vector3, b: Vector3, length: float) -> Dictionary:
	var points := PackedVector3Array()
	for i in range(COUNT + 1):
		var t := float(i) / COUNT
		# 轻微侧弯打破完全重合或竖直链的对称，不改变固定段长约束。
		points.append(a.lerp(b, t) + Vector3(0, -sin(PI * t) * minf(20, length * 0.1), sin(PI * t) * 0.1))
	return {"points": points, "previous": points.duplicate(), "bound": [true, true],
		"tension": 0.0, "stretch": 0.0, "length": length}

static func release(state: Dictionary, role: int) -> void:
	if not state.is_empty(): state.bound[role] = false

static func shift(state: Dictionary, offset: Vector3) -> void:
	if state.is_empty(): return
	for key in ["points", "previous"]:
		for i in range(state[key].size()): state[key][i] += offset

static func advance(state: Dictionary, a: Vector3, b: Vector3, dt: float,
		floor_query: Callable, colliders: Array, guide: PackedVector3Array) -> void:
	if dt <= 0: return
	var points: PackedVector3Array = state.points
	var previous: PackedVector3Array = state.previous
	var bound_a:bool=state.bound[0]
	var bound_b:bool=state.bound[1]
	var rest: float = state.length / COUNT
	var alpha := COMPLIANCE / (dt * dt)
	var damping:=exp(-2.4*dt)
	var gravity_step:=GRAVITY*dt*dt
	var bend_alpha:=0.0002/(dt*dt)
	var lambdas := PackedFloat32Array()
	lambdas.resize(COUNT)
	for i in range(COUNT + 1):
		if (i == 0 and bound_a) or (i == COUNT and bound_b):
			previous[i] = points[i]
			points[i] = a if i==0 else b
			continue
		var position := points[i]
		points[i] += (position - previous[i]) * damping + gravity_step
		previous[i] = position
	# 接近全长时几何路径就是不可伸长绳的极限解，消除有限迭代的残留弯曲。
	var span := 0.0
	for i in range(1, guide.size()): span += guide[i - 1].distance_to(guide[i])
	var taut: bool = bound_a and bound_b and span >= state.length * 0.995
	if taut and guide.size() >= 2:
		for i in range(COUNT + 1):
			points[i] = along(guide, span * i / COUNT)
			if i>0 and i<COUNT: points[i] = project(points[i],points[i],floor_query,colliders)
			if i>0 and i<COUNT: previous[i] = points[i]
	else:
		for iteration in range(ITERATIONS):
			if bound_a: points[0] = a
			if bound_b: points[COUNT] = b
			# 交替扫描避免修正偏向某一端。
			for k in range(COUNT):
				var i := k if iteration % 2 == 0 else COUNT - k - 1
				var offset := points[i + 1] - points[i]
				var distance := offset.length()
				if distance < 0.000001: continue
				var w0 := 0.0 if i == 0 and bound_a else 1.0
				var w1 := 0.0 if i + 1 == COUNT and bound_b else 1.0
				var change := (-(distance - rest) - alpha * lambdas[i]) / (w0 + w1 + alpha)
				lambdas[i] += change
				var correction := offset / distance * change
				points[i] -= correction * w0
				points[i + 1] += correction * w1
			# 有限弯曲刚度抑制不自然的尖折，柔顺度保留松绳的弯曲与堆叠。
			for i in range(COUNT-1):
				var bend := points[i+2]-points[i]
				var distance := bend.length()
				if distance < 0.000001: continue
				var w0 := 0.0 if i==0 and bound_a else 1.0
				var w1 := 0.0 if i+2==COUNT and bound_b else 1.0
				var correction := bend/distance*(distance-rest*2.0)/(w0+w1+bend_alpha)
				points[i] += correction*w0
				points[i+2] -= correction*w1
			for i in range(COUNT + 1):
				if (i == 0 and bound_a) or (i == COUNT and bound_b): continue
				var before := points[i]
				# 按粒子半径分片扫掠，不能一步穿过细柱或移动到崖壁另一侧。
				var samples := clampi(ceili(previous[i].distance_to(points[i])/RADIUS),1,12)
				var projected := previous[i]
				for step in range(1,samples+1):
					var target := projected+(points[i]-previous[i])/samples
					projected = project(target,projected,floor_query,colliders)
				points[i] = projected
				if not before.is_equal_approx(points[i]):
					# 接触时保留法向修正并衰减切向速度，形成麻绳拖地摩擦。
					previous[i] = points[i] - (before - previous[i]) * 0.65
	if bound_a: points[0] = a
	if bound_b: points[COUNT] = b
	state.points = points
	state.previous = previous
	var actual := 0.0
	for i in range(COUNT): actual += points[i].distance_to(points[i + 1])
	state.actual_length = actual
	state.stretch = maxf(0, actual / state.length - 1)
	state.tension = maxf(0, -lambdas[lambdas.size() / 2]) / (dt * dt)

static func project(point: Vector3, from: Vector3, floor_query: Callable, colliders: Array) -> Vector3:
	var floor_height: float = floor_query.call(Vector2(point.x, point.z))
	if is_finite(floor_height) and point.y < floor_height + RADIUS and from.y >= floor_height - RADIUS:
		point.y = floor_height + RADIUS
	for collider in colliders:
		if collider.has("radius"):
			if point.y < collider.bottom - RADIUS or point.y > collider.top + RADIUS: continue
			var direction: Vector2 = Vector2(point.x, point.z) - collider.center
			var radius: float = collider.radius + RADIUS
			if direction.length_squared() >= radius * radius: continue
			if direction.length_squared() < 0.000001: direction = Vector2.RIGHT
			direction = direction.normalized() * radius + collider.center
			point.x = direction.x
			point.z = direction.y
		else:
			var low: Vector3 = collider.low - Vector3.ONE * RADIUS
			var high: Vector3 = collider.high + Vector3.ONE * RADIUS
			if point.x <= low.x or point.x >= high.x or point.y <= low.y or point.y >= high.y or point.z <= low.z or point.z >= high.z: continue
			var distances := [point.x-low.x, high.x-point.x, point.y-low.y, high.y-point.y, point.z-low.z, high.z-point.z]
			var side := distances.find(distances.min())
			match side:
				0: point.x = low.x
				1: point.x = high.x
				2: point.y = low.y
				3: point.y = high.y
				4: point.z = low.z
				5: point.z = high.z
	return point

static func along(path: PackedVector3Array, distance: float) -> Vector3:
	for i in range(1, path.size()):
		var piece := path[i-1].distance_to(path[i])
		if distance <= piece or i == path.size()-1:
			return path[i-1].lerp(path[i], clampf(distance / maxf(piece, 0.000001), 0, 1))
		distance -= piece
	return path[-1]
