extends SceneTree

# 主角步态画面回归：跳跃三段、无滑步步速、侧步/后退混合、持枪上半身层与双脚贴地；
# 救援、受击/死亡让位于原整段动作，模拟状态不受画面影响。
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:call_deferred("verify")

func clip(player:AnimationPlayer,name:String)->String:
	return "CharacterArmature|"+name

func foot_heights(game,i:int,name:String,samples:int)->PackedFloat32Array:
	var player:AnimationPlayer=game.animation_players[i]
	var skeleton:Skeleton3D=game.hand_skeletons[i]
	var animation:=player.get_animation(clip(player,name))
	player.play(clip(player,name))
	var lowest:=PackedFloat32Array()
	for k in range(samples+1):
		player.seek(animation.length*k/samples,true)
		skeleton.force_update_all_bone_transforms()
		var low:=INF
		for bone in ["LeftFoot","RightFoot"]:
			low=minf(low,(skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin).y)
		lowest.append(low)
	return lowest

# 支撑脚（贴近最低点的一只）滑过地面的水平速度，即片段原速下角色应有的移动速度。
func stride_speed(game,i:int)->float:
	var player:AnimationPlayer=game.animation_players[i]
	var skeleton:Skeleton3D=game.hand_skeletons[i]
	var animation:=player.get_animation(clip(player,"Run"))
	player.play(clip(player,"Run"))
	var points:=[]
	var n:=96
	for k in range(n+1):
		player.seek(animation.length*k/n,true)
		skeleton.force_update_all_bone_transforms()
		points.append([skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("LeftFoot")).origin,skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("RightFoot")).origin])
	var low:=INF
	for row in points:low=minf(low,minf(row[0].y,row[1].y))
	var total:=0.0;var count:=0
	for k in range(n):
		for f in range(2):
			if points[k][f].y<low+0.04 and points[k+1][f].y<low+0.04:
				var step:Vector3=points[k+1][f]-points[k][f];step.y=0
				total+=step.length()/(animation.length/n);count+=1
	return total/maxf(count,1)

func sync(game,frames:int=1)->void:
	for n in range(frames):
		game.sync_view()
		await process_frame

