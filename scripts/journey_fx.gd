extends Node3D
# 纯表现层粒子：只读取模拟结果（位置、跳跃高度、命中时间），不改变任何玩法状态。
# 一次性特效用固定容量对象池轮换；持续特效（奔跑扬尘、环境粒子）常驻并只切换发射。
# GPU 粒子在 Forward+ 与 Compatibility（网页）均可用；网页与移动端数量减半。
const POOL := 6
var pools := {}
var cursor := {}
var run_dust: Array[GPUParticles3D] = []
var last_heights := [0.0, 0.0]
var last_feet := [Vector3.ZERO, Vector3.ZERO]
var leaves: GPUParticles3D
var motes: GPUParticles3D
var embers: GPUParticles3D
var scale_amount := 1.0
var fireflies: GPUParticles3D
var mist: GPUParticles3D
var pollen: GPUParticles3D
# 冲击波环与瞬时闪光：固定容量轮换，逐帧推进；只表现，不读写玩法状态。
const RING_POOL := 6
const FLASH_POOL := 3
var rings: Array[MeshInstance3D] = []
var ring_state: Array = []
var flashes: Array[OmniLight3D] = []
var flash_state: Array = []
var ring_cursor := 0
var flash_cursor := 0

func _ready() -> void:
	name = "JourneyFx"
	if OS.has_feature("web") or OS.has_feature("mobile"): scale_amount = 0.5
	pools["spark"] = []
	pools["dust"] = []
	for n in range(POOL):
		pools.spark.append(make_spark())
		pools.dust.append(make_dust(18, 0.75, Color(0.62, 0.54, 0.42, 0.55)))
	cursor = {"spark": 0, "dust": 0}
	for i in range(2):
		var dust := make_dust(10, 0.55, Color(0.66, 0.58, 0.46, 0.35))
		dust.one_shot = false
		dust.emitting = false
		(dust.process_material as ParticleProcessMaterial).initial_velocity_min = 0.4
		(dust.process_material as ParticleProcessMaterial).initial_velocity_max = 1.1
		run_dust.append(dust)
	leaves = make_leaves()
	motes = make_motes()
	embers = make_embers()
	fireflies = make_fireflies()
	mist = make_mist()
	pollen = make_pollen()
	for n in range(RING_POOL):
		var ring := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		ring.mesh = plane
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://scripts/journey_shockwave.gdshader")
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = false
		add_child(ring)
		rings.append(ring)
		ring_state.append({"age": 1.0, "life": 0.4})
	# 网页与移动端不建闪光灯，避免额外的动态光。
	if scale_amount >= 1.0:
		for n in range(FLASH_POOL):
			var light := OmniLight3D.new()
			light.shadow_enabled = false
			light.omni_range = 6.0
			light.light_volumetric_fog_energy = 1.0
			light.visible = false
			add_child(light)
			flashes.append(light)
			flash_state.append({"age": 1.0, "life": 0.25, "energy": 0.0})

# 柔边圆点贴图，所有粒子共用。
static func dot_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	return texture

func billboard(size: float, unshaded: bool) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = dot_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.disable_receive_shadows = true
	quad.material = mat
	return quad

func fade_ramp(color: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp

func emitter(amount: int, lifetime: float, process: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = maxi(1, int(amount * scale_amount))
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.emitting = false
	particles.process_material = process
	particles.draw_pass_1 = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))
	add_child(particles)
	return particles

# 命中火花：短促、明亮、向外迸射。
func make_spark() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 75.0
	process.initial_velocity_min = 4.0
	process.initial_velocity_max = 8.0
	process.gravity = Vector3(0, -14, 0)
	process.scale_min = 0.5
	process.scale_max = 1.0
	process.color_ramp = fade_ramp(Color(1.0, 0.86, 0.5, 1.0))
	return emitter(14, 0.32, process, billboard(0.16, true))

# 尘土：落地、倒地与奔跑共用，缓慢扩散并变淡。
func make_dust(amount: int, lifetime: float, color: Color) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.45
	process.emission_ring_inner_radius = 0.1
	process.emission_ring_height = 0.05
	process.direction = Vector3(0, 0.35, 0)
	process.spread = 80.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 2.4
	process.gravity = Vector3(0, 0.6, 0)
	process.damping_min = 2.5
	process.damping_max = 3.5
	process.scale_min = 0.8
	process.scale_max = 1.5
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.6))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	process.color_ramp = fade_ramp(color)
	return emitter(amount, lifetime, process, billboard(0.7, false))

