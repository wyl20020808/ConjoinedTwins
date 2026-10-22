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
# 四把枪均为 Tripo 生成并经 build-tools/journey/process_tripo_weapons.py 规整的模型。
const WEAPON_MODELS := {"smg":"res://assets/weapons/tripo_smg.glb","shotgun":"res://assets/weapons/tripo_shotgun.glb","flamer":"res://assets/weapons/tripo_flamer.glb","launcher":"res://assets/weapons/tripo_launcher.glb"}
const GRENADE_FLIGHT := 0.28
var last_shots := [0,0]
var previous_health := [100,100]
var previous_shield_uses := 0
var flame_on := [false,false]
# 真实枪声录音按武器区分（喷火器另走循环声）。
const SHOT_SOUNDS := {"smg":"smg_shot","shotgun":"shotgun_shot","launcher":"launcher_shot"}
# 背上的第二把枪（每人一组四种枪模型，按类型显示一个）。
var back_guns: Array[Node3D] = []
# 瞄准权重：开火或刚开过火时 0.08 秒抬枪瞄准，停火 0.35 秒后放回抱枪姿势。
var aim_level := [0.0,0.0]
const AIM_IN := 0.08
const AIM_OUT := 0.35
const AIM_HOLD := 0.45
# 姿势按右手握把相对胸口骨骼的位置给出（米，右/上/前；肩膀约在其上方 0.5、左右各 0.28，手臂长约 0.87）：
# 抱枪时右手在右腹前，枪身斜横胸前、枪口朝左上方；瞄准时枪居中贴身、枪口指向目标。
const CARRY_GRIP := Vector3(0.15,-0.05,0.35)
const CARRY_DIRECTION := Vector3(-0.70,0.55,0.45)
const AIM_GRIP := Vector3(0.05,0.30,0.22)
const BACK_OFFSET := Vector3(0.0,0.05,-0.30)
const BACK_DIRECTION := Vector3(-0.50,0.85,0.0)
# 枪模型本地的握持点：右手握把，左手护木（枪口朝 -Z）。
const GRIP_RIGHT := Vector3(0,-0.10,0.12)
const GRIP_LEFT := Vector3(0,-0.06,-0.34)
const RECOIL := {"smg":[0.065,0.12,0.07],"shotgun":[0.16,0.24,0.20],"launcher":[0.2,0.26,0.24],"flamer":[0.05,0.03,0.01]}

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

# 模型里的标记点：Muzzle 枪口、Magazine 弹匣（或燃料罐、装填口）、GripLeft 左手握点、Port 逐发装填口、
# ChargingHandle 拉机柄；带 MagazineMesh 的模型弹匣可拆，换弹时整体拔出再插回。
func make_weapon(parent: Node3D, type: String) -> Node3D:
	if not ResourceLoader.exists(WEAPON_MODELS.get(type,"")):return make_gun(parent)
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
	gun.set_meta("magazine_rest",magazine.position)
	var mag_mesh:Node3D=model.find_child("MagazineMesh",true,false)
	if mag_mesh:
		var placed:Transform3D=mag_mesh.transform
		mag_mesh.get_parent().remove_child(mag_mesh)
		magazine.add_child(mag_mesh)
		mag_mesh.transform=Transform3D(Basis.IDENTITY,-magazine.position)*placed
		gun.set_meta("detachable",true)
	for marker in [["GripLeft","grip_left"],["Port","port"],["ChargingHandle","handle"]]:
		var node:Node3D=model.find_child(marker[0],true,false)
		if node:gun.set_meta(marker[1],node.position)
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
func make_casings(shotgun:bool=false)->GPUParticles3D:
	var process:=ParticleProcessMaterial.new()
	process.direction=Vector3(1,0.8,0.2);process.spread=18.0
	process.initial_velocity_min=2.2;process.initial_velocity_max=3.2
	process.gravity=Vector3(0,-14,0)
	process.angular_velocity_min=-900.0;process.angular_velocity_max=900.0
	var shell:=CylinderMesh.new();shell.top_radius=0.022;shell.bottom_radius=0.022;shell.height=0.07;shell.radial_segments=6;shell.rings=1
	var brass:=StandardMaterial3D.new();brass.albedo_color=Color("c99a3c");brass.metallic=0.9;brass.roughness=0.3
	# 霰弹枪泵动抛出的是红色塑料弹壳，更粗更长。
	if shotgun:
		shell.top_radius=0.03;shell.bottom_radius=0.03;shell.height=0.11
		brass.albedo_color=Color("b8322a");brass.metallic=0.2;brass.roughness=0.45
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
		var back:=Node3D.new()
		add_child(back)
		for type in ["smg","shotgun","flamer","launcher"]:
			var spare:=make_weapon(back,type)
			spare.name=type
			spare.visible=type=="smg"
			var flash:Node3D=spare.get_node_or_null("Flash")
			if flash!=null:flash.visible=false
			var light:Node3D=spare.get_node_or_null("FlashLight")
			if light!=null:light.queue_free()
		back.visible=false
		back_guns.append(back)
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
		shells.append(make_casings(true))
		reload_items.append(make_reload_item())

# 弹药补给：橄榄绿金属弹药箱，翻边箱盖、提手、卡扣和黄色标识带，箱顶立着三发黄铜子弹。
func make_ammo_can(model:Node3D)->void:
	var olive:=pickup_material("ammo_olive",Color("4f5a34"),0.45,0.5)
	var dark:=pickup_material("ammo_dark",Color("2f3622"),0.5,0.45)
	var steel:=pickup_material("ammo_steel",Color("8a8f86"),0.85,0.3)
	var brass:=pickup_material("ammo_brass",Color("d2a24a"),0.9,0.25)
	var copper:=pickup_material("ammo_copper",Color("b5653a"),0.85,0.3)
	var stripe:Material=game.material("ammo_stripe",Color("f2c33d"),0.35)
	game.box(model,Vector3(0,0,0),Vector3(0.86,0.44,0.5),olive)
	game.box(model,Vector3(0,0.25,0),Vector3(0.9,0.07,0.54),dark)
	for x in [-0.38,0.38]:game.box(model,Vector3(x,0,0),Vector3(0.05,0.46,0.52),dark)
	game.box(model,Vector3(0,0.02,0.255),Vector3(0.56,0.08,0.012),stripe)
	game.box(model,Vector3(0,0.02,-0.255),Vector3(0.56,0.08,0.012),stripe)
	for x in [-0.22,0.22]:game.box(model,Vector3(x,0.18,0.27),Vector3(0.08,0.12,0.04),steel)
	for x in [-0.13,0.13]:game.box(model,Vector3(x,0.33,0),Vector3(0.04,0.08,0.05),steel)
	game.box(model,Vector3(0,0.375,0),Vector3(0.32,0.035,0.06),steel)
	for n in range(3):
		var at:=Vector3(0.24+n*0.07-0.07,0.39,-0.13+n*0.03)
		game.cylinder(model,at,0.032,0.2,brass)
		game.cylinder(model,at+Vector3(0,0.13,0),0.026,0.07,copper)

