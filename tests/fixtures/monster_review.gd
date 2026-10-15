extends Node
# 仅跳转观察点以审查真实渲染，不作为通关证据。命中和换弹使用生产固定步。
var game
func _ready()->void:
	game=load("res://scenes/journey.tscn").instantiate();game.incremental_loading=true;add_child(game)
	while not game.scene_prepared:await get_tree().process_frame
	game.set_physics_process(false);game.set_process(false);game.web_test_mode=true
	for spec in [[0,"briar","forest"],[0,"raider","village"],[2,"sentinel","mine"]]:
		game.run.level_index=spec[0];game.run.retry();game.reset_journey_views();game.run.state="running";game.run.clear_input=false
		var enemy:Dictionary={}
		# 从实际生成列表选取一只正前方有空地、枪线无遮挡的怪物。
		for e in game.run.journey_events:
			if e.kind!="monster" or e.archetype!=spec[1] or game.run.theme_at(e.y-250)!=spec[2]:continue
			var point:Vector2=e.origin-Vector2(0,250)
			if not game.run.Monsters.safe_spawn(game.run,point):continue
			if not game.run.Combat.line_of_sight(game.run,point,e.origin,36,38):continue
			enemy=e;break
		assert(not enemy.is_empty())
		game.run.a.position=enemy.origin-Vector2(0,250);game.run.b.position=game.run.a.position+Vector2(56,0)
		game.run.distance=game.run.a.position.y;game.run.elapsed=10.0
		game.run.rope.reset(game.run.a.position,game.run.b.position)
		for gate in game.run.charge_gates:
			gate.open=gate.receiver.y<game.run.distance-180;gate.opened_at=0.0 if gate.open else -1.0
		game.run.select_charge_gate();game.run.combat.weapons[0]=game.run.Combat.gun()
		while not game.prepare_journey_frame():await get_tree().process_frame
		game.run.step(game.run.FIXED_STEP)
		for e in game.run.journey_events:
			if e.id==game.run.combat.weapons[0].target:enemy=e;break
		assert(enemy.kind=="monster" and enemy.archetype==spec[1])
		game.sync_view();await capture(spec[2]+"-ready",enemy)
		game.run.set_combat_input(true);game.run.step(game.run.FIXED_STEP)
		game.run.set_combat_input(false);game.sync_view();await capture(spec[2]+"-hit",enemy)
		game.run.set_combat_input(true)
		for n in range(100):
			if enemy.hp<=0:break
			game.run.step(game.run.FIXED_STEP)
		game.run.set_combat_input(false);game.sync_view();await capture(spec[2]+"-defeat",enemy)
	JavaScriptBridge.eval("window.__monsterDone=true",true)
func capture(name:String,enemy:Dictionary)->void:
	await get_tree().create_timer(.3).timeout
	JavaScriptBridge.eval("window.__monsterShot="+JSON.stringify({"name":name,"hp":enemy.hp,"max_hp":enemy.max_hp,"phase":enemy.phase,"state":game.run.state,"target":game.run.combat.weapons[0].target,"enemy":enemy.id,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}),true)
	await get_tree().create_timer(1.2).timeout
