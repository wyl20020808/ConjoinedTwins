extends RefCounted
# 第一章死亡演出只读取模拟时钟；碎片固定数量、确定性轨迹，暂停与重试不残留计时器。
const FRACTURED := "res://assets/boss/rigged/root_colossus_fractured.glb"
const SPLIT := 2.2
const BURST := 4.0
const TITLE := 7.5
const LENGTH := 10.5

static func active(run) -> bool:
	var event: Dictionary = run.Boss.boss(run)
	return not event.is_empty() and event.get("species", "") == "" and event.hp <= 0 and event.has("defeated_at") and run.elapsed-event.defeated_at < LENGTH

static func camera(event: Dictionary, elapsed: float, home: Transform3D) -> Dictionary:
	var t: float = elapsed-event.defeated_at
	var core := Vector3(event.origin.x/20.0, 9.0, -event.y/20.0)
	var close := Transform3D.IDENTITY.translated(core+Vector3(0, 1, 24)).looking_at(core)
	var wide := Transform3D.IDENTITY.translated(core+Vector3(0, 7, 42)).looking_at(core)
	var pose := home.interpolate_with(close, smoothstep(0.0, 1.3, t))
	if t >= BURST: pose = close.interpolate_with(wide, smoothstep(BURST, 5.8, t))
	if t >= LENGTH-1.4: pose = wide.interpolate_with(home, smoothstep(LENGTH-1.4, LENGTH, t))
	return {"transform": pose, "fov": 62.0-10.0*smoothstep(0.0, 1.3, t)*(1.0-smoothstep(BURST, 5.8, t))}

static func build(view: Node3D) -> void:
	var pieces: Node3D = load(FRACTURED).instantiate()
	pieces.name = "DeathFragments"
	pieces.scale = Vector3.ONE*16.5
	pieces.rotation.y = -PI/2
	pieces.hide()
	view.add_child(pieces)
	var shards: Array = pieces.find_children("*", "MeshInstance3D", true, false)
	var cracks := ShaderMaterial.new()
	cracks.shader = preload("res://scripts/boss_fracture_cracks.gdshader")
	var points := PackedVector3Array()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/boss/rigged/root_colossus_fracture.json"))
	for point in data.seeds: points.append(Vector3(point[0],point[1],point[2]))
	cracks.set_shader_parameter("seeds", points)
	pieces.set_meta("cracks", cracks)
	for shard in shards:
		shard.material_overlay = cracks
		shard.set_meta("home", shard.transform)
		var center: Vector3 = shard.transform*shard.mesh.get_aabb().get_center()
		shard.set_meta("center", center)
		shard.set_meta("direction", (center-Vector3(0, 0.45, 0)).normalized())
	pieces.set_meta("shards", shards)

static func sync(game, view: Node3D, event: Dictionary) -> void:
	var run = game.run
	var dead: bool = event.hp <= 0 and event.has("defeated_at")
	var pieces: Node3D = view.get_node("DeathFragments")
	pieces.visible = false
	if not dead:
		for tag in ["final_roar", "final_burst", "final_clear"]: view.remove_meta(tag)
		view.get_node("Cinema/Name").text = "枯根巨像"
		view.get_node("Cinema/Epithet").text = "被腐化的森林守护者"
		return
	var t: float = run.elapsed-event.defeated_at
	view.get_node("BossBar").visible = false
	var body: Node3D = view.get_node("Body/Colossus")
	body.visible = t < SPLIT
	body.position.y = 0.0
	var heart: MeshInstance3D = body.get_node("Heart")
	heart.visible = t < SPLIT
	heart.scale = Vector3.ONE*(1.0+2.0*smoothstep(0.5, BURST, t))
	var light: OmniLight3D = body.get_node("HeartLight")
	light.light_energy = (3.0+9.0*smoothstep(0.5, BURST, t)) if t < BURST else 0.0
	var base := Vector3(event.origin.x/20.0, 0, -event.y/20.0)
	if t < BURST and not view.has_meta("final_roar"):
		view.set_meta("final_roar", true)
		game.sfx.play("colossus_death", -1.0, 1.0)
		game.sfx.play_at("wood_creak_heavy", base+Vector3.UP*8, 3.0, 0.6)
	if t >= BURST and t < TITLE and not view.has_meta("final_burst"):
		view.set_meta("final_burst", true)
		game.sfx.play("colossus_fracture", -1.0, 1.0)
		game.sfx.play_at("tree_fall", base, 3.0, 0.65)
		if game.get("fx") != null:
			game.fx.impact(base+Vector3.UP*8, Color("ffd38a"), 12.0, 5.0)
			game.fx.burst("dust", base)
		if game.get("hazard_fx") != null: game.hazard_fx.slam(base, 12.0)
	if t >= SPLIT and t < TITLE:
		pieces.visible = true
		pieces.position.x = event.origin.x/20.0
		var age := maxf(0.0, t-BURST)
		(pieces.get_meta("cracks") as ShaderMaterial).set_shader_parameter("strength", (1.0+5.0*smoothstep(SPLIT,BURST,t))*(1.0-smoothstep(BURST,BURST+1.3,t)))
		var opening := 0.024*smoothstep(SPLIT, BURST, t)
		var fade := 1.0-smoothstep(TITLE-1.4, TITLE, t)
		var shards: Array = pieces.get_meta("shards")
		for i in range(shards.size()):
			var shard: MeshInstance3D = shards[i]
			var home: Transform3D = shard.get_meta("home")
			var center: Vector3 = shard.get_meta("center")
			var direction: Vector3 = shard.get_meta("direction")
			var spin := Basis(Vector3(0.3+float(i%3), 1, 0.5).normalized(), age*(0.4+0.15*(i%4)))
			var displacement := direction*(opening+age*(0.14+0.025*(i%5)))+Vector3.UP*(age*0.12-age*age*0.11)
			shard.transform = Transform3D(spin.scaled(Vector3.ONE*fade), center+displacement-spin*(center*fade))*home
	var cinema: CanvasLayer = view.get_node("Cinema")
	cinema.visible = t < LENGTH and run.state in ["running", "paused"]
	if not cinema.visible: return
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var weight := smoothstep(0.0, 0.5, t)*(1.0-smoothstep(LENGTH-0.7, LENGTH, t))
	for name in ["Top", "Bottom"]:
		var bar: ColorRect = cinema.get_node(name)
		bar.size = Vector2(size.x, size.y*0.1*weight)
		bar.position = Vector2(0, 0 if name == "Top" else size.y-bar.size.y)
	var title: Label = cinema.get_node("Name")
	var subtitle: Label = cinema.get_node("Epithet")
	title.text = "恭喜通关"
	subtitle.text = "第一章 · 枯根巨像已击败"
	title.position = Vector2(0, size.y*0.38)
	title.size = Vector2(size.x, 80)
	title.scale = Vector2.ONE
	subtitle.position = title.position+Vector2(0, 85)
	subtitle.size = Vector2(size.x, 32)
	title.modulate.a = smoothstep(TITLE, TITLE+0.6, t)*weight
	subtitle.modulate.a = title.modulate.a
	cinema.get_node("Skip").modulate.a = 0.0
	if t >= TITLE and not view.has_meta("final_clear"):
		view.set_meta("final_clear", true)
		game.sfx.play("clear", -5.0, 0.9)