# 森林落叶：在镜头前方的箱体内缓慢飘落、左右摆动。
func make_leaves() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(22, 4, 26)
	process.direction = Vector3(0.3, -1, 0.2)
	process.spread = 25.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.3
	process.gravity = Vector3(0, -0.35, 0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.6
	process.turbulence_noise_scale = 6.0
	process.angle_min = 0.0
	process.angle_max = 360.0
	process.angular_velocity_min = -90.0
	process.angular_velocity_max = 90.0
	process.scale_min = 0.6
	process.scale_max = 1.2
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.55, 0.62, 0.25, 0.0))
	gradient.add_point(0.15, Color(0.62, 0.55, 0.22, 0.9))
	gradient.add_point(0.85, Color(0.72, 0.45, 0.18, 0.9))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.7, 0.4, 0.15, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	var leaf := billboard(0.38, false)
	(leaf.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var particles := emitter(70, 7.0, process, leaf)
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.preprocess = 7.0
	particles.visibility_aabb = AABB(Vector3(-30, -12, -34), Vector3(60, 24, 68))
	return particles

# 村庄与原野的浮尘/花粉：细小亮点在阳光里漂浮。
func make_motes() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(22, 3, 26)
	process.direction = Vector3(0, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.25
	process.gravity = Vector3.ZERO
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.8
	process.turbulence_noise_scale = 4.0
	process.scale_min = 0.4
	process.scale_max = 1.0
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.92, 0.7, 0.0))
	gradient.add_point(0.5, Color(1.0, 0.92, 0.7, 0.75))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 0.92, 0.7, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	var particles := emitter(110, 6.0, process, billboard(0.13, true))
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.preprocess = 6.0
	particles.visibility_aabb = AABB(Vector3(-30, -8, -34), Vector3(60, 16, 68))
	return particles

# 矿道余烬：细小暖色火星缓慢上飘，给第三章一点空气感。
func make_embers() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(18, 3, 24)
	process.direction = Vector3(0, 1, 0)
	process.spread = 24.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.75
	process.gravity = Vector3(0, 0.25, 0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.8
	process.turbulence_noise_scale = 5.0
	process.scale_min = 0.3
	process.scale_max = 0.8
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.55, 0.2, 0.0))
	gradient.add_point(0.25, Color(1.0, 0.62, 0.28, 0.85))
	gradient.add_point(0.8, Color(1.0, 0.28, 0.10, 0.7))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 0.2, 0.06, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	var particles := emitter(46, 5.0, process, billboard(0.09, true))
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.preprocess = 5.0
	particles.visibility_aabb = AABB(Vector3(-26, -8, -30), Vector3(52, 18, 60))
	return particles

# 冲击：贴地扩散环 + 火花 + 瞬时补光。radius 为环的最终半径（米）。
func impact(point: Vector3, color: Color, radius: float, light_energy: float, sparks: bool = true) -> void:
	var ring := rings[ring_cursor]
	ring_cursor = (ring_cursor + 1) % rings.size()
	ring.global_position = Vector3(point.x, point.y + 0.06, point.z)
	ring.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	(ring.material_override as ShaderMaterial).set_shader_parameter("tint", color)
	(ring.material_override as ShaderMaterial).set_shader_parameter("progress", 0.0)
	ring.visible = true
	ring_state[rings.find(ring)] = {"age": 0.0, "life": 0.42}
	if sparks: burst("spark", point + Vector3(0, 0.8, 0))
	if flashes.is_empty(): return
	var light := flashes[flash_cursor]
	flash_state[flash_cursor] = {"age": 0.0, "life": 0.22, "energy": light_energy}
	flash_cursor = (flash_cursor + 1) % flashes.size()
	light.global_position = point + Vector3(0, 1.2, 0)
	light.light_color = color
	light.light_energy = light_energy
	light.visible = true

func _process(delta: float) -> void:
	for n in range(rings.size()):
		if not rings[n].visible: continue
		var state: Dictionary = ring_state[n]
		state.age += delta
		var progress: float = state.age / state.life
		if progress >= 1.0:
			rings[n].visible = false
			continue
		(rings[n].material_override as ShaderMaterial).set_shader_parameter("progress", 1.0 - pow(1.0 - progress, 2.2))
	for n in range(flashes.size()):
		if not flashes[n].visible: continue
		var state: Dictionary = flash_state[n]
		state.age += delta
		var left: float = 1.0 - state.age / state.life
		if left <= 0.0:
			flashes[n].visible = false
			continue
		flashes[n].light_energy = state.energy * left * left

