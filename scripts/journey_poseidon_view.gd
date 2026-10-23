extends RefCounted
# 第三章 Boss「海神波塞冬」的画面：模型与动作、深潭水面、地面预警、三叉激流、巨浪水墙与缺口、涌泉与旋涡水洼、
# 怒涛震环与海啸、潮汐之心与水弹、雷光、三阶段两侧海水、海神之心与顶部血条、入场运镜。
# 全部只读模拟状态（run.elapsed 与 Boss 事件字段），不写回模拟；一次性特效按“状态 + 技能序号”去重。
# 血条、黑边、预警平面复用 journey_boss_view.gd；粒子面片与圆环复用 journey_dragon_view.gd 的构件。

const Poseidon = preload("res://scripts/journey_poseidon.gd")
const BossView = preload("res://scripts/journey_boss_view.gd")
const DragonView = preload("res://scripts/journey_dragon_view.gd")
const BODY := "res://assets/boss/rigged/poseidon.glb"
const TEMPLE := "res://assets/boss/sunken_temple.glb"
const PATHS := [BODY, TEMPLE]
const SCALE := 20.0
# 模型原生高约 0.98（含神矛），放大 16 倍约 15.7 米（固定远景镜头下才压得住场面）；Pivot 在腰部，悬浮时绕腰部微微前倾。
const SIZE := 16.0
const CROSSFADE := 0.25
const AQUA := Color("5fe6ff")
const DEEP := Color("1b6f8f")
const FOAM := Color("e8fbff")
const DANGER := Color("4ad8ff")
const SAFE := Color("8dffb0")
const MAX_PUDDLES := 20
const ORB_HEIGHT := 1.4

static func world(point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x/SCALE, height, -point.y/SCALE)

static func local(event: Dictionary, point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x/SCALE, height, -(point.y-event.y)/SCALE)

static func has_asset(path: String) -> bool:
	return ResourceLoader.exists(path)

# —— 着色器 ——

