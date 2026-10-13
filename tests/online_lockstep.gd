extends SceneTree
# 联机帧同步回归：同进程起一个中转服务器和两个真实生产场景客户端，经本机 UDP 跑一段对局，
# 核对两端逐帧状态指纹一致、命令同帧生效、断线后另一端暂停；另测后台生成在不同线程快慢下仍一致。

const Run = preload("res://scripts/road_run.gd")
const Relay = preload("res://scripts/net_relay.gd")
const PORT := 24781
var checks: Array = []

func _initialize() -> void:
	call_deferred("verify")

func check(label: String, passed: bool) -> void:
	checks.append({"name": label, "passed": passed})
	print("PASS " if passed else "FAIL ", label)

func wait_until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await process_frame
	return condition.call()

func pattern(t: int, phase: float) -> Vector2:
	return Vector2(sin(t * 0.021 + phase), 0.35 * cos(t * 0.013 + phase)).snapped(Vector2(1, 1)) * 0.7

func verify_threads() -> void:
	var runs := [Run.new(true, true), Run.new(true, true)]
	for r in runs:
		r.lockstep = true
		r.seed_value = 777
		r.new_campaign()
	var mismatch := -1
	for t in range(4200):
		for k in range(2):
			# 第二个实例每帧故意晚一点轮询，模拟设备快慢不同。
			if k == 1 and t % 7 == 0: OS.delay_msec(2)
			var jump := t % 150 < 6
			runs[k].step(Run.FIXED_STEP * 2.0, pattern(t, 0.0), pattern(t, 1.3), jump, t % 190 < 6)
		if runs[0].sync_hash() != runs[1].sync_hash() and mismatch < 0: mismatch = t
		if runs[0].state == "failed":
			runs[0].retry(true)
			runs[1].retry(true)
	check("后台生成在线程快慢不同下逐帧一致（%d 段）" % runs[0].next_segment, mismatch < 0 and runs[0].next_segment >= 4)
	check("联机重试种子确定性推导", runs[0].seed_value == runs[1].seed_value and runs[0].seed_value != 777)
	for r in runs: r.dispose()

func verify() -> void:
	verify_threads()
	var relay = Relay.new()
	relay.name = "Relay"
	relay.port = PORT
	root.add_child(relay)
	var scene: PackedScene = load("res://scenes/road_demo.tscn")
	var games := [scene.instantiate(), scene.instantiate()]
	for i in range(2):
		games[i].name = "Game%d" % i
		root.add_child(games[i])
	for g in games: g.net.connect_to("127.0.0.1:%d" % PORT)
	var started: bool = await wait_until(func(): return games[0].net.in_match and games[1].net.in_match, 10.0)
	check("两客户端连上并开局", started)
	check("角色分别为 01 和 02", [games[0].net.role, games[1].net.role].has(0) and [games[0].net.role, games[1].net.role].has(1))
	check("联机开局两端种子相同", games[0].run.seed_value == games[1].run.seed_value and games[0].run.lockstep)
	games[1].command("difficulty", "困难")
	await wait_until(func(): return games[0].run.difficulty == "困难" and games[1].run.difficulty == "困难", 3.0)
	check("难度命令两端同步", games[0].run.difficulty == "困难" and games[1].run.difficulty == "困难")
	games[0].command("primary")
	await wait_until(func(): return games[0].run.state == "running" and games[1].run.state == "running", 3.0)
	check("开始命令两端同帧生效", games[0].run.state == "running" and games[1].run.state == "running")
	Engine.time_scale = 4.0
	var t := 0
	var retries := 0
	var deadline := Time.get_ticks_msec() + 25000
	while games[0].net.next_frame < 2400 and Time.get_ticks_msec() < deadline:
		for i in range(2):
			var role: int = games[i].net.role
			games[i].touch.move = pattern(t, 0.0 if role == 0 else 1.3)
			if t % (150 if role == 0 else 190) == 0: games[i].touch.jump_tapped = true
		if games[0].run.state == "failed" and t % 30 == 0 and retries < 20:
			games[0].command("retry")
			retries += 1
		t += 1
		await physics_frame
	Engine.time_scale = 1.0
	await wait_until(func(): return games[0].net.next_frame == games[1].net.next_frame and games[0].net.frames.is_empty(), 5.0)
	var frames: int = games[0].net.next_frame
	check("联机推进 %d 帧（失败后重试 %d 次）" % [frames, retries], frames >= 2400)
	check("两端最终状态指纹一致", games[0].net.next_frame == games[1].net.next_frame and games[0].run.sync_hash() == games[1].run.sync_hash())
	check("服务器未报告不同步", not games[0].net.desynced and not games[1].net.desynced)
	check("两端都装入了后台生成段落", games[0].run.next_segment >= 3 and games[0].run.next_segment == games[1].run.next_segment)
	if games[0].run.state != "running":
		games[0].command("retry")
		await wait_until(func(): return games[0].run.state == "running" and games[1].run.state == "running", 3.0)
	games[1].toggle_online()
	await wait_until(func(): return not games[0].net.in_match, 5.0)
	check("队友断开后本端停止对局并暂停", not games[0].net.in_match and games[0].run.state in ["paused", "failed", "settlement"])
	check("断开一方回到单机", not games[1].net.active() and not games[1].run.lockstep)
	games[0].net.disconnect_from()
	var failed := checks.filter(func(c): return not c.passed).size()
	print("RESULT %d/%d passed" % [checks.size() - failed, checks.size()])
	for g in games: g.queue_free()
	relay.queue_free()
	await process_frame
	quit(1 if failed > 0 else 0)
