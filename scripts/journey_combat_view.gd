extends Node3D

# 仅呈现模拟数据，不参与伤害、拾取或锁敌判定。
const EnemyView=preload("res://scripts/journey_enemy_view.gd")
var game
var pickup_views := {}
var guns: Array[Node3D] = []
var beams: Array[MeshInstance3D] = []
# 霰弹枪每人 7 条弹丸曳光（第 0 条与普通曳光共用）；喷火器火舌；榴弹飞行体。
var pellet_beams: Array = []
var flames: Array[GPUParticles3D] = []
var grenades: Array[MeshInstance3D] = []
var exploded := [0,0]
const WEAPON_MODELS := {"shotgun":"res://assets/weapons/shotgun.glb","flamer":"res://assets/weapons/flamer.glb","launcher":"res://assets/weapons/launcher.glb"}
const GRENADE_FLIGHT := 0.28
var last_shots := [0,0]
var previous_health := [100,100]
var previous_shield_uses := 0
var previous_reload := [0,0]

func make_gun(parent: Node3D) -> Node3D:
	var gun := Node3D.new()
	parent.add_child(gun)
	var metal: Material=game.material("gun_metal",Color("354b54"))
	var grip: Material=game.material("gun_grip",Color("6c4d35"))
	game.box(gun,Vector3(0,0,-0.24),Vector3(0.18,0.2,0.64),metal)
	game.box(gun,Vector3(0,0,-0.7),Vector3(0.08,0.08,0.38),metal)
	game.box(gun,Vector3(0,0,0.2),Vector3(0.14,0.16,0.3),grip)
	var handle: Node3D=game.box(gun,Vector3(0,-0.2,-0.05),Vector3(0.12,0.32,0.14),grip)
	handle.rotation.x=-0.15
	var magazine: Node3D=game.box(gun,Vector3(0,-0.22,-0.37),Vector3(0.16,0.34,0.2),grip)
	magazine.name="Magazine"
	game.box(gun,Vector3(0,-0.41,-0.37),Vector3(0.19,0.04,0.23),metal).name="MagazineLip"
	game.box(gun,Vector3(0.13,0.04,-0.15),Vector3(0.12,0.06,0.08),metal).name="ChargingHandle"
	game.box(gun,Vector3(0,0.13,-0.2),Vector3(0.05,0.1,0.12),game.material("gun_sight",Color("71e9cf"),0.7))
	add_flash(gun,-1.02)
	return gun

# 三把新枪来自 build-tools/journey/make_weapons.py 生成的低模 GLB；枪口与弹匣位置读取模型里的标记点。
func make_weapon(parent: Node3D, type: String) -> Node3D:
	if type=="smg":return make_gun(parent)
	var gun := Node3D.new()
	parent.add_child(gun)
	var model: Node3D=load(WEAPON_MODELS[type]).instantiate()
	gun.add_child(model)
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		(mesh as GeometryInstance3D).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var muzzle: Node3D=model.find_child("Muzzle",true,false)
	var mark: Node3D=model.find_child("Magazine",true,false)
	var magazine:=Node3D.new();magazine.name="Magazine";gun.add_child(magazine)
	if mark:magazine.position=mark.position
	add_flash(gun,muzzle.position.z if muzzle else -0.95)
	if muzzle:gun.get_node("Flash").position=muzzle.position
	return gun

# 枪口焰：两片十字交叉的加色火焰面片加一片朝后的星形，每次射击随机旋转缩放。
func add_flash(gun: Node3D, muzzle_z: float) -> void:
	var flash:=Node3D.new();flash.name="Flash";flash.position=Vector3(0,0,muzzle_z);gun.add_child(flash)
	for n in range(3):
		var quad:=MeshInstance3D.new();var plane:=QuadMesh.new()
		plane.size=Vector2(0.55,0.9) if n<2 else Vector2(0.6,0.6)
		quad.mesh=plane;quad.material_override=muzzle_material()
		quad.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.rotation=Vector3(-PI/2,n*PI/2,0) if n<2 else Vector3(0,0,0)
		if n<2:quad.position.z=-0.25
		flash.add_child(quad)
	flash.hide()
	var flash_light:=OmniLight3D.new()
	flash_light.name="FlashLight"
	flash_light.position=Vector3(0,0,muzzle_z+0.07)
	flash_light.light_color=Color("ffdca0")
	flash_light.light_energy=3.2
	flash_light.omni_range=3.0
	flash_light.shadow_enabled=false
	flash_light.visible=false
	gun.add_child(flash_light)

