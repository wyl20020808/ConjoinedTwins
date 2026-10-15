extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures.append(label);printerr("FAIL ",label)
func isolated():
	var run=Journey.new()
	run.journey_events.clear();run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear()
	run.charge_gates.clear();run.select_charge_gate();run.rewards.clear();run.combat=run.Combat.fresh()
	run.state="running";run.clear_input=false
	return run
func ticks(run,count:int)->void:
	for n in range(count):run.step(run.FIXED_STEP,Vector2.ZERO,Vector2.ZERO)
func _initialize()->void:call_deferred("verify")
func verify()->void:
	for chapter in range(3):
		var run=Journey.new();run.level_index=chapter;run.retry()
		var monsters:Array=run.journey_events.filter(func(e):return e.kind=="monster")
		check(monsters.size()>=25,"chapter %d populated"%chapter)
		var themes:={}
		for event in monsters:
			check(run.Monsters.safe_spawn(run,event.origin),"monster on safe ground away from gates")
			themes[event.archetype]=true
		check((themes.has("briar") and themes.has("raider")) if chapter==0 else not themes.is_empty(),"regional archetypes")
		print("MONSTER LAYOUT ",chapter," count=",monsters.size()," themes=",themes.keys()," ammo=",run.combat.pickups.filter(func(p):return p.kind=="ammo").size())
		run.dispose()
	var run=isolated()
	var first:Dictionary=run.Monsters.add(run,Vector2(-42,220),"forest")
	var second:Dictionary=run.Monsters.add(run,Vector2(42,260),"village")
	run.combat.weapons[0]=run.Combat.gun();ticks(run,1)
	check(run.combat.weapons[0].target==first.id and first.hp==30,"auto lock without auto fire")
	run.set_combat_input(true);ticks(run,41)
	check(first.hp==0 and run.combat.kills==1,"three bullets kill forest enemy")
	ticks(run,1)
	check(run.combat.weapons[0].target==second.id,"dead target switches to next visible enemy")
	ticks(run,80)
	check(second.hp==0 and run.combat.kills==2,"four bullets kill village enemy")
	check(run.combat.weapons[0].ammo==17,"seven hits consume seven bullets")
	run.set_combat_input(false);ticks(run,600)
	check(run.combat.health==[100,100] and first.phase=="spent","dead enemies never attack or revive")
	run.dispose()
	run=isolated();first=run.Monsters.add(run,Vector2(-42,220),"forest")
	run.combat.weapons[0]=run.Combat.gun();run.add_hazard("cargo",Rect2(-100,110,120,30))
	run.set_combat_input(true);ticks(run,41)
	check(first.hp==30 and run.combat.weapons[0].target==-1,"solid blocks targeting and damage")
	check(first.trigger<0,"enemy does not acquire through cover")
	run.dispose()
	run=isolated();first=run.Monsters.add(run,Vector2(-42,220),"forest")
	run.add_hazard("rail",Rect2(-100,110,120,12));run.combat.weapons[0]=run.Combat.gun()
	ticks(run,1);check(run.combat.weapons[0].target==first.id,"low rail leaves raised gun line clear")
	run.dispose()
	run=isolated();first=run.Monsters.add(run,Vector2(-42,220),"forest")
	ticks(run,1)
	check(first.phase=="warning" and run.combat.health==[100,100],"enemy gives harmless warning before attack")
	var landing:Vector2=first.landing
	var frozen:Dictionary=first.duplicate(true);run.pause();ticks(run,300)
	check(first==frozen and run.combat.health==[100,100],"pause freezes warning and damage")
	run.pause();ticks(run,230)
	check(run.combat.health==[85,100],"one actual falling attack hits once for 15")
	ticks(run,480)
	check(run.combat.health==[70,100] and first.attack_seq==2,"cooldown permits a second distinct attack")
	check(run.combat.hits.size()<=2,"repeated attack deduplication stays bounded")
	check(first.landing==landing,"attack targets are deterministic")
	run.capture_checkpoint();var saved:Dictionary=first.duplicate(true)
	run.combat.weapons[0]=run.Combat.gun();run.set_combat_input(true);ticks(run,41)
	check(first.hp==0,"enemy changed after saved checkpoint")
	run.fail_threat("测试恢复")
	check(run.restore_checkpoint(),"failed run actually restores checkpoint")
	check(run.journey_events[0]==saved,"checkpoint restores enemy health and exact attack phase")
	check(run.combat.health==[70,100],"checkpoint restores player health")
	run.dispose()
	# 预警之后离开落点，攻击不追踪；保留生产移动与命中判定。
	run=isolated();first=run.Monsters.add(run,Vector2(-42,220),"forest");ticks(run,1)
	landing=first.landing
	for n in range(210):run.step(run.FIXED_STEP,Vector2.DOWN,Vector2.DOWN)
	check(first.landing==landing and run.combat.health==[100,100],"moving away dodges locked landing")
	run.dispose()
	# 相同输入的两份真实模拟包含新怪物攻击、受击与击败，逐步比对完整状态指纹。
	var left=isolated();var right=isolated()
	for twin in [left,right]:
		twin.Monsters.add(twin,Vector2(-42,200),"forest")
		twin.Monsters.add(twin,Vector2(42,240),"village")
		twin.Monsters.add(twin,Vector2(-42,300),"mine")
		twin.combat.weapons[0]=twin.Combat.gun()
	var identical:=true
	for n in range(640):
		for twin in [left,right]:
			twin.set_combat_input(n%240<100,n==400)
			ticks(twin,1)
		identical=identical and left.sync_hash()==right.sync_hash()
	check(identical and left.combat.kills>0,"640 combat steps remain deterministic with live monsters")
	left.dispose();right.dispose()
	# 实际展示节点：血条、命中反馈、暂停、死亡回收与重新开始。
	var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
	game.set_physics_process(false);game.set_process(false);game.run.state="running"
	first=game.run.Monsters.add(game.run,Vector2(-42,220),"forest")
	game.run.combat.weapons[0]=game.run.Combat.gun();game.run.set_combat_input(true)
	ticks(game.run,1);game.sync_view()
	var view:Node3D=game.event_views[first.id]
	var bar:Node3D=view.get_node("EnemyHealth")
	check(bar.visible and is_equal_approx(bar.get_node("Fill").scale.x,2.0/3),"health bar shows actual damage fraction")
	check("锁定" in bar.get_node("Title").text,"target badge follows real weapon lock")
	check(view.get_node("HitBurst").visible and view.get_node("HitNumber").text=="-10","hit sparks and damage number")
	var pose:Transform3D=view.get_node("Monster").transform
	game.run.pause();ticks(game.run,30);game.sync_view()
	check(view.get_node("Monster").transform.is_equal_approx(pose),"pause keeps hit pose stable")
	game.run.pause();game.run.set_combat_input(true);ticks(game.run,40);game.sync_view()
	check(first.hp==0 and not bar.visible,"death hides health bar immediately")
	ticks(game.run,65);game.sync_view();check(not view.visible,"defeat animation ends and hides enemy")
	game.run.retry();game.reset_journey_views();game.sync_view()
	check(game.run.journey_events.all(func(e):return e.get("hp",1)>0),"retry creates fresh enemies")
	for player in game.sfx.players:player.stop()
	await create_timer(.15).timeout
	game.queue_free();await process_frame
	await create_timer(.2).timeout
	print("MONSTER CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