# 深潭水面：两层滚动噪声扰动法线，深青色、半透明，入场与凝聚时 churn 增大（翻涌与旋涡白沫）。
const POOL_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform float churn = 0.0;
uniform vec2 center = vec2(0.5, 0.3);
uniform vec4 deep : source_color = vec4(0.05, 0.25, 0.33, 1.0);
uniform vec4 shallow : source_color = vec4(0.16, 0.55, 0.62, 1.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float waves(vec2 p) {
	return noise(p * 3.0 + vec2(TIME * 0.35, TIME * 0.2)) * 0.6 + noise(p * 7.0 - vec2(TIME * 0.5, -TIME * 0.3)) * 0.4;
}
void fragment() {
	vec2 p = UV * vec2(4.0, 6.0);
	vec2 c = UV - center;
	float r = length(c * vec2(1.0, 0.65));
	float ang = atan(c.y, c.x);
	// 旋涡：沿极坐标旋转的条纹，churn 越大越靠外、越亮。
	float spiral = sin(ang * 5.0 + r * 40.0 - TIME * 5.0) * 0.5 + 0.5;
	float swirl = spiral * (1.0 - smoothstep(0.05, 0.12 + churn * 0.25, r)) * churn;
	float h = waves(p) + swirl * 0.6;
	float hx = waves(p + vec2(0.02, 0.0)) - h;
	float hy = waves(p + vec2(0.0, 0.02)) - h;
	NORMAL_MAP = normalize(vec3(-hx * 8.0, -hy * 8.0, 1.0)) * 0.5 + 0.5;
	float foam = smoothstep(0.72, 0.9, h) * 0.5 + swirl * 0.8;
	ALBEDO = mix(mix(deep.rgb, shallow.rgb, h), vec3(0.9, 0.98, 1.0), clamp(foam, 0.0, 1.0));
	EMISSION = vec3(0.05, 0.35, 0.45) * (0.25 + churn * 0.8) * (0.4 + h);
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	ALPHA = 0.88;
}
"""

# 流水：沿 UV.y 流动的条纹与噪声，青白色半透明，用于激流水柱、水墙、涌泉、水球与两侧海水。
const FLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float speed = 2.0;
uniform float alpha = 0.85;
uniform float glow = 1.0;
uniform vec2 tiling = vec2(2.0, 4.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 uv = UV * tiling + vec2(0.0, -TIME * speed);
	float n = noise(uv * 2.0) * 0.6 + noise(uv * 5.3 + 7.1) * 0.4;
	float streak = smoothstep(0.55, 0.85, noise(vec2(UV.x * tiling.x * 6.0, uv.y * 0.8)));
	vec3 deep = vec3(0.1, 0.55, 0.75);
	vec3 bright = vec3(0.75, 0.97, 1.0);
	ALBEDO = mix(deep, bright, clamp(n * 0.7 + streak * 0.6, 0.0, 1.0)) * glow;
	ALPHA = clamp(alpha * (0.55 + n * 0.5 + streak * 0.3), 0.0, 1.0);
}
"""

# 旋涡水洼：螺旋条纹向中心旋转，边缘淡出；life 控制消散。
const WHIRL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float life = 1.0;
uniform float seed = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float spiral = sin(a * 3.0 + r * 14.0 + TIME * 6.0 + seed) * 0.5 + 0.5;
	float edge = 1.0 - smoothstep(0.75, 1.0, r);
	vec3 col = mix(vec3(0.05, 0.35, 0.5), vec3(0.8, 0.97, 1.0), spiral * (1.0 - r * 0.5));
	ALBEDO = col;
	ALPHA = edge * clamp(life * 1.5, 0.0, 1.0) * (0.45 + spiral * 0.45);
}
"""

static func shader_material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

static func flow_mesh(mesh: Mesh, speed: float, alpha: float, tiling: Vector2) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := shader_material(FLOW_SHADER)
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("alpha", alpha)
	mat.set_shader_parameter("tiling", tiling)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.hide()
	return node

static func water_ramp() -> GradientTexture1D:
	var fade := Gradient.new()
	fade.set_color(0, Color(1.2, 1.25, 1.3, 0.0))
	fade.add_point(0.06, Color(1.1, 1.2, 1.3, 0.9))
	fade.add_point(0.35, Color(0.6, 0.95, 1.15, 0.75))
	fade.add_point(0.7, Color(0.25, 0.6, 0.85, 0.45))
	fade.set_color(fade.get_point_count()-1, Color(0.15, 0.4, 0.6, 0.0))
	var texture := GradientTexture1D.new()
	texture.gradient = fade
	return texture

# 水花粒子：火焰面片同款的翻卷圆斑，换成青白色，向上喷出后受重力落下。
static func spray(name: String, amount: int, life: float, size: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = name
	particles.amount = amount
	particles.lifetime = life
	particles.local_coords = false
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-80, -20, -80), Vector3(160, 80, 160))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 1.0
	process.direction = Vector3(0, 1, 0)
	process.spread = 30.0
	process.initial_velocity_min = 8.0
	process.initial_velocity_max = 16.0
	process.gravity = Vector3(0, -14.0, 0)
	process.scale_min = 0.7
	process.scale_max = 1.3
	process.scale_curve = DragonView.grow_curve(0.5, 1.8)
	process.angular_velocity_min = -90.0
	process.angular_velocity_max = 90.0
	process.color_ramp = water_ramp()
	particles.process_material = process
	particles.draw_pass_1 = DragonView.additive(null, size)
	return particles

static func cyan_ring(game, name: String, color: Color) -> MeshInstance3D:
	var node := DragonView.ring(game, name)
	(node.material_override as StandardMaterial3D).albedo_color = color
	return node

static func prop(game, parent: Node3D, path: String, size: Vector3) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	if has_asset(path): game.tripo_model(holder, path, size, Vector3(0, size.y*0.5, 0))
	return holder

# 开放的渐细螺旋水面：沿高度上升，宽度与半径不均匀，避免闭合圆环的硬边。
static func spiral_mesh(phase: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS := 160
	const ACROSS := 6
	for i in range(STEPS+1):
		var t := float(i)/STEPS
		var angle := t*TAU*1.65+phase
		var radius := 3.1+0.55*sin(t*PI)+0.2*sin(t*13.0+phase)
		var width := pow(sin(t*PI), 0.65)*(1.1+0.35*sin(t*17.0+phase))
		for j in range(ACROSS+1):
			var v := float(j)/ACROSS
			var r := radius+(v-0.5)*0.35
			surface.set_uv(Vector2(v, t))
			surface.set_normal(Vector3(cos(angle), 0.15, sin(angle)).normalized())
			surface.add_vertex(Vector3(cos(angle)*r, 0.7+t*8.2+(v-0.5)*width, sin(angle)*r))
	for i in range(STEPS):
		for j in range(ACROSS):
			var a := i*(ACROSS+1)+j
			var b := a+ACROSS+1
			for index in [a, b, a+1, a+1, b, b+1]: surface.add_index(index)
	return surface.commit()

# —— 构建 ——

static func build(game, root: Node3D, event: Dictionary) -> void:
	var run = game.run
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var god := Node3D.new()
	god.name = "God"
	body.add_child(god)
	# 固定数量的水带与水花复用，随本体移动，不逐帧创建资源。
	for n in range(2):
		var ribbon := MeshInstance3D.new()
		ribbon.mesh = spiral_mesh(n*PI)
		var material := ShaderMaterial.new()
		material.shader = load("res://scripts/poseidon_spiral.gdshader")
		material.set_shader_parameter("foam_texture", load("res://assets/boss/poseidon_water/foam_mask.png"))
		material.set_shader_parameter("phase", n*PI)
		ribbon.material_override = material
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ribbon.name = "WaterRibbon%d"%n
		god.add_child(ribbon)
	var casting := spray("CastingSpray", 48, 0.7, 0.45)
	root.add_child(casting)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, SIZE*0.47, 0)
	god.add_child(pivot)
	var model: Node3D = load(BODY).instantiate()
	model.name = "Figure"
	model.scale = Vector3.ONE*SIZE
	model.position = Vector3(0, -SIZE*0.47, 0)
	pivot.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player: AnimationPlayer = players[0]
		player.speed_scale = 0.0
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		god.set_meta("anim", player)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty(): god.set_meta("skeleton", skeletons[0])
	var parts: Array = []
	BossView.meshes(model, parts)
	god.set_meta("meshes", parts)
	# 海神之心：平时只有胸口一点青光随呼吸起伏；被震落时放大发白光、暴露弱点。
	var core := MeshInstance3D.new()
	core.name = "Core"
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	core.mesh = sphere
	core.material_override = game.material("poseidon_core", AQUA, 5.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var core_light := OmniLight3D.new()
	core_light.name = "CoreLight"
	core_light.light_color = AQUA
	core_light.omni_range = 16.0
	root.add_child(core_light)
	# 深潭：覆盖场地尽头到终点之后，海神悬浮其上。
	var pool := MeshInstance3D.new()
	pool.name = "Pool"
	var plane := PlaneMesh.new()
	var width: float = (run.EDGE+260.0)*2.0/SCALE
	var depth: float = (Poseidon.ARENA-Poseidon.POOL_NEAR+700.0)/SCALE
	plane.size = Vector2(width, depth)
	pool.mesh = plane
	pool.material_override = shader_material(POOL_SHADER)
	(pool.material_override as ShaderMaterial).set_shader_parameter("center", Vector2(0.5, (Poseidon.PERCH-Poseidon.POOL_NEAR)/(depth*SCALE)))
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.position = local(event, Vector2(0, event.arena+Poseidon.POOL_NEAR+depth*SCALE*0.5), 0.12)
	root.add_child(pool)
	var pool_light := OmniLight3D.new()
	pool_light.name = "PoolLight"
	pool_light.light_color = AQUA
	pool_light.omni_range = 28.0
	pool_light.light_energy = 1.2
	pool_light.position = local(event, event.perch, 2.0)
	root.add_child(pool_light)
	# 潭边一圈白沫（盒形发射区，常驻）。
	var rim := spray("Rim", 50, 1.4, 1.2)
	var rim_process: ParticleProcessMaterial = rim.process_material
	rim_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rim_process.emission_box_extents = Vector3(width*0.5, 0.1, 0.6)
	rim_process.initial_velocity_min = 0.5
	rim_process.initial_velocity_max = 2.0
	rim_process.gravity = Vector3(0, -1.0, 0)
	rim.position = local(event, Vector2(0, event.arena+Poseidon.POOL_NEAR), 0.2)
	rim.emitting = true
	root.add_child(rim)
	var temple := prop(game, root, TEMPLE, Vector3(26.0, 17.0, 23.0))
	temple.name = "Temple"
	temple.position = local(event, Vector2(0, event.arena+Poseidon.ARENA+300.0), -0.4)
	temple.rotation.y = PI
	var marks := Node3D.new()
	marks.name = "Telegraphs"
	root.add_child(marks)
	for n in range(3): BossView.telegraph(marks, "Lane%d"%n, 0, DANGER)
	for n in range(2):
		for side in range(2): BossView.telegraph(marks, "WaveDanger%d_%d"%[n, side], 0, DANGER)
	for n in range(7): BossView.telegraph(marks, "Circle%d"%n, 1, DANGER)
	BossView.telegraph(marks, "Bolt", 1, DANGER)
	BossView.telegraph(marks, "Warn", 1, DANGER)
	BossView.telegraph(marks, "OrbMark", 1, SAFE)
	# 三叉激流：贴地横冲的水柱（圆柱沿局部 -Z 拉长），水柱末端翻起水花。
	for n in range(3):
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.3
		cylinder.bottom_radius = 1.3
		cylinder.height = 1.0
		cylinder.radial_segments = 16
		var jet := flow_mesh(cylinder, 6.0, 0.85, Vector2(3.0, 12.0))
		jet.name = "Jet%d"%n
		root.add_child(jet)
		root.add_child(spray("JetSpray%d"%n, 70, 0.8, 1.6))
	# 巨浪：每道浪两段水墙（缺口左、右），浪顶翻白沫。
	for n in range(2):
		for side in ["L", "R"]:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			var wall := flow_mesh(box, 2.5, 0.8, Vector2(8.0, 2.0))
			wall.name = "Wall%d%s"%[n, side]
			root.add_child(wall)
		var crest := spray("Crest%d"%n, 110, 0.9, 1.5)
		var crest_process: ParticleProcessMaterial = crest.process_material
		crest_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		crest_process.emission_box_extents = Vector3((run.EDGE+60.0)/SCALE, 0.3, 0.5)
		crest_process.initial_velocity_min = 3.0
		crest_process.initial_velocity_max = 7.0
		root.add_child(crest)
	# 涌泉水柱。
	for n in range(7):
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.6
		cylinder.bottom_radius = 2.6
		cylinder.height = 1.0
		cylinder.radial_segments = 14
		var column := flow_mesh(cylinder, -5.0, 0.8, Vector2(3.0, 4.0))
		column.name = "Geyser%d"%n
		root.add_child(column)
	# 一次性水花：restart() 时整团迸出，之后不再持续喷出。
	var burst := spray("Burst", 140, 1.6, 2.0)
	burst.one_shot = true
	burst.explosiveness = 0.85
	(burst.process_material as ParticleProcessMaterial).emission_sphere_radius = 3.0
	(burst.process_material as ParticleProcessMaterial).initial_velocity_max = 20.0
	root.add_child(burst)
	var puddles := Node3D.new()
	puddles.name = "Puddles"
	root.add_child(puddles)
	for n in range(MAX_PUDDLES):
		var disc := MeshInstance3D.new()
		disc.name = "Puddle%d"%n
		var quad := PlaneMesh.new()
		quad.size = Vector2.ONE*(Poseidon.PUDDLE_RADIUS*2/SCALE)
		disc.mesh = quad
		var mat := shader_material(WHIRL_SHADER)
		mat.set_shader_parameter("seed", float(n)*2.3)
		disc.material_override = mat
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disc.hide()
		puddles.add_child(disc)
	for name in ["Ring0", "Ring1"]: root.add_child(cyan_ring(game, name, Color(0.45, 0.9, 1.0, 0.85)))
	root.add_child(cyan_ring(game, "Tsunami", Color(0.6, 0.95, 1.0, 0.95)))
	# 潮汐之心：水球与补光；能量绳穿过时绕球的白光；水弹。
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = Poseidon.ORB_RADIUS/SCALE*1.6
	orb_mesh.height = orb_mesh.radius*2.0
	var orb := flow_mesh(orb_mesh, 1.5, 0.75, Vector2(4.0, 4.0))
	orb.name = "Orb"
	root.add_child(orb)
	var orb_light := OmniLight3D.new()
	orb_light.name = "OrbLight"
	orb_light.light_color = AQUA
	orb_light.omni_range = 9.0
	orb.add_child(orb_light)
	var bolt_mesh := SphereMesh.new()
	bolt_mesh.radius = 0.9
	bolt_mesh.height = 1.8
	var bolt := flow_mesh(bolt_mesh, 3.0, 0.9, Vector2(3.0, 3.0))
	bolt.name = "WaterBolt"
	root.add_child(bolt)
	# 雷光：从天而降打在神矛尖上的一道亮线与一盏瞬时强光。
	var lightning := MeshInstance3D.new()
	lightning.name = "Lightning"
	var beam := CylinderMesh.new()
	beam.top_radius = 0.18
	beam.bottom_radius = 0.1
	beam.height = 1.0
	beam.radial_segments = 6
	lightning.mesh = beam
	lightning.material_override = game.material("poseidon_lightning", Color("dff6ff"), 8.0)
	lightning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lightning.hide()
	root.add_child(lightning)
	var flash := OmniLight3D.new()
	flash.name = "Flash"
	flash.light_color = Color("cfefff")
	flash.omni_range = 60.0
	flash.light_energy = 0.0
	root.add_child(flash)
	# 三阶段两侧海水。
	for side in [-1.0, 1.0]:
		var strip := PlaneMesh.new()
		strip.size = Vector2(Poseidon.FLOOD_WIDTH/SCALE, Poseidon.HOLD/SCALE)
		var flood := flow_mesh(strip, 0.8, 0.7, Vector2(1.0, 20.0))
		flood.name = "Flood%d"%(0 if side < 0 else 1)
		flood.position = local(event, Vector2(side*(run.EDGE-Poseidon.FLOOD_WIDTH*0.5), event.arena+Poseidon.HOLD*0.5), 0.15)
		root.add_child(flood)
	BossView.build_bar(root)
	BossView.build_cinema(root)
	var cinema: CanvasLayer = root.get_node("Cinema")
	(cinema.get_node("Name") as Label).text = Poseidon.NAME
	(cinema.get_node("Epithet") as Label).text = Poseidon.EPITHET

# —— 每帧同步 ——

static func once(view: Node3D, key: String) -> bool:
	return BossView.once(view, key)

static func once_tag(view: Node3D, tag: String, key: String) -> bool:
	return BossView.once_tag(view, tag, key)

static func sync(game, view: Node3D, event: Dictionary) -> void:
	var run = game.run
	var god: Node3D = view.get_node("Body/God")
	var age: float = run.elapsed-event.state_at
	var dead: bool = event.hp <= 0
	var death_age: float = run.elapsed-event.get("defeated_at", run.elapsed)
	place(run, view, god, event, dead, death_age)
	animate(run, god, event, age, dead, death_age)
	water_aura(game, view, god, event, age, dead)
	core(run, view, god, event, age, dead)
	flash(game, god, event)
	telegraphs(game, view, event, age)
	jets(game, view, god, event, age)
	waves(game, view, event, age)
	geysers(game, view, event, age)
	puddles(run, view, event)
	rings(game, view, event)
	orb(game, view, god, event, age)
	sky(game, view, god, event, age)
	floods(game, view, event, dead)
	moments(game, view, god, event, age, dead)
	bar(game, view, event, dead, death_age)
	intro(game, view, god, event)

static func water_aura(game, view: Node3D, god: Node3D, event: Dictionary, age: float, dead: bool) -> void:
	var run = game.run
	var casting: bool = not dead and event.phase == "fight" and event.state in ["lance", "wave", "geysers", "summon", "ring", "channel", "tsunami"]
	for n in range(2):
		var ribbon: MeshInstance3D = god.get_node("WaterRibbon%d"%n)
		ribbon.visible = not dead and event.phase == "fight"
		ribbon.rotation.y = -run.elapsed*0.55
		ribbon.scale = Vector3(1.12 if casting else 1.0, 1.0, 1.12 if casting else 1.0)
		(ribbon.material_override as ShaderMaterial).set_shader_parameter("strength", 1.0 if casting else 0.0)
	var spray_node: GPUParticles3D = view.get_node("CastingSpray")
	spray_node.global_position = trident_tip(god)
	spray_node.emitting = casting and run.state == "running"
	if casting:
		var pivot: Node3D = god.get_node("Pivot")
		pivot.rotation.x += sin(minf(age, 1.2)/1.2*PI)*0.16
		pivot.rotation.z += sin(age*3.0)*0.08
	game.sfx.loop_at("poseidon_cast_water", "water_jet_loop", casting and run.state == "running", trident_tip(god), -8.0, 0.85)
	if casting and once_tag(view, "water_cast", "%s:%d"%[event.state, event.skill_seq]):
		game.sfx.play_at("water_splash", left_hand(god), 3.0, 1.2)

static func place(run, view: Node3D, god: Node3D, event: Dictionary, dead: bool, death_age: float) -> void:
	var pose: Dictionary = Poseidon.body_pose(run, event, run.elapsed)
	var ahead: Dictionary = Poseidon.body_pose(run, event, run.elapsed+0.3)
	var pos: Vector2 = pose.pos
	god.position = local(event, pos, float(pose.alt)/SCALE)
	# 漂移时朝运动方向微微侧倾，并略转身看向两人中点。
	var drift: float = ((ahead.pos as Vector2).x-pos.x)/0.3
	var pivot: Node3D = god.get_node("Pivot")
	pivot.rotation = Vector3(0.05, 0, clampf(-drift*0.004, -0.12, 0.12))
	var middle: Vector2 = (run.a.position+run.b.position)*0.5
	var look: Vector2 = middle-pos
	god.rotation.y = clampf(atan2(look.x, -look.y), -0.35, 0.35) if look.length() > 1.0 else 0.0
	god.visible = event.phase != "dormant" and (not dead or death_age < 6.0)
	var pool: MeshInstance3D = view.get_node("Pool")
	var churn := 0.25
	if event.phase == "intro":
		var t: float = run.elapsed-event.state_at
		churn = 0.25+smoothstep(Poseidon.INTRO_STIR, Poseidon.INTRO_RISE, t)*0.75*(1.0-smoothstep(Poseidon.INTRO_RISEN, Poseidon.INTRO_RISEN+1.5, t))
	elif event.state == "channel" and not dead: churn = 0.6
	elif dead: churn = 0.25+0.6*(1.0-smoothstep(0.0, 6.0, death_age))
	(pool.material_override as ShaderMaterial).set_shader_parameter("churn", churn)
	(pool.material_override as ShaderMaterial).set_shader_parameter("center", Vector2(0.5+pos.x/((run.EDGE+260.0)*2.0), (float(event.perch.y)-event.arena-Poseidon.POOL_NEAR)/(Poseidon.ARENA-Poseidon.POOL_NEAR+700.0)))

# 动作按模拟时间直接取样。
static func animate(run, god: Node3D, event: Dictionary, age: float, dead: bool, death_age: float) -> void:
	if not god.has_meta("anim"): return
	var player: AnimationPlayer = god.get_meta("anim")
	var pace: float = Poseidon.PACE[event.stage]
	var clip := "Idle"
	var t: float = fposmod(run.elapsed, 4.0)
	if dead:
		clip = "Death"; t = minf(death_age, 3.0)
	elif event.phase == "intro":
		if age < Poseidon.INTRO_RISE: clip = "Rise"; t = 0.0
		elif age < Poseidon.INTRO_RISE+3.0: clip = "Rise"; t = age-Poseidon.INTRO_RISE
		elif age < Poseidon.INTRO_RAISE: clip = "Idle"; t = fposmod(run.elapsed, 4.0)
		elif age < Poseidon.INTRO_SLAM: clip = "Raise"; t = minf((age-Poseidon.INTRO_RAISE)/(Poseidon.INTRO_SLAM-Poseidon.INTRO_RAISE)*1.6, 1.6)
		else: clip = "Slam"; t = minf(0.6+(age-Poseidon.INTRO_SLAM), 1.4)
	else:
		match event.state:
			"roar": clip = "Summon"; t = clampf(age/Poseidon.ROAR, 0, 1)*1.6
			"lance":
				var windup: float = Poseidon.LANCE_WINDUP*pace
				if age < windup: clip = "Raise"; t = age/windup
				else: clip = "Thrust"; t = minf(0.1+(age-windup), 1.0)
			"wave":
				var windup: float = Poseidon.WAVE_WINDUP*pace
				clip = "Sweep"; t = age/windup if age < windup else minf(1.0+(age-windup), 1.6)
			"geysers":
				var windup: float = Poseidon.GEYSER_WINDUP*pace
				clip = "Summon"; t = age/windup if age < windup else minf(1.0+(age-windup)*0.6, 1.6)
			"summon":
				var windup: float = Poseidon.SUMMON_WINDUP*pace
				clip = "Summon"; t = minf(age/windup, 1.6)
			"ring":
				var windup: float = Poseidon.RING_WINDUP*pace
				clip = "Slam"; t = age/windup if age < windup else minf(1.0+(age-windup), 1.4)
			"channel": clip = "Channel"; t = fposmod(age, 2.0)
			"tsunami": clip = "Slam"; t = minf(1.0+age, 1.4)
			"stagger": clip = "Stagger"; t = age if age < 0.5 else 0.5+fposmod(age-0.5, 2.0)
	var name: String = god.get_meta("clip_" + clip, "")
	if name.is_empty():
		for candidate in player.get_animation_list():
			if candidate.get_slice("|", candidate.get_slice_count("|")-1) == clip: name = candidate
		god.set_meta("clip_" + clip, name)
	if name.is_empty(): return
	var skeleton: Skeleton3D = god.get_meta("skeleton", null)
	if player.current_animation != name:
		if skeleton != null and player.current_animation != "":
			var snapshot: Array = []
			for bone in range(skeleton.get_bone_count()): snapshot.append(skeleton.get_bone_pose_rotation(bone))
			god.set_meta("blend_from", snapshot)
			god.set_meta("blend_at", run.elapsed)
		player.play(name)
	player.seek(clampf(t, 0.0, player.current_animation_length), true)
	var blend: float = (run.elapsed-float(god.get_meta("blend_at", -10.0)))/CROSSFADE
	if skeleton != null and blend < 1.0 and god.has_meta("blend_from"):
		var from: Array = god.get_meta("blend_from")
		var w := smoothstep(0.0, 1.0, maxf(blend, 0.0))
		for bone in range(mini(from.size(), skeleton.get_bone_count())):
			skeleton.set_bone_pose_rotation(bone, (from[bone] as Quaternion).slerp(skeleton.get_bone_pose_rotation(bone), w))

# 骨骼的世界位置；找不到时按模型比例估算。
static func bone_point(god: Node3D, bone_name: String, along: float = 0.0) -> Vector3:
	var skeleton: Skeleton3D = god.get_meta("skeleton", null)
	if skeleton != null:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			var pose := skeleton.get_bone_global_pose(bone)
			return skeleton.global_transform*(pose.origin+pose.basis.y.normalized()*along)
	return god.global_position+Vector3(0, SIZE*0.7, 0)

static func chest(god: Node3D) -> Vector3:
	return bone_point(god, "Chest")

# 神矛尖：右手握矛竖直，尖端约在手上方 4 米（随身体倾斜）。
static func trident_tip(god: Node3D) -> Vector3:
	return bone_point(god, "Hand.R")+god.global_transform.basis.y.normalized()*SIZE*0.3

static func left_hand(god: Node3D) -> Vector3:
	return bone_point(god, "Hand.L", 0.05)

static func core(run, view: Node3D, god: Node3D, event: Dictionary, age: float, dead: bool) -> void:
	var node: MeshInstance3D = view.get_node("Core")
	var light: OmniLight3D = view.get_node("CoreLight")
	var exposed: bool = event.state == "stagger" and not dead
	var at := chest(god)
	var toward := (god.global_transform.basis*Vector3(0, 0, 1)).normalized()
	node.global_position = at+toward*1.4
	var pulse := 0.5+0.5*sin(run.elapsed*(9.0 if exposed else 2.0))
	node.visible = exposed and god.visible
	node.scale = Vector3.ONE*(1.0+pulse*0.4)*smoothstep(0.0, 0.4, age)
	light.global_position = at+toward*2.5
	var energy := 0.8+pulse*0.6
	if event.state == "channel": energy = 1.5+pulse*1.5+Poseidon.hold_ratio(event)*2.0
	if exposed: energy = 6.0+pulse*3.0
	light.light_energy = 0.0 if dead or not god.visible else energy
	light.light_color = Color("f2fdff") if exposed else AQUA

static func flash(game, god: Node3D, event: Dictionary) -> void:
	var run = game.run
	var hit_age: float = run.elapsed-event.get("hit_at", -10.0)
	var on: bool = hit_age >= 0.0 and hit_age < 0.07
	if god.get_meta("flashing", false) == on: return
	god.set_meta("flashing", on)
	var overlay: Material = game.material("enemy_hit_flash", Color("ffe2ad"), .9) if on else null
	for mesh in god.get_meta("meshes"): mesh.material_overlay = overlay

static func set_charge(node: MeshInstance3D, charge: float) -> void:
	(node.material_override as ShaderMaterial).set_shader_parameter("charge", clampf(charge, 0, 1))

# 直线预警：line 从 from 沿 dir 延伸 length（道路单位），半宽 half。
static func lane(node: MeshInstance3D, event: Dictionary, from: Vector2, dir: Vector2, length: float, half: float, charge: float, flow: float) -> void:
	node.show()
	node.position = local(event, from+dir*length*0.5, 0.06)
	node.rotation = Vector3(0, atan2(dir.x, -dir.y), 0)
	node.scale = Vector3(half*2/SCALE, 1, length/SCALE)
	var mat := node.material_override as ShaderMaterial
	mat.set_shader_parameter("aspect", Vector2(1, length/(half*2)))
	mat.set_shader_parameter("flow", flow)
	set_charge(node, charge)

static func telegraphs(game, view: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var marks: Node3D = view.get_node("Telegraphs")
	for child in marks.get_children(): child.hide()
	if event.hp <= 0 or event.phase != "fight": return
	var pace: float = Poseidon.PACE[event.stage]
	match event.state:
		"lance":
			var windup: float = Poseidon.LANCE_WINDUP*pace
			if age > windup+Poseidon.LANCE_DELAY: return
			for n in range(event.lances.size()):
				lane(marks.get_node("Lane%d"%n), event, event.lance_from, event.lances[n], Poseidon.LANCE_LENGTH, Poseidon.LANCE_HALF, age/(windup+Poseidon.LANCE_DELAY), -1.0)
		"wave":
			# 只显示最近一道浪的危险区，避免交错缺口的预警互相覆盖。
			for n in range(event.gaps.size()):
				var front: float = Poseidon.wave_y(event, run.elapsed, n)
				if front == -INF: continue
				var top: float = float(event.perch.y)-Poseidon.WAVE_START if front == INF else front
				var bottom: float = event.arena+Poseidon.FLOOR
				var length := maxf(10.0, top-bottom)
				var gap: float = event.gaps[n]
				for side in range(2):
					var inner: float = gap-Poseidon.WAVE_GAP if side == 0 else gap+Poseidon.WAVE_GAP
					var outer: float = -run.EDGE if side == 0 else run.EDGE
					lane(marks.get_node("WaveDanger%d_%d"%[n, side]), event, Vector2((inner+outer)*0.5, bottom), Vector2(0, 1), length, absf(outer-inner)*0.5, clampf(age/(Poseidon.WAVE_WINDUP*pace), 0.3, 0.8), -1.0)
				break
		"geysers":
			var erupt: float = Poseidon.geyser_age(event)
			if age > erupt: return
			for n in range(event.targets.size()):
				var circle: MeshInstance3D = marks.get_node("Circle%d"%n)
				circle.show()
				circle.position = local(event, event.targets[n], 0.07)
				circle.scale = Vector3.ONE*(Poseidon.GEYSER_RADIUS*2/SCALE)
				set_charge(circle, age/erupt)
		"ring":
			var windup: float = Poseidon.RING_WINDUP*pace
			if age > windup: return
			var warn: MeshInstance3D = marks.get_node("Warn")
			warn.show()
			warn.position = local(event, Poseidon.ring_center(event), 0.06)
			warn.scale = Vector3.ONE*(8.0+age/windup*4.0)
			set_charge(warn, age/windup)
		"channel":
			var bolt_age: float = run.elapsed-float(event.get("bolt_at", -10.0))
			if bolt_age >= 0.0 and bolt_age < Poseidon.BOLT_FLIGHT:
				var circle: MeshInstance3D = marks.get_node("Bolt")
				circle.show()
				circle.position = local(event, event.bolt_target, 0.12)
				circle.scale = Vector3.ONE*(Poseidon.BOLT_RADIUS*2/SCALE)
				set_charge(circle, bolt_age/Poseidon.BOLT_FLIGHT)
			if Poseidon.orb_ready(event, run.elapsed):
				var mark: MeshInstance3D = marks.get_node("OrbMark")
				mark.show()
				mark.position = local(event, Poseidon.orb_center(event, run.elapsed), 0.05)
				mark.scale = Vector3.ONE*(Poseidon.ORB_RADIUS*2.6/SCALE)
				set_charge(mark, 0.3+Poseidon.hold_ratio(event)*0.6)
			if Poseidon.tsunami_warning(run, event):
				var warn: MeshInstance3D = marks.get_node("Warn")
				warn.show()
				warn.position = local(event, Poseidon.source(run, event), 0.06)
				warn.scale = Vector3.ONE*20.0
				set_charge(warn, 0.9)

# 三叉激流：水柱贴地从海神脚下沿锁定方向冲出，0.15 秒伸到全长；末端与神矛尖翻起水花。
static func jets(game, view: Node3D, god: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var live: bool = event.hp > 0 and Poseidon.lance_live(event, run.elapsed) and run.state == "running"
	var start: float = Poseidon.LANCE_WINDUP*Poseidon.PACE[event.stage]+Poseidon.LANCE_DELAY
	for n in range(3):
		var jet: MeshInstance3D = view.get_node("Jet%d"%n)
		var spray_node: GPUParticles3D = view.get_node("JetSpray%d"%n)
		var on: bool = live and n < event.lances.size()
		jet.visible = on
		if spray_node.emitting != on: spray_node.emitting = on
		if not on: continue
		var dir: Vector2 = event.lances[n]
		var grow := smoothstep(0.0, 0.15, age-start)
		var fade := 1.0-smoothstep(Poseidon.LANCE_FIRE-0.15, Poseidon.LANCE_FIRE, age-start)
		var length: float = Poseidon.LANCE_LENGTH*grow
		var from := world(event.lance_from, 1.1)
		var dir3 := Vector3(dir.x, 0, -dir.y).normalized()
		var basis := Basis.looking_at(dir3, Vector3.UP)*Basis(Vector3.RIGHT, PI/2)
		jet.global_transform = Transform3D(basis*Basis.from_scale(Vector3(fade, maxf(0.01, length/SCALE), fade)), from+dir3*length/SCALE*0.5)
		spray_node.global_position = from+dir3*length/SCALE
	game.sfx.loop_at("poseidon_jet", "water_jet_loop", live, world(event.lance_from, 1.0), 4.0, 1.0)

# 巨浪：水墙在缺口两侧各一段，高约 4 米，浪顶翻白沫；拍过两人后继续推到场地入口消失。
static func waves(game, view: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	for n in range(2):
		var crest: GPUParticles3D = view.get_node("Crest%d"%n)
		var front := INF
		if event.hp > 0 and event.state == "wave" and n < event.gaps.size(): front = Poseidon.wave_y(event, run.elapsed, n)
		var on: bool = front != INF and front != -INF
		if crest.emitting != (on and run.state == "running"): crest.emitting = on and run.state == "running"
		for side in ["L", "R"]:
			var wall: MeshInstance3D = view.get_node("Wall%d%s"%[n, side])
			wall.visible = on
			if not on: continue
			var gap: float = event.gaps[n]
			var inner: float = gap-Poseidon.WAVE_GAP if side == "L" else gap+Poseidon.WAVE_GAP
			var outer: float = -run.EDGE-240.0 if side == "L" else run.EDGE+240.0
			var width := absf(outer-inner)
			var rise := smoothstep(0.0, 0.25, run.elapsed-(event.state_at+Poseidon.WAVE_WINDUP*Poseidon.PACE[event.stage]+n*Poseidon.WAVE_SECOND))
			var height := 4.2*rise
			wall.position = local(event, Vector2((inner+outer)*0.5, front), height*0.5)
			wall.scale = Vector3(width/SCALE, maxf(0.05, height), Poseidon.WAVE_HALF*2/SCALE)
		if on: crest.global_position = world(Vector2(0, front), 4.0)

static func geysers(game, view: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var erupt: float = Poseidon.geyser_age(event)
	var active: bool = event.hp > 0 and event.state == "geysers"
	for n in range(7):
		var column: MeshInstance3D = view.get_node("Geyser%d"%n)
		var k: float = age-erupt
		var show: bool = active and n < event.targets.size() and k >= -0.05 and k < 0.8
		column.visible = show
		if not show: continue
		var height := 9.0*smoothstep(-0.05, 0.12, k)*(1.0-smoothstep(0.45, 0.8, k))
		column.position = local(event, event.targets[n], height*0.5)
		column.scale = Vector3(1.0, maxf(0.05, height), 1.0)
	if active and age >= erupt and once_tag(view, "geysers", "%d"%event.skill_seq):
		var burst: GPUParticles3D = view.get_node("Burst")
		var fx = game.get("fx")
		for target in event.targets:
			var at := world(target, 0.1)
			if fx != null: fx.impact(at, AQUA, Poseidon.GEYSER_RADIUS/SCALE, 0.0, false)
		burst.global_position = world(event.targets[0], 0.5)
		burst.restart()
		game.sfx.play_at("water_splash", world(event.targets[0], 0.5), 6.0, 0.8)
		if event.targets.size() > 2: game.sfx.play_at("water_splash", world(event.targets[2], 0.5), 2.0, 0.95)
		game.sfx.play_at("tide_crash", world(event.targets[0], 0.5), -4.0, 1.3)

static func puddles(run, view: Node3D, event: Dictionary) -> void:
	var holder: Node3D = view.get_node("Puddles")
	var list: Array = event.get("puddles", []) if event.hp > 0 else []
	for n in range(MAX_PUDDLES):
		var node: MeshInstance3D = holder.get_child(n)
		var show: bool = n < list.size()
		node.visible = show
		if not show: continue
		var puddle: Dictionary = list[n]
		node.position = local(event, puddle.position, 0.06+n*0.002)
		var left: float = float(puddle.until)-run.elapsed
		(node.material_override as ShaderMaterial).set_shader_parameter("life", clampf(left/1.0, 0.0, 1.0))

static func rings(game, view: Node3D, event: Dictionary) -> void:
	var run = game.run
	var center := world(Poseidon.ring_center(event), 0.0)
	var reach: float = Poseidon.ring_reach(run, event)
	for n in range(2):
		var node: MeshInstance3D = view.get_node("Ring%d"%n)
		var radius := -1.0
		if event.hp > 0 and event.phase == "fight" and event.state == "ring" and n < Poseidon.ring_count(event):
			radius = Poseidon.ring_radius(event, run.elapsed, n)
		if radius > reach: radius = -1.0
		DragonView.set_ring(node, center, radius/SCALE, Poseidon.RING_HALF/SCALE, 0.9)
		var fx = game.get("fx")
		if radius > 0.0 and fx != null and int(run.elapsed/run.FIXED_STEP)%4 == 0:
			var spin: float = run.elapsed*5.0+n
			for k in range(3):
				var a := spin+k*TAU/3.0
				fx.burst("dust", center+Vector3(cos(a), 0, sin(a))*radius/SCALE)
	var tsunami: MeshInstance3D = view.get_node("Tsunami")
	if event.phase == "intro": return
	var r: float = Poseidon.tsunami_radius(event, run.elapsed) if event.hp > 0 else -1.0
	var origin := world(Poseidon.source(run, event), 0.0)
	if r > origin.distance_to(world(Vector2(run.EDGE, event.arena), 0.0))*SCALE+60.0: r = -1.0
	DragonView.set_ring(tsunami, origin, r/SCALE, Poseidon.TSUNAMI_HALF/SCALE*1.4, 1.0)

# 潮汐之心：水球从海神头顶落到场地中段，左右摆动；能量绳穿过时球体变亮、四周迸出火花；破甲瞬间炸开。水弹从左手掷出。
static func orb(game, view: Node3D, god: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var node: MeshInstance3D = view.get_node("Orb")
	var light: OmniLight3D = node.get_node("OrbLight")
	var active: bool = event.hp > 0 and event.phase == "fight" and event.state == "channel"
	node.visible = active
	if active:
		var windup: float = Poseidon.CHANNEL_WINDUP*Poseidon.PACE[event.stage]
		var above := left_hand(god).lerp(bone_point(god, "Hand.R"), 0.5)+Vector3(0, 2.0, 0)
		var settled := world(Poseidon.orb_center(event, run.elapsed), ORB_HEIGHT)
		var k := smoothstep(windup, windup+Poseidon.ORB_DROP, age)
		var grow := smoothstep(0.0, windup, age)
		var through: bool = Poseidon.rope_through(run, event)
		node.global_position = above.lerp(settled, k)+Vector3(0, sin(k*PI)*4.0, 0)
		var pulse := 0.5+0.5*sin(run.elapsed*(12.0 if through else 4.0))
		node.scale = Vector3.ONE*grow*(1.0+pulse*0.08+Poseidon.hold_ratio(event)*0.35)
		(node.material_override as ShaderMaterial).set_shader_parameter("glow", 1.0+Poseidon.hold_ratio(event)*1.2+(0.4 if through else 0.0))
		light.light_energy = 1.5+Poseidon.hold_ratio(event)*5.0+(2.0 if through else 0.0)
		var fx = game.get("fx")
		if through and fx != null and int(run.elapsed/run.FIXED_STEP)%6 == 0: fx.burst("spark", node.global_position)
		game.sfx.loop_at("poseidon_orb", "water_jet_loop", through, node.global_position, -6.0, 1.6)
	else:
		game.sfx.loop_at("poseidon_orb", "water_jet_loop", false)
	# 破甲：水球炸开。
	if event.hp > 0 and event.state == "stagger" and once_tag(view, "orb_burst", "%d"%event.stagger_count):
		var at := world(event.get("burst_at", event.perch), ORB_HEIGHT)
		var fx = game.get("fx")
		if fx != null: fx.impact(at, AQUA, 6.0, 4.0)
		var burst: GPUParticles3D = view.get_node("Burst")
		burst.global_position = at
		burst.restart()
		game.sfx.play_at("water_splash", at, 8.0, 0.7)
		game.sfx.play_at("thunder", at, 4.0, 1.1)
		game.sfx.play_at("boss_roar", chest(god), 4.0, 0.75)
		view.set_meta("strike_at", run.elapsed)
	# 水弹。
	var ball: MeshInstance3D = view.get_node("WaterBolt")
	var bolt_age: float = run.elapsed-float(event.get("bolt_at", -10.0))
	var flying: bool = active and bolt_age >= 0.0 and bolt_age < Poseidon.BOLT_FLIGHT
	ball.visible = flying
	if flying:
		var k: float = bolt_age/Poseidon.BOLT_FLIGHT
		var from := left_hand(god)
		var to := world(event.bolt_target, 0.4)
		var point := from.lerp(to, k)
		point.y += sin(k*PI)*5.0
		ball.global_position = point
	if active and bolt_age >= Poseidon.BOLT_FLIGHT and once_tag(view, "bolt", "%d:%d"%[event.skill_seq, int(event.bolt_seq)]):
		var at := world(event.bolt_target, 0.2)
		if game.get("fx") != null: game.fx.impact(at, AQUA, 2.5, 0.0, false)
		game.sfx.play_at("water_splash", at, 0.0, 1.1)

# 雷光：入场举矛、凝聚潮汐之心、破甲时各劈一道，强光 0.25 秒衰减。
static func sky(game, view: Node3D, god: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	if event.hp > 0 and event.phase == "fight" and event.state == "channel" and age >= 0.3 and once_tag(view, "channel_strike", "%d"%event.skill_seq):
		view.set_meta("strike_at", run.elapsed)
		game.sfx.play_at("thunder", trident_tip(god), 4.0, 1.0)
	var since: float = run.elapsed-float(view.get_meta("strike_at", -10.0))
	var lightning: MeshInstance3D = view.get_node("Lightning")
	var light: OmniLight3D = view.get_node("Flash")
	var on := since >= 0.0 and since < 0.25
	lightning.visible = on and god.visible
	light.light_energy = 0.0 if not on else 12.0*(1.0-since/0.25)
	if not on: return
	var tip := trident_tip(god)
	var top := tip+Vector3(sin(run.elapsed*31.0)*3.0, 40.0, -6.0)
	lightning.global_transform = Transform3D(Basis.looking_at((tip-top).normalized(), Vector3.FORWARD)*Basis(Vector3.RIGHT, PI/2), (tip+top)*0.5)
	lightning.scale = Vector3(1.0+sin(run.elapsed*80.0)*0.4, tip.distance_to(top), 1.0)
	light.global_position = tip+Vector3(0, 3.0, 0)

static func floods(game, view: Node3D, event: Dictionary, dead: bool) -> void:
	var run = game.run
	var on: bool = event.stage == 2 and not dead and event.phase == "fight"
	for n in range(2):
		(view.get_node("Flood%d"%n) as MeshInstance3D).visible = on
	game.sfx.loop_at("poseidon_flood", "water_jet_loop", on and run.state == "running", world(Vector2(0, event.arena+Poseidon.HOLD*0.6), 1.0), -12.0, 0.6)

# 出手瞬间的冲击与声音。
static func moments(game, view: Node3D, god: Node3D, event: Dictionary, age: float, dead: bool) -> void:
	var run = game.run
	var fx = game.get("fx")
	var hazard_fx = game.get("hazard_fx")
	var base := world(Poseidon.source(run, event), 0.2)
	var head := bone_point(god, "Head")
	var key := "%s:%d:%d"%[event.state, event.skill_seq, event.stage]
	if dead:
		if once(view, "dead"):
			game.sfx.play_at("boss_roar", head, 4.0, 0.65)
			game.sfx.play("thunder", -6.0, 0.8)
		if run.elapsed-float(event.get("defeated_at", run.elapsed)) >= 2.0 and once_tag(view, "dead_sink", "1"):
			game.sfx.play_at("tide_crash", base, 6.0, 0.7)
			if fx != null: fx.impact(base, AQUA, 12.0, 0.0, false)
			var burst: GPUParticles3D = view.get_node("Burst")
			burst.global_position = base
			burst.restart()
		return
	if event.phase != "fight": return
	var pace: float = Poseidon.PACE[event.stage]
	match event.state:
		"roar":
			if age >= 0.6 and once(view, key):
				game.sfx.play_at("boss_roar", head, 6.0, 0.8)
				game.sfx.play("thunder", -8.0, 0.9)
				view.set_meta("strike_at", run.elapsed)
				if hazard_fx != null: hazard_fx.slam(base, 10.0)
		"lance":
			if once(view, key): game.sfx.play_at("growl", head, 2.0, 0.5)
			if age >= Poseidon.LANCE_WINDUP*pace+Poseidon.LANCE_DELAY and once_tag(view, "lance", key):
				game.sfx.play_at("tide_crash", base, 2.0, 1.4)
				game.sfx.play_at("rocket_whoosh", base, 2.0, 0.7)
		"wave":
			if once(view, key): game.sfx.play_at("growl", head, 2.0, 0.55)
			for n in range(Poseidon.wave_count(event)):
				if age >= Poseidon.WAVE_WINDUP*pace+n*Poseidon.WAVE_SECOND and once_tag(view, "wave%d"%n, key):
					game.sfx.play_at("tide_crash", base, 8.0, 0.85)
					game.sfx.play_at("water_splash", base, 4.0, 0.7)
					if hazard_fx != null: hazard_fx.slam(base, 8.0)
		"summon":
			if once(view, key): game.sfx.play_at("boss_roar", head, 0.0, 1.1)
			if age >= Poseidon.SUMMON_WINDUP*pace and once_tag(view, "summon", key):
				for x in [-180.0, 0.0, 180.0]:
					var at := world(Vector2(x, event.arena+Poseidon.POOL_NEAR-40.0), 0.2)
					game.sfx.play_at("water_splash", at, 2.0, 0.9)
					if fx != null: fx.impact(at, AQUA, 3.0, 0.0, false)
		"ring":
			if once(view, key): game.sfx.play_at("growl", head, 2.0, 0.6)
			for n in range(Poseidon.ring_count(event)):
				if age >= Poseidon.RING_WINDUP*pace+n*Poseidon.RING_SECOND and once_tag(view, "ring%d"%n, key):
					game.sfx.play_at("tide_crash", world(Poseidon.ring_center(event), 0.2), 6.0, 1.1)
					game.sfx.play_at("punch_heavy", world(Poseidon.ring_center(event), 0.2), 4.0, 0.5)
					if hazard_fx != null: hazard_fx.slam(world(Poseidon.ring_center(event), 0.1), 8.0)
		"channel":
			if once(view, key):
				game.sfx.play_at("boss_rumble", base, 2.0, 1.0)
				game.sfx.play("warning", -4.0, 0.9)
			if Poseidon.tsunami_warning(run, event) and once_tag(view, "warn", key): game.sfx.play("warning", -2.0, 0.8)
			var launch: float = run.elapsed-float(event.get("bolt_at", -10.0))
			if launch >= 0.0 and launch < 0.05 and once_tag(view, "bolt_launch", "%d:%d"%[event.skill_seq, int(event.bolt_seq)]):
				game.sfx.play_at("whoosh", left_hand(god), 2.0, 1.3)
		"tsunami":
			if once(view, key):
				game.sfx.play_at("tide_crash", base, 10.0, 0.7)
				game.sfx.play("tide_crash", -2.0, 0.8)
				if hazard_fx != null: hazard_fx.slam(base, 16.0)
				if fx != null: fx.impact(base, AQUA, 20.0, 0.0)

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
	fill.color = Color("bff6ff") if exposed else Color("3aa7c9")
	frame.get_node("Back").size.x = width
	var lag: ColorRect = frame.get_node("Lag")
	var shown: float = move_toward(float(view.get_meta("bar_lag", ratio)), ratio, game.frame_delta*0.25)
	view.set_meta("bar_lag", shown)
	lag.size.x = (width-4)*maxf(shown, ratio)
	var title: Label = frame.get_node("Title")
	title.size.x = width
	var status := "  ·  海神之心暴露！" if exposed else "  ·  神甲（伤害 25%）"
	title.text = "%s · 第 %d 阶段%s"%[Poseidon.NAME, event.stage+1, status]
	if dead: title.text = "%s 已沉入深潭"%Poseidon.NAME

# —— 入场 ——

static func intro_age(run, event: Dictionary) -> float:
	if event.phase == "dormant": return -1.0
	if event.phase == "intro": return run.elapsed-event.state_at
	return Poseidon.INTRO+1.0

static func shot(eye: Vector3, look: Vector3) -> Transform3D:
	var dir := (look-eye).normalized()
	return Transform3D.IDENTITY.translated(eye).looking_at(look, Vector3.UP if absf(dir.y) < 0.97 else Vector3.BACK)

static func ease01(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))

# 返回 {transform, fov}：从旅程镜头转向深潭 → 低机位推近翻涌的潭心 → 海神破水升起时仰拍跟上 → 举矛雷光正面仰拍 → 顿矛远景 → 落在 Boss 战镜头。
static func intro_camera(game, event: Dictionary, home: Transform3D, game_shot: Transform3D) -> Dictionary:
	var run = game.run
	var t: float = run.elapsed-event.state_at
	var perch_z: float = -float(event.perch.y)/SCALE
	var players_z: float = -minf(run.a.position.y, run.b.position.y)/SCALE
	var pose: Dictionary = Poseidon.body_pose(run, event, run.elapsed)
	var chest_y: float = float(pose.alt)/SCALE+SIZE*0.68
	var watch := shot(Vector3(0, 6.0, players_z+10.0), Vector3(0, 1.0, perch_z))
	var low_from := shot(Vector3(6.0, 2.2, perch_z+34.0), Vector3(0, 1.0, perch_z))
	var low_to := shot(Vector3(4.0, 1.8, perch_z+26.0), Vector3(0, 1.5, perch_z))
	var result: Dictionary
	if t < Poseidon.INTRO_STIR:
		var k := ease01(t/Poseidon.INTRO_STIR)
		result = {"transform":home.interpolate_with(watch, k), "fov":lerpf(57.0, 60.0, k)}
	elif t < Poseidon.INTRO_RISE:
		var k := ease01((t-Poseidon.INTRO_STIR)/(Poseidon.INTRO_RISE-Poseidon.INTRO_STIR))
		result = {"transform":watch.interpolate_with(low_from, ease01(k*2.0)).interpolate_with(low_to, ease01(k*2.0-1.0)), "fov":58.0}
	elif t < Poseidon.INTRO_RAISE:
		var k := ease01((t-Poseidon.INTRO_RISE)/(Poseidon.INTRO_RAISE-Poseidon.INTRO_RISE))
		var follow := shot(Vector3(4.0, 1.8, perch_z+26.0+k*4.0), Vector3(0, maxf(1.5, chest_y*0.9), perch_z))
		result = {"transform":follow, "fov":lerpf(58.0, 62.0, k)}
	elif t < Poseidon.INTRO_SLAM:
		var k := ease01((t-Poseidon.INTRO_RAISE)/(Poseidon.INTRO_SLAM-Poseidon.INTRO_RAISE))
		var from := shot(Vector3(-3.0, 2.0, perch_z+24.0), Vector3(0, chest_y+1.0, perch_z))
		var to := shot(Vector3(-2.0, 1.6, perch_z+20.0), Vector3(0, chest_y+3.0, perch_z))
		result = {"transform":from.interpolate_with(to, k), "fov":54.0}
	elif t < Poseidon.INTRO-Poseidon.RETURN_TIME:
		var k := ease01((t-Poseidon.INTRO_SLAM)/(Poseidon.INTRO-Poseidon.RETURN_TIME-Poseidon.INTRO_SLAM))
		var from := shot(Vector3(-2.0, 1.6, perch_z+20.0), Vector3(0, chest_y+3.0, perch_z))
		var wide := shot(Vector3(8.0, 7.0, perch_z+44.0), Vector3(0, chest_y*0.6, perch_z))
		result = {"transform":from.interpolate_with(wide, k), "fov":lerpf(54.0, 60.0, k)}
	else:
		var k := ease01((t-(Poseidon.INTRO-Poseidon.RETURN_TIME))/Poseidon.RETURN_TIME)
		var wide := shot(Vector3(8.0, 7.0, perch_z+44.0), Vector3(0, chest_y*0.6, perch_z))
		result = {"transform":wide.interpolate_with(game_shot, k), "fov":lerpf(60.0, 62.0, k)}
	var amount := intro_shake(t)
	if amount > 0.0:
		var e: float = run.elapsed
		var offset := Vector3(sin(e*41.0)+sin(e*67.0)*0.5, sin(e*53.0+1.3)+sin(e*29.0)*0.4, 0.0)*amount*0.5
		var xform: Transform3D = result.transform
		xform.origin += xform.basis*offset
		xform.basis = xform.basis*Basis(Vector3.FORWARD, sin(e*37.0)*amount*0.02)
		result.transform = xform
	return result

# 震动：潭水翻涌时轻颤，破水升起猛震，雷光一抖，顿矛最强。
static func intro_shake(t: float) -> float:
	if t < 0.0: return 0.0
	var amount := 0.0
	if t >= Poseidon.INTRO_STIR and t < Poseidon.INTRO_RISE: amount = 0.15+0.25*ease01((t-Poseidon.INTRO_STIR)/(Poseidon.INTRO_RISE-Poseidon.INTRO_STIR))
	if t >= Poseidon.INTRO_RISE: amount = maxf(amount, 1.2*exp(-(t-Poseidon.INTRO_RISE-0.1)*2.0))
	var strike: float = Poseidon.INTRO_RAISE+0.8
	if t >= strike: amount = maxf(amount, 0.6*exp(-(t-strike)*5.0))
	var slam: float = Poseidon.INTRO_SLAM+0.4
	if t >= slam: amount = maxf(amount, 1.4*exp(-(t-slam)*3.0))
	return amount

static func intro(game, view: Node3D, god: Node3D, event: Dictionary) -> void:
	var run = game.run
	var t := intro_age(run, event)
	var layer: CanvasLayer = view.get_node("Cinema")
	var center := world(event.perch, 0.2)
	var fx = game.get("fx")
	var hazard_fx = game.get("hazard_fx")
	var key := "%.3f"%event.trigger
	var skipped: bool = event.get("intro_skipped", false)
	if event.phase == "dormant":
		for tag in ["intro_rumble", "intro_rise", "intro_strike", "intro_slam", "intro_cry"]:
			view.remove_meta("fx_" + tag)
	var churning: bool = event.phase == "intro" and t >= Poseidon.INTRO_STIR and t < Poseidon.INTRO_RISEN and run.state == "running" and not skipped
	game.sfx.loop_at("poseidon_churn", "water_jet_loop", churning, center, 2.0, 0.55)
	var tsunami: MeshInstance3D = view.get_node("Tsunami")
	if event.phase == "intro":
		# 顿矛后一圈水环从潭心扩散（纯画面）。
		var slam_age: float = t-(Poseidon.INTRO_SLAM+0.4)
		DragonView.set_ring(tsunami, center, slam_age*32.0 if slam_age > 0.0 and slam_age < 1.6 else -1.0, 1.2, 1.0-clampf(slam_age/1.6, 0, 1))
	if t < 0.0 or t > Poseidon.INTRO+0.5:
		layer.visible = false
		return
	if t >= 0.2 and once_tag(view, "intro_rumble", key) and not skipped:
		game.sfx.play("boss_rumble", -6.0, 0.8)
	if t >= Poseidon.INTRO_RISE+0.1 and once_tag(view, "intro_rise", key) and not skipped:
		game.sfx.play_at("tide_crash", center, 10.0, 0.75)
		game.sfx.play("water_splash", -4.0, 0.7)
		var burst: GPUParticles3D = view.get_node("Burst")
		burst.global_position = center
		burst.restart()
		if fx != null: fx.impact(center, AQUA, 14.0, 0.0, false)
		if hazard_fx != null: hazard_fx.slam(center, 12.0)
	if t >= Poseidon.INTRO_RISE and t < Poseidon.INTRO_RISEN and fx != null and int(run.elapsed/run.FIXED_STEP)%3 == 0:
		var spin: float = run.elapsed*7.0
		fx.burst("dust", center+Vector3(cos(spin)*6.0, 0, sin(spin)*6.0))
	if t >= Poseidon.INTRO_RAISE+0.8 and once_tag(view, "intro_strike", key) and not skipped:
		view.set_meta("strike_at", run.elapsed)
		game.sfx.play("thunder", 0.0, 0.9)
		game.sfx.play_at("boss_roar", bone_point(god, "Head"), 8.0, 0.8)
	if t >= Poseidon.INTRO_SLAM+0.4 and once_tag(view, "intro_slam", key) and not skipped:
		game.sfx.play_at("tide_crash", center, 10.0, 0.9)
		game.sfx.play("tide_crash", -6.0, 1.0)
		if hazard_fx != null: hazard_fx.slam(center, 16.0)
		if fx != null: fx.impact(center, AQUA, 18.0, 0.0, false)
	# 登场必有声：跳过时在交还镜头那一刻补一声。
	if t >= Poseidon.INTRO-Poseidon.RETURN_TIME and once_tag(view, "intro_cry", key):
		game.sfx.play("boss_roar", -4.0, 0.8)
	layer.visible = event.phase == "intro" and run.state in ["running", "paused"]
	if not layer.visible: return
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var bars := ease01(t/0.6)*(1.0-ease01((t-(Poseidon.INTRO-0.7))/0.7))
	var bar_height := size.y*0.12*bars
	var top: ColorRect = layer.get_node("Top")
	var bottom: ColorRect = layer.get_node("Bottom")
	top.position = Vector2.ZERO
	top.size = Vector2(size.x, bar_height)
	bottom.position = Vector2(0, size.y-bar_height)
	bottom.size = Vector2(size.x, bar_height)
	var title := ease01((t-(Poseidon.INTRO_RAISE+0.8))/0.5)*(1.0-ease01((t-(Poseidon.INTRO_SLAM+1.0))/0.6))
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
	skip.modulate.a = 0.0 if t < Poseidon.INTRO_SKIP_AFTER or t > Poseidon.INTRO-Poseidon.RETURN_TIME else bars
