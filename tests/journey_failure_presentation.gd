extends SceneTree

var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.frame_delta=1.0/60
	var run=game.run
	run.state="running";run.distance=600
	game.sync_view()
	var home:Transform3D=game.camera.transform
	check(is_equal_approx(home.origin.z,game.camera_home.origin.z-30),"普通机位跟随旅程世界进度")
	run.fail_threat("01 撞击障碍")
	game.sync_view()
	check(not game.panel.visible,"受击演出先于失败面板")
	check(game.animation_players[0].current_animation.contains("HitRecieve"),"受击播放既有骨骼动作")
	game.apply_journey_primary()
	check(run.state=="failed","回车不能跳过失败演出")
	for player in game.animation_players:
		player.advance(player.current_animation_length+0.1)
	game.sync_view()
	check(game.animation_players[0].current_animation.ends_with("Death"),"受击结束进入淘汰动画且不被刷新覆盖")
	check(not game.camera.transform.is_equal_approx(home),"撞击镜头推近出事角色")
	for frame in range(90):run.step(run.FIXED_STEP)
	game.sync_view()
	check(run.death_positions[0].y<run.floor_heights[0] and is_equal_approx(game.robots[0].position.y,run.floor_heights[0]/20),"物理腰扣下降不会把倒地模型重复沉入地面")
	run.death_time=game.FAIL_HIT_SHOW+0.1;game.sync_view()
	check(game.panel.visible,"受击演出结束显示重试入口")
	game.apply_journey_primary()
	check(run.state!="failed" and not game.failed_animation_started.has(true),"重试清理淘汰动作状态")
	run.state="running";run.fall(0,run.a.position)
	for frame in range(60):run.step(run.FIXED_STEP)
	game.sync_view()
	var waist:Vector3=game.robots[0].position+game.robots[0].basis*Vector3(0,1.4,0)
	var body:Vector3=run.death_positions[0]
	check(absf(game.robots[0].rotation.x)>0.1,"坠落恢复身体翻滚")
	check(waist.distance_to(Vector3(body.x/20,body.y/20+1.4,-body.z/20))<0.001,"翻滚围绕物理腰部挂点")
	check(not game.shadows[0].visible and not game.panel.visible,"坠落隐藏地面阴影并保留演出窗口")
	check(not game.camera_shot().is_equal_approx(home),"坠落镜头跟随角色下坠")
	for role in range(2):
		run.retry();game.reset_journey_views();run.state="running"
		run.a.position=Vector2(run.EDGE-70,100);run.b.position=Vector2(run.EDGE-30,100)
		run.last_support=[run.a.position,run.b.position]
		run.ground_support=[true,true]
		run.combat.weapons[role]=run.Combat.gun()
		run.combat.weapons[role].reload=30
		run.begin_fall(role,Vector2(run.EDGE+12,100))
		for frame in range(30):run.step(run.FIXED_STEP)
		game.sync_view()
		check(game.animation_players[role].current_animation=="Climb","角色 %d 吊挂攀爬"%role)
		check(game.animation_players[1-role].current_animation=="RopePull","角色 %d 拉绳救援"%(1-role))
		check(not game.shadows[role].visible,"吊挂者不显示路面阴影")
		check(not game.combat_view.guns[role].visible,"救援期间隐藏持枪与换弹表现")
		for frame in range(90):game.update_journey_camera()
		var screen:Rect2=game.get_viewport().get_visible_rect()
		for actor in game.robots:
			for height in [0.2,3.3]:
				var point:Vector3=actor.position+Vector3.UP*height
				check(not game.camera.is_position_behind(point) and screen.grow(-12).has_point(game.camera.unproject_position(point)),"救援特写同时容纳两人的头脚")
			for child in actor.get_children():
				if child is Label3D:check(not child.visible,"特写隐藏放大的角色编号")
		var rescue_camera:Transform3D=game.camera.transform
		run.pause();game.sync_view()
		check(game.animation_players[0].speed_scale==0 and game.animation_players[1].speed_scale==0,"暂停冻结救援动作")
		check(game.camera.transform.is_equal_approx(rescue_camera),"暂停冻结救援镜头")
		check(not game.combat_view.guns[role].visible,"暂停救援不会重新显示枪械")
		run.pause();run.rescue.progress=1.0;run.step(run.FIXED_STEP)
		check(run.rescue.has("climb"),"救援成功进入实际爬上阶段")
		for frame in range(int(run.RESCUE_CLIMB_TIME/run.FIXED_STEP*.65)):run.step(run.FIXED_STEP)
		game.sync_view()
		check(game.animation_players[role].current_animation.ends_with("Run"),"爬上后段切换迈上路面动作")
		for frame in range(int(run.RESCUE_CLIMB_TIME/run.FIXED_STEP)):run.step(run.FIXED_STEP)
		game.sync_view()
		check(run.state=="running" and run.rescue.is_empty(),"拉起结束回到正常运行")
		for frame in range(300):game.update_journey_camera()
		check(game.camera.transform.origin.distance_to(game.camera_shot().origin)<0.02,"救援后镜头平滑回到正常机位")
	for player in game.sfx.players:player.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("JOURNEY_FAILURE_PRESENTATION failures=",failures)
	quit(1 if failures else 0)