# 医疗补给：白色急救箱，四角深灰护角、红色十字（顶面和两个侧面），顶部提手与金属卡扣。
func make_medkit(model:Node3D)->void:
	var shell:=pickup_material("medkit_shell",Color("eef0ea"),0.05,0.35)
	var trim:=pickup_material("medkit_trim",Color("3b4247"),0.2,0.55)
	var red:Material=game.material("medkit_red",Color("d8423c"),0.45)
	var steel:=pickup_material("ammo_steel",Color("8a8f86"),0.85,0.3)
	game.box(model,Vector3.ZERO,Vector3(0.8,0.42,0.5),shell)
	game.box(model,Vector3(0,0.0,0),Vector3(0.82,0.05,0.52),trim)
	for x in [-0.39,0.39]:
		for z in [-0.24,0.24]:game.box(model,Vector3(x,0,z),Vector3(0.07,0.44,0.07),trim)
	game.box(model,Vector3(0,0.215,0),Vector3(0.42,0.015,0.13),red)
	game.box(model,Vector3(0,0.215,0),Vector3(0.13,0.015,0.36),red)
	for z in [-0.253,0.253]:
		game.box(model,Vector3(0,0.1,z),Vector3(0.26,0.07,0.01),red)
		game.box(model,Vector3(0,0.1,z),Vector3(0.08,0.2,0.01),red)
	for x in [-0.12,0.12]:game.box(model,Vector3(x,0.26,0),Vector3(0.04,0.08,0.05),trim)
	game.box(model,Vector3(0,0.3,0),Vector3(0.3,0.04,0.06),trim)
	for x in [-0.25,0.25]:game.box(model,Vector3(x,-0.06,0.26),Vector3(0.07,0.08,0.03),steel)

func pickup_material(name:String,color:Color,metallic:float,roughness:float)->StandardMaterial3D:
	var mat:StandardMaterial3D=game.material(name,color)
	mat.metallic=metallic;mat.roughness=roughness
	return mat

# 拾取声走二维播放器，任何站位都听得清；音量压低，不盖过枪声。
func pickup_sound(kind:String)->void:
	match kind:
		"medkit":game.sfx.play("heal",-9.0)
		"ammo":
			game.sfx.play("metal_latch",-9.0,1.1)
			game.sfx.play("metal_click",-10.0,0.85)
		"gun":
			game.sfx.play("metal_click",-8.0,0.9)
			game.sfx.play("metal_latch",-11.0,1.2)

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
	flame_on=[false,false]
	heat=[0.0,0.0]
	motion_seen=[-INF,-INF]
	reload_clock=[-1.0,-1.0]
	reload_ended=[-INF,-INF]
	reload_from_empty=[false,false]
	previous_health=game.run.combat.health.duplicate()
	previous_shield_uses=game.run.shield_uses

