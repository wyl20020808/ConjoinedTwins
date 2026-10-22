extends RefCounted
# 「枯根巨像」的画面：模型与动作、地面预警、根刺/根浪/孢果/缚根、入口根墙、三阶段荆棘、
# 树心光与顶部血条。全部只读模拟状态（run.elapsed 与 Boss 事件字段），不写回模拟；
# 一次性特效按“状态 + 技能序号”去重，只在状态切换的那一帧触发。

const Boss = preload("res://scripts/journey_boss.gd")
const TELEGRAPH = preload("res://scripts/boss_telegraph.gdshader")
const BODY := "res://assets/boss/rigged/root_colossus.glb"
const SPIKE := "res://assets/boss/root_spike.glb"
const POD := "res://assets/boss/seed_pod.glb"
const KNOT := "res://assets/boss/binding_root.glb"
const WALL := "res://assets/boss/root_wall.glb"
const PATHS := [BODY, SPIKE, POD, KNOT, WALL]
const SCALE := 20.0
# 模型原生高 1、正前方 +X；放大到约 16 米并转向镜头（+Z）。
const HEIGHT := 16.5
# 胸口树心在模型里的高度比例与前凸距离（米）；模型自带发光树心，额外的发光核只在硬直时放大。
const CHEST := 0.6
const CHEST_FRONT := 1.7
# 换动作时用 0.25 秒（模拟时间）把上一帧骨骼姿势过渡到新动作，避免瞬间跳变显得僵硬。
const CROSSFADE := 0.25
const IDLE_LOOP := 6.0
const SPIKE_STEP := 90.0
const SPIKE_SIZE := 3.2
const MAX_SPIKES := 48
const THORN_STEP := 80.0
const AMBER := Color("ffb347")
const TOXIC := Color("c8e060")
const DANGER := Color("ff5a2a")

static func world(point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x/SCALE, height, -point.y/SCALE)

static func first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D: return node
	for child in node.get_children():
		var found := first_mesh(child)
		if found != null: return found
	return null

static func meshes(node: Node, result: Array) -> void:
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): meshes(child, result)

static func telegraph(parent: Node3D, name: String, shape: int, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	node.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = TELEGRAPH
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("tint", color)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.hide()
	parent.add_child(node)
	return node

# 道具模型：按目标尺寸（米）缩放，底面贴地居中。
static func prop(game, parent: Node3D, path: String, size: Vector3) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	game.tripo_model(holder, path, size, Vector3(0, size.y*0.5, 0))
	return holder

# 根刺用 MultiMesh：共享 Tripo 网格，每帧只更新钻出中的实例。
static func spike_field(parent: Node3D, name: String, count: int) -> MultiMeshInstance3D:
	var source: Node3D = load(SPIKE).instantiate()
	var mesh := first_mesh(source)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh.mesh
	multi.instance_count = count
	multi.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = multi
	node.set_meta("base", mesh.transform)
	parent.add_child(node)
	source.free()
	return node

static func build(game, root: Node3D, event: Dictionary) -> void:
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var boss := Node3D.new()
	boss.name = "Colossus"
	body.add_child(boss)
	var model: Node3D = load(BODY).instantiate()
	model.name = "Figure"
	model.scale = Vector3.ONE*HEIGHT
	model.rotation.y = -PI/2
	boss.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player: AnimationPlayer = players[0]
		player.speed_scale = 0.0
		# 只在 animate() 里按模拟时间取样，引擎不再每帧覆盖骨骼，换动作的渐变才保得住。
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		boss.set_meta("anim", player)
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty(): boss.set_meta("skeleton", skeletons[0])
	var parts: Array = []
	meshes(model, parts)
	boss.set_meta("meshes", parts)
	# 树心：胸口的发光核与补光，硬直时放大变亮。
	var heart := MeshInstance3D.new()
	heart.name = "Heart"
	var sphere := SphereMesh.new()
	sphere.radius = 0.75
	sphere.height = 1.5
	heart.mesh = sphere
	heart.material_override = game.material("boss_heart", AMBER, 4.0)
	heart.position = Vector3(0, HEIGHT*CHEST, CHEST_FRONT)
	heart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	boss.add_child(heart)
	var light := OmniLight3D.new()
	light.name = "HeartLight"
	light.light_color = AMBER
	light.omni_range = 16.0
	light.light_energy = 1.5
	light.position = Vector3(0, HEIGHT*CHEST, 2.2)
	boss.add_child(light)
	# 预警层。
	var marks := Node3D.new()
	marks.name = "Telegraphs"
	root.add_child(marks)
	for n in range(5): telegraph(marks, "Lane%d"%n, 0, DANGER)
	telegraph(marks, "Band", 0, DANGER)
	for n in range(6): telegraph(marks, "Circle%d"%n, 1, TOXIC)
	telegraph(marks, "Rip", 1, DANGER)
	spike_field(root, "Spikes", MAX_SPIKES)
	# 根浪（巨臂横扫）：根墙模型竖着铺在道路纵向，横向扫过。
	for arm in range(2):
		var wave := prop(game, root, WALL, Vector3(Boss.SWEEP_DEPTH/SCALE, 2.8, 2.2))
		wave.name = "Wave%d"%arm
		wave.rotation.y = PI/2
		wave.hide()
	for n in range(6):
		var pod := prop(game, root, POD, Vector3(1.8, 2.1, 1.8))
		pod.name = "Pod%d"%n
		pod.hide()
	var knot := prop(game, root, KNOT, Vector3(4.6, 1.4, 4.4))
	knot.name = "Knot"
	var knot_light := OmniLight3D.new()
	knot_light.name = "KnotLight"
	knot_light.light_color = AMBER
	knot_light.omni_range = 7.0
	knot_light.position = Vector3(0, 1.4, 0)
	knot.add_child(knot_light)
	knot.hide()
	# 入口根墙：开战时从地下升起，击败后沉回。
	var gate := prop(game, root, WALL, Vector3(34.0, 3.4, 2.4))
	gate.name = "Gate"
	gate.position = Vector3(0, -3.6, -(event.arena+60.0-event.y)/SCALE)
	var thorns := spike_field(root, "Thorns", 2*int(ceil(Boss.HOLD/THORN_STEP)))
	thorns.hide()
	# 沉睡时地面只有一团发光根结，入场时被顶破；Boss 本体此时埋在地下。
	var mound := prop(game, root, KNOT, Vector3(13.0, 3.2, 12.0))
	mound.name = "Mound"
	var mound_light := OmniLight3D.new()
	mound_light.name = "MoundLight"
	mound_light.light_color = AMBER
	mound_light.omni_range = 14.0
	mound_light.position = Vector3(0, 2.0, 0)
	mound.add_child(mound_light)
	telegraph(root, "Crack", 1, Color(1.0, 0.62, 0.2, 0.9))
	spike_field(root, "IntroSpikes", INTRO_SPIKES)
	build_bar(root)
	build_cinema(root)

static func build_bar(root: Node3D) -> void:
	var layer := CanvasLayer.new()
	layer.name = "BossBar"
	layer.layer = 3
	layer.visible = false
	root.add_child(layer)
	var frame := Control.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_CENTER_TOP)
	frame.position = Vector2(-280, 18)
	frame.size = Vector2(560, 46)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(frame)
	var title := Label.new()
	title.name = "Title"
	title.position = Vector2(0, 0)
	title.size = Vector2(560, 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("f3e3c0"))
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.04, 0.95))
	title.add_theme_constant_override("outline_size", 5)
	frame.add_child(title)
	var back := ColorRect.new()
	back.name = "Back"
	back.position = Vector2(0, 26)
	back.size = Vector2(560, 14)
	back.color = Color(0.04, 0.05, 0.04, 0.78)
	frame.add_child(back)
	var lag := ColorRect.new()
	lag.name = "Lag"
	lag.position = Vector2(2, 28)
	lag.size = Vector2(556, 10)
	lag.color = Color("f2e6c4")
	frame.add_child(lag)
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.position = Vector2(2, 28)
	fill.size = Vector2(556, 10)
	frame.add_child(fill)
	for ratio in Boss.STAGES:
		var tick := ColorRect.new()
		tick.position = Vector2(2+556*ratio-1, 24)
		tick.size = Vector2(2, 18)
		tick.color = Color(1, 1, 1, 0.55)
		frame.add_child(tick)