# 喷火器火舌：沿枪口前方喷出的加色火团，随距离变大、变暗。
func make_flame()->GPUParticles3D:
	var process:=ParticleProcessMaterial.new()
	process.direction=Vector3(0,0,-1);process.spread=14.0
	process.initial_velocity_min=11.0;process.initial_velocity_max=14.0
	process.gravity=Vector3(0,1.5,0)
	process.scale_min=0.5;process.scale_max=0.8
	var grow:=Curve.new();grow.add_point(Vector2(0,0.35));grow.add_point(Vector2(1,2.4))
	var curve:=CurveTexture.new();curve.curve=grow;process.scale_curve=curve
	var tint:=Gradient.new()
	tint.set_color(0,Color(1.0,0.95,0.7,1.0));tint.add_point(0.4,Color(1.0,0.55,0.15,0.9));tint.set_color(tint.get_point_count()-1,Color(0.35,0.12,0.05,0.0))
	var ramp:=GradientTexture1D.new();ramp.gradient=tint;process.color_ramp=ramp
	var quad:=QuadMesh.new();quad.size=Vector2(0.5,0.5)
	var mat:=muzzle_material().duplicate()
	mat.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo=true
	quad.material=mat
	var particles:=GPUParticles3D.new()
	particles.amount=48;particles.lifetime=0.55;particles.emitting=false;particles.local_coords=false
	particles.process_material=process;particles.draw_pass_1=quad
	particles.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb=AABB(Vector3(-6,-4,-12),Vector3(12,8,14))
	add_child(particles)
	return particles

static var muzzle_mat:StandardMaterial3D
static func muzzle_material()->StandardMaterial3D:
	if muzzle_mat:return muzzle_mat
	var gradient:=Gradient.new()
	gradient.set_color(0,Color(1.0,0.97,0.85,1.0));gradient.add_point(0.35,Color(1.0,0.75,0.3,0.85));gradient.set_color(gradient.get_point_count()-1,Color(1.0,0.4,0.05,0.0))
	var texture:=GradientTexture2D.new();texture.gradient=gradient
	texture.fill=GradientTexture2D.FILL_RADIAL;texture.fill_from=Vector2(0.5,0.5);texture.fill_to=Vector2(0.5,0.0)
	muzzle_mat=StandardMaterial3D.new()
	muzzle_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	muzzle_mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	muzzle_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	muzzle_mat.albedo_texture=texture
	muzzle_mat.albedo_color=Color(2.4,1.9,1.2,1.0)
	return muzzle_mat

# 抛弹壳：每次开枪从枪右侧抛出一枚黄铜弹壳，带旋转与重力。
var casings:Array[GPUParticles3D]=[]
func make_casings()->GPUParticles3D:
	var process:=ParticleProcessMaterial.new()
	process.direction=Vector3(1,0.8,0.2);process.spread=18.0
	process.initial_velocity_min=2.2;process.initial_velocity_max=3.2
	process.gravity=Vector3(0,-14,0)
	process.angular_velocity_min=-900.0;process.angular_velocity_max=900.0
	var shell:=CylinderMesh.new();shell.top_radius=0.022;shell.bottom_radius=0.022;shell.height=0.07;shell.radial_segments=6;shell.rings=1
	var brass:=StandardMaterial3D.new();brass.albedo_color=Color("c99a3c");brass.metallic=0.9;brass.roughness=0.3
	shell.material=brass
	var particles:=GPUParticles3D.new()
	particles.amount=6;particles.lifetime=0.8;particles.one_shot=false;particles.explosiveness=0.0
	particles.emitting=false;particles.local_coords=false
	particles.process_material=process;particles.draw_pass_1=shell
	particles.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	return particles

