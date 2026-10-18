extends SceneTree
# 使用引擎真实物理回调；覆盖不按救援键的失败路径，不能只验证快速拉起。
var failures:=0
func check(ok:bool,message:String)->void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	call_deferred("verify")
func verify()->void:
	Engine.max_fps=60
	var boot=load("res://scenes/journey_boot.tscn").instantiate()
	root.add_child(boot)
	while not is_instance_valid(boot.game) or not boot.game.scene_prepared:await process_frame
	var game=boot.game
	game.play_mode="local"
	var run=game.run
	for cycle in range(8):
		run.retry();game.reset_journey_views();run.state="running"
		var role:=cycle%2
		var side:float=1.0 if cycle%4<2 else -1.0
		var y:float=100 if cycle<4 else 600
		run.a.position=Vector2(side*(run.EDGE-70),y);run.b.position=Vector2(side*(run.EDGE-30),y)
		run.last_support=[run.a.position,run.b.position];run.ground_support=[true,true];run.distance=y
		run.rope.reset(run.a.position,run.b.position)
		run.begin_fall(role,Vector2(side*(run.EDGE+12),y))
		var before:=Vector3.ZERO
		var deadline:=Time.get_ticks_msec()+12000
		var captured:=false
		while run.state in ["rescue","paused"] and Time.get_ticks_msec()<deadline:
			if run.state=="paused":game.command("pause",run.paused_from)
			before=run.rescue_body_position(role)
			# 第一次用力后松开，让进度衰减直至失败。
			var press:bool=run.rescue.time>.3 and run.rescue.time<.34
			game.input_override={"a":Vector2.ZERO,"b":Vector2.ZERO,"ja":press,"jb":press,"fire":false,"reload":false,"drop":false}
			if cycle==0 and run.rescue.time>.4 and not captured:
				var directory:=OS.get_environment("RESCUE_REPORT_DIR")
				if not directory.is_empty() and DisplayServer.get_name()!="headless":root.get_texture().get_image().save_png(directory.path_join("rescue-input.png"))
				captured=true
			await process_frame
		check(run.state=="failed","真实回调救援超时 cycle=%d"%cycle)
		if run.state!="failed":break
		check(before.y<0 and run.death_positions[role].y<0,"超时前后人物都在崖下")
		while run.death_time<3.0 and Time.get_ticks_msec()<deadline:await process_frame
		check(run.death_time>=3.0 and game.panel.visible,"死亡演出结束可重试")
		check(not game.rescue_box.visible and run.death_positions[role].is_finite(),"救援 HUD 关闭，身体坐标保持有效")
		print("LIFECYCLE_DONE cycle=",cycle," y=",run.death_positions[role].y)
	game.set_physics_process(false);game.set_process(false)
	for player in game.sfx.players:player.stop()
	boot.queue_free()
	for frame in range(4):await process_frame
	await create_timer(.2).timeout
	print("JOURNEY_RESCUE_LIFECYCLE failures=",failures," cycles=8")
	quit(1 if failures else 0)
