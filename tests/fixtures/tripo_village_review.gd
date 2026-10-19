extends SceneTree
# 原生渲染观察点巡检；位置跳转只用于美术检查，不作为通关或真人输入证据。
var game
var records:Array=[]
func _initialize()->void:call_deferred("review")
func review()->void:
	var output:=OS.get_environment("TRIPO_REVIEW_OUTPUT")
	if output.is_empty():push_error("需要工程外的 TRIPO_REVIEW_OUTPUT");quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	game.web_test_mode=true;game.incremental_loading=true
	game.run.random_seed=false;game.run.seed_value=20261012
	for spot in [[0,0,"ridge"],[0,520,"forest"],[0,1400,"village"],[1,240,"farm"]]:
		game.run.level_index=spot[0];game.run.retry();game.reset_journey_views()
		game.run.state="running";game.run.distance=spot[1]*20;game.run.elapsed=15.0
		game.run.a.position=Vector2(-42,game.run.distance);game.run.b.position=Vector2(42,game.run.distance)
		game.run.rope.reset(game.run.a.position,game.run.b.position)
		for gate in game.run.charge_gates:
			gate.open=gate.receiver.y<game.run.distance-180;gate.opened_at=0 if gate.open else -1
		game.run.select_charge_gate()
		var waits:=0
		while not game.prepare_journey_frame():
			waits+=1
			if waits>3000:push_error("场景预热超时");quit(1);return
			await process_frame
		var before:int=game.run.sync_hash()
		game.sync_view()
		for frame in range(45):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(spot[2]+".png"))
		var record:={"name":spot[2],"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"nodes":get_node_count(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"state_unchanged":before==game.run.sync_hash()}
		records.append(record);print("TRIPO_REVIEW ",JSON.stringify(record))
	var file:=FileAccess.open(output.path_join("render-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"observations":records,"scope":"原生 Forward+ 实际画面巡检；未测试真实键盘输入或持续玩法帧率。"},"\t"))
	for player in game.sfx.players:player.stop()
	game.queue_free();await process_frame;await create_timer(.3).timeout
	quit(0)
