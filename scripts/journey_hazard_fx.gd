extends Node3D
# 机关特效：只读每个可见机关的模拟采样（阶段、位置、高度），在阶段切换时触发一次性特效，
# 运动中的机关挂持续拖尾。不改任何判定、碰撞或时序。网页与移动端数量减半、不建拖尾灯。
# 一次性特效与拖尾都用固定容量对象池；离开显示窗口的机关立即归还拖尾。
const DEBRIS_POOL := 6
const STEAM_POOL := 4
const TRAIL_POOL := 8

var game
var fx
var scale_amount := 1.0
var debris: Array[GPUParticles3D] = []
var steam: Array[GPUParticles3D] = []
var debris_cursor := 0
var trails: Array[GPUParticles3D] = []
var trail_owner: Array[int] = []
var jets: Array[GPUParticles3D] = []
var jet_owner: Array[int] = []
var last_stage := {}
var last_seen := {}
var last_position := {}

func _init(owner_game, owner_fx) -> void:
	game = owner_game
	fx = owner_fx
	name = "HazardFx"

func _ready() -> void:
	if OS.has_feature("web") or OS.has_feature("mobile"): scale_amount = 0.5
	for n in range(DEBRIS_POOL): debris.append(make_debris())
	for n in range(STEAM_POOL):
		jets.append(make_steam_jet()); jet_owner.append(-1)
	for n in range(TRAIL_POOL):
		trails.append(make_trail()); trail_owner.append(-1)

# —— 发射器 ——

func emitter(amount: int, lifetime: float, process: ParticleProcessMaterial, mesh: Mesh, one_shot: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = maxi(1, int(amount * scale_amount))
	particles.lifetime = lifetime
	particles.one_shot = one_shot
	particles.explosiveness = 0.9 if one_shot else 0.0
	particles.emitting = false
	particles.local_coords = false
	particles.process_material = process
	particles.draw_pass_1 = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 12, 16))
	add_child(particles)
	return particles

func ramp(colors: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, colors[0])
	gradient.set_color(1, colors[colors.size() - 1])
	for n in range(1, colors.size() - 1):
		gradient.add_point(float(n) / (colors.size() - 1), colors[n])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

func curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points: c.add_point(p)
	var texture := CurveTexture.new()
	texture.curve = c
	return texture

# 碎石：受光照的小石块，高抛落地。
func make_debris() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.6
	process.direction = Vector3(0, 1, 0)
	process.spread = 60.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 7.5
	process.gravity = Vector3(0, -18, 0)
	process.angular_velocity_min = -360.0
	process.angular_velocity_max = 360.0
	process.scale_min = 0.5
	process.scale_max = 1.4
	process.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	var rock := BoxMesh.new()
	rock.size = Vector3(0.16, 0.12, 0.14)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("6f6254")
	mat.roughness = 0.95
	rock.material = mat
	return emitter(16, 0.9, process, rock, true)

# 蒸汽柱：持续喷射的白色软团，向上加速、扩散变淡。
func make_steam_jet() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.9, 0.1, 0.5)
	process.direction = Vector3(0, 1, 0)
	process.spread = 8.0
	process.initial_velocity_min = 9.0
	process.initial_velocity_max = 13.0
	process.gravity = Vector3(0, 2.0, 0)
	process.damping_min = 2.5
	process.damping_max = 3.5
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.4
	process.turbulence_noise_scale = 3.0
	process.scale_min = 0.8
	process.scale_max = 1.3
	process.scale_curve = curve([Vector2(0, 0.5), Vector2(1, 2.8)])
	process.color_ramp = ramp([Color(1, 1, 1, 0.0), Color(1.15, 1.15, 1.2, 0.85), Color(1.0, 1.0, 1.05, 0.45), Color(0.95, 0.96, 1.0, 0.0)])
	var mesh: QuadMesh = fx.billboard(1.7, true)
	var particles := emitter(130, 1.25, process, mesh, false)
	particles.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 16, 8))
	return particles

