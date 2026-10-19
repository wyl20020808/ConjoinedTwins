extends RefCounted

# 复用场景材质；怪物、血条与反馈都由模拟时间驱动，无逐怪物 _process / Tween。
# Tripo 文生 3D 静态模型（约 5.7k 三角面、1024 贴图）：[路径, 缩放, 实际高度(米)]。
# 原生最长边为 1、朝向 +X、脚底在原点；人形原生高 1，狼原生高约 0.73。
const SCANNED := {
	"briar":["res://assets/monsters/bark_sprite.glb",2.5,2.5],
	"raider":["res://assets/monsters/raider.glb",3.1,3.1],
	"sentinel":["res://assets/monsters/stone_guard.glb",3.7,3.7],
	"archer":["res://assets/monsters/raider_slinger.glb",3.0,3.0],
	"dasher":["res://assets/monsters/brute_charger.glb",3.2,3.2],
	"wolf":["res://assets/monsters/grey_wolf.glb",2.8,2.0],
}

static func model_path(archetype: String) -> String:
	return SCANNED[archetype][0] if SCANNED.has(archetype) else ""

static func make_monster(game, parent: Node3D, archetype: String) -> Node3D:
	if SCANNED.has(archetype) and ResourceLoader.exists(SCANNED[archetype][0]):
		return make_scanned(parent,archetype)
	var models:Dictionary=game.get_meta("enemy_models",{})
	if models.has(archetype):
		var instance:Node3D=models[archetype].instantiate();parent.add_child(instance);return instance
	var actor := Node3D.new();actor.name="Monster";parent.add_child(actor)
	var color: Color={"briar":Color("617648"),"raider":Color("9a5342"),"sentinel":Color("647b88"),"archer":Color("4e6449"),"dasher":Color("88533c"),"wolf":Color("777b75")}[archetype]
	var hide: Material=game.material("monster_"+archetype,color)
	var dark: Material=game.material("monster_dark",Color("293537"))
	var trim: Material=game.material("monster_trim",Color("c6ad77"))
	var glow: Material=game.material("monster_eyes",Color("ffcc68"),1.4)
	if archetype=="wolf":
		volume(actor,Vector3(0,.95,-.15),Vector3(.95,1.1,1.85),hide)
		volume(actor,Vector3(0,1.35,.75),Vector3(.8,.9,.9),hide)
		volume(actor,Vector3(0,1.12,1.28),Vector3(.5,.4,.65),dark)
		for side in [-1,1]:
			var ear:Node3D=game.box(actor,Vector3(side*.28,1.86,.7),Vector3(.23,.5,.28),dark);ear.rotation.z=-side*.2
			game.box(actor,Vector3(side*.27,1.4,1.12),Vector3(.13,.09,.07),glow)
			for front in [false,true]:
				var leg:=Node3D.new();actor.add_child(leg)
				leg.name=("Left" if side<0 else "Right")+("Arm" if front else "Leg")
				leg.position=Vector3(side*.36,.85,.5 if front else -.85)
				volume(leg,Vector3(0,-.36,.03),Vector3(.25,.8,.3),hide)
		var tail:Node3D=game.box(actor,Vector3(0,.9,-1.3),Vector3(.3,.3,1.1),hide);tail.rotation.x=-.35
		cache_model(game,actor,archetype)
		return actor
	volume(actor,Vector3(0,1.5,0),Vector3(1.25,1.6,.9),hide)
	game.box(actor,Vector3(0,1.35,.4),Vector3(.8,.55,.09),dark)
	volume(actor,Vector3(0,2.45,.12),Vector3(1.1,.95,.95),hide)
	game.box(actor,Vector3(0,2.4,.54),Vector3(.8,.23,.08),dark)
	for side in [-1,1]:
		game.box(actor,Vector3(side*.23,2.42,.6),Vector3(.18,.12,.06),glow)
		var leg:=Node3D.new();leg.name="LeftLeg" if side==-1 else "RightLeg"
		actor.add_child(leg);leg.position=Vector3(side*.35,.85,0)
		game.box(leg,Vector3(0,-.45,.05),Vector3(.36,.8,.48),dark)
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
	elif archetype=="archer":
		var bow:=Node3D.new();bow.name="Bow";actor.get_node("LeftArm").add_child(bow);bow.position=Vector3(0,-.8,.2)
		for n in range(7):
			var a:float=-1.2+n*.4
			var segment:Node3D=game.box(bow,Vector3(0,sin(a)*.8,cos(a)*.3),Vector3(.09,.37,.09),trim);segment.rotation.x=a*.4
		game.box(bow,Vector3(0,0,.1),Vector3(.025,1.5,.025),dark)
		game.box(actor,Vector3(.35,1.8,-.6),Vector3(.4,1.1,.4),dark)
	elif archetype=="dasher":
		game.box(actor,Vector3(0,2.8,.1),Vector3(1.2,.5,1),trim)
		for side in [-1,1]:
			game.box(actor,Vector3(side*.85,2.15,.1),Vector3(.65,.65,.9),dark)
	cache_model(game,actor,archetype)
	return actor

