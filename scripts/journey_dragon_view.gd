extends RefCounted
# 「烬翼魔龙」的画面：模型、飞行姿态与动作、吐息火焰、甩尾冲击环、火雨与熔岩池、起飞横掠火线、
# 绞盘踏板与锁链、三阶段火墙、胸口熔岩核、血条与电影式入场运镜。
# 全部只读模拟状态（run.elapsed 与 Boss 事件字段），不写回模拟；一次性特效按“状态 + 技能序号”去重。

const Dragon = preload("res://scripts/journey_dragon.gd")
const BossView = preload("res://scripts/journey_boss_view.gd")
const TELEGRAPH = preload("res://scripts/boss_telegraph.gdshader")
const BODY := "res://assets/boss/rigged/fire_dragon.glb"
const WINCH := "res://assets/boss/chain_winch.glb"
const METEOR := "res://assets/boss/meteor.glb"
const NEST := "res://assets/boss/dragon_nest.glb"
const PATHS := [BODY, WINCH, METEOR, NEST]
const SCALE := 20.0
# 原模型最长边约 1（头到尾 0.98、翼展 0.98、高 0.63），放大 26 倍：身长约 25 米、站高约 16 米。
const SIZE := 26.0
# 飞行时绕身体中部（离地约 7 米）俯仰与侧倾，而不是绕脚底。
const PIVOT := 7.0
# 半直立的站姿在空中前倾成水平飞行。
const FLY_PITCH := 0.85
const CROSSFADE := 0.25
const HEAD_LENGTH := 0.15
const EMBER := Color("ff6a1a")
const LAVA := Color("ffb347")
const DANGER := Color("ff4a1a")
const TOXIC := Color("ffcf4a")
const MAX_POOLS := 16
const CHAIN_LINKS := 48

static func world(point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x/SCALE, height, -point.y/SCALE)

static func local(event: Dictionary, point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x/SCALE, height, -(point.y-event.y)/SCALE)

static func has_asset(path: String) -> bool:
	return ResourceLoader.exists(path)

# —— 构建 ——

static func build(game, root: Node3D, event: Dictionary) -> void:
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var dragon := Node3D.new()
	dragon.name = "Dragon"
	body.add_child(dragon)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, PIVOT, 0)
	dragon.add_child(pivot)
	var model: Node3D = load(BODY).instantiate()
	model.name = "Figure"
	model.scale = Vector3.ONE*SIZE
	model.position = Vector3(0, -PIVOT, 0)
	pivot.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player: AnimationPlayer = players[0]
		player.speed_scale = 0.0
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		dragon.set_meta("anim", player)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty(): dragon.set_meta("skeleton", skeletons[0])
	var parts: Array = []
	BossView.meshes(model, parts)
	dragon.set_meta("meshes", parts)
	# 胸口熔岩核：平时只有暗红补光随呼吸起伏；被锁链拽倒时放大变亮、暴露弱点。
	var core := MeshInstance3D.new()
	core.name = "Core"
	var sphere := SphereMesh.new()
	sphere.radius = 1.3
	sphere.height = 2.6
	core.mesh = sphere
	core.material_override = game.material("dragon_core", LAVA, 5.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var core_light := OmniLight3D.new()
	core_light.name = "CoreLight"
	core_light.light_color = EMBER
	core_light.omni_range = 18.0
	root.add_child(core_light)
	var marks := Node3D.new()
	marks.name = "Telegraphs"
	root.add_child(marks)
	telegraph(marks, "Sector", 2, DANGER)
	telegraph(marks, "Band", 0, DANGER)
	for n in range(8): telegraph(marks, "Circle%d"%n, 1, TOXIC)
	telegraph(marks, "Spit", 1, DANGER)
	telegraph(marks, "Warn", 1, DANGER)
	for name in ["Ring0", "Ring1", "Nova"]: root.add_child(ring(game, name))
	root.add_child(flame("Flame", 260, 1.1))
	root.add_child(scorch("Scorch"))
	root.add_child(scorch("Trail"))
	# 朝天火柱：比吐息慢、粗，从嘴里直接翻涌而上。
	var sky := flame("SkyFlame", 220, 1.3)
	sky.draw_pass_1 = additive(null, 4.4)
	var sky_process: ParticleProcessMaterial = sky.process_material
	sky_process.initial_velocity_min = 26.0
	sky_process.initial_velocity_max = 34.0
	sky_process.damping_min = 4.0
	sky_process.damping_max = 7.0
	sky_process.spread = 11.0
	sky_process.scale_curve = grow_curve(0.7, 3.0)
	root.add_child(sky)
	for n in range(8):
		var rock := prop(game, root, METEOR, Vector3.ONE*2.6)
		rock.name = "Meteor%d"%n
		rock.add_child(trail_fire())
		rock.hide()
	var spit := prop(game, root, METEOR, Vector3.ONE*1.6)
	spit.name = "Fireball"
	spit.add_child(trail_fire())
	spit.hide()
	var pools := Node3D.new()
	pools.name = "Pools"
	root.add_child(pools)
	for n in range(MAX_POOLS): pools.add_child(lava_pool(n))
	# 绞盘踏板、两侧绞盘与锁链。
	for n in range(Dragon.PLATES.size()):
		var plate := MeshInstance3D.new()
		plate.name = "Plate%d"%n
		var disc := CylinderMesh.new()
		disc.top_radius = Dragon.PLATE_HALF/SCALE
		disc.bottom_radius = Dragon.PLATE_HALF/SCALE*1.08
		disc.height = 0.22
		disc.radial_segments = 32
		plate.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("3b3430")
		mat.emission_enabled = true
		mat.emission = LAVA
		mat.roughness = 0.6
		plate.material_override = mat
		plate.position = local(event, Dragon.plate_center(event, n), 0.08)
		root.add_child(plate)
		var glow := OmniLight3D.new()
		glow.name = "Glow"
		glow.light_color = LAVA
		glow.omni_range = 5.0
		glow.position = Vector3(0, 0.8, 0)
		plate.add_child(glow)
	for side in [-1.0, 1.0]:
		var winch := prop(game, root, WINCH, Vector3(4.2, 4.0, 4.2))
		winch.name = "Winch%d"%(0 if side < 0 else 1)
		winch.position = local(event, Vector2(side*Dragon.WINCH_X, event.arena+Dragon.WINCH_Y))
		winch.rotation.y = -side*PI/2
		root.add_child(chain("Chain%d"%(0 if side < 0 else 1)))
	# 三阶段两侧火墙，开战时入口燃起的火线。
	for side in [-1.0, 1.0]: root.add_child(wall_fire("Wall%d"%(0 if side < 0 else 1), event, side))
	root.add_child(entry_fire(event))
	var nest := prop(game, root, NEST, Vector3(18.0, 3.2, 16.0))
	nest.name = "Nest"
	nest.position = local(event, (event.perch as Vector2)+Vector2(0, 80))
	var nest_light := OmniLight3D.new()
	nest_light.light_color = EMBER
	nest_light.omni_range = 16.0
	nest_light.light_energy = 1.4
	nest_light.position = Vector3(0, 2.0, 0)
	nest.add_child(nest_light)
	BossView.build_bar(root)
	BossView.build_cinema(root)
	var cinema: CanvasLayer = root.get_node("Cinema")
	(cinema.get_node("Name") as Label).text = Dragon.NAME
	(cinema.get_node("Epithet") as Label).text = Dragon.EPITHET
	root.add_child(BossView.build_soil())

static func telegraph(parent: Node3D, name: String, shape: int, color: Color) -> MeshInstance3D:
	return BossView.telegraph(parent, name, shape, color)

static func prop(game, parent: Node3D, path: String, size: Vector3) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	if has_asset(path): game.tripo_model(holder, path, size, Vector3(0, size.y*0.5, 0))
	return holder

# 火舌：粒子面片朝向镜头，片元里用滚动的噪声把圆斑撕成翻卷的火舌，每个粒子的噪声相位不同。
# 普通混合 + 超过 1 的高亮颜色（配合辉光），叠在一起仍是橙红而不会加成一片白。
const FIRE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying float seed;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.55 + noise(p * 2.1 + 3.7) * 0.3 + noise(p * 4.3 + 9.1) * 0.15; }
void vertex() {
	seed = float(INSTANCE_ID) * 0.6180339;
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	world = world * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float n = fbm(p * 1.7 + vec2(fract(seed) * 31.0, -TIME * 2.6 - fract(seed * 7.0) * 9.0));
	float d = length(p);
	float shape = 1.0 - smoothstep(0.35, 1.0, d + (n - 0.5) * 0.6);
	float core = 1.0 - smoothstep(0.0, 0.6, d + (n - 0.5) * 0.5);
	ALBEDO = COLOR.rgb * (0.75 + core * 0.5);
	ALPHA = clamp(shape * COLOR.a * 1.15, 0.0, 1.0);
}
"""

static func additive(_texture: Texture2D, size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE*size
	var shader := Shader.new()
	shader.code = FIRE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	quad.material = mat
	return quad

static func fire_ramp(smoke: bool) -> GradientTexture1D:
	var fade := Gradient.new()
	fade.set_color(0, Color(1.4, 0.7, 0.18, 0.0))
	fade.add_point(0.05, Color(1.4, 0.62, 0.12, 0.9))
	fade.add_point(0.28, Color(1.2, 0.3, 0.05, 0.85))
	fade.add_point(0.6, Color(0.75, 0.11, 0.03, 0.65) if not smoke else Color(0.42, 0.1, 0.04, 0.6))
	fade.add_point(0.85, Color(0.16, 0.08, 0.06, 0.4))
	fade.set_color(fade.get_point_count()-1, Color(0.1, 0.07, 0.06, 0.0))
	var texture := GradientTexture1D.new()
	texture.gradient = fade
	return texture

static func grow_curve(a: float, b: float) -> CurveTexture:
	var grow := Curve.new()
	grow.add_point(Vector2(0, a))
	grow.add_point(Vector2(1, b))
	var texture := CurveTexture.new()
	texture.curve = grow
	return texture

# 吐息火焰：从嘴部沿局部 -Z 喷出的一道火柱，越远越粗、由白黄转橙红再化作暗烟。世界坐标发射。
static func flame(name: String, amount: int, life: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = name
	particles.amount = amount*3/2
	particles.lifetime = life
	particles.local_coords = false
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-80, -20, -80), Vector3(160, 60, 160))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.5
	process.direction = Vector3(0, 0, -1)
	process.spread = 7.0
	process.initial_velocity_min = 62.0
	process.initial_velocity_max = 74.0
	process.damping_min = 10.0
	process.damping_max = 16.0
	process.gravity = Vector3(0, 2.0, 0)
	process.scale_min = 0.8
	process.scale_max = 1.3
	process.scale_curve = grow_curve(0.3, 3.4)
	process.angular_velocity_min = -90.0
	process.angular_velocity_max = 90.0
	process.color_ramp = fire_ramp(false)
	particles.process_material = process
	particles.draw_pass_1 = additive(null, 3.6)
	return particles

# 地面火：沿吐息火柱或横掠火线落地处翻腾的一条火带（盒形发射区，世界坐标）。
static func scorch(name: String) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = name
	particles.amount = 220
	particles.lifetime = 0.8
	particles.local_coords = false
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 30, 120))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(1.2, 0.2, 20.0)
	process.direction = Vector3(0, 1, 0)
	process.spread = 25.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 7.0
	process.gravity = Vector3(0, 3.0, 0)
	process.scale_min = 0.6
	process.scale_max = 1.1
	process.scale_curve = grow_curve(0.6, 1.4)
	process.color_ramp = fire_ramp(true)
	particles.process_material = process
	particles.draw_pass_1 = additive(null, 2.8)
	return particles

static func trail_fire() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Trail"
	particles.amount = 40
	particles.lifetime = 0.5
	particles.local_coords = false
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.8
	process.direction = Vector3(0, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.0
	process.gravity = Vector3.ZERO
	process.scale_curve = grow_curve(1.0, 2.2)
	process.color_ramp = fire_ramp(true)
	particles.process_material = process
	particles.draw_pass_1 = additive(null, 2.4)
	return particles

# 冲击环：薄而亮的火红圆环，半径每帧按模拟更新（环宽固定，不随半径变粗）。
static func ring(game, name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	var torus := TorusMesh.new()
	torus.rings = 64
	torus.ring_segments = 6
	node.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.45, 0.12, 0.85)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3(1, 0.25, 1)
	node.hide()
	return node

const LAVA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float life = 1.0;
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float n = noise(p * 4.0 + vec2(seed, TIME * 0.6)) * 0.6 + noise(p * 9.0 - vec2(TIME * 0.9, seed)) * 0.4;
	float edge = 1.0 - smoothstep(0.7 + n * 0.25, 1.0, d);
	float hot = smoothstep(0.35, 0.8, n);
	vec3 crust = vec3(0.12, 0.04, 0.02);
	vec3 molten = mix(vec3(0.85, 0.16, 0.02), vec3(1.15, 0.5, 0.08), hot);
	ALBEDO = mix(crust, molten, smoothstep(0.35, 0.7, n) * (0.6 + 0.4 * life));
	ALPHA = edge * clamp(life * 1.5, 0.0, 1.0);
}
"""