# 拖尾：滚石/木桶扬尘或火焰弩火舌，按机关类型切换颜色与形态。
func make_trail() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.5
	process.direction = Vector3(0, 1, 0)
	process.spread = 70.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 1.4
	process.gravity = Vector3(0, 0.6, 0)
	process.damping_min = 1.5
	process.damping_max = 2.5
	process.scale_curve = curve([Vector2(0, 0.6), Vector2(1, 2.2)])
	var particles := emitter(64, 1.0, process, fx.billboard(1.4, false), false)
	particles.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 8, 12))
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.omni_range = 5.0
	light.shadow_enabled = false
	light.light_color = Color("ff8a3a")
	light.visible = false
	particles.add_child(light)
	return particles

func style_trail(particles: GPUParticles3D, kind: String) -> void:
	var process := particles.process_material as ParticleProcessMaterial
	var mesh := particles.draw_pass_1 as QuadMesh
	var fire := kind == "rocket"
	process.color_ramp = ramp([Color(1.6, 1.0, 0.45, 0.95), Color(1.3, 0.42, 0.12, 0.7), Color(0.25, 0.22, 0.2, 0.0)]) if fire \
		else ramp([Color(0.66, 0.58, 0.46, 0.0), Color(0.66, 0.58, 0.46, 0.7), Color(0.58, 0.52, 0.44, 0.0)])
	(mesh.material as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if fire else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	(mesh.material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD if fire else BaseMaterial3D.BLEND_MODE_MIX
	process.gravity = Vector3(0, 2.5, 0) if fire else Vector3(0, 0.6, 0)
	particles.lifetime = 0.45 if fire else 1.0
	var glow: OmniLight3D = particles.get_node("Glow")
	glow.visible = fire and scale_amount >= 1.0
	glow.light_energy = 2.4

# —— 一次性特效 ——

# reach：从中心向四周的发射半径（米）。压机这类大块头要从边缘喷出，否则碎石被本体挡住。
func burst_debris(point: Vector3, color: Color = Color("6f6254"), reach: float = 0.6) -> void:
	var particles := debris[debris_cursor]
	debris_cursor = (debris_cursor + 1) % debris.size()
	((particles.draw_pass_1 as BoxMesh).material as StandardMaterial3D).albedo_color = color
	var process := particles.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = maxf(0.6, reach)
	process.emission_ring_inner_radius = maxf(0.3, reach * 0.8)
	process.emission_ring_height = 0.1
	particles.global_position = point
	particles.restart()

# 砸地：冲击环 + 四周碎石 + 尘爆 + 短促补光。
func slam(point: Vector3, radius: float) -> void:
	fx.impact(point, Color("ffd7a0"), radius, 2.2, false)
	burst_debris(point + Vector3(0, 0.2, 0), Color("6f6254"), radius * 0.55)
	for corner in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
		fx.burst("dust", point + corner * radius * 0.4 + Vector3(0, 0.1, 0))

# —— 每帧 ——

func track(index: int, kind: String, sample: Dictionary, view: Node3D) -> void:
	if view == null or not view.visible: return
	last_seen[index] = Engine.get_process_frames()
	var stage: String = sample.get("stage", "")
	var before: String = last_stage.get(index, stage)
	last_stage[index] = stage
	var base: Vector3 = view.global_position
	var rect: Rect2 = sample.get("rect", Rect2())
	var size := maxf(rect.size.x, rect.size.y) / 20.0
	if stage != before:
		match kind:
			"press":
				if stage == "hold":
					slam(base, maxf(2.2, size * 0.8))
					cue("metal_heavy", base, -1.0, 0.8)
			"active_spikes":
				if stage == "extend":
					burst_debris(base + Vector3(0, 0.15, 0), Color("5b4a3a"))
					fx.burst("spark", base + Vector3(0, 0.5, 0))
					cue("metal_light", base, -4.0, 1.0)
			"collapse":
				if stage == "crack":
					burst_debris(base + Vector3(0, 0.1, 0), Color("4d4136"))
					cue("creak", base, -4.0, 0.9)
				elif stage == "collapsed":
					burst_debris(base, Color("4d4136"))
					fx.burst("dust", base)
					fx.impact(base, Color("c9b08a"), maxf(2.0, size * 0.6), 0.0, false)
					cue("rubble", base, 0.0, 0.85)
			"hammer":
				if stage == "swing":
					fx.burst("dust", base + Vector3(0, 0.1, 0))
					cue("whoosh", base, -6.0, 0.75)
			"steam":
				if stage == "pressure":
					fx.burst("dust", base + Vector3(0, 0.1, 0))
					cue("whoosh", base, -9.0, 1.35)
	# 持续：蒸汽柱。原有喷流块的材质每帧由机关同步重设，这里每帧隐藏，改由粒子表现；碰撞与采样不变。
	if kind == "steam":
		var jet := view.get_node_or_null("jet")
		if jet: jet.visible = false
		var on := stage in ["jet", "fade"]
		var slot := jet_owner.find(index)
		if on and slot < 0:
			slot = jet_owner.find(-1)
			if slot >= 0: jet_owner[slot] = index
		if slot >= 0:
			jets[slot].global_position = base + Vector3(0, 0.3, 0)
			var box := Vector3(rect.size.x / 40.0, 0.1, rect.size.y / 40.0)
			(jets[slot].process_material as ParticleProcessMaterial).emission_box_extents = box
			jets[slot].emitting = stage == "jet"
			if not on: jet_owner[slot] = -1
	# 持续：滚动/飞行拖尾。
	var moving: bool = kind == "rocket" or kind == "barrel" or kind.begins_with("fly_") or game.run.Threats.is_ball(kind)
	if moving:
		# 按真实位移判断：预警阶段采样也标为 active，但球还停着，不该扬尘。
		var previous: Vector3 = last_position.get(index, base)
		last_position[index] = base
		var active: bool = previous.distance_to(base) > 0.02 and stage not in ["tripped", "spent"]
		var slot := trail_owner.find(index)
		if active and slot < 0:
			slot = trail_owner.find(-1)
			if slot >= 0:
				trail_owner[slot] = index
				style_trail(trails[slot], kind)
		if slot >= 0:
			var lift: float = 0.35 if kind != "rocket" else (float(sample.get("bottom", 0.0)) + float(sample.get("top", 40.0))) / 40.0
			trails[slot].global_position = base + Vector3(0, lift, 0)
			trails[slot].emitting = active
			if not active:
				trail_owner[slot] = -1
				if kind == "rocket" and before in ["active", "flight"]:
					fx.impact(base, Color("ff7a2a"), 1.8, 3.0)
					fx.burst("spark", base + Vector3(0, 0.5, 0))
					cue("plate_heavy", base, -4.0, 1.0)

# 机关阶段切换时在机关位置发声：玩家看不到预警标记，也能靠方位听出危险。
func cue(name: String, point: Vector3, volume_db: float, pitch: float) -> void:
	var sfx = game.get("sfx")
	if sfx != null and sfx.has_method("play_at"): sfx.play_at(name, point, volume_db, pitch)

# 未在本帧出现的机关（离开窗口或被释放）归还持续特效。
func release_missing() -> void:
	var frame := Engine.get_process_frames()
	for pool in [[trails, trail_owner], [jets, jet_owner]]:
		var owners: Array = pool[1]
		for slot in range(owners.size()):
			if owners[slot] >= 0 and last_seen.get(owners[slot], -1) != frame:
				pool[0][slot].emitting = false
				var glow = pool[0][slot].get_node_or_null("Glow")
				if glow: glow.visible = false
				owners[slot] = -1
	if last_stage.size() > 256:
		last_position.clear()
		for index in last_stage.keys():
			if last_seen.get(index, -1) != frame:
				last_stage.erase(index); last_seen.erase(index)
