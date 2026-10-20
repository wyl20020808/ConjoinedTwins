extends Node3D

# 仅呈现模拟数据，不参与伤害、拾取或锁敌判定。
const EnemyView=preload("res://scripts/journey_enemy_view.gd")
var game
var pickup_views := {}
var guns: Array[Node3D] = []
var beams: Array[MeshInstance3D] = []
var last_shots := [0,0]
var previous_health := [100,100]
var previous_shield_uses := 0

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
	var flash: Node3D=game.box(gun,Vector3(0,0,-0.94),Vector3(0.22,0.22,0.3),game.material("gun_flash",Color("ffe7a0"),2.0))
	flash.name="Flash"
	flash.hide()
	var flash_light:=OmniLight3D.new()
	flash_light.name="FlashLight"
	flash_light.position=Vector3(0,0,-0.95)
	flash_light.light_color=Color("ffdca0")
	flash_light.light_energy=3.2
	flash_light.omni_range=3.0
	flash_light.shadow_enabled=false
	flash_light.visible=false
	gun.add_child(flash_light)
	return gun

func _ready() -> void:
	for role in range(2):
		guns.append(make_gun(self))
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
		mesh.top_radius=0.018
		mesh.bottom_radius=0.018
		mesh.radial_segments=6
		beam.mesh=mesh
		beam.material_override=game.material("bullet_trail",Color("ffdc8c"),1.2)
		beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		beams.append(beam)

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
			collected.queue_free()
			pickup_views.erase(id)
	for pickup in nearby.values():
		if not pickup_views.has(pickup.id):
			var view := Node3D.new()
			add_child(view)
			pickup_views[pickup.id]=view
			if pickup.kind=="gun":
				var gun := make_gun(view)
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
			game.add_sign(view,{"gun":"冲锋枪","ammo":"弹药 +48","medkit":"医疗 +30"}[pickup.kind],Vector3(0,1.2,0),22)
		var view: Node3D=pickup_views[pickup.id]
		view.position=Vector3(pickup.position.x/20,0.65+sin(run.elapsed*2)*0.08,-pickup.position.y/20)
		view.visible=absf(pickup.position.y-run.distance)<3000
		for child in view.get_children():
			if child is Label3D:child.visible=visual_state not in ["rescue","failed"]
	for role in range(2):
		game.robots[role].get_node("CombatShield").visible=run.shield
		var weapon: Dictionary=run.combat.weapons[role]
		guns[role].visible=not weapon.is_empty() and visual_state not in ["rescue","failed","complete","settlement"]
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
		apply_reload(guns[role],int(weapon.get("reload",0)))
		if guns[role].visible and is_instance_valid(skeleton) and int(weapon.get("reload",0))>0:
			reach_hand(skeleton,"R",guns[role].global_position)
			reach_hand(skeleton,"L",guns[role].to_global(guns[role].get_node("Magazine").position))
		var shot: Dictionary=run.combat.shots[role]
		var recent: bool=not shot.is_empty() and run.elapsed-shot.time<0.065 and visual_state=="running"
		guns[role].get_node("Flash").visible=recent
		var flash_light:OmniLight3D=guns[role].get_node_or_null("FlashLight")
		if flash_light!=null:flash_light.visible=recent
		beams[role].visible=recent
		if recent:
			if int(weapon.get("reload",0))==0:
				var recoil:float=1.0-clampf((run.elapsed-shot.time)/.065,0,1)
				guns[role].position+=guns[role].basis.z*.12*recoil
				guns[role].rotate_object_local(Vector3.RIGHT,.07*recoil)
			var from := Vector3(shot.from.x/20,shot.height/20,-shot.from.y/20)
			var to := Vector3(shot.to.x/20,shot.target_height/20,-shot.to.y/20)
			beams[role].position=(from+to)/2
			if from.distance_to(to)>0.001: beams[role].quaternion=Quaternion(Vector3.UP,(to-from).normalized())
			# 光束拓扑固定，长度由变换表达，避免每次射击销毁并重建渲染表面。
			beams[role].scale.y=maxf(.001,from.distance_to(to)/beams[role].mesh.height)
			if shot.id!=last_shots[role]: game.sfx.play("gunshot",-13.0)
		if not shot.is_empty(): last_shots[role]=shot.id
		if run.combat.health[role]<previous_health[role]: game.sfx.play("hit",-9.0)
		previous_health[role]=run.combat.health[role]
	if run.shield_uses>previous_shield_uses: game.sfx.play("shield_break",-6.0)
	previous_shield_uses=run.shield_uses
	for event in run.journey_events:
		if event.has("hp") and game.event_views.has(event.id):
			EnemyView.sync(game,game.event_views[event.id],event)

# 无 Tween、无墙钟时间：暂停、联机、重试和丢枪都直接服从武器剩余帧数。
# 从固定背后视角能看到抬枪、倾斜弹匣口、抽出/插入弹匣和拉栓归位。
func apply_reload(gun:Node3D,remaining:int)->void:
	var t:float=1.0-float(remaining)/game.run.Combat.RELOAD_STEPS
	var lift:=smoothstep(0.0,0.16,t)*(1.0-smoothstep(0.84,1.0,t)) if remaining>0 else 0.0
	var eject:=smoothstep(0.18,0.38,t)*(1.0-smoothstep(0.58,0.78,t)) if remaining>0 else 0.0
	gun.rotate_object_local(Vector3.RIGHT,-0.65*lift)
	gun.rotate_object_local(Vector3.BACK,-0.85*lift)
	gun.position+=Vector3(0.38,0.48,0.12)*lift
	var magazine:Node3D=gun.get_node("Magazine")
	magazine.position=Vector3(-0.2*eject,-0.22-0.65*eject,-0.37+0.12*eject)
	magazine.rotation.z=-0.3*eject
	gun.get_node("MagazineLip").position=magazine.position+Vector3(0,-0.19,0)
	var rack:=sin(clampf((t-0.78)/0.14,0,1)*PI) if remaining>0 else 0.0
	gun.get_node("ChargingHandle").position.z=-0.15+0.18*rack

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
