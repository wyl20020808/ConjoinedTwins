extends SceneTree
var report := {}
func _initialize() -> void: call_deferred("measure")
func summary(values: Array) -> Dictionary:
	values.sort()
	return {"median_usec":values[values.size()/2],"p95_usec":values[int((values.size()-1)*0.95)],"max_usec":values[-1],"samples":values.size()}
func measure() -> void:
	var started := Time.get_ticks_usec()
	var game = load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	report.scene_ready_usec = Time.get_ticks_usec()-started
	report.audio_hashes = {}
	for key in game.ambience_streams: report.audio_hashes[key] = game.ambience_streams[key].data.hex_encode().sha256_text()
	report.layout_hashes = {}
	var transitions: Array = []
	var views: Array = []
	for chapter in range(3):
		game.run.level_index=chapter
		game.run.retry()
		game.reset_journey_views()
		for zone in range(6):
			game.run.distance=game.run.finish_distance()/6*zone+400
			started=Time.get_ticks_usec()
			game.sync_view()
			transitions.append(Time.get_ticks_usec()-started)
			var chunks: Array = []
			for number in game.world_chunks:
				var items: Array = []
				for node in game.world_chunks[number].get_children():
					if node.name=="Floor": continue
					items.append([node.get_class(),node.transform,node.get_meta("wind",0.0)])
				chunks.append([number,items])
			report.layout_hashes["%d:%d"%[chapter,zone]]=var_to_str(chunks).sha256_text()
			for frame in range(60):
				started=Time.get_ticks_usec()
				game.sync_view()
				views.append(Time.get_ticks_usec()-started)
			await process_frame
	report.transition_view=summary(transitions)
	report.steady_view=summary(views)
	report.engine=Engine.get_version_info().string
	report.cpu=OS.get_processor_name()
	report.mode="headless CPU；首次进程资源加载；区域跳转和稳定画面分别计时"
	var path:=OS.get_environment("PERFORMANCE_REPORT")
	if path.is_empty():path="res://build-tools/cache/loading-performance/journey-latest.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("JOURNEY_PERFORMANCE ",JSON.stringify(report))
	game.free()
	quit()
