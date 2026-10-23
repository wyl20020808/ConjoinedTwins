extends SceneTree

const Journey=preload("res://scripts/journey_run.gd")
var failures: Array[String]=[]
var checks:=0
var output:="D:/ConjoinedTwins-task-temp/minimal-hud-evidence/"

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		printerr("FAIL ",message)

func isolated():
	var run=Journey.new()
	run.journey_events.clear();run.rewards.clear();run.charge_gates.clear();run.select_charge_gate()
	run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear()
	run.combat=run.Combat.fresh();run.state="running";run.clear_input=false
	return run

func ticks(run, count: int) -> void:
	for n in range(count): run.step(run.FIXED_STEP)

func _initialize() -> void:
	call_deferred("validate")

func validate() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	# 静态陷阱必须通过生产固定步伤人，且只扣命中角色。
	var run=isolated()
	run.add_hazard("spikes",Rect2(-60,-10,35,30))
	ticks(run,1)
	check(run.combat.health==[80,100] and run.state=="running","地刺接触扣20血，存活并保留另一角色血量")
	ticks(run,60)
	check(run.combat.health==[80,100],"持续重叠半秒不连扣")
	run.pause();var paused: Dictionary=run.combat.duplicate(true);ticks(run,240)
	check(run.combat==paused,"暂停冻结伤害及冷却")
	run.pause();run.clear_input=false;ticks(run,62)
	check(run.combat.health==[60,100],"停留超过一秒再次扣血")
	run.capture_checkpoint();var saved: Dictionary=run.combat.duplicate(true)
	run.combat.health[0]=1;run.fail_threat("存档核验")
	check(run.restore_checkpoint() and run.combat==saved,"存档恢复血量和接触冷却")
	run.dispose()

	for fixture in [["steam",2.1,15],["piston",.9,45],["press",2.1,80]]:
		run=isolated();var trap: int=run.add_hazard(fixture[0],Rect2(-65,220,45,40))
		run.hazard_specs[trap].trigger=0;run.elapsed=fixture[1]
		run.a.position=Vector2(-42,240);run.b.position=Vector2(65,240)
		run.rope.reset(run.a.position,run.b.position);ticks(run,1)
		check(run.combat.health[0]==100-fixture[2] and run.state=="running",fixture[0]+"实际激活阶段固定步扣血")
		run.dispose()

	run=isolated();run.add_hazard("spikes",Rect2(-60,-10,35,30))
	run.heights=[60.0,60.0];ticks(run,1)
	check(run.combat.health==[100,100],"跳过地刺保留高度碰撞规则")
	run.dispose()

	run=isolated();var index: int=run.add_hazard("hammer",Rect2(-20,220,40,40))
	# 锤头处于最低点，两个角色分别位于锤头两侧，真实扫掠同时命中。
	run.a.position=Vector2(-18,240);run.b.position=Vector2(18,240)
	run.rope.reset(run.a.position,run.b.position);ticks(run,1)
	check(run.combat.health==[20,20] and run.state=="running","真实摆锤扫掠对双方各扣80血，同帧绳段不重复扣")
	run.hazard_contact(index,0,"")
	check(run.combat.health==[20,20],"多分部命中共用同一机关冷却")
	run.elapsed+=1.01;run.hazard_contact(index,0,"")
	check(run.combat.health[0]==0 and run.state=="failed","累计重伤耗尽血量后才共同重试")
	run.dispose()

	# 多类型均接入同一生产回调；护盾、绳段和另一个角色分别核验。
	for kind in ["steam","shuttle","piston","press","forklift","stone_ball","rocket"]:
		run=isolated();index=run.add_hazard(kind,Rect2(-20,200,40,40))
		run.hazard_contact(index,1,"")
		check(run.combat.health==[100,100-run.Combat.HAZARD_DAMAGE[kind]],kind+"按类型扣中02")
		run.dispose()
	run=isolated();index=run.add_hazard("steam",Rect2(-20,200,40,40));run.shield=true
	run.hazard_contact(index,-1,"")
	check(run.combat.health==[100,100] and not run.shield and run.shield_uses==1,"护盾吸收绳段传导，团队保护仍生效")
	run.elapsed+=1.01;run.hazard_contact(index,-1,"")
	check(run.combat.health==[85,85],"保护结束后绳段接触双方各扣15")
	var fingerprint: int=run.sync_hash();run.combat.hits["probe:0"]=run.elapsed
	check(run.sync_hash()!=fingerprint,"接触冷却纳入联机指纹")
	run.dispose()

	for kind in ["tree","cart","swing"]:
		run=isolated();run.add_event(kind,300,-1)
		var event: Dictionary=run.journey_events[0]
		event.phase="active";event.sample=Rect2(run.a.position-Vector2(12,12),Vector2(24,24));event.previous=event.sample;event.bottom=0;event.top=160
		run.check_event_hits([run.a.position,run.b.position])
		check(run.combat.health[0]==100-run.Combat.HAZARD_DAMAGE[kind] and run.state=="running",kind+"真实事件接触改为扣血")
		run.dispose()

	# 同样输入和危险连续推进，伤害、冷却、暂停和恢复不破坏确定性。
	var first=isolated();var second=isolated()
	for replica in [first,second]:
		replica.seed_value=8123;replica.add_hazard("spikes",Rect2(-60,-10,35,30))
	for frame in range(150):
		first.step(first.FIXED_STEP);second.step(second.FIXED_STEP)
	check(first.sync_hash()==second.sync_hash() and first.combat.health==[60,100],"双模拟固定步血量与冷却一致")
	first.dispose();second.dispose()
	await validate_hud()
	var receipt:={"checks":checks,"failures":failures,"renderer":DisplayServer.get_name(),"user_playtest":"pending","controller_tests":[]}
	var file:=FileAccess.open(output+"result-"+DisplayServer.get_name()+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("HUD DAMAGE CHECKS ",checks," FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)

func validate_hud() -> void:
	# 独立视口提供精确像素尺寸，避免隐藏父窗口固定分辨率伪装手机截图。
	var surface:=SubViewport.new()
	surface.size=Vector2i(1280,720)
	surface.own_world_3d=true
	surface.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(surface)
	var game=load("res://scenes/journey.tscn").instantiate()
	surface.add_child(game);game.set_physics_process(false)
	await process_frame
	game.run.state="running";game.run.combat.weapons[0]=game.run.Combat.gun()
	game.run.combat.weapons[0].ammo=7;game.run.combat.health=[64,28]
	for size in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844)]:
		surface.size=size
		game.touch_device=size.x!=1280
		for frame in range(3):
			game.update_journey_ui();await process_frame
		game.sync_view();await process_frame
		var viewport: Vector2=game.get_viewport().get_visible_rect().size
		check(viewport==Vector2(size),"验证视口实际像素尺寸 "+str(size))
		check(game.health_panel.position.x<viewport.x/2 and game.combat_health.value==64 and game.partner_health.value==28,"左上两人血条 "+str(size))
		check(game.weapon_panel.position.x>viewport.x/2 and game.combat_status.text=="冲锋枪" and game.weapon_ammo.text=="07 / 72","右上枪名及弹药 "+str(size))
		check(game.weapon_icon.visible and not game.combat_status.visible and game.weapon_icon.texture!=null,"枪形图标替代可见枪名 "+str(size))
		check(game.health_panel.get_theme_stylebox("panel") is StyleBoxFlat and game.weapon_panel.get_theme_stylebox("panel") is StyleBoxFlat,"两角HUD使用暗色玻璃底板 "+str(size))
		check(game.health_panel.get_global_rect().end.x<game.pause_button.position.x and game.pause_button.get_global_rect().end.x<game.weapon_panel.position.x,"两角状态不与暂停控件重叠 "+str(size))
		check(game.weapon_panel.get_global_rect().end.x<=viewport.x and game.health_panel.get_global_rect().end.y<viewport.y*.3,"HUD在视口内且高度收敛 "+str(size))
		check(not game.journey_hint.visible and game.pause_button.text.is_empty(),"游玩无常驻说明和暂停文字 "+str(size))
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var rendered: Image=surface.get_texture().get_image()
			check(rendered.get_size()==size and rendered.save_png(output+"hud-%dx%d.png"%[size.x,size.y])==OK,"保存实际渲染 "+str(size))
	game.run.combat.weapons[0].reload=120;game.update_journey_ui()
	check(game.weapon_detail.text=="换弹 1.0 秒","换弹仅在发生时显示")
	game.run.combat.weapons[0]={};game.update_journey_ui()
	check(game.combat_status.text=="空手" and game.weapon_ammo.text.is_empty(),"丢枪后清空弹药")
	game.run.combat.weapons[0]=game.run.Combat.gun()
	game.run.combat.weapons[0].ammo=0;game.run.combat.weapons[0].reserve=0;game.update_journey_ui()
	check(game.weapon_detail.text=="弹药耗尽","无弹药时显示必要反馈")
	game.play_mode="online";game.net.in_match=true;game.net.role=1;game.update_journey_ui()
	check(game.combat_health.value==28 and game.partner_health.value==64 and game.hud.text.begins_with("02"),"联机02视角正确交换血量")
	game.run.state="rescue";game.run.rescue={"progress":.5,"time":1.0};game.update_journey_ui()
	check(game.journey_hint.visible and game.journey_hint.text.contains("救援"),"救援保留必要提示")
	game.run.state="paused";game.update_journey_ui()
	check(game.panel.visible and not game.health_panel.visible and not game.weapon_panel.visible,"暂停菜单独占显示")
	game.net.in_match=false;surface.queue_free();await process_frame
	await create_timer(.15).timeout