func sync() -> void:
	var run=game.run
	var visual_state:String=run.paused_from if run.state=="paused" else run.state
	# 一次建立可见拾取集合，同时清理已领取和离开窗口的节点。
	var nearby:={}
	for pickup in run.combat.pickups:
		if game.view_gap(pickup.position.y)<3000:nearby[pickup.id]=pickup
	for id in pickup_views.keys():
		if not nearby.has(id):
			var collected:Node3D=pickup_views[id]
			var fx=game.get("fx")
			if fx!=null and is_instance_valid(collected) and collected.visible and collected.global_position.distance_to(game.robots[0].global_position)<60.0:
				fx.burst("spark",collected.global_position+Vector3(0,0.4,0))
				if game.get("coop_fx")!=null:game.coop_fx.pickup(collected.global_position)
				pickup_sound(str(collected.get_meta("kind","")))
			collected.queue_free()
			pickup_views.erase(id)
	for pickup in nearby.values():
		if not pickup_views.has(pickup.id):
			var view := Node3D.new()
			add_child(view)
			pickup_views[pickup.id]=view
			view.set_meta("kind",pickup.kind)
			if pickup.kind=="gun":
				var gun := make_weapon(view,pickup.get("weapon_type","smg"))
				gun.rotation.z=PI/2
				gun.scale=Vector3.ONE*1.3
			else:
				var model:=Node3D.new();model.name="Model";view.add_child(model)
				if pickup.kind=="ammo":make_ammo_can(model)
				else:make_medkit(model)
			game.cylinder(view,Vector3(0,-0.4,0),0.75,0.04,game.material("pickup_ring",Color("62c7ba"),0.6))
			# 竖直光柱：远处也能一眼看到拾取物，颜色按种类区分。
			var pillar:MeshInstance3D=game.cylinder(view,Vector3(0,2.6,0),0.26,6.0,pillar_material(pickup.kind))
			pillar.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var tube:CylinderMesh=pillar.mesh;tube.cap_top=false;tube.cap_bottom=false;tube.radial_segments=12
			var gun_name:String=run.Combat.WEAPONS[pickup.get("weapon_type","smg")].name
			game.add_sign(view,{"gun":gun_name,"ammo":"弹药补给","medkit":"医疗 +30"}[pickup.kind],Vector3(0,1.2,0),22)
		var view: Node3D=pickup_views[pickup.id]
		view.position=Vector3(pickup.position.x/20,0.65+sin(run.elapsed*2)*0.08,-pickup.position.y/20)
		var spin:Node3D=view.get_node_or_null("Model")
		if spin!=null:spin.rotation.y=run.elapsed*0.9+float(pickup.id)
		view.visible=game.view_gap(pickup.position.y)<3000
		for child in view.get_children():
			if child is Label3D:child.visible=visual_state not in ["rescue","failed"]
	# 丢出去还在空中的枪：对应的地面拾取物等落地后再显示。
	var tossing:={}
	for role in range(2):
		var motion:Dictionary=run.combat.get("motion",[{},{}])[role]
		if motion.get("kind","")=="drop" and run.elapsed-float(motion.time)<TOSS_TIME:tossing[int(motion.pickup)]=true
	for id in pickup_views:
		if tossing.has(id):pickup_views[id].visible=false
	for role in range(2):
		game.robots[role].get_node("CombatShield").visible=run.shield
		var weapon: Dictionary=run.combat.weapons[role]
		var showing:bool=visual_state not in ["rescue","failed","complete","settlement"]
		var running:bool=visual_state=="running"
		var type:String=weapon.get("type","smg")
		# 与既有角色右手骨骼同步，枪身朝向模拟选中的目标。
		var known:Skeleton3D=game.hand_skeletons.get(role)
		if is_instance_valid(known):known.clear_bones_global_pose_override()
		var hand: Vector3=game.hand_point(role)
		var skeleton: Skeleton3D=game.hand_skeletons.get(role)
		var rest_left:=Vector3.INF
		if is_instance_valid(skeleton):
			var wrist:int=game.find_bone(skeleton,"RightHand","Wrist.R")
			if wrist>=0: hand=skeleton.global_transform*game.final_bone_pose(skeleton,wrist).origin
			var left_wrist:int=game.find_bone(skeleton,"LeftHand","Wrist.L")
			if left_wrist>=0: rest_left=skeleton.global_transform*game.final_bone_pose(skeleton,left_wrist).origin
		var target := hand+Vector3(0,0,-5)
		var has_target:=false
		if not weapon.is_empty():
			for event in run.journey_events:
				if event.id==weapon.target:
					var point: Vector2=run.Combat.enemy_position(event)
					target=Vector3(point.x/20,run.Combat.enemy_height(event)/20,-point.y/20)
					has_target=true
		var shot: Dictionary=run.combat.shots[role]
		var anchor:=chest_anchor(role,skeleton)
		var hold:=Transform3D(Basis.IDENTITY,hand)
		if anchor.has("origin"):
			var shooting:bool=run.combat.fire[role] or (not shot.is_empty() and run.elapsed-float(shot.time)<AIM_HOLD)
			var rate:float=1.0/(AIM_IN if shooting else AIM_OUT)
			if running: aim_level[role]=move_toward(aim_level[role],1.0 if shooting else 0.0,game.frame_delta*rate)
			hold=gun_pose(anchor,aim_level[role],target if has_target or shooting else Vector3.INF)
		elif hand.distance_to(target)>0.01: hold=Transform3D(Basis.looking_at(target-hand,Vector3.UP),hand)
		# 收枪上背、从背上取枪、捡枪、丢枪：按模拟记录的开始时间播放，优先于换弹与后坐。
		var act:=motion_state(role,anchor,hold)
		motion_sounds(role,act)
		if act.is_empty():act=reload_state(role,weapon,anchor,hold)
		else:reload_clock[role]=-1.0
		var held:String=act.get("held",type if not weapon.is_empty() else "")
		guns[role].visible=held!="" and showing
		for variant in guns[role].get_children():variant.visible=variant.name==held
		var model:Node3D=guns[role].get_node(held if held!="" else "smg")
		guns[role].global_transform=act.get("transform",hold)
		apply_items(role,model,act)
		sync_back_gun(role,anchor,showing,act)
		var shot_type:String=shot.get("type","smg")
		var recent: bool=not shot.is_empty() and run.elapsed-shot.time<0.065 and running
		# 喷火器连发间隔 0.05 秒，火舌在扳机松开后 0.12 秒内熄灭。
		flames[role].emitting=not shot.is_empty() and shot_type=="flamer" and run.elapsed-shot.time<0.12 and running and guns[role].visible
		if flames[role].emitting:flames[role].global_transform=model.get_node("Flash").global_transform
		# 喷火：点火瞬间一声起燃，按住扳机期间持续火焰与噼啪声，松开即停。
		if flames[role].emitting and not flame_on[role]:game.sfx.play_at("flame_start",guns[role].global_position,-8.0)
		# 暂停时火舌画面保持，声音停下。
		flame_on[role]=flames[role].emitting and run.state=="running"
		game.sfx.loop_at("flamer:%d"%role,"flame_loop",flame_on[role],guns[role].global_position,-12.0)
		game.sfx.loop_at("flamer_crackle:%d"%role,"fire_crackle_loop",flame_on[role],guns[role].global_position,-16.0)
		sync_grenade(role,shot,visual_state)
		model.get_node("Flash").visible=recent and shot_type!="flamer"
		var flash_light:OmniLight3D=model.get_node_or_null("FlashLight")
		if flash_light!=null:flash_light.visible=recent or flames[role].emitting
		beams[role].visible=recent and shot_type in ["smg","shotgun"]
		for n in range(1,pellet_beams[role].size()):pellet_beams[role][n].visible=false
		var new_shot:bool=not shot.is_empty() and shot.id!=last_shots[role]
		# 连射热度：每发累积，停火回落；冲锋枪越打枪口越往上走，霰弹枪和榴弹单发就顶得很高。
		if new_shot and running:
			heat[role]=minf(1.0,heat[role]+float(HEAT.get(shot_type,0.0)))
			jitter[role]=randf_range(-1.0,1.0)
		if running:heat[role]=move_toward(heat[role],0.0,game.frame_delta*HEAT_FALL)
		# 后坐按枪种区分：[时长, 后移, 上扬]，时长可长于枪口焰；双手随后由 IK 跟着枪一起后坐。
		var kick:Array=RECOIL.get(shot_type,RECOIL.smg)
		var steady:bool=act.is_empty()
		if steady and not shot.is_empty() and visual_state=="running" and run.elapsed-float(shot.time)<kick[0]:
			var recoil:float=1.0-clampf((run.elapsed-float(shot.time))/kick[0],0,1)
			recoil*=recoil
			guns[role].position+=guns[role].basis.z*kick[1]*recoil
			guns[role].rotate_object_local(Vector3.RIGHT,kick[2]*recoil)
			guns[role].rotate_object_local(Vector3.UP,kick[2]*0.35*jitter[role]*recoil)
		if steady and heat[role]>0.001:
			guns[role].position+=guns[role].basis.z*0.05*heat[role]
			guns[role].rotate_object_local(Vector3.RIGHT,0.16*heat[role])
		# 霰弹枪每发之后、以及空仓装填完毕后拉一次泵：左手后拉再推回，此时抛出红色弹壳。
		var pump:=pump_stroke(role,weapon,shot,steady)
		if pump>0.0:
			guns[role].position+=guns[role].basis.z*0.02*pump
			act={"clip":"GunPump","clip_time":float(shells[role].get_meta("pump",0.0)),"weight":1.0}
		# 主角上半身动作层：动作期间按片段时间覆盖脊柱、头和肩。
		var rig=game.hero_rigs[role] if role<game.hero_rigs.size() else null
		if rig!=null and is_instance_valid(rig):
			rig.action_clip=act.get("clip","")
			rig.action_time=act.get("clip_time",0.0)
			rig.action_weight=act.get("weight",0.0) if showing else 0.0
		if recent:
			var from := Vector3(shot.from.x/20,shot.height/20,-shot.from.y/20)
			var to := Vector3(shot.to.x/20,shot.target_height/20,-shot.to.y/20)
			place_beam(beams[role],from,to)
			if shot_type=="shotgun":
				var ends:Array=shot.get("pellets",[])
				for n in range(mini(ends.size(),pellet_beams[role].size())):
					var end:Vector2=ends[n]
					place_beam(pellet_beams[role][n],from,Vector3(end.x/20,shot.height/20,-end.y/20))
					pellet_beams[role][n].visible=true
			if new_shot:
				if shot_type!="flamer":game.sfx.play(SHOT_SOUNDS.get(shot_type,"smg_shot"),{"smg":-14.0,"shotgun":-9.0,"launcher":-10.0}.get(shot_type,-14.0))
				# 机械层：冲锋枪枪机撞击的短促金属声，叠在枪声下面增加“咔哒”的实感。
				if shot_type=="smg":game.sfx.play_at("metal_click",guns[role].global_position,-20.0,randf_range(1.8,2.1))
				var flash_node:Node3D=model.get_node("Flash")
				var size:Array=FLASH_SIZE.get(shot_type,[0.8,1.25])
				flash_node.rotation.z=randf()*TAU
				flash_node.scale=Vector3.ONE*randf_range(size[0],size[1])
				if shot_type=="smg":eject(casings[role],model)
		if new_shot or shot.is_empty(): last_shots[role]=int(shot.get("id",0))
		if casings[role].emitting and run.elapsed>float(casings[role].get_meta("until",0.0)):casings[role].emitting=false
		if shells[role].emitting and run.elapsed>float(shells[role].get_meta("until",0.0)):shells[role].emitting=false
		dry_fire(role,weapon,running)
		# 双手握枪：枪的位置（含后坐、换弹、收取枪动作）确定后，再把双手送到握持点。
		if guns[role].visible and is_instance_valid(skeleton) and anchor.has("origin"):
			var grip_left:Vector3=model.to_global(grip_left_of(model)+Vector3(0,0,0.14*pump))
			if not act.get("right_free",false):reach_hand(skeleton,"R",act.get("right",guns[role].to_global(GRIP_RIGHT)))
			var left:Vector3=grip_left
			var weight:float=act.get("left",1.0)
			var loose:Vector3=act.get("left_reach",rest_left)
			if weight<0.999 and loose!=Vector3.INF:left=loose.lerp(left,smoothstep(0.0,1.0,weight))
			if weight>0.001 or loose!=rest_left:reach_hand(skeleton,"L",left)
		elif act.has("right") and is_instance_valid(skeleton) and anchor.has("origin"):
			# 空手伸向背后或地面（取枪、捡枪的前半段）。
			reach_hand(skeleton,"R",act.right)
		if run.combat.health[role]<previous_health[role]: game.sfx.play_at("punch_heavy",game.robots[role].global_position+Vector3(0,1.5,0),-2.0,0.95)
		previous_health[role]=run.combat.health[role]
	if run.shield_uses>previous_shield_uses: game.sfx.play("shield_break",-6.0)
	previous_shield_uses=run.shield_uses
	for event in run.journey_events:
		if event.has("hp") and event.kind!="boss" and game.event_views.has(event.id):
			EnemyView.sync(game,game.event_views[event.id],event)

