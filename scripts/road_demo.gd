extends Node3D

signal online_frame_applied(frame_index: int)

const Run = preload("res://scripts/road_run.gd")
const RelayPowerView = preload("res://scripts/relay_power_view.gd")
const SCALE := 20.0
const SKY_YAW := 240.0
# 可见路面比可站立范围每侧多 0.3 米：角色中心到边即踩空。
const ROAD_HALF := Run.EDGE / SCALE + 0.3
# 缺口岩壁向下 6 米后敞开，再往下 28 米是与路外相同的云海（坠落角色先穿过可见空间再没入云中）；窄桥桥面只露出一米厚的石板。
const GAP_DEPTH := 6.0
const PLANK_THICKNESS := 1.0
var run = Run.new(true, true)
var road := Node3D.new()
var camera := Camera3D.new()
var robots: Array[Node3D] = []
# 旧版方条绳索的节点池已由 rope_view 取代；保留空数组供历史测试读取。
var cable_parts: Array[MeshInstance3D] = []
var hud: Label
var distance_label: Label
var panel: PanelContainer
var title: Label
var subtitle: Label
var primary: Button
var animation_players: Array[AnimationPlayer] = []
var shadows: Array[MeshInstance3D] = []
var blocked_keys: Array[int] = []
var failed_animation_started := [false, false]
var rope_sound_time := -10.0
var rope_sound_bound := [true,true]
var hazard_views: Array[Node3D] = []
var last_actions := ["Idle", "Idle"]
# 仅供表现：救援时每次按键的拉拽/攀爬抖动，逐帧衰减。
# 保留历史夹具的属性接口；生产入口只接收两名真人输入。
var solo := false
var rescue_pulse := [0.0, 0.0]
var rescue_seen := [0, 0]
var view_revision := -1
var generation_waiting := false
var loading_box: Control
var loading_label: Label
var loading_progress: ProgressBar
var prepared_online_frame := -1
var hazard_build_count := 0
var preview_runs := {}
const MODEL_POOL_LIMIT := 64
var difficulty_buttons: Array[Button] = []
var hazard_pool := {}
const MOVE_KEYS := [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_SPACE, KEY_ENTER]
var progress_bar: ColorRect
var progress_fill: ColorRect
# 救援提示：谁该狂按什么键、拉起进度和剩余时间。
var rescue_box: Control
var rescue_label: Label
var rescue_fill: ColorRect
var rescue_timer_fill: ColorRect
const RESCUE_BAR := 560.0
var scenery: Array[Node3D] = []
var materials := {}
var cable_material: StandardMaterial3D
var capture_mode := false
var reward_views: Array[Node3D] = []
var finish_view := Node3D.new()
var fall_clock := 0.0
# 失败演出：失败后先运镜展示过程（撞击推近、坠落跟拍），演出结束才弹失败面板。
# 镜头只在失败演出期间移动，跑动中仍固定朝向。
var fail_clock := 0.0
var camera_home := Transform3D()
const FAIL_HIT_SHOW := 1.6
const FAIL_FALL_SHOW := 2.6
var rock_meshes := {}
var support_run_id := 0
var support_revision := -1
var support_gaps: Array[Rect2] = []
var support_mesh_build_count := 0
var support_mesh_cache := {}
const SUPPORT_MESH_CACHE_LIMIT := 128
var mist_layers: Array[StandardMaterial3D] = []
const RopeView = preload("res://scripts/rope_view.gd")
const Sfx = preload("res://scripts/sfx.gd")
var rope_view: MeshInstance3D
var sfx: Node
var frame_delta := 1.0 / 60.0
# 得分栏与金币飞行：拾取时从金币位置飞到右上角得分图标，落到图标上才加分。
var ui_root: Control
var coin_icon: Panel
var score_label: Label
var shown_score := 0
var flying := 0
var announced := {}
var last_claims := 0
var hammer_signs := {}
const NetClient = preload("res://scripts/net_client.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
const NET_CONFIG := "user://online.cfg"
var net: Node
var touch: Control
var touch_device := false
var net_address: LineEdit
var net_button: Button
var net_status: Label
var pause_button: Button
var bottom_hint: Label
var charge_gate_view := Node3D.new()
var charge_gate_views: Array[Node3D] = []
var gate_announced := {}
var charge_announced := false
func material(name: String, color: Color, emission: float = 0.0) -> StandardMaterial3D:
	if materials.has(name):
		return materials[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.75
	if emission > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	materials[name] = m
	return m

# 实拍石材贴图（颜色、法线、粗糙度），按物体自身坐标三向投影，方块和生成的岩体都不用展 UV。
func tex_material(name: String, texture: String, scale: float, tint: Color = Color.WHITE) -> StandardMaterial3D:
	if materials.has(name): return materials[name]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/env/%s_diff.jpg" % texture)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load("res://assets/env/%s_nor.jpg" % texture)
	m.roughness_texture = load("res://assets/env/%s_rough.jpg" % texture)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	materials[name] = m
	return m

# 用噪声把圆柱或圆球推成凹凸不平的岩体：column 为上细下粗的石峰，round 为卵形巨石，flat 顶面是平台。
func rock_mesh(key: String, seed_value: int, bottom: float, top: float, height: float, lump: float, shape: String = "column") -> ArrayMesh:
	if rock_meshes.has(key): return rock_meshes[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.0
	var rings := 16
	var segments := 16
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drift := Vector2.ZERO
	for ring in range(rings + 1):
		var t := float(ring) / rings
		var y := height * t
		var radius := lerpf(bottom, top, pow(t, 0.7))
		if shape == "round": radius = bottom * sin(PI * (0.06 + 0.9 * t))
		drift = Vector2(noise.get_noise_2d(y * 0.03, 11.0), noise.get_noise_2d(y * 0.03, 47.0)) * bottom * (0.0 if shape == "round" else 0.28)
		for segment in range(segments):
			var angle := TAU * segment / segments
			var dir := Vector2(cos(angle), sin(angle))
			var bump := noise.get_noise_3d(dir.x * 0.9 + seed_value, y * 0.06 / maxf(0.2, bottom / 5.0), dir.y * 0.9) + 0.5 * noise.get_noise_3d(dir.x * 2.6, y * 0.2, dir.y * 2.6 + seed_value)
			var r := radius * (1.0 + lump * bump * 1.6)
			tool.add_vertex(Vector3(dir.x * r + drift.x, y, dir.y * r + drift.y))
	tool.add_vertex(Vector3(drift.x, height + (0.0 if shape == "flat" else top * 0.5), drift.y))
	for ring in range(rings):
		for segment in range(segments):
			var a := ring * segments + segment
			var b := ring * segments + (segment + 1) % segments
			var c := a + segments
			var d := b + segments
			for index in [a, b, c, b, d, c]: tool.add_index(index)
	var cap := (rings + 1) * segments
	for segment in range(segments):
		for index in [rings * segments + segment, rings * segments + (segment + 1) % segments, cap]: tool.add_index(index)
	tool.generate_normals()
	rock_meshes[key] = tool.commit()
	return rock_meshes[key]

func rock(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, size: float = 1.0, yaw: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	instance.scale = Vector3.ONE * size
	instance.rotation.y = yaw
	parent.add_child(instance)
	return instance

# 地面危险区：半透明、不受光照，压在路面上仍看得见下面的车道线。
# 缺口内壁与路外崖壁同材质；内壁整天处在路面阴影里，不接收阴影以免变成黑洞。
func gap_wall_material() -> StandardMaterial3D:
	if materials.has("gap_wall_lit"): return materials["gap_wall_lit"]
	var m: StandardMaterial3D = tex_material("cliff_face", "rock_face_03", 0.11, Color("a89a90")).duplicate()
	m.disable_receive_shadows = true
	# 黄昏逆光下缺口远壁正对镜头背光，补一点同色自发光保留岩石纹理。
	m.emission_enabled = true
	m.emission_texture = m.albedo_texture
	m.emission = Color("a89a90")
	m.emission_energy_multiplier = 0.12
	materials["gap_wall_lit"] = m
	return m

# 缺口下方的云海：复用背景云层纹理，不受路面阴影压暗，颜色与路外云海一致。
func gap_mist_material() -> StandardMaterial3D:
	if materials.has("gap_mist"): return materials["gap_mist"]
	var m: StandardMaterial3D = mist_layers[0].duplicate() if not mist_layers.is_empty() else StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	m.albedo_color = Color("8d86a0")
	materials["gap_mist"] = m
	return m

func zone_material(name: String, color: Color) -> StandardMaterial3D:
	var m := material(name, color)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	parent.add_child(instance)
	return instance

func model(path: String, parent: Node3D, pos: Vector3, height: float, yaw: float = 0.0, width_limit: float = 8.0) -> Node3D:
	var instance: Node3D = load(path).instantiate()
	parent.add_child(instance)
	var bounds := model_bounds(instance, instance)
	var factor := height / maxf(bounds.size.y, 0.01)
	if "industrial" in path:
		factor = minf(factor, width_limit / maxf(bounds.size.x, bounds.size.z))
	instance.scale = Vector3.ONE * factor
	instance.position = pos - Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
	instance.rotation.y = yaw
	if "industrial" in path:
		apply_industrial_palette(instance)
	return instance

func apply_industrial_palette(node: Node) -> void:
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var original = node.mesh.surface_get_material(surface)
			if original is StandardMaterial3D:
				var mat: StandardMaterial3D = original.duplicate()
				mat.albedo_texture = load("res://assets/industrial/Textures/colormap.png")
				mat.albedo_color = Color("92a6b0")
				mat.roughness = 0.85
				node.set_surface_override_material(surface, mat)
	for child in node.get_children():
		apply_industrial_palette(child)

func model_bounds(root: Node3D, node: Node) -> AABB:
	var bounds := AABB()
	if node is MeshInstance3D:
		bounds = (root.global_transform.affine_inverse() * node.global_transform) * node.get_aabb()
	for child in node.get_children():
		var sub := model_bounds(root, child)
		if sub.size != Vector3.ZERO:
			bounds = sub if bounds.size == Vector3.ZERO else bounds.merge(sub)
	return bounds

# Blender 生成的救援动作（tools/blender/make_rescue_anims.py）：与冒险者共用骨架路径。
const RESCUE_CLIPS := {"RopePull": "res://assets/humans/rescue_ropepull.glb", "Climb": "res://assets/humans/rescue_climb.glb"}
var rescue_clips := {}

func add_rescue_clips(player: AnimationPlayer) -> void:
	if rescue_clips.is_empty():
		for clip in RESCUE_CLIPS:
			var scene: PackedScene = load(RESCUE_CLIPS[clip])
			if scene == null: continue
			var root := scene.instantiate()
			var source: Array = root.find_children("*", "AnimationPlayer", true, false)
			if not source.is_empty() and not source[0].get_animation_list().is_empty():
				var anim: Animation = source[0].get_animation(source[0].get_animation_list()[0]).duplicate()
				anim.loop_mode = Animation.LOOP_LINEAR
				rescue_clips[clip] = anim
			root.free()
	var library: AnimationLibrary = player.get_animation_library("")
	if library == null: return
	for clip in rescue_clips:
		if not library.has_animation(clip): library.add_animation(clip, rescue_clips[clip])

# 两只手腕骨骼的世界坐标中点；找不到骨架时退回胸口高度。
var hand_skeletons := {}

func hand_point(i: int) -> Vector3:
	var fallback: Vector3 = robots[i].position + Vector3(0, 1.4, 0)
	if not hand_skeletons.has(i):
		var found: Array = robots[i].find_children("*", "Skeleton3D", true, false)
		hand_skeletons[i] = found[0] if not found.is_empty() else null
	var skeleton: Skeleton3D = hand_skeletons[i]
	if skeleton == null or not is_instance_valid(skeleton): return fallback
	var sum := Vector3.ZERO
	var count := 0
	for bone_name in ["Wrist.L", "Wrist.R"]:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			sum += skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			count += 1
	return sum / count if count > 0 else fallback

func register_animation(node: Node) -> void:
	if node is AnimationPlayer:
		animation_players.append(node)
		add_rescue_clips(node)
		for name in node.get_animation_list():
			if name.ends_with("Idle") or name.ends_with("Run") or name.ends_with("Interact") or name.ends_with("HitRecieve_2"):
				node.get_animation(name).loop_mode = Animation.LOOP_LINEAR
		node.animation_finished.connect(func(name):
			if name.contains("HitRecieve") and run.state == "failed":
				play_action(node, "Death"))
	for child in node.get_children():
		register_animation(child)

func run_animation_speed() -> float:
	# 普通第一关为 1.3 倍，仅 Run 随关速小幅变化，跳跃仍由物理高度驱动。
	return clampf(run.speed() / 150.0, 1.3, 2.2)

# 冒险者动画没有 Jump 和 HitRecieve_1：腾空用翻滚，受击用 HitRecieve。
const ACTION_FALLBACK := {"Jump": "Roll", "HitRecieve_1": "HitRecieve"}
# 纯预警表现节点：不属于机关或道具本体，同步时统一隐藏。
const WARNING_NODES := ["WarningLabel", "WarningFootprint", "FlightRoute", "TrajectoryCorridor", "LaunchMarker",
	"HammerZone", "GapApproach", "GapNear", "GapFar", "GapNearInner", "GapFarInner", "GapLeftRim", "GapRightRim"]

func play_action(player: AnimationPlayer, action: String) -> void:
	for wanted in [action, ACTION_FALLBACK.get(action, action)]:
		for name in player.get_animation_list():
			if name.ends_with(wanted):
				if player.current_animation != name:
					player.play(name, 0.1)
				return

func _ready() -> void:
	# 使用随项目分发的中文字体，覆盖桌面默认字体缺字及 Label3D。
	ThemeDB.fallback_font=preload("res://assets/fonts/web_ui_font.tres")
	capture_mode = "--capture-demo" in OS.get_cmdline_user_args()
	# 每次开局、重试、进下一关都换新种子：段落顺序、左右、散布陷阱和奖励每次都不一样。
	randomize()
	run.random_seed = true
	run.charge_tutorial = true
	run.retry()
	run.state = "start"
	sfx = Sfx.new()
	add_child(sfx)
	touch_device = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	net = NetClient.new()
	net.name = "Net"
	add_child(net)
	net.status_changed.connect(on_net_status)
	net.match_started.connect(start_online_match)
	net.match_stopped.connect(stop_online_match)
	add_child(road)
	build_lighting()
	build_road()
	build_robots()
	build_rewards()
	build_charge_gate()
	build_ui()
	sync_view()

func _exit_tree() -> void:
	for preview in preview_runs.values(): preview.dispose()
	run.dispose()

func build_lighting() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	# 实拍黄昏天空全景图同时提供背景和环境光，转到让晚霞最亮的一侧落在道路前方。
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/env/belfast_sunset_puresky_2k.hdr")
	sky_mat.energy_multiplier = 0.36
	sky.sky_material = sky_mat
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(SKY_YAW), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 2.0
	# 深度雾把远处石峰推远；高度雾让崖底沉进云海，看不到底。
	env.fog_enabled = true
	env.fog_light_color = Color("4a4660")
	env.fog_density = 0.0026
	env.fog_height = -10.0
	env.fog_height_density = 0.06
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	# 低角度暖色侧逆光：岩石和人物有亮边，影子拉长。
	sun.rotation_degrees = Vector3(-24, 122, 0)
	sun.light_color = Color("ffb37a")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140
	add_child(sun)
	# 路面加宽到 32 米后镜头抬高后移，两侧路边（含后退 5 米时）仍在 16:9 画面内；仍固定朝向。
	camera.position = Vector3(0, 11.5, 22.0)
	camera.fov = 62
	camera.far = 450
	add_child(camera)
	camera.look_at(Vector3(0, 1.2, -22))
	camera.current = true
	camera_home = camera.transform

func build_road() -> void:
	# 悬空山脊：没有护栏的古石板路，两侧是崖壁、孤峰和云海。路面宽度与可站立范围同源。
	var paving := tex_material("ridge_paving", "monastery_stone_floor", 0.25, Color("b3aaa0"))
	var cliff := tex_material("cliff_face", "rock_face_03", 0.11, Color("a89a90"))
	var boulder := tex_material("cliff_boulder", "rock_boulder_dry", 0.22, Color("9c8f84"))
	var far_rock := tex_material("far_rock", "rock_face_03", 0.05, Color("6f6a78"))
	var seam_mat := material("ridge_seam", Color("332d28"))
	var moss := zone_material("ridge_moss", Color(0.13, 0.17, 0.08, 0.32))
	var edge_mat := material("ridge_edge", Color("d9cfb8"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261013
	for n in range(6): rock_mesh("spire_%d" % n, 40 + n, rng.randf_range(5.0, 9.0), rng.randf_range(1.2, 3.6), rng.randf_range(52.0, 86.0), 0.2)
	for n in range(4): rock_mesh("buttress_%d" % n, 60 + n, rng.randf_range(3.6, 5.6), rng.randf_range(1.8, 3.0), rng.randf_range(24.0, 40.0), 0.24)
	for n in range(3): rock_mesh("island_%d" % n, 80 + n, rng.randf_range(4.0, 5.5), rng.randf_range(3.6, 4.6), 62.0, 0.16, "flat")
	for n in range(4): rock_mesh("boulder_%d" % n, 100 + n, 1.0, 1.0, 1.5, 0.22, "round")
	var trees := ["DeadTree_A", "DeadTree_B", "Pine", "Pine"]
	# 地貌分段：每 9 段（72 米）换一种山脊风貌，63 段循环内依次出现石板山脊、松林、遗迹回廊、赤岩荒脊。
	# 只换路面色调和路外装饰，路面宽度、高度与碰撞完全不变。
	var zone_paving := [
		paving,
		tex_material("forest_paving", "monastery_stone_floor", 0.25, Color("8f9a7e")),
		tex_material("ruin_paving", "monastery_stone_floor", 0.18, Color("c9b48f")),
		tex_material("badland_paving", "rock_boulder_dry", 0.2, Color("b98a6a")),
	]
	var zone_moss := [moss, zone_material("forest_moss", Color(0.12, 0.22, 0.06, 0.5)), moss, zone_material("badland_dust", Color(0.35, 0.18, 0.08, 0.3))]
	var ruin_stone := tex_material("ruin_stone", "monastery_stone_floor", 0.4, Color("d8c8a8"))
	for i in range(-2, 61):
		var chunk := Node3D.new()
		road.add_child(chunk)
		chunk.position.z = -i * 8.0
		chunk.set_meta("road_slot", i + 2)
		var zone: int = ((i + 2) / 9) % 4
		chunk.set_meta("zone", zone)
		scenery.append(chunk)
		var surface := box(chunk, Vector3(0, -0.25, 0), Vector3(ROAD_HALF * 2, 0.5, 8), zone_paving[zone])
		surface.name = "SupportSurface"
		surface.set_meta("original_mesh", surface.mesh)
		var seam := box(chunk, Vector3(0, 0.005, 3.95), Vector3(ROAD_HALF * 2 - 0.4, 0.02, 0.1), seam_mat)
		seam.set_meta("road_overlay", true)
		# 石缝里的苔斑和零星裂缝，跑动时脚下有东西掠过；没有碰撞。
		for n in range(3):
			var patch := cylinder(chunk, Vector3(rng.randf_range(-ROAD_HALF + 1.2, ROAD_HALF - 1.2), 0.008, rng.randf_range(-3.2, 3.2)), 1.0, 0.012, zone_moss[zone])
			patch.scale = Vector3(rng.randf_range(0.4, 1.3), 1, rng.randf_range(0.3, 0.9))
			patch.rotation.y = rng.randf_range(0, PI)
			patch.set_meta("road_overlay", true)
		var crack := box(chunk, Vector3(rng.randf_range(-ROAD_HALF * 0.6, ROAD_HALF * 0.6), 0.006, rng.randf_range(-3, 3)), Vector3(rng.randf_range(2.0, 6.0), 0.02, 0.06), seam_mat)
		crack.rotation.y = rng.randf_range(-0.4, 0.4)
		crack.set_meta("road_overlay", true)
		# 岩体顶面低于缺口坑底，缺口处向下看是黑洞而不是浅台阶。
		box(chunk, Vector3(0, -33.2, 0), Vector3(ROAD_HALF * 2 - 1.6, 60, 8), cliff).name = "CliffBody"
		for side in [-1, 1]:
			var rim := box(chunk, Vector3(side * (ROAD_HALF - 0.12), 0.012, 0), Vector3(0.2, 0.02, 8), edge_mat)
			rim.set_meta("road_overlay", true)
			box(chunk, Vector3(side * (ROAD_HALF - 0.45), -1.85, 0), Vector3(0.9, 2.7, 8), cliff).name = "EdgeWallLeft" if side < 0 else "EdgeWallRight"
			# 崖壁不是一堵平墙：每段两根贴壁的扶壁岩柱，顶端参差地停在路面以下。
			for z in [-2.0, 2.0]:
				var buttress: Mesh = rock_meshes["buttress_%d" % rng.randi_range(0, 3)]
				rock(chunk, buttress, cliff, Vector3(side * (ROAD_HALF + rng.randf_range(-0.6, 1.2)), -rng.randf_range(1.2, 6.0) - buttress.get_aabb().size.y, z + rng.randf_range(-1, 1)), 1.0, rng.randf_range(0, TAU))
			# 路沿半埋的碎石，偶尔有草从石缝里长出来。
			for n in range(3):
				var pebble := rock(chunk, rock_meshes["boulder_%d" % rng.randi_range(0, 3)], boulder, Vector3(side * (ROAD_HALF + rng.randf_range(-0.05, 0.35)), -0.35, rng.randf_range(-3.8, 3.8)), rng.randf_range(0.28, 0.55), rng.randf_range(0, TAU))
				pebble.scale.y *= 0.7
			if rng.randf() < 0.4:
				model("res://assets/decor/TallGrass.glb", chunk, Vector3(side * (ROAD_HALF - 0.05), 0, rng.randf_range(-3.5, 3.5)), rng.randf_range(0.5, 0.9), rng.randf_range(0, TAU))
			# 从崖壁斜着长出来的松树和枯树。
			if rng.randf() < 0.45:
				var tree := model("res://assets/decor/%s.glb" % trees[rng.randi_range(0, 3)], chunk, Vector3(side * (ROAD_HALF + 1.4), -rng.randf_range(6.0, 16.0), rng.randf_range(-3, 3)), rng.randf_range(5.0, 8.0), rng.randf_range(0, TAU))
				tree.rotation.z = -side * rng.randf_range(0.35, 0.7)
			# 两侧云海里升起的孤峰，只作远近参照，够不着也站不上去。隔段出现，疏密不一。
			if rng.randf() < 0.4:
				var spire: Mesh = rock_meshes["spire_%d" % rng.randi_range(0, 5)]
				rock(chunk, spire, cliff, Vector3(side * rng.randf_range(32.0, 95.0), -64.0 + rng.randf_range(-10.0, 4.0), rng.randf_range(-3, 3)), rng.randf_range(0.8, 1.3), rng.randf_range(0, TAU))
		# 每隔几段在路外七八米处立一座平顶石台，上面是残柱、拱门、旗帜和火把；与路面之间隔着深渊。
		if i >= 0 and i % 3 == 0:
			build_ruin_island(chunk, -1.0 if (i / 3) % 2 == 0 else 1.0, rng, cliff)
		build_zone_decor(chunk, zone, i, boulder, ruin_stone)
	build_backdrop(far_rock)

# 各地貌段的路外装饰。全部落在路沿以外的崖边岩台上，不进入可站立范围，也没有碰撞。
# 用独立随机种子，避免改变原有山脊装饰的排布。
func build_zone_decor(chunk: Node3D, zone: int, slot: int, boulder: Material, ruin_stone: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + slot
	for side in [-1, 1]:
		var outer: float = side * (ROAD_HALF + 0.9)
		match zone:
			1:
				# 松林：崖边岩台上成排的松树和灌木，路沿草更密。
				for z in [-2.5, 1.5]:
					var ledge := rock(chunk, rock_meshes["boulder_%d" % rng.randi_range(0, 3)], boulder, Vector3(outer + side * rng.randf_range(0.4, 1.0), -1.1, z), rng.randf_range(1.4, 1.9), rng.randf_range(0, TAU))
					ledge.scale.y *= 0.55
					model("res://assets/decor/Pine.glb", chunk, Vector3(outer + side * rng.randf_range(0.6, 1.4), -0.4, z + rng.randf_range(-0.6, 0.6)), rng.randf_range(4.5, 7.5), rng.randf_range(0, TAU))
				model("res://assets/decor/Bush.glb", chunk, Vector3(outer + side * 0.3, -0.25, rng.randf_range(-3.5, 3.5)), rng.randf_range(0.9, 1.4), rng.randf_range(0, TAU))
				model("res://assets/decor/TallGrass.glb", chunk, Vector3(side * (ROAD_HALF - 0.05), 0, rng.randf_range(-3.5, 3.5)), rng.randf_range(0.6, 1.0), rng.randf_range(0, TAU))
			2:
				# 遗迹回廊：路两侧的石基残柱，隔段一座火把，偶尔一根断柱斜倒在崖边。
				box(chunk, Vector3(outer + side * 0.5, -0.45, 0), Vector3(1.4, 1.0, 7.6), ruin_stone)
				var column := model("res://assets/decor/%s.glb" % ("Column" if rng.randf() < 0.65 else "ColumnRound"), chunk, Vector3(outer + side * 0.5, 0.05, rng.randf_range(-1.5, 1.5)), rng.randf_range(3.2, 5.0), rng.randf_range(0, TAU))
				if rng.randf() < 0.3: column.rotation.z = side * rng.randf_range(0.2, 0.45)
				if slot % 2 == 0 and side > 0 or slot % 2 != 0 and side < 0:
					var torch_spot := Vector3(outer + side * 0.6, 0.05, -3.0)
					model("res://assets/decor/Torch.glb", chunk, torch_spot, 1.8)
					box(chunk, torch_spot + Vector3(0, 1.95, 0), Vector3(0.18, 0.24, 0.18), material("torch_flame", Color("ffb347"), 3.0))
				if rng.randf() < 0.35:
					model("res://assets/decor/Banner.glb", chunk, Vector3(outer + side * 0.6, 0.05, 2.6), rng.randf_range(3.0, 3.8), PI / 2 * side)
			3:
				# 赤岩荒脊：路沿堆着风化巨石，枯树从石堆里伸出来。
				for n in range(2):
					var heap := rock(chunk, rock_meshes["boulder_%d" % rng.randi_range(0, 3)], boulder, Vector3(outer + side * rng.randf_range(0.3, 1.2), -0.6, rng.randf_range(-3.4, 3.4)), rng.randf_range(1.0, 1.8), rng.randf_range(0, TAU))
					heap.scale.y *= rng.randf_range(0.6, 0.95)
				if rng.randf() < 0.55:
					var dead := model("res://assets/decor/%s.glb" % ("DeadTree_A" if rng.randf() < 0.5 else "DeadTree_B"), chunk, Vector3(outer + side * 1.0, -0.2, rng.randf_range(-2.5, 2.5)), rng.randf_range(3.5, 5.5), rng.randf_range(0, TAU))
					dead.rotation.z = -side * rng.randf_range(0.05, 0.3)

func build_ruin_island(chunk: Node3D, side: float, rng: RandomNumberGenerator, cliff: Material) -> void:
	var island := Node3D.new()
	island.position = Vector3(side * (ROAD_HALF + rng.randf_range(8.0, 12.0)), rng.randf_range(-1.0, 1.5), rng.randf_range(-2, 2))
	chunk.add_child(island)
	rock(island, rock_meshes["island_%d" % rng.randi_range(0, 2)], cliff, Vector3(0, -62.0, 0), 1.0, rng.randf_range(0, TAU))
	var picks := ["Column", "Column", "ColumnRound", "ArchRound", "Banner", "Torch", "DeadTree_A", "Bush", "TallGrass", "Pine"]
	var heights := {"Column": 5.5, "ColumnRound": 2.2, "ArchRound": 5.0, "Banner": 4.5, "Torch": 2.4, "DeadTree_A": 6.0, "Bush": 1.2, "TallGrass": 1.0, "Pine": 6.5}
	for n in range(rng.randi_range(2, 4)):
		var name: String = picks[rng.randi_range(0, picks.size() - 1)]
		var spot := Vector3(rng.randf_range(-2.2, 2.2), 0, rng.randf_range(-2.2, 2.2))
		var prop := model("res://assets/decor/%s.glb" % name, island, spot, heights[name] * rng.randf_range(0.85, 1.15), rng.randf_range(0, TAU))
		if name == "Column" and rng.randf() < 0.4: prop.rotation.z = rng.randf_range(0.15, 0.4)
		if name == "Torch":
			# 火把是场景里唯一的点光源，暖光打在周围的残柱和岩面上。
			var flame := OmniLight3D.new()
			flame.position = spot + Vector3(0, 2.6, 0)
			flame.light_color = Color("ff9a45")
			flame.light_energy = 3.0
			flame.omni_range = 13.0
			island.add_child(flame)
			box(island, flame.position, Vector3(0.22, 0.3, 0.22), material("torch_flame", Color("ffb347"), 3.0))

func build_backdrop(far_rock: Material) -> void:
	# 云海、远山和飘尘不随道路滚动。
	var backdrop := Node3D.new()
	backdrop.name = "AbyssBackdrop"
	add_child(backdrop)
	var mist := material("abyss_mist", Color("4a4660"))
	mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box(backdrop, Vector3(0, -60, -150), Vector3(1600, 0.5, 1100), mist).name = "MistSea"
	# 两层缓慢流动的云雾盖在崖底上方，孤峰从云里穿出来。
	var cloud_noise := FastNoiseLite.new()
	cloud_noise.frequency = 0.006
	cloud_noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 1))
	ramp.set_offset(0, 0.42)
	for layer in range(2):
		var texture := NoiseTexture2D.new()
		texture.noise = cloud_noise
		texture.seamless = true
		texture.color_ramp = ramp
		var cloud := zone_material("mist_layer_%d" % layer, Color(0.78, 0.66, 0.68, 0.5) if layer == 0 else Color(0.62, 0.56, 0.68, 0.42))
		cloud.albedo_texture = texture
		cloud.uv1_scale = Vector3(3, 3, 1)
		cloud.disable_fog = true
		var plane := MeshInstance3D.new()
		plane.mesh = PlaneMesh.new()
		plane.mesh.size = Vector2(900, 900)
		plane.material_override = cloud
		plane.position = Vector3(0, -22.0 - layer * 14.0, -260)
		backdrop.add_child(plane)
		mist_layers.append(cloud)
	# 远处的巨型石峰和两道山脊剪影，被雾压成冷色，拉开纵深。
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for n in range(16):
		var giant: Mesh = rock_meshes["spire_%d" % (n % 6)]
		rock(backdrop, giant, far_rock, Vector3((n - 7.5) * 46.0 + rng.randf_range(-12, 12), -70.0, -250.0 - rng.randf_range(0, 150)), rng.randf_range(2.0, 3.6), rng.randf_range(0, TAU))
	var ridge_noise := FastNoiseLite.new()
	ridge_noise.frequency = 0.012
	ridge_noise.fractal_octaves = 5
	for layer in range(2):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var previous := Vector2.ZERO
		for step in range(101):
			var x := (step - 50) * 18.0
			var top := 20.0 + layer * 34.0 + 70.0 * (ridge_noise.get_noise_2d(x, layer * 500.0) + 0.5 * absf(ridge_noise.get_noise_2d(x * 3.0, 90.0 + layer * 50.0)))
			if step > 0:
				for vertex in [Vector3(previous.x, -60, 0), Vector3(previous.x, previous.y, 0), Vector3(x, top, 0), Vector3(previous.x, -60, 0), Vector3(x, top, 0), Vector3(x, -60, 0)]:
					tool.set_normal(Vector3(0, 0, 1))
					tool.add_vertex(vertex)
			previous = Vector2(x, top)
		var ridge := MeshInstance3D.new()
		ridge.mesh = tool.commit()
		var tone := material("ridge_far_%d" % layer, Color("3a3850") if layer == 0 else Color("4f4a66"))
		tone.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tone.cull_mode = BaseMaterial3D.CULL_DISABLED
		ridge.material_override = tone
		ridge.position = Vector3(0, 0, -400.0 - layer * 40.0)
		backdrop.add_child(ridge)
	# 迎面飘来的火星和尘粒：给速度一个参照，也让空气里有东西。
	var embers := CPUParticles3D.new()
	embers.amount = 110
	embers.lifetime = 5.0
	embers.preprocess = 5.0
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(18, 6, 34)
	embers.direction = Vector3(0.1, 0.12, 1)
	embers.spread = 12.0
	embers.initial_velocity_min = 5.0
	embers.initial_velocity_max = 11.0
	embers.gravity = Vector3(0, 0.4, 0)
	embers.position = Vector3(0, 4, -30)
	var speck := QuadMesh.new()
	speck.size = Vector2(0.035, 0.035)
	var glow := material("ember", Color("ffb066"), 1.6)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	speck.material = glow
	embers.mesh = speck
	backdrop.add_child(embers)

func build_hazard_model(chunk: Node3D, index: int) -> void:
	if run.kinds[index] in Run.Terrain.KINDS:
		build_terrain_model(chunk, index)
		return
	if run.kinds[index] in Run.Industrial.KINDS:
		build_industrial_model(chunk, index)
		return
	if run.kinds[index] in ["sweeper", "road_gap"]:
		build_surface_hazard(chunk, index)
		return
	var rect: Rect2 = run.obstacles[index]
	var kind: String = run.kinds[index]
	var spec: Dictionary = run.hazard_specs[index]
	var bottom: float = spec.bottom / SCALE
	var height: float = (run.obstacle_heights[index] - spec.bottom) / SCALE
	var mat := material("hazard_%d" % index, Color("fa6545"), 0.5).duplicate() as StandardMaterial3D
	if kind in ["scanner", "fly_body"]:
		mat.albedo_color = Color("dd69ef")
	var volume := box(chunk, Vector3(0, bottom + height / 2, 0), Vector3(rect.size.x / SCALE, height, rect.size.y / SCALE), mat)
	volume.name = "DangerVolume"
	if kind == "rail":
		box(chunk, Vector3(0, height - 0.08, 0), Vector3(rect.size.x / SCALE, 0.16, rect.size.y / SCALE), material("rail_stripe", Color("ffe4a1")))
	if kind.begins_with("fly_") or kind == "rocket":
		# 前灯和推进器位于危险包围盒内部，不扩大视觉危险范围。
		box(volume, Vector3(0, 0, rect.size.y / SCALE / 2 + 0.001), Vector3(rect.size.x / SCALE * 0.7, height * 0.15, 0.02), material("flight_light", Color("ffc15c"), 0.8))
		var route := box(chunk, Vector3(0, 0.025, 5), Vector3(rect.size.x / SCALE, 0.02, 10), zone_material("flight_route", Color(1.0, 0.3, 0.12, 0.4)))
		route.name = "FlightRoute"
		var shadow := cylinder(chunk, Vector3(0, 0.015, 0), rect.size.x / SCALE * 0.5, 0.02, material("flight_shadow", Color(0.02, 0.03, 0.04, 1)))
		shadow.name = "ThreatShadow"
		shadow.scale.z = rect.size.y / rect.size.x
	if kind == "rocket":
		# 火箭外形位于同源危险盒内：尖头、机身、两侧尾翼和尾喷口。
		volume.material_override = material("rocket_envelope", Color(0.95, 0.3, 0.15, 0.14))
		volume.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var body := box(chunk, Vector3(0, bottom + height / 2, -0.15), Vector3(0.8, height * 0.7, 2.0), material("rocket_body", Color("8a6a4a")))
		body.name = "RocketBody"
		var nose := cylinder(chunk, Vector3(0, bottom + height / 2, 1.12), 0.36, 0.8, material("rocket_nose", Color("f76749")))
		nose.mesh.top_radius = 0
		nose.rotation.x = PI / 2
		for side in [-1, 1]:
			box(chunk, Vector3(side * 0.65, bottom + height / 2, -1.0), Vector3(0.7, height * 0.25, 0.7), material("rocket_fin", Color("e9e2d2")))
		box(chunk, Vector3(0, bottom + height / 2, -1.45), Vector3(0.5, height * 0.4, 0.25), material("rocket_exhaust", Color("ffae42"), 1.2))
	if kind in ["spikes", "active_spikes"]:
		var envelope := material("spike_envelope_%d" % index, Color(0.95, 0.3, 0.15, 0.12))
		envelope.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		volume.material_override = envelope
		for x in range(8):
			var spike := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0
			cone.bottom_radius = 0.24
			cone.height = height
			spike.mesh = cone
			spike.material_override = mat
			spike.position = Vector3(-rect.size.x / SCALE / 2 + 0.25 + x * 0.5, height / 2, 0)
			chunk.add_child(spike)
			spike.set_meta("spike", true)
	var footprint := box(chunk, Vector3(0, 0.02, 0), Vector3(rect.size.x / SCALE, 0.025, rect.size.y / SCALE), material("warning_%d" % index, Color("ffca60"), 0.5))
	# 节点池会改变列表索引，预警材质必须独立，避免另一危险改写其颜色。
	footprint.material_override = footprint.material_override.duplicate()
	footprint.name = "WarningFootprint"
	var sign := Label3D.new()
	sign.name = "WarningLabel"
	sign.text = Run.hazard_name(kind)
	sign.position = Vector3(0, maxf(1.5, bottom + height + 0.4), 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 28
	sign.pixel_size = 0.012
	chunk.add_child(sign)

# 摆锤：路外两根立柱撑起横跨道路的龙门架，锤从横梁中点吊下，在横跨道路的竖直面里来回摆。
# 锤体缩在碰撞盒内，两侧钝刺尖刚好到碰撞盒边缘；立柱和横梁在头顶和路外，不参与碰撞。
func build_hammer_model(chunk: Node3D) -> void:
	var steel := material("hammer_steel", Color("3f3a36"))
	var height := Run.Industrial.HAMMER_PIVOT / SCALE
	for name in ["PostLeft", "PostRight"]:
		box(chunk, Vector3(0, height / 2 - 3.0, 0), Vector3(0.6, height + 6.0, 0.6), steel).name = name
	box(chunk, Vector3(0, height + 0.35, 0), Vector3(ROAD_HALF * 2 + 2.0, 0.6, 0.7), steel).name = "Beam"
	var swing := Node3D.new()
	swing.name = "Swing"
	swing.position.y = height
	chunk.add_child(swing)
	var length := Run.Industrial.HAMMER_LENGTH / SCALE
	var axle := cylinder(swing, Vector3.ZERO, 0.3, 0.9, material("hammer_axle", Color("8a7f70")))
	axle.rotation.x = PI / 2
	# 摆臂用两根并排的铁链杆，比单根方条更像吊锤。
	for z in [-0.12, 0.12]:
		box(swing, Vector3(0, -length / 2, z), Vector3(0.1, length, 0.1), material("hammer_rod", Color("6f6862")))
	var size: Vector3 = Run.Industrial.HAMMER_HEAD / SCALE
	var head := box(swing, Vector3(0, -length, 0), Vector3(size.x * 0.8, size.z * 0.86, size.y * 0.86), tex_material("hammer_head", "rock_boulder_dry", 0.3, Color("8f8379")))
	for x in [-0.5, 0.5]:
		box(head, Vector3(x, 0, 0), Vector3(0.16, size.z * 0.9, size.y * 0.9), material("hammer_band", Color("ff4d2e"), 0.8))
	for side in [-1, 1]:
		var spike := cylinder(head, Vector3(side * size.x * 0.45, 0, 0), 0.3, size.x * 0.1, material("hammer_spike", Color("d9d0c4")))
		spike.mesh.top_radius = 0.0
		spike.rotation.z = -side * PI / 2
	var shadow := cylinder(chunk, Vector3(0, 0.02, 0), size.x * 0.55, 0.02, zone_material("hammer_shadow", Color(0.02, 0.02, 0.03, 0.55)))
	shadow.name = "HammerShadow"
	# 地面上一条淡红色带：锤头会低到人身高度的横向范围。
	var zone := box(chunk, Vector3(0, 0.03, 0), Vector3(1, 0.02, size.y), zone_material("hammer_zone", Color(1.0, 0.3, 0.12, 0.22)))
	zone.name = "HammerZone"

func sync_hammer(view: Node3D, index: int) -> void:
	var pivot: Vector2 = run.obstacles[index].get_center()
	view.position = Vector3(pivot.x / SCALE, 0, -pivot.y / SCALE)
	# 节点池会把别的摆锤的模型拿来复用，支点左右不同：立柱和横梁每帧按本锤的支点重新摆放。
	view.get_node("PostLeft").position.x = -(ROAD_HALF + 0.7) - pivot.x / SCALE
	view.get_node("PostRight").position.x = ROAD_HALF + 0.7 - pivot.x / SCALE
	view.get_node("Beam").position.x = -pivot.x / SCALE
	var angle: float = Run.Industrial.hammer_angle(run.hazard_specs[index], run.elapsed)
	view.get_node("Swing").rotation.z = angle
	var head: Vector2 = Run.Industrial.hammer_head(pivot, angle)
	var shadow: MeshInstance3D = view.get_node("HammerShadow")
	shadow.position.x = (head.x - pivot.x) / SCALE
	var low := clampf(1.0 - (head.y - 25.0) / 140.0, 0.25, 1.0)
	shadow.scale = Vector3(low, 1.0, low)
	# 锤头中心低于 身高 + 半个锤头 时会撞人；换算成摆角，再得到地面上的危险横向范围。
	var danger := acos(clampf((Run.Industrial.HAMMER_PIVOT - Run.BODY_HEIGHT - Run.Industrial.HAMMER_HEAD.z * 0.5) / Run.Industrial.HAMMER_LENGTH, -1.0, 1.0))
	var reach := Run.Industrial.HAMMER_LENGTH * sin(minf(danger, Run.Industrial.HAMMER_ANGLE)) + Run.Industrial.HAMMER_HEAD.x * 0.5
	var zone: MeshInstance3D = view.get_node("HammerZone")
	zone.mesh.size.x = reach * 2.0 / SCALE
	zone.position.x = 0.0
	# 锤头摆过最低点时呼一声；只在离两人不远时出声。
	var id: int = run.obstacle_ids[index]
	var sign_now := signf(angle)
	if hammer_signs.has(id) and hammer_signs[id] != sign_now and run.state == "running" and absf(pivot.y - run.distance) < 520.0:
		sfx.play("whoosh", -4.0, randf_range(0.85, 1.05))
	hammer_signs[id] = sign_now

func build_industrial_model(chunk: Node3D, index: int) -> void:
	var sample: Dictionary = run.hazard_sample(index, run.elapsed)
	var kind: String = run.kinds[index]
	if kind == "hammer":
		build_hammer_model(chunk)
		return
	for p in sample.parts:
		# 会伤人的活动部件统一高亮红橙；支架、立柱用深色钢，不与浅色厂房混在一起。
		var danger: bool = p.name in ["head", "plate", "jet", "drone_body", "ram"]
		var color := Color("ff4d2e") if danger else (Color("a8552c") if kind == "forklift" else Color("5b5148"))
		if p.name == "load": color = Color("3f3a37")
		if p.name.begins_with("fork_"): color = Color("c9c2b6")
		if p.name in ["track", "shaft"]: color = Color("a8b7bc")
		if p.name == "nozzle": color = Color("ffb347")
		var body := box(chunk, Vector3.ZERO, Vector3.ONE, material("industrial_" + kind + p.name, color, 0.7 if danger else 0.0))
		body.name = p.name
		if p.name == "jet":
			# 危险体只驱动范围，喷流用多股渐隐锥柱表达，避免把气体显示成实心方块。
			body.material_override=zone_material("hidden_steam_volume",Color(0,0,0,0))
			var plume_material:=ShaderMaterial.new()
			var shader:=Shader.new()
			shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float flow_time=0.0;
void fragment(){
 float wave=sin(UV.y*35.0+UV.x*19.0-flow_time*13.0)*0.5+0.5;
 float fade=smoothstep(0.0,0.18,UV.y)*smoothstep(1.0,0.3,UV.y);
 ALBEDO=mix(vec3(1.0,0.35,0.08),vec3(1.0,0.88,0.56),wave);
 EMISSION=ALBEDO*0.7;
 ALPHA=fade*(0.16+wave*0.4);
}"""
			plume_material.shader=shader
			body.set_meta("plume_material",plume_material)
			for plume_index in range(10):
				var plume:=cylinder(body,Vector3.ZERO,0.5,1.0,plume_material)
				plume.mesh.top_radius=0.08
				plume.set_meta("plume_index",plume_index)
		if kind in ["shuttle", "piston"] and p.name in ["ram", "plate"]:
			# 实体上的横向金属条帮助辨认运动方向，装饰保持在碰撞盒内部。
			for stripe in range(3):
				var span: float = p.rect.size.x / SCALE
				box(body, Vector3((stripe-1)*span*0.28, 0, p.rect.size.y/SCALE*0.49), Vector3(span*0.08, 0.8, 0.02), material("mechanical_stripe", Color("ffcf72")))
		if p.name == "floor":
			# 每块地板的阶段颜色独立变化，避免共享材质覆盖其他板的预警。
			body.material_override = body.material_override.duplicate()
			for n in range(3):
				var crack := box(body, Vector3((n - 1) * 1.5, 0.02, 0), Vector3(0.12, 0.02, 2.6), material("collapse_crack", Color("ff692e"), 1.2))
				crack.rotation.y = (n - 1) * 0.35
		# 岩鹰和矿车用实际模型，缩放到不超出同源碰撞盒；原方块隐藏但仍驱动位置和显隐。
		if kind == "drone":
			# 翼展 3.6 米，比 1.8 米宽的碰撞盒各多出约 0.9 米翼尖：翼尖擦过不算命中，对玩家从宽。
			var eagle := fit_model("res://assets/props/Eagle_Flying.glb", body, Vector3(3.6, 2.4, 2.4), Vector3.ZERO)
			var wings := animation_player(eagle)
			for name in ["Flap", "Dive"]: wings.get_animation(name).loop_mode = Animation.LOOP_LINEAR
			body.set_meta("eagle", eagle)
			body.set_meta("wings", wings)
		if p.name == "load":
			# 矿石堆：深色岩块上嵌几块发光矿晶，与矿车区分开。
			for n in range(4):
				var crystal := box(body, Vector3([-0.86, 0.86, -0.3, 0.4][n], [0.9, 0.2, -0.8, 1.6][n], [0.3, -0.4, 1.01, -1.01][n]), Vector3(0.28, 0.5, 0.28), material("ore_crystal", Color("ffb347"), 1.4))
				crystal.rotation = Vector3(0.5, n * 0.9, 0.4)
		if p.name == "vehicle":
			fit_model("res://assets/props/Minecart_HunterParamore.glb", body, Vector3(3.0, 3.2, 2.4), Vector3.ZERO)
	if run.kinds[index]=="steam":
		var vapor:=cylinder(chunk,Vector3(0,0.7,0),0.35,0.65,zone_material("pressure_vapor",Color(0.8,0.75,0.6,0.32)))
		vapor.name="PressureVapor"
		vapor.material_override.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	box(chunk, Vector3.ZERO, Vector3.ONE, zone_material("industrial_warning", Color(1.0, 0.25, 0.12, 0.34))).name = "WarningFootprint"
	box(chunk, Vector3.ZERO, Vector3.ONE, zone_material("industrial_corridor", Color(1.0, 0.45, 0.1, 0.42))).name = "TrajectoryCorridor"
	cylinder(chunk, Vector3.ZERO, 0.7, 0.025, material("industrial_launch", Color("ffda79"), 0.7)).name = "LaunchMarker"
	var sign := Label3D.new()
	sign.name = "WarningLabel"
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 28
	sign.pixel_size = 0.012
	chunk.add_child(sign)

func sync_industrial_model(view: Node3D, index: int, sample: Dictionary) -> void:
	if run.kinds[index] == "hammer":
		sync_hammer(view, index)
		return
	var center: Vector2 = sample.rect.get_center()
	for p in sample.parts:
		var body: MeshInstance3D = view.get_node(p.name)
		body.position = Vector3((p.rect.get_center().x - center.x) / SCALE,
			(p.bottom + p.top) * 0.5 / SCALE, -(p.rect.get_center().y - center.y) / SCALE)
		var size: Vector2 = p.get("size", p.rect.size)
		body.mesh.size = Vector3(size.x / SCALE, (p.top - p.bottom) / SCALE, size.y / SCALE)
		body.rotation.y = p.get("angle", 0.0)
		body.visible = p.active or run.kinds[index] == "drone" or p.name in ["nozzle", "track"] or (p.name == "floor" and sample.supported)
		if p.name=="jet":
			body.get_meta("plume_material").set_shader_parameter("flow_time",run.elapsed)
			for plume in body.get_children():
				var n:int=plume.get_meta("plume_index")
				var pulse:float=0.85+sin(run.elapsed*11.0+n*2.1)*0.15
				plume.position=Vector3((float(n)/9.0-0.5)*size.x/SCALE*0.9,0,sin(n*2.0)*size.y/SCALE*0.12)
				plume.scale=Vector3(size.x/SCALE/8.0,(p.top-p.bottom)/SCALE*pulse,size.y/SCALE*0.8)
		if p.name == "floor":
			body.position.y = 0.01
			body.mesh.size.y = 0.02
			# 琥珀色裂纹石板本身就是道具外形；不再做黄红闪烁预警。
			body.material_override.albedo_color = Color("c9963f")
			for child in body.get_children(): child.visible = true
		if p.name == "nozzle": body.position.y = 0.26
	if run.kinds[index]=="steam":
		var vapor:MeshInstance3D=view.get_node("PressureVapor")
		vapor.visible=sample.stage in ["warning","pressure"]
		vapor.position.y=0.7+sin(run.elapsed*9.0)*0.08
		vapor.scale=Vector3.ONE*(1.0 if sample.stage=="pressure" else 0.6)
		view.get_node("nozzle").material_override.albedo_color=Color("c7964c") if sample.warning else Color("655b4e")
	if run.kinds[index] == "drone":
		# 预警时原地扇翅悬停，俯冲时收成后掠翼并压低机头；暂停时动画一起冻结。
		var eagle_body: MeshInstance3D = view.get_node("drone_body")
		var wings: AnimationPlayer = eagle_body.get_meta("wings")
		var diving: bool = sample.stage == "flight"
		if wings.current_animation != ("Dive" if diving else "Flap"): wings.play("Dive" if diving else "Flap", 0.15)
		wings.speed_scale = 0.0 if run.state == "paused" else 1.0
		eagle_body.get_meta("eagle").rotation.x = 0.4 if diving else 0.0
	var footprint: MeshInstance3D = view.get_node("WarningFootprint")
	var envelope: Rect2 = sample.envelope if run.kinds[index] == "hammer" else sample.rect
	footprint.position = Vector3((envelope.get_center().x - center.x) / SCALE, 0.28, -(envelope.get_center().y - center.y) / SCALE)
	footprint.mesh.size = Vector3(envelope.size.x / SCALE, 0.025, envelope.size.y / SCALE)
	footprint.visible = sample.warning or run.kinds[index] in ["press", "hammer"]
	var corridor: MeshInstance3D = view.get_node("TrajectoryCorridor")
	var marker: MeshInstance3D = view.get_node("LaunchMarker")
	var spec: Dictionary = run.hazard_specs[index]
	marker.position = Vector3((sample.launch.x - center.x) / SCALE, 0.035, -(sample.launch.y - center.y) / SCALE)
	marker.visible = sample.warning
	corridor.visible = sample.warning and run.kinds[index] in ["drone", "forklift"]
	var delta: Vector2 = spec.velocity * (5.0 if run.kinds[index] == "drone" else 4.0)
	var launch_sample: Dictionary = Run.Industrial.sample(run.kinds[index], run.obstacles[index], spec, maxf(0, spec.trigger))
	var launch_center: Vector2 = launch_sample.rect.get_center() - center
	var direction := delta.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var across: float = absf(perpendicular.x) * launch_sample.rect.size.x + absf(perpendicular.y) * launch_sample.rect.size.y
	var along: float = absf(direction.x) * launch_sample.rect.size.x + absf(direction.y) * launch_sample.rect.size.y
	corridor.position = Vector3(launch_center.x + delta.x * 0.5, 0.4, -launch_center.y - delta.y * 0.5) / SCALE
	corridor.mesh.size = Vector3(maxf(0.1, across / SCALE), 0.025, maxf(0.1, (delta.length() + along) / SCALE))
	corridor.rotation.y = atan2(-delta.x, delta.y)
	var sign: Label3D = view.get_node("WarningLabel")
	sign.position = Vector3(0, 7.0, 0)
	var stage: String = {"warning": "预警", "flight": "俯冲", "spent": "已通过", "parked": "停驻", "crossing": "横穿", "down": "下压", "hold": "停留", "up": "回升", "safe": "开放时窗", "ready": "待触发", "lower": "落锤", "swing": "摆动", "raise": "抬锤", "intact": "完整地板", "crack": "裂纹预警", "grace": "退出宽限", "collapsed": "已塌陷", "pressure": "升压", "jet": "喷射", "fade": "消退"}.get(sample.stage, sample.stage)
	sign.text = stage + " · " + Run.hazard_name(run.kinds[index])
	if run.kinds[index] == "collapse" and sample.remaining >= 0: sign.text += " · %.1f 秒" % sample.remaining
	if run.kinds[index] == "drone": sign.text += " · 高度 0.9–2.4m · 锁定后不追踪"

func build_surface_hazard(chunk: Node3D, index: int) -> void:
	var kind: String = run.kinds[index]
	var rect: Rect2 = run.obstacles[index]
	if kind == "sweeper":
		var geometry: Dictionary = run.hazard_sample(index, run.elapsed).geometry
		var post := cylinder(chunk, Vector3(0, geometry.post_top / SCALE / 2, 0), geometry.post_radius / SCALE, geometry.post_top / SCALE, material("sweep_post", Color("556a78")))
		post.name = "SweeperPost"
		var arm := box(chunk, Vector3(0, (geometry.top - geometry.radius) / SCALE, 0), Vector3(Run.Surfaces.ARM_HALF * 2 / SCALE, geometry.radius * 2 / SCALE, geometry.radius * 2 / SCALE), material("sweep_arm", Color("ff5a2e"), 0.9))
		arm.name = "SweeperArm"
		for side in [-1, 1]:
			var cap := cylinder(arm, Vector3(side * Run.Surfaces.ARM_HALF / SCALE, 0, 0), geometry.radius / SCALE, geometry.radius * 2 / SCALE, material("sweep_tip", Color("ffe2a0"), 0.8))
			cap.name = "TipLeft" if side < 0 else "TipRight"
		var envelope := cylinder(chunk, Vector3(0, 0.02, 0), (Run.Surfaces.ARM_HALF + geometry.radius) / SCALE, 0.02, zone_material("sweep_envelope", Color(1.0, 0.3, 0.12, 0.3)))
		envelope.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		envelope.name = "WarningFootprint"
	else:
		# 断崖缺口是真正的镂空：缺口下方路基隐藏，透过岩壁向下看到的是与路外相同的云海。
		var mist := box(chunk, Vector3(0, -28.0, 0), Vector3(1, 0.05, 1), gap_mist_material())
		mist.name = "GapMist"
		# 坑沿是发光黄色警戒条，坑前路面另有一条闪烁的红色预警带。所有尺寸在 sync_view 中按实际缺口矩形同步。
		for side in [-1, 1]:
			var edge := box(chunk, Vector3(0, 0.03, side), Vector3(1, 0.06, 0.4), material("gap_edge", Color("ffd23a"), 1.4))
			edge.name = "GapNear" if side > 0 else "GapFar"
			var inner := box(chunk, Vector3(0, 0.035, side), Vector3(1, 0.06, 0.14), material("gap_edge_inner", Color("ff3b1f"), 1.6))
			inner.name = "GapNearInner" if side > 0 else "GapFarInner"
			var face := box(chunk, Vector3(0, -GAP_DEPTH / 2, side), Vector3(1, GAP_DEPTH, 0.06), gap_wall_material())
			face.name = "GapNearWall" if side > 0 else "GapFarWall"
		for side in [-1, 1]:
			var wall := box(chunk, Vector3(side, -GAP_DEPTH / 2, 0), Vector3(0.06, GAP_DEPTH, 1), gap_wall_material())
			wall.name = "GapLeft" if side < 0 else "GapRight"
			var rim := box(chunk, Vector3(side, 0.03, 0), Vector3(0.3, 0.06, 1), material("gap_edge", Color("ffd23a"), 1.4))
			rim.name = "GapLeftRim" if side < 0 else "GapRightRim"
		var approach := box(chunk, Vector3(0, 0.02, 2), Vector3(1, 0.02, 2.4), zone_material("gap_approach", Color(1.0, 0.18, 0.08, 0.45)))
		approach.name = "GapApproach"
	var sign := Label3D.new()
	sign.name = "WarningLabel"
	sign.text = Run.hazard_name(kind)
	sign.position = Vector3(0, 2.6, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 28
	sign.pixel_size = 0.012
	chunk.add_child(sign)

func sync_road_support(chunk: Node3D) -> void:
	# 同一布局只收集一次地形；槽位循环或原点重定位后重新匹配。
	if support_run_id != run.get_instance_id() or support_revision != run.revision:
		support_run_id = run.get_instance_id()
		support_revision = run.revision
		support_gaps = run.ground_gaps()
		for index in range(run.kinds.size()):
			if run.kinds[index] in ["slope","steps","tilt"]: support_gaps.append(run.obstacles[index])
	var slot_z := snappedf(chunk.position.z, 0.001)
	if chunk.get_meta("support_run_id", 0) == support_run_id and chunk.get_meta("support_revision", -1) == support_revision and chunk.get_meta("support_z", INF) == slot_z: return
	chunk.set_meta("support_run_id", support_run_id)
	chunk.set_meta("support_revision", support_revision)
	chunk.set_meta("support_z", slot_z)
	var surface: MeshInstance3D = chunk.get_node("SupportSurface")
	var cuts: Array[Rect2] = []
	for gap in support_gaps:
		var local := Rect2(gap.position.x / SCALE, -gap.end.y / SCALE - chunk.position.z, gap.size.x / SCALE, gap.size.y / SCALE)
		if local.intersects(Rect2(-ROAD_HALF, -4, ROAD_HALF * 2, 8)): cuts.append(local)
	# 缺口下方不留实心路基，镂空直通崖下云雾；缺口自身的岩壁补齐断面。
	chunk.get_node("CliffBody").visible = cuts.is_empty()
	for side in [-1, 1]:
		var touches_edge := false
		for cut in cuts:
			touches_edge = touches_edge or (cut.end.x >= ROAD_HALF - 0.9 if side > 0 else cut.position.x <= -ROAD_HALF + 0.9)
		chunk.get_node("EdgeWallLeft" if side < 0 else "EdgeWallRight").visible = not touches_edge
	if cuts.is_empty():
		surface.mesh = surface.get_meta("original_mesh")
	elif support_mesh_cache.has(cuts):
		surface.mesh = support_mesh_cache[cuts]
	else:
		var xs: Array[float] = [-ROAD_HALF, ROAD_HALF]
		var zs: Array[float] = [-4.0, 4.0]
		for cut in cuts:
			xs.append(clampf(cut.position.x, -ROAD_HALF, ROAD_HALF))
			xs.append(clampf(cut.end.x, -ROAD_HALF, ROAD_HALF))
			zs.append(clampf(cut.position.y, -4, 4))
			zs.append(clampf(cut.end.y, -4, 4))
		xs.sort()
		zs.sort()
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for x in range(xs.size() - 1):
			for z in range(zs.size() - 1):
				if xs[x + 1] - xs[x] < 0.00001 or zs[z + 1] - zs[z] < 0.00001: continue
				var middle := Vector2((xs[x] + xs[x + 1]) / 2, (zs[z] + zs[z + 1]) / 2)
				var missing := false
				for cut in cuts:
					if cut.has_point(middle): missing = true
				if missing: continue
				# 与原路面同高；缺口区域不生成顶部三角形。
				for vertex in [Vector3(xs[x], 0.25, zs[z]), Vector3(xs[x + 1], 0.25, zs[z]), Vector3(xs[x + 1], 0.25, zs[z + 1]), Vector3(xs[x], 0.25, zs[z]), Vector3(xs[x + 1], 0.25, zs[z + 1]), Vector3(xs[x], 0.25, zs[z + 1])]:
					tool.set_normal(Vector3.UP)
					tool.add_vertex(vertex)
		surface.mesh = tool.commit()
		support_mesh_build_count += 1
		if support_mesh_cache.size() >= SUPPORT_MESH_CACHE_LIMIT: support_mesh_cache.erase(support_mesh_cache.keys()[0])
		support_mesh_cache[cuts.duplicate()] = surface.mesh
	for child in chunk.get_children():
		if not child.has_meta("road_overlay"): continue
		child.visible = true
		for cut in cuts:
			var extent: Vector3 = child.get_aabb().size * child.scale
			if cut.intersects(Rect2(child.position.x - extent.x / 2, child.position.z - extent.z / 2, extent.x, extent.z)): child.visible = false

# 把模型等比缩放进给定尺寸并居中挂到碰撞方块下，方块本身改为不可见。
func skeleton_of(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found := skeleton_of(child)
		if found != null: return found
	return null

# Run 动画一整圈里骨骼的最低和最高点（世界坐标）。
func bone_span(player: AnimationPlayer, skeleton: Skeleton3D) -> Vector2:
	var span := Vector2(INF, -INF)
	for name in player.get_animation_list():
		if not name.ends_with("Run"): continue
		player.play(name)
		for n in range(12):
			player.seek(player.current_animation_length * n / 12.0, true)
			for bone in range(skeleton.get_bone_count()):
				var height: float = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin.y
				span = Vector2(minf(span.x, height), maxf(span.y, height))
		player.stop()
	return span

# 模型包围盒里混有脚下的附属网格，按包围盒落地和定身高会让 01 悬空约 1 米、两人还不一样高。
# 改按骨骼：先把头顶骨到脚底骨统一成 3 米（与 2.9 米的碰撞身高一致），再让跑动时最低的骨节贴地。
func ground_character(character: Node3D) -> void:
	var player := animation_player(character)
	var skeleton := skeleton_of(character)
	if player == null or skeleton == null: return
	var span := bone_span(player, skeleton)
	if span.y <= span.x: return
	character.scale *= 3.0 / (span.y - span.x)
	character.position *= 3.0 / (span.y - span.x)
	# 最低的是脚趾骨节，鞋底在它下面约 6 厘米。
	character.position.y -= bone_span(player, skeleton).x - 0.06

func animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found := animation_player(child)
		if found != null: return found
	return null

func fit_model(path: String, body: MeshInstance3D, limit: Vector3, tilt: Vector3) -> Node3D:
	body.material_override = zone_material("hidden_volume", Color(0, 0, 0, 0))
	var pivot := Node3D.new()
	body.add_child(pivot)
	var instance: Node3D = load(path).instantiate()
	pivot.add_child(instance)
	var bounds := model_bounds(instance, instance)
	var factor := minf(limit.x / bounds.size.x, minf(limit.y / bounds.size.y, limit.z / bounds.size.z))
	instance.scale = Vector3.ONE * factor
	instance.position = -bounds.get_center() * factor
	pivot.rotation = tilt
	return pivot

# 巨岩：占满碰撞盒的石块，顶面压一圈警示色；尺寸与生产矩形一致。
func build_rock_block(chunk: Node3D, index: int) -> void:
	var rect: Rect2 = run.obstacles[index]
	var size := Vector3(rect.size.x / SCALE, run.obstacle_heights[index] / SCALE, rect.size.y / SCALE)
	# 顶板、警示圈与本体形成阶差，避免共面闪烁；总高度仍等于碰撞高度。
	box(chunk, Vector3(0, (size.y - 0.1) / 2, 0), Vector3(size.x, size.y - 0.1, size.z), tex_material("rock_block", "rock_boulder_dry", 0.2, Color("a3907f")))
	box(chunk, Vector3(0, size.y - 0.06, 0), Vector3(size.x, 0.08, size.z), material("rock_block_rim", Color("8a7a66")))
	box(chunk, Vector3(0, size.y - 0.06, 0), Vector3(size.x - 0.3, 0.12, size.z - 0.3), tex_material("rock_block_top", "rock_boulder_dry", 0.2, Color("b8a694")))
	var sign := Label3D.new()
	sign.name = "WarningLabel"
	sign.position = Vector3(0, size.y + 0.9, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.pixel_size = 0.012
	chunk.add_child(sign)

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	parent.add_child(instance)
	return instance

# 两种滚球使用同一球体结构和节点池，半径与危险体相同；条带随实际路程转动。
func build_ball_model(chunk: Node3D, index: int) -> void:
	var radius: float = run.obstacles[index].size.x / SCALE * 0.5
	var iron: bool = run.kinds[index] == "iron_ball"
	var volume := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	sphere.radial_segments = 32
	sphere.rings = 16
	volume.mesh = sphere
	volume.name = "BallBody"
	volume.position.y = radius
	var mat := material("iron_ball" if iron else "stone_ball", Color("566b7c") if iron else Color("7d5f48")).duplicate() as StandardMaterial3D
	mat.metallic = 0.85 if iron else 0.0
	mat.roughness = 0.24 if iron else 0.95
	volume.material_override = mat
	chunk.add_child(volume)
	var band := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.045
	torus.outer_radius = radius + 0.025
	band.mesh = torus
	band.material_override = material("ball_band_" + run.kinds[index], Color("ffd15a") if iron else Color("ff7a3c"), 0.9)
	volume.add_child(band)
	var shadow := cylinder(chunk, Vector3(0, 0.018, 0), radius, 0.025, material("ball_shadow", Color("263039")))
	shadow.name = "ThreatShadow"
	var ring := cylinder(chunk, Vector3(0, Run.ROPE_HEIGHT / SCALE, 0), radius + 0.035, 0.055, material("ball_contact", Color("ffc06b"), 0.5).duplicate())
	ring.name = "ContactRing"
	ring.hide()
	box(chunk, Vector3(0, 0.03, 5), Vector3(radius * 2, 0.02, 10), zone_material("ball_route", Color(1.0, 0.3, 0.12, 0.4))).name = "FlightRoute"
	var sign := Label3D.new()
	sign.name = "WarningLabel"
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0, radius * 2 + 0.5, 0)
	sign.font_size = 28
	sign.pixel_size = 0.012
	chunk.add_child(sign)

# 高柱：模型半径、高度与生产碰撞一致；接触环只在绳索挂住这根柱子时显示。
func build_pillar_model(chunk: Node3D, index: int) -> void:
	var radius: float = run.obstacles[index].size.x * 0.5 / SCALE
	var height: float = run.obstacle_heights[index] / SCALE
	cylinder(chunk, Vector3(0, height / 2, 0), radius, height, material("pillar_body", Color("8c7f70"))).name = "PillarBody"
	cylinder(chunk, Vector3(0, 0.06, 0), radius + 0.22, 0.12, material("pillar_base", Color("4a4037")))
	cylinder(chunk, Vector3(0, height - 0.1, 0), radius + 0.08, 0.2, material("pillar_cap", Color("ffca60"), 0.6))
	for y in [0.9, 1.2]:
		cylinder(chunk, Vector3(0, y, 0), radius + 0.012, 0.12, material("pillar_stripe", Color("ffca60"), 0.35))
	var ring := cylinder(chunk, Vector3(0, 1.4, 0), radius + 0.07, 0.16, material("pillar_contact", Color("ffc06b"), 1.2).duplicate())
	ring.name = "ContactRing"
	ring.visible = false
	var sign := Label3D.new()
	sign.name = "WarningLabel"
	sign.text = Run.hazard_name("pillar")
	sign.position = Vector3(0, height + 0.4, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 28
	sign.pixel_size = 0.012
	chunk.add_child(sign)

func build_robots() -> void:
	for index in range(2):
		var robot := Node3D.new()
		add_child(robot)
		robots.append(robot)
		var character := model("res://assets/humans/%s.glb" % ["Adventurer_A", "Adventurer_B"][index], robot, Vector3.ZERO, 3.8, PI)
		register_animation(character)
		ground_character(character)
		# 识别灯保持两人辨识度；阴影固定在地面，角色独立腾空。
		var accent := material("robot_%d" % index, Color("57dbea") if index == 0 else Color("ffb95e"), 0.65)
		# 两人衣着接近路面颜色，脚下加各自识别色的光环，远处也分得清谁是谁。
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.66
		torus.outer_radius = 0.74
		ring.mesh = torus
		ring.material_override = accent
		ring.position.y = 0.05
		ring.scale.y = 0.15
		robot.add_child(ring)
		# 腰部皮带与铜扣交代麻绳的真实固定位置。
		var belt := cylinder(robot, Vector3(0,1.4,0),0.37,0.13,material("rope_belt",Color("493025")))
		belt.scale.z = 0.8
		var knot := MeshInstance3D.new()
		var knot_mesh := TorusMesh.new()
		knot_mesh.inner_radius = 0.07
		knot_mesh.outer_radius = 0.13
		knot.mesh = knot_mesh
		knot.material_override = material("rope_knot",Color("b58a52"))
		knot.name="RopeKnot"
		knot.position = Vector3(0,1.4,0)
		knot.rotation.z = PI/2
		robot.add_child(knot)
		var shadow := MeshInstance3D.new()
		var disk := CylinderMesh.new()
		disk.top_radius = 0.5
		disk.bottom_radius = 0.5
		disk.height = 0.01
		shadow.mesh = disk
		var shadow_mat := material("contact_shadow_%d" % index, Color(0.015, 0.025, 0.035, 0.4))
		shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shadow.material_override = shadow_mat
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shadow)
		shadows.append(shadow)
		var tag := Label3D.new()
		tag.text = "01" if index == 0 else "02"
		tag.position = Vector3(0, 3.9, 0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 40
		tag.pixel_size = 0.012
		tag.modulate = accent.albedo_color
		robot.add_child(tag)
	# 真绳子：有重量、会下垂和甩动的细麻绳，替代原来的发光方条。
	rope_view = RopeView.new()
	rope_view.length = Run.LINK_LIMIT / SCALE
	add_child(rope_view)
	cable_material = rope_view.rope_material

func label(text: String, size: int, color: Color = Color("e3eee9")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var top := PanelContainer.new()
	top.position = Vector2(28, 22)
	top.size = Vector2(1224, 82)
	root.add_child(top)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.075, 0.1, 0.92)
	style.border_color = Color("385360")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	top.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	top.add_child(row)
	row.add_child(label("共生连线 / 归航", 21))
	hud = label("", 16, Color("68dce3"))
	hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hud)
	distance_label = label("", 16, Color("ffc175"))
	row.add_child(distance_label)
	ui_root = root
	var score_box := HBoxContainer.new()
	score_box.add_theme_constant_override("separation", 10)
	row.add_child(score_box)
	coin_icon = Panel.new()
	coin_icon.custom_minimum_size = Vector2(30, 30)
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_icon.pivot_offset = Vector2(15, 15)
	coin_icon.add_theme_stylebox_override("panel", coin_style(Color("ffd15a")))
	score_box.add_child(coin_icon)
	score_label = label("0", 28, Color("ffe08a"))
	score_label.custom_minimum_size.x = 96
	score_label.pivot_offset = Vector2(10, 20)
	score_box.add_child(score_label)
	progress_bar = ColorRect.new()
	progress_bar.position = Vector2(52, 89)
	progress_bar.size = Vector2(1176, 4)
	progress_bar.color = Color("2b424f")
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_fill = ColorRect.new()
	progress_fill.color = Color("5fcdd5")
	progress_fill.size = Vector2(0, 4)
	progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.add_child(progress_fill)
	root.add_child(progress_bar)
	var bottom := label("01：WASD / 空格跳跃与确认   ·   02：方向键 / 回车跳跃与确认   ·   Esc 暂停   ·   R 重试当前关", 17)
	bottom.position = Vector2(40, 677)
	root.add_child(bottom)
	bottom_hint = bottom
	loading_box = Control.new()
	loading_box.position = Vector2(360, 280)
	loading_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(loading_box)
	loading_label = label("正在准备道路…", 28, Color.WHITE)
	loading_label.size = Vector2(560, 80)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_box.add_child(loading_label)
	loading_progress = ProgressBar.new()
	loading_progress.position = Vector2(0, 90)
	loading_progress.size = Vector2(560, 28)
	loading_box.add_child(loading_progress)
	loading_box.hide()
	rescue_box = Control.new()
	rescue_box.position = Vector2(640 - RESCUE_BAR / 2, 520)
	rescue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rescue_box.visible = false
	root.add_child(rescue_box)
	rescue_label = label("", 30, Color("ffe08a"))
	rescue_label.position = Vector2(0, -52)
	rescue_label.size = Vector2(RESCUE_BAR, 44)
	rescue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rescue_label.add_theme_color_override("font_outline_color", Color("1a0d05"))
	rescue_label.add_theme_constant_override("outline_size", 10)
	rescue_box.add_child(rescue_label)
	var rescue_back := ColorRect.new()
	rescue_back.size = Vector2(RESCUE_BAR, 22)
	rescue_back.color = Color(0.04, 0.07, 0.09, 0.85)
	rescue_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rescue_box.add_child(rescue_back)
	rescue_fill = ColorRect.new()
	rescue_fill.size = Vector2(0, 22)
	rescue_fill.color = Color("ffc06b")
	rescue_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rescue_box.add_child(rescue_fill)
	rescue_timer_fill = ColorRect.new()
	rescue_timer_fill.position = Vector2(0, 28)
	rescue_timer_fill.size = Vector2(RESCUE_BAR, 6)
	rescue_timer_fill.color = Color("ff5a48")
	rescue_timer_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rescue_box.add_child(rescue_timer_fill)
	touch = TouchControls.new()
	root.add_child(touch)
	pause_button = Button.new()
	pause_button.text = "暂停"
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.position = Vector2(1150, 112)
	pause_button.size = Vector2(100, 52)
	pause_button.add_theme_font_size_override("font_size", 20)
	pause_button.pressed.connect(func(): command("pause"))
	root.add_child(pause_button)
	touch.blockers.append(pause_button)
	panel = PanelContainer.new()
	panel.position = Vector2(355, 140)
	panel.size = Vector2(570, 470)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	var column := VBoxContainer.new()
	# 网页版自带的中文字体行高更大、折行更多，收紧间距以免面板底部的联机状态被挤出画面。
	column.add_theme_constant_override("separation", 12 if OS.has_feature("web") else 20)
	panel.add_child(column)
	column.add_child(label("CO-OP ROAD / 本地双人三关", 16, Color("63dbe4")))
	title = label("共生归航", 40)
	column.add_child(title)
	subtitle = label("", 19)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(510, 110)
	column.add_child(subtitle)
	primary = Button.new()
	primary.focus_mode = Control.FOCUS_NONE
	primary.custom_minimum_size.y = 48
	primary.add_theme_font_size_override("font_size", 21)
	primary.pressed.connect(func(): command("primary"))
	column.add_child(primary)
	var choices := HBoxContainer.new()
	column.add_child(choices)
	for name in Run.Templates.DIFFICULTIES:
		var button := Button.new()
		button.text = name
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func(): command("difficulty", name))
		choices.add_child(button)
		difficulty_buttons.append(button)
	var online := HBoxContainer.new()
	online.add_theme_constant_override("separation", 10)
	column.add_child(online)
	net_address = LineEdit.new()
	net_address.placeholder_text = "联机服务器地址，如 100.64.0.1"
	net_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	net_address.custom_minimum_size.y = 44
	net_address.text = load_address()
	online.add_child(net_address)
	net_button = Button.new()
	net_button.focus_mode = Control.FOCUS_NONE
	net_button.custom_minimum_size = Vector2(110, 44)
	net_button.pressed.connect(toggle_online)
	online.add_child(net_button)
	net_status = label("单机：同屏双人键盘。填写地址后点“联机”与队友远程合作。", 15, Color("9fb7c0"))
	net_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(net_status)

func coin_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.darkened(0.45)
	style.set_border_width_all(3)
	style.set_corner_radius_all(64)
	return style

# 当前应显示的团队总分：已完成各关成绩 + 本关金币和奖品。结算后本关已计入 results，不再重复加。
func target_score() -> int:
	if run.state in ["settlement", "complete"]: return run.total_score()
	return run.total_score() + run.coins * 10 + run.prizes * 100

# 金币（或奖品）从拾取位置沿弧线飞向得分图标，到达时才加分并让图标跳一下。
func spawn_flyer(world: Vector3, color: Color, value: int) -> void:
	if camera.is_position_behind(world) or not is_instance_valid(coin_icon):
		shown_score += value
		return
	var start := camera.unproject_position(world)
	var dot := Panel.new()
	dot.size = Vector2(26, 26)
	dot.pivot_offset = dot.size * 0.5
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", coin_style(color))
	dot.position = start - dot.size * 0.5
	ui_root.add_child(dot)
	var target := coin_icon.get_global_rect().get_center()
	var control := start.lerp(target, 0.35) + Vector2(randf_range(-60, 60), -170)
	flying += 1
	var tween := create_tween()
	tween.tween_method(move_flyer.bind(dot, start, control, target), 0.0, 1.0, randf_range(0.5, 0.65)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(land_flyer.bind(dot, value))

func move_flyer(t: float, dot: Panel, start: Vector2, control: Vector2, target: Vector2) -> void:
	var point := start.lerp(control, t).lerp(control.lerp(target, t), t)
	dot.position = point - dot.size * 0.5
	dot.scale = Vector2.ONE * lerpf(1.35, 0.75, t)
	dot.rotation = t * 5.0

func land_flyer(dot: Panel, value: int) -> void:
	dot.queue_free()
	flying = maxi(0, flying - 1)
	shown_score += value
	sfx.play("coin_land", -12.0, randf_range(0.95, 1.1))
	for node in [coin_icon, score_label]:
		node.scale = Vector2.ONE * 1.35
		create_tween().tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hazard_shape(index: int) -> String:
	return var_to_str([run.kinds[index], run.obstacles[index].size, run.obstacle_heights[index], run.hazard_specs[index].get("bottom", 0.0), run.hazard_specs[index].get("amplitude", 0.0)])

func hazard_identity(index: int) -> String:
	return "%d:%d:%d:%s" % [run.seed_value, run.level_index, run.obstacle_ids[index], hazard_shape(index)]

func make_hazard_view(index: int) -> Node3D:
	var chunk := Node3D.new()
	chunk.set_meta("hazard_kind", run.kinds[index])
	chunk.set_meta("hazard_shape", hazard_shape(index))
	road.add_child(chunk)
	if Run.Threats.is_ball(run.kinds[index]): build_ball_model(chunk, index)
	elif run.kinds[index] == "pillar": build_pillar_model(chunk, index)
	elif run.kinds[index] == "cargo": build_rock_block(chunk, index)
	else: build_hazard_model(chunk, index)
	hazard_build_count += 1
	return chunk

func rebuild_hazard_views() -> void:
	var kept := {}
	for index in range(run.obstacles.size()): kept[hazard_identity(index)] = true
	var old := {}
	for view in hazard_views:
		var identity: String = view.get_meta("hazard_identity", "")
		if kept.has(identity):
			old[identity] = view
			continue
		scenery.erase(view)
		view.hide()
		var shape: String = view.get_meta("hazard_shape")
		if not hazard_pool.has(shape): hazard_pool[shape] = []
		hazard_pool[shape].append(view)
	hazard_views.clear()
	for index in range(run.obstacles.size()):
		var identity := hazard_identity(index)
		var shape := hazard_shape(index)
		var view: Node3D
		if old.has(identity): view = old[identity]
		else:
			if hazard_pool.has(shape) and not hazard_pool[shape].is_empty(): view = hazard_pool[shape].pop_back()
			else: view = make_hazard_view(index)
			scenery.append(view)
		view.set_meta("hazard_identity", identity)
		view.show()
		hazard_views.append(view)
	# 有界回收；只清除不在当前场景中的备用模型。
	var spare := 0
	for shape in hazard_pool:
		spare += hazard_pool[shape].size()
		while spare > MODEL_POOL_LIMIT and not hazard_pool[shape].is_empty():
			hazard_pool[shape].pop_back().queue_free()
			spare -= 1
	view_revision = run.revision

# 已证明布局提前逐个准备隐藏模型；当前帧需要安装时若模型未齐，只保留帧等待，不一口气建一整段。
func prepare_generation_views(startup: bool = false) -> bool:
	var targets: Array = []
	if run.cooperative_job != null and run.cooperative_job.done:
		targets.append({"job": run.async_job, "block": run.cooperative_job.result.block, "blocking": not run.lockstep or run.generation_due()})
	for key in run.async_preload_tasks:
		var task = run.async_preload_tasks[key]
		if task.done: targets.append({"job": task.job, "block": task.result.block, "blocking": startup})
	var current: Array = []
	for target in targets: current.append(str(target.job.key))
	for key in preview_runs.keys():
		if current.has(key): continue
		preview_runs[key].dispose()
		preview_runs.erase(key)
	for target in targets:
		if target.block.is_empty(): continue
		var key: String = target.job.key
		if not preview_runs.has(key):
			var preview = Run.new(false)
			preview.level_index = target.job.level
			preview.difficulty = target.job.difficulty
			preview.install_block(target.block, target.job.base, "preview")
			preview_runs[key] = preview
		var live = run
		run = preview_runs[key]
		var required := {}
		for index in range(run.obstacles.size()):
			var shape := hazard_shape(index)
			required[shape] = required.get(shape, 0) + 1
			if hazard_pool.get(shape, []).size() >= required[shape]: continue
			var spare := 0
			for cached in hazard_pool.values(): spare += cached.size()
			if spare < MODEL_POOL_LIMIT or target.blocking:
				var view := make_hazard_view(index)
				view.hide()
				if not hazard_pool.has(shape): hazard_pool[shape] = []
				hazard_pool[shape].append(view)
			run = live
			return not target.blocking
		run = live
	return true

func prepare_game_frame() -> bool:
	var startup: bool = run.async_startup_pending and run.state == "running"
	var ready: bool = run.prepare_frame()
	# 证明期间同步逐个准备模型，避免计算进度完成后再集中建模。
	var models_ready := prepare_generation_views(startup)
	if startup and (not ready or not models_ready):
		run.async_startup_pending = true
		return false
	if startup: clear_controls()
	return ready and models_ready

func build_rewards() -> void:
	# 固定奖励槽，不随领取或跨关增加节点；每次同步完整覆盖可复用槽的表现。
	for index in range(Run.Levels.MAX_REWARDS):
		var view := Node3D.new()
		road.add_child(view)
		var body := cylinder(view, Vector3(0, 0.65, 0), 0.38, 0.18, material("reward", Color("ffd15a"), 0.4).duplicate())
		body.name = "RewardBody"
		body.rotation.z = PI / 2
		for socket in range(2):
			var mark := cylinder(view, Vector3(0, 0.025, 0), 1.25, 0.025, material("reward_mark", Color("50ded5"), 0.2))
			mark.name = "Socket%d" % socket
		var sign := Label3D.new()
		sign.name = "RewardLabel"
		sign.position.y = 1.8
		sign.font_size = 32
		sign.pixel_size = 0.007
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		view.add_child(sign)
		reward_views.append(view)
	road.add_child(finish_view)
	var mat := material("finish", Color("65eee4"), 0.6)
	box(finish_view, Vector3(0, 0.03, 0), Vector3(ROAD_HALF * 2, 0.04, 0.5), mat)
	for side in [-1, 1]: box(finish_view, Vector3(side * (ROAD_HALF - 0.3), 3, 0), Vector3(0.3, 6, 0.3), mat)
	var sign := Label3D.new()
	sign.text = "山脊尽头 · 两人到达"
	sign.position.y = 5
	sign.font_size = 64
	sign.pixel_size = 0.01
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	finish_view.add_child(sign)

func sync_rewards() -> void:
	# 重试或进下一关时本关收益清零，奖励编号会复用，已播报记录随之清空。
	var claims: int = run.coins + run.prizes
	if claims < last_claims: announced.clear()
	last_claims = claims
	for reward in run.rewards:
		if not reward.claimed or announced.has(reward.id): continue
		announced[reward.id] = true
		var world := Vector3(reward.position.x / SCALE, 0.65, -(reward.position.y - run.distance) / SCALE)
		match reward.kind:
			"coin":
				sfx.play("coin", -8.0, randf_range(0.97, 1.06))
				spawn_flyer(world, Color("ffd15a"), 10)
			"prize":
				sfx.play("prize", -3.0)
				spawn_flyer(world, Color("f78cd4"), 100)
			"shield":
				sfx.play("shield", -4.0)
	for index in range(reward_views.size()):
		var view := reward_views[index]
		view.visible = index < run.rewards.size()
		if not view.visible: continue
		var reward: Dictionary = run.rewards[index]
		view.visible = not reward.claimed and reward.position.y - run.distance > -440 and reward.position.y - run.distance < 3600
		view.position = Vector3(reward.position.x / SCALE, 0, -reward.position.y / SCALE)
		var body: MeshInstance3D = view.get_node("RewardBody")
		body.rotation.y = run.elapsed * 2
		body.material_override.albedo_color = {"coin": Color("ffd15a"), "prize": Color("f78cd4"), "shield": Color("68dff5")}[reward.kind]
		body.material_override.emission = body.material_override.albedo_color
		var sign: Label3D = view.get_node("RewardLabel")
		sign.visible = false
		var staggered: bool = reward.get("staggered", false)
		for socket in range(2):
			var mark: MeshInstance3D = view.get_node("Socket%d" % socket)
			mark.visible = reward.kind == "prize" and (socket == 0 or staggered)
			mark.position.z = (-1.5 if socket == 0 else 1.5) if staggered else 0.0
			var radius: float = minf(reward.radius, Run.Levels.PRIZE_SOCKET_MAX_RADIUS) if staggered else reward.radius
			mark.mesh.top_radius = radius / SCALE
			mark.mesh.bottom_radius = radius / SCALE
	finish_view.position.z = -(run.finish_distance() - run.world_origin) / SCALE
	finish_view.visible = run.finish_distance() - run.total_distance() < 3600

func build_charge_gate(view: Node3D = null) -> void:
	if view == null: view = charge_gate_view
	charge_gate_views.append(view)
	road.add_child(view)
	view.name = "ChargeGate"
	var steel := material("gate_steel", Color("385360"))
	var energy := material("gate_energy", Color("ffc06b"), 0.4)
	for side in [-1, 1]:
		box(view, Vector3(side * (ROAD_HALF + 0.4), 2.5, -7.8), Vector3(0.6, 5, 0.8), steel)
	box(view, Vector3(0, 5.1, -7.8), Vector3(ROAD_HALF * 2 + 1.4, 0.4, 0.8), steel)
	var door := box(view, Vector3(0, 2.5, -7.8), Vector3(ROAD_HALF * 2 + 1.0, 5, 0.6), energy)
	door.name = "Door"
	for side in [-1, 1]:
		var zone_center: float = (Run.ChargeGate.ZONE_INNER + Run.ChargeGate.ZONE_OUTER) * 0.5 / SCALE
		var zone_width: float = (Run.ChargeGate.ZONE_OUTER - Run.ChargeGate.ZONE_INNER) / SCALE
		var zone := box(view, Vector3(side * zone_center, 0.02, -3), Vector3(zone_width, 0.025, 3), zone_material("gate_zone", Color(0.3, 0.85, 0.8, 0.28)))
		zone.name = "LeftZone" if side < 0 else "RightZone"
	var receiver := cylinder(view, Vector3(0, 1.4, -3), Run.ChargeGate.RECEIVER_RADIUS / SCALE, 0.3, energy)
	receiver.name = "Receiver"
	var stem := box(view, Vector3(0, 0.7, -3), Vector3(0.15, 1.4, 0.15), steel)
	stem.name = "ReceiverStem"
	for side in [-1, 1]:
		var plate := cylinder(view, Vector3(side * 2.25, 0.04, -3), Run.SyncPlates.PLATE_RADIUS / SCALE, 0.06, steel)
		plate.name = "LeftPlate" if side < 0 else "RightPlate"
		plate.visible = false
	var bar := box(view, Vector3(0, 3.1, -3), Vector3(3, 0.16, 0.12), material("gate_progress", Color("68dce3"), 0.5))
	bar.name = "Progress"
	var sign := Label3D.new()
	sign.name = "Status"
	sign.position = Vector3(0, 4, -3)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 36
	sign.pixel_size = 0.008
	view.add_child(sign)
	var winch := Node3D.new()
	winch.name="Winch"
	view.add_child(winch)
	var drum := cylinder(winch,Vector3.ZERO,0.2,0.8,material("winch_wood",Color("715337")))
	drum.name="Drum"
	drum.rotation.z=PI/2
	for side in [-1,1]:
		cylinder(winch,Vector3(side*0.43,0,0),0.3,0.07,material("winch_iron",Color("625f54"))).rotation.z=PI/2
		box(winch,Vector3(side*0.5,-0.6,0),Vector3(0.14,1.2,0.2),steel)
	var weight:=box(winch,Vector3(1.3,-0.7,0),Vector3(0.5,0.7,0.5),material("winch_weight",Color("686258")))
	weight.name="Counterweight"
	RelayPowerView.build(self, view)

func sync_charge_gate() -> void:
	while charge_gate_views.size() < run.charge_gates.size(): build_charge_gate(Node3D.new())
	for slot in range(charge_gate_views.size()):
		var view: Node3D = charge_gate_views[slot]
		view.visible = slot < run.charge_gates.size()
		if not view.visible: continue
		var gate: Dictionary = run.charge_gates[slot]
		view.visible = absf(gate.receiver.y - run.distance) < 4000
		view.position.z = -(gate.receiver.y - Run.ChargeGate.HOLD_DISTANCE) / SCALE
		view.get_node("Door").visible = not gate.open
		# 站位、桥头门和模型均按该实例的真实几何定位。
		var local_receiver_z: float=-gate.receiver.y/SCALE-view.position.z
		var door: MeshInstance3D=view.get_node("Door")
		door.position=Vector3(gate.door.get_center().x/SCALE,2.5,-gate.door.get_center().y/SCALE-view.position.z)
		door.mesh.size=Vector3(gate.door.size.x/SCALE,5.0,gate.door.size.y/SCALE)
		for name in ["Receiver","ReceiverStem","Progress","Status"]: view.get_node(name).position.z=local_receiver_z
		for side in range(2):
			var zone_rect:Rect2=gate.left if side==0 else gate.right
			var zone:MeshInstance3D=view.get_node("LeftZone" if side==0 else "RightZone")
			zone.position=Vector3(zone_rect.get_center().x/SCALE,0.02,-zone_rect.get_center().y/SCALE-view.position.z)
			zone.mesh.size=Vector3(zone_rect.size.x/SCALE,0.025,zone_rect.size.y/SCALE)
			var plate:Node3D=view.get_node("LeftPlate" if side==0 else "RightPlate")
			plate.position=zone.position+Vector3(0,0.02,0)
		var winch:Node3D=view.get_node("Winch")
		winch.visible=gate.get("winch",false)
		winch.position=Vector3(gate.receiver.x/SCALE,1.4,local_receiver_z)
		winch.get_node("Drum").rotation.x=gate.charge*TAU
		winch.get_node("Counterweight").position.y=-0.7-gate.charge*0.8
		var plates: bool = gate.get("kind", "charge") == "sync_plates"
		var hold_time: float = Run.SyncPlates.HOLD_TIME if plates else Run.ChargeGate.CHARGE_TIME
		view.get_node("Progress").scale.x = maxf(0.001, gate.charge / hold_time)
		view.get_node("LeftZone").visible = not plates
		view.get_node("RightZone").visible = not plates
		view.get_node("Receiver").visible = not plates and not gate.get("winch",false)
		view.get_node("ReceiverStem").visible = not plates and not gate.get("winch",false)
		for side in range(2):
			var plate: MeshInstance3D = view.get_node("LeftPlate" if side == 0 else "RightPlate")
			plate.visible = plates
			if plates:
				plate.material_override = material("plate_on" if gate.occupied[side] else "plate_off", Color("68dce3") if gate.occupied[side] else Color("385360"), 0.4 if gate.occupied[side] else 0.0)
		view.get_node("Status").text = run.gate_hint(gate)
		RelayPowerView.sync(self, view, gate)
		if gate.open and not gate_announced.get(gate.id, false): sfx.play("prize", -3.0)
		gate_announced[gate.id] = gate.open
	for id in gate_announced.keys():
		if not run.charge_gates.any(func(g): return g.id == id): gate_announced.erase(id)

func clear_controls() -> void:
	blocked_keys.assign(MOVE_KEYS)
	run.reset_input()
	if is_instance_valid(touch): touch.reset()

func key_down(key: int) -> bool:
	if blocked_keys.has(key):
		if not Input.is_physical_key_pressed(key):
			blocked_keys.erase(key)
		return false
	return Input.is_physical_key_pressed(key)

func primary_action() -> void:
	if is_instance_valid(sfx): sfx.play("click", -8.0)
	if run.state == "paused":
		run.pause()
	elif run.state == "complete":
		run.new_campaign()
	elif run.state == "failed" and run.restore_checkpoint():
		# 存档之后领取的奖励已恢复为未领取，清除其播报记录，再次拾取仍有飞币和音效。
		for reward in run.rewards:
			if not reward.claimed: announced.erase(reward.id)
	elif run.state in ["start", "failed"]:
		run.retry(run.state == "failed")
	clear_controls()
	update_ui()

# 所有改变对局的操作都经过这里：单机立即执行；联机发给服务器，由服务器排进同一帧让两端同时执行。
func command(name: String, arg := "") -> void:
	if net.active():
		if net.in_match: net.send_command(name, arg)
		return
	apply_command(name, arg)

func apply_command(name: String, arg := "") -> void:
	match name:
		"primary":
			if run.state != "running" and run.state != "settlement": primary_action()
			return
		"pause":
			if run.state in ["running", "paused"]: run.pause()
		"retry":
			run.retry(run.state == "failed")
		"difficulty":
			if run.state == "start": run.set_difficulty(arg)
	clear_controls()
	sync_view()
	update_ui()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if run.state == "settlement": return
	if event.keycode in MOVE_KEYS and blocked_keys.has(event.keycode): return
	if event.keycode == KEY_ESCAPE:
		command("pause")
	elif event.keycode == KEY_R:
		command("retry")

func _physics_process(delta: float) -> void:
	if capture_mode:
		return
	fail_clock = fail_clock + delta if run.state == "failed" else 0.0
	touch.set_enabled(touch_device and run.state in ["running", "rescue", "settlement"])
	if net.active():
		online_process(delta)
		return
	generation_waiting = not prepare_game_frame()
	if generation_waiting:
		frame_delta = delta
		sync_view()
		return
	var first := Vector2(float(key_down(KEY_D)) - float(key_down(KEY_A)), float(key_down(KEY_W)) - float(key_down(KEY_S)))
	var second := Vector2(float(key_down(KEY_RIGHT)) - float(key_down(KEY_LEFT)), float(key_down(KEY_UP)) - float(key_down(KEY_DOWN)))
	var touch_jump: bool = touch.take_jump()
	if touch.move != Vector2.ZERO: first = touch.move
	var second_jump := key_down(KEY_ENTER)
	var previous_state: String = run.state
	var before := {"heights": run.heights.duplicate(), "shield": run.shield, "shield_uses": run.shield_uses, "locked": locked_threats(), "presses": rescue_presses()}
	run.step(delta, first, second, key_down(KEY_SPACE) or touch_jump, second_jump)
	play_events(before, previous_state)
	fall_clock = fall_clock + delta if falling() else 0.0
	if run.state != previous_state: clear_controls()
	frame_delta = delta
	sync_view()

# 联机：本机只采集自己那一个角色的输入上传；模拟严格按服务器下发的帧推进，没有新帧就等待。
func online_process(delta: float) -> void:
	if not net.in_match:
		sync_view()
		return
	var move := Vector2(float(key_down(KEY_D) or key_down(KEY_RIGHT)) - float(key_down(KEY_A) or key_down(KEY_LEFT)),
		float(key_down(KEY_W) or key_down(KEY_UP)) - float(key_down(KEY_S) or key_down(KEY_DOWN)))
	if touch.move != Vector2.ZERO: move = touch.move
	var touch_jump: bool = touch.take_jump()
	net.send_input(move, key_down(KEY_SPACE) or key_down(KEY_ENTER) or touch_jump)
	var applied := 0
	var started := Time.get_ticks_usec()
	generation_waiting = false
	var queued: int = net.frames.size()
	var limit: int = mini(4, queued - 2) if queued > 8 else (2 if queued > 3 else 1)
	# 保留原有缓冲节奏；只限制积压时的单次追帧量，不丢弃任何帧。
	# 保留未准备好的完整帧，命令只执行一次；不把计算时间算作模拟时间。
	while not net.frames.is_empty() and applied < limit:
		var index: int = net.next_frame
		var frame: Dictionary = net.frames[0]
		if prepared_online_frame != index:
			for entry in frame.cmds: apply_command(entry[1], entry[2])
			prepared_online_frame = index
		if not prepare_game_frame():
			generation_waiting = true
			break
		net.take_frames(1)
		var previous_state: String = run.state
		var before := {"heights": run.heights.duplicate(), "shield": run.shield, "shield_uses": run.shield_uses, "locked": locked_threats(), "presses": rescue_presses()}
		run.step(Run.FIXED_STEP * 2.0, frame.a, frame.b, frame.ja, frame.jb)
		play_events(before, previous_state)
		fall_clock = fall_clock + Run.FIXED_STEP * 2.0 if falling() else 0.0
		if run.state != previous_state: clear_controls()
		net.report(index, run.sync_hash())
		online_frame_applied.emit(index)
		applied += 1
		if Time.get_ticks_usec() - started >= 6000: break
	frame_delta = delta * maxi(1, applied)
	sync_view()

func start_online_match(seed: int) -> void:
	prepared_online_frame = -1
	run.cancel_generation()
	run.lockstep = true
	run.random_seed = false
	run.difficulty = "普通"
	run.seed_value = seed
	run.new_campaign()
	run.state = "start"
	fall_clock = 0.0
	failed_animation_started = [false, false]
	view_revision = -1
	clear_controls()
	sync_view()
	update_ui()

func stop_online_match(_reason: String) -> void:
	if run.state == "running": run.pause()
	clear_controls()
	update_ui()

func on_net_status(text: String) -> void:
	if is_instance_valid(net_status): net_status.text = text
	update_ui()

func toggle_online() -> void:
	if net.active():
		net.disconnect_from()
		net_status.text = "已断开联机，回到单机同屏双人。"
		run.cancel_generation()
		run.lockstep = false
		run.random_seed = true
		run.new_campaign()
		run.state = "start"
		view_revision = -1
		clear_controls()
		sync_view()
		update_ui()
		return
	save_address(net_address.text.strip_edges())
	net.connect_to(net_address.text)
	update_ui()

func load_address() -> String:
	# 网页版优先用网址给出的服务器，避免浏览器里保存的旧地址失效。
	var page := NetClient.page_default_address()
	if not page.is_empty(): return page
	var config := ConfigFile.new()
	if config.load(NET_CONFIG) != OK: return ""
	return str(config.get_value("online", "address", ""))

func save_address(address: String) -> void:
	var config := ConfigFile.new()
	config.set_value("online", "address", address)
	config.save(NET_CONFIG)

func locked_threats() -> int:
	var count := 0
	for spec in run.hazard_specs:
		if spec.get("locked", false): count += 1
	return count

# 把这一帧规则状态的变化翻成音效：起跳、落地、护盾、迎面物锁定预警、失败、过关。金币和奖品在 sync_rewards 里播。
func play_events(before: Dictionary, previous_state: String) -> void:
	if run.elapsed<rope_sound_time: rope_sound_time=-10.0
	if run.state=="running" and run.rope_tension()>0.96 and run.elapsed-rope_sound_time>1.2:
		sfx.play("rope",-15.0)
		rope_sound_time=run.elapsed
	if run.state == "running":
		for i in range(2):
			if before.heights[i] == 0.0 and run.heights[i] > 0.0: sfx.play("jump", -10.0, 1.0 if i == 0 else 1.15)
			if before.heights[i] > 0.0 and run.heights[i] == 0.0: sfx.play("land", -9.0, 1.0 if i == 0 else 1.1)
	if run.shield_uses > before.shield_uses: sfx.play("shield_break", -3.0)
	if rescue_presses() > before.get("presses", 0): sfx.play("jump", -8.0, 0.8 + run.rescue.get("progress", 0.0) * 0.6)
	if run.state == previous_state: return
	match run.state:
		"failed": sfx.play("fall" if falling() else "hit", -2.0)
		"rescue": sfx.play("warning", -4.0)
		"running":
			if previous_state == "rescue": sfx.play("shield", -3.0)
		"settlement": sfx.play("clear", -2.0)

func rescue_presses() -> int:
	return 0 if run.rescue.is_empty() else run.rescue.presses[0] + run.rescue.presses[1]

func falling() -> bool:
	return run.state == "failed" and (run.fallen[0] or run.fallen[1])

func fail_showing() -> bool:
	return run.state == "failed" and fail_clock < (FAIL_FALL_SHOW if falling() else FAIL_HIT_SHOW)

# 撞击：推近到出事角色身后侧上方。坠落：跟到崖边，镜头随下坠角色俯视进云雾。
# 救援：从坠落者外侧回望，同时看到吊着的人和拉绳的队友。各机位之间平滑过渡，结束后回到固定机位。
func update_camera() -> void:
	var target := camera_shot()
	var rate := 12.0 if run.state == "failed" and falling() else 4.0
	camera.transform = camera.transform.interpolate_with(target, clampf(frame_delta * rate, 0.0, 1.0))
	if target == camera_home and camera.transform.origin.distance_to(camera_home.origin) < 0.01: camera.transform = camera_home

func camera_shot() -> Transform3D:
	if robots.size() < 2: return camera_home
	if not run.rescue.is_empty() and run.state in ["rescue", "paused"]:
		var hanging: Vector3 = robots[run.rescue.role].position
		var holder: Vector3 = robots[1 - run.rescue.role].position
		var away := Vector3(hanging.x - holder.x, 0, hanging.z - holder.z)
		away = away.normalized() if away.length() > 0.01 else Vector3(0, 0, -1)
		return Transform3D.IDENTITY.translated(hanging + away * 7.0 + Vector3(0, 4.5, 0)).looking_at((hanging + holder) * 0.5 + Vector3(0, 0.6, 0), Vector3.UP)
	if run.state != "failed": return camera_home
	var role := 1 if run.reason.begins_with("02") else 0
	if falling(): role = 0 if run.fallen[0] else 1
	var single: bool = falling() or run.reason.begins_with("01") or run.reason.begins_with("02")
	var focus: Vector3 = robots[role].position if single else (robots[0].position + robots[1].position) * 0.5
	var eye: Vector3
	var look: Vector3
	if falling() and absf(focus.x) > ROAD_HALF - 1.0:
		# 走出路边：镜头移到崖外半空，侧看角色沿崖壁坠入云雾。
		var out_side := signf(focus.x)
		eye = Vector3(focus.x + out_side * 9.0, focus.y+6.0, focus.z + 10.0)
		look = Vector3(focus.x - out_side * 1.0, focus.y + 0.6, focus.z)
	elif falling():
		# 路面缺口：镜头越过缺口到对侧上方回望，俯视角色掉进镂空（不被近侧岩壁挡住）。
		eye = Vector3(focus.x + 1.5, focus.y+8.0, focus.z - 8.0)
		look = Vector3(focus.x, focus.y + 0.6, focus.z - 1.0)
	else:
		eye = Vector3(focus.x * 0.7, 4.6, focus.z + 7.5)
		look = focus + Vector3(0, 1.3, -1.5)
	return Transform3D.IDENTITY.translated(eye).looking_at(look, Vector3.UP)

func sync_gap_model(view: Node3D, rect: Rect2) -> void:
	# 窄桥两侧缺口延伸到路外；显示只画路面以内部分，坑底不悬在悬崖外。
	if view.get_meta("gap_rect", Rect2()) != rect:
		view.set_meta("gap_rect", rect)
		var left := maxf(rect.position.x / SCALE, -ROAD_HALF)
		var right := minf(rect.end.x / SCALE, ROAD_HALF)
		var width: float = maxf(0.05, right - left)
		var length: float = rect.size.y / SCALE
		view.position.x = (left + right) * 0.5
		view.set_meta("gap_center_x", view.position.x)
		view.get_node("GapMist").mesh.size = Vector3(width + 2.0, 0.05, length + 2.0)
		var narrow: bool = rect.size.y >= Run.Templates.NARROW_LENGTH - 0.01
		for edge_name in ["GapNear", "GapFar", "GapNearInner", "GapFarInner", "GapNearWall", "GapFarWall"]:
			var edge: MeshInstance3D = view.get_node(edge_name)
			edge.mesh.size.x = width
			var inset: float = 0.07 if edge_name.ends_with("Inner") else (0.03 if edge_name.ends_with("Wall") else 0.2)
			edge.position.z = (1 if edge_name.begins_with("GapNear") else -1) * (length / 2 + inset)
		for wall_name in ["GapLeft", "GapRight"]:
			var sign_x := -1 if wall_name == "GapLeft" else 1
			var wall: MeshInstance3D = view.get_node(wall_name)
			wall.mesh.size.z = length
			wall.position.x = sign_x * (width / 2 + 0.03)
			# 窄桥一侧只画桥板厚度，桥下悬空；其余缺口侧壁深入崖下。
			var depth: float = PLANK_THICKNESS if narrow and (left if sign_x < 0 else right) * sign_x < ROAD_HALF - 0.01 else GAP_DEPTH
			wall.mesh.size.y = depth
			wall.position.y = -depth / 2
			var rim: MeshInstance3D = view.get_node(wall_name + "Rim")
			rim.mesh.size.z = length
			rim.position.x = sign_x * (width / 2 + 0.15)
			# 贴着悬崖外沿的一边不画桥边警戒条。
			rim.visible = (left if sign_x < 0 else right) * sign_x < ROAD_HALF - 0.01
		var approach: MeshInstance3D = view.get_node("GapApproach")
		approach.mesh.size.x = width
		approach.position.z = length / 2 + 0.4 + 1.2
		view.get_node("WarningLabel").text = "独木窄桥 · 只容一人，前后依次通过" if narrow else ("长缺口 · 两人同侧绕行" if rect.size.y >= Run.Surfaces.LONG_GAP else Run.hazard_name("road_gap"))
	view.position.x = view.get_meta("gap_center_x")
	var approach: MeshInstance3D = view.get_node("GapApproach")
	approach.material_override.albedo_color.a = 0.3 + 0.25 * sin(run.elapsed * 7.0)

func sync_view() -> void:
	if view_revision != run.revision: rebuild_hazard_views()
	sync_rewards()
	sync_charge_gate()
	# 云雾随前进向后流动，另带一点自身漂移。
	for layer in range(mist_layers.size()):
		mist_layers[layer].uv1_offset = Vector3(run.elapsed * 0.004 * (layer + 1), run.total_distance() / SCALE / 300.0, 0)
	var forward: float = run.distance / SCALE
	for i in range(2):
		var presses: int = 0 if run.rescue.is_empty() else run.rescue.presses[i]
		if presses > rescue_seen[i]: rescue_pulse[i] = 1.0
		rescue_seen[i] = presses
		rescue_pulse[i] = maxf(0.0, rescue_pulse[i] - frame_delta * 6.0)
	road.position.z = forward
	for chunk in scenery:
		if chunk.has_meta("road_slot"):
			# 固定 63 个道路/栏杆/装饰槽，循环重定位，不再建新路面节点。
			var slot: int = chunk.get_meta("road_slot")
			var local_z := fposmod(-slot * 8.0 + run.total_distance() / SCALE + 480.0, 504.0) - 480.0
			chunk.position.z = local_z - forward
			sync_road_support(chunk)
		chunk.visible = chunk.position.z + forward > -180 and chunk.position.z + forward < 22
		if chunk.has_meta("arch"):
			chunk.visible = chunk.position.z + forward < -12 and chunk.position.z + forward > -180
	for index in range(hazard_views.size()):
		var view := hazard_views[index]
		var sample: Dictionary = run.hazard_sample(index, run.elapsed)
		var rect: Rect2 = sample.rect
		view.position = Vector3(rect.get_center().x / SCALE, 0, -rect.get_center().y / SCALE)
		view.visible = rect.get_center().y - run.distance > -440 and rect.get_center().y - run.distance < 3600
		if run.kinds[index] in Run.Terrain.KINDS:
			sync_terrain_model(view, index)
			continue
		if run.kinds[index] in Run.Industrial.KINDS:
			sync_industrial_model(view, index, sample)
			continue
		if run.kinds[index] == "sweeper":
			var geometry: Dictionary = sample.geometry
			view.get_node("SweeperArm").rotation.y = geometry.angle
			view.get_node("WarningFootprint").visible = sample.warning
			view.get_node("WarningLabel").text = "旋转扫杆 · 支座须绕行 · 低杆可跳"
			continue
		if run.kinds[index] == "road_gap":
			sync_gap_model(view, rect)
			continue
		if run.hazard_specs[index].get("front", false):
			var route: MeshInstance3D = view.get_node("FlightRoute")
			var length: float = maxf(0.05, absf(run.hazard_specs[index].velocity.y) * sample.ttc / SCALE)
			route.mesh.size.z = length
			route.position.z = length * 0.5
		if Run.Threats.is_ball(run.kinds[index]):
			var body: MeshInstance3D = view.get_node("BallBody")
			body.rotation.x = run.hazard_specs[index].travel / (rect.size.x * 0.5)
			var ring: MeshInstance3D = view.get_node("ContactRing")
			ring.visible = run.rope.touches(run.obstacle_ids[index])
			for contact in run.rope.contacts:
				if contact.id != run.obstacle_ids[index]: continue
				ring.mesh.top_radius = contact.radius / SCALE
				ring.mesh.bottom_radius = contact.radius / SCALE
				ring.position.y = clampf(rect.size.x * 0.5, minf(run.rope.height_a, run.rope.height_b), maxf(run.rope.height_a, run.rope.height_b)) / SCALE
			ring.material_override.albedo_color = Color("ff5a48") if run.hazard_specs[index].blocked else Color("ffc06b")
			view.get_node("FlightRoute").visible = sample.warning
			var sign: Label3D = view.get_node("WarningLabel")
			sign.text = ("受阻 %.2f 秒 · " % run.hazard_specs[index].blocked_time if run.hazard_specs[index].blocked else "迎面 %.1f 秒 · " % sample.ttc) + Run.hazard_name(run.kinds[index])
			continue
		if run.kinds[index] == "pillar":
			# 接触反馈：挂住绳索的柱子亮起接触环，受阻时转红。
			var ring: MeshInstance3D = view.get_node("ContactRing")
			ring.visible = index < run.obstacle_ids.size() and run.rope.touches(run.obstacle_ids[index])
			ring.material_override.albedo_color = Color("ff5a48") if run.rope_bound or run.rope_failed else Color("ffc06b")
			ring.material_override.emission = ring.material_override.albedo_color
			continue
		if run.kinds[index] == "cargo": continue
		var volume: MeshInstance3D = view.get_node("DangerVolume")
		volume.visible = sample.active
		volume.position.y = (sample.bottom + sample.top) / SCALE / 2
		volume.mesh.size.y = maxf(0.001, (sample.top - sample.bottom) / SCALE)
		for child in view.get_children():
			if child.has_meta("spike"):
				child.visible = sample.active
				child.scale.y = maxf(0.001, sample.top / run.obstacle_heights[index])
				child.position.y = sample.top / SCALE / 2
		var footprint: MeshInstance3D = view.get_node("WarningFootprint")
		footprint.material_override.albedo_color = Color("ffcb55") if sample.warning else (Color("e9553a") if sample.active else Color("51cdb6"))
		var sign: Label3D = view.get_node("WarningLabel")
		sign.text = ("预警 · " if sample.warning else ("危险 · " if sample.active else "安全时窗 · ")) + Run.hazard_name(run.kinds[index])
		if run.kinds[index].begins_with("fly_") or run.kinds[index] == "rocket":
			view.get_node("FlightRoute").visible = sample.warning
			footprint.visible = sample.active or sample.warning
			sign.visible = sample.active or sample.warning
			if run.hazard_specs[index].get("front", false):
				sign.text = "迎面 %.1f 秒 · " % sample.ttc + Run.hazard_name(run.kinds[index])
	# 场景里只保留机关和道具本体：文字说明、地面预警区、轨迹线、警戒条和透明危险包围盒一律隐藏。
	for view in hazard_views:
		for warning_name in WARNING_NODES:
			var node: Node3D = view.get_node_or_null(warning_name)
			if node != null: node.visible = false
		# 火箭和地刺的危险盒只是半透明包络，外形已由机身/刺锥表达。
		var volume: MeshInstance3D = view.get_node_or_null("DangerVolume")
		if volume != null and volume.material_override != null and volume.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			volume.visible = false
	for i in range(2):
		var p: Vector2 = run.a.position if i == 0 else run.b.position
		robots[i].position = Vector3(p.x / SCALE, run.foot_height(i) / SCALE, -p.y / SCALE + forward)
		# 小角度倾斜反馈四向输入；镜头保持不变，松开后回正。
		robots[i].rotation.z = -run.move_directions[i].x * 0.06 if run.state == "running" else 0.0
		# 跑动时身体前倾，加速前冲时更明显；角色背对镜头，负角度是向前。
		robots[i].rotation.x = -0.13 - run.move_directions[i].y * 0.07 if run.state == "running" else 0.0
		robots[i].rotation.y = 0.0
		shadows[i].position = Vector3(p.x / SCALE, run.floor_heights[i] / SCALE + 0.018, -p.y / SCALE + forward)
		# 阴影随生产跳跃高度缩小，最高点（JUMP_APEX）缩至 0.64。
		shadows[i].scale = Vector3.ONE * (1.0 - 0.36 * run.heights[i] / Run.JUMP_APEX + run.land_time[i] * 1.2)
		# 死亡位移来自固定步，挂点与身体共同下落。
		var drop: float = run.death_time if falling() else 0.0
		if run.state == "failed" and run.death_positions.size() == 2:
			var body: Vector3 = run.death_positions[i]
			robots[i].position = Vector3(body.x / SCALE, body.y / SCALE, -body.z / SCALE + forward)
		var hanging: bool = not run.rescue.is_empty() and i == run.rescue.role
		if not run.rescue.is_empty():
			# 救援：坠落者吊在崖边绳下，随进度被拉上来；救援者后仰拉绳。
			var climb: float = clampf(run.rescue.get("climb", 0.0) / Run.RESCUE_CLIMB_TIME, 0.0, 1.0)
			# 两人面对面：救援者朝坠落者收绳，坠落者面朝崖壁往上爬。
			var holder_p: Vector2 = run.b.position if run.rescue.role == 0 else run.a.position
			var facing: Vector2 = (run.rescue.hang - holder_p) * (1.0 if not hanging else -1.0)
			if facing.length() > 1.0 and climb < 0.5:
				robots[i].rotation.y = atan2(-facing.x, facing.y)
			if hanging:
				# 吊着时随连按往上蹭，每按一下身体一抖；拉满后沿弧线翻上崖沿、走到落脚点。
				var hang: Vector2 = run.rescue.hang
				var hang_y: float = lerpf(-2.0, -0.4, run.rescue.progress) + sin(run.rescue.time * 9.0) * 0.06 + rescue_pulse[i] * 0.18
				var spot := Vector3(hang.x / SCALE, hang_y, -hang.y / SCALE + forward)
				if run.rescue.has("climb"):
					var anchor: Vector2 = run.rescue.anchor
					var top := Vector3(anchor.x / SCALE, 0.0, -anchor.y / SCALE + forward)
					var lift: float = smoothstep(0.0, 0.55, climb)
					var walk: float = smoothstep(0.45, 1.0, climb)
					spot = Vector3(lerpf(spot.x, top.x, walk), lerpf(spot.y, 0.0, lift) + sin(climb * PI) * 0.5, lerpf(spot.z, top.z, walk))
				robots[i].position = spot
				robots[i].rotation.x = lerpf(-0.08 - rescue_pulse[i] * 0.12, 0.0, climb)
			else:
				# 救援者的后仰与倒手收绳由 RopePull 动作表现；每次按键再猛拽一下。
				robots[i].rotation.x = lerpf(0.08 + rescue_pulse[i] * 0.25, 0.0, climb)
		if run.state == "rescue":
			var body: Vector3=run.rescue_body_position(i)
			robots[i].position=Vector3(body.x/SCALE,body.y/SCALE,-body.z/SCALE+forward)
		if drop > 0:
			# 从路边坠落的角色边翻滚边向外飘离崖壁，不被扶壁岩挡住。
			robots[i].rotation.x = drop * 2.4
			robots[i].rotation.z = drop * (0.9 if i == 0 else -0.9)
		# 身体倾斜和翻滚均绕腰部旋转，物理挂点不会从身体上飘开。
		robots[i].position += Vector3(0,1.4,0)-robots[i].basis*Vector3(0,1.4,0)
		robots[i].get_node("RopeKnot").visible=run.rope.physical.is_empty() or run.rope.physical.bound[i]
		shadows[i].visible = drop == 0.0 and not hanging
		if i < animation_players.size():
			var player := animation_players[i]
			if run.state == "paused":
				player.speed_scale = 0
			else:
				player.speed_scale = 1
				if run.state == "failed":
					if not failed_animation_started[i]:
						play_action(player, "HitRecieve_1")
						failed_animation_started[i] = true
				else:
					failed_animation_started[i] = false
					var waiting: bool = run.charge_gate.active and not run.charge_gate.open and run.distance >= run.charge_gate.receiver.y and run.move_directions[i] == Vector2.ZERO
					if not run.rescue.is_empty() and run.state == "rescue":
						# 救援者倒手收绳；坠落者沿绳倒手攀爬，翻上崖沿后期改为跑步迈上来。
						# 两个循环的播放速度跟随连按节奏，按得越快拉得越快。
						var climb_t: float = run.rescue.get("climb", 0.0) / Run.RESCUE_CLIMB_TIME
						play_action(player, "RopePull" if i != run.rescue.role else ("Run" if climb_t > 0.5 else "Climb"))
						if not player.current_animation.ends_with("Run"):
							player.speed_scale = 0.8 + rescue_pulse[i] * 1.6 + (0.6 if climb_t > 0.0 else 0.0)
					else:
						play_action(player, "Jump" if run.heights[i] > 0 else ("Run" if run.state == "running" and not waiting else "Idle"))
					if player.current_animation.ends_with("Run"):
						player.speed_scale = run_animation_speed()
					# 动画与物理抛物线同步；不让 Jump 自带位移改变碰撞中心。
					if run.heights[i] > 0:
						player.seek(clampf((Run.JUMP_SPEED - run.vertical_speed[i]) / Run.GRAVITY / (2 * Run.JUMP_SPEED / Run.GRAVITY), 0, 1) * player.current_animation_length, true)
					elif run.actions[i] == "Land" and last_actions[i] != "Land":
						player.seek(0, true)
			last_actions[i] = run.actions[i]
	# 生产物理链同时用于碰撞、存档和画面。道路只在这里转换坐标。
	var rope_points: Array[Vector3] = []
	if not run.rope.physical.is_empty():
		for p: Vector3 in run.rope.physical.points:
			rope_points.append(Vector3(p.x / SCALE, p.y / SCALE, -p.z / SCALE + forward))
	else:
		rope_points = [robots[0].position + Vector3(0, 1.4, 0), robots[1].position + Vector3(0, 1.4, 0)]
	rope_view.simulate(rope_points, 0, Color.WHITE, 0)
	for role in range(2):
		var bound:bool=run.rope.physical.is_empty() or run.rope.physical.bound[role]
		if rope_sound_bound[role] and not bound: sfx.play("buckle",-12.0)
		rope_sound_bound[role]=bound
	update_camera()
	update_ui()

func update_ui() -> void:
	if not is_instance_valid(hud):
		return
	loading_box.visible = run.async_startup_pending and run.state == "running"
	if loading_box.visible:
		var progress: float = run.startup_progress()
		loading_progress.value = progress * 100.0
		loading_label.text = "正在准备道路 %d%%\n%s" % [int(progress * 100), "正在准备场景…" if progress >= 1.0 else "出发前预计算前方路段，减少途中等待"]
	hud.text = "第 %d/3 关 · %s · 金币 %d · 奖品 %d · 护盾 %s" % [run.level_index + 1, run.difficulty, run.coins, run.prizes, "无敌 %.1fs" % maxf(0, run.invulnerable_until - run.elapsed) if run.elapsed < run.invulnerable_until else ("1" if run.shield else "0")]
	if run.charge_gate.active: hud.text += "\n" + run.gate_hint(run.charge_gate)
	hud.text += "\n本地双人 · 01 WASD / 空格 · 02 方向键 / 回车"
	distance_label.text = "绳长 %.2fm · 张紧 %d%% · 终点 %.0fm" % [Run.LINK_LIMIT / SCALE, int(run.rope_tension()*100), maxf(0, run.finish_distance() - run.progress()) / SCALE]
	match run.rope_status():
		"contact": distance_label.text += (" · 滚球带绳 张力 %d%%" if run.ball_contact() else " · 绳索挂柱 张力 %d%%") % int(run.rope_tension() * 100)
		"blocked": distance_label.text += " · 绕柱受阻 %.1f / %.1f 秒：退回同侧" % [run.rope_block_time(), Run.ROPE_BLOCK_LIMIT]
		"unwinding": distance_label.text += " · 正在解围 %.1f / %.1f 秒" % [run.rope_block_time(), Run.ROPE_BLOCK_LIMIT]
	progress_fill.size.x = clampf(run.progress() / run.finish_distance(), 0, 1) * 1176
	# 没有金币在飞时直接对齐真实分数（重试清零、结算换算都在这里收口）。
	if flying == 0: shown_score = target_score()
	score_label.text = str(shown_score)
	for button in difficulty_buttons:
		button.visible = run.state == "start"
		button.text = button.text.trim_prefix("✓ ")
		if button.text == run.difficulty: button.text = "✓ " + button.text
	panel.visible = run.state not in ["running", "rescue"] and not fail_showing()
	rescue_box.visible = run.state == "rescue"
	if run.state == "rescue":
		var holder: int = 1 - run.rescue.role
		var keys := ["空格", "回车"]
		var tap := "（触屏点右半屏）" if touch_device else ""
		rescue_label.text = "%02d 狂按%s拉人！%02d 按%s往上爬%s" % [holder + 1, keys[holder], run.rescue.role + 1, keys[run.rescue.role], tap]
		rescue_fill.size.x = RESCUE_BAR * run.rescue.progress
		rescue_timer_fill.size.x = RESCUE_BAR * maxf(0.0, 1.0 - run.rescue.time / Run.RESCUE_TIME)
	primary.visible = run.state != "settlement"
	match run.state:
		"start":
			title.text = "共生归航"
			subtitle.text = "【本地双人】01：WASD 移动 / 空格跳；02：方向键移动 / 回车跳。\n" + "两侧是悬崖，没有护栏：走出路面会坠落，并把队友拖下去。\n自动推进 · 前后调节 ±5 米 · 连线最多 7.33 米。\n三关各约 100 秒，每局地图、陷阱和奖励随机；两人共同到终点后分别确认。
吃到的金币会飞进右上角得分。\n金币共享，奖品需两人到位；护盾吸收一次角色伤害，不解绳索受阻。松开启动键再跳。"
			primary.text = "开始归航  /  Enter"
		"paused":
			title.text = "归航已暂停"
			subtitle.text = "道路、跳跃与计时已冻结。\n01：WASD / 空格；02：方向键 / 回车。\n恢复后请松开旧按键再按下。\n麻绳拉紧会牵引队友，请靠近或同侧绕行。"
			primary.text = "继续归航  /  Esc"
		"failed":
			title.text = "连接中断"
			subtitle.text = run.reason + "\n第 %d 关已前进 %.0f 米；已完成总分 %d。\n%s\n" % [run.level_index + 1, run.progress() / SCALE, run.total_score(), checkpoint_text()] + ("分侧过柱会让绳索绕住柱子；受阻后退回并绕到同一侧可以解围。" if run.rope_failed else ("路两侧没有护栏，一人踩空两人都会被拖下去。" if falling() else "两人协调选择安全走廊，保持地面连接距离。"))
			primary.text = "从存档点继续  /  Enter" if not run.checkpoint.is_empty() else "两人共同重试  /  R"
			if run.reason.contains("滚球") or run.reason.contains("滚石") or run.reason.contains("铁刺球"):
				subtitle.text += "\n滚球应共同同侧避让；接触后及时后撤解围，耗尽长度持续 0.8 秒会失败。"

		"settlement":
			var result: Dictionary = run.results[-1]
			title.text = "第 %d 关完成 · %s" % [run.level_index + 1, result.rating]
			subtitle.text = "金币 %d ×10 + 合作奖品 %d ×100 = %d 分\n本关 %.1f 秒 · 已完成累计 %d 分\n先松开按键，再分别按下确认：\n01 空格：%s    02 回车：%s\n双方确认后%s。" % [result.coins, result.prizes, result.score, result.seconds, run.total_score(), "已确认" if run.confirmations[0] else "待确认", "已确认" if run.confirmations[1] else "待确认", "查看总成绩" if run.level_index == 2 else "进入下一关"]
		"complete":
			title.text = "三关归航完成"
			subtitle.text = "团队总成绩：%d 分\n" % run.total_score()
			for result in run.results:
				subtitle.text += "第 %d 关：%d 分 · %s · %.1f 秒\n" % [result.level, result.score, result.rating, result.seconds]
			subtitle.text += "重新开始将清空本轮总成绩。"
			primary.text = "重新开始三关"
	update_online_ui()

func checkpoint_text() -> String:
	if run.checkpoint.is_empty(): return "重试会换一张新的随机地图，清空本关收益和护盾。"
	return "空格/回车：回到 %.0f 米处存档点，地图不变，金币与护盾回到存档时；R：整关重开并换新地图。" % [run.checkpoint.progress / SCALE]

func update_online_ui() -> void:
	var online: bool = net.active()
	net_button.text = "断开" if online else "联机"
	net_address.editable = not online
	pause_button.visible = touch_device and run.state == "running"
	primary.disabled = online and not net.in_match
	if online and not net.in_match:
		title.text = "联机等待中"
		subtitle.text = "两人都连上同一服务器后自动开局。\n左半屏按住滑动＝移动，右半屏点击＝跳跃。"
	if not online and not touch_device:
		bottom_hint.text = "正在准备前方道路…" if generation_waiting else "01：WASD / 空格跳跃与确认   ·   02：方向键 / 回车跳跃与确认   ·   Esc 暂停   ·   R 重试当前关"
		return
	var role_text := "你是 %02d 号 · " % (net.role + 1) if online and net.role >= 0 else ""
	bottom_hint.text = role_text + "左半屏按住滑动移动 · 右半屏点击跳跃与确认 · 右上角暂停"
	if generation_waiting: bottom_hint.text = "正在准备前方道路…"
	if not online: return
	match run.state:
		"start": subtitle.text = role_text + "联机双人：各自控制一个角色。\n左半屏摇杆移动，右半屏点击跳跃（电脑上 WASD/方向键 + 空格/回车）。\n两侧悬崖，连线最多 7.33 米，三关各约 100 秒。"
		"paused": subtitle.text = role_text + "任一方都可以继续；恢复后请先松手再操作。"
		"settlement": subtitle.text += "\n联机：点击右半屏（或空格/回车）确认。"

func build_terrain_model(view: Node3D, index: int) -> void:
	var kind: String = run.kinds[index]
	var rect: Rect2 = run.obstacles[index]
	var spec: Dictionary = run.hazard_specs[index]
	var mat := tex_material("terrain_deck", "monastery_stone_floor", 0.25, Color("bba385"))
	if kind in Run.Terrain.MOVING or kind == "drawbridge":
		var deck := box(view,Vector3(0,-0.12,0),Vector3(rect.size.x/SCALE,0.24,rect.size.y/SCALE),mat)
		deck.name="TerrainDeck"
		# 木板顶面提供连续可读的落脚面，避免桥板在山体阴影里看成黑洞。
		for plank in range(16):
			var depth:float=rect.size.y/SCALE/16.0
			var z:float=-rect.size.y/SCALE/2+(plank+0.5)*depth
			box(deck,Vector3(0,0.13,z),Vector3(rect.size.x/SCALE-0.22,0.035,depth-0.025),material("deck_plank_%d"%(plank%3),[Color("b99b6c"),Color("a88a60"),Color("c2a477")][plank%3]))
		for side in [-1,1]:
			box(deck,Vector3(side*(rect.size.x/SCALE/2-0.1),0.14,0),Vector3(0.16,0.06,rect.size.y/SCALE),material("deck_rim",Color("cda45d")))
		if kind == "lift":
			for side in [-1,1]: cylinder(view,Vector3(side*(rect.size.x/SCALE/2+0.2),0.8,0),0.1,2.0,material("lift_post",Color("655b4e")))
	else:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rows := 8 if kind == "steps" else 24
		for row in range(rows):
			for column in range(8):
				var x0 := rect.position.x+rect.size.x*column/8.0
				var x1 := rect.position.x+rect.size.x*(column+1)/8.0
				var y0 := rect.position.y+rect.size.y*row/rows
				var y1 := rect.position.y+rect.size.y*(row+1)/rows
				var vertices := [Vector2(x0,y0),Vector2(x1,y1),Vector2(x1,y0),Vector2(x0,y0),Vector2(x0,y1),Vector2(x1,y1)]
				for point: Vector2 in vertices:
					var sample_point := Vector2(point.x,(y0+y1)/2) if kind=="steps" else point
					var height: float = Run.Terrain.mesh_height(kind,rect,spec,0,sample_point)
					tool.set_uv(Vector2(point.x,point.y)/SCALE)
					tool.add_vertex(Vector3((point.x-rect.get_center().x)/SCALE,height/SCALE,-(point.y-rect.get_center().y)/SCALE))
				if kind == "steps" and row>0:
					var old_height: float = Run.Terrain.mesh_height(kind,rect,spec,0,Vector2(x0,y0-rect.size.y/rows/2))
					var new_height: float = Run.Terrain.mesh_height(kind,rect,spec,0,Vector2(x0,(y0+y1)/2))
					for corner in [Vector3(x0,old_height,y0),Vector3(x1,new_height,y0),Vector3(x1,old_height,y0),Vector3(x0,old_height,y0),Vector3(x0,new_height,y0),Vector3(x1,new_height,y0)]:
						tool.set_uv(Vector2(corner.x,corner.y)/SCALE)
						tool.add_vertex(Vector3((corner.x-rect.get_center().x)/SCALE,corner.y/SCALE,-(corner.z-rect.get_center().y)/SCALE))
		tool.generate_normals()
		tool.generate_tangents()
		var deck := MeshInstance3D.new()
		deck.mesh=tool.commit()
		deck.material_override=mat
		view.add_child(deck)
	var sign := Label3D.new()
	sign.name="TerrainSign"
	sign.position=Vector3(0,3,0)
	sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size=26
	sign.pixel_size=0.01
	sign.text={"slope":"起伏山脊", "steps":"石阶", "tilt":"倾斜桥面", "lift":"升降平台 · 共同上桥", "ferry":"横移浮台 · 随台移动", "drawbridge":"合作吊桥"}[kind]
	view.add_child(sign)

func sync_terrain_model(view: Node3D, index: int) -> void:
	var kind: String=run.kinds[index]
	var sample: Dictionary=run.terrain_sample(index,run.elapsed,run.obstacles[index].get_center())
	if kind in Run.Terrain.MOVING: view.position.y=sample.height/SCALE
	if kind=="drawbridge":
		var opening: float=sample.opening
		var deck: Node3D=view.get_node("TerrainDeck")
		var half: float=run.obstacles[index].size.y/SCALE/2
		deck.rotation.x=-(1.0-opening)*PI/2
		deck.position=Vector3(0,sin((1.0-opening)*PI/2)*half-0.12,half-cos((1.0-opening)*PI/2)*half)
