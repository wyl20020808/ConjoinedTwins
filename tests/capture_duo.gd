extends SceneTree

var game
var records: Array = []

func _initialize() -> void:
	call_deferred("capture")

func shot(name: String) -> void:
	game.sync_view()
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://docs/screenshots/duo-" + name + ".png"
	var result := root.get_texture().get_image().save_png(path)
	records.append({"file": path, "save_error": result, "state": game.run.state, "positions": [str(game.run.a.position), str(game.run.b.position)], "heights": game.run.heights.duplicate(), "distance": game.run.distance})
	print("CAPTURE ", name, " ", result)

func capture() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await shot("start")
	game.primary_action()
	game.run.step(1.0 / 60)
	for i in range(24):
		game.run.step(1.0 / 60, Vector2(-1, 1), Vector2(1, -1))
		game.sync_view()
		await process_frame
	await shot("wide-road")
	for i in range(15):
		game.run.step(1.0 / 60, Vector2.ZERO, Vector2.ZERO, true, false)
		game.sync_view()
		await process_frame
	await shot("jump")
	game.run.pause()
	await shot("pause")
	game.run.retry()
	game.run.step(1.0 / 60)
	for i in range(30):
		game.run.step(1.0 / 60, Vector2.LEFT, Vector2.LEFT)
	for i in range(400):
		game.run.step(1.0 / 60)
		game.sync_view()
		if game.run.state == "failed": break
	await shot("hit")
	for i in range(90): await process_frame
	await shot("failure")
	var file := FileAccess.open("res://docs/screenshots/duo-capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	var failed := false
	for item in records:
		if item.save_error != OK: failed = true
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
