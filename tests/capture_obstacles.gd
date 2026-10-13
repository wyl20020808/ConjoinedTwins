extends SceneTree
var game
var records: Array = []

func _initialize() -> void:
	call_deferred("capture")

func shot(name: String) -> void:
	game.sync_view()
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://docs/screenshots/t02-" + name + ".png"
	var error := root.get_texture().get_image().save_png(path)
	records.append({"file": path, "save_error": error, "elapsed": game.run.elapsed, "distance": game.run.distance, "state": game.run.state, "actions": game.run.actions.duplicate()})
	print("CAPTURE ", name, " ", error)

func capture() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await shot("start")
	game.primary_action()
	game.run.step(1.0 / 60)
	for i in range(100): game.run.step(1.0 / 60, Vector2.RIGHT, Vector2.RIGHT)
	var next := 0
	for i in range(4500):
		game.run.step(1.0 / 60)
		if game.run.state != "running": break
		if next < 8 and game.run.distance >= game.run.obstacles[next].position.y - 105:
			await shot(game.run.kinds[next])
			if next == 1:
				for tick in range(15):
					game.run.step(1.0 / 60, Vector2.ZERO, Vector2.ZERO, true)
					game.sync_view()
					await process_frame
				await shot("jump")
			if next == 3:
				# 自然向前推进至周期下一预警及伸出阶段，未改时间或位置。
				for phase in ["warning", "extend", "active", "retract", "safe"]:
					for tick in range(250):
						if game.run.hazard_sample(next, game.run.elapsed).stage == phase: break
						game.run.step(1.0 / 120)
					await shot("spikes-" + phase)
			next += 1
	await shot("route-end")
	var output := FileAccess.open("res://docs/screenshots/t02-capture.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(records, "\t"))
	var passed: bool = next == 8 and game.run.state == "finished"
	for record in records:
		passed = passed and record.save_error == OK
	game.queue_free()
	await process_frame
	quit(0 if passed else 1)
