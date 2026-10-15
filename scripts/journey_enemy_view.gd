extends RefCounted

# 复用场景材质；怪物、血条与反馈都由模拟时间驱动，无逐怪物 _process / Tween。
static func make_monster(game, parent: Node3D, archetype: String) -> Node3D:
	var actor := Node3D.new();actor.name="Monster";parent.add_child(actor)
	var color: Color={"briar":Color("617648"),"raider":Color("9a5342"),"sentinel":Color("647b88")}[archetype]
	var hide: Material=game.material("monster_"+archetype,color)
	var dark: Material=game.material("monster_dark",Color("293537"))
	var trim: Material=game.material("monster_trim",Color("c6ad77"))
	var glow: Material=game.material("monster_eyes",Color("ffcc68"),1.4)
	volume(actor,Vector3(0,1.5,0),Vector3(1.25,1.6,.9),hide)
	game.box(actor,Vector3(0,1.35,.4),Vector3(.8,.55,.09),dark)
	volume(actor,Vector3(0,2.45,.12),Vector3(1.1,.95,.95),hide)
	game.box(actor,Vector3(0,2.4,.54),Vector3(.8,.23,.08),dark)
	for side in [-1,1]:
		game.box(actor,Vector3(side*.23,2.42,.6),Vector3(.18,.12,.06),glow)
		game.box(actor,Vector3(side*.35,.4,.05),Vector3(.36,.8,.48),dark)
		var arm:=Node3D.new();arm.name="LeftArm" if side==-1 else "RightArm"
		actor.add_child(arm);arm.position=Vector3(side*.7,2.0,0)
		game.box(arm,Vector3(0,-.4,0),Vector3(.35,1.0,.4),hide)
		game.box(arm,Vector3(0,-.9,.05),Vector3(.46,.32,.48),trim)
		if archetype=="briar":
			var horn:Node3D=game.cylinder(actor,Vector3(side*.45,3.05,.03),.12,.9,trim)
			horn.rotation.z=-side*.4
		elif archetype=="sentinel":
			game.box(actor,Vector3(side*.75,2.1,0),Vector3(.6,.45,.85),trim)
		else:
			game.box(actor,Vector3(side*.61,2.5,.12),Vector3(.22,.34,.8),dark)
	if archetype=="raider":
		game.box(actor,Vector3(0,2.85,.13),Vector3(1.14,.16,.9),trim)
		var scarf:Node3D=game.box(actor,Vector3(.45,1.9,-.25),Vector3(.28,.9,.13),hide)
		scarf.rotation.z=-.3
	elif archetype=="sentinel":
		game.box(actor,Vector3(0,2.95,.08),Vector3(.3,.4,.65),glow)
	return actor

static func volume(parent:Node3D,position:Vector3,size:Vector3,mat:Material)->void:
	var mesh:=MeshInstance3D.new();var shape:=SphereMesh.new()
	shape.radius=.5;shape.height=1;shape.radial_segments=8;shape.rings=4
	mesh.mesh=shape;mesh.material_override=mat;mesh.position=position;mesh.scale=size
	parent.add_child(mesh)

static func meshes(node: Node, result: Array) -> void:
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): meshes(child,result)

