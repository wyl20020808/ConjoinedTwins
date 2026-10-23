extends SceneTree
# 命中手感：本机受击约 3 帧色散、敌人命中停顿与画面击退、开关保存；全部只读模拟状态。
const EnemyView=preload("res://scripts/journey_enemy_view.gd")
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
	run.state="running"
	game.impact_effects=true
	game.sync_view()
	# 队友受击只有红边，本机受击才有画面冲击。
	run.combat.health[1]-=20;game.update_journey_ui()
	check(game.damage_flash>0.9 and game.impact_flash==0.0,"队友受击不触发本机画面冲击")
	run.combat.health[0]-=20;game.update_journey_ui()
	check(game.impact_flash==1.0,"本机受击触发画面冲击")
	game.impact_flash=maxf(0.0,game.impact_flash-(1.0/60)/game.IMPACT_TIME)
	check(game.impact_flash>0.0,"第 1 帧后仍有色散")
	for n in range(3): game.impact_flash=maxf(0.0,game.impact_flash-(1.0/60)/game.IMPACT_TIME)
	check(game.impact_flash==0.0,"色散约 3 帧内结束")
	# 关闭开关后色散参数为 0，并写入本机设置。
	game._process(1.0/60)
	game.impact_flash=1.0;game.impact_effects=false;game._process(1.0/60)
	check(float(game.vignette_mat.get_shader_parameter("impact"))==0.0,"关闭开关后不做色散")
	game.save_feel_settings();game.impact_effects=true;game.load_feel_settings()
	check(not game.impact_effects,"开关保存到本机设置")
	game.impact_effects=true;game.save_feel_settings()
	# 开关已并入设置页：暂停后从设置入口进入。
	run.pause();game.update_journey_ui();game.open_settings()
	check(game.impact_button.is_visible_in_tree() and game.impact_button.text.ends_with("开"),"暂停菜单的设置页显示画面冲击开关")
	run.pause();game.update_journey_ui()
	check(not game.impact_button.is_visible_in_tree(),"游玩时隐藏开关")
	# 敌人命中停顿与击退：用第一只敌人的显示节点直接验证。
	var event:Dictionary={}
	for candidate in run.journey_events:
		if candidate.kind=="monster": event=candidate;break
	run.distance=event.y-300;run.a.position=Vector2(-42,event.y-300);run.b.position=Vector2(42,event.y-300)
	game.sync_view()
	var view:Node3D=game.event_views.get(event.id)
	check(view!=null,"敌人显示节点存在")
	if view!=null:
		EnemyView.sync(game,view,event)
		var actor:Node3D=view.get_meta("enemy_body")
		var rest:Vector3=actor.position;var rest_scale:Vector3=actor.scale
		var player:AnimationPlayer=actor.get_meta("anim") if actor.has_meta("anim") else null
		event.hit_at=run.elapsed;event.hit_damage=10
		EnemyView.sync(game,view,event)
		check(actor.position.z<rest.z-0.1,"命中后画面击退远离玩家")
		check(actor.scale.x>rest_scale.x*1.05,"命中瞬间放大强调")
		if player!=null:
			var pose:float=player.current_animation_position
			run.elapsed+=0.03;EnemyView.sync(game,view,event)
			check(is_equal_approx(player.current_animation_position,pose),"命中停顿期间保持姿势")
			run.elapsed+=0.3;EnemyView.sync(game,view,event)
			check(actor.position.distance_to(rest)<0.02 and is_equal_approx(actor.scale.x,rest_scale.x),"0.2 秒后回到模拟位置与原尺寸")
	for p in game.sfx.players:p.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("JOURNEY_HIT_FEEL failures=",failures)
	quit(1 if failures else 0)
