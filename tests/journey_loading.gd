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
