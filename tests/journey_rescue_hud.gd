extends SceneTree
var failures:=0
func check(ok:bool,message:String)->void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false);game.set_process(false);game.frame_delta=1.0/60
	var run=game.run
	for role in range(2):
		run.retry();game.reset_journey_views();run.state="running";game.play_mode="local"
		run.a.position=Vector2(run.EDGE-70,100);run.b.position=Vector2(run.EDGE-30,100)
		run.last_support=[run.a.position,run.b.position];run.ground_support=[true,true]
		run.begin_fall(role,Vector2(run.EDGE+12,100))
		for frame in range(60):run.step(run.FIXED_STEP)
		game.sync_view()
		check(game.rescue_box.visible,"救援显示独立双进度条")
		check(game.rescue_label.text.contains("空格") and game.rescue_label.text.contains("回车"),"两角色显示各自的救援按键")
		var timer_width:float=game.rescue_timer_fill.size.x
		run.step(run.FIXED_STEP,Vector2.ZERO,Vector2.ZERO,true,true);game.sync_view()
		check(game.rescue_fill.size.x>0 and game.rescue_timer_fill.size.x<timer_width,"按键增长大条、时间减少小条")
		check(game.rescue_fill.size.y>game.rescue_timer_fill.size.y*2,"上下进度条粗细明确")
		var before:=Vector3.ZERO
		while run.state=="rescue":
			before=run.rescue_body_position(role)
			run.step(run.FIXED_STEP)
		check(run.state=="failed" and before.y<0,"未完成救援在崖下超时")
		check(run.death_positions[role].distance_to(before)<2,"失败继承崖下位置，不弹回路面")
		for frame in range(120):run.step(run.FIXED_STEP)
		game.sync_view()
		check(run.death_positions[role].y<0 and not game.rescue_box.visible,"死亡后保持真实下坠，关闭救援条")
		var pose:Vector3=game.robots[role].rotation
		for frame in range(240):run.step(run.FIXED_STEP)
		game.sync_view()
		check(game.robots[role].rotation.is_equal_approx(pose),"坠落倾斜稳定，不持续原地打转")
		check(game.panel.visible,"失败演出结束显示重试，不停在救援状态")
	for player in game.sfx.players:player.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("JOURNEY_RESCUE_HUD failures=",failures)
	quit(1 if failures else 0)
