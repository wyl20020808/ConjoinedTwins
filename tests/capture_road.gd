extends SceneTree

var game
var records: Array = []

func _initialize() -> void:
	call_deferred("capture")

func shot(name: String, hide_menu: bool = false) -> void:
	game.sync_view()
	if hide_menu:
		game.panel.hide()
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://docs/screenshots/" + name + ".png"
	var result := image.save_png(path)
	records.append({"file": path, "save_error": result, "state": game.run.state, "progress": game.run.progress(), "elapsed": game.run.elapsed, "menu_hidden_for_contact_review": hide_menu})
	print("CAPTURE ", name, " ", result)

func capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/screenshots")
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.capture_mode = true
	game.set_physics_process(false)
	await shot("00-start")
	game.primary_action()
	for i in range(5000):
		var r = game.run
		r.step(1.0 / 60, r.steering(r.a.position, r.safe_target(r.a.position, -42)))
		if i == 500: await shot("01-departure")
		if i == 1600:
			await shot("02-energy")
			r.pause()
			await shot("04-pause")
			r.pause()
		if i == 3000: await shot("03-homeward")
		if i == 4300: await shot("06-finish-approach")
		if r.state == "finished":
			await shot("05-finish")
			break
		if r.state == "failed":
			await shot("unexpected-failure")
			break
	var completed: bool = game.run.state == "finished"
	# 第二条路线用普通横向输入撞到能量屏障，保存失败及共同重试。
	game.run.retry()
	var danger: Rect2 = game.run.obstacles[game.run.kinds.find("energy")]
	var approach_saved := false
	for i in range(2200):
		var r = game.run
		var target: float = r.safe_target(r.a.position, -42) if r.a.position.y < danger.position.y - 260 else danger.get_center().x
		r.step(1.0 / 60, r.steering(r.a.position, target))
		if r.a.position.y > danger.position.y - 100 and not approach_saved:
			await shot("07-barrier-approach")
			approach_saved = true
		if r.state == "failed":
			await shot("08-barrier-failure")
			await shot("08-barrier-contact-detail", true)
			game.primary_action()
			await shot("09-common-retry")
			break
	var retried: bool = game.run.state == "running" and game.run.failures == 1 and game.run.progress() == 0
	var output := FileAccess.open("res://docs/screenshots/capture.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(records, "\t"))
	quit(0 if completed and retried else 1)
