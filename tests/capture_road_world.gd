extends SceneTree
# 生产场景的固定机位美术巡检。跳转只用于展示，不作为通关或真人输入验收。
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	call_deferred("capture")

func capture()->void:
	var output:=OS.get_environment("ROAD_WORLD_CAPTURE")
	if output.is_empty():quit(2);return
	var game=load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading=true
	root.add_child(game)
	while not game.scene_prepared:await process_frame
	game.set_physics_process(false)
	game.opening_enabled=false;game.run.opening_enabled=false;game.run.opening_at=game.run.NO_OPENING
	game.web_test_mode=true
	var gate_meters:float=game.run.charge_gates[0].door.position.y/20.0-20.0
	for meters in [25,gate_meters,380,1100]:
		game.run.state="running"
		game.run.elapsed=12.0
		game.run.distance=meters*20.0
		game.run.a.position=Vector2(-42,meters*20)
		game.run.b.position=Vector2(42,meters*20)
		game.run.rope.reset(game.run.a.position,game.run.b.position)
		for gate in game.run.charge_gates:
			gate.open=gate.receiver.y<meters*20-180
			gate.opened_at=0.0 if gate.open else -1.0
		game.run.select_charge_gate()
		while not game.prepare_journey_frame():await process_frame
		for frame in range(30):
			game.sync_view()
			await process_frame
		await RenderingServer.frame_post_draw
		var error:=root.get_texture().get_image().save_png(output.path_join("road-%d.png"%meters))
		print("CAPTURE ",meters," error=",error)
	game.queue_free()
	await process_frame
	await create_timer(.3).timeout
	quit()