# 电影黑边、Boss 名称标题与“按跳跃跳过”提示，画在游戏界面之上。
static func build_cinema(root: Node3D) -> void:
	var layer := CanvasLayer.new()
	layer.name = "Cinema"
	layer.layer = 4
	layer.visible = false
	root.add_child(layer)
	for side in ["Top", "Bottom"]:
		var bar := ColorRect.new()
		bar.name = side
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(bar)
	for spec in [["Name", 64, Color("f6e2b8")], ["Epithet", 22, Color("d9c7a0")], ["Skip", 15, Color(1, 1, 1, 0.6)]]:
		var label := Label.new()
		label.name = spec[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", spec[1])
		label.add_theme_color_override("font_color", spec[2])
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 8 if spec[0] == "Name" else 4)
		layer.add_child(label)
	layer.get_node("Name").text = Boss.NAME
	layer.get_node("Epithet").text = "被腐化的森林守护者"
	layer.get_node("Skip").text = "按跳跃键跳过"
	layer.get_node("Skip").horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

# 一次性特效按“状态 + 技能序号”只触发一次。
static func once(view: Node3D, key: String) -> bool:
	if view.get_meta("fx_once", "") == key: return false
	view.set_meta("fx_once", key)
	return true

static func once_tag(view: Node3D, tag: String, key: String) -> bool:
	var meta := "fx_" + tag
	if view.get_meta(meta, "") == key: return false
	view.set_meta(meta, key)
	return true

static func local_z(event: Dictionary, y: float) -> float:
	return -(y-event.y)/SCALE

static func sync(game, view: Node3D, event: Dictionary) -> void:
	var run = game.run
	var boss: Node3D = view.get_node("Body/Colossus")
	var age: float = run.elapsed-event.state_at
	var dead: bool = event.hp <= 0
	var death_age: float = run.elapsed-event.get("defeated_at", run.elapsed)
	boss.position = Vector3(event.origin.x/SCALE, 0, 0)
	if dead: boss.position.y = -smoothstep(2.5, 7.0, death_age)*HEIGHT*0.9
	boss.visible = not dead or death_age < 7.5
	animate(run, boss, event, age, dead, death_age)
	heart(run, boss, event, age, dead)
	flash(game, boss, event)
	telegraphs(game, view, event, age)
	spikes(game, view, event)
	waves(game, view, event)
	pods(game, view, event, age)
	knot(game, view, event, age)
	gate(view, event, dead, death_age, run)
	thorns(view, event, run)
	moments(game, view, event, age, dead)
	bar(game, view, event, dead, death_age)
	intro(game, view, event)

