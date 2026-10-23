extends SceneTree
# CPU 回归门槛，不代表显卡帧率。必须串行运行，避免并行测试相互抢占。
const Journey=preload("res://scripts/journey_run.gd")
var failures:Array=[]
var report:={"kind":"headless CPU regression; not GPU acceptance", "resource_loading":"headless main-thread compatibility; native/Web keep background IO"}
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func stats(values:Array)->Dictionary:
	values.sort()
	return {"p50_usec":values[values.size()/2],"p95_usec":values[int(values.size()*.95)],"max_usec":values[-1]}
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var navigation:Array=[]
	# 在完整三章地图的不同位置持续更新敌人；不会因玩家死亡而跳过寻路。
	for chapter in range(3):
		for location in [0.0,6000.0,16000.0]:
			var run=Journey.new();run.level_index=chapter;run.retry()
			run.a.position=Vector2(-40,location);run.b.position=Vector2(40,location);run.distance=location
			var samples:Array=[]
			for frame in range(180):
				var started:=Time.get_ticks_usec()
				run.advance_events(run.FIXED_STEP)
				samples.append(Time.get_ticks_usec()-started)
				run.elapsed+=run.FIXED_STEP
			var cost:=stats(samples);cost.chapter=chapter;cost.location=location
			navigation.append(cost)
			check(cost.p95_usec<5000 and cost.max_usec<40000,"追击预算超限 chapter=%d location=%d: %s"%[chapter,location,cost])
			run.dispose()
	report.navigation=navigation
	Engine.max_fps=60
	var boot=load("res://scenes/journey_boot.tscn").instantiate();root.add_child(boot)
	var begun:=Time.get_ticks_msec()
	while not is_instance_valid(boot.game) or not boot.game.scene_prepared:
		if Time.get_ticks_msec()-begun>60000:
			check(false,"生产入口准备超时");boot.queue_free();await process_frame;finish();return
		await process_frame
	var game=boot.game
	# 固定 CPU 回归地图，避免随机开局改变每轮测量的敌群与碰撞拓扑。
	game.run.random_seed=false;game.run.seed_value=20261012;game.run.retry()
	game.run.state="paused";game.reset_journey_views()
	while not game.prepare_journey_frame():await process_frame
	game.web_verify=true;game.run.state="running"
	for frame in range(60):await process_frame
	game.frame_costs.clear()
	var measured_started:=Time.get_ticks_usec()
	for frame in range(180):await process_frame
	report.display={"frames":180,"wall_usec":Time.get_ticks_usec()-measured_started,"driver":DisplayServer.get_name(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	report.entry=game.frame_costs.duplicate(true)
	var simulation:Dictionary=game.frame_costs.get("simulation",{})
	var view:Dictionary=game.frame_costs.get("render_view",{})
	check(game.run.state=="running","必须测量真实运行状态，不能以死亡或暂停的空转冒充性能")
	check(simulation.get("samples",0)>=170 and simulation.get("samples",9999)<=270,"180 画面循环的物理回调必须在 170–270 内，防止追赶失控")
	check(simulation.get("total_usec",INF)/maxi(1,simulation.get("samples",0))<14000,"双固定步模拟平均 CPU 超过 14 ms")
	check(view.get("samples",0)>=170 and view.get("samples",9999)<=181,"本地展示必须每画面帧至多一次")
	check(Engine.max_physics_steps_per_frame==3,"本地长帧追赶上限必须保留")
	for player in game.sfx.players:player.stop()
	boot.queue_free()
	for frame in range(4):await process_frame
	# AudioServer 异步混音释放播放实例；与现有怪物展示测试一致，等一次音频收尾。
	await create_timer(.2).timeout
	finish()
func finish()->void:
	report.failures=failures;report.engine=Engine.get_version_info().string;report.cpu=OS.get_processor_name()
	var output:=OS.get_environment("JOURNEY_PERF_REPORT")
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file==null:check(false,"无法写入性能报告："+output)
		else:file.store_string(JSON.stringify(report,"\t"))
	print("JOURNEY_RUNTIME_BUDGET ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