# 胸口骨骼的世界位置（随跑步起伏）与身体朝向；找不到骨骼时返回空字典，沿用跟随右手的旧摆法。
func chest_anchor(role:int,skeleton:Skeleton3D)->Dictionary:
	if not is_instance_valid(skeleton):return {}
	var chest:int=game.find_bone(skeleton,"UpperChest","Chest")
	if chest<0:chest=game.find_bone(skeleton,"Chest","Spine")
	if chest<0:return {}
	var body:Basis=game.robots[role].global_basis.orthonormalized()
	return {"origin":skeleton.global_transform*skeleton.get_bone_global_pose(chest).origin,
		"right":body.x,"up":Vector3.UP,"forward":-body.z}

func offset(anchor:Dictionary,local:Vector3)->Vector3:
	return anchor.origin+anchor.right*local.x+anchor.up*local.y+anchor.forward*local.z

# 抱枪与瞄准之间按 aim 混合：握点位置线性插值，朝向球面插值；没有目标时瞄准方向取正前方。
# 枪的原点由右手握点反推，保证右手始终落在握把上。
func gun_pose(anchor:Dictionary,aim:float,target:Vector3)->Transform3D:
	var carry_grip:=offset(anchor,CARRY_GRIP)
	var carry_dir:Vector3=(anchor.right*CARRY_DIRECTION.x+anchor.up*CARRY_DIRECTION.y+anchor.forward*CARRY_DIRECTION.z).normalized()
	# 横抱时枪身上面朝外（身体前方）。
	var carry:=Basis.looking_at(carry_dir,anchor.forward)
	var aim_grip:=offset(anchor,AIM_GRIP)
	var aim_dir:Vector3=anchor.forward
	if target!=Vector3.INF and target.distance_to(aim_grip)>0.5:aim_dir=(target-aim_grip).normalized()
	var aimed:=Basis.looking_at(aim_dir,Vector3.UP)
	var weight:=smoothstep(0.0,1.0,aim)
	var basis:=Basis(carry.get_rotation_quaternion().slerp(aimed.get_rotation_quaternion(),weight))
	return Transform3D(basis,carry_grip.lerp(aim_grip,weight)-basis*GRIP_RIGHT)

