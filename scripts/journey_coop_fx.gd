extends Node3D
# 合作反馈特效：绳索极限、受阻与松脱，合作门踏板与开门，救援失足与拉起，拾取。
# 只读模拟状态的变化沿，复用 journey_fx 的冲击环与火花，另建一个青橙能量碎片池。
const SHARD_POOL := 4

var game
var fx
var hazard_fx
var scale_amount := 1.0
var shards: Array[GPUParticles3D] = []
var shard_cursor := 0
var last_rope_status := ""
var next_crackle := 0.0
var gate_state := {}
var last_state := ""
var last_rescue := false

func _init(owner_game, owner_fx, owner_hazard_fx) -> void:
	game = owner_game
	fx = owner_fx
	hazard_fx = owner_hazard_fx
	name = "CoopFx"

func _ready() -> void:
	if OS.has_feature("web") or OS.has_feature("mobile"): scale_amount = 0.5
	for n in range(SHARD_POOL): shards.append(make_shards())

# 能量碎片：加色小亮点，青→橙渐变，四散后快速熄灭。
func make_shards() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.4
	process.spread = 180.0
	process.initial_velocity_min = 2.5
	process.initial_velocity_max = 6.0
	process.gravity = Vector3(0, -4, 0)
	process.damping_min = 2.0
	process.damping_max = 3.0
	process.scale_min = 0.5
	process.scale_max = 1.2
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.1, 1.1, 2.2, 1.0))
	gradient.add_point(0.45, Color(0.2, 0.9, 1.8, 0.9))
	gradient.add_point(0.7, Color(2.0, 0.65, 0.12, 0.8))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.4, 0.35, 0.05, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	var mesh: QuadMesh = fx.billboard(0.3, true)
	(mesh.material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var particles := GPUParticles3D.new()
	particles.amount = maxi(1, int(36 * scale_amount))
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emitting = false
	particles.local_coords = false
	particles.process_material = process
	particles.draw_pass_1 = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 9, 12))
	add_child(particles)
	return particles

func shard_burst(point: Vector3, radius: float = 0.4) -> void:
	var particles := shards[shard_cursor]
	shard_cursor = (shard_cursor + 1) % shards.size()
	(particles.process_material as ParticleProcessMaterial).emission_sphere_radius = radius
	particles.global_position = point
	particles.restart()

static func along(path: Array[Vector3], fraction: float) -> Vector3:
	var total := 0.0
	for n in range(1, path.size()): total += path[n - 1].distance_to(path[n])
	return game_along(path, total * fraction)

static func game_along(path: Array[Vector3], distance: float) -> Vector3:
	for n in range(1, path.size()):
		var piece := path[n - 1].distance_to(path[n])
		if distance <= piece or n == path.size() - 1:
			return path[n - 1].lerp(path[n], clampf(distance / maxf(piece, 0.00001), 0.0, 1.0))
		distance -= piece
	return path[path.size() - 1]

# 每帧由旅程视图调用；path 为当前绳索质点（米）。
func sync(path: Array[Vector3]) -> void:
	var run = game.run
	var state: String = run.state
	if state == "paused":
		return
	sync_rope(run, path, state)
	sync_gates(run)
	sync_rescue(run, state)
	last_state = state

func sync_rope(run, path: Array[Vector3], state: String) -> void:
	if path.size() < 2 or state not in ["running", "rescue"]:
		last_rope_status = ""
		return
	var status: String = run.rope_status()
	var tension: float = run.rope_tension()
	# 拉到极限：绳中段间歇迸火花（约 0.22 秒一次）。
	if status == "taut" and tension > 0.97 and run.elapsed >= next_crackle:
		next_crackle = run.elapsed + 0.22
		fx.burst("spark", along(path, randf_range(0.3, 0.7)))
	# 受阻、松脱、失败：沿绳三处炸出能量碎片。
	if status != last_rope_status and status in ["blocked", "failed"] and last_rope_status != "":
		for f in [0.25, 0.5, 0.75]: shard_burst(along(path, f), 0.3)
	last_rope_status = status

func sync_gates(run) -> void:
	for gate in run.charge_gates:
		if not game.gate_views.has(gate.id): continue
		var view: Node3D = game.gate_views[gate.id]
		if not view.visible: continue
		var before: Dictionary = gate_state.get(gate.id, {})
		var occupied: Array = gate.get("occupied", [false, false]).duplicate()
		var open: bool = gate.open
		if not before.is_empty():
			# 踩上踏板：踏板处一圈青色光波。
			if gate.get("kind", "") == "relay":
				for n in range(2):
					if occupied[n] and not before.occupied[n]:
						var plate: Node3D = view.get_node_or_null(["near", "far"][n])
						if plate: fx.impact(plate.global_position, Color("6fe9ff"), 1.4, 0.0, false)
			# 开门：门洞处冲击环、能量碎片与补光。
			if open and not before.open:
				var door: Node3D = view.get_node_or_null("Door")
				var point: Vector3 = door.global_position if door else view.global_position
				fx.impact(point, Color("ffd27a"), 4.0, 3.0, false)
				shard_burst(point + Vector3(0, 1.5, 0), 1.6)
				shard_burst(point + Vector3(0, 3.0, 0), 1.6)
		gate_state[gate.id] = {"occupied": occupied, "open": open}

func sync_rescue(run, state: String) -> void:
	var rescuing: bool = state == "rescue" and not run.rescue.is_empty()
	if rescuing and not last_rescue:
		# 失足：崖沿掉碎石。
		var role: int = run.rescue.role
		var robot: Node3D = game.robots[role]
		hazard_fx.burst_debris(robot.global_position + Vector3(0, 0.3, 0), Color("5b4c3e"), 0.5)
	if last_rescue and not rescuing and state == "running":
		# 拉起落地：一圈光与尘，被救者身上能量碎片。
		for i in range(2):
			fx.impact(game.robots[i].global_position, Color("9fe8ff") if i == 0 else Color("ffc58a"), 1.8, 1.8, false)
		fx.burst("dust", game.robots[0].global_position)
		fx.burst("dust", game.robots[1].global_position)
		shard_burst(game.robots[0].global_position + Vector3(0, 1.4, 0), 0.6)
		shard_burst(game.robots[1].global_position + Vector3(0, 1.4, 0), 0.6)
	last_rescue = rescuing

# 拾取：原处火花之外，最近的角色身上闪一圈光与碎片。
func pickup(point: Vector3) -> void:
	var nearest: Node3D = game.robots[0]
	if game.robots[1].global_position.distance_to(point) < nearest.global_position.distance_to(point):
		nearest = game.robots[1]
	fx.impact(nearest.global_position, Color("ffe08a"), 1.2, 1.2, false)
	shard_burst(nearest.global_position + Vector3(0, 1.4, 0), 0.5)