# 扫描模型没有骨骼：四肢关节为空节点以兼容同步逻辑，步态改由 Figure 整体摇摆/前倾表现。
# 同类实例共享导入后的网格与贴图资源。
static func make_scanned(parent: Node3D, archetype: String) -> Node3D:
	var actor := Node3D.new();actor.name="Monster";parent.add_child(actor)
	var figure:Node3D=load(SCANNED[archetype][0]).instantiate();figure.name="Figure"
	figure.scale=Vector3.ONE*SCANNED[archetype][1]
	figure.rotation.y=-PI/2
	actor.add_child(figure)
	for limb in ["LeftLeg","RightLeg","LeftArm","RightArm"]:
		var joint:=Node3D.new();joint.name=limb;actor.add_child(joint)
	actor.set_meta("figure_height",SCANNED[archetype][2])
	return actor

# 静态躯干按材质合并，四肢保留独立关节；同类实例共享网格资源。
static func cache_model(game,actor:Node3D,archetype:String)->void:
	var groups:={}
	for child in actor.get_children():
		if not child is MeshInstance3D:continue
		var mat:Material=child.material_override
		if not groups.has(mat):
			var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES);groups[mat]=tool
		groups[mat].append_from(child.mesh,0,child.transform)
		child.free()
	for mat:Material in groups:
		var mesh:=MeshInstance3D.new();mesh.mesh=groups[mat].commit();mesh.material_override=mat;actor.add_child(mesh)
	assign_owner(actor,actor)
	var packed:=PackedScene.new();packed.pack(actor)
	var models:Dictionary=game.get_meta("enemy_models",{});models[archetype]=packed;game.set_meta("enemy_models",models)

