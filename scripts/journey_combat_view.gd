extends Node3D

# 仅呈现模拟数据，不参与伤害、拾取或锁敌判定。
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
	game.box(gun,Vector3(0,-0.22,-0.37),Vector3(0.13,0.3,0.18),metal)
	game.box(gun,Vector3(0,0.13,-0.2),Vector3(0.05,0.1,0.12),game.material("gun_sight",Color("71e9cf"),0.7))
	var flash: Node3D=game.box(gun,Vector3(0,0,-0.94),Vector3(0.22,0.22,0.3),game.material("gun_flash",Color("ffe7a0"),2.0))
	flash.name="Flash"
	flash.hide()
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

func reset() -> void:
	for view in pickup_views.values(): view.queue_free()
	pickup_views.clear()
	last_shots=[0,0]
	previous_health=game.run.combat.health.duplicate()
	previous_shield_uses=game.run.shield_uses

func sync() -> void:
	var run=game.run
	for id in pickup_views.keys():
		if not run.combat.pickups.any(func(p): return p.id==id):
			pickup_views[id].queue_free()
			pickup_views.erase(id)
	for pickup in run.combat.pickups:
		if absf(pickup.position.y-run.distance)>3000: continue
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
			game.add_sign(view,{"gun":"冲锋枪","ammo":"弹药 +48","medkit":"医疗 +30"}[pickup.kind],Vector3(0,1.2,0),22)
		var view: Node3D=pickup_views[pickup.id]
		view.position=Vector3(pickup.position.x/20,0.65+sin(run.elapsed*2)*0.08,-pickup.position.y/20)
		view.visible=absf(pickup.position.y-run.distance)<3000
	for id in pickup_views:
		if not run.combat.pickups.any(func(p): return p.id==id and absf(p.position.y-run.distance)<3000): pickup_views[id].hide()
	for role in range(2):
		game.robots[role].get_node("CombatShield").visible=run.shield
		var weapon: Dictionary=run.combat.weapons[role]
		guns[role].visible=not weapon.is_empty() and run.state not in ["rescue","failed","complete","settlement"]
		# 与既有角色右手骨骼同步，枪身朝向模拟选中的目标。
		var hand: Vector3=game.hand_point(role)
		var skeleton: Skeleton3D=game.hand_skeletons.get(role)
		if is_instance_valid(skeleton):
			var wrist := skeleton.find_bone("Wrist.R")
			if wrist>=0: hand=skeleton.global_transform*skeleton.get_bone_global_pose(wrist).origin
		guns[role].global_position=hand
		var target := hand+Vector3(0,0,-5)
		if not weapon.is_empty():
			for event in run.journey_events:
				if event.id==weapon.target:
					var point: Vector2=run.Combat.enemy_position(event)
					target=Vector3(point.x/20,run.Combat.enemy_height(event)/20,-point.y/20)
		if hand.distance_to(target)>0.01: guns[role].look_at(target)
		var shot: Dictionary=run.combat.shots[role]
		var recent: bool=not shot.is_empty() and run.elapsed-shot.time<0.065 and run.state in ["running","paused"]
		guns[role].get_node("Flash").visible=recent
		beams[role].visible=recent
		if recent:
			var from := Vector3(shot.from.x/20,shot.height/20,-shot.from.y/20)
			var to := Vector3(shot.to.x/20,shot.target_height/20,-shot.to.y/20)
			beams[role].position=(from+to)/2
			if from.distance_to(to)>0.001: beams[role].quaternion=Quaternion(Vector3.UP,(to-from).normalized())
			beams[role].mesh.height=from.distance_to(to)
			if shot.id!=last_shots[role]: game.sfx.play("gunshot",-13.0)
		if not shot.is_empty(): last_shots[role]=shot.id
		if run.combat.health[role]<previous_health[role]: game.sfx.play("hit",-9.0)
		previous_health[role]=run.combat.health[role]
	if run.shield_uses>previous_shield_uses: game.sfx.play("shield_break",-6.0)
	previous_shield_uses=run.shield_uses
	for event in run.journey_events:
		if not event.has("hp") or not game.event_views.has(event.id): continue
		var view: Node3D=game.event_views[event.id]
		if event.hp<=0:
			view.hide()
			continue
		view.show()
		if not view.has_node("EnemyHealth"):
			game.add_sign(view,"",Vector3.ZERO,23).name="EnemyHealth"
		var sign: Label3D=view.get_node("EnemyHealth")
		var point: Vector2=run.Combat.enemy_position(event)
		sign.global_position=Vector3(point.x/20,3.4,-point.y/20)
		var locked: bool=run.combat.weapons.any(func(w): return not w.is_empty() and w.target==event.id)
		sign.text=("[锁定] " if locked else "")+"%d / %d"%[event.hp,event.max_hp]
		sign.modulate=Color("ffe18b") if locked else Color("e8ebe2")
		sign.visible=event.phase!="spent"