func _ready() -> void:
	for role in range(2):
		var holder:=Node3D.new()
		add_child(holder)
		for type in ["smg","shotgun","flamer","launcher"]:
			var variant:=make_weapon(holder,type)
			variant.name=type
			variant.visible=type=="smg"
		guns.append(holder)
		flames.append(make_flame())
		var grenade:=MeshInstance3D.new()
		var ball:=SphereMesh.new();ball.radius=0.12;ball.height=0.24;ball.radial_segments=8;ball.rings=4
		grenade.mesh=ball
		grenade.material_override=game.material("grenade_shell",Color("6b7a3a"),0.4)
		grenade.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grenade.visible=false
		add_child(grenade)
		grenades.append(grenade)
		var shield := MeshInstance3D.new()
		shield.name="CombatShield"
		var bubble := SphereMesh.new()
		bubble.radius=1.15
		bubble.height=3.8
		shield.mesh=bubble
		shield.position.y=1.8
		var mat: StandardMaterial3D=game.material("combat_shield",Color(0.28,0.8,0.9,0.18),0.3)
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		shield.material_override=mat
		shield.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		game.robots[role].add_child(shield)
		var beam := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius=0.03
		mesh.bottom_radius=0.03
		mesh.radial_segments=6
		beam.mesh=mesh
		# 曳光：HDR 超出 1 会在 Screen 晕光里晕开。
		beam.material_override=game.material("bullet_trail",Color("ffdc8c"),4.0)
		beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		beams.append(beam)
		var spread:Array[MeshInstance3D]=[beam]
		for n in range(6):
			var pellet:=MeshInstance3D.new()
			pellet.mesh=mesh
			pellet.material_override=beam.material_override
			pellet.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pellet.visible=false
			add_child(pellet)
			spread.append(pellet)
		pellet_beams.append(spread)
		casings.append(make_casings())

var pillar_materials:={}
func pillar_material(kind:String)->Material:
	if pillar_materials.has(kind):return pillar_materials[kind]
	var color:Color={"gun":Color("ffcf6a"),"ammo":Color("ffd36a"),"medkit":Color("7dffb0")}.get(kind,Color("9fe8ff"))
	var fade:=Gradient.new()
	fade.set_color(0,Color(1,1,1,0.0));fade.add_point(0.8,Color(1,1,1,0.35));fade.set_color(fade.get_point_count()-1,Color(1,1,1,0.75))
	var texture:=GradientTexture2D.new();texture.gradient=fade;texture.fill_from=Vector2(0,0);texture.fill_to=Vector2(0,1);texture.width=8;texture.height=64
	var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test=false
	mat.albedo_color=Color(color.r,color.g,color.b,0.5)
	mat.albedo_texture=texture
	mat.disable_receive_shadows=true
	pillar_materials[kind]=mat
	return mat

func reset() -> void:
	for view in pickup_views.values(): view.queue_free()
	pickup_views.clear()
	last_shots=[0,0]
	exploded=[0,0]
	previous_health=game.run.combat.health.duplicate()
	previous_shield_uses=game.run.shield_uses

