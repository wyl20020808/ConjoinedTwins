extends SceneTree
var failures:=0
func check(ok:bool,label:String):
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize():call_deferred("verify")
func verify():
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.frame_delta=1.0/60.0
	await process_frame
	var run=game.run
	run.state="running"
	for type in ["smg","shotgun","flamer","launcher"]:
		for role in range(2):run.combat.weapons[role]=run.Combat.gun(type)
		for aiming in [false,true]:
			run.combat.fire=[aiming,aiming]
			for frame in range(25):
				game.sync_view()
				await process_frame
			for role in range(2):
				var rig=game.hero_rigs[role]
				var sk:Skeleton3D=game.hand_skeletons[role]
				var view=game.combat_view
				var gun:Node3D=view.guns[role]
				for side in ["Right","Left"]:
					var pose:Transform3D=rig.final_pose(sk.find_bone(side+"Hand"))
					var palm:Vector3=sk.global_transform*(pose*Vector3(0,0.045,0))
					var target:Vector3=gun.to_global(view.GRIP_RIGHT if side=="Right" else view.grip_left_of(gun.get_node(type)))
					var error:=palm.distance_to(target)
					check(error<0.12,"%s role=%d aim=%s %s palm error=%.3f"%[type,role,aiming,side,error])
					if error>0.12:print("DETAIL palm=",palm," target=",target," basis=",pose.basis)
	var view=game.combat_view
	# 转身后的最终姿势也必须保持掌心接触，肘部不能使用固定世界方向。
	for yaw in [PI/2,PI,-PI/2]:
		for role in range(2):game.robots[role].rotation.y=yaw
		view.sync()
		await process_frame
		for role in range(2):
			var sk:Skeleton3D=game.hand_skeletons[role]
			var rig=game.hero_rigs[role]
			var hand:Transform3D=rig.final_pose(sk.find_bone("RightHand"))
			var palm:Vector3=sk.global_transform*(hand*Vector3(0,0.045,0))
			check(palm.distance_to(view.guns[role].to_global(view.GRIP_RIGHT))<0.12,"转身 %.2f role=%d 保持握把接触"%[yaw,role])
	# 跳跃姿势在渲染更新后仍停留在选定的物理相位。
	run.heights[0]=30.0;run.vertical_speed[0]=run.JUMP_SPEED*0.8
	game.sync_view()
	var player:AnimationPlayer=game.animation_players[0]
	var time:=player.current_animation_position
	await process_frame
	check(is_equal_approx(player.current_animation_position,time),"腾空动画不会被渲染帧再次推进")
	check(game.hero_rigs[0].strafe.values().max()==0.0,"腾空不残留地面侧步")
	run.heights[0]=0.0;run.vertical_speed[0]=0.0
	for type in ["smg","shotgun","flamer","launcher"]:
		run.combat.weapons[0]=run.Combat.gun(type)
		run.combat.weapons[0].ammo=0
		run.Combat.start_reload(run,0)
		var weapon:Dictionary=run.combat.weapons[0]
		for fraction in [0.15,0.45,0.7,0.95]:
			weapon.reload=maxi(1,int(weapon.reload_total*(1.0-fraction)))
			game.sync_view();await process_frame
			var sk:Skeleton3D=game.hand_skeletons[0]
			var hand:Transform3D=game.hero_rigs[0].final_pose(sk.find_bone("RightHand"))
			var palm:Vector3=sk.global_transform*(hand*Vector3(0,0.045,0))
			check(palm.distance_to(view.guns[0].to_global(view.GRIP_RIGHT))<0.12,"%s 换弹 %.2f 右手持续持枪"%[type,fraction])
	# 暂停后瞄准与热度不能继续变化。
	run.paused_from="running";run.state="paused"
	var aim:float=view.aim_level[0]
	view.heat[0]=0.6
	for frame in range(8):game.sync_view();await process_frame
	check(view.aim_level[0]==aim and view.heat[0]==0.6,"暂停冻结瞄准与后坐热度")
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("HERO_COMBAT_POSE failures=",failures)
	quit(1 if failures else 0)