static func panel(game, parent: Node3D, name: String, size: Vector2, color: Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=name
	var quad:=QuadMesh.new();quad.size=size;node.mesh=quad
	var mat:StandardMaterial3D=game.material("enemy_ui_"+color.to_html(),color)
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override=mat;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func prepare(game, view: Node3D, event: Dictionary) -> void:
	var body:Node3D=view.get_node("Monster" if event.kind=="monster" else ("Villager" if event.kind=="stone" else "Body"))
	var parts:Array=[];meshes(body,parts)
	view.set_meta("enemy_meshes",parts)
	view.set_meta("enemy_body",body)
	view.set_meta("enemy_scale",body.scale)
	view.set_meta("enemy_rotation",body.rotation)
	view.set_meta("last_hit_at",-1.0)
	var health:=Node3D.new();health.name="EnemyHealth";view.add_child(health)
	panel(game,health,"Back",Vector2(3.15,.34),Color("18262d"))
	var fill:=panel(game,health,"Fill",Vector2(3.0,.22),Color("81d694"));fill.position.z=.02
	var title:Label3D=game.add_sign(health,"",Vector3(0,.7,0),28);title.name="Title";title.pixel_size=.03
	var damage:Label3D=game.add_sign(view,"",Vector3.ZERO,30);damage.name="HitNumber";damage.pixel_size=.03;damage.modulate=Color("fff1b5")
	var burst:=Node3D.new();burst.name="HitBurst";view.add_child(burst)
	for angle in [PI/4,-PI/4]:
		var ray:=panel(game,burst,"Spark",Vector2(.75,.09),Color("ffe8a0"));ray.rotation.z=angle

static func sync(game, view: Node3D, event: Dictionary) -> void:
	var run=game.run
	if not view.has_node("EnemyHealth"): prepare(game,view,event)
	var died:bool=event.hp<=0
	var death_age:float=run.elapsed-event.get("defeated_at",-10.0)
	if died and death_age>.48:
		view.hide();return
	# 不把加载队列中尚未进入显示窗口的敌人重新显示出来。
	if event.y-run.distance< -900 or event.y-run.distance>=4200: return
	var point:Vector2=run.Combat.enemy_position(event)
	var location:=Vector3(point.x/20,0,-point.y/20)
	var actor:Node3D=view.get_meta("enemy_body")
	actor.rotation=view.get_meta("enemy_rotation");actor.scale=view.get_meta("enemy_scale")
	if event.kind=="monster":
		actor.position=Vector3(event.origin.x/20,0,0)
		var target:Vector2=(run.a.position+run.b.position)*.5-event.origin
		actor.rotation.y=atan2(target.x,-target.y)
		actor.position.y=sin(run.elapsed*3+event.id)*.045
		var charge:=sin(clampf((run.elapsed-event.trigger)/run.Monsters.WINDUP,0,1)*PI/2) if event.phase=="warning" else 0.0
		actor.get_node("LeftArm").rotation.x=-charge*1.7
		actor.get_node("RightArm").rotation.x=-charge*1.7
		view.get_node("Body").visible=event.phase=="active" and not died
		view.get_node("Hint").hide()
	var hit_age:float=run.elapsed-event.get("hit_at",-10.0)
	var flash:Material=game.material("enemy_hit_flash",Color("ffe2ad"),.9) if hit_age<.09 else null
	for mesh in view.get_meta("enemy_meshes"): mesh.material_overlay=flash
	if hit_age<.2: actor.rotation.x-=sin(hit_age/.2*PI)*.22
	if died:
		actor.show();actor.rotation.x-=smoothstep(0,.45,death_age)*1.2
		actor.scale*=maxf(.01,1.0-smoothstep(.18,.48,death_age))
		view.get_node("Warning").hide();view.get_node("Hint").hide()
	var health:Node3D=view.get_node("EnemyHealth")
	health.visible=not died and event.phase!="spent" and absf(point.y-run.distance)<800
	health.global_position=location+Vector3(0,3.5,0)
	health.global_basis=game.camera.global_basis
	var ratio:=clampf(float(event.hp)/event.max_hp,0,1)
	var fill:MeshInstance3D=health.get_node("Fill");fill.scale.x=maxf(.001,ratio);fill.position.x=-1.5*(1-ratio)
	var color:=Color("81d694") if ratio>.5 else (Color("ffc36a") if ratio>.25 else Color("f17666"))
	fill.material_override=game.material("enemy_ui_"+color.to_html(),color)
	fill.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var locked:bool=run.combat.weapons.any(func(w):return not w.is_empty() and w.target==event.id)
	var title:Label3D=health.get_node("Title")
	var enemy_name:String=run.Monsters.NAMES[event.archetype] if event.kind=="monster" else ("野猪" if event.kind=="boar" else "投掷者")
	title.visible=locked or hit_age<.4
	title.text=("锁定 · " if locked else "")+enemy_name
	title.modulate=Color("ffe18b") if locked else Color("e8ebe2")
	var number:Label3D=view.get_node("HitNumber");number.visible=hit_age<.4
	number.text="击败" if died else "-%d"%event.get("hit_damage",10)
	number.global_position=location+Vector3(0,3.0+hit_age*2,.1)
	number.modulate.a=clampf(1-hit_age/.4,0,1)
	var burst:Node3D=view.get_node("HitBurst");burst.visible=hit_age<.12
	burst.global_position=location+Vector3(0,run.Combat.enemy_height(event)/20,.1)
	burst.global_basis=game.camera.global_basis.scaled(Vector3.ONE*(1+maxf(0,hit_age)*5))
	if hit_age<.2 and event.hit_at!=view.get_meta("last_hit_at"):
		game.sfx.play("buckle",-15.0,.7 if died else 1.25)
	view.set_meta("last_hit_at",event.get("hit_at",-1.0))
