extends SceneTree

const Journey=preload("res://scripts/journey_run.gd")
var failures: Array[String]=[]
var checks := 0

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		printerr("FAIL ",message)

func isolated():
	var run=Journey.new()
	run.journey_events.clear()
	run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear()
	run.charge_gates.clear();run.select_charge_gate();run.rewards.clear()
	run.combat=run.Combat.fresh()
	run.state="running";run.clear_input=false
	return run

func ticks(run, count: int, move: Vector2=Vector2.ZERO) -> void:
	for n in range(count): run.step(run.FIXED_STEP,move,move)

func _initialize() -> void:
	call_deferred("validate")

func validate() -> void:
	var run=isolated()
	run.Combat.add_pickup(run,"gun",run.a.position)
	ticks(run,1)
	check(not run.combat.weapons[0].is_empty() and run.combat.weapons[1].is_empty(),"nearest player alone picks gun")
	check(run.combat.pickups.is_empty(),"pickup consumed once")
	var weapon: Dictionary=run.combat.weapons[0]
	run.add_event("boar",240,-0.336)
	run.set_combat_input(true)
	ticks(run,41)
	check(run.journey_events[0].hp==0 and run.combat.kills==1,"auto target: three shots defeat boar")
	check(weapon.ammo==21,"shooting consumes one bullet per shot")
	ticks(run,1)
	check(run.journey_events[0].phase=="spent","dead enemy cannot attack again")
	run.set_combat_input(false,true)
	ticks(run,1)
	check(weapon.reload==168,"R request begins 1.4 second reload")
	var health_before: Array=run.combat.health.duplicate()
	var frozen_reload: int=weapon.reload
	run.pause();ticks(run,30)
	check(weapon.reload==frozen_reload and run.combat.health==health_before,"pause freezes combat")
	run.pause();ticks(run,168)
	check(weapon.ammo==24 and weapon.reserve==69 and weapon.reload==0,"reload conserves ammunition")
	weapon.ammo=1
	run.set_combat_input(true);ticks(run,1)
	check(weapon.ammo==0 and weapon.reload==168,"empty magazine automatically reloads")
	run.set_combat_input(false,false,true);ticks(run,1)
	check(run.combat.weapons[0].is_empty(),"G drops weapon and cancels reload")
	check(run.combat.pickups.size()==1 and run.combat.pickups[0].weapon.reload==0,"ground gun preserves ammunition, no background reload")
	ticks(run,30)
	check(run.combat.weapons[0].is_empty(),"thrower cannot immediately pick gun back up")
	run.b.position=run.a.position+Vector2(25,0)
	run.rope.reset(run.a.position,run.b.position)
	ticks(run,1)
	check(not run.combat.weapons[1].is_empty(),"partner can take dropped gun during thrower lock")
	run.dispose()

	# 同一真实攻击不重复扣血；不同攻击受独立角色无敌和团队护盾约束。
	run=isolated()
	run.add_event("boar",800,1)
	var enemy: Dictionary=run.journey_events[0]
	enemy.phase="active";enemy.sample=Rect2(run.a.position-Vector2(15,15),Vector2(30,30));enemy.previous=enemy.sample;enemy.top=34
	run.check_event_hits([run.a.position,run.b.position])
	check(run.state=="running" and run.combat.health[0]==80,"real boar collision loses health instead of immediate failure")
	for n in range(20): run.check_event_hits([run.a.position,run.b.position])
	check(run.combat.health[0]==80,"persistent overlap deals damage once")
	run.elapsed+=1
	run.shield=true
	run.Combat.hit(run,0,"second")
	check(not run.shield and run.shield_uses==1 and run.combat.health[0]==80,"shield absorbs combat damage")
	run.Combat.hit(run,1,"third")
	check(run.combat.health[1]==100,"shield grants one second team immunity")
	run.elapsed+=2
	run.combat.health[0]=20
	run.Combat.hit(run,0,"lethal")
	check(run.state=="failed" and run.combat.health[0]==0,"zero health triggers shared checkpoint failure")
	run.dispose()

	run=isolated()
	run.Combat.add_pickup(run,"medkit",run.a.position)
	ticks(run,1)
	check(run.combat.pickups.size()==1,"full health leaves medical pickup")
	run.combat.health[0]=80;ticks(run,1)
	check(run.combat.health[0]==100 and run.combat.pickups.is_empty(),"medical pickup restores 30 capped at 100")
	run.Combat.add_pickup(run,"ammo",run.a.position);ticks(run,1)
	check(run.combat.pickups.size()==1,"empty hands leave ammunition pickup")
	run.combat.weapons[0]=run.Combat.gun();ticks(run,1)
	check(run.combat.weapons[0].reserve==120,"ammo pickup refills owned gun")
	run.combat.weapons[0].reserve=144
	run.Combat.add_pickup(run,"ammo",run.a.position);ticks(run,1)
	check(run.combat.pickups.size()==1,"full reserve leaves ammunition pickup")
	run.capture_checkpoint()
	var saved: Dictionary=run.checkpoint.run.combat.duplicate(true)
	run.combat.health[0]=1;run.combat.weapons[0].ammo=0;run.combat.pickups.clear()
	run.fail_threat("test checkpoint")
	check(run.restore_checkpoint(),"restore combat checkpoint")
	check(run.combat.health==saved.health and run.combat.weapons==saved.weapons and run.combat.pickups==saved.pickups,"checkpoint restores health, ammo, pickup identities")
	var before_hash: int=run.sync_hash()
	run.combat.weapons[0].ammo-=1
	check(run.sync_hash()!=before_hash,"combat state changes sync fingerprint")
	run.dispose()

	# 实体遮挡、前方扇区、目标稳定、同帧双人命中不会重复击杀。
	run=isolated()
	run.combat.weapons[0]=run.Combat.gun()
	run.add_event("boar",250,-0.336)
	run.add_event("boar",270,0.2)
	var first: Dictionary=run.journey_events[0]
	check(run.Combat.select_target(run,0,-1).id==first.id,"nearest visible enemy targeted")
	var retained: int=run.journey_events[1].id
	check(run.Combat.select_target(run,0,retained).id==retained,"valid target retained")
	run.add_hazard("cargo",Rect2(-80,100,80,50))
	check(not run.Combat.visible_target(run,0,first),"high solid blocks bullet line")
	check(run.Combat.blind_shot_end(run,run.a.position,run.a.position+Vector2(0,400),36).y==100,"untargeted bullet trail also stops at solid")
	run.obstacles[0].position.x=1000
	run.add_gate(100,false,"test_gate")
	check(not run.Combat.visible_target(run,0,first),"closed gate blocks bullet line")
	run.charge_gates[0].open=true
	check(run.Combat.visible_target(run,0,first),"open gate allows shot")
	run.journey_events[0].sample.position.y=-200
	check(not run.Combat.visible_target(run,0,first),"enemy behind player not auto targeted")
	run.dispose()

	# 使用生产固定步验证持枪速度与丢枪恢复，不仅检查倍率常量。
	run=isolated();run.combat.weapons[0]=run.Combat.gun();run.combat.weapons[1]=run.Combat.gun()
	ticks(run,120,Vector2.UP*-1)
	check(absf(run.a.position.y-136)<0.5,"held gun moves 6.8 metres per second")
	run.Combat.drop_weapon(run,0);run.Combat.drop_weapon(run,1);run.combat.pickups.clear()
	var start: float=run.a.position.y
	ticks(run,120,Vector2(0,1))
	check(absf(run.a.position.y-start-160)<0.5,"dropping gun restores eight metres per second")
	run.dispose()

	run=isolated();run.solo_control=true
	for n in range(120): run.step(run.FIXED_STEP,Vector2.RIGHT)
	check(run.a.position.x>80 and run.state=="running","companion does not swap sides and block crossing road centre")
	run.dispose()

	run=isolated();run.solo_control=true
	run.add_gate(1000,false,"solo_charge")
	run.a.position=Vector2(-73,1010);run.b.position=Vector2(0,1010)
	run.rope.reset(run.a.position,run.b.position)
	ticks(run,240)
	check(run.charge_gates[0].open,"companion walks to opposite charging zone without teleport")
	run.dispose()

	await scene_and_touch()
	print("COMBAT CHECKS ",checks," FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)

func touch_event(control, index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index=index;event.position=point;event.pressed=pressed
	control._input(event)

func scene_and_touch() -> void:
	var game=load("res://scenes/combat_trial.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	check(game.run.combat_trial and game.run.solo_control,"training scene uses single player controls")
	var font: Font=load("res://assets/fonts/web_ui_font.tres")
	var missing := ""
	for character in "射击跳跃换弹丢弃冲锋枪弹药医疗血量生命搭档锁定":
		if not font.has_char(character.unicode_at(0)): missing+=character
	check(missing.is_empty(),"bundled web font covers new combat labels: "+missing)
	game.journey_primary();game.run.clear_input=false
	game.run.combat.weapons[0]=game.run.Combat.gun()
	game.run.combat.weapons[0].ammo=5
	var start: Vector2=game.run.a.position
	var event := InputEventKey.new()
	event.keycode=KEY_R;event.pressed=true
	game._unhandled_key_input(event)
	game._physics_process(game.run.FIXED_STEP)
	check(game.run.combat.weapons[0].reload>0 and game.run.a.position==start,"R reloads without restarting level")
	event.keycode=KEY_G;game._unhandled_key_input(event)
	game._physics_process(game.run.FIXED_STEP)
	check(game.run.combat.weapons[0].is_empty(),"G reaches production input path")
	game.run.combat.weapons[0]=game.run.Combat.gun()
	var mouse := InputEventMouseButton.new()
	mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true
	Input.parse_input_event(mouse);Input.flush_buffered_events()
	game._physics_process(game.run.FIXED_STEP)
	check(game.run.combat.weapons[0].ammo==23,"mouse left button fires through production input path")
	game.run.pause();game.clear_controls();game.run.pause()
	game._physics_process(game.run.FIXED_STEP)
	check(game.run.combat.weapons[0].ammo==23,"held mouse cannot fire after pause until released")
	var release := InputEventMouseButton.new()
	release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
	Input.parse_input_event(release);Input.flush_buffered_events()
	game.touch_device=true
	game.touch.set_enabled(true)
	var circles: Dictionary=game.touch.action_circles()
	for action in circles:
		check(circles[action].x-circles[action].z>game.get_viewport().get_visible_rect().size.x/2,"all action buttons on right: "+action)
	check(circles.fire.z>circles.reload.z and circles.jump.z>circles.drop.z,"primary buttons larger than secondary buttons")
	var fire := Vector2(circles.fire.x,circles.fire.y)
	var jump := Vector2(circles.jump.x,circles.jump.y)
	touch_event(game.touch,0,Vector2(100,500),true)
	var drag := InputEventScreenDrag.new()
	drag.index=0;drag.position=Vector2(150,450);game.touch._input(drag)
	touch_event(game.touch,1,fire,true)
	touch_event(game.touch,2,jump,true)
	check(game.touch.move!=Vector2.ZERO and game.touch.take_jump() and game.touch.take_combat().fire,"three fingers support move, shoot and jump together")
	touch_event(game.touch,1,Vector2(600,200),false)
	touch_event(game.touch,2,jump,false)
	check(not game.touch.take_combat().fire and not game.touch.take_jump(),"release outside fire button clears held action")
	touch_event(game.touch,3,Vector2(900,250),true)
	check(not game.touch.take_jump(),"empty right area does not jump")
	var reload := Vector2(circles.reload.x,circles.reload.y)
	touch_event(game.touch,4,reload,true);touch_event(game.touch,4,reload,false)
	check(game.touch.take_combat().reload and not game.touch.take_combat().reload,"quick reload tap consumed once")
	game.clear_controls()
	check(game.touch.move==Vector2.ZERO and not game.touch.take_combat().fire,"state transition clears touch and combat input")
	game.run.combat.weapons[0]=game.run.Combat.gun()
	game.run.add_event("boar",250,-0.336)
	game.run.set_combat_input(true)
	game.run.step(game.run.FIXED_STEP)
	game.sync_view()
	check(game.combat_view.guns[0].visible,"held weapon has actual scene representation")
	check(game.combat_status.text.contains("冲锋枪"),"HUD displays gun and ammunition")
	for size in [Vector2i(720,1280),Vector2i(1024,768),Vector2i(1280,720)]:
		root.size=size
		await process_frame
		game.sync_view()
		var viewport: Vector2=game.get_viewport().get_visible_rect().size
		for circle: Vector3 in game.touch.action_circles().values():
			check(circle.x-circle.z>=viewport.x/2 and circle.x+circle.z<=viewport.x and circle.y+circle.z<=viewport.y,"responsive touch circle inside right half "+str(size))
		check(game.panel.size.x<=viewport.x,"menu fits viewport "+str(size))
	game.run.state="settlement";game.run.confirmations=[false,false];game.run.confirmation_held=[true,true]
	game.journey_primary()
	check(game.run.level_index==1 or game.run.state=="complete","single player can confirm settlement without second keyboard")
	game.queue_free()
	await process_frame
	# 音频服务异步释放播放句柄，退出前给实际服务一个混音周期。
	await create_timer(0.15).timeout