# 背上的第二把枪：斜挎在背后，枪口朝左肩上方，贴着背部；收取枪动作期间按动作显示的枪种和位置。
func sync_back_gun(role:int,anchor:Dictionary,showing:bool,act:Dictionary)->void:
	var spare:Dictionary=game.run.Combat.backup(game.run,role) if not game.run.combat.is_empty() else {}
	var type:String=act.get("back",spare.get("type","") if not spare.is_empty() else "")
	var holder:=back_guns[role]
	holder.visible=type!="" and anchor.has("origin") and showing
	if not holder.visible:return
	for variant in holder.get_children():variant.visible=variant.name==type
	holder.global_transform=act.get("back_transform",back_pose(anchor))

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
		game.sfx.play_at("explosion",Vector3(to.x,0.5,to.z),-3.0)

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

# ---- 收枪、取枪、捡枪、丢枪、换弹：Blender 动作片段 ----
# 动作在 tools/blender/make_gun_anims.py 里按关键帧制作：主角上半身片段（脊柱、头、肩）由 hero_locomotion 的动作层混合，
# 枪身轨迹与双手目标写在 gun_action_curves.gd，这里按模拟时间采样并换算到胸口锚点，双手再用 IK 精确贴到枪上。
# 时长与模拟的冷却步数一致（120 Hz）：换枪 0.55 秒（前 0.25 秒收枪上背，后 0.3 秒从背上取枪）；
# 捡起拿到手上 0.35 秒；捡起背到背上 0.45 秒；丢枪 0.3 秒抛到地上，背上有枪时再用 0.3 秒取下来。
const Curves=preload("res://scripts/gun_action_curves.gd")
const HOLSTER_TIME := 0.25
const SWAP_TIME := 0.55
const PICKUP_TIME := 0.35
const STOW_TIME := 0.45
const TOSS_TIME := 0.3
const DROP_TIME := 0.6
# 丢枪片段在 0.35 处松手，之后枪沿抛物线落到地上的拾取点。
const TOSS_RELEASE := 0.35
# 逐发装填结束后收回护木的时长。
const SHELL_END_TIME := 0.15
const HEAT := {"smg":0.2,"shotgun":0.85,"launcher":0.9,"flamer":0.0}
const HEAT_FALL := 2.6
const FLASH_SIZE := {"smg":[0.75,1.1],"shotgun":[1.35,1.75],"launcher":[1.1,1.35]}
var heat := [0.0,0.0]
var jitter := [0.0,0.0]
var motion_clock := [-1.0,-1.0]
var motion_seen := [-INF,-INF]
var reload_clock := [-1.0,-1.0]
var reload_ended := [-INF,-INF]
var reload_from_empty := [false,false]
var dry_clicked := [-INF,-INF]
var arm_scales := [0.0,0.0]
var shells: Array[GPUParticles3D] = []
var reload_items: Array[MeshInstance3D] = []

func back_pose(anchor:Dictionary)->Transform3D:
	var direction:Vector3=(anchor.right*BACK_DIRECTION.x+anchor.up*BACK_DIRECTION.y).normalized()
	return Transform3D(Basis.looking_at(direction,-anchor.forward),offset(anchor,BACK_OFFSET))

# 地上的枪与拾取物同样侧放、放大 1.3 倍。
func ground_pose(at:Vector2,sink:float=0.0)->Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0,0,PI/2)).scaled(Vector3.ONE*1.3),Vector3(at.x/20,0.65-sink,-at.y/20))

# 经过中间点的平滑路径：位置走二次贝塞尔，朝向分两段球面插值，缩放线性过渡。
func carry_path(a:Transform3D,middle:Transform3D,b:Transform3D,u:float)->Transform3D:
	var e:=clampf(u,0.0,1.0)
	var position:Vector3=a.origin*(1-e)*(1-e)+middle.origin*2*(1-e)*e+b.origin*e*e
	var qa:=a.basis.get_rotation_quaternion();var qm:=middle.basis.get_rotation_quaternion();var qb:=b.basis.get_rotation_quaternion()
	var rotation:Quaternion=qa.slerp(qm,e*2) if e<0.5 else qm.slerp(qb,e*2-1)
	var size:Vector3=a.basis.get_scale().lerp(b.basis.get_scale(),e)
	return Transform3D(Basis(rotation).scaled(size),position)

func blend(a:Transform3D,b:Transform3D,u:float)->Transform3D:
	return a.interpolate_with(b,smoothstep(0.0,1.0,clampf(u,0.0,1.0)))

# 片段曲线以 Adventurer 骨架手臂长为基准；按主角实际手臂长度等比换算位置。
func arm_scale(role:int)->float:
	if arm_scales[role]>0.0:return arm_scales[role]
	var skeleton:Skeleton3D=game.hand_skeletons.get(role)
	if not is_instance_valid(skeleton):return 1.0
	var chain:=[game.find_bone(skeleton,"RightUpperArm","UpperArm.R"),game.find_bone(skeleton,"RightLowerArm","LowerArm.R"),game.find_bone(skeleton,"RightHand","Wrist.R")]
	if chain.has(-1):return 1.0
	var total:=0.0
	for n in range(2):
		total+=(skeleton.global_basis*(skeleton.get_bone_global_rest(chain[n+1]).origin-skeleton.get_bone_global_rest(chain[n]).origin)).length()
	arm_scales[role]=total/Curves.ARM
	return arm_scales[role]