func verify()->void:
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.frame_delta=1.0/60
	var run=game.run
	await process_frame
	for i in range(2):game.hand_point(i)
	for i in range(2):
		var list:PackedStringArray=game.animation_players[i].get_animation_list()
		for name in ["Jump_Start","Jump_Air","Jump_Land","Jump_Land_Heavy","Run_Left","Run_Right","Run_Back","Idle_Gun_Pointing"]:
			check(list.has(clip(game.animation_players[i],name)),"%02d 含 %s"%[i+1,name])
		var measured:=stride_speed(game,i)
		check(absf(measured-game.HERO_STRIDE_SPEED[i])<game.HERO_STRIDE_SPEED[i]*0.05,"%02d 自然步速常量与 Run 片段一致（实测 %.2f）"%[i+1,measured])
		# 合成的落地缓冲两只脚始终踩在 Idle 的脚踝高度上，不悬空也不穿地。
		var idle:float=foot_heights(game,i,"Idle",4)[0]
		for name in ["Jump_Land","Jump_Land_Heavy"]:
			var worst:=0.0
			for h in foot_heights(game,i,name,24):worst=maxf(worst,absf(h-idle))
			check(worst<0.03,"%02d %s 全程脚掌贴地（偏差 %.3f）"%[i+1,name,worst])
		var start:=foot_heights(game,i,"Jump_Start",8)
		check(absf(start[0]-idle)<0.03 and start[8]>idle+0.04,"%02d 起跳从踩地蹲伏到蹬离地面"%(i+1))

	# 跳跃三段按竖直速度切换，相位由模拟决定。
	run.state="running"
	var hash_before:int=run.sync_hash()
	var player:AnimationPlayer=game.animation_players[0]
	run.heights[0]=4.0;run.vertical_speed[0]=run.JUMP_SPEED*0.9
	game.sync_view()
	check(player.current_animation.ends_with("Jump_Start") and absf(player.current_animation_position/player.current_animation_length-0.25)<0.01,"上升初段播放起跳预备并按竖直速度定相位")
	await process_frame
	run.heights[0]=30.0;run.vertical_speed[0]=0.0
	game.sync_view()
	check(player.current_animation.ends_with("Jump_Air") and absf(player.current_animation_position/player.current_animation_length-0.375)<0.01,"顶点附近播放腾空收腿")
	await process_frame
	run.vertical_speed[0]=-run.JUMP_SPEED
	game.sync_view()
	check(absf(player.current_animation_position/player.current_animation_length-1.0)<0.01,"下落末段伸腿准备着地")
	check(game.hero_rigs[0].foot_weight==0.0,"腾空时关闭双脚贴地")
	run.heights[0]=0.0;run.vertical_speed[0]=0.0
	await sync(game)
	check(player.current_animation.ends_with("Jump_Land") and game.landing_strength[0]<0.5,"普通跳跃落地轻缓冲")
	for n in range(60):await sync(game)
	check(not player.current_animation.contains("Jump"),"缓冲结束回到行进动作")
	run.heights[0]=run.JUMP_APEX*1.8;run.vertical_speed[0]=-run.JUMP_SPEED*1.5
	await sync(game)
	run.heights[0]=0.0;run.vertical_speed[0]=0.0
	await sync(game)
	check(player.current_animation.ends_with("Jump_Land_Heavy") and game.landing_strength[0]>0.8,"高处落下重缓冲")
	check(player.speed_scale<1.2,"重缓冲放慢，轻缓冲更快")
	for n in range(80):await sync(game)
	check(run.sync_hash()==hash_before,"画面层不改模拟状态")

	# 跑步倍率随实际水平速度，侧移不再偏航，侧步/后退按方向混合。
	for dir in [Vector2(0,1),Vector2(1,0),Vector2(-1,0),Vector2(0,-1)]:
		for n in range(20):
			run.fixed_step(dir,dir)
			await sync(game)
		var speed:float=game.hero_velocity[0].length()
		var rig=game.hero_rigs[0]
		var label:="前进" if dir.y>0 else ("后退" if dir.y<0 else ("右移" if dir.x>0 else "左移"))
		check(player.current_animation.ends_with("Run") and absf(player.speed_scale-speed/game.HERO_STRIDE_SPEED[0])<0.01 and speed>10.0,"%s：Run 倍率 = 实际速度 / 自然步速（%.2f）"%[label,player.speed_scale])
		check(is_zero_approx(game.robots[0].rotation.y),"%s：身体保持朝前，不用偏航假装侧移"%label)
		var expected:="Run_Right" if dir.x>0 else ("Run_Left" if dir.x<0 else ("Run_Back" if dir.y<0 else ""))
		for name in rig.strafe:
			var w:float=rig.strafe[name]
			check(w>0.9 if name==expected else w<0.1,"%s：%s 混合权重 %.2f"%[label,name,w])
	# 侧步层确实改动了骨骼：右移时脚踝相对动画姿势有横向位移。
	var skeleton:Skeleton3D=game.hand_skeletons[0]
	var rig=game.hero_rigs[0]
	var foot:int=skeleton.find_bone("RightFoot")
	for n in range(20):
		run.fixed_step(Vector2(1,0),Vector2(1,0))
		await sync(game)
	check(rig.final_pose(foot).origin.distance_to(skeleton.get_bone_global_pose(foot).origin)>0.01,"侧步混合作用于最终骨骼姿势")

	# 持枪：右臂取持枪姿势，枪挂在修改后的手腕上；换弹时手臂交还战斗画面的手部 IK。
	run.combat.weapons[0]=run.Combat.gun()
	for n in range(40):
		run.fixed_step(Vector2(0,1),Vector2(0,1))
		await sync(game)
	var hand:int=skeleton.find_bone("RightHand")
	check(is_equal_approx(rig.gun_weight,1.0) and rig.gun_arms,"拿枪后上半身持枪层完全生效")
	check(player.current_animation.ends_with("Run") and player.speed_scale>1.0,"持枪时下半身继续跑步")
	check(rig.final_pose(hand).origin.distance_to(skeleton.get_bone_global_pose(hand).origin)>0.02,"右臂离开跑步摆臂，改为持枪")
	game.sync_view()
	var gun:Node3D=game.combat_view.guns[0]
	check(gun.global_position.distance_to(skeleton.global_transform*rig.final_pose(hand).origin)<0.001,"枪挂在持枪层修改后的手腕上")
	run.combat.weapons[0].reload=10
	await sync(game)
	check(not rig.gun_arms,"换弹时持枪层不覆盖双臂")
	run.combat.weapons[0]={}
	await sync(game)
	check(rig.gun_weight==0.0,"放下枪立即撤掉持枪层")

	# 双脚贴地：右脚下方高 0.3、左脚平地时只抬右脚；右脚下方低 0.3 时先压低髋部再下探。
	for n in range(10):
		run.fixed_step(Vector2.ZERO,Vector2.ZERO)
		await sync(game)
	check(is_equal_approx(game.hero_ground(game.robots[0].global_position),run.floor_heights[0]/20.0),"平地采样与模拟地面高度一致")
	var real_ground:Callable=rig.ground
	var scale:float=skeleton.global_transform.basis.get_scale().y
	var lfoot:int=skeleton.find_bone("LeftFoot")
	for n in range(30):await sync(game)
	# 台阶分界取两脚当前位置的中点，右脚在外侧。
	var centre:float=(skeleton.global_transform*((skeleton.get_bone_global_pose(lfoot).origin+skeleton.get_bone_global_pose(foot).origin)*0.5)).x
	for step in [0.3,-0.3]:
		rig.ground=func(p:Vector3)->float:return rig.ground_ref+(step if p.x>centre else 0.0)
		await sync(game,2)
		var right_shift:float=(rig.final_pose(foot).origin.y-skeleton.get_bone_global_pose(foot).origin.y)*scale
		var left_shift:float=(rig.final_pose(lfoot).origin.y-skeleton.get_bone_global_pose(lfoot).origin.y)*scale
		check(absf(right_shift-step)<0.03 and absf(left_shift)<0.03,"台阶 %+.1f：右脚落到台面（%.3f），左脚不动（%.3f）"%[step,right_shift,left_shift])
	rig.ground=real_ground

	# 救援与死亡：步态层全部让位，保持原 RopePull / Climb / 受击动作。
	run.state="rescue"
	run.rescue={"role":1,"point":Vector2(200,60),"hang":Vector2(330,60),"progress":0.3,"time":0.5,"rate":0.0,"gain":0.0,"presses":[0,0],"rim":Vector2(200,60)}
	await sync(game,3)
	check(String(game.animation_players[0].current_animation)=="RopePull" and String(game.animation_players[1].current_animation)=="Climb","救援仍播放 RopePull / Climb")
	for i in range(2):
		var r=game.hero_rigs[i]
		check(r.foot_weight==0.0 and r.gun_weight==0.0 and r.strafe.values().max()<=0.001,"%02d 救援时步态层关闭"%(i+1))
	run.state="running";run.rescue={}
	await sync(game)
	run.fail_threat("01 撞击障碍")
	await sync(game)
	check(game.animation_players[0].current_animation.contains("HitRecieve") and game.hero_rigs[0].foot_weight==0.0,"受击动作不被贴地层改动")

	for p in game.sfx.players:p.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("HERO_LOCOMOTION failures=",failures)
	quit(1 if failures else 0)
