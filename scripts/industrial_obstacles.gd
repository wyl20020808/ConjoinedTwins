extends RefCounted

# 复合障碍的生产与视图共用几何。20 单位为一米；实体不能被护盾穿越。
const KINDS := ["drone", "forklift", "press", "hammer", "collapse", "steam", "shuttle", "piston"]
const TOPS := {"drone": 48.0, "forklift": 92.0, "press": 130.0, "hammer": 136.0, "collapse": 0.0, "steam": 100.0, "shuttle": 70.0, "piston": 130.0}
const WARNING := 1.5
const PRESS_DOWN := 0.45
const PRESS_HOLD := 0.6
const PRESS_UP := 0.7
const PRESS_SAFE := 2.8
# 摆锤是真正的单摆：支点在路面上方 HAMMER_PIVOT 处，摆臂长 HAMMER_LENGTH，
# 在横跨道路的竖直平面里按 θ = HAMMER_ANGLE·sin(2πt/HAMMER_PERIOD + 相位) 不停摆动，没有抬起/放下阶段。
# 最低点锤头底部离地 0.35 米（跳不过），摆到两端时锤头抬到头顶以上，可以从下面钻过。
const HAMMER_PERIOD := 1.8
const HAMMER_LENGTH := 210.0
const HAMMER_PIVOT := 235.0
const HAMMER_ANGLE := 1.12
const HAMMER_HEAD := Vector3(52, 44, 36)
const HAMMER_RATE := HAMMER_ANGLE * TAU / HAMMER_PERIOD
# 新机关采用分段线性往复，转向时刻显式参与连续碰撞分片。
const SHUTTLE_PERIOD := 1.6
const SHUTTLE_REACH := 80.0
const PISTON_PERIOD := 1.8
const STEAM_PRESSURE := 0.4
const STEAM_JET := 0.8
const STEAM_FADE := 0.3
const STEAM_SAFE := 0.65

# 包住任意相位的全部平面分部；仅用于排除完全不相交的查询。
static func motion_envelope(kind:String,rect:Rect2,state:Dictionary)->Rect2:
	match kind:
		"hammer":return rect.grow(HAMMER_LENGTH+HAMMER_HEAD.length()+8.0)
		"shuttle":return rect.grow(SHUTTLE_REACH)
		"press","piston":return rect.grow(16.0)
		"drone":return rect.merge(Rect2(rect.position+state.velocity*5.0,rect.size))
		"forklift":
			var body:=rect.grow(100.0)
			return body.merge(Rect2(body.position+state.velocity*4.0,body.size))
	return rect

static func spec(kind: String, side: float, base: float) -> Dictionary:
	return {"bottom": 0.0, "industrial": true, "start_distance": base,
		"trigger": -1.0, "warning": WARNING, "side": side,
		"velocity": Vector2(side * 35.0, -640.0) if kind == "drone" else Vector2(side * 230.0, 0),
		"warning_evidence": {}, "phase": 0.0, "grace": 2.5, "support_broken": false}

static func hammer_angle(state: Dictionary, time: float) -> float:
	return HAMMER_ANGLE * sin(TAU * time / HAMMER_PERIOD + state.get("phase", 0.0))

# 摆臂上离支点 length 处的点：x 为横向地面坐标，y 为离地高度。
static func hammer_head(pivot: Vector2, angle: float, length: float = HAMMER_LENGTH) -> Vector2:
	return Vector2(pivot.x + length * sin(angle), HAMMER_PIVOT - length * cos(angle))

static func part(name: String, rect: Rect2, bottom: float, top: float, active: bool = true) -> Dictionary:
	return {"name": name, "rect": rect, "bottom": bottom, "top": top, "active": active}