static func assign_owner(node:Node,owner_node:Node)->void:
	for child in node.get_children():
		child.owner=owner_node;assign_owner(child,owner_node)

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
	view.set_meta("bar_height",body.get_meta("figure_height",2.9)+.6)
	view.set_meta("last_hit_at",-1.0)
	view.set_meta("hit_flash",false)
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
	if not game.model_visible(event.y): return
	# 模拟窗口外的敌人尚未行动，静止远景只初始化一次；进入近景立即恢复动画。
	var far:bool=event.kind=="monster" and absf(event.y-run.distance)>1400
	if far and view.get_meta("enemy_far_ready",false):return
	view.set_meta("enemy_far_ready",far)
	var point:Vector2=run.Combat.enemy_position(event)
	var location:=Vector3(point.x/20,0,-point.y/20)
	var actor:Node3D=view.get_meta("enemy_body")
	actor.rotation=view.get_meta("enemy_rotation");actor.scale=view.get_meta("enemy_scale")
	if event.kind=="monster":
		actor.position=Vector3(event.origin.x/20,0,0)
		var target:Vector2=event.get("facing",Vector2(0,-1))
		actor.rotation.y=atan2(target.x,-target.y)
		var stride:float=event.get("stride",0.0)
		var moving:bool=event.get("velocity",Vector2.ZERO).length_squared()>1 and not died
		var swing:float=sin(stride)*.85 if moving else 0.0
		actor.position.y=run.surface_at(event.origin,run.elapsed).height/20.0+(absf(sin(stride))*.12 if moving else 0.0)
		actor.rotation.x=-.16 if moving else 0.0
		actor.get_node("LeftLeg").rotation.x=swing
		actor.get_node("RightLeg").rotation.x=-swing
		var charge:=sin(clampf((run.elapsed-event.trigger)/run.Monsters.profile(event).windup,0,1)*PI/2) if event.phase=="warning" else 0.0
		actor.get_node("LeftArm").rotation.x=-charge*1.7-swing*.7
		actor.get_node("RightArm").rotation.x=-charge*1.7+swing*.7
		if event.archetype=="archer" and event.phase in ["warning","active"]:
			actor.get_node("LeftArm").rotation.x=-1.5
			actor.get_node("RightArm").rotation.x=-1.5+charge*.65
		elif event.archetype in ["dasher","wolf"]:
			actor.position.y-=charge*.22
			actor.rotation.x=-charge*.3-(.25 if event.phase=="active" else 0.0)
			if event.archetype=="wolf":
				actor.get_node("LeftArm").rotation.x=-swing
				actor.get_node("RightArm").rotation.x=swing
		if actor.has_node("Figure"):
			# Figure 原生朝 +X：绕本地 X 为左右摇摆，绕本地 Z 为前后俯仰（正值后仰蓄力）。
			var figure:Node3D=actor.get_node("Figure")
			figure.rotation.x=swing*.11
			figure.rotation.z=charge*.28
		view.get_node("Body").visible=event.phase=="active" and not died and event.archetype not in ["dasher","wolf"]
		view.get_node("Hint").hide()
	var hit_age:float=run.elapsed-event.get("hit_at",-10.0)
	# 命中火花与倒地尘爆：按模拟命中/击败时间各触发一次，只读状态。
	var fx=game.get("fx")
	if fx!=null and event.kind=="monster":
		var body_height:float=actor.get_meta("figure_height",2.9)
		if event.get("hit_at",-10.0)>view.get_meta("fx_hit_at",-10.0) and hit_age<.1:
			view.set_meta("fx_hit_at",event.hit_at);fx.burst("spark",location+Vector3(0,body_height*.6,0))
		if died and not view.get_meta("fx_dead",false):
			view.set_meta("fx_dead",true);fx.burst("dust",location+Vector3(0,.1,0))
	var flashing:bool=hit_age<.09
	if flashing!=view.get_meta("hit_flash",false):
		var flash:Material=game.material("enemy_hit_flash",Color("ffe2ad"),.9) if flashing else null
		for mesh in view.get_meta("enemy_meshes"): mesh.material_overlay=flash
		view.set_meta("hit_flash",flashing)
	if hit_age<.2: actor.rotation.x-=sin(hit_age/.2*PI)*.22
	if died:
		actor.show();actor.rotation.x-=smoothstep(0,.45,death_age)*1.2
		actor.scale*=maxf(.01,1.0-smoothstep(.18,.48,death_age))
		view.get_node("Warning").hide();view.get_node("Hint").hide()
	var health:Node3D=view.get_node("EnemyHealth")
	health.visible=not died and event.phase!="spent" and absf(point.y-run.distance)<800
	if health.visible:
		health.global_position=location+Vector3(0,view.get_meta("bar_height",3.5)+event.get("ground_height",0.0)/20,0)
		health.global_basis=game.camera.global_basis
		var health_key:Vector2i=Vector2i(event.hp,event.max_hp)
		if view.get_meta("health_key",Vector2i(-1,-1))!=health_key:
			var ratio:=clampf(float(event.hp)/event.max_hp,0,1)
			var fill:MeshInstance3D=health.get_node("Fill");fill.scale.x=maxf(.001,ratio);fill.position.x=-1.5*(1-ratio)
			var color:=Color("81d694") if ratio>.5 else (Color("ffc36a") if ratio>.25 else Color("f17666"))
			fill.material_override=game.material("enemy_ui_"+color.to_html(),color)
			fill.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			view.set_meta("health_key",health_key)
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
