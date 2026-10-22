extends RefCounted
# 开场运镜、Boss 巢穴浓烟与地面震动（纯画面，不改模拟）。时间轴取自 journey_run 的 opening_age()，联机两端一致。
# 运镜按剪辑分镜：螺旋绕着巢穴浓烟升起一圈 → 依次给沿途几处机关/敌人一个低机位特写（每个镜头慢慢绕、推近、正弦起伏）
# → 两人面前停留后绕到身后，落在正常旅程镜头上。镜头之间用短暂的淡出淡入切换。
# 坐标：道路单位（20 = 1 米），世界 z = -道路 y / 20。

const SCALE := 20.0
const LAIR := 4.2
const HEROES := 3.0
const CUT := 0.22
const THUMP := 0.5
const HIGHLIGHTS := [0.8, 0.6, 0.4, 0.2]
const SHOWCASE := ["sweeper", "hammer", "press", "piston", "shuttle", "pillar", "active_spikes", "jump_bar", "lift", "rail", "steam"]
const FOV := 58.0
const CLOSE_FOV := 50.0
const ROAD_HALF := 12.0
const SMOKE_COLOR := Color(0.16, 0.14, 0.13)

# 巢穴浓烟：沉睡时从 Boss 的土丘里源源不断冒出的一根暗色烟柱，远处就能看到“这里有东西”。
static func build_smoke() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "LairSmoke"
	particles.amount = 240
	particles.lifetime = 8.0
	particles.preprocess = 8.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 80, 80))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 2.6
	process.direction = Vector3(0, 1, 0)
	process.spread = 9.0
	process.initial_velocity_min = 5.0
	process.initial_velocity_max = 7.0
	process.damping_min = 0.3
	process.damping_max = 0.6
	# 高处被风吹得略微斜向一侧。
	process.gravity = Vector3(0.35, 0.25, 0)
	process.angular_velocity_min = -20.0
	process.angular_velocity_max = 20.0
	process.scale_min = 0.8
	process.scale_max = 1.3
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.6))
	grow.add_point(Vector2(1, 3.6))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(SMOKE_COLOR, 0.0))
	fade.add_point(0.1, Color(SMOKE_COLOR, 0.92))
	fade.add_point(0.6, Color(SMOKE_COLOR.lightened(0.2), 0.7))
	fade.set_color(fade.get_point_count()-1, Color(SMOKE_COLOR.lightened(0.4), 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE*7.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = preload("res://scripts/journey_fx.gd").dot_texture()
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	particles.draw_pass_1 = quad
	return particles

# 烟柱跟着 Boss 土丘；沉睡时持续冒烟，开战破土后停止喷出、余烟自然散去。
static func sync_smoke(smoke: GPUParticles3D, run) -> void:
	var event: Dictionary = run.Boss.boss(run)
	if event.is_empty() or event.hp <= 0:
		smoke.visible = false
		smoke.emitting = false
		return
	smoke.visible = true
	var place := Vector3(event.origin.x/SCALE, 0.5, -event.origin.y/SCALE)
	# 世界坐标粒子：换位置（换章、重开）后重新预热，烟柱一出现就是完整的一根，而不是从旧位置拖过来。
	if smoke.position.distance_to(place) > 1.0:
		smoke.position = place
		smoke.restart()
	var emitting: bool = event.phase == "dormant"
	if smoke.emitting != emitting: smoke.emitting = emitting

# 地面震动：沉睡时巢穴下每 THUMP 秒闷响一下（扬尘圈、土丘一鼓、附近镜头轻震），让人知道下面有东西。
# 按模拟时间取拍，联机两端节奏一致。
static func thump_age(run) -> float:
	return fposmod(run.elapsed, THUMP)

static func lair_dormant(run) -> Dictionary:
	var event: Dictionary = run.Boss.boss(run)
	if event.is_empty() or event.hp <= 0 or event.phase != "dormant": return {}
	return event

# 每一拍触发一次扬尘圈；只在 Boss 场地处于显示范围内时触发。
static func sync_thump(game) -> void:
	var run = game.run
	var event := lair_dormant(run)
	if event.is_empty() or run.state != "running" or not game.model_visible(event.y): return
	var beat := int(floor(run.elapsed/THUMP))
	if game.get_meta("lair_thump", -1) == beat: return
	game.set_meta("lair_thump", beat)
	var hazard_fx = game.get("hazard_fx")
	if hazard_fx != null: hazard_fx.slam(world(event.origin, 0.1), 7.0)

# 镜头轻震：离巢穴 20 米内最强，100 米外为零；每拍一下后迅速衰减。
static func shake(game, xform: Transform3D) -> Transform3D:
	var run = game.run
	var event := lair_dormant(run)
	if event.is_empty() or run.state != "running": return xform
	var gap: float = absf(-xform.origin.z*SCALE-event.y)
	var near := 1.0-clampf((gap-400.0)/1600.0, 0.0, 1.0)
	var amount := 0.14*near*exp(-thump_age(run)*9.0)
	if amount < 0.002: return xform
	var e: float = run.elapsed
	xform.origin += xform.basis*Vector3(sin(e*53.0), sin(e*61.0+1.3), 0.0)*amount
	return xform

static func world(point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x/SCALE, height, -point.y/SCALE)

static func ease01(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))

static func smoke_center(run) -> Vector3:
	var event: Dictionary = run.Boss.boss(run)
	return world(event.origin) if not event.is_empty() else world(Vector2(0, run.finish_distance()-400.0))

static func heroes_center(run) -> Vector3:
	return world((run.a.position+run.b.position)*0.5)

# 螺旋绕烟：从 Boss 背后出发绕一整圈，半径逐渐收紧、高度按正弦起伏着升高，镜头盯住随高度上移的烟柱。
static func spiral(run, u: float) -> Array:
	var e := lerpf(u, ease01(u), 0.5)
	var center := smoke_center(run)
	var angle := -PI+TAU*e
	var radius := lerpf(36.0, 24.0, e)+2.5*sin(e*PI*3.0)
	var height := lerpf(5.0, 19.0, e)+3.0*sin(e*TAU*1.5)
	var eye := center+Vector3(sin(angle)*radius, height, cos(angle)*radius)
	var look := center+Vector3(0, lerpf(7.0, 16.0, e), 0)
	return [eye, look]

# 特写目标：在 Boss 场地与两人之间按比例取几处，每处在附近挑最有看点的怪物、合作门或机关。
# 顺序从 Boss 一侧往两人一侧，剪辑上像一路往回走。
static func highlights(game) -> Array:
	var run = game.run
	var start: float = minf(run.a.position.y, run.b.position.y)
	var event: Dictionary = run.Boss.boss(run)
	var end: float = event.arena if not event.is_empty() else run.finish_distance()
	var span := end-start
	# [位置, 基础分, 是否 NPC, 取景倍数]；合作门体量大，取景拉远拉高；机关只挑一眼能看懂的会动的那些。
	var candidates: Array = []
	for item in run.journey_events:
		if item.kind == "boss": continue
		candidates.append([item.rect.get_center(), 2.0, item.kind == "monster", 1.0])
	for gate in run.charge_gates:
		candidates.append([Vector2(0, gate.receiver.y), 2.0, false, 1.9])
	for index in range(run.kinds.size()):
		if run.kinds[index] in SHOWCASE:
			candidates.append([run.obstacles[index].get_center(), 2.5, false, 1.3])
	var result: Array = []
	for n in range(HIGHLIGHTS.size()):
		var target: float = start+span*HIGHLIGHTS[n]
		# 怪物与机关交替出镜：第 1、3 个镜头优先怪物，第 2、4 个优先机关/合作门。
		var want_npc := n%2 == 0
		var best: Array = []
		var best_score := -INF
		for candidate in candidates:
			var point: Vector2 = candidate[0]
			if point.y < start+600.0 or point.y > end-200.0 or absf(point.y-target) > span*0.12: continue
			var score: float = candidate[1]+(2.0 if candidate[2] == want_npc else 0.0)-absf(point.y-target)/(span*0.12)
			if score > best_score:
				best_score = score
				best = candidate
		if not best.is_empty(): result.append([Vector2(clampf(best[0].x, -260.0, 260.0), best[0].y), best[3]])
	return result

# 镜头表：[开始, 结束, 类型, 目标（世界坐标）, 摆向, 取景倍数, 运镜方式]。巢穴 → 各处特写 → 两人；镜头之间淡出淡入切换。
static func shots(game) -> Array:
	var run = game.run
	var result: Array = [[0.0, LAIR, "lair", smoke_center(run), 1.0]]
	var picks := highlights(game)
	var close: float = (run.OPENING-LAIR-HEROES)/maxf(picks.size(), 1)
	var time := LAIR
	var side := 1.0
	for n in range(picks.size()):
		result.append([time, time+close, "close", world(picks[n][0], 1.0), side, picks[n][1], n])
		time += close
		side = -side
	result.append([time, run.OPENING, "heroes", heroes_center(run), side])
	return result

# 开场镜头：返回 {transform, fov}。home 是正常旅程镜头，最后正好落在它上面。
static func camera(game, home: Transform3D, list: Array) -> Dictionary:
	var run = game.run
	var t: float = run.opening_age()
	if run.opening_skipped_age >= 0.0:
		# 跳过：从跳过那一刻的画面收回正常镜头。
		var from := pose(game, home, list, run.opening_skipped_age)
		var k := ease01((t-(run.OPENING-run.OPENING_RETURN))/run.OPENING_RETURN)
		return {"transform": from.transform.interpolate_with(home, k), "fov": lerpf(from.fov, 57.0, k)}
	return pose(game, home, list, t)

static func current(list: Array, t: float) -> int:
	for i in range(list.size()):
		if t < list[i][1]: return i
	return list.size()-1

static func pose(game, home: Transform3D, list: Array, t: float) -> Dictionary:
	var run = game.run
	var shot: Array = list[current(list, t)]
	var u := clampf((t-shot[0])/maxf(shot[1]-shot[0], 0.001), 0.0, 1.0)
	match shot[2]:
		"lair":
			var lair := spiral(run, u)
			return {"transform": Transform3D.IDENTITY.translated(lair[0]).looking_at(lair[1], Vector3.UP), "fov": FOV}
		"close":
			return close_up(shot, u)
	return heroes(run, home, shot, u)

# 特写：机位在目标的两人一侧，背景是通往 Boss 的路。每个镜头里上下、左右各只朝一个方向走，同时一直推近：
# 上下：第 1、3 个镜头从高处降下，第 2、4 个从低处升起；左右：按摆向从一侧单向绕向正后方，相邻镜头方向相反。
# 缓动只取三成，整个镜头里一直在动，不会停住。
static func close_up(shot: Array, u: float) -> Dictionary:
	var e := lerpf(u, ease01(u), 0.3)
	var target: Vector3 = shot[3]
	var side: float = shot[4]
	var scale: float = shot[5]
	var descend: bool = shot[6]%2 == 0
	var angle := side*lerpf(0.8, 0.1, e)
	var radius := lerpf(17.0, 8.5, e)
	var height := lerpf(8.5, 2.2, e) if descend else lerpf(1.8, 5.0, e)
	var eye := target+Vector3(sin(angle)*radius*scale, height*scale, cos(angle)*radius*scale)
	# 机位不出路面（路两侧多是树林和房屋，侧得太远会钻进树冠或墙里）。
	eye.x = clampf(eye.x, -ROAD_HALF, ROAD_HALF)
	var look := target+Vector3(0, 1.3*scale, 0)
	return {"transform": Transform3D.IDENTITY.translated(eye).looking_at(look, Vector3.UP), "fov": CLOSE_FOV}

# 收尾：先在两人面前稍作停留并推近，再沿弧线从侧面绕到身后，视线始终盯住两人，最后与正常镜头重合。
static func heroes(run, home: Transform3D, shot: Array, u: float) -> Dictionary:
	var center := heroes_center(run)
	var side: float = shot[4]
	var push := ease01(u/0.3)
	var front := center+Vector3(side*lerpf(4.0, 2.5, push), lerpf(3.4, 3.0, push), lerpf(-12.0, -9.5, push))
	var k := ease01((u-0.3)/0.7)
	var from := front-center
	var to := home.origin-center
	# 从正面经侧面绕到背后，不从头顶翻过：正面机位已按摆向偏到一侧，取较短的那一边绕正好经过这一侧。
	var from_angle := atan2(from.x, from.z)
	var turn := wrapf(atan2(to.x, to.z)-from_angle, -PI, PI)
	var angle := from_angle+turn*k
	var radius := lerpf(Vector2(from.x, from.z).length(), Vector2(to.x, to.z).length(), k)
	var height := lerpf(from.y, to.y, k)+3.0*sin(k*PI)
	var eye := center+Vector3(sin(angle)*radius, height, cos(angle)*radius)
	var home_look := home.origin-home.basis.z*40.0
	var look := (center+Vector3(0, 1.4, 0)).lerp(home_look, ease01((k-0.35)/0.65))
	if u >= 1.0: return {"transform": home, "fov": 57.0}
	return {"transform": Transform3D.IDENTITY.translated(eye).looking_at(look, Vector3.UP), "fov": lerpf(CLOSE_FOV, 57.0, k)}

# 开场期间需要载入场景的道路位置：当前镜头的目标与机位（必须就绪），以及下一个镜头的目标（提前排队）。
# 切到下一个镜头时若场景还没就绪，模拟停在黑场上等待，不会露出空白地面。
static func foci(game, home: Transform3D, list: Array) -> Array:
	var run = game.run
	var t: float = maxf(run.opening_age(), 0.0)
	if run.opening_skipped_age >= 0.0 or t >= run.OPENING: return []
	var i := current(list, t)
	var shot: Array = list[i]
	var xform: Transform3D = pose(game, home, list, t).transform
	var result: Array = [-shot[3].z*SCALE, -xform.origin.z*SCALE]
	if i+1 < list.size(): result.append(-list[i+1][3].z*SCALE)
	return result

# 黑边、淡入与跳过提示。
static func build_cinema(parent: Node) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "OpeningCinema"
	layer.layer = 4
	layer.visible = false
	parent.add_child(layer)
	for name in ["Top", "Bottom", "Fade"]:
		var bar := ColorRect.new()
		bar.name = name
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(bar)
	for spec in [["Title", 40, Color("f6e2b8")], ["Skip", 15, Color(1, 1, 1, 0.6)]]:
		var label := Label.new()
		label.name = spec[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", spec[1])
		label.add_theme_color_override("font_color", spec[2])
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 6 if spec[0] == "Title" else 4)
		layer.add_child(label)
	layer.get_node("Skip").text = "按跳跃键跳过"
	layer.get_node("Skip").horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return layer

static func sync_cinema(layer: CanvasLayer, game) -> void:
	var run = game.run
	layer.visible = run.opening_active() and run.state in ["running", "paused"]
	if not layer.visible: return
	var t: float = run.opening_age()
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var bars := 1.0-ease01((t-(run.OPENING-0.8))/0.8)
	var bar_height := size.y*0.11*bars
	var top: ColorRect = layer.get_node("Top")
	var bottom: ColorRect = layer.get_node("Bottom")
	top.size = Vector2(size.x, bar_height)
	bottom.position = Vector2(0, size.y-bar_height)
	bottom.size = Vector2(size.x, bar_height)
	# 开头从黑场淡入；镜头之间淡出淡入切换（跳过后不再切）。
	var fade: ColorRect = layer.get_node("Fade")
	fade.size = size
	var dark := 1.0-ease01(t/0.5)
	if run.opening_skipped_age < 0.0:
		var list: Array = game.opening_keys(game.opening_home())
		for i in range(1, list.size()):
			dark = maxf(dark, 1.0-ease01(absf(t-list[i][0])/CUT))
	fade.color.a = dark
	# 章节名在绕烟镜头的后半段浮现。
	var title: Label = layer.get_node("Title")
	title.text = run.CHAPTERS[run.level_index].name
	title.position = Vector2(0, size.y*0.72)
	title.size = Vector2(size.x, 60)
	title.modulate.a = ease01((t-1.6)/0.6)*(1.0-ease01((t-LAIR+0.2)/0.6)) if run.opening_skipped_age < 0.0 else 0.0
	var skip: Label = layer.get_node("Skip")
	skip.position = Vector2(0, size.y-bar_height*0.5-12)
	skip.size = Vector2(size.x-24, 24)
	skip.modulate.a = 0.0 if t < run.OPENING_SKIP_AFTER or t > run.OPENING-run.OPENING_RETURN else bars