func curve_point(anchor:Dictionary,frame:Basis,scale:float,data:Array,a:int,b:int,w:float,at:int)->Vector3:
	var p:=Vector3(data[a+at],data[a+at+1],data[a+at+2]).lerp(Vector3(data[b+at],data[b+at+1],data[b+at+2]),w)
	return anchor.origin+frame*(p*scale)

func curve_basis(frame:Basis,data:Array,a:int,b:int,w:float,at:int)->Basis:
	var q:=Quaternion(data[a+at],data[a+at+1],data[a+at+2],data[a+at+3]).slerp(Quaternion(data[b+at],data[b+at+1],data[b+at+2],data[b+at+3]),w)
	return frame*Basis(q)

# 采样片段：返回世界坐标的枪、背枪、双手目标（rw/lw 为手在握把/护木上的权重）与道具状态。
func sample(role:int,anchor:Dictionary,clip:String,u:float)->Dictionary:
	var entry:Dictionary=Curves.CLIPS[clip]
	var data:Array=entry.data
	var last:int=int(entry.frames)-1
	var f:=clampf(u,0.0,1.0)*last
	var i:=int(f)
	var a:=i*Curves.STRIDE;var b:=mini(i+1,last)*Curves.STRIDE;var w:=f-i
	var frame:=Basis(anchor.right,anchor.up,-anchor.forward)
	var scale:=arm_scale(role)
	return {"clip":clip,"time":clampf(u,0.0,1.0)*float(entry.length),
		"gun":Transform3D(curve_basis(frame,data,a,b,w,3),curve_point(anchor,frame,scale,data,a,b,w,0)),
		"right":curve_point(anchor,frame,scale,data,a,b,w,7),"rw":lerpf(data[a+10],data[b+10],w),
		"left":curve_point(anchor,frame,scale,data,a,b,w,11),"lw":lerpf(data[a+14],data[b+14],w),"item":data[a+15],
		"back":Transform3D(curve_basis(frame,data,a,b,w,19),curve_point(anchor,frame,scale,data,a,b,w,16))}

# 把采样结果整理成画面动作：held=手上显示的枪种，transform=手上枪的姿势，right=右手目标（不在握把上时），
# left=左手回到护木的权重，left_reach=左手空出来时的位置，clip/clip_time/weight 交给主角上半身动作层。
func act_from(s:Dictionary,held:String,gun:Transform3D,weight:float,t:float)->Dictionary:
	var act:={"held":held,"transform":gun,"left":s.lw,"left_reach":s.left,"clip":"Gun"+String(s.clip),"clip_time":s.time,"weight":weight,"t":t}
	if s.rw<0.5:act.right=s.right
	return act

func motion_state(role:int,anchor:Dictionary,hold:Transform3D)->Dictionary:
	var run=game.run
	var motion:Dictionary=run.combat.get("motion",[{},{}])[role]
	if motion.is_empty() or not anchor.has("origin"):return {}
	var t:float=run.elapsed-float(motion.time)
	if t<0.0:return {}
	var from:String=motion.from
	var to:String=motion.to
	match motion.kind:
		"swap":
			if t>=SWAP_TIME:return {}
			if t<HOLSTER_TIME:
				var u:=t/HOLSTER_TIME
				var s:=sample(role,anchor,"Holster",u)
				var act:=act_from(s,from,blend(hold,s.gun,u/0.3),smoothstep(0.0,0.2,u),t)
				act.back=to
				if from=="":act.right=s.gun*GRIP_RIGHT
				return act
			return draw_state(role,anchor,hold,(t-HOLSTER_TIME)/(SWAP_TIME-HOLSTER_TIME),to,from,t)
		"pickup":
			if t>=PICKUP_TIME:return {}
			var u:=t/PICKUP_TIME
			var s:=sample(role,anchor,"Pickup",u)
			# 前段枪从地上飞进伸低的右手，后段随片段抬到持枪位置。
			var gun:=blend(ground_pose(motion.at),s.gun,u/0.35) if u<0.35 else blend(s.gun,hold,(u-0.7)/0.3)
			var act:=act_from(s,to,gun,smoothstep(0.0,0.15,u)*(1.0-smoothstep(0.8,1.0,u)),t)
			if u<0.35:act.right=s.gun*GRIP_RIGHT
			return act
		"stow":
			if t>=STOW_TIME:return {}
			var u:=t/STOW_TIME
			var s:=sample(role,anchor,"Stow",u)
			var back:Transform3D=blend(ground_pose(motion.at),s.back,u/0.3) if u<0.3 else s.back
			return {"back":to,"back_transform":back,"left":s.lw,"left_reach":s.left,"clip":"GunStow","clip_time":s.time,
				"weight":smoothstep(0.0,0.15,u)*(1.0-smoothstep(0.85,1.0,u)),"t":t}
		"drop":
			if t<TOSS_TIME:
				var u:=t/TOSS_TIME
				var s:=sample(role,anchor,"Toss",u)
				var gun:=blend(hold,s.gun,u/0.3)
				if u>=TOSS_RELEASE:
					# 松手后沿抛物线落到拾取点；掉进缺口时继续往下落。
					var release:Transform3D=sample(role,anchor,"Toss",TOSS_RELEASE).gun
					var land:=ground_pose(motion.at,0.0 if int(motion.pickup)>=0 else 3.0)
					var middle:=Transform3D(release.basis.rotated(anchor.forward,-1.4),release.origin.lerp(land.origin,0.5)+Vector3.UP*0.6)
					gun=carry_path(release,middle,land,pow((u-TOSS_RELEASE)/(1.0-TOSS_RELEASE),1.4))
				var act:=act_from(s,from,gun,smoothstep(0.0,0.2,u)*(1.0-smoothstep(0.8,1.0,u)) if to=="" else smoothstep(0.0,0.2,u),t)
				act.back=to
				return act
			if to=="":return {} if t>=TOSS_TIME+0.05 else {"held":"","t":t}
			if t>=DROP_TIME:return {}
			return draw_state(role,anchor,hold,(t-TOSS_TIME)/(DROP_TIME-TOSS_TIME),to,"",t)
	return {}

