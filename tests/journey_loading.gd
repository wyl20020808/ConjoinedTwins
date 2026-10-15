extends SceneTree
var failures: Array = []
var report := {}
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("verify")
func verify() -> void:
	var started := Time.get_ticks_usec()
	var boot = load("res://scenes/journey_boot.tscn").instantiate()
	root.add_child(boot)
	report.loading_ui_usec=Time.get_ticks_usec()-started
	check(boot.overlay.visible and boot.game==null,"轻量加载页先于生产场景建立")
	for frame in range(10000):
		await process_frame
		if boot.game!=null and boot.game.scene_prepared: break
	check(boot.game!=null and boot.game.scene_prepared,"后台加载和分帧安装完成")
	if boot.game==null or not boot.game.scene_prepared: quit(1); return
	var game=boot.game
	game.set_physics_process(false)
	if OS.get_environment("JOURNEY_NO_WORKERS")=="1": game.parallel_chunk_plans=false
	var initial_plan_tasks: int=game.chunk_plan_tasks_started
	report.boot_wall_usec=Time.get_ticks_usec()-started
	check(game.run.elapsed==0 and game.run.distance==0,"首屏准备不消费模拟时间和移动")
	var calls: Array=[]
	var views: Array=[]
	var layouts := {}
	for chapter in range(3):
		game.run.level_index=chapter
		game.run.retry()
		game.reset_journey_views()
		for zone in range(6):
			game.run.distance=game.run.finish_distance()/6*zone+400
			var before: int=game.run.sync_hash()
			var ready:=false
			for poll in range(10000):
				started=Time.get_ticks_usec()
				ready=game.prepare_journey_frame()
				calls.append(Time.get_ticks_usec()-started)
				if ready: break
				await process_frame
			check(ready and before==game.run.sync_hash(),"区块准备不改变模拟 chapter=%d zone=%d"%[chapter,zone])
			var current:=int(game.run.distance/game.SCALE/game.CHUNK)
			started=Time.get_ticks_usec()
			game.sync_view()
			views.append(Time.get_ticks_usec()-started)
			var chunks: Array=[]
			var numbers: Array=game.world_chunks.keys()
			numbers.sort()
			for number in numbers:
				if number>current+3: continue
				var items: Array=[]
				for node in game.world_chunks[number].get_children():
					if node.name=="Floor":continue
					items.append([node.get_class(),node.transform,node.get_meta("wind",0.0)])
				chunks.append([number,items])
			layouts["%d:%d"%[chapter,zone]]=var_to_str(chunks).sha256_text()
			check(game.world_chunks.size()+game.chunk_jobs.size()<=7,"区块队列有界")
			await process_frame
	report.layout_hashes=layouts
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/loading_baseline.json"))
	check(layouts==expected.journey_layout_hashes,"18 个区域的布局与原始 test 完全一致")
	if not game.parallel_chunk_plans: check(game.chunk_plan_tasks_started==initial_plan_tasks,"禁用工作线程后全部区块使用分帧回退")
	check(game.chunk_parallel_peak<=2 and game.chunk_plan_tasks_started>0,"旅程规划实际分发到最多两个任务")
	report.parallel_peak=game.chunk_parallel_peak
	report.plan_tasks=game.chunk_plan_tasks_started
	# 按最高合法前进速度推进视图窗口，确认提前两块能覆盖正常跨块。
	game.run.level_index=0
	game.run.retry()
	game.reset_journey_views()
	for poll in range(10000):
		if game.prepare_journey_frame(): break
		await process_frame
	var runtime_waits:=0
	for frame in range(1200):
		game.run.distance+=game.run.WALK_SPEED/60.0
		if not game.prepare_journey_frame(): runtime_waits+=1
		game.sync_view()
		await process_frame
	check(runtime_waits==0,"最高合法前进速度跨越两个区块无需途中等待")
	report.runtime_waits=runtime_waits
	var number: int=game.world_chunks.keys()[0]
	var floor_id: int=game.world_chunks[number].get_node("Floor").get_instance_id()
	game.run.revision+=1
	game.sync_world()
	check(game.world_chunks[number].get_node("Floor").get_instance_id()==floor_id,"无关版本更新复用原地面网格")
	report.prepare_calls=stats(calls)
	report.prepared_view=stats(views)
	report.peak_usec=game.preparation_peak_usec
	report.waits=game.preparation_waits
	var path:=OS.get_environment("PERFORMANCE_REPORT")
	if path.is_empty(): path="res://build-tools/cache/loading-performance/journey-loading.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("JOURNEY_LOADING failures=",failures.size()," ",JSON.stringify(report))
	boot.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
func stats(values: Array) -> Dictionary:
	values.sort()
	return {"median_usec":values[values.size()/2],"p95_usec":values[int((values.size()-1)*0.95)],"max_usec":values[-1],"samples":values.size()}
