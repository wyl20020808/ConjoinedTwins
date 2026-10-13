extends SceneTree
var game
var records: Array = []
func _initialize() -> void:
	call_deferred("capture")
func shot(name: String) -> void:
	game.sync_view()
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://docs/screenshots/t04-" + name + ".png"
	var error := root.get_texture().get_image().save_png(path)
	records.append({"file": path, "error": error, "seed": game.run.seed_value, "difficulty": game.run.difficulty, "state": game.run.state, "elapsed": game.run.elapsed, "distance": game.run.total_distance(), "heights": game.run.heights.duplicate()})
func capture() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await shot("start")
	game.primary_action()
	game.run.step(0)
	for frame in range(50):
		game.run.step(1.0 / 60, Vector2(-0.2, 0.5), Vector2(0.2, -0.5))
	await shot("wide-offset")
	for frame in range(16):
		game.run.step(1.0 / 60, Vector2.ZERO, Vector2.ZERO, true)
		game.sync_view()
		await process_frame
	await shot("jump")
	game.run.pause()
	await shot("pause")
	game.run.retry()
	game.run.step(0)
	for frame in range(1350):
		var r = game.run
		r.step(1.0 / 60, Vector2(clampf((175 - r.a.position.x) / 10, -1, 1), 0), Vector2(clampf((215 - r.b.position.x) / 10, -1, 1), 0))
	await shot("dynamic")
	game.run.retry()
	game.run.step(0)
	var target: float = game.run.obstacles[0].get_center().x
	for frame in range(1000):
		var r = game.run
		r.step(1.0 / 60, Vector2(clampf((target - r.a.position.x) / 10, -1, 1), 0), Vector2(clampf((target - r.b.position.x) / 10, -1, 1), 0))
		game.sync_view()
		if r.state == "failed": break
	await shot("hit")
	for frame in range(100): await process_frame
	await shot("failure")
	game.primary_action()
	await shot("retry")
	var output := FileAccess.open("res://docs/screenshots/t04-capture.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(records, "\t"))
	var ok: bool = records[6].state == "failed" and game.run.state == "running"
	for record in records: ok = ok and record.error == OK
	game.queue_free()
	await process_frame
	quit(0 if ok else 1)