func sync() -> void:
	var run=game.run
	var visual_state:String=run.paused_from if run.state=="paused" else run.state
	# 一次建立可见拾取集合，同时清理已领取和离开窗口的节点。
	var nearby:={}
	for pickup in run.combat.pickups:
		if absf(pickup.position.y-run.distance)<3000:nearby[pickup.id]=pickup
	for id in pickup_views.keys():
		if not nearby.has(id):
			var collected:Node3D=pickup_views[id]
			var fx=game.get("fx")
			if fx!=null and is_instance_valid(collected) and collected.visible and collected.global_position.distance_to(game.robots[0].global_position)<60.0:
				fx.burst("spark",collected.global_position+Vector3(0,0.4,0))
				if game.get("coop_fx")!=null:game.coop_fx.pickup(collected.global_position)
			collected.queue_free()
			pickup_views.erase(id)
	for pickup in nearby.values():
		if not pickup_views.has(pickup.id):
			var view := Node3D.new()
			add_child(view)
			pickup_views[pickup.id]=view
			if pickup.kind=="gun":
				var gun := make_weapon(view,pickup.get("weapon_type","smg"))
				gun.rotation.z=PI/2
				gun.scale=Vector3.ONE*1.3
			else:
				var color := Color("d6ae48") if pickup.kind=="ammo" else Color("e8ebe2")
				game.box(view,Vector3.ZERO,Vector3(0.75,0.5,0.65),game.material("pickup_"+pickup.kind,color))
				if pickup.kind=="medkit":
					var red: Material=game.material("medical_cross",Color("de5752"),0.3)
					game.box(view,Vector3(0,0.28,0),Vector3(0.5,0.05,0.16),red)
					game.box(view,Vector3(0,0.28,0),Vector3(0.16,0.05,0.5),red)
			game.cylinder(view,Vector3(0,-0.4,0),0.75,0.04,game.material("pickup_ring",Color("62c7ba"),0.6))
			# 竖直光柱：远处也能一眼看到拾取物，颜色按种类区分。
			var pillar:MeshInstance3D=game.cylinder(view,Vector3(0,2.6,0),0.26,6.0,pillar_material(pickup.kind))
			pillar.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var tube:CylinderMesh=pillar.mesh;tube.cap_top=false;tube.cap_bottom=false;tube.radial_segments=12
			var gun_name:String=run.Combat.WEAPONS[pickup.get("weapon_type","smg")].name
			game.add_sign(view,{"gun":gun_name,"ammo":"弹药补给","medkit":"医疗 +30"}[pickup.kind],Vector3(0,1.2,0),22)
		var view: Node3D=pickup_views[pickup.id]
		view.position=Vector3(pickup.position.x/20,0.65+sin(run.elapsed*2)*0.08,-pickup.position.y/20)
		view.visible=absf(pickup.position.y-run.distance)<3000
		for child in view.get_children():
			if child is Label3D:child.visible=visual_state not in ["rescue","failed"]
	for role in range(2):
		game.robots[role].get_node("CombatShield").visible=run.shield
		var weapon: Dictionary=run.combat.weapons[role]
		guns[role].visible=not weapon.is_empty() and visual_state not in ["rescue","failed","complete","settlement"]
		var type:String=weapon.get("type","smg")
		for variant in guns[role].get_children():variant.visible=variant.name==type
		var model:Node3D=guns[role].get_node(type)
		# 与既有角色右手骨骼同步，枪身朝向模拟选中的目标。
		var known:Skeleton3D=game.hand_skeletons.get(role)
		if is_instance_valid(known):known.clear_bones_global_pose_override()
		var hand: Vector3=game.hand_point(role)
		var skeleton: Skeleton3D=game.hand_skeletons.get(role)
		if is_instance_valid(skeleton):
			var wrist:int=game.find_bone(skeleton,"RightHand","Wrist.R")
			if wrist>=0: hand=skeleton.global_transform*skeleton.get_bone_global_pose(wrist).origin
		guns[role].global_position=hand
		var target := hand+Vector3(0,0,-5)
		if not weapon.is_empty():
			for event in run.journey_events:
				if event.id==weapon.target:
					var point: Vector2=run.Combat.enemy_position(event)
					target=Vector3(point.x/20,run.Combat.enemy_height(event)/20,-point.y/20)
		if hand.distance_to(target)>0.01: guns[role].look_at(target)
		apply_reload(guns[role],model,int(weapon.get("reload",0)),run.Combat.spec(weapon).reload if not weapon.is_empty() else 1)
		if guns[role].visible and is_instance_valid(skeleton) and int(weapon.get("reload",0))>0:
			reach_hand(skeleton,"R",guns[role].global_position)
			reach_hand(skeleton,"L",model.to_global(model.get_node("Magazine").position))
		var shot: Dictionary=run.combat.shots[role]
		var shot_type:String=shot.get("type","smg")
		var recent: bool=not shot.is_empty() and run.elapsed-shot.time<0.065 and visual_state=="running"
		# 喷火器连发间隔 0.05 秒，火舌在扳机松开后 0.12 秒内熄灭。
		flames[role].emitting=not shot.is_empty() and shot_type=="flamer" and run.elapsed-shot.time<0.12 and visual_state=="running" and guns[role].visible
		if flames[role].emitting:flames[role].global_transform=model.get_node("Flash").global_transform
		sync_grenade(role,shot,visual_state)
		model.get_node("Flash").visible=recent and shot_type!="flamer"
		var flash_light:OmniLight3D=model.get_node_or_null("FlashLight")
		if flash_light!=null:flash_light.visible=recent or flames[role].emitting
		beams[role].visible=recent and shot_type in ["smg","shotgun"]
		for n in range(1,pellet_beams[role].size()):pellet_beams[role][n].visible=false
		if recent:
			if int(weapon.get("reload",0))==0:
				var recoil:float=1.0-clampf((run.elapsed-shot.time)/.065,0,1)
				guns[role].position+=guns[role].basis.z*.12*recoil
				guns[role].rotate_object_local(Vector3.RIGHT,.07*recoil)
			var from := Vector3(shot.from.x/20,shot.height/20,-shot.from.y/20)
			var to := Vector3(shot.to.x/20,shot.target_height/20,-shot.to.y/20)
			place_beam(beams[role],from,to)
			if shot_type=="shotgun":
				var ends:Array=shot.get("pellets",[])
				for n in range(mini(ends.size(),pellet_beams[role].size())):
					var end:Vector2=ends[n]
					place_beam(pellet_beams[role][n],from,Vector3(end.x/20,shot.height/20,-end.y/20))
					pellet_beams[role][n].visible=true
			if shot.id!=last_shots[role]:
				if shot_type!="flamer" or int(shot.id)%6==0:game.sfx.play("whoosh" if shot_type=="flamer" else "gunshot",{"smg":-13.0,"shotgun":-7.0,"flamer":-16.0,"launcher":-9.0}.get(shot_type,-13.0),{"shotgun":0.7,"launcher":0.55}.get(shot_type,1.0))
				var flash_node:Node3D=model.get_node("Flash")
				flash_node.rotation.z=randf()*TAU
				flash_node.scale=Vector3.ONE*randf_range(0.8,1.25)
				casings[role].global_transform=model.global_transform
				casings[role].emitting=true
				casings[role].amount_ratio=1.0
				casings[role].set_meta("until",run.elapsed+0.05)
		if not shot.is_empty(): last_shots[role]=shot.id
		if casings[role].emitting and run.elapsed>float(casings[role].get_meta("until",0.0)):casings[role].emitting=false
		if run.combat.health[role]<previous_health[role]: game.sfx.play_at("punch_heavy",game.robots[role].global_position+Vector3(0,1.5,0),-2.0,0.95)
		# 换弹：开始时卸弹匣，结束时上膛。
		var reloading:int=int(weapon.get("reload",0))
		if reloading>0 and previous_reload[role]==0: game.sfx.play_at("metal_latch",guns[role].global_position,-6.0)
		elif reloading==0 and previous_reload[role]>0 and not weapon.is_empty(): game.sfx.play_at("metal_click",guns[role].global_position,-4.0)
		previous_reload[role]=reloading
		previous_health[role]=run.combat.health[role]
	if run.shield_uses>previous_shield_uses: game.sfx.play("shield_break",-6.0)
	previous_shield_uses=run.shield_uses
	for event in run.journey_events:
		if event.has("hp") and game.event_views.has(event.id):
			EnemyView.sync(game,game.event_views[event.id],event)