# 从背上取枪：右手先伸到背后握住，再越过右肩拉到身前；最后 30% 并入当前持枪姿势。
func draw_state(role:int,anchor:Dictionary,hold:Transform3D,u:float,held:String,back:String,t:float)->Dictionary:
	var s:=sample(role,anchor,"Draw",u)
	var act:=act_from(s,held,blend(s.gun,hold,(u-0.7)/0.3),1.0-smoothstep(0.8,1.0,u),t)
	act.back=back
	return act

# 动作音效按模拟时间越过关键帧时播放：收枪甩动、枪身贴背的闷响、取枪到位的上膛声、丢枪落地的金属撞击。
func motion_sounds(role:int,act:Dictionary)->void:
	var motion:Dictionary=game.run.combat.get("motion",[{},{}])[role]
	if motion.is_empty() or act.is_empty() or game.run.state!="running":return
	var start:float=float(motion.time)
	if start!=motion_seen[role]:
		motion_seen[role]=start
		motion_clock[role]=-0.001
	var before:float=motion_clock[role]
	var now:float=act.get("t",0.0)
	motion_clock[role]=now
	var at:Vector3=guns[role].global_position
	var marks:Array=[]
	match motion.kind:
		"swap":marks=[[0.0,"whoosh",-22.0,1.6],[HOLSTER_TIME-0.02,"land_soft",-15.0,1.7],[HOLSTER_TIME+0.04,"metal_light",-20.0,1.4],[SWAP_TIME-0.07,"metal_latch",-11.0,1.15]]
		"pickup":marks=[[0.1,"whoosh",-24.0,1.8],[PICKUP_TIME-0.06,"metal_latch",-12.0,1.2]]
		"stow":marks=[[0.12,"whoosh",-22.0,1.5],[STOW_TIME-0.06,"land_soft",-15.0,1.7]]
		"drop":
			marks=[[0.05,"whoosh",-22.0,1.3]]
			if int(motion.pickup)>=0:marks.append([TOSS_TIME-0.01,"metal_heavy",-13.0,1.15])
			if motion.to!="":marks.append_array([[TOSS_TIME+0.06,"metal_light",-20.0,1.4],[DROP_TIME-0.07,"metal_latch",-11.0,1.15]])
	for mark in marks:
		if before<float(mark[0]) and now>=float(mark[0]):game.sfx.play_at(mark[1],at,mark[2],mark[3])

# ---- 换弹 ----
# 无 Tween、无墙钟时间：暂停、联机、重试和丢枪都直接服从武器剩余帧数。
# 冲锋枪：侧倾枪身，左手拔出空弹匣丢掉，从左腰弹袋取新弹匣插入，再拉机柄（ReloadMag）。
# 霰弹枪、榴弹发射器：起手把枪侧倾，左手一发一发从弹袋取弹压入，结束后收回护木（Shell*/Grenade*）。
# 喷火器：左手握住燃料罐拧下换上（ReloadTank）。
func reload_state(role:int,weapon:Dictionary,anchor:Dictionary,hold:Transform3D)->Dictionary:
	var run=game.run
	if weapon.is_empty() or not anchor.has("origin"):
		reload_clock[role]=-1.0
		return {}
	var remaining:int=int(weapon.get("reload",0))
	var type:String=weapon.get("type","smg")
	var data:Dictionary=run.Combat.spec(weapon)
	var shell:bool=data.get("per_shell",false)
	var prefix:="Shell" if type=="shotgun" else "Grenade"
	if remaining==0:
		if reload_clock[role]>=0.0:
			reload_ended[role]=run.elapsed
			reload_clock[role]=-1.0
		var since:float=run.elapsed-reload_ended[role]
		if not shell or since<0.0 or since>=SHELL_END_TIME:return {}
		var u:=since/SHELL_END_TIME
		var s:=sample(role,anchor,prefix+"End",u)
		return act_from(s,type,blend(s.gun,hold,u),1.0-smoothstep(0.4,1.0,u),since)
	var total:int=int(weapon.get("reload_total",data.reload))
	var t:float=1.0-float(remaining)/maxf(1,total)
	if reload_clock[role]<0.0:reload_from_empty[role]=int(weapon.ammo)==0
	var previous:float=reload_clock[role]
	if shell:
		var per:int=int(data.reload)
		var start:int=total-per
		var done:int=total-remaining
		if done<start:
			reload_clock[role]=0.0
			var u:=float(done)/float(start)
			var s:=sample(role,anchor,prefix+"Start",u)
			return act_from(s,type,blend(hold,s.gun,u/0.4),smoothstep(0.0,0.4,u),t)
		var c:=float(done-start)/float(per)
		reload_clock[role]=c
		var s:=sample(role,anchor,prefix+"Load",c)
		var before:float=-1.0 if previous<0.0 or previous>c else previous
		if run.state=="running" and before<0.68 and c>=0.68:
			if type=="shotgun":game.sfx.play_at("metal_click",guns[role].global_position,-9.0,randf_range(1.4,1.55))
			else:game.sfx.play_at("metal_latch",guns[role].global_position,-10.0,0.8)
		var act:=act_from(s,type,s.gun,1.0,t)
		act.item="shell" if type=="shotgun" else "grenade"
		act.item_state=s.item
		return act
	reload_clock[role]=t
	var clip:="ReloadTank" if type=="flamer" else "ReloadMag"
	var s:=sample(role,anchor,clip,t)
	var edge:=smoothstep(0.0,0.1,t)*(1.0-smoothstep(0.9,1.0,t))
	var act:=act_from(s,type,blend(hold,s.gun,edge),edge,t)
	act.item="magazine"
	act.item_state=s.item
	# 拔出的旧弹匣在 0.4 处松手下落。
	if s.item>=1.5 and s.item<2.5:
		act.fall_from=sample(role,anchor,clip,0.4).left
		act.fall=(t-0.4)*total/120.0
	var marks:Array
	if type=="flamer":marks=[[0.3,"metal_latch",-10.0,0.75],[0.42,"steam_hiss",-20.0,1.3],[0.8,"metal_latch",-8.0,0.9],[0.9,"metal_click",-6.0,0.8]]
	else:marks=[[0.22,"metal_latch",-10.0,1.3],[0.47,"metal_light",-20.0,1.2],[0.76,"metal_latch",-7.0,0.9],[0.87,"metal_click",-5.0,1.0]]
	reload_marks(guns[role],marks,previous,t)
	return act

