extends SceneTree
# 失败—重试循环：演出 0.6 秒后可按跳跃从存档继续，失败条在底部不遮挡演出，
# 恢复时黑场淡入，新存档出现时短暂提示；全部只读模拟状态。
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:call_deferred("verify")

func key(code:int)->InputEventKey:
	var event:=InputEventKey.new();event.keycode=code;event.pressed=true
	return event

func verify()->void:
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.frame_delta=1.0/60
	var run=game.run
	game.scene_prepared=true
	run.state="running"
	for frame in range(240):run.step(run.FIXED_STEP,Vector2(0,1),Vector2(0,1))
	game.sync_view()
	# 新存档出现时提示一次，同一存档不重复提示。
	run.capture_checkpoint()
	game.update_restore_feedback(1.0/60)
	check(game.checkpoint_toast.visible,"新存档出现时显示已存档提示")
	for n in range(60):game.update_restore_feedback(1.0/60)
	check(not game.checkpoint_toast.visible,"存档提示约 0.8 秒后消失")
	game.update_restore_feedback(1.0/60)
	check(not game.checkpoint_toast.visible,"同一存档不重复提示")
	var saved:Dictionary=run.checkpoint.duplicate(true)
	for frame in range(120):run.step(run.FIXED_STEP,Vector2(0,1),Vector2(0,1))
	run.fail_threat("01 撞击障碍")
	game.sync_view()
	check(not game.panel.visible,"演出开头不显示失败条")
	game._unhandled_key_input(key(KEY_SPACE))
	check(run.state=="failed","演出开头 0.6 秒内跳跃不能误触重试")
	for frame in range(int(ceil(game.FAIL_SKIP_AFTER/run.FIXED_STEP))+1):run.step(run.FIXED_STEP)
	check(run.death_time<game.FAIL_HIT_SHOW,"完整演出尚未结束")
	game.sync_view()
	check(game.panel.visible,"0.6 秒后显示失败条")
	var viewport:Vector2=game.get_viewport().get_visible_rect().size
	check(game.panel.position.y+game.panel.size.y>viewport.y*0.75 and game.panel.size.y<viewport.y*0.4,"失败条在屏幕下方且不遮挡演出")
	check(game.primary.text.begins_with("从存档继续"),"失败条主按钮提示从存档继续")
	game._unhandled_key_input(key(KEY_SPACE))
	check(run.state=="running","跳过演出后按空格从存档继续")
	check(run.a.position==saved.a and run.b.position==saved.b,"恢复到最近存档站位")
	check(game.restore_fade_left>0.0,"恢复时开始黑场淡入")
	game.update_restore_feedback(1.0/60)
	check(game.restore_fade.visible and game.restore_fade.color.a>0.8,"淡入从接近全黑开始")
	check(not game.checkpoint_toast.visible,"恢复同一存档不提示已存档")
	for n in range(20):game.update_restore_feedback(1.0/60)
	check(not game.restore_fade.visible,"淡入 0.25 秒后结束")
	# 没有存档时回车整关重试，失败条文案对应调整。
	run.checkpoint={}
	run.fail_threat("02 撞击障碍")
	for frame in range(90):run.step(run.FIXED_STEP)
	game.sync_view()
	check(game.primary.text.begins_with("从起点重试"),"无存档时提示从起点重试")
	game._unhandled_key_input(key(KEY_ENTER))
	check(run.state!="failed","无存档时回车整关重试")
	for player in game.sfx.players:player.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("JOURNEY_FAST_RETRY failures=",failures)
	quit(1 if failures else 0)