# 黄昏萤火虫：路边低空的黄绿色光点，缓慢游走、明灭闪烁。
func make_fireflies() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(26, 1.4, 30)
	process.direction = Vector3(0, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.4
	process.gravity = Vector3.ZERO
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.2
	process.turbulence_noise_scale = 3.0
	process.scale_min = 0.6
	process.scale_max = 1.0
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.75, 1.25, 0.12, 0.0))
	for n in range(1, 6):
		gradient.add_point(n / 6.0, Color(0.75, 1.25, 0.12, 0.95 if n % 2 == 1 else 0.15))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.75, 1.25, 0.12, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	var dot := billboard(0.3, true)
	(dot.material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var particles := emitter(150, 6.0, process, dot)
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.preprocess = 6.0
	particles.visibility_aabb = AABB(Vector3(-32, -6, -36), Vector3(64, 14, 72))
	return particles

# 夜间贴地薄雾：大而淡的雾团贴着路面缓慢横移。
func make_mist() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(30, 0.3, 34)
	process.direction = Vector3(1, 0, 0.2)
	process.spread = 30.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 0.8
	process.gravity = Vector3.ZERO
	process.scale_min = 0.8
	process.scale_max = 1.4
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.55, 0.62, 0.8, 0.0))
	gradient.add_point(0.5, Color(0.55, 0.62, 0.8, 0.09))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.55, 0.62, 0.8, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	var particles := emitter(70, 9.0, process, billboard(9.0, false))
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.preprocess = 9.0
	particles.visibility_aabb = AABB(Vector3(-34, -4, -38), Vector3(68, 10, 76))
	return particles

# 清晨林间花粉：比村庄浮尘更大更稀，受光时在光柱里发亮。
func make_pollen() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(22, 5, 26)
	process.direction = Vector3(0.2, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.2
	process.gravity = Vector3(0, -0.05, 0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.turbulence_noise_scale = 5.0
	process.scale_min = 0.5
	process.scale_max = 1.1
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.4, 1.3, 0.9, 0.0))
	gradient.add_point(0.5, Color(1.4, 1.3, 0.9, 0.7))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.4, 1.3, 0.9, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	var mote := billboard(0.2, true)
	(mote.material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var particles := emitter(120, 8.0, process, mote)
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.preprocess = 8.0
	particles.visibility_aabb = AABB(Vector3(-30, -8, -34), Vector3(60, 18, 68))
	return particles

# 按章节时段开关：0 清晨林间花粉，1 黄昏萤火虫，2 夜间贴地薄雾。
func sync_time_of_day(center: Vector3, chapter: int, forest: float) -> void:
	var anchor := center + Vector3(0, 0, -14.0)
	fireflies.global_position = anchor + Vector3(0, 1.3, 0)
	mist.global_position = anchor + Vector3(0, 0.4, 0)
	pollen.global_position = anchor + Vector3(0, 4.0, 0)
	fireflies.emitting = chapter == 1
	mist.emitting = false
	pollen.emitting = chapter == 0 and forest > 0.2
	pollen.amount_ratio = clampf(forest, 0.0, 1.0)

func burst(kind: String, point: Vector3) -> void:
	var list: Array = pools[kind]
	var particles: GPUParticles3D = list[cursor[kind]]
	cursor[kind] = (cursor[kind] + 1) % list.size()
	particles.global_position = point
	particles.restart()

# 每帧由旅程视图调用：脚位为角色地面点（米），height 为模拟跳跃高度（道路单位）。
func sync_player(i: int, feet: Vector3, height: float, grounded_allowed: bool, delta: float) -> void:
	var landed: bool = last_heights[i] > 8.0 and height <= 0.5
	if landed and grounded_allowed: burst("dust", feet)
	var speed := 0.0
	if delta > 0.0: speed = Vector2(feet.x - last_feet[i].x, feet.z - last_feet[i].z).length() / delta
	var dust := run_dust[i]
	dust.global_position = feet
	dust.emitting = grounded_allowed and height <= 0.5 and speed > 2.5 and speed < 40.0
	last_heights[i] = height
	last_feet[i] = feet

# 环境粒子跟随两人中点前方；forest 为林地权重，village 为村庄/原野权重。
func sync_ambient(center: Vector3, forest: float, village: float, mine: float = 0.0) -> void:
	var anchor := center + Vector3(0, 3.0, -14.0)
	leaves.global_position = anchor + Vector3(0, 3.0, 0)
	motes.global_position = anchor
	embers.global_position = anchor + Vector3(0, 1.5, 0)
	leaves.amount_ratio = clampf(forest, 0.0, 1.0)
	motes.amount_ratio = clampf(0.25 + village * 0.75, 0.0, 1.0)
	embers.amount_ratio = clampf(mine, 0.0, 1.0)
	leaves.emitting = forest > 0.05
	motes.emitting = true
	embers.emitting = mine > 0.02