# 无 Tween、无墙钟时间：暂停、联机、重试和丢枪都直接服从武器剩余帧数。
# 从固定背后视角能看到抬枪、倾斜弹匣口、抽出/插入弹匣和拉栓归位。
func apply_reload(gun:Node3D,model:Node3D,remaining:int,total:int)->void:
	var t:float=1.0-float(remaining)/maxf(1,total)
	var lift:=smoothstep(0.0,0.16,t)*(1.0-smoothstep(0.84,1.0,t)) if remaining>0 else 0.0
	var eject:=smoothstep(0.18,0.38,t)*(1.0-smoothstep(0.58,0.78,t)) if remaining>0 else 0.0
	gun.rotate_object_local(Vector3.RIGHT,-0.65*lift)
	gun.rotate_object_local(Vector3.BACK,-0.85*lift)
	gun.position+=Vector3(0.38,0.48,0.12)*lift
	# 只有程序化冲锋枪有可拆弹匣与拉机柄；新枪模型只做抬枪换弹姿势。
	if not model.has_node("MagazineLip"):return
	var magazine:Node3D=model.get_node("Magazine")
	magazine.position=Vector3(-0.2*eject,-0.22-0.65*eject,-0.37+0.12*eject)
	magazine.rotation.z=-0.3*eject
	model.get_node("MagazineLip").position=magazine.position+Vector3(0,-0.19,0)
	var rack:=sin(clampf((t-0.78)/0.14,0,1)*PI) if remaining>0 else 0.0
	model.get_node("ChargingHandle").position.z=-0.15+0.18*rack

