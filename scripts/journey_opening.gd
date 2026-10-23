extends RefCounted
# 开场运镜、Boss 巢穴浓烟与地面震动（纯画面，不改模拟）。时间轴取自 journey_run 的 opening_age()，联机两端一致。
# 运镜按剪辑分镜：螺旋绕着巢穴浓烟升起（镜头随地面震动猛烈左右颠）→ 依次给沿途三处机关/敌人一个低机位特写
# → 离两人约 10% 路程处的特写不切镜，一条连续曲线：贴近目标慢慢后拉升起，逐渐加速面朝 Boss 方向倒着飞回两人身边
# （高度正弦起伏、左右来回摆），落在正常旅程镜头上，章节名此时才浮现。
# 镜头之间用短暂的淡出淡入切换。
# 坐标：道路单位（20 = 1 米），世界 z = -道路 y / 20。

const SCALE := 20.0
const LAIR := 3.2
const CLOSE := 2.4
const TITLE_HOLD := 2.6
const CUT := 0.22
const THUMP := 0.5
const HIGHLIGHTS := [0.8, 0.6, 0.4, 0.1]
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

# 地面震动：沉睡时巢穴下每 THUMP 秒闷响一下——巢穴扬尘圈、整片场地四处扬尘、土丘一鼓、附近镜头跟着震，让人知道下面有东西。
# 按模拟时间取拍，联机两端节奏一致。
static func thump_age(run) -> float:
	return fposmod(run.elapsed, THUMP)

static func lair_dormant(run) -> Dictionary:
	var event: Dictionary = run.Boss.boss(run)
	if event.is_empty() or event.hp <= 0 or event.phase != "dormant": return {}
	return event

# 每一拍触发一次：巢穴扬尘圈，加上巢穴周围约 25 米内八处碎土与扬尘（位置按拍数变化）。只在 Boss 场地处于显示范围内时触发。
static func sync_thump(game) -> void:
	var run = game.run
	var event := lair_dormant(run)
	if event.is_empty() or run.state != "running" or not game.model_visible(event.y): return
	var beat := int(floor(run.elapsed/THUMP))
	if game.get_meta("lair_thump", -1) == beat: return
	game.set_meta("lair_thump", beat)
	# 开场近景用非空间声音，避免听者仍在远处角色位置而听不到震动。
	if run.opening_age() >= 0.0 and run.opening_age() < LAIR:
		game.sfx.play("punch_heavy", -5.0, 0.5)
		if beat % 4 == 0: game.sfx.play("boss_rumble", -9.0, 1.0)
	else:
		game.sfx.play_at("punch_heavy", world(event.origin, 0.1), -5.0, 0.5)
	var hazard_fx = game.get("hazard_fx")
	if hazard_fx != null: hazard_fx.slam(world(event.origin, 0.1), 7.0)
	var fx = game.get("fx")
	if fx == null: return
	fx.impact(world(event.origin, 0.05), Color("d8c2a0"), 18.0, 0.0, false)
	for n in range(8):
		var seed := float(beat*8+n)
		var spot := world(Vector2(sin(seed*12.9898)*260.0, event.origin.y+sin(seed*78.233)*500.0), 0.05)
		# 每处一小撮碎土加两团扬尘，远看也能分辨出地面在抖。
		if hazard_fx != null: hazard_fx.burst_debris(spot+Vector3(0, 0.2, 0), Color("6f6254"), 1.6)
		fx.burst("dust", spot)
		fx.burst("dust", spot+Vector3(0.9, 0, -0.6))

# 镜头跟着地面震：离巢穴 30 米内最强，150 米外为零；每拍猛地一震后衰减，带一点滚转。
# violent：开场巢穴镜头用，以左右为主的狂颠，衰减更慢，两拍之间也一直在抖。
static func shake(game, xform: Transform3D, violent := false) -> Transform3D:
	var run = game.run
	var event := lair_dormant(run)
	if event.is_empty() or run.state != "running": return xform
	var gap: float = absf(-xform.origin.z*SCALE-event.y)
	var near := 1.0-clampf((gap-600.0)/2400.0, 0.0, 1.0)
	var amount := (1.1*exp(-thump_age(run)*4.0) if violent else 0.38*exp(-thump_age(run)*7.0))*near
	if amount < 0.002: return xform
	var e: float = run.elapsed
	var sideways := 1.6 if violent else 1.0
	xform.origin += xform.basis*Vector3((sin(e*47.0)+sin(e*29.0)*0.6)*sideways, sin(e*61.0+1.3)*0.5+sin(e*23.0)*0.3, 0.0)*amount
	xform.basis = xform.basis*Basis(Vector3.FORWARD, sin(e*37.0)*amount*(0.07 if violent else 0.03))
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

# 螺旋绕烟：从 Boss 背后出发绕大半圈，半径逐渐收紧、高度按正弦起伏着升高，镜头盯住随高度上移的烟柱。
static func spiral(run, u: float) -> Array:
	var e := lerpf(u, ease01(u), 0.5)
	var center := smoke_center(run)
	var angle := -PI+TAU*0.8*e
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
		# 怪物与机关交替出镜：第 1、3 个镜头优先怪物，第 2 个优先机关/合作门；最后一个是倒飞起点，挑怪物更好认。
		var want_npc := n%2 == 0 or n == HIGHLIGHTS.size()-1
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