# 动作按模拟时间直接取样：前摇映射到动作的蓄力段，出手映射到挥击段。
static func animate(run, boss: Node3D, event: Dictionary, age: float, dead: bool, death_age: float) -> void:
	if not boss.has_meta("anim"): return
	var player: AnimationPlayer = boss.get_meta("anim")
	var pace: float = Boss.PACE[event.stage]
	var clip := "Idle"
	var t: float = fposmod(run.elapsed, IDLE_LOOP)
	if dead:
		clip = "Death"; t = minf(death_age, 3.0)
	elif event.phase == "dormant":
		clip = "Idle"; t = fposmod(run.elapsed*0.5, IDLE_LOOP)
	else:
		match event.state:
			"intro":
				# 破土时保持咆哮动作的下蹲蓄力姿势，站稳后放完整段咆哮，最后回到待机。
				if age < Boss.INTRO_ROAR:
					clip = "Roar"; t = 0.35
				elif age < Boss.INTRO_ROARED:
					clip = "Roar"; t = 0.35+(age-Boss.INTRO_ROAR)/(Boss.INTRO_ROARED-Boss.INTRO_ROAR)*1.85
				else:
					clip = "Idle"; t = fposmod(run.elapsed, IDLE_LOOP)
			"roar":
				clip = "Roar"; t = clampf(age/Boss.ROAR, 0, 1)*2.2
			"summon":
				clip = "Roar"; t = clampf(age/(Boss.SUMMON_WINDUP*pace), 0, 1)*1.1
			"spikes":
				var windup: float = Boss.SPIKE_WINDUP*pace
				clip = "Slam"; t = age/windup*0.6 if age < windup else minf(0.6+(age-windup), 2.0)
			"sweep":
				var windup: float = Boss.SWEEP_WINDUP*pace
				var arm := 1 if Boss.sweep_arms(event) == 2 and age >= windup+Boss.SWEEP_TIME else 0
				var side: float = event.sweep_side*(1.0 if arm == 0 else -1.0)
				# 模型 L 臂在画面右侧（+x）：根浪从 +x 侧出发时用 L 臂。
				clip = "SweepL" if side > 0 else "SweepR"
				var start: float = windup+arm*Boss.SWEEP_SECOND
				if arm == 0 and age < windup: t = age/windup*0.7
				else: t = minf(0.7+(age-start)/Boss.SWEEP_TIME*0.3, 2.0) if age >= start else 0.55+(age-(windup+Boss.SWEEP_TIME))/(start-windup-Boss.SWEEP_TIME)*0.15
			"seeds":
				var windup: float = Boss.SEED_WINDUP*pace
				clip = "Throw"; t = age/windup*0.7 if age < windup else minf(0.7+(age-windup)*0.5, 1.8)
			"root":
				var windup: float = Boss.ROOT_WINDUP*pace
				clip = "Root"; t = age/windup*0.8 if age < windup else 0.8+fposmod(age-windup, 1.2)
				if Boss.rip_warning(run, event): t = 2.0
			"stagger":
				clip = "Stagger"; t = age if age < 0.35 else 0.35+fposmod(age-0.35, 1.65)
			"recover":
				clip = "Idle"; t = fposmod(run.elapsed, IDLE_LOOP)
	var name: String = boss.get_meta("clip_" + clip, "")
	if name.is_empty():
		for candidate in player.get_animation_list():
			if candidate.get_slice("|", candidate.get_slice_count("|")-1) == clip: name = candidate
		boss.set_meta("clip_" + clip, name)
	if name.is_empty(): return
	var skeleton: Skeleton3D = boss.get_meta("skeleton", null)
	if player.current_animation != name:
		# 记下切换前的骨骼姿势，随后按模拟时间渐变到新动作。
		if skeleton != null and player.current_animation != "":
			var snapshot: Array = []
			for bone in range(skeleton.get_bone_count()): snapshot.append(skeleton.get_bone_pose_rotation(bone))
			boss.set_meta("blend_from", snapshot)
			boss.set_meta("blend_at", run.elapsed)
		player.play(name)
	player.seek(clampf(t, 0.0, player.current_animation_length), true)
	var blend: float = (run.elapsed-float(boss.get_meta("blend_at", -10.0)))/CROSSFADE
	if skeleton != null and blend < 1.0 and boss.has_meta("blend_from"):
		var from: Array = boss.get_meta("blend_from")
		var w := smoothstep(0.0, 1.0, maxf(blend, 0.0))
		for bone in range(mini(from.size(), skeleton.get_bone_count())):
			skeleton.set_bone_pose_rotation(bone, (from[bone] as Quaternion).slerp(skeleton.get_bone_pose_rotation(bone), w))

static func heart(run, boss: Node3D, event: Dictionary, age: float, dead: bool) -> void:
	var core: MeshInstance3D = boss.get_node("Heart")
	var light: OmniLight3D = boss.get_node("HeartLight")
	var exposed: bool = Boss.exposed(event)
	var pulse := 0.5+0.5*sin(run.elapsed*(9.0 if exposed else 2.2))
	# 模型自带树心，平时只补光；硬直时额外的发光核从胸口放大前探（身体前扑，树心下移）。
	core.visible = exposed and not dead
	core.scale = Vector3.ONE*(1.0+pulse*0.35)*smoothstep(0.0, 0.3, age)
	core.position = Vector3(0, HEIGHT*(CHEST-0.14*smoothstep(0, 0.35, age)) if exposed else HEIGHT*CHEST, CHEST_FRONT+(1.8 if exposed else 0.0))
	light.position = core.position+Vector3(0, 0, 1.4)
	light.light_energy = 0.0 if dead else ((5.0+pulse*3.0) if exposed else (1.2+pulse*0.6))
	light.light_color = Color("fff0b8") if exposed else AMBER

