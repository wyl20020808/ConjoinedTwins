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
var scale_amount := 1.0

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
func sync_ambient(center: Vector3, forest: float, village: float) -> void:
	var anchor := center + Vector3(0, 3.0, -14.0)
	leaves.global_position = anchor + Vector3(0, 3.0, 0)
	motes.global_position = anchor
	leaves.amount_ratio = clampf(forest, 0.0, 1.0)
	motes.amount_ratio = clampf(0.25 + village * 0.75, 0.0, 1.0)
	leaves.emitting = forest > 0.05
	motes.emitting = true
