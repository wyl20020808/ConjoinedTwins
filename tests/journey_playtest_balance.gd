extends SceneTree

const Journey=preload("res://scripts/journey_run.gd")
const ChapterBar=preload("res://scripts/journey_chapter_bar.gd")
const RandomLayout=preload("res://scripts/journey_random.gd")
var failures:=0
func check(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("FAIL ",message)
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	call_deferred("verify")

func verify()->void:
	var run=Journey.new()
	run.journey_events.clear();run.charge_gates.clear();run.select_charge_gate()
	run.obstacles.clear();run.kinds.clear();run.hazard_specs.clear();run.obstacle_ids.clear();run.obstacle_heights.clear()
	run.combat=run.Combat.fresh()
	var base_hp:={"briar":30,"raider":40,"sentinel":50,"archer":40,"dasher":60,"wolf":40,"root_spider":30,"goblin_bomber":35,"river_crab_knight":90}
	for kind in base_hp:
		var monster:Dictionary=run.Monsters.add(run,Vector2.ZERO,"forest",kind)
		check(monster.hp==roundi(base_hp[kind]*1.5) and monster.max_hp==monster.hp,"怪物血量增加约 50%%：%s"%kind)
	run.journey_events.clear()
	var layout=RandomLayout.new(123,0,2)
	var baseline=RandomLayout.new(123,0,2)
	var original:=0
	for wave in range(3):original+=int(baseline.draw("wave_size",[10,11,11,12]))
	var rotation:={"previous":""}
	for wave in range(3):run.Monsters.arena_wave(run,1000.0+wave*600,wave==2,layout,rotation,100.0)
	check(run.journey_events.size()==original-10,"每片怪物潮恰减十只")
	for count in [4,5]:check(run.Monsters.PACK_LANES[count].size()==count,"机关小队由 2/3 只增加到 4/5 只")
	run.journey_events.clear()
	run.Encounters.narrow_terrain(run,{"start":400.0,"end":840.0,"lanes":[0.0]})
	for x in [-30.0,0.0,30.0]:check(run.ground_sweep_supported(Vector2(x,600),Vector2(x,700),0.0),"单道桥横向偏移仍有完整脚下支撑：%s"%x)
	check(not run.has_ground_support(Vector2(80,600)),"单道桥边界仍可坠落")
	var solids:Array[Rect2]=[Rect2(-20,100,40,40),Rect2(60,200,40,80)]
	for y in range(0,900,20):
		for x in range(-300,301,20):
			var point:=Vector2(x,y)
			var expected:bool=absf(point.x)<=run.EDGE-run.Monsters.BODY_RADIUS
			for rect in solids:
				if run.segment_hits(point,point,rect):expected=false
			for offset in [Vector2.ZERO,Vector2(16,0),Vector2(-16,0),Vector2(0,16),Vector2(0,-16)]:
				if not run.has_ground_support(point+offset):expected=false
			check(run.Monsters.clear_path(run,point,point,solids)==expected,"寻路静止采样与原五点、闭区间线段判定一致")
	run.dispose()

	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	run=game.run
	game.application_focused=true
	run.state="running"
	game.pump_music(3.0,true)
	for frame in range(8):
		run.state="paused";game.pump_music(0.016,true)
		check(game.music_explore.stream_paused and game.music_combat.stream_paused,"连续暂停帧保持两层音乐冻结")
	run.state="running";game.pump_music(0.016,true)
	check(not game.music_explore.stream_paused and not game.music_combat.stream_paused,"恢复后两层音乐继续播放")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	for frame in range(8):game.pump_music(0.016,true)
	check(game.music_explore.stream_paused and game.music_combat.stream_paused,"失焦后持续静音")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	run.state="paused";game.pump_music(0.016,true)
	check(game.music_explore.stream_paused,"重新聚焦不会越过游戏暂停")
	run.state="running";game.pump_music(0.016,true)
	for kind in run.Combat.WEAPONS:
		run.combat.weapons[0]=run.Combat.gun(kind)
		game.update_journey_ui()
		check(game.weapon_caption.text==run.Combat.weapon_name(run.combat.weapons[0]),"武器名称随当前枪械刷新：%s"%kind)
	run.combat.weapons[0]={};game.update_journey_ui()
	check(game.weapon_caption.text=="空手","空手名称刷新")
	# 两次换阶段都用非默认资源验证恢复，避免只验证阶段号而遗漏弹药与血量。
	var fight:Dictionary=run.Boss.boss(run)
	fight.phase="fight"
	for stage in [1,2]:
		run.a.position=Vector2(-42,fight.arena+700);run.b.position=Vector2(42,fight.arena+700)
		run.rope.reset(run.a.position,run.b.position)
		run.combat.health=[71,43]
		run.combat.weapons=[run.Combat.gun("smg"),run.Combat.gun("shotgun")]
		run.combat.weapons[0].ammo=3;run.combat.weapons[0].reserve=21
		run.combat.weapons[1].ammo=2;run.combat.weapons[1].reserve=9
		fight.hp=int(fight.max_hp*(0.6 if stage==1 else 0.25))
		run.Boss.choose(run,fight)
		var saved:Dictionary=run.checkpoint.run.combat.duplicate(true)
		var positions:Array=[run.a.position,run.b.position]
		var hp:int=fight.hp
		run.combat.health=[0,5];run.combat.weapons[0].ammo=0
		run.a.position+=Vector2(20,30);fight.hp=1;run.state="failed"
		check(run.restore_checkpoint(),"阶段 %d 死亡后可恢复"%stage)
		fight=run.Boss.boss(run)
		check(fight.stage==stage and fight.hp==hp and fight.phase=="fight","阶段 %d 保留 Boss 战进度"%stage)
		check(run.combat==saved and [run.a.position,run.b.position]==positions,"阶段 %d 恢复双方非默认血量、子弹及位置"%stage)
	run.Combat.damage(run,fight,fight.max_hp*10)
	run.advance_events(run.FIXED_STEP)
	run.state="failed";check(run.restore_checkpoint() and run.Boss.boss(run).hp==0,"击败 Boss 后存档保留胜利")
	var bar=ChapterBar.new();root.add_child(bar)
	var boss:Dictionary=run.Boss.boss(run)
	boss.phase="dormant"
	check(ChapterBar.zone_names(run).back()=="???","Boss 出场前隐藏名称")
	boss.phase="intro"
	check(ChapterBar.zone_names(run).back()=="枯根巨像 Boss","Boss 出场后显示名称")
	bar.refresh(run,0.016,Rect2(0,0,700,4),true,false)
	check(bar.segments==7 and bar.zone_labels[6].visible,"第一章独立 Boss 终点段")
	check(is_equal_approx(bar.progress_fraction(run,boss.arena),6.0/7.0),"Boss 进度定位到终点段入口")
	# 第二、三章也有终点 Boss（烬翼魔龙、海神波塞冬），同样是独立终点段并显示各自名称。
	for chapter in [[1,"烬翼魔龙 Boss"],[2,"海神波塞冬 Boss"]]:
		run.level_index=chapter[0];run.retry()
		bar.refresh(run,0.016,Rect2(0,0,700,4),true,false)
		var later:Dictionary=run.Boss.boss(run)
		later.phase="intro"
		check(bar.segments==7 and ChapterBar.zone_names(run).back()==chapter[1],"第 %d 章独立 Boss 终点段与名称"%(chapter[0]+1))
		later.phase="dormant"
	game.frame_delta=1.0/60.0;run.state="running"
	game.journey_camera_returning=true
	game.camera.transform=game.camera_shot().translated(Vector3(8,4,6))
	for frame in range(60):game.update_journey_camera()
	check(not game.journey_camera_returning and game.camera.position.distance_to(game.camera_shot().origin)<0.01,"救援回镜在一秒内收敛")
	bar.queue_free();game.queue_free()
	for frame in range(4):await process_frame
	await create_timer(0.2).timeout
	print("PLAYTEST BALANCE failures=",failures)
	quit(1 if failures else 0)
