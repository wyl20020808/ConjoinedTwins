extends SceneTree
var game
var records: Array = []
func _initialize() -> void:
	call_deferred("capture")
func shot(name: String) -> void:
	game.sync_view()
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://docs/screenshots/t03-review-" + name + ".png"
	var error := root.get_texture().get_image().save_png(path)
	records.append({"file": path, "save_error": error, "distance": game.run.total_distance(), "rebases": game.run.rebases, "hazards": game.run.obstacles.size()})
func capture() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.run.seed_value = 42
	game.run.set_difficulty("困难")
	game.set_physics_process(false)
	await shot("start")
	game.primary_action()
	for frame in range(3700):
		var r = game.run
		var ia := Vector2(clampf((175 - r.a.position.x) / 10, -1, 1), clampf((r.distance + 35 - r.a.position.y) / 15, -1, 1))
		var ib := Vector2(clampf((215 - r.b.position.x) / 10, -1, 1), clampf((r.distance - 35 - r.b.position.y) / 15, -1, 1))
		r.step(1.0 / 60, ia, ib)
		if frame == 1560: await shot("warning-active")
		if frame == 700: await shot("teaching")
		if frame == 3000: await shot("rebase")
	game.run.pause()
	await shot("pause")
	var file := FileAccess.open("res://docs/screenshots/t03-review-capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	var ok: bool = game.run.state == "paused" and game.run.rebases > 0
	for record in records: ok = ok and record.save_error == OK
	game.queue_free()
	await process_frame
	quit(0 if ok else 1)
