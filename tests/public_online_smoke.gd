extends SceneTree
# 发布前的公网联机冒烟：两个生产场景客户端都连默认服务器（主机经 SakuraFrp 隧道发布的 wss 地址），
# 对上局、共同出发、一起前进，核对逐帧状态指纹一致后断开。会占用线上房间约半分钟，有人在玩时不要运行。
# 用法（对导出的 Windows 程序）：ConjoinedTwins.exe --headless -s <工程>/tests/public_online_smoke.gd
const NetClient = preload("res://scripts/net_client.gd")
var failures: Array = []
var records := [{}, {}]
var common := 0
var equal := true

func check(ok: bool, name: String) -> void:
	print("PASS " if ok else "FAIL ", name)
	if not ok: failures.append(name)

func _initialize() -> void:
	call_deferred("validate")

func until(predicate: Callable, seconds: float = 60.0) -> bool:
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
	var address := NetClient.default_address()
	print("SERVER ", address)
	var games: Array = []
	for endpoint in range(2):
		var game = load("res://scenes/journey.tscn").instantiate()
		root.add_child(game)
		games.append(game)
	check(await until(func(): return games.all(func(g): return g.scene_prepared), 180.0), "两个客户端场景准备完成")
	for endpoint in range(2):
		var game = games[endpoint]
		game.play_mode = "online"
		game.input_override = {"a": Vector2.ZERO, "b": Vector2.ZERO, "ja": false, "jb": false}
		game.online_frame_applied.connect(func(index): record(endpoint, index, game))
		game.net_address.text = address
		game.toggle_online()
		await until(func(): return game.net.role >= 0, 20.0)
	check(await until(func(): return games.all(func(g): return g.net.in_match)), "经公网服务器进入对局")
	games[0].command("primary")
	check(await until(func(): return games.all(func(g): return g.run.state == "running")), "双方就绪后共同出发")
	games[0].input_override.a = Vector2(0, 1)
	games[1].input_override.a = Vector2(0, 1)
	check(await until(func(): return common >= 300), "300 个共同网络帧")
	check(equal and games.all(func(g): return not g.net.desynced), "两端逐帧状态指纹一致")
	check(games.all(func(g): return g.run.a.position.y > 100 and g.run.b.position.y > 100), "双方远程输入生效")
	for game in games:
		print("TRAFFIC role=", game.net.role, " frames=", game.net.next_frame, " down=", game.net.bytes_received, " up=", game.net.bytes_sent)
		game.net.disconnect_from()
		game.queue_free()
	await process_frame
	print("PUBLIC ONLINE common=", common, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
