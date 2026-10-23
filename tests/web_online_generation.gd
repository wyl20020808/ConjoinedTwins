extends "res://tests/online_lockstep.gd"
const NoThreads = preload("res://tests/fixtures/no_threads_run.gd")
var cooperative_seen := false
func client_address(index: int) -> String:
	if index == 1:
		var game = network_games[index]
		game.run.dispose()
		game.run = NoThreads.new(true, true)
		game.run.charge_tutorial = true
		game.run.random_seed = true
		game.run.retry()
		game.run.state = "start"
	return super.client_address(index)
func record_frame(endpoint: int, frame_index: int, game) -> void:
	if endpoint == 1:
		cooperative_seen = cooperative_seen or game.run.async_events.any(func(event): return event.get("backend", "") == "cooperative" and event.source == "proven")
	super.record_frame(endpoint, frame_index, game)
func verify_extra() -> void:
	check("真实联机的第二客户端执行无线程验证并安装障碍", cooperative_seen)