# 在阶段边界分段，避免把激活前接触或压机转折当成整步线性运动。
static func time_cuts(kind: String, state: Dictionary, start: float, end: float) -> Array:
	var cuts: Array = [start, end]
	var trigger: float = state.get("trigger", -1.0)
	if kind in ["shuttle", "piston"]:
		var half_period := (SHUTTLE_PERIOD if kind == "shuttle" else PISTON_PERIOD) * 0.5
		var phase: float = state.get("phase", 0.0)
		for n in range(int(floor((start + phase) / half_period)), int(ceil((end + phase) / half_period)) + 1):
			var turn := n * half_period - phase
			if turn > start and turn < end: cuts.append(turn)
		cuts.sort()
		return cuts
	if trigger < 0 or end <= start: return cuts
	var boundaries: Array = []
	if kind == "collapse":
		boundaries = [trigger + 0.75, trigger + state.grace]
	elif kind == "steam":
		var cycle: float = state.get("period", state.warning + STEAM_PRESSURE + STEAM_JET + STEAM_FADE + STEAM_SAFE)
		var phases := [0.0, state.warning, state.warning + STEAM_PRESSURE,
			state.warning + STEAM_PRESSURE + STEAM_JET, cycle - STEAM_SAFE]
		var origin: float = trigger + state.phase
		for n in range(maxi(0, int(floor((start - origin) / cycle))), maxi(0, int(floor((end - origin) / cycle))) + 1):
			for phase in phases: boundaries.append(origin + n * cycle + phase)
	elif kind == "hammer":
		# 单摆连续运动没有阶段边界；生产扫掠另用角加速度上界补偿弧线。
		pass
	elif kind == "press":
		var cycle: float = state.warning + PRESS_DOWN + PRESS_HOLD + PRESS_UP + PRESS_SAFE
		var phases := [0.0, state.warning, state.warning + PRESS_DOWN,
			state.warning + PRESS_DOWN + PRESS_HOLD, cycle - PRESS_SAFE]
		for n in range(int(floor((start - trigger) / cycle)), int(floor((end - trigger) / cycle)) + 1):
			for phase in phases: boundaries.append(trigger + n * cycle + phase)
	else:
		boundaries = [trigger + state.warning, trigger + state.warning + (5.0 if kind == "drone" else 4.0)]
	for time in boundaries:
		if time > start and time < end and not cuts.has(time): cuts.append(time)
	cuts.sort()
	return cuts

