extends SceneTree
# 联机章节同步：01 号在主界面选了第二章、02 号选了第三章，连上后两端都进入 01 号的章节；
# 一端尚未确认就绪时“出发”记为待定，双方就绪后同帧出发；之后逐帧状态指纹一致。
# 用法：Godot --headless --path . --script res://tests/online_chapter_sync.gd
const Relay = preload("res://scripts/net_relay.gd")
var failures: Array = []
var records := [{}, {}]
var common := 0
var equal := true

func check(ok: bool, name: String) -> void:
	print("PASS " if ok else "FAIL ", name)
	if not ok: failures.append(name)

func _initialize() -> void:
	call_deferred("validate")

func until(predicate: Callable, seconds: float = 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func record(endpoint: int, index: int, game) -> void:
	records[endpoint][index] = game.run.sync_hash()
	if records[1 - endpoint].has(index):
		equal = equal and records[endpoint][index] == records[1 - endpoint][index]
		common += 1
		records[0].erase(index)
		records[1].erase(index)

func validate() -> void:
	var relay = Relay.new()
	relay.port = 24851
	relay.ws_port = 24852
	root.add_child(relay)
	var games: Array = []
	for endpoint in range(2):
		var game = load("res://scenes/journey.tscn").instantiate()
		game.start_chapter = 1 if endpoint == 0 else 2
		root.add_child(game)
		games.append(game)
	check(await until(func(): return games.all(func(g): return g.scene_prepared), 120.0), "两端按各自选择的章节准备完成")
	check(games[0].run.level_index == 1 and games[1].run.level_index == 2, "连接前两端停在各自章节")
	for endpoint in range(2):
		var game = games[endpoint]
		game.play_mode = "online"
		game.input_override = {"a": Vector2.ZERO, "b": Vector2.ZERO, "ja": false, "jb": false}
		game.online_frame_applied.connect(func(index): record(endpoint, index, game))
	# 先连 01 号，保证它拿到 01 号位置。
	games[0].net_address.text = "ws://127.0.0.1:24852"
	games[0].toggle_online()
	check(await until(func(): return games[0].online_entry and games[0].pack_overlay.visible, 2.0), "点连接后显示联机入场画面")
	check(await until(func(): return games[0].net.role == 0), "01 号先连接")
	games[1].net_address.text = "127.0.0.1:24851"
	games[1].toggle_online()
	check(await until(func(): return games.all(func(g): return g.net.in_match)), "两端进入对局")
	check(await until(func(): return games.all(func(g): return g.run.level_index == 1 and g.chapter_epoch == 2)), "两端同步到 01 号选择的第二章")
	games[1].command("primary")
	check(await until(func(): return games.all(func(g): return g.online_start_pending or g.run.state == "running")), "未全部就绪时出发记为待定或已同帧出发")
	check(await until(func(): return games.all(func(g): return g.run.state == "running" and g.online_ready == [true, true])), "双方就绪后共同出发")
	check(await until(func(): return not games[0].pack_overlay.visible and not games[1].pack_overlay.visible), "就绪后收起联机入场画面")
	games[0].input_override.a = Vector2(0, 1)
	games[1].input_override.a = Vector2(0, 1)
	check(await until(func(): return common >= 240), "240 个共同网络帧")
	check(equal and games.all(func(g): return not g.net.desynced), "两端逐帧状态指纹一致")
	check(games.all(func(g): return g.run.level_index == 1), "对局中保持第二章")
	for game in games:
		game.net.disconnect_from()
		game.queue_free()
	relay.queue_free()
	await process_frame
	print("ONLINE CHAPTER SYNC common=", common, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
