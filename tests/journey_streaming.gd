extends SceneTree
# 展示驻留测试会移动观察位置；不作为合法通关或真人输入验收。
const Journey=preload("res://scripts/journey_run.gd")
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.web_test_mode=true;game.incremental_loading=true
	check(game.run.random_seed,"生产入口默认启用随机种子")
	game.run.random_seed=false;game.run.seed_value=20261012;game.run.retry();game.run.state="paused"
	var logical_count:int=game.run.kinds.size()+game.run.journey_events.size()
	for location in [0.0,6000.0,16000.0,0.0]:
		game.run.distance=location;game.run.a.position.y=location;game.run.b.position.y=location
		var before:int=game.run.sync_hash()
		var waits:=0
		while waits<2000:
			var ready:bool=game.prepare_journey_frame()
			if ready and game.chunk_jobs.is_empty() and game.chunk_assets.pending.is_empty() and game.chunk_assets.active.is_empty():break
			waits+=1;await process_frame
		check(waits<2000,"附近资源预热可完成")
		game.sync_view();await process_frame
		check(game.run.sync_hash()==before,"模型创建卸载不改变模拟状态")
		check(game.run.kinds.size()+game.run.journey_events.size()==logical_count,"整章远处机关与动物逻辑完整保留")
		for event in game.run.journey_events:
			if not game.model_resident(event.y):check(not game.event_views.has(event.id),"远处动物与事件没有展示节点")
		for gate in game.run.charge_gates:
			if not game.model_resident(gate.receiver.y):check(not game.gate_views.has(gate.id),"远处合作门没有展示节点")
		for index in game.static_views:
			check(game.model_resident(game.hazard_view_y(index)),"机关模型仅驻留在安全迟滞窗口")
		for index in game.visual_hazard_candidates():
			if game.hazard_has_view(index) and game.model_visible(game.hazard_view_y(index)):
				if game.run.kinds[index]=="drone" and game.run.hazard_sample(index,game.run.elapsed).stage=="spent":continue
				check(game.static_views.has(index),"进入展示窗口前机关模型已经就绪: %d %s"%[index,game.run.kinds[index]])
		print("STREAMING location=",location," nodes=",get_node_count()," events=",game.event_views.size()," hazards=",game.static_views.size()," logical=",logical_count)
	# 固定静态布局在多个固定步中不能重新遍历建立整章空间索引。
	var run=Journey.new()
	run.obstacles_in_bounds(Rect2(-400,0,800,2400))
	var rebuilds:int=run.spatial_rebuilds
	for step in range(120):
		run.elapsed+=run.FIXED_STEP;run.obstacles_in_bounds(Rect2(-400,step*10,800,2400))
	check(run.spatial_rebuilds==rebuilds,"120 个固定步复用静态空间索引")
	var index:int=run.add_hazard("pillar",Rect2(0,100000,24,24))
	run.obstacles_in_bounds(Rect2(-400,0,800,2400))
	run.obstacles[index]=Rect2(0,100,24,24);run.elapsed+=run.FIXED_STEP
	check(run.obstacles_in_bounds(Rect2(-40,80,100,100)).has(index),"同类型实体位置变化使空间索引失效")
	run.dispose()
	# 清空/替换地图后，在时间尚未前进的预测查询中也不能沿用旧的塌陷索引。
	run=Journey.new()
	for items in [run.kinds,run.obstacles,run.hazard_specs,run.obstacle_ids,run.obstacle_heights]:items.clear()
	check(run.ground_gaps(.6).is_empty(),"同一时刻替换地图使缺口缓存失效")
	run.dispose()
	for player in game.sfx.players:player.stop()
	game.queue_free()
	for n in range(4):await process_frame
	await create_timer(.2).timeout
	print("JOURNEY_STREAMING checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