static func flash(game, boss: Node3D, event: Dictionary) -> void:
	var run = game.run
	var hit_age: float = run.elapsed-event.get("hit_at", -10.0)
	var on: bool = hit_age >= 0.0 and hit_age < 0.07
	if boss.get_meta("flashing", false) == on: return
	boss.set_meta("flashing", on)
	var overlay: Material = game.material("enemy_hit_flash", Color("ffe2ad"), .9) if on else null
	for mesh in boss.get_meta("meshes"): mesh.material_overlay = overlay

static func set_charge(node: MeshInstance3D, charge: float) -> void:
	(node.material_override as ShaderMaterial).set_shader_parameter("charge", clampf(charge, 0, 1))

static func telegraphs(game, view: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var marks: Node3D = view.get_node("Telegraphs")
	for child in marks.get_children(): child.hide()
	if event.hp <= 0 or event.phase != "fight": return
	var pace: float = Boss.PACE[event.stage]
	match event.state:
		"spikes":
			var windup: float = Boss.SPIKE_WINDUP*pace
			if age > windup+0.6: return
			var top: float = event.origin.y-100.0
			var length: float = top-event.arena
			for n in range(event.lanes.size()):
				var lane: MeshInstance3D = marks.get_node("Lane%d"%n)
				lane.show()
				lane.position = Vector3(event.lanes[n]/SCALE, 0.06, local_z(event, top-length*0.5))
				lane.scale = Vector3(Boss.SPIKE_HALF*2/SCALE, 1, length/SCALE)
				(lane.material_override as ShaderMaterial).set_shader_parameter("aspect", Vector2(1, length/(Boss.SPIKE_HALF*2)))
				(lane.material_override as ShaderMaterial).set_shader_parameter("flow", -1.0)
				set_charge(lane, age/windup)
		"sweep":
			var windup: float = Boss.SWEEP_WINDUP*pace
			var finish: float = windup+(Boss.sweep_arms(event)-1)*Boss.SWEEP_SECOND+Boss.SWEEP_TIME
			if age > finish: return
			var band: MeshInstance3D = marks.get_node("Band")
			var front: float = event.arena+Boss.HOLD
			band.show()
			band.position = Vector3(0, 0.05, local_z(event, front-Boss.SWEEP_DEPTH*0.5))
			band.scale = Vector3(run.EDGE*2/SCALE, 1, Boss.SWEEP_DEPTH/SCALE)
			band.rotation.y = PI/2*event.sweep_side
			band.scale = Vector3(Boss.SWEEP_DEPTH/SCALE, 1, run.EDGE*2/SCALE)
			(band.material_override as ShaderMaterial).set_shader_parameter("aspect", Vector2(1, run.EDGE*2/Boss.SWEEP_DEPTH*4))
			set_charge(band, age/windup)
		"seeds":
			var land: float = Boss.seed_land_age(event)
			if age > land: return
			for n in range(event.targets.size()):
				var circle: MeshInstance3D = marks.get_node("Circle%d"%n)
				var target: Vector2 = event.targets[n]
				circle.show()
				circle.position = Vector3(target.x/SCALE, 0.07, local_z(event, target.y))
				circle.scale = Vector3.ONE*(Boss.SEED_RADIUS*2/SCALE)
				set_charge(circle, age/land)
		"root":
			if Boss.rip_warning(run, event):
				var rip: MeshInstance3D = marks.get_node("Rip")
				var center := Vector2(0, event.arena+(Boss.TRIGGER+Boss.HOLD)*0.5)
				rip.show()
				rip.position = Vector3(0, 0.08, local_z(event, center.y))
				rip.scale = Vector3(run.EDGE*2/SCALE, 1, (Boss.HOLD-Boss.TRIGGER)/SCALE)
				var limit: float = Boss.ROOT_WINDUP*pace+Boss.ROOT_LIMIT
				set_charge(rip, 1.0-(limit-age)/1.5)

# 根刺：直线上每 SPIKE_STEP 一簇，根刺前沿经过后钻出、停留，再缩回地下。
static func spikes(game, view: Node3D, event: Dictionary) -> void:
	var run = game.run
	var field: MultiMeshInstance3D = view.get_node("Spikes")
	var multi := field.multimesh
	var count := 0
	if event.hp > 0 and event.state == "spikes":
		var base: Transform3D = field.get_meta("base")
		var front: float = Boss.spike_front(run, event, run.elapsed)
		var top: float = event.origin.y-100.0
		var linger: float = Boss.SPIKE_SPEED*Boss.SPIKE_LINGER
		var steps := int((top-event.arena)/SPIKE_STEP)
		var fx = game.get("fx")
		for lane_index in range(event.lanes.size()):
			var x: float = event.lanes[lane_index]
			for k in range(steps):
				var y: float = top-k*SPIKE_STEP
				if y < front or y > front+linger or count >= MAX_SPIKES: continue
				var since: float = (y-front)/Boss.SPIKE_SPEED
				var grow: float = smoothstep(0.0, 0.07, since)*(1.0-smoothstep(Boss.SPIKE_LINGER*0.7, Boss.SPIKE_LINGER, since))
				var wobble: float = float((k*7+lane_index*3)%5)*0.4
				var basis := Basis(Vector3.UP, wobble).scaled(Vector3(SPIKE_SIZE, SPIKE_SIZE*maxf(grow, 0.01), SPIKE_SIZE))
				var origin := Vector3(x/SCALE+float(k%3-1)*0.35, -0.2, local_z(event, y))
				multi.set_instance_transform(count, Transform3D(basis, origin)*base)
				count += 1
				# 每一簇钻出的瞬间扬土一次；只给离镜头较近的几簇，避免粒子池被占满。
				if fx != null and since < run.FIXED_STEP*1.5 and k%2 == 0 and once_tag(field, "spike%d"%lane_index, "%d:%d"%[event.skill_seq, k]):
					fx.burst("dust", world(Vector2(x, y), 0.1))
	multi.visible_instance_count = count

static func waves(game, view: Node3D, event: Dictionary) -> void:
	var run = game.run
	var fx = game.get("fx")
	for arm in range(2):
		var wave: Node3D = view.get_node("Wave%d"%arm)
		var x: float = Boss.sweep_x(run, event, run.elapsed, arm) if event.hp > 0 and event.state == "sweep" and arm < Boss.sweep_arms(event) else INF
		wave.visible = x != INF
		if x == INF: continue
		var center: float = event.arena+Boss.HOLD-Boss.SWEEP_DEPTH*0.5
		wave.position = Vector3(x/SCALE, 0, local_z(event, center))
		wave.rotation.z = -event.sweep_side*(1.0 if arm == 0 else -1.0)*0.25
		if fx != null and int(run.elapsed/run.FIXED_STEP)%6 == 0:
			for along in [-0.35, 0.0, 0.35]:
				fx.burst("dust", world(Vector2(x, center+along*Boss.SWEEP_DEPTH), 0.1))
		if once_tag(wave, "sound", "%d"%event.skill_seq): game.sfx.play_at("tree_fall", world(Vector2(x, center), 1.0), -1.0, 1.15)

static func pods(game, view: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var flying: bool = event.hp > 0 and event.state == "seeds"
	var windup: float = Boss.SEED_WINDUP*Boss.PACE[event.stage]
	var start := world(event.origin+Vector2(0, -60), HEIGHT*0.55)
	for n in range(6):
		var pod: Node3D = view.get_node("Pod%d"%n)
		var t: float = (age-windup)/Boss.SEED_FLIGHT
		pod.visible = flying and n < event.targets.size() and t >= 0.0 and t < 1.0
		if not pod.visible: continue
		var target: Vector3 = world(event.targets[n], 0.6)
		var point := start.lerp(target, t)
		point.y += sin(t*PI)*4.0
		pod.position = point-Vector3(0, 0, -event.y/SCALE)
		pod.rotation = Vector3(t*6.0, t*4.0+n, 0)
	# 落地爆炸：冲击环、孢子尘与爆炸声。
	if flying and age >= Boss.seed_land_age(event) and once_tag(view, "seeds", "%d"%event.skill_seq):
		var fx = game.get("fx")
		for target in event.targets:
			var at := world(target, 0.1)
			if fx != null:
				fx.impact(at, TOXIC, Boss.SEED_RADIUS/SCALE, 2.5)
				fx.burst("dust", at)
			game.sfx.play_at("explosion", at, -6.0, 1.1)

static func knot(game, view: Node3D, event: Dictionary, age: float) -> void:
	var run = game.run
	var node: Node3D = view.get_node("Knot")
	var active: bool = event.hp > 0 and event.state == "root"
	var windup: float = Boss.ROOT_WINDUP*Boss.PACE[event.stage]
	node.visible = active or (event.state == "stagger" and age < 0.4)
	if not node.visible: return
	var rise: float = smoothstep(0.0, windup, age) if active else 1.0-smoothstep(0.0, 0.4, age)
	node.position = Vector3(event.binding.x/SCALE, -1.4*(1.0-rise), local_z(event, event.binding.y))
	var burn: float = Boss.burn_ratio(event)
	var light: OmniLight3D = node.get_node("KnotLight")
	light.light_energy = 1.5+burn*6.0
	light.light_color = AMBER.lerp(Color("fff6dc"), burn)
	var fx = game.get("fx")
	if active and age >= windup and Boss.burning(run, event) and fx != null and int(run.elapsed/run.FIXED_STEP)%10 == 0:
		fx.burst("spark", world(event.binding, 1.2))
		game.sfx.play_at("rope", world(event.binding, 1.0), -10.0, 1.4)
	if event.state == "stagger" and once_tag(view, "burst", "%d"%event.skill_seq):
		var at := world(event.binding, 0.8)
		if fx != null: fx.impact(at, Color("fff0b8"), 4.0, 5.0)
		var coop_fx = game.get("coop_fx")
		if coop_fx != null:
			coop_fx.shard_burst(at, 0.8)
			coop_fx.shard_burst(at+Vector3(0, 0.8, 0), 0.6)
		game.sfx.play_at("shield_break", at, -2.0, 0.8)
		game.sfx.play_at("punch_heavy", world(event.origin, 6.0), 0.0, 0.7)

static func gate(view: Node3D, event: Dictionary, dead: bool, death_age: float, run) -> void:
	var wall: Node3D = view.get_node("Gate")
	var raised: float = 0.0
	if event.phase != "dormant": raised = smoothstep(0.0, 1.5, run.elapsed-event.trigger)
	if dead: raised *= 1.0-smoothstep(3.0, 6.0, death_age)
	wall.position.y = -3.6*(1.0-raised)
	wall.visible = raised > 0.01

static func thorns(view: Node3D, event: Dictionary, run) -> void:
	var field: MultiMeshInstance3D = view.get_node("Thorns")
	var on: bool = event.stage == 2 and event.hp > 0
	field.visible = on
	if not on: return
	var grow: float = smoothstep(0.0, 1.2, run.elapsed-float(event.get("stage_at", 0.0)))
	var base: Transform3D = field.get_meta("base")
	var multi := field.multimesh
	var count := 0
	var rows := int(ceil(Boss.HOLD/THORN_STEP))
	for side in [-1.0, 1.0]:
		for k in range(rows):
			if count >= multi.instance_count: break
			var y: float = event.arena+k*THORN_STEP
			var basis := Basis(Vector3.UP, float(k%5)).scaled(Vector3(2.6, 2.6*maxf(grow, 0.01), 2.6))
			multi.set_instance_transform(count, Transform3D(basis, Vector3(side*(run.EDGE-Boss.THORN_WIDTH*0.5)/SCALE, -0.2, local_z(event, y)))*base)
			count += 1
	multi.visible_instance_count = count

# 开战、怒吼、出手瞬间与倒下的冲击和声音。
static func moments(game, view: Node3D, event: Dictionary, age: float, dead: bool) -> void:
	var run = game.run
	var fx = game.get("fx")
	var hazard_fx = game.get("hazard_fx")
	var base := world(event.origin, 0.1)
	var key := "%s:%d:%d"%[event.state, event.skill_seq, event.stage]
	if dead:
		if once(view, "dead"):
			game.sfx.play_at("tree_fall", base+Vector3(0, 4, 0), 2.0, 0.6)
			if fx != null: fx.impact(base, AMBER, 9.0, 6.0)
			if hazard_fx != null: hazard_fx.slam(base, 7.0)
		return
	if event.phase == "dormant": return
	var pace: float = Boss.PACE[event.stage]
	match event.state:
		"roar":
			if once(view, key):
				game.sfx.play_at("wood_creak_heavy", base+Vector3(0, 6, 0), 2.0, 0.6)
				game.sfx.play_at("tree_fall", base+Vector3(0, 6, 0), 0.0, 0.5)
				if hazard_fx != null: hazard_fx.slam(base, 8.0)
		"spikes":
			if once(view, key): game.sfx.play_at("wood_creak_heavy", base+Vector3(0, 6, 0), -2.0, 0.8)
			if age >= Boss.SPIKE_WINDUP*pace and once_tag(view, "strike", key):
				game.sfx.play_at("rubble", base+Vector3(0, 0, 6), 0.0, 0.7)
				if hazard_fx != null: hazard_fx.slam(base+Vector3(0, 0, 5), 4.0)
		"sweep", "seeds", "summon":
			if once(view, key): game.sfx.play_at("wood_creak_heavy", base+Vector3(0, 6, 0), -2.0, 0.9)
			if event.state == "summon" and age >= Boss.SUMMON_WINDUP*pace and once_tag(view, "strike", key):
				for x in [-220.0, 220.0]:
					var at := world(Vector2(x, event.arena+Boss.HOLD+100), 0.1)
					if hazard_fx != null: hazard_fx.slam(at, 2.5)
				game.sfx.play_at("rubble", base, -2.0, 1.0)
		"root":
			if age >= Boss.ROOT_WINDUP*pace and once_tag(view, "strike", key):
				game.sfx.play_at("rubble", base+Vector3(0, 0, 5), 2.0, 0.6)
				if hazard_fx != null: hazard_fx.slam(base+Vector3(0, 0, 6), 6.0)
			if Boss.rip_warning(run, event) and once_tag(view, "warn", key): game.sfx.play("warning", -2.0, 0.8)
		"recover":
			# 超时拔出的全场冲击：前一个状态是扎根且没有灼断。
			if event.skill == "root" and not event.burned and once(view, key) and age < 0.2:
				if hazard_fx != null: hazard_fx.slam(world(Vector2(0, event.arena+900.0), 0.1), 14.0)
				game.sfx.play_at("tree_fall", base, 2.0, 0.7)

static func bar(game, view: Node3D, event: Dictionary, dead: bool, death_age: float) -> void:
	var run = game.run
	var layer: CanvasLayer = view.get_node("BossBar")
	var show: bool = event.phase not in ["dormant", "intro"] and (not dead or death_age < 3.0) and run.state in ["running", "paused"]
	layer.visible = show
	if not show: return
	var frame: Control = layer.get_node("Frame")
	var width := minf(560.0, game.get_viewport().get_visible_rect().size.x-40.0)
	# 放在章节标题下方居中，避开左上血量与右上武器面板。
	frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	frame.position = Vector2((game.get_viewport().get_visible_rect().size.x-width)*0.5, 104)
	var ratio: float = clampf(float(event.hp)/event.max_hp, 0, 1)
	var exposed: bool = Boss.exposed(event)
	var fill: ColorRect = frame.get_node("Fill")
	fill.size.x = (width-4)*ratio
	fill.color = AMBER if exposed else Color("8fae7a")
	frame.get_node("Back").size.x = width
	var lag: ColorRect = frame.get_node("Lag")
	var shown: float = move_toward(float(view.get_meta("bar_lag", ratio)), ratio, game.frame_delta*0.25)
	view.set_meta("bar_lag", shown)
	lag.size.x = (width-4)*maxf(shown, ratio)
	var title: Label = frame.get_node("Title")
	title.size.x = width
	title.text = "%s · 第 %d 阶段%s"%[Boss.NAME, event.stage+1, "  ·  树心暴露！" if exposed else ("  ·  护甲（伤害 25%）" if not dead else "")]
	if dead: title.text = "%s 已倒下"%Boss.NAME

# —— 入场动画 ——
# 时间轴见 journey_boss.gd 的 INTRO_*：0–1.2 秒镜头拉高拉远、地面开裂；1.4 秒破土，根刺环形钻出；
# 1.4–3.4 秒低机位仰拍 Boss 从地下升起；3.6–5.6 秒正面推近咆哮、冲击波与标题；5.6–7 秒镜头交还。
const INTRO_SPIKES := 14

static func intro_age(run, event: Dictionary) -> float:
	if event.phase == "dormant": return -1.0
	if event.phase == "intro": return run.elapsed-event.state_at
	return Boss.INTRO+1.0

static func shot(eye: Vector3, look: Vector3) -> Transform3D:
	return Transform3D.IDENTITY.translated(eye).looking_at(look, Vector3.UP)

static func ease01(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))

# 返回 {transform, fov}。home 为旅程镜头，game_shot 为 Boss 战镜头；运镜从前者出发、在后者落地。
static func intro_camera(game, event: Dictionary, home: Transform3D, game_shot: Transform3D) -> Dictionary:
	var run = game.run
	var t: float = run.elapsed-event.state_at
	var core: float = -event.y/SCALE
	var players: float = -minf(run.a.position.y, run.b.position.y)/SCALE
	var crane := shot(Vector3(0, 30, players+16), Vector3(0, 0, core+10))
	var rise_from := shot(Vector3(12, 1.8, core+27), Vector3(0, 7, core))
	var rise_to := shot(Vector3(8.5, 2.4, core+22), Vector3(0, 9, core))
	var roar_from := shot(Vector3(2.8, 4.5, core+26), Vector3(0, HEIGHT*0.66, core))
	var roar_to := shot(Vector3(1.6, 5.5, core+20), Vector3(0, HEIGHT*0.68, core))
	if t < Boss.INTRO_CRANE:
		var k := ease01(t/Boss.INTRO_CRANE)
		return {"transform":home.interpolate_with(crane, k), "fov":lerpf(57.0, 60.0, k)}
	if t < Boss.INTRO_RISE: return {"transform":crane, "fov":60.0}
	if t < Boss.INTRO_ROAR:
		return {"transform":rise_from.interpolate_with(rise_to, ease01((t-Boss.INTRO_RISE)/(Boss.INTRO_ROAR-Boss.INTRO_RISE))), "fov":50.0}
	if t < Boss.INTRO_ROARED:
		return {"transform":roar_from.interpolate_with(roar_to, ease01((t-Boss.INTRO_ROAR)/(Boss.INTRO_ROARED-Boss.INTRO_ROAR))), "fov":48.0}
	var k := ease01((t-Boss.INTRO_ROARED)/(Boss.INTRO-Boss.INTRO_ROARED))
	return {"transform":roar_to.interpolate_with(game_shot, k), "fov":lerpf(48.0, 62.0, k)}

static func intro(game, view: Node3D, event: Dictionary) -> void:
	var run = game.run
	var t := intro_age(run, event)
	var boss: Node3D = view.get_node("Body/Colossus")
	var mound: Node3D = view.get_node("Mound")
	var crack: MeshInstance3D = view.get_node("Crack")
	var spikes_field: MultiMeshInstance3D = view.get_node("IntroSpikes")
	var layer: CanvasLayer = view.get_node("Cinema")
	var base := world(event.origin, 0.1)
	var fx = game.get("fx")
	var hazard_fx = game.get("hazard_fx")
	var key := "%.3f"%event.trigger
	var skipped: bool = event.get("intro_skipped", false)
	# 沉睡：只露出发光根结，微微起伏；开战后越抖越亮，破土时消失。
	mound.visible = event.hp > 0 and t < Boss.INTRO_RISE
	if mound.visible:
		var pulse := 0.5+0.5*sin(run.elapsed*1.6)
		var build := ease01(t/Boss.INTRO_RISE) if t >= 0.0 else 0.0
		mound.scale = Vector3.ONE*(1.0+0.03*pulse+0.12*build)
		mound.position = Vector3(event.origin.x/SCALE+sin(run.elapsed*40.0)*0.08*build, 0, 0)
		(mound.get_node("MoundLight") as OmniLight3D).light_energy = 1.2+pulse*0.8+4.0*build
	if event.phase == "dormant":
		boss.visible = false
		# 失败重打会恢复到开战前，开战时刻可能完全相同：沉睡时清掉入场一次性标记，下次开战重新播放。
		for tag in ["intro_rumble", "intro_burst", "intro_roar", "intro_wave0.15", "intro_wave0.55", "intro_wave0.95"]:
			view.remove_meta("fx_" + tag)
	elif event.phase == "intro":
		# 破土前埋在地下；1.4–3.4 秒升起，升起途中轻微抖动。
		var rise := ease01((t-Boss.INTRO_RISE)/(Boss.INTRO_RISEN-Boss.INTRO_RISE))
		boss.visible = t >= Boss.INTRO_RISE
		boss.position.y = -HEIGHT*1.02*(1.0-rise)
		if rise < 1.0: boss.position.x += sin(run.elapsed*31.0)*0.18*(1.0-rise)
	# 埋在地下时不让胸口补光从地面下透出来。
	if not boss.visible: (boss.get_node("HeartLight") as OmniLight3D).light_energy = 0.0
	# 地面裂纹：开战到破土之间由小变大，之后淡出。
	crack.visible = t >= 0.0 and t < Boss.INTRO_RISEN
	if crack.visible:
		crack.position = Vector3(event.origin.x/SCALE, 0.08, 0)
		crack.scale = Vector3.ONE*lerpf(6.0, 20.0, ease01(t/Boss.INTRO_RISE))
		set_charge(crack, 1.0-ease01((t-Boss.INTRO_RISE)/1.2))
	# 根刺环：破土瞬间一圈钻出，Boss 站稳后缩回。
	var multi := spikes_field.multimesh
	multi.visible_instance_count = 0
	if t >= Boss.INTRO_RISE and t < Boss.INTRO_ROAR+0.4:
		var base_transform: Transform3D = spikes_field.get_meta("base")
		var grow := ease01((t-Boss.INTRO_RISE)/0.18)*(1.0-ease01((t-Boss.INTRO_RISEN)/0.6))
		for n in range(INTRO_SPIKES):
			var angle := TAU*n/INTRO_SPIKES+0.3
			var radius := 8.5+float(n%3)*1.4
			var outward := Vector3(cos(angle), 0, -sin(angle))
			var basis := Basis(Vector3.UP, angle).rotated(outward.cross(Vector3.UP).normalized(), -0.35).scaled(Vector3(4.2, 4.2*maxf(grow, 0.01), 4.2))
			multi.set_instance_transform(n, Transform3D(basis, Vector3(event.origin.x/SCALE, -0.3, 0)+outward*radius)*base_transform)
		multi.visible_instance_count = INTRO_SPIKES
	if t < 0.0 or t > Boss.INTRO+0.5:
		layer.visible = false
		return
	# 声音与冲击：每次开战（以开战时刻区分）各触发一次；跳过时不补放已跳过的段落。
	if t < Boss.INTRO_RISE and once_tag(view, "intro_rumble", key):
		game.sfx.play_at("boss_rumble", base+Vector3(0, 1, 0), 2.0, 1.0)
	if t >= 0.0 and t < Boss.INTRO_RISEN and fx != null and int(run.elapsed/run.FIXED_STEP)%14 == 0:
		var spin: float = run.elapsed*7.3
		fx.burst("dust", base+Vector3(cos(spin)*6.0, 0, sin(spin)*6.0))
	if t >= Boss.INTRO_RISE and once_tag(view, "intro_burst", key) and not skipped:
		game.sfx.play_at("boss_burst", base+Vector3(0, 1, 0), 3.0, 0.85)
		game.sfx.play_at("tree_fall", base+Vector3(0, 3, 0), 0.0, 0.6)
		if hazard_fx != null:
			hazard_fx.slam(base, 10.0)
			for n in range(6): hazard_fx.burst_debris(base+Vector3(cos(n)*5.0, 0.5, sin(n)*5.0), Color("5e4126"), 1.6)
		if fx != null: fx.impact(base, AMBER, 12.0, 6.0)
	if t >= Boss.INTRO_ROAR and once_tag(view, "intro_roar", key) and not skipped:
		game.sfx.play_at("boss_roar", base+Vector3(0, HEIGHT*0.7, 2), 6.0, 1.0)
		game.sfx.play("boss_roar", -10.0, 1.0)
	for wave in [0.15, 0.55, 0.95]:
		if t >= Boss.INTRO_ROAR+wave and once_tag(view, "intro_wave%.2f"%wave, key) and not skipped:
			if fx != null: fx.impact(base, AMBER.lerp(Color.WHITE, 0.3), 14.0+wave*10.0, 4.0)
			if hazard_fx != null and wave < 0.3: hazard_fx.slam(base, 12.0)
	# 黑边、标题与跳过提示。
	layer.visible = event.phase == "intro" and run.state in ["running", "paused"]
	if not layer.visible: return
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var bars := ease01(t/0.6)*(1.0-ease01((t-(Boss.INTRO-0.7))/0.7))
	var bar_height := size.y*0.12*bars
	var top: ColorRect = layer.get_node("Top")
	var bottom: ColorRect = layer.get_node("Bottom")
	top.position = Vector2.ZERO
	top.size = Vector2(size.x, bar_height)
	bottom.position = Vector2(0, size.y-bar_height)
	bottom.size = Vector2(size.x, bar_height)
	var title := ease01((t-(Boss.INTRO_ROAR+0.4))/0.5)*(1.0-ease01((t-(Boss.INTRO_ROARED+0.2))/0.6))
	var name_label: Label = layer.get_node("Name")
	var epithet: Label = layer.get_node("Epithet")
	name_label.position = Vector2(0, size.y*0.7)
	name_label.size = Vector2(size.x, 80)
	epithet.position = Vector2(0, size.y*0.7+74)
	epithet.size = Vector2(size.x, 30)
	name_label.modulate.a = title
	epithet.modulate.a = title*0.9
	# 标题由略大缩回原尺寸，配合咆哮的冲击感。
	name_label.pivot_offset = Vector2(size.x*0.5, 40)
	name_label.scale = Vector2.ONE*(1.12-0.12*title)
	var skip: Label = layer.get_node("Skip")
	skip.position = Vector2(0, size.y-bar_height*0.5-12)
	skip.size = Vector2(size.x-24, 24)
	skip.modulate.a = 0.0 if t < Boss.INTRO_SKIP_AFTER or t > Boss.INTRO-Boss.RETURN_TIME else bars