static func lava_pool(n: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Pool%d"%n
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE*(Dragon.POOL_RADIUS*2/SCALE)
	node.mesh = plane
	var shader := Shader.new()
	shader.code = LAVA_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("seed", float(n)*3.7)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = EMBER
	light.omni_range = 4.5
	light.light_energy = 1.6
	light.position = Vector3(0, 0.8, 0)
	node.add_child(light)
	node.hide()
	return node

# 锁链：一串交错 90° 的铁环（MultiMesh），从绞盘射向龙颈。
static func chain(name: String) -> MultiMeshInstance3D:
	var link := TorusMesh.new()
	link.inner_radius = 0.3
	link.outer_radius = 0.58
	link.rings = 10
	link.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("4a4540")
	mat.metallic = 0.85
	mat.roughness = 0.45
	mat.emission_enabled = true
	mat.emission = Color("ff7a2a")
	mat.emission_energy_multiplier = 0.9
	link.material = mat
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = link
	multi.instance_count = CHAIN_LINKS
	multi.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = multi
	return node

static func wall_fire(name: String, event: Dictionary, side: float) -> GPUParticles3D:
	var particles := scorch(name)
	particles.amount = 300
	particles.lifetime = 1.0
	var process: ParticleProcessMaterial = particles.process_material
	process.emission_box_extents = Vector3(1.4, 0.2, Dragon.HOLD/SCALE*0.5)
	process.initial_velocity_min = 4.0
	process.initial_velocity_max = 9.0
	particles.position = local(event, Vector2(side*(320.0-Dragon.WALL_WIDTH*0.5), event.arena+Dragon.HOLD*0.5))
	var light := OmniLight3D.new()
	light.light_color = EMBER
	light.omni_range = 30.0
	light.light_energy = 0.0
	light.position = Vector3(0, 2.0, 0)
	particles.add_child(light)
	return particles

static func entry_fire(event: Dictionary) -> GPUParticles3D:
	var particles := scorch("EntryFire")
	particles.amount = 200
	var process: ParticleProcessMaterial = particles.process_material
	process.emission_box_extents = Vector3(17.0, 0.2, 0.8)
	particles.position = local(event, Vector2(0, event.arena+60.0))
	return particles

# —— 每帧同步 ——

static func once(view: Node3D, key: String) -> bool:
	return BossView.once(view, key)

static func once_tag(view: Node3D, tag: String, key: String) -> bool:
	return BossView.once_tag(view, tag, key)

static func sync(game, view: Node3D, event: Dictionary) -> void:
	var run = game.run
	var dragon: Node3D = view.get_node("Body/Dragon")
	var age: float = run.elapsed-event.state_at
	var dead: bool = event.hp <= 0
	var death_age: float = run.elapsed-event.get("defeated_at", run.elapsed)
	place(run, view, dragon, event, dead, death_age)
	animate(run, dragon, event, age, dead, death_age)
	core(run, view, dragon, event, age, dead)
	flash(game, dragon, event)
	telegraphs(game, view, event, age)
	breath_fx(game, view, dragon, event, age)
	rings(game, view, event)
	meteors(game, view, dragon, event, age)
	pools(run, view, event)
	strafe_fx(game, view, dragon, event, age)
	charge_fx(game, view, dragon, event, age)
	fires(game, view, event, dead)
	moments(game, view, dragon, event, age, dead)
	bar(game, view, event, dead, death_age)
	intro(game, view, dragon, event)

# 龙身位置与姿态：落地时站在落点；飞行时前倾成水平、转弯时侧倾。
static func place(run, view: Node3D, dragon: Node3D, event: Dictionary, dead: bool, death_age: float) -> void:
	var pose: Dictionary = Dragon.body_pose(run, event, run.elapsed)
	var ahead: Dictionary = Dragon.body_pose(run, event, run.elapsed+0.15)
	var pos: Vector2 = pose.pos
	var alt: float = pose.alt
	var heading: Vector2 = pose.heading
	dragon.position = local(event, pos, alt/SCALE)
	dragon.rotation.y = atan2(heading.x, -heading.y)
	var pivot: Node3D = dragon.get_node("Pivot")
	var flying := smoothstep(30.0, 140.0, alt)
	# 侧倾：朝转弯内侧压翼，按 0.15 秒后的朝向变化估算转弯角速度。
	var turn: float = heading.angle_to(ahead.heading)
	pivot.rotation = Vector3(FLY_PITCH*flying, 0, clampf(turn*3.0, -0.6, 0.6)*flying)
	if dead: dragon.position.y = -smoothstep(6.0, 9.0, death_age)*8.0
	dragon.visible = event.phase != "dormant" and (not dead or death_age < 9.0)

# 动作按模拟时间直接取样。
static func animate(run, dragon: Node3D, event: Dictionary, age: float, dead: bool, death_age: float) -> void:
	if not dragon.has_meta("anim"): return
	var player: AnimationPlayer = dragon.get_meta("anim")
	var pace: float = Dragon.PACE[event.stage]
	var clip := "Idle"
	var t: float = fposmod(run.elapsed, 4.0)
	if dead:
		clip = "Death"; t = minf(death_age, 3.0)
	elif event.phase == "intro":
		if age < Dragon.INTRO_LAND-Dragon.LAND_TOUCH:
			# 盘旋：中段滑翔，其余振翅。
			var k := (age-Dragon.INTRO_CIRCLE)/(Dragon.INTRO_DIVE-Dragon.INTRO_CIRCLE)
			if k > 0.3 and k < 0.62: clip = "Glide"; t = fposmod(run.elapsed, 2.0)
			else: clip = "Fly"; t = fposmod(run.elapsed*1.1, 1.0)
		elif age < Dragon.INTRO_ROAR:
			clip = "Land"; t = age-(Dragon.INTRO_LAND-Dragon.LAND_TOUCH)
		elif age < Dragon.INTRO_FIRE:
			clip = "Roar"; t = (age-Dragon.INTRO_ROAR)/(Dragon.INTRO_FIRE-Dragon.INTRO_ROAR)*2.4
		elif age < Dragon.INTRO_FIRED:
			clip = "SkyFire"; t = (age-Dragon.INTRO_FIRE)/(Dragon.INTRO_FIRED-Dragon.INTRO_FIRE)*2.6
	else:
		match event.state:
			"roar", "nova":
				clip = "Roar"; t = clampf(age/Dragon.ROAR, 0, 1)*2.4 if event.state == "roar" else 0.75+fposmod(age, 1.0)
			"breath":
				var windup: float = Dragon.BREATH_WINDUP*pace
				var side := 1.0
				t = age/windup*1.0 if age < windup else 1.2
				var sweep := 0
				if age >= windup:
					var into := age-windup
					sweep = mini(int(into/(Dragon.BREATH_SWEEP+Dragon.BREATH_GAP)), Dragon.breath_sweeps(event)-1)
					var local_t := into-sweep*(Dragon.BREATH_SWEEP+Dragon.BREATH_GAP)
					t = 1.2+minf(local_t, Dragon.BREATH_SWEEP)/Dragon.BREATH_SWEEP*1.4 if local_t <= Dragon.BREATH_SWEEP else 2.6+minf(local_t-Dragon.BREATH_SWEEP, 0.4)
				side = event.breath_side*(1.0 if sweep == 0 else -1.0)
				clip = "BreathL" if side > 0 else "BreathR"
			"tail":
				var windup: float = Dragon.TAIL_WINDUP*pace
				clip = "TailSwipe"; t = age/windup*1.0 if age < windup else minf(1.0+(age-windup), 2.0)
			"meteors":
				var windup: float = Dragon.METEOR_WINDUP*pace
				clip = "SkyFire"; t = age/windup*0.85 if age < windup else minf(0.85+(age-windup), 2.6)
			"strafe":
				if age < Dragon.STRAFE_TAKEOFF: clip = "Takeoff"; t = age
				elif age < Dragon.STRAFE_LOCK or age >= Dragon.STRAFE_LOCK+Dragon.STRAFE_PASS and age < Dragon.STRAFE_RETURN:
					clip = "Fly"; t = fposmod(age*1.2, 1.0)
				elif age < Dragon.STRAFE_RETURN: clip = "Glide"; t = fposmod(age, 2.0)
				else: clip = "Land"; t = age-Dragon.STRAFE_RETURN
			"charge":
				clip = "Charge"; t = fposmod(age, 2.0)
			"stagger":
				clip = "Pinned"; t = age if age < 0.4 else 0.4+fposmod(age-0.4, 1.6)
	var name: String = dragon.get_meta("clip_" + clip, "")
	if name.is_empty():
		for candidate in player.get_animation_list():
			if candidate.get_slice("|", candidate.get_slice_count("|")-1) == clip: name = candidate
		dragon.set_meta("clip_" + clip, name)
	if name.is_empty(): return
	var skeleton: Skeleton3D = dragon.get_meta("skeleton", null)
	if player.current_animation != name:
		if skeleton != null and player.current_animation != "":
			var snapshot: Array = []
			for bone in range(skeleton.get_bone_count()): snapshot.append(skeleton.get_bone_pose_rotation(bone))
			dragon.set_meta("blend_from", snapshot)
			dragon.set_meta("blend_at", run.elapsed)
		player.play(name)
	player.seek(clampf(t, 0.0, player.current_animation_length), true)
	var blend: float = (run.elapsed-float(dragon.get_meta("blend_at", -10.0)))/CROSSFADE
	if skeleton != null and blend < 1.0 and dragon.has_meta("blend_from"):
		var from: Array = dragon.get_meta("blend_from")
		var w := smoothstep(0.0, 1.0, maxf(blend, 0.0))
		for bone in range(mini(from.size(), skeleton.get_bone_count())):
			skeleton.set_bone_pose_rotation(bone, (from[bone] as Quaternion).slerp(skeleton.get_bone_pose_rotation(bone), w))

# 骨骼的世界位置；找不到时按模型比例估算。
static func bone_point(dragon: Node3D, bone_name: String, along: float = 0.0) -> Vector3:
	var skeleton: Skeleton3D = dragon.get_meta("skeleton", null)
	if skeleton != null:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			var pose := skeleton.get_bone_global_pose(bone)
			return skeleton.global_transform*(pose.origin+pose.basis.y.normalized()*along)
	return dragon.global_position+Vector3(0, SIZE*0.5, SIZE*0.3)

static func mouth(dragon: Node3D) -> Vector3:
	return bone_point(dragon, "Head", HEAD_LENGTH*0.95)

static func chest(dragon: Node3D) -> Vector3:
	return bone_point(dragon, "Neck1")

static func core(run, view: Node3D, dragon: Node3D, event: Dictionary, age: float, dead: bool) -> void:
	var node: MeshInstance3D = view.get_node("Core")
	var light: OmniLight3D = view.get_node("CoreLight")
	var exposed: bool = event.state == "stagger" and not dead
	var charging: bool = event.state == "charge" and not dead
	var at := chest(dragon)
	var toward := (dragon.global_transform.basis*Vector3(0, 0, 1)).normalized()
	node.global_position = at+toward*1.6-Vector3(0, 0.4, 0)
	var pulse := 0.5+0.5*sin(run.elapsed*(9.0 if exposed else (5.0 if charging else 2.0)))
	node.visible = exposed and dragon.visible
	node.scale = Vector3.ONE*(1.0+pulse*0.35)*smoothstep(0.0, 0.4, age)
	light.global_position = at+toward*3.0
	var energy := 1.0+pulse*0.8
	if charging: energy = 2.0+pulse*2.5+Dragon.hold_ratio(event)*2.0
	if exposed: energy = 6.0+pulse*3.0
	light.light_energy = 0.0 if dead or not dragon.visible else energy
	light.light_color = Color("fff0b8") if exposed else EMBER

static func flash(game, dragon: Node3D, event: Dictionary) -> void:
	var run = game.run
	var hit_age: float = run.elapsed-event.get("hit_at", -10.0)
	var on: bool = hit_age >= 0.0 and hit_age < 0.07
	if dragon.get_meta("flashing", false) == on: return
	dragon.set_meta("flashing", on)
	var overlay: Material = game.material("enemy_hit_flash", Color("ffe2ad"), .9) if on else null
	for mesh in dragon.get_meta("meshes"): mesh.material_overlay = overlay

static func set_charge(node: MeshInstance3D, charge: float) -> void:
	(node.material_override as ShaderMaterial).set_shader_parameter("charge", clampf(charge, 0, 1))

static func telegraphs(game, view: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var marks: Node3D = view.get_node("Telegraphs")
	for child in marks.get_children(): child.hide()
	if event.hp <= 0 or event.phase != "fight": return
	var pace: float = Dragon.PACE[event.stage]
	match event.state:
		"breath":
			# 扇形：当前或下一道扫射覆盖的半场，从嘴下方的地面铺开。
			var windup: float = Dragon.BREATH_WINDUP*pace
			var cycle := Dragon.BREATH_SWEEP+Dragon.BREATH_GAP
			var sweep := clampi(int(maxf(age-windup+Dragon.BREATH_GAP, 0.0)/cycle), 0, Dragon.breath_sweeps(event)-1)
			var start: float = windup+sweep*cycle
			if age > start+Dragon.BREATH_SWEEP: return
			var side: float = event.breath_side*(1.0 if sweep == 0 else -1.0)
			var sector: MeshInstance3D = marks.get_node("Sector")
			var radius := 1700.0
			sector.show()
			sector.position = local(event, Dragon.mouth(event), 0.05)
			sector.scale = Vector3.ONE*(radius*2/SCALE)
			var mat := sector.material_override as ShaderMaterial
			mat.set_shader_parameter("angle_from", deg_to_rad(side*(Dragon.BREATH_FROM-Dragon.BREATH_HALF)))
			mat.set_shader_parameter("angle_to", deg_to_rad(side*(Dragon.BREATH_TO+Dragon.BREATH_HALF)))
			var lead: float = windup if sweep == 0 else Dragon.BREATH_GAP
			set_charge(sector, 1.0-(start-age)/lead)
		"strafe":
			if age > Dragon.STRAFE_LOCK+Dragon.STRAFE_PASS: return
			var band: MeshInstance3D = marks.get_node("Band")
			band.show()
			band.position = local(event, Vector2(0, event.lane_y), 0.05)
			band.rotation.y = PI/2
			band.scale = Vector3(Dragon.STRAFE_HALF*2/SCALE, 1, run.EDGE*2/SCALE)
			(band.material_override as ShaderMaterial).set_shader_parameter("aspect", Vector2(1, run.EDGE*2/(Dragon.STRAFE_HALF*2)))
			(band.material_override as ShaderMaterial).set_shader_parameter("flow", -event.lane_side)
			set_charge(band, age/Dragon.STRAFE_LOCK)
		"meteors":
			var land: float = Dragon.meteor_land_age(event)
			if age > land: return
			for n in range(event.targets.size()):
				var circle: MeshInstance3D = marks.get_node("Circle%d"%n)
				circle.show()
				circle.position = local(event, event.targets[n], 0.07)
				circle.scale = Vector3.ONE*(Dragon.METEOR_RADIUS*2/SCALE)
				set_charge(circle, age/land)
		"tail":
			# 前摇：脚下一圈逐渐亮起，提示冲击环从这里扩散。
			var windup: float = Dragon.TAIL_WINDUP*pace
			if age > windup: return
			var warn: MeshInstance3D = marks.get_node("Warn")
			warn.show()
			warn.position = local(event, event.perch, 0.06)
			warn.scale = Vector3.ONE*(14.0+age/windup*4.0)
			set_charge(warn, age/windup)
		"charge":
			var spit_age: float = run.elapsed-float(event.get("spit_at", -10.0))
			if spit_age >= 0.0 and spit_age < Dragon.SPIT_FLIGHT:
				var circle: MeshInstance3D = marks.get_node("Spit")
				circle.show()
				circle.position = local(event, event.spit_target, 0.12)
				circle.scale = Vector3.ONE*((Dragon.PLATE_HALF+20.0)*2/SCALE)
				set_charge(circle, spit_age/Dragon.SPIT_FLIGHT)
			if Dragon.nova_warning(run, event):
				var warn: MeshInstance3D = marks.get_node("Warn")
				warn.show()
				warn.position = local(event, event.perch, 0.06)
				warn.scale = Vector3.ONE*22.0
				set_charge(warn, 0.9)

# 吐息：火柱从嘴里沿模拟角度喷出，略向下压到地面；地面沿火柱翻起一条火带。
static func breath_fx(game, view: Node3D, dragon: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var fire: GPUParticles3D = view.get_node("Flame")
	var ground: GPUParticles3D = view.get_node("Scorch")
	var angle := INF
	if event.hp > 0 and event.phase == "fight" and event.state == "breath":
		for sweep in range(Dragon.breath_sweeps(event)):
			var a := Dragon.breath_angle(event, run.elapsed, sweep)
			if a != INF: angle = a
	var on: bool = angle != INF and run.state == "running"
	if on:
		var at := mouth(dragon)
		var flat := Vector3(sin(deg_to_rad(angle)), 0, cos(deg_to_rad(angle)))
		var aim := (flat-Vector3(0, 0.16, 0)).normalized()
		fire.global_transform = Transform3D(Basis.looking_at(aim, Vector3.UP), at)
		var mid := Vector3(at.x, 0.1, at.z)+flat*38.0
		ground.global_transform = Transform3D(Basis.looking_at(flat, Vector3.UP), mid)
		(ground.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(1.4, 0.2, 30.0)
		view.set_meta("flame_at", at+flat*10.0)
		if once_tag(view, "breath_start", "%d"%event.skill_seq): game.sfx.play_at("flame_start", at, 6.0, 0.6)
	# 火柱与喷火声由吐息和横掠共用，在 strafe_fx 里统一开关。
	view.set_meta("breath_on", on)
	if ground.emitting != on: ground.emitting = on

static func set_ring(node: MeshInstance3D, center: Vector3, radius: float, width: float, alpha: float) -> void:
	node.visible = radius > 0.1 and alpha > 0.01
	if not node.visible: return
	var torus := node.mesh as TorusMesh
	torus.inner_radius = maxf(0.05, radius-width)
	torus.outer_radius = radius+width
	node.global_position = center+Vector3(0, 0.3, 0)
	(node.material_override as StandardMaterial3D).albedo_color.a = alpha

static func rings(game, view: Node3D, event: Dictionary) -> void:
	var run = game.run
	var center := world(event.perch, 0.0)
	var reach: float = Dragon.tail_reach(run, event)
	for n in range(2):
		var node: MeshInstance3D = view.get_node("Ring%d"%n)
		var radius := -1.0
		if event.hp > 0 and event.phase == "fight" and event.state == "tail" and n < Dragon.tail_rings(event):
			radius = Dragon.tail_radius(event, run.elapsed, n)
		if radius > reach: radius = -1.0
		set_ring(node, center, radius/SCALE, Dragon.TAIL_HALF/SCALE, 0.9)
		var fx = game.get("fx")
		if radius > 0.0 and fx != null and int(run.elapsed/run.FIXED_STEP)%4 == 0:
			var spin: float = run.elapsed*5.0+n
			for k in range(3):
				var a := spin+k*TAU/3.0
				fx.burst("dust", center+Vector3(cos(a), 0, sin(a))*radius/SCALE)
	var nova: MeshInstance3D = view.get_node("Nova")
	var r: float = Dragon.nova_radius(event, run.elapsed) if event.hp > 0 else -1.0
	if r > reach: r = -1.0
	set_ring(nova, center, r/SCALE, Dragon.NOVA_HALF/SCALE*1.3, 1.0)

static func meteors(game, view: Node3D, dragon: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var falling: bool = event.hp > 0 and event.phase == "fight" and event.state == "meteors"
	var windup: float = Dragon.METEOR_WINDUP*Dragon.PACE[event.stage]
	var sky: GPUParticles3D = view.get_node("SkyFlame")
	# 仰天喷火：出手前后约 0.9 秒朝天喷出火柱。
	var spewing: bool = falling and age >= windup-0.3 and age < windup+0.6 and run.state == "running"
	if spewing:
		var at := mouth(dragon)
		sky.global_transform = Transform3D(Basis.looking_at(Vector3(0, 1, 0.25).normalized(), Vector3.BACK), at)
	# 入场期间朝天火柱由 intro() 控制，这里不去关它。
	if event.phase == "fight" and sky.emitting != spewing: sky.emitting = spewing
	for n in range(8):
		var rock: Node3D = view.get_node("Meteor%d"%n)
		var k: float = (age-windup)/Dragon.METEOR_FALL
		var show: bool = falling and n < event.targets.size() and k >= 0.0 and k < 1.0
		rock.visible = show
		var trail: GPUParticles3D = rock.get_node("Trail")
		if trail.emitting != show: trail.emitting = show
		if not show: continue
		var target := local(event, event.targets[n], 0.3)
		var from := target+Vector3(-6.0+n*1.5, 24.0, -14.0)
		rock.position = from.lerp(target, k*(0.4+0.6*k))
		rock.rotation = Vector3(k*7.0+n, k*5.0, 0)
	if falling and age >= Dragon.meteor_land_age(event) and once_tag(view, "meteors", "%d"%event.skill_seq):
		var fx = game.get("fx")
		var hazard_fx = game.get("hazard_fx")
		for target in event.targets:
			var at := world(target, 0.1)
			if fx != null:
				fx.impact(at, EMBER, Dragon.METEOR_RADIUS/SCALE, 3.0)
				fx.burst("dust", at)
			if hazard_fx != null: hazard_fx.burst_debris(at+Vector3(0, 0.3, 0), Color("2a1d18"), 1.2)
		game.sfx.play_at("explosion", world(event.targets[0], 0.5), 2.0, 0.85)
		if event.targets.size() > 2: game.sfx.play_at("explosion", world(event.targets[2], 0.5), -2.0, 0.75)

static func pools(run, view: Node3D, event: Dictionary) -> void:
	var holder: Node3D = view.get_node("Pools")
	var list: Array = event.get("pools", []) if event.hp > 0 else []
	for n in range(MAX_POOLS):
		var node: MeshInstance3D = holder.get_child(n)
		var show: bool = n < list.size()
		node.visible = show
		if not show: continue
		var pool: Dictionary = list[n]
		node.position = local(event, pool.position, 0.06+n*0.002)
		var left: float = float(pool.until)-run.elapsed
		(node.material_override as ShaderMaterial).set_shader_parameter("life", clampf(left/1.2, 0.0, 1.0))

# 横掠：龙低空横穿，嘴下方一路喷火，横带上沿着龙的轨迹翻起火带。
static func strafe_fx(game, view: Node3D, dragon: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var trail: GPUParticles3D = view.get_node("Trail")
	var fire: GPUParticles3D = view.get_node("Flame")
	var passing: bool = event.hp > 0 and event.state == "strafe" and age >= Dragon.STRAFE_LOCK-0.15 and age < Dragon.STRAFE_LOCK+Dragon.STRAFE_PASS and run.state == "running"
	if passing:
		var pose: Dictionary = Dragon.body_pose(run, event, run.elapsed)
		var x: float = (pose.pos as Vector2).x
		var ground := world(Vector2(x, event.lane_y), 0.1)
		trail.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), ground)
		(trail.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(1.4, 0.2, 4.5)
		var at := mouth(dragon)
		fire.global_transform = Transform3D(Basis.looking_at((ground-at).normalized(), Vector3.UP if absf((ground-at).normalized().y) < 0.98 else Vector3.BACK), at)
		view.set_meta("flame_at", ground)
		var fx = game.get("fx")
		if fx != null and int(run.elapsed/run.FIXED_STEP)%5 == 0: fx.burst("dust", ground)
	if trail.emitting != passing: trail.emitting = passing
	var flaming: bool = passing or view.get_meta("breath_on", false)
	if fire.emitting != flaming: fire.emitting = flaming
	game.sfx.loop_at("dragon_breath", "flame_loop", flaming, view.get_meta("flame_at", Vector3.ZERO), 4.0, 0.7)
	# 起飞与降落时翼风扬尘。
	if event.hp > 0 and event.state == "strafe":
		var fx = game.get("fx")
		var gust: bool = age < Dragon.STRAFE_TAKEOFF or age > Dragon.STRAFE_RETURN+0.3 and age < Dragon.STRAFE_RETURN+1.2
		if gust and fx != null and int(run.elapsed/run.FIXED_STEP)%6 == 0:
			var base := world(event.perch, 0.1)
			var spin: float = run.elapsed*6.0
			fx.burst("dust", base+Vector3(cos(spin)*9.0, 0, sin(spin)*9.0))
			fx.burst("dust", base+Vector3(-cos(spin)*9.0, 0, -sin(spin)*9.0))

static func charge_fx(game, view: Node3D, dragon: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var active: bool = event.hp > 0 and event.phase == "fight" and event.state == "charge"
	var ratio: float = Dragon.hold_ratio(event)
	for n in range(Dragon.PLATES.size()):
		var plate: MeshInstance3D = view.get_node("Plate%d"%n)
		var standing := false
		for role in range(2):
			if Dragon.on_plate(run, event, role) == n: standing = true
		var mat := plate.material_override as StandardMaterial3D
		var pulse := 0.5+0.5*sin(run.elapsed*6.0+n)
		mat.emission_energy_multiplier = (1.2+pulse*1.2+ratio*3.0 if active else 0.15)+(1.5 if standing and active else 0.0)
		mat.emission = LAVA.lerp(Color("fff2c0"), ratio) if active else Color("6b3a20")
		(plate.get_node("Glow") as OmniLight3D).light_energy = (1.5+ratio*4.0+(2.0 if standing else 0.0)) if active else 0.0
		if active and standing and ratio > 0.0 and game.get("fx") != null and int(run.elapsed/run.FIXED_STEP)%12 == n*6:
			game.fx.burst("spark", plate.global_position+Vector3(0, 0.4, 0))
	# 吐向踏板的火球。
	var ball: Node3D = view.get_node("Fireball")
	var spit_age: float = run.elapsed-float(event.get("spit_at", -10.0))
	var flying: bool = active and spit_age >= 0.0 and spit_age < Dragon.SPIT_FLIGHT
	ball.visible = flying
	var trail: GPUParticles3D = ball.get_node("Trail")
	if trail.emitting != flying: trail.emitting = flying
	if flying:
		var k: float = spit_age/Dragon.SPIT_FLIGHT
		var from: Vector3 = mouth(dragon)-view.global_position
		var to := local(event, event.spit_target, 0.4)
		var point := from.lerp(to, k)
		point.y += sin(k*PI)*6.0
		ball.position = point
	if active and spit_age >= Dragon.SPIT_FLIGHT and once_tag(view, "spit", "%d:%d"%[event.skill_seq, int(event.spit_seq)]):
		var at := world(event.spit_target, 0.2)
		if game.get("fx") != null: game.fx.impact(at, EMBER, 3.0, 3.0)
		game.sfx.play_at("explosion", at, -4.0, 1.1)
	if active and int(event.spit_seq) > 0 and spit_age < 0.05 and once_tag(view, "spit_launch", "%d:%d"%[event.skill_seq, int(event.spit_seq)]):
		game.sfx.play_at("flame_start", mouth(dragon), 2.0, 0.8)
	# 锁链：拽倒时从两侧绞盘射向龙颈，0.35 秒射到；硬直期间拉紧，结束后收回。
	var pinned: bool = event.hp > 0 and event.state == "stagger" and event.get("pinned", false)
	var neck := bone_point(dragon, "Neck2")
	for side in range(2):
		var node: MultiMeshInstance3D = view.get_node("Chain%d"%side)
		var multi := node.multimesh
		if not pinned:
			multi.visible_instance_count = 0
			continue
		var winch: Node3D = view.get_node("Winch%d"%side)
		var from := winch.global_position+Vector3(0, 3.2, 0)
		var reach := smoothstep(0.0, 0.35, age)*(1.0-smoothstep(Dragon.STAGGER-0.5, Dragon.STAGGER, age))
		var to := from.lerp(neck+Vector3((-1.0 if side == 0 else 1.0)*0.8, 0, 0), reach)
		var span := to-from
		var count := clampi(int(span.length()/0.85), 1, CHAIN_LINKS)
		var dir := span.normalized() if span.length() > 0.01 else Vector3.UP
		var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.BACK)
		# 实例变换是节点本地坐标：先算世界坐标再换回节点空间。
		var to_local := node.global_transform.affine_inverse()
		for k in range(count):
			var twist := Basis(dir, PI/2 if k%2 == 1 else 0.0)
			# 绳形微微下垂。
			var u := float(k)/maxf(1.0, count-1)
			var sag := Vector3(0, -sin(u*PI)*0.6*(1.0-reach*0.5), 0)
			multi.set_instance_transform(k, to_local*Transform3D(twist*basis, from+span*u+sag))
		multi.visible_instance_count = count
	if pinned and once_tag(view, "chains", "%d"%event.skill_seq):
		game.sfx.play_at("chain_rattle", neck, 6.0, 0.7)
		game.sfx.play_at("metal_heavy", neck, 4.0, 0.6)
		game.sfx.play_at("dragon_roar" if game.sfx.has_sound("dragon_roar") else "boss_roar", neck, 2.0, 1.15)
		if game.get("hazard_fx") != null: game.hazard_fx.slam(world(event.perch, 0.1), 9.0)

# 三阶段火墙与入口火线。
static func fires(game, view: Node3D, event: Dictionary, dead: bool) -> void:
	var run = game.run
	var walls_on: bool = event.stage == 2 and not dead and run.state == "running"
	for n in range(2):
		var wall: GPUParticles3D = view.get_node("Wall%d"%n)
		if wall.emitting != walls_on: wall.emitting = walls_on
		var light: OmniLight3D = wall.get_child(0)
		light.light_energy = 2.5 if walls_on else 0.0
	game.sfx.loop_at("dragon_walls", "fire_crackle_loop", walls_on, world(Vector2(0, event.arena+Dragon.HOLD*0.6), 1.0), -2.0, 0.9)
	var entry: GPUParticles3D = view.get_node("EntryFire")
	var entry_on: bool = event.phase == "fight" and not dead and run.state == "running"
	if entry.emitting != entry_on: entry.emitting = entry_on

# 出手瞬间的冲击与声音。
static func moments(game, view: Node3D, dragon: Node3D, event: Dictionary, age: float, dead: bool) -> void:
	var run = game.run
	var fx = game.get("fx")
	var hazard_fx = game.get("hazard_fx")
	var base := world(event.perch, 0.1)
	var head := mouth(dragon)
	var key := "%s:%d:%d"%[event.state, event.skill_seq, event.stage]
	var roar_name := "dragon_roar" if game.sfx.has_sound("dragon_roar") else "boss_roar"
	if dead:
		if once(view, "dead"):
			game.sfx.play_at(roar_name, head, 4.0, 0.7)
		if death_landed(run, event) and once_tag(view, "dead_fall", "1"):
			game.sfx.play_at("boss_burst", base, 4.0, 0.8)
			game.sfx.play_at("explosion", base, 0.0, 0.6)
			if fx != null: fx.impact(base, EMBER, 12.0, 6.0)
			if hazard_fx != null: hazard_fx.slam(base, 12.0)
		return
	if event.phase != "fight": return
	var pace: float = Dragon.PACE[event.stage]
	match event.state:
		"roar":
			if age >= 0.7 and once(view, key):
				game.sfx.play_at(roar_name, head, 6.0, 1.0)
				game.sfx.play(roar_name, -10.0, 1.0)
				if hazard_fx != null: hazard_fx.slam(base, 10.0)
				if fx != null: fx.impact(base, EMBER, 16.0, 3.0, false)
		"breath":
			if once(view, key): game.sfx.play_at("growl", head, 4.0, 0.55)
		"tail":
			if once(view, key): game.sfx.play_at("growl", head, 2.0, 0.6)
			for ring_index in range(Dragon.tail_rings(event)):
				if age >= Dragon.TAIL_WINDUP*pace+ring_index*Dragon.TAIL_SECOND and once_tag(view, "tail%d"%ring_index, key):
					game.sfx.play_at("boss_burst", base, 2.0, 1.1)
					game.sfx.play_at("punch_heavy", base, 4.0, 0.5)
					if hazard_fx != null: hazard_fx.slam(base, 8.0)
		"meteors":
			if once(view, key): game.sfx.play_at("growl", head, 2.0, 0.5)
			if age >= Dragon.METEOR_WINDUP*pace and once_tag(view, "strike", key):
				game.sfx.play_at(roar_name, head, 2.0, 1.2)
				game.sfx.play_at("flame_start", head, 6.0, 0.5)
				game.sfx.play_at("rocket_whoosh", base+Vector3(0, 30, 0), 6.0, 0.6)
		"strafe":
			if once(view, key):
				game.sfx.play_at("whoosh", base, 6.0, 0.45)
				game.sfx.play_at(roar_name, head, 0.0, 1.1)
			# 振翅：飞行中每次下拍一声低沉的风声。
			var beat := int(age*1.2)
			if age > 0.4 and age < Dragon.STRAFE_RETURN+0.6 and once_tag(view, "flap", "%s:%d"%[key, beat]):
				game.sfx.play_at("wing_flap" if game.sfx.has_sound("wing_flap") else "whoosh", dragon.global_position+Vector3(0, PIVOT, 0), 4.0, 0.55)
			if age >= Dragon.STRAFE_RETURN+Dragon.LAND_TOUCH and once_tag(view, "land", key):
				game.sfx.play_at("boss_burst", base, 0.0, 1.0)
				if hazard_fx != null: hazard_fx.slam(base, 9.0)
				if fx != null: fx.impact(base, Color("d8c2a0"), 12.0, 0.0, false)
		"charge":
			if once(view, key):
				game.sfx.play_at("boss_rumble", base, 2.0, 0.9)
				game.sfx.play("warning", -4.0, 0.9)
			if Dragon.nova_warning(run, event) and once_tag(view, "warn", key): game.sfx.play("warning", -2.0, 0.8)
		"nova":
			if once(view, key):
				game.sfx.play_at("boss_burst", base, 6.0, 0.8)
				game.sfx.play_at("explosion", base, 4.0, 0.6)
				if hazard_fx != null: hazard_fx.slam(base, 16.0)
				if fx != null: fx.impact(base, EMBER, 20.0, 8.0)

static func death_landed(run, event: Dictionary) -> bool:
	return run.elapsed-float(event.get("defeated_at", run.elapsed)) >= 2.0

static func bar(game, view: Node3D, event: Dictionary, dead: bool, death_age: float) -> void:
	var run = game.run
	var layer: CanvasLayer = view.get_node("BossBar")
	var show: bool = event.phase not in ["dormant", "intro"] and (not dead or death_age < 3.0) and run.state in ["running", "paused"]
	layer.visible = show
	if not show: return
	var frame: Control = layer.get_node("Frame")
	var width := minf(560.0, game.get_viewport().get_visible_rect().size.x-40.0)
	frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	frame.position = Vector2((game.get_viewport().get_visible_rect().size.x-width)*0.5, 104)
	var ratio: float = clampf(float(event.hp)/event.max_hp, 0, 1)
	var exposed: bool = event.state == "stagger"
	var fill: ColorRect = frame.get_node("Fill")
	fill.size.x = (width-4)*ratio
	fill.color = LAVA if exposed else Color("c2563a")
	frame.get_node("Back").size.x = width
	var lag: ColorRect = frame.get_node("Lag")
	var shown: float = move_toward(float(view.get_meta("bar_lag", ratio)), ratio, game.frame_delta*0.25)
	view.set_meta("bar_lag", shown)
	lag.size.x = (width-4)*maxf(shown, ratio)
	var title: Label = frame.get_node("Title")
	title.size.x = width
	var status := "  ·  熔岩核暴露！" if exposed else ("  ·  空中" if event.get("airborne", false) else "  ·  龙鳞（伤害 25%）")
	title.text = "%s · 第 %d 阶段%s"%[Dragon.NAME, event.stage+1, status]
	if dead: title.text = "%s 已倒下"%Dragon.NAME

# —— 入场 ——

static func intro_age(run, event: Dictionary) -> float:
	if event.phase == "dormant": return -1.0
	if event.phase == "intro": return run.elapsed-event.state_at
	return Dragon.INTRO+1.0

static func shot(eye: Vector3, look: Vector3) -> Transform3D:
	var dir := (look-eye).normalized()
	return Transform3D.IDENTITY.translated(eye).looking_at(look, Vector3.UP if absf(dir.y) < 0.97 else Vector3.BACK)

static func ease01(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))

# 返回 {transform, fov}：从旅程镜头出发，盘旋时在两人身后仰望追拍，降落时低机位侧前方，咆哮与喷火正面仰拍，最后落在 Boss 战镜头。
static func intro_camera(game, event: Dictionary, home: Transform3D, game_shot: Transform3D) -> Dictionary:
	var run = game.run
	var t: float = run.elapsed-event.state_at
	var perch_z: float = -float(event.perch.y)/SCALE
	var players_z: float = -minf(run.a.position.y, run.b.position.y)/SCALE
	var pose: Dictionary = Dragon.body_pose(run, event, run.elapsed)
	var dragon_at := world(pose.pos, float(pose.alt)/SCALE+PIVOT)
	var watch := Vector3(0, 4.5, players_z+12.0)
	var sky := shot(watch, Vector3(0, 26.0, -float(event.arena+Dragon.CIRCLE_CENTER)/SCALE))
	var result: Dictionary
	if t < Dragon.INTRO_CIRCLE:
		var k := ease01(t/Dragon.INTRO_CIRCLE)
		result = {"transform":home.interpolate_with(sky, k), "fov":lerpf(57.0, 64.0, k)}
	elif t < Dragon.INTRO_DIVE:
		# 追拍：镜头留在两人身后，视线跟着盘旋的龙走，掠过头顶时视线不翻转。
		var look := dragon_at
		look.y = minf(look.y, watch.y+(watch.z-look.z)*1.2+30.0)
		var blend := ease01((t-Dragon.INTRO_CIRCLE)/0.6)
		var tracked := shot(watch+Vector3(sin(t*0.4)*2.0, 0, 0), look)
		result = {"transform":sky.interpolate_with(tracked, blend), "fov":64.0}
	elif t < Dragon.INTRO_ROAR:
		var eye := Vector3(13.0, 2.6, perch_z+30.0)
		var look := dragon_at.lerp(Vector3(0, 6.0, perch_z), ease01((t-Dragon.INTRO_LAND+0.4)/0.8))
		result = {"transform":shot(eye, look), "fov":58.0}
	elif t < Dragon.INTRO_FIRE:
		var k := ease01((t-Dragon.INTRO_ROAR)/(Dragon.INTRO_FIRE-Dragon.INTRO_ROAR))
		var from := shot(Vector3(4.0, 3.2, perch_z+30.0), Vector3(0, 11.0, perch_z))
		var to := shot(Vector3(2.4, 2.8, perch_z+25.0), Vector3(0, 12.5, perch_z))
		result = {"transform":from.interpolate_with(to, k), "fov":52.0}
	elif t < Dragon.INTRO_FIRED:
		var k := ease01((t-Dragon.INTRO_FIRE)/(Dragon.INTRO_FIRED-Dragon.INTRO_FIRE))
		var from := shot(Vector3(-11.0, 3.0, perch_z+36.0), Vector3(0, 13.0, perch_z-2.0))
		var to := shot(Vector3(-8.0, 4.0, perch_z+40.0), Vector3(0, 16.0, perch_z-4.0))
		result = {"transform":from.interpolate_with(to, k), "fov":56.0}
	else:
		var k := ease01((t-Dragon.INTRO_FIRED)/(Dragon.INTRO-Dragon.INTRO_FIRED))
		var last := shot(Vector3(-8.0, 4.0, perch_z+40.0), Vector3(0, 16.0, perch_z-4.0))
		result = {"transform":last.interpolate_with(game_shot, k), "fov":lerpf(56.0, 62.0, k)}
	var amount := intro_shake(t)
	if amount > 0.0:
		var e: float = run.elapsed
		var offset := Vector3(sin(e*41.0)+sin(e*67.0)*0.5, sin(e*53.0+1.3)+sin(e*29.0)*0.4, 0.0)*amount*0.6
		var xform: Transform3D = result.transform
		xform.origin += xform.basis*offset
		xform.basis = xform.basis*Basis(Vector3.FORWARD, sin(e*37.0)*amount*0.025)
		result.transform = xform
	return result

# 震动：盘旋时龙从头顶掠过轻颤，落地猛震，咆哮最强，喷火持续抖动。
static func intro_shake(t: float) -> float:
	if t < 0.0: return 0.0
	var amount := 0.0
	if t >= Dragon.INTRO_LAND: amount = maxf(amount, 1.5*exp(-(t-Dragon.INTRO_LAND)*3.0))
	if t >= Dragon.INTRO_ROAR+0.6 and t < Dragon.INTRO_FIRE+0.3:
		amount = maxf(amount, 0.85*ease01((t-Dragon.INTRO_ROAR-0.6)/0.15)*(1.0-ease01((t-Dragon.INTRO_FIRE+0.5)/0.8)))
	if t >= Dragon.INTRO_FIRE+0.8 and t < Dragon.INTRO_FIRED-0.4: amount = maxf(amount, 0.3)
	return amount

static func intro(game, view: Node3D, dragon: Node3D, event: Dictionary) -> void:
	var run = game.run
	var t := intro_age(run, event)
	var layer: CanvasLayer = view.get_node("Cinema")
	var base := world(event.perch, 0.1)
	var fx = game.get("fx")
	var hazard_fx = game.get("hazard_fx")
	var key := "%.3f"%event.trigger
	var skipped: bool = event.get("intro_skipped", false)
	var roar_name := "dragon_roar" if game.sfx.has_sound("dragon_roar") else "boss_roar"
	if event.phase == "dormant":
		for tag in ["intro_far", "intro_pass", "intro_land", "intro_roar", "intro_fire", "intro_cry", "intro_wave0", "intro_wave1"]:
			view.remove_meta("fx_" + tag)
	var sky: GPUParticles3D = view.get_node("SkyFlame")
	var firing: bool = event.phase == "intro" and t >= Dragon.INTRO_FIRE+0.85 and t < Dragon.INTRO_FIRED-0.5 and run.state == "running"
	if firing:
		var at := mouth(dragon)
		var up := (at-bone_point(dragon, "Neck2")).normalized()
		var aim := (up+Vector3(0, 0.6, 0)).normalized()
		sky.global_transform = Transform3D(Basis.looking_at(aim, Vector3.BACK if absf(aim.y) > 0.97 else Vector3.UP), at)
		if not sky.emitting: sky.emitting = true
	elif event.phase == "intro" and sky.emitting: sky.emitting = false
	game.sfx.loop_at("dragon_intro_fire", "flame_loop", firing, mouth(dragon), 6.0, 0.6)
	if t < 0.0 or t > Dragon.INTRO+0.5:
		layer.visible = false
		return
	if t >= 0.2 and once_tag(view, "intro_far", key) and not skipped:
		game.sfx.play(roar_name, -8.0, 0.8)
	# 盘旋经过两人头顶时一阵翼风。
	if t >= Dragon.INTRO_CIRCLE+(Dragon.INTRO_DIVE-Dragon.INTRO_CIRCLE)*0.45 and once_tag(view, "intro_pass", key) and not skipped:
		game.sfx.play("whoosh", 2.0, 0.4)
		game.sfx.play(roar_name, -2.0, 1.1)
	if event.phase == "intro" and t < Dragon.INTRO_LAND and not skipped:
		var beat := int(t*1.1)
		if once_tag(view, "intro_flap", "%s:%d"%[key, beat]):
			game.sfx.play_at("wing_flap" if game.sfx.has_sound("wing_flap") else "whoosh", dragon.global_position+Vector3(0, PIVOT, 0), 8.0, 0.5)
	if t >= Dragon.INTRO_LAND and once_tag(view, "intro_land", key) and not skipped:
		game.sfx.play_at("boss_burst", base, 6.0, 0.8)
		game.sfx.play("boss_burst", -4.0, 0.9)
		game.sfx.play_at("rubble", base, 4.0, 0.6)
		if hazard_fx != null:
			hazard_fx.slam(base, 14.0)
			for n in range(6): hazard_fx.burst_debris(base+Vector3(cos(n)*6.0, 0.5, sin(n)*6.0), Color("4a3a2c"), 1.6)
		if fx != null: fx.impact(base, Color("d8c2a0"), 16.0, 0.0, false)
		var soil: GPUParticles3D = view.get_node("Soil")
		soil.global_position = base
		soil.amount_ratio = 0.7
		soil.restart()
	if t >= Dragon.INTRO_LAND-0.6 and t < Dragon.INTRO_LAND+1.2 and fx != null and int(run.elapsed/run.FIXED_STEP)%3 == 0:
		var spin: float = run.elapsed*9.0
		fx.burst("dust", base+Vector3(cos(spin)*8.0, 0, sin(spin)*8.0))
		fx.burst("dust", base+Vector3(-cos(spin)*11.0, 0, -sin(spin)*11.0))
	# 登场必有声：落地瞬间（跳过时在跳过那一刻）一声贴耳龙吼。
	if t >= Dragon.INTRO_LAND and once_tag(view, "intro_cry", key):
		game.sfx.play(roar_name, -2.0, 0.95)
	if t >= Dragon.INTRO_ROAR+0.7 and once_tag(view, "intro_roar", key) and not skipped:
		game.sfx.play_at(roar_name, mouth(dragon), 8.0, 0.95)
		game.sfx.play(roar_name, -8.0, 0.9)
	for n in range(2):
		var wave: float = [0.8, 1.3][n]
		if t >= Dragon.INTRO_ROAR+wave and once_tag(view, "intro_wave%d"%n, key) and not skipped:
			if fx != null: fx.impact(base, EMBER.lerp(Color.WHITE, 0.3), 16.0+wave*10.0, 4.0, false)
			if hazard_fx != null: hazard_fx.slam(base, 12.0)
	if t >= Dragon.INTRO_FIRE+0.8 and once_tag(view, "intro_fire", key) and not skipped:
		game.sfx.play_at("flame_start", mouth(dragon), 8.0, 0.55)
	if fx != null and intro_shake(t) > 0.25 and int(run.elapsed/run.FIXED_STEP)%5 == 0:
		var e: float = run.elapsed
		var spot := Vector2(sin(e*13.7)*260.0, lerpf(event.arena+Dragon.TRIGGER, float(event.perch.y)-200.0, 0.5+0.5*sin(e*7.9)))
		fx.burst("dust", world(spot, 0.05))
	layer.visible = event.phase == "intro" and run.state in ["running", "paused"]
	if not layer.visible: return
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var bars := ease01(t/0.6)*(1.0-ease01((t-(Dragon.INTRO-0.7))/0.7))
	var bar_height := size.y*0.12*bars
	var top: ColorRect = layer.get_node("Top")
	var bottom: ColorRect = layer.get_node("Bottom")
	top.position = Vector2.ZERO
	top.size = Vector2(size.x, bar_height)
	bottom.position = Vector2(0, size.y-bar_height)
	bottom.size = Vector2(size.x, bar_height)
	var title := ease01((t-(Dragon.INTRO_ROAR+0.6))/0.5)*(1.0-ease01((t-(Dragon.INTRO_FIRE+0.6))/0.6))
	var name_label: Label = layer.get_node("Name")
	var epithet: Label = layer.get_node("Epithet")
	name_label.position = Vector2(0, size.y*0.7)
	name_label.size = Vector2(size.x, 80)
	epithet.position = Vector2(0, size.y*0.7+74)
	epithet.size = Vector2(size.x, 30)
	name_label.modulate.a = title
	epithet.modulate.a = title*0.9
	name_label.pivot_offset = Vector2(size.x*0.5, 40)
	name_label.scale = Vector2.ONE*(1.12-0.12*title)
	var skip: Label = layer.get_node("Skip")
	skip.position = Vector2(0, size.y-bar_height*0.5-12)
	skip.size = Vector2(size.x-24, 24)
	skip.modulate.a = 0.0 if t < Dragon.INTRO_SKIP_AFTER or t > Dragon.INTRO-Dragon.RETURN_TIME else bars