static func sample(kind: String, rect: Rect2, state: Dictionary, time: float) -> Dictionary:
	var trigger: float = state.get("trigger", -1.0)
	var age: float = maxf(0.0, time - trigger) if trigger >= 0 else 0.0
	var warning: bool = trigger >= 0 and age < state.warning
	var flight := clampf(age - state.warning, 0.0, 5.0)
	var parts: Array = []
	var stage := "warning" if warning else "ready"
	var center := rect.get_center()
	if kind == "shuttle":
		var wave := absf(fposmod(time + state.phase, SHUTTLE_PERIOD) / SHUTTLE_PERIOD * 2.0 - 1.0)
		var moving := rect
		moving.position.x += (wave * 2.0 - 1.0) * SHUTTLE_REACH
		parts.append(part("ram", moving, 0, 70))
		parts.append(part("track", Rect2(rect.position - Vector2(SHUTTLE_REACH,0), rect.size + Vector2(SHUTTLE_REACH*2,0)), -3, 0, false))
		stage = "shuttling"
	elif kind == "piston":
		var wave := absf(fposmod(time + state.phase, PISTON_PERIOD) / PISTON_PERIOD * 2.0 - 1.0)
		parts.append(part("plate", rect, wave * 100.0, wave * 100.0 + 24.0))
		parts.append(part("shaft", Rect2(center - Vector2(6,6), Vector2(12,12)), wave * 100.0 + 24.0, 124.0))
		parts.append(part("beam", rect, 124.0, 130.0))
		stage = "cycling"
	elif kind == "hammer":
		# 按绝对时间摆动，远处就能看见它在摆；与玩家何时到达无关。
		var angle := hammer_angle(state, time)
		var head := hammer_head(center, angle)
		parts.append(part("head", Rect2(Vector2(head.x - HAMMER_HEAD.x * 0.5, center.y - HAMMER_HEAD.y * 0.5), Vector2(HAMMER_HEAD.x, HAMMER_HEAD.y)),
			head.y - HAMMER_HEAD.z * 0.5, head.y + HAMMER_HEAD.z * 0.5))
		# 摆臂按三段轴对齐小盒近似，每段盒子包住该段斜杆（含 4 单位粗细）。
		for n in range(3):
			var near := hammer_head(center, angle, HAMMER_LENGTH * (0.25 + n * 0.25))
			var far := hammer_head(center, angle, HAMMER_LENGTH * (0.5 + n * 0.25) - HAMMER_HEAD.z * 0.5 * float(n == 2))
			var low := minf(near.y, far.y) - 4.0
			parts.append(part("rod_%d" % n, Rect2(Vector2(minf(near.x, far.x) - 4.0, center.y - 4.0), Vector2(absf(far.x - near.x) + 8.0, 8.0)), low, maxf(near.y, far.y) + 4.0))
		var bottom: float = parts[0].bottom
		stage = "swing" if bottom < 100.0 else "high"
		warning = bottom < 100.0
		parts[0].angle = angle
	elif kind == "collapse":
		stage = "intact" if trigger < 0 else ("crack" if age < 0.75 else ("grace" if age < state.grace else "collapsed"))
		warning = stage in ["crack", "grace"]
		parts.append(part("floor", rect, -4, 0, false))
	elif kind == "steam":
		var cycle := fposmod(maxf(0, age - state.phase), state.get("period", state.warning + STEAM_PRESSURE + STEAM_JET + STEAM_FADE + STEAM_SAFE))
		stage = "warning"
		var jet_top := 100.0
		if cycle >= state.warning and cycle < state.warning + STEAM_PRESSURE: stage = "pressure"
		elif cycle >= state.warning + STEAM_PRESSURE and cycle < state.warning + STEAM_PRESSURE + STEAM_JET: stage = "jet"
		elif cycle >= state.warning + STEAM_PRESSURE + STEAM_JET and cycle < state.warning + STEAM_PRESSURE + STEAM_JET + STEAM_FADE:
			stage = "fade"
			jet_top *= 1.0 - (cycle - state.warning - STEAM_PRESSURE - STEAM_JET) / STEAM_FADE
		elif cycle >= state.warning + STEAM_PRESSURE + STEAM_JET + STEAM_FADE: stage = "safe"
		if trigger < 0 or age < state.phase: stage = "ready"
		warning = stage in ["warning", "pressure"]
		# 不活动的端点也会参与跨相位扫掠；消退终点必须保持零高度。
		if not stage in ["jet", "fade"]: jet_top = 0.0
		parts.append(part("nozzle", rect, -3, 0, false))
		parts.append(part("jet", rect, 0, jet_top, stage in ["jet", "fade"]))
	elif kind == "drone":
		var moving := rect
		moving.position += state.velocity * flight
		var active: bool = trigger >= 0 and age >= state.warning and age <= state.warning + 5.0
		parts.append(part("drone_body", moving, 18.0, 48.0, active))
		stage = "flight" if active else ("warning" if warning else "spent")
	elif kind == "forklift":
		var offset: Vector2 = state.velocity * clampf(age - state.warning, 0.0, 4.0)
		center += offset
		parts.append(part("vehicle", Rect2(center + Vector2(-30, -24), Vector2(60, 48)), 0.0, 64.0))
		# 货叉与车体、货箱分别检测，两根货叉之间保留真实空隙。
		for n in [-1, 1]:
			parts.append(part("fork_%d" % n, Rect2(center + Vector2(30 if state.side > 0 else -70, n * 15 - 4), Vector2(40, 8)), 4.0, 12.0))
		parts.append(part("load", Rect2(center + Vector2(32 if state.side > 0 else -66, -20), Vector2(34, 40)), 12.0, 92.0))
		stage = "crossing" if age >= state.warning and age < state.warning + 4.0 else ("warning" if warning else "parked")
	elif kind == "press":
		var cycle := fposmod(age, state.warning + PRESS_DOWN + PRESS_HOLD + PRESS_UP + PRESS_SAFE)
		var bottom := 100.0
		if cycle < state.warning:
			stage = "warning"
		elif cycle < state.warning + PRESS_DOWN:
			bottom = lerpf(100, 0, (cycle - state.warning) / PRESS_DOWN)
			stage = "down"
		elif cycle < state.warning + PRESS_DOWN + PRESS_HOLD:
			bottom = 0
			stage = "hold"
		elif cycle < state.warning + PRESS_DOWN + PRESS_HOLD + PRESS_UP:
			bottom = lerpf(0, 100, (cycle - state.warning - PRESS_DOWN - PRESS_HOLD) / PRESS_UP)
			stage = "up"
		else:
			stage = "safe"
		warning = trigger >= 0 and stage == "warning"
		parts.append(part("plate", rect, bottom, bottom + 28.0))
		for n in [-1, 1]:
			parts.append(part("post_%d" % n, Rect2(Vector2(center.x + n * (rect.size.x * 0.5 + 10) - 6, rect.position.y), Vector2(12, rect.size.y)), 0.0, 130.0))
		parts.append(part("beam", Rect2(Vector2(rect.position.x - 16, rect.position.y), Vector2(rect.size.x + 32, rect.size.y)), 110.0, 130.0))
	var bounds: Rect2 = parts[0].rect
	for p in parts: bounds = bounds.merge(p.rect)
	var reach := HAMMER_LENGTH * sin(HAMMER_ANGLE) + HAMMER_HEAD.x * 0.5
	var envelope := Rect2(center - Vector2(reach, HAMMER_HEAD.y * 0.5), Vector2(reach * 2, HAMMER_HEAD.y)) if kind == "hammer" else (Rect2(rect.position - Vector2(SHUTTLE_REACH,0), rect.size + Vector2(SHUTTLE_REACH*2,0)) if kind == "shuttle" else rect)
	return {"rect": bounds, "bottom": 0.0, "top": TOPS[kind], "active": true,
		"warning": warning, "stage": stage, "parts": parts, "launch": rect.get_center(),
		"velocity": state.velocity, "flight": flight, "envelope": envelope,
		"supported": stage != "collapsed", "remaining": maxf(0, state.grace - age) if kind == "collapse" and trigger >= 0 else -1.0}
