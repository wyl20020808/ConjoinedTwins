extends SceneTree
# 双枪：手上一把、背上一把；第二把自动背上，第三把不拾取；换枪互换并有 0.3 秒不能开火；
# 丢下手上的枪自动换上背后的；存档恢复、联机命令（新旧格式）、界面与背枪模型。
const Journey=preload("res://scripts/journey_run.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:call_deferred("verify")

func pickup_at(run,type:String)->void:
	run.Combat.add_pickup(run,"gun",run.a.position,{},type)

func verify()->void:
	var run=Journey.new();run.retry();run.state="running"
	var Combat=run.Combat
	run.combat.pickups.clear()
	run.a.position=Vector2(-42,300);run.b.position=Vector2(42,300)
	var previous:=[run.a.position,run.b.position]
	pickup_at(run,"smg");Combat.collect(run,previous)
	check(run.combat.weapons[0].get("type","")=="smg" and run.combat.backups[0].is_empty(),"第一把枪拿在手上")
	pickup_at(run,"shotgun");Combat.collect(run,previous)
	check(Combat.backup(run,0).get("type","")=="shotgun","第二把枪背到背上")
	check(run.combat.notice.contains("背在背上"),"提示第二把背在背上")
	pickup_at(run,"launcher");Combat.collect(run,previous)
	check(run.combat.pickups.size()==1 and run.combat.pickups[0].weapon_type=="launcher","两把都满时不拾取第三把")
	run.combat.pickups.clear()
	# 换枪：互换，手上的换弹中断，新枪 0.3 秒内不能开火。
	run.combat.weapons[0].ammo=3;run.combat.weapons[0].reload=50
	run.set_combat_input(false,false,false,true)
	Combat.tick(run,previous)
	check(run.combat.weapons[0].type=="shotgun" and run.combat.backups[0].type=="smg","换枪互换手上与背上")
	check(run.combat.backups[0].reload==0,"收起的枪中断换弹")
	var shots:int=run.combat.shot_serial
	for n in range(Combat.SWAP_STEPS-2):
		run.combat.fire[0]=true;Combat.tick(run,previous)
	check(run.combat.shot_serial==shots,"换枪后 0.3 秒内不能开火")
	run.combat.swap[0]=true;Combat.tick(run,previous)
	check(run.combat.weapons[0].type=="smg" and run.combat.backups[0].type=="shotgun","再按一次换回")
	# 丢下手上的枪：背后的自动拿到手上。
	run.combat.drop[0]=true;Combat.tick(run,previous)
	check(run.combat.weapons[0].type=="shotgun" and run.combat.backups[0].is_empty(),"丢枪后换上背后的枪")
	check(run.combat.pickups.size()==1 and run.combat.pickups[0].weapon.type=="smg","丢下的枪留在地上")
	# 背上没有枪时换枪无动作。
	run.combat.swap[0]=true;Combat.tick(run,previous)
	check(run.combat.weapons[0].type=="shotgun","背上没有枪时换枪无动作")
	# 存档恢复背枪。
	run.combat.backups[0]=Combat.gun("flamer")
	run.capture_checkpoint()
	run.combat.backups[0]={}
	run.fail_threat("测试")
	check(run.restore_checkpoint() and Combat.backup(run,0).get("type","")=="flamer","存档恢复背上的枪")
	# 旧存档与旧夹具没有背枪槽，按需补齐。
	run.combat.erase("backups");run.combat.erase("swap")
	Combat.tick(run,previous)
	check(run.combat.backups==[{},{}] and run.combat.swap==[false,false],"旧战斗数据自动补齐背枪槽")
	run.dispose()

	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.frame_delta=1.0/60
	var view_run=game.run
	view_run.state="running"
	# 联机命令：4 个字段带换枪，3 个字段为旧版客户端。
	view_run.combat.weapons[1]=view_run.Combat.gun("smg");view_run.combat.backups[1]=view_run.Combat.gun("launcher")
	game.apply_combat_command(1,"0,0,0,1")
	check(view_run.combat.swap[1],"4 字段联机命令写入换枪")
	view_run.combat.swap[1]=false
	game.apply_combat_command(1,"1,0,0")
	check(view_run.combat.fire[1] and not view_run.combat.swap[1],"旧版 3 字段命令仍然有效")
	view_run.combat.fire[1]=false
	# 键盘 Q 换枪。
	var key:=InputEventKey.new();key.keycode=KEY_Q;key.pressed=true
	game.scene_prepared=true
	game._unhandled_key_input(key)
	check(game.sample_local_input().get("swap",false),"Q 键请求换枪")
	# 界面：背上的枪显示名称与换枪键；背枪模型显示对应类型。
	view_run.combat.weapons[0]=view_run.Combat.gun("smg");view_run.combat.backups[0]=view_run.Combat.gun("shotgun")
	game.sync_view();game.update_journey_ui()
	check(game.weapon_detail.text.contains("背后：霰弹枪"),"武器面板显示背后的枪")
	var back:Node3D=game.combat_view.back_guns[0]
	check(back.visible and back.get_node("shotgun").visible and not back.get_node("smg").visible,"背上显示霰弹枪模型")
	var gun:Node3D=game.combat_view.guns[0]
	check(back.global_position.distance_to(gun.global_position)>0.3,"背枪与手上的枪分开")
	view_run.combat.backups[0]={}
	game.sync_view()
	check(not back.visible,"背上没枪时隐藏背枪模型")
	# 触屏：换枪按钮在右半屏。
	var circles:Dictionary=game.touch.action_circles()
	check(circles.has("swap") and circles.swap.x-circles.swap.z>game.get_viewport().get_visible_rect().size.x/2,"触屏换枪按钮在右半屏")
	for p in game.sfx.players:p.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("JOURNEY_DUAL_WEAPON failures=",failures)
	quit(1 if failures else 0)