func place_beam(beam:MeshInstance3D,from:Vector3,to:Vector3)->void:
	beam.position=(from+to)/2
	if from.distance_to(to)>0.001: beam.quaternion=Quaternion(Vector3.UP,(to-from).normalized())
	# 光束拓扑固定，长度由变换表达，避免每次射击销毁并重建渲染表面。
	beam.scale.y=maxf(.001,from.distance_to(to)/beam.mesh.height)

# 榴弹：伤害在开火的固定步已结算；画面上用 0.28 秒抛物线飞到落点再炸开。
func sync_grenade(role:int,shot:Dictionary,visual_state:String)->void:
	var grenade:=grenades[role]
	if shot.is_empty() or shot.get("type","")!="launcher" or visual_state!="running":
		grenade.visible=false
		return
	var t:float=(game.run.elapsed-float(shot.time))/GRENADE_FLIGHT
	var from := Vector3(shot.from.x/20,shot.height/20,-shot.from.y/20)
	var to := Vector3(shot.to.x/20,float(shot.target_height)/20*0.4,-shot.to.y/20)
	grenade.visible=t>=0 and t<1
	if grenade.visible:
		grenade.position=from.lerp(to,t)+Vector3(0,sin(t*PI)*from.distance_to(to)*0.18,0)
	elif t>=1 and exploded[role]!=int(shot.id):
		exploded[role]=int(shot.id)
		var fx=game.get("fx")
		if fx!=null:
			fx.impact(Vector3(to.x,0,to.z),Color("ffa040"),float(shot.get("splash",95.0))/20,4.0)
			fx.burst("dust",Vector3(to.x,0.1,to.z))
		game.sfx.play("hit",-6.0,0.6)

# 仅覆盖双臂：双腿继续使用走跑/跳跃动画，不增设动画状态机。
# 两段骨骼解析到达枪握把与弹匣；每次先清除覆盖，避免累计旋转。
func reach_hand(skeleton:Skeleton3D,side:String,target_world:Vector3)->void:
	var prefix:="Left" if side=="L" else "Right"
	var upper:int=game.find_bone(skeleton,prefix+"UpperArm","UpperArm."+side)
	var lower:int=game.find_bone(skeleton,prefix+"LowerArm","LowerArm."+side)
	var wrist:int=game.find_bone(skeleton,prefix+"Hand","Wrist."+side)
	if upper<0 or lower<0 or wrist<0:return
	skeleton.force_update_all_bone_transforms()
	var a:=skeleton.get_bone_global_pose(upper)
	var b:=skeleton.get_bone_global_pose(lower)
	var c:=skeleton.get_bone_global_pose(wrist)
	var target:=skeleton.to_local(target_world)
	var first:=a.origin.distance_to(b.origin);var second:=b.origin.distance_to(c.origin)
	var direction:Vector3=(target-a.origin).normalized()
	var distance:=clampf(target.distance_to(a.origin),absf(first-second)+.001,first+second-.001)
	var along:float=(first*first-second*second+distance*distance)/(2*distance)
	var pole:=skeleton.global_basis.inverse()*Vector3(1 if side=="R" else -1,0,.4)
	pole=(pole-direction*pole.dot(direction)).normalized()
	var elbow:=a.origin+direction*along+pole*sqrt(maxf(0,first*first-along*along))
	target=a.origin+direction*distance
	var arm:=a;arm.basis=Basis(Quaternion((b.origin-a.origin).normalized(),(elbow-a.origin).normalized()))*a.basis
	var forearm:=b;forearm.origin=elbow;forearm.basis=Basis(Quaternion((c.origin-b.origin).normalized(),(target-elbow).normalized()))*b.basis
	var hand:=c;hand.origin=target
	skeleton.set_bone_global_pose_override(upper,arm,1.0,true)
	skeleton.set_bone_global_pose_override(lower,forearm,1.0,true)
	skeleton.set_bone_global_pose_override(wrist,hand,1.0,true)
