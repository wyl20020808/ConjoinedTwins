extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
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
	# 相同输入时长下，斜向归一化和武器减速必须保留。
	for direction in [Vector2.DOWN,Vector2(1,1)]:
		var run=isolated();var start:Vector2=run.a.position
		for n in range(60):run.step(run.FIXED_STEP,direction,direction)
		check(absf(run.a.position.distance_to(start)-160)<.1,"unarmed runs 16 m/s including diagonal")
		check(run.actions[0]=="Run","movement selects running clip")
		run.dispose()
	var run=isolated()
	var enemy:Dictionary=run.Monsters.add(run,Vector2(-200,700),"forest")
	var start:Vector2=enemy.origin
	ticks(run,120)
	check(enemy.origin.distance_to(start)>180 and enemy.origin.distance_to(run.a.position)<start.distance_to(run.a.position),"distant enemy runs toward player")
	check(enemy.stride>0 and enemy.velocity.length()>100,"stride driven by actual movement")
	var frozen:Dictionary=enemy.duplicate(true);run.pause();ticks(run,120)
	check(enemy==frozen,"pause freezes navigation stride and attack")
	run.pause();run.clear_input=false
	run.capture_checkpoint();var saved:Dictionary=enemy.duplicate(true);ticks(run,80)
	run.fail_threat("pursuit restore test");check(run.restore_checkpoint(),"checkpoint restores")
	check(run.journey_events[0]==saved,"checkpoint restores pursuit position and path exactly")
	run.dispose()
	# 从两侧及后方加入，枪械必须能够还击，射线仍受实体遮挡。
	run=isolated();enemy=run.Monsters.add(run,Vector2(-160,-80),"village")
	check(run.Combat.visible_target(run,0,enemy),"flanking enemy can be targeted behind player")
	run.add_hazard("cargo",Rect2(-130,-60,50,50))
	check(not run.Combat.visible_target(run,0,enemy),"rear aim respects cover")
	run.dispose()
	# 在真实实体旁绕行；每步验证脚下支撑和连续移动，不能穿墙或瞬移。
	for kind in ["cargo","road_gap"]:
		run=isolated();run.add_hazard(kind,Rect2(-130,200,180,100))
		enemy=run.Monsters.add(run,Vector2(-42,470),"village")
		var safe:=true;var detoured:=false
		for n in range(480):
			var before:Vector2=enemy.origin;ticks(run,1)
			safe=safe and enemy.origin.distance_to(before)<=240*run.FIXED_STEP+.001
			safe=safe and not run.obstacles[0].grow(15).has_point(enemy.origin) and run.has_ground_support(enemy.origin)
			detoured=detoured or absf(enemy.origin.x+42)>100
		check(safe and detoured and enemy.origin.y<190,"enemy navigates around "+kind)
		run.dispose()
	run=isolated();run.add_gate(250,false,"blocker")
	enemy=run.Monsters.add(run,Vector2(-42,550),"mine");ticks(run,360)
	check(enemy.origin.y>run.charge_gates[0].door.end.y,"closed gate blocks pursuit")
	run.charge_gates[0].open=true;ticks(run,360)
	check(enemy.origin.y<250,"enemy resumes pursuit through opened gate")
	run.dispose()
	# 按最高跑速靠近真实吊桥，开门标记不能提前当作桥面支撑。
	run=isolated();run.add_gate(1000,true,"opening_bridge")
	preload("res://scripts/journey_encounters.gd").bridge(run,run.charge_gates[0])
	run.charge_gates[0].open=true;run.charge_gates[0].opened_at=0.0
	run.a.position=Vector2(-28,1046);run.b.position=Vector2(28,1046)
	run.distance=1046;run.rope.reset(run.a.position,run.b.position)
	for n in range(60):run.step(run.FIXED_STEP,Vector2.DOWN,Vector2.DOWN)
	check(run.state=="running" and run.a.position.y<=1166.01,"full speed waits before gap while drawbridge opens")
	for n in range(180):run.step(run.FIXED_STEP,Vector2.DOWN,Vector2.DOWN)
	check(run.state=="running" and run.a.position.y>1400,"running resumes across physically lowered bridge")
	run.dispose()
	# 固定输入下两个模拟包含移动、绕障、射击和攻击，完整指纹逐步一致。
	var left=isolated();var right=isolated()
	for twin in [left,right]:
		twin.add_hazard("cargo",Rect2(-130,200,180,100))
		twin.Monsters.add(twin,Vector2(-42,470),"forest")
		twin.Monsters.add(twin,Vector2(200,600),"village")
		twin.combat.weapons[0]=twin.Combat.gun()
	var identical:=true
	for n in range(600):
		for twin in [left,right]:
			twin.set_combat_input(n>200);ticks(twin,1)
		identical=identical and left.sync_hash()==right.sync_hash()
	check(identical,"600 navigation/combat steps deterministic")
	left.dispose();right.dispose()
	for chapter in range(3):
		run=Journey.new();run.level_index=chapter;run.retry()
		var count:int=run.encounter_markers.size()
		check(count>=[100,80,80][chapter],"dense chapter with cooperation approach zones "+str(chapter))
		var grouped:=true
		for n in range(1,count):
			var gap:float=run.encounter_markers[n].y-run.encounter_markers[n-1].y
			if gap<600:
				# 组内中拍允许零均值的 ±18 扰动；换侧边界仍须保留原来的 400。
				grouped=grouped and (absf(gap-80)<=18 or absf(gap-240)<=18 or gap==400)
				if run.encounter_markers[n].blocked!=run.encounter_markers[n-1].blocked:grouped=grouped and gap>=400
		check(grouped,"dense groups preserve 20 m side-change spacing")
		print("PURSUIT LAYOUT chapter=",chapter," encounters=",count," monsters=",run.journey_events.filter(func(e):return e.kind=="monster").size())
		run.dispose()
	# 使用生产展示节点，验证移动位置、腿部摆动与实际跑步动画倍率。
	var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
	game.set_physics_process(false);game.set_process(false);game.run.dispose();game.run=isolated()
	enemy=game.run.Monsters.add(game.run,Vector2(-42,500),"forest")
	ticks(game.run,60);game.sync_view()
	var actor:Node3D=game.event_views[enemy.id].get_node("Monster")
	check(absf(actor.global_position.z+enemy.origin.y/20)<.001,"visual follows actual pursuing position")
	var pose:Transform3D=actor.get_node("LeftLeg").transform
	ticks(game.run,20);game.sync_view()
	check(not actor.get_node("LeftLeg").transform.is_equal_approx(pose),"legs animate while running")
	game.run.step(game.run.FIXED_STEP,Vector2.DOWN,Vector2.DOWN);game.sync_view()
	check(game.animation_players[0].current_animation.ends_with("Run") and is_equal_approx(game.animation_players[0].speed_scale,2.2),"production running clip and doubled cadence")
	pose=actor.transform;game.run.pause();ticks(game.run,60);game.sync_view()
	check(actor.transform.is_equal_approx(pose) and game.animation_players[0].speed_scale==0,"pause freezes both visual locomotion paths")
	for player in game.sfx.players:player.stop()
	game.queue_free();await process_frame
	print("PURSUIT CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
