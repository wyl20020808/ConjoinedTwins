extends SceneTree
# 展示层有界巡检：移动观察位置以覆盖流式资源生命周期，不作为合法通关证据。
var failures:Array=[]
func _initialize()->void:call_deferred("validate")
func validate()->void:
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.web_test_mode=true
	game.incremental_loading=true
	var samples:Array=[]
	for lap in range(2):
		for chapter in range(3):
			game.run.level_index=chapter;game.run.retry();game.run.state="paused"
			for meters in range(0,int(game.run.finish_distance()/20),40):
				game.run.a.position=Vector2(-42,meters*20);game.run.b.position=Vector2(42,meters*20)
				game.run.distance=meters*20;game.run.elapsed=meters/8.0
				var waits:=0
				while not game.prepare_journey_frame() and waits<2000:
					waits+=1;await process_frame
				if waits>=2000: failures.append("preparation stalled")
				game.sync_view()
				await process_frame
				var record:={"lap":lap,"chapter":chapter,"meters":meters,"nodes":get_node_count(),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"memory":Performance.get_monitor(Performance.MEMORY_STATIC),"chunks":game.world_chunks.size(),"jobs":game.chunk_jobs.size(),"materials":game.materials.size(),"mesh_cache":game.rock_meshes.size()}
				samples.append(record)
				if record.chunks>7 or record.jobs>7:failures.append(record)
			print("LIFETIME ",JSON.stringify(samples[-1]))
	game.queue_free()
	for n in range(4):await process_frame
	var output:=OS.get_environment("ENVIRONMENT_REPORT")
	if output.is_empty():output="res://build-tools/journey/evidence/environment/lifetime.json"
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"samples":samples,"failures":failures},"\t"))
	print("ENVIRONMENT LIFETIME FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)
