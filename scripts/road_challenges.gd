extends RefCounted

# 新内容直接进入三关随机目录。段落只提供地形与机关，证明器仍使用真实双人按键。
const ROUTES := ["ridge_turn", "offset_bridge", "slope_path", "chain_collapse", "steam_corridor", "pressure_bridge",
	"fork_islands", "steps_path", "tilt_path", "ferry_crossing", "winch_bridge", "lift_crossing", "hammer_collapse"]
# 保留目录查询接口；三关引用同一完整目录，不再限制内容所属关卡。
const POOLS := [ROUTES, ROUTES, ROUTES]

static func edges(hazards: Array, center: float, width: float, start: float, length: float) -> void:
	var outer := 360.0
	hazards.append({"kind": "road_gap", "rect": Rect2(-outer, start, outer + center-width*0.5, length)})
	hazards.append({"kind": "road_gap", "rect": Rect2(center+width*0.5, start, outer-center-width*0.5, length)})

static func make_block(kind: String, side: float) -> Dictionary:
	var block := {"route": kind, "lane": 0.0, "hazards": [], "rewards": [], "challenge": true, "side": side}
	var hazards: Array = block.hazards
	if kind in ["pressure_bridge", "winch_bridge"]:
		var gate: Dictionary = preload("res://scripts/road_sync_plates.gd").make_tutorial() if kind == "pressure_bridge" else preload("res://scripts/road_charge_gate.gd").make_tutorial()
		preload("res://scripts/road_charge_gate.gd").relocate(gate, 100.0-gate.receiver.y)
		gate.door = Rect2(-380, 210, 760, 12)
		gate.bridge = true
		gate.winch = kind == "winch_bridge"
		block.gate = gate
		hazards.append({"kind": "road_gap", "rect": Rect2(-360, 230, 720, 200)})
		hazards.append({"kind": "drawbridge", "rect": Rect2(-105, 202, 210, 256), "gate_slot": 0})
		return block
	if kind in ["slope_path", "steps_path", "tilt_path"]:
		var terrain: String = {"slope_path":"slope", "steps_path":"steps", "tilt_path":"tilt"}[kind]
		edges(hazards, 0, 220, 160, 420)
		hazards.append({"kind": terrain, "rect": Rect2(-110, 150, 220, 440), "amplitude": 32.0 if terrain != "steps" else 24.0})
		return block
	if kind in ["ferry_crossing", "lift_crossing"]:
		block.wait_budget=4.0
		hazards.append({"kind":"road_gap", "rect":Rect2(-360,260,720,220)})
		hazards.append({"kind":"ferry" if kind == "ferry_crossing" else "lift", "rect":Rect2(-100,232,200,276), "amplitude":48.0 if kind == "ferry_crossing" else 24.0, "period":3.2, "phase":side*0.5})
		return block
	if kind == "fork_islands":
		edges(hazards,0,220,180,390)
		hazards.append({"kind":"road_gap", "rect":Rect2(-16,210,32,320)})
		return block
	if kind in ["ridge_turn", "offset_bridge"]:
		for n in range(6):
			var center := side * (sin(float(n)/5*TAU)*55.0 if kind == "ridge_turn" else (30.0 if n%2==0 else -30.0))
			edges(hazards,center,230,170+n*65,65)
		return block
	if kind == "hammer_collapse":
		edges(hazards,0,190,430,290)
		hazards.append({"kind":"hammer", "rect":Rect2(side*60-6,210,12,12), "side":side, "phase":PI*0.5})
		for n in range(2): hazards.append({"kind":"collapse", "rect":Rect2(-95,490+n*105,190,88), "side":side, "chain":true})
		return block
	if kind == "chain_collapse":
		edges(hazards,0,190,180,430)
		for n in range(3):
			hazards.append({"kind":"collapse", "rect":Rect2(-95,280+n*100,190,88), "side":side, "chain":true})
		return block
	if kind == "steam_corridor":
		edges(hazards,0,270,140,600)
		# 三排交错喷口，身体必须改道或等待；中间安全岛保留观察与换位空间。
		for n in range(3):
			hazards.append({"kind":"steam", "rect":Rect2(-135 if n%2==0 else 10,190+n*230,125,32), "side":side, "encounter":true, "phase":0.0, "warning":0.75, "period":2.6})
		return block
	return block

static func route_input(run, block: Dictionary, base: float) -> Array:
	var kind: String = block.route
	var d: float = run.distance-base
	var centers := [0.0, 0.0]
	var width := 25.0
	var positions := [run.a.position, run.b.position]
	var jumps := [false,false]
	var rear_y:float=minf(run.a.position.y,run.b.position.y)-base
	if not run.rope.physical.is_empty():
		for point:Vector3 in run.rope.physical.points: rear_y=minf(rear_y,point.z-base)
	for role in range(2):
		var point: Vector2 = positions[role]
		var local_y: float = point.y-base
		if kind == "fork_islands" and local_y > 80 and local_y < 590:
			centers[role] = -32.0 if role == 0 else 32.0
		if kind in ["ridge_turn", "offset_bridge"] and local_y > 80 and local_y < 590:
			var n := clampi(int((local_y+55.0-170)/65),0,5)
			centers[role] = block.side * (sin(float(n)/5*TAU)*55.0 if kind == "ridge_turn" else (30.0 if n%2==0 else -30.0))
		if kind == "hammer_collapse" and local_y < 280 and local_y >= 0:
			centers[role] = -block.side*160.0
		if kind == "ferry_crossing":
			for i in range(run.kinds.size()):
				if run.kinds[i] == "ferry" and absf(run.obstacles[i].position.y-base-232)<1 and local_y>120 and local_y<550:
					centers[role] = run.terrain_sample(i,run.elapsed,point).rect.get_center().x
		if kind == "steam_corridor" and local_y>30 and local_y<738:
			# 下一排用共同横移通过；跨排保留完整的身体与绳段宽度。
			var row := 0
			if rear_y > 190+32+2: row = 1
			if rear_y > 420+32+2: row = 2
			centers[role] = 55.0 if row%2==0 else -55.0
	var inputs: Array = []
	for role in range(2):
		var target := Vector2(centers[role]+(-width if role==0 else width),run.distance)
		var error: Vector2 = target-positions[role]
		if d<650: error.y=0
		inputs.append(run.Templates.keyboard_direction(error))
	return [inputs[0],inputs[1],jumps[0],jumps[1]]