# 弹匣与手里的子弹、榴弹：弹匣可拆的枪在换弹时随左手拔出、丢下、从弹袋取出再插回。
func apply_items(role:int,model:Node3D,act:Dictionary)->void:
	var item:=reload_items[role]
	item.visible=false
	var magazine:Node3D=model.get_node_or_null("Magazine")
	var detachable:bool=model.has_node("MagazineLip") or model.get_meta("detachable",false)
	var rest:Vector3=model.get_meta("magazine_rest",Vector3(0,-0.22,-0.37))
	if magazine!=null and detachable:
		magazine.position=rest;magazine.rotation=Vector3.ZERO;magazine.visible=true
	if model.has_node("MagazineLip"):
		model.get_node("MagazineLip").position=rest+Vector3(0,-0.19,0)
		model.get_node("MagazineLip").visible=true
	var state:float=act.get("item_state",0.0)
	match act.get("item",""):
		"magazine":
			if magazine==null or not detachable:return
			if state>=0.5 and state<1.5:magazine.global_position=act.left_reach
			elif state>=1.5 and state<2.5:
				var fall:float=act.get("fall",0.0)
				magazine.global_position=act.fall_from-Vector3.UP*4.9*fall*fall
				magazine.rotation.x=fall*8.0
			elif state>=2.5:magazine.visible=false
			if state>=0.5 and state<2.5:magazine.rotation.z=-0.3
			if model.has_node("MagazineLip"):
				model.get_node("MagazineLip").position=magazine.position+Vector3(0,-0.19,0)
				model.get_node("MagazineLip").visible=magazine.visible
		"shell","grenade":
			show_item(role,act.item,act.left_reach,guns[role].global_basis,state>=0.5)

func grip_left_of(model:Node3D)->Vector3:
	return model.get_meta("grip_left",GRIP_LEFT)

func reload_marks(gun:Node3D,marks:Array,previous:float,t:float)->void:
	if game.run.state!="running":return
	var before:float=-1.0 if previous<0.0 or previous>t else previous
	for mark in marks:
		if before<float(mark[0]) and t>=float(mark[0]):game.sfx.play_at(mark[1],gun.global_position,mark[2],mark[3])

# 左手里拿着的子弹或榴弹。
func show_item(role:int,kind:String,at:Vector3,basis:Basis,visible:bool)->void:
	var item:=reload_items[role]
	item.visible=visible
	if not visible:return
	item.mesh=item.get_meta(kind)
	item.global_transform=Transform3D(basis.orthonormalized()*Basis(Vector3.RIGHT,PI/2),at)

func make_reload_item()->MeshInstance3D:
	var item:=MeshInstance3D.new()
	var shell:=CylinderMesh.new();shell.top_radius=0.03;shell.bottom_radius=0.03;shell.height=0.11;shell.radial_segments=8;shell.rings=1
	shell.material=pickup_material("shell_red",Color("b8322a"),0.2,0.45)
	var round:=CylinderMesh.new();round.top_radius=0.035;round.bottom_radius=0.05;round.height=0.12;round.radial_segments=8;round.rings=1
	round.material=pickup_material("grenade_round",Color("6b7a3a"),0.5,0.4)
	item.set_meta("shell",shell);item.set_meta("grenade",round)
	item.mesh=shell
	item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.visible=false
	add_child(item)
	return item

# 霰弹枪泵动：开火后 0.14–0.42 秒，或空仓装填完毕后 0.05–0.33 秒；返回 0..1 的行程。
func pump_stroke(role:int,weapon:Dictionary,shot:Dictionary,steady:bool)->float:
	if weapon.get("type","")!="shotgun" or not steady:return 0.0
	var run=game.run
	var since:=INF
	if not shot.is_empty() and shot.get("type","")=="shotgun":since=run.elapsed-float(shot.time)-0.14
	var after:float=run.elapsed-reload_ended[role]-0.05
	if reload_from_empty[role] and after>=0.0 and after<since:since=after
	if since<0.0 or since>=0.28:return 0.0
	var stroke:=sin(since/0.28*PI)
	var previous:float=float(shells[role].get_meta("pump",-1.0))
	if game.run.state=="running":
		var before:float=-1.0 if previous>since else previous
		if before<0.05 and since>=0.05:game.sfx.play_at("metal_latch",guns[role].global_position,-9.0,1.35)
		if before<0.12 and since>=0.12:eject(shells[role],guns[role].get_node("shotgun"))
		if before<0.2 and since>=0.2:game.sfx.play_at("metal_click",guns[role].global_position,-8.0,1.1)
	shells[role].set_meta("pump",since)
	return stroke

func eject(particles:GPUParticles3D,model:Node3D)->void:
	particles.global_transform=model.global_transform
	particles.emitting=true
	particles.amount_ratio=1.0
	particles.set_meta("until",game.run.elapsed+0.05)

# 弹匣和备弹都打光后扣扳机：空膛击发的“咔”声，0.3 秒一次。
func dry_fire(role:int,weapon:Dictionary,running:bool)->void:
	if not running or weapon.is_empty() or not game.run.combat.fire[role]:return
	if int(weapon.ammo)>0 or int(weapon.reserve)>0 or int(weapon.get("reload",0))>0:return
	if game.run.elapsed-dry_clicked[role]<0.3 and game.run.elapsed>=dry_clicked[role]:return
	dry_clicked[role]=game.run.elapsed
	game.sfx.play_at("metal_click",guns[role].global_position,-6.0,1.7)
