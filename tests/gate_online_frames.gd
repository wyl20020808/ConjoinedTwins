extends SceneTree
const Relay = preload("res://scripts/net_relay.gd")
class StalledRun extends "res://tests/fixtures/no_threads_run.gd":
	var delayed_seed := -1
	var remaining := 0
	var waits := 0
	func prepare_frame() -> bool:
		if state == "running" and elapsed == 0.0 and delayed_seed != seed_value:
			delayed_seed = seed_value
			remaining = 6
		if remaining > 0:
			remaining -= 1
			waits += 1
			return false
		return super.prepare_frame()
var checks := 0
var failures := 0
var records := [{},{}]
var last := [-1,-1]
var contiguous := true
var equal := true
var common := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func _initialize() -> void: call_deferred("verify")
func until(condition: Callable, seconds := 12.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds*1000)
	while Time.get_ticks_msec() < end:
		if condition.call(): return true
		await process_frame
	return condition.call()
func record(endpoint: int, frame: int, game) -> void:
	contiguous = contiguous and frame == last[endpoint]+1
	last[endpoint] = frame
	records[endpoint][frame] = game.run.sync_hash()
	if records[1-endpoint].has(frame):
		equal = equal and records[endpoint][frame] == records[1-endpoint][frame]
		common += 1
		records[0].erase(frame)
		records[1].erase(frame)
func verify() -> void:
	var relay = Relay.new()
	relay.port = 24791
	relay.ws_port = 24792
	root.add_child(relay)
	var games: Array = []
	for endpoint in range(2):
		var game = load("res://scenes/road_demo.tscn").instantiate()
		root.add_child(game)
		if endpoint == 1:
			game.run.dispose()
			game.run = StalledRun.new(true,true)
			game.run.charge_tutorial = true
			game.run.retry()
			game.run.state = "start"
		game.online_frame_applied.connect(func(frame): record(endpoint,frame,game))
		games.append(game)
	for endpoint in range(2):
		var ws := OS.get_environment("ONLINE_TRANSPORT") != "mixed" or endpoint == 1
		games[endpoint].net.connect_to("ws://127.0.0.1:24792" if ws else "127.0.0.1:24791")
	check("真实双端连接", await until(func(): return games.all(func(game): return game.net.in_match)))
	games[0].command("primary")
	check("延迟准备后两端开始", await until(func(): return games.all(func(game): return game.run.state == "running") and common >= 120))
	var before_seed: int = games[0].run.seed_value
	games[0].command("retry")
	var expected := (before_seed*1103515245+12345)&0x7fffffff
	check("等待帧中的重试只执行一次", await until(func(): return common >= 240 and games.all(func(game): return game.run.seed_value == expected)))
	games[0].command("pause")
	check("暂停指令仍在同一模拟帧生效", await until(func(): return games.all(func(game): return game.run.state == "paused") and common >= 300))
	games[0].command("pause")
	check("暂停恢复与后续帧持续一致", await until(func(): return common >= 420 and games.all(func(game): return game.run.state == "running")))
	check("两端所有共同帧状态一致且编号连续", common >= 420 and equal and contiguous)
	check("慢端确实让出帧且不触发集中补算", games[1].run.waits >= 12 and games.all(func(game): return game.run.async_deadline_steps == 0))
	check("服务器未报告不同步", games.all(func(game): return not game.net.desynced))
	print("FRAME_PREPARE common=",common," last=",last," equal=",equal," contiguous=",contiguous," waits=",games[1].run.waits)
	for game in games:
		game.net.disconnect_from()
		for player in game.sfx.players:
			player.stop()
			player.stream = null
		game.queue_free()
	relay.queue_free()
	await process_frame
	print("RESULT %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