# 镜头表：[开始, 结束, 类型, 目标（世界坐标）, 摆向, 取景倍数, 运镜方式]。
# 巢穴 → 前几处特写 → 从最后一处（离两人约 10%）倒飞回两人身边；镜头之间淡出淡入切换。
static func shots(game) -> Array:
	var run = game.run
	var result: Array = [[0.0, LAIR, "lair", smoke_center(run), 1.0]]
	var picks := highlights(game)
	var start: float = minf(run.a.position.y, run.b.position.y)
	var event: Dictionary = run.Boss.boss(run)
	var end: float = event.arena if not event.is_empty() else run.finish_distance()
	# 倒飞起点：最后一个特写目标；没挑到时用 10% 处的路中央。
	var origin: Array = picks.pop_back() if picks.size() == HIGHLIGHTS.size() else [Vector2(0, start+(end-start)*HIGHLIGHTS[-1]), 1.0]
	var time := LAIR
	var side := 1.0
	for n in range(picks.size()):
		result.append([time, time+CLOSE, "close", world(picks[n][0], 1.0), side, picks[n][1], n])
		time += CLOSE
		side = -side
	result.append([time, run.OPENING, "flyback", world(origin[0], 1.0), side, origin[1], picks.size()])
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
	return flyback(home, shot, u)

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

# 收尾：一条连续曲线，不分段、不停顿。开头贴近目标、看着它慢慢后拉并升起（就是这里的特写），
# 速度逐渐加大，面朝 Boss 方向倒着飞回两人身边，最后减速落在正常镜头上。
# 前后位置：五次缓动加一项 0.15·u·(1−u)²——起步就有一点后拉的速度，不是从静止猛地起飞；落地速度为零。
# 途中高度：整体抬高约 5.5 米加 ±3 米正弦（一开始向上，正好接上特写的升起），左右来回摆 ±9 米一个半来回；
# 包络在开头 30%、结尾 18% 内平滑收放，两端偏移与速度都归零。镜头随左右摆动略微转向，走出弧线感；
# 视线先盯住目标，再逐渐转到正常镜头的朝向，最后与正常镜头完全重合。
static func flyback(home: Transform3D, shot: Array, u: float) -> Dictionary:
	if u >= 1.0: return {"transform": home, "fov": 57.0}
	var target: Vector3 = shot[3]
	var side: float = shot[4]
	var scale: float = shot[5]
	var from := target+Vector3(side*1.5, 2.2*scale, 7.5*scale)
	var e := u*u*u*(u*(u*6.0-15.0)+10.0)+0.15*u*(1.0-u)*(1.0-u)
	var eye := from.lerp(home.origin, e)
	var envelope := smoothstep(0.0, 0.3, u)*(1.0-smoothstep(0.82, 1.0, u))
	var sway := side*9.0*sin(u*TAU*1.5)*envelope
	eye.y += (5.5+3.0*sin(u*TAU*2.0))*envelope
	eye.x = clampf(eye.x+sway, -ROAD_HALF, ROAD_HALF)
	var at_target := (target+Vector3(0, 1.2*scale, 0)-eye).normalized()
	var look := at_target.slerp(-home.basis.z, ease01((u-0.12)/0.5)).rotated(Vector3.UP, sway/45.0)
	return {"transform": Transform3D.IDENTITY.translated(eye).looking_at(eye+look*40.0, Vector3.UP), "fov": lerpf(CLOSE_FOV, 57.0, ease01(u))}

# 开场期间需要载入场景的道路位置：当前镜头的目标与机位（必须就绪），以及下一个镜头的目标、倒飞时 1.2 秒后的机位（提前排队）。
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
	# 倒飞途中再提前排队 1.2 秒后机位一带。
	if shot[2] == "flyback": result.append(-pose(game, home, list, minf(t+1.2, run.OPENING-0.01)).transform.origin.z*SCALE)
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
	for spec in [["Title", 58, Color("f6e2b8")], ["Skip", 15, Color(1, 1, 1, 0.6)]]:
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
	# 开场结束后再留 TITLE_HOLD 秒显示章节名（其余元素此时都已收起）。
	layer.visible = run.opening_age() >= 0.0 and run.opening_age() < run.OPENING+TITLE_HOLD and run.state in ["running", "paused"]
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
	# 章节名在镜头落回两人身后时才浮现，开始操作后再停留一会儿淡出；放在画面中上方，不挡人物和 HUD。
	var title: Label = layer.get_node("Title")
	title.text = run.CHAPTERS[run.level_index].name
	title.position = Vector2(0, size.y*0.28)
	title.size = Vector2(size.x, 80)
	title.modulate.a = ease01((t-(run.OPENING-0.4))/0.6)*(1.0-ease01((t-(run.OPENING+TITLE_HOLD-0.7))/0.7))
	var skip: Label = layer.get_node("Skip")
	skip.position = Vector2(0, size.y-bar_height*0.5-12)
	skip.size = Vector2(size.x-24, 24)
	skip.modulate.a = 0.0 if t < run.OPENING_SKIP_AFTER or t > run.OPENING-run.OPENING_RETURN else bars
