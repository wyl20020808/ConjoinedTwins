extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.play_mode="local";game.opening_enabled=false;game.incremental_loading=true
	game.run.random_seed=false;game.run.seed_value=8123;game.run.retry();game.run.state="paused"
	game.reset_journey_views()
	var expected:int=game.run.sync_hash()
	var frames:=0;var peak:=0
	while frames<1200:
		game.prepare_journey_frame()
		var made:int=game.model_builds_this_frame
		game.prepare_journey_frame()
		check(game.model_builds_this_frame<=1,"重复准备调用也不能突破每画面帧一个模型")
		peak=maxi(peak,game.model_builds_this_frame)
		game.sync_view()
		frames+=1
		await process_frame
		if made==0 and game.chunk_jobs.is_empty() and game.chunk_assets.pending.is_empty() and game.chunk_assets.active.is_empty() and game.scene_preparation_progress==1.0:break
	check(frames<1200,"限量准备最终完成")
	check(game.run.sync_hash()==expected,"展示加载不改模拟和联机指纹")
	var hidden:=0
	for collection in [game.event_views,game.static_views,game.gate_views]:
		for view:Node3D in collection.values():
			if not view.visible:
				hidden+=1;check(not view.can_process(),"隐藏展示树不处理动画")
			var was:bool=view.visible
			view.hide();check(not view.can_process(),"离开显示范围即停止处理")
			view.show()
			check(view.can_process()==not view.get_meta("enemy_far_ready",false),"恢复显示时按近景/远景恢复处理")
			view.visible=was
	# 真实 AnimationPlayer 验证：隐藏期间时间停止，恢复后继续。
	var holder:=Node3D.new();game.road.add_child(holder)
	var player:=AnimationPlayer.new();holder.add_child(player)
	var clip:=Animation.new();clip.length=5.0;clip.loop_mode=Animation.LOOP_LINEAR
	var library:=AnimationLibrary.new();library.add_animation("idle",clip);player.add_animation_library("",library)
	game.manage_presentation(holder);player.play("idle")
	await create_timer(.05).timeout
	holder.hide();var age:float=player.current_animation_position
	await create_timer(.05).timeout
	check(player.current_animation_position==age,"隐藏模型的原生动画时钟停止")
	holder.show();await create_timer(.05).timeout
	check(player.current_animation_position>age,"重新显示后原生动画时钟恢复")
	print("PRESENTATION_STREAMING checks=",checks," failures=",failures," frames=",frames," max_builds=",peak," hidden=",hidden," events=",game.event_views.size()," hazards=",game.static_views.size())
	for p in game.sfx.players:p.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	quit(1 if failures else 0)
