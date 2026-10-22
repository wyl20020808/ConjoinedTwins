extends SceneTree
# 枪械手感：霰弹枪逐发装填与开火打断、取枪/捡枪冷却、动作记录与存档，
# 以及画面上换枪两段（收枪上背 → 从背上取枪）、捡枪、丢枪抛出、换弹左手与泵动。
const Journey=preload("res://scripts/journey_run.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:call_deferred("verify")

func steps(run,count:int)->void:
	for n in range(count):run.Combat.tick(run,[run.a.position,run.b.position])

func verify()->void:
	var run=Journey.new();run.retry();run.state="running"
	var Combat=run.Combat
	run.combat.pickups.clear();run.journey_events.clear()
	run.a.position=Vector2(-42,300);run.b.position=Vector2(42,300)
	# 霰弹枪逐发装填：起手 + 每发计时，装满或打光备弹为止。
	var shotgun:Dictionary=Combat.gun("shotgun")
	shotgun.ammo=3
	run.combat.weapons[0]=shotgun
	Combat.start_reload(run,0)
	check(shotgun.reload==60 and shotgun.reload_total==60,"首发装填含 0.17 秒起手")
	steps(run,60)
	check(shotgun.ammo==4 and shotgun.reserve==17 and shotgun.reload==40,"压进一发后接着装下一发")
	steps(run,40)
	check(shotgun.ammo==5,"每发 0.33 秒")
	# 弹仓有弹时扣扳机打断装填。
	run.combat.fire[0]=true;steps(run,1)
	check(shotgun.reload==0 and shotgun.ammo==4 and run.combat.shots[0].get("type","")=="shotgun","开火打断逐发装填")
	run.combat.fire[0]=false
	# 空仓：装满 6 发。
	shotgun.ammo=0;shotgun.cooldown=0;shotgun.reserve=18
	Combat.start_reload(run,0);steps(run,60+40*5)
	check(shotgun.ammo==6 and shotgun.reserve==12 and shotgun.reload==0,"空仓逐发装满 6 发")
	# 冲锋枪仍是整匣换弹，时长不变。
	var smg:Dictionary=Combat.gun("smg");smg.ammo=10
	run.combat.weapons[0]=smg
	Combat.start_reload(run,0)
	check(smg.reload==168 and smg.reload_total==168,"冲锋枪整匣换弹 1.4 秒")
	steps(run,168)
	# 换枪：0.55 秒内不能开火，并记录动作。
	run.combat.backups[0]=Combat.gun("launcher")
	run.combat.swap[0]=true;steps(run,1)
	var motion:Dictionary=run.combat.motion[0]
	check(motion.kind=="swap" and motion.from=="smg" and motion.to=="launcher","换枪记录收枪与取枪的枪种")
	check(Combat.SWAP_STEPS==66 and run.combat.weapons[0].cooldown>=Combat.SWAP_STEPS-2,"换枪 0.55 秒内不能开火")
	# 丢枪：记录丢下的拾取物与换上的枪。
	run.combat.drop[0]=true;steps(run,1)
	motion=run.combat.motion[0]
	check(motion.kind=="drop" and motion.from=="launcher" and motion.to=="smg" and int(motion.pickup)==run.combat.pickups[-1].id,"丢枪记录抛出的枪和换上的背枪")
	check(run.combat.weapons[0].cooldown>=Combat.DROP_DRAW_STEPS-2,"丢枪后取背枪 0.6 秒")
	# 捡枪：拿到手上 0.35 秒后才能开火；第二把背上不影响手上的枪。
	run.combat.weapons[0]={};run.combat.backups[0]={};run.combat.pickups.clear()
	Combat.add_pickup(run,"gun",run.a.position,{},"shotgun");steps(run,1)
	check(run.combat.motion[0].kind=="pickup" and run.combat.weapons[0].cooldown>=Combat.DRAW_STEPS-2,"捡枪拿到手上有取枪动作")
	Combat.add_pickup(run,"gun",run.a.position,{},"flamer");steps(run,1)
	check(run.combat.motion[0].kind=="stow" and run.combat.motion[0].to=="flamer","第二把枪甩到背上")
	# 存档恢复动作记录；旧数据自动补齐。
	run.capture_checkpoint()
	run.combat.motion[0]={}
	run.state="failed"
	check(run.restore_checkpoint() and run.combat.motion[0].get("kind","")=="stow","存档恢复动作记录")
	run.state="running"
	run.combat.erase("motion");steps(run,1)
	check(run.combat.motion==[{},{}],"旧战斗数据补齐动作记录")
	run.dispose()

	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.frame_delta=1.0/60
	var view=game.combat_view
	var vrun=game.run
	vrun.state="running"
	for n in range(4):await process_frame
	vrun.combat.weapons[0]=vrun.Combat.gun("smg");vrun.combat.backups[0]=vrun.Combat.gun("shotgun")
	game.sync_view()
	var gun:Node3D=view.guns[0]
	var back:Node3D=view.back_guns[0]
	var hold:Transform3D=gun.global_transform
	var back_rest:Transform3D=back.global_transform
	# Blender 动作片段已载入主角动作层。
	var rig=game.hero_rig(0)
	check(rig!=null and rig.clips.has("GunHolster") and rig.clips.has("GunReloadMag") and rig.clips.has("GunShellLoad"),"Blender 枪械动作片段载入主角")
	# 换枪前段：冲锋枪离开双手往背上收，霰弹枪还在背上。
	vrun.combat.swap[0]=true;vrun.Combat.tick(vrun,[vrun.a.position,vrun.b.position])
	vrun.elapsed+=0.12;game.sync_view()
	check(rig!=null and rig.action_clip=="GunHolster" and rig.action_weight>0.5,"收枪时上半身播放收枪片段（%s %.2f）"%[rig.action_clip if rig else "",rig.action_weight if rig else 0.0])
	check(gun.get_node("smg").visible and back.get_node("shotgun").visible,"收枪阶段：手上仍是冲锋枪，背上仍是霰弹枪")
	check(gun.global_position.distance_to(hold.origin)>0.1,"收枪阶段：枪离开持枪位置")
	vrun.elapsed+=0.13;game.sync_view()
	check(gun.global_position.distance_to(back_rest.origin)<0.25,"收枪到 0.25 秒时枪已贴到背上")
	vrun.elapsed+=0.15;game.sync_view()
	check(rig!=null and rig.action_clip=="GunDraw","取枪时上半身播放取枪片段")
	check(gun.get_node("shotgun").visible and back.get_node("smg").visible,"取枪阶段：霰弹枪从背上拿下，冲锋枪留在背上")
	vrun.elapsed+=0.2;game.sync_view()
	check(rig!=null and rig.action_weight<0.001,"动作结束后上半身层撤出")
	check(gun.get_node("shotgun").visible and gun.global_position.distance_to(view.guns[0].global_position)<0.001,"0.55 秒后取枪结束")
	# 丢枪：抛出的枪在空中，地上拾取物落地前隐藏。
	vrun.combat.drop[0]=true;vrun.Combat.tick(vrun,[vrun.a.position,vrun.b.position])
	var dropped:int=vrun.combat.motion[0].pickup
	vrun.elapsed+=0.1;game.sync_view()
	check(gun.visible and gun.get_node("shotgun").visible,"丢枪：枪在空中")
	check(view.pickup_views.has(dropped) and not view.pickup_views[dropped].visible,"丢枪：落地前地上不显示")
	vrun.elapsed+=0.25;game.sync_view()
	check(view.pickup_views[dropped].visible and gun.get_node("smg").visible,"丢枪：落地后显示，并从背上取冲锋枪")
	vrun.elapsed+=0.4;game.sync_view()
	# 换弹：左手离开护木去拿弹匣。
	var skeleton:Skeleton3D=game.hand_skeletons.get(0)
	var smg_now:Dictionary=vrun.combat.weapons[0]
	smg_now.ammo=0;vrun.Combat.start_reload(vrun,0)
	game.sync_view()
	smg_now.reload=int(168*0.48);game.sync_view()
	if is_instance_valid(skeleton):
		var left:Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin
		check(left.distance_to(gun.to_global(view.GRIP_LEFT))>0.2,"换弹：左手离开护木去弹袋")
	smg_now.reload=0;game.sync_view()
	# 霰弹枪泵动：开火后左手后拉护木。
	vrun.combat.weapons[0]=vrun.Combat.gun("shotgun")
	vrun.combat.shots[0]={"id":999,"type":"shotgun","from":vrun.a.position,"to":vrun.a.position+Vector2(0,100),"height":36.0,"target_height":36.0,"time":vrun.elapsed-0.28,"hit":false}
	game.sync_view()
	if is_instance_valid(skeleton):
		var left:Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin
		check(left.distance_to(gun.to_global(view.GRIP_LEFT))>0.08,"泵动：左手后拉护木")
	for p in game.sfx.players:p.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("JOURNEY_GUN_FEEL failures=",failures)
	quit(1 if failures else 0)
