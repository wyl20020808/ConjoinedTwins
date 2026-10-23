extends SceneTree
# 实时播放开场运镜：按生产流程进入第一章、按“出发”，播完开场后再停 1.5 秒自动退出，不留游戏窗口。
# 用法：Godot --path . --resolution 1600x900 --script res://build-tools/play_opening.gd
var game

func _initialize() -> void:
	call_deferred("play")

func play() -> void:
	game = load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading = true
	game.opening_enabled = true
	game.start_chapter = 0
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.apply_journey_primary()
	var run = game.run
	while run.opening_active() and run.state == "running": await process_frame
	await create_timer(1.5).timeout
	game.queue_free()
	for n in range(4): await process_frame
	quit(0)
