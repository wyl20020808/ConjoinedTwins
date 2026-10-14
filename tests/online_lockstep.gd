extends SceneTree
# 联机帧同步回归：同进程起一个中转服务器和两个真实生产场景客户端，经本机 UDP 跑一段对局，
# 核对两端逐帧状态指纹一致、命令同帧生效、断线后另一端暂停；另测后台生成在不同线程快慢下仍一致。

const Run = preload("res://scripts/road_run.gd")
const Relay = preload("res://scripts/net_relay.gd")
const PORT := 24781
var checks: Array = []
var common_frames := 0
var common_equal := true
var plate_progress_seen := false
var plate_open_seen := false
var combination_plate_progress_seen := false
var combination_plate_open_seen := false
var combination_exit_seen := false
var combination_collision_free := true
var combination_reward_count := 0

func combination_kind() -> String:
	return "sync_cargo"

func combination_exited(run) -> bool:
	if run.state != "running": return false
	for segment in run.route_segments:
		if segment.get("number",-1)!=0 or segment.block.route!=combination_kind(): continue
		combination_reward_count=segment.block.rewards.size()
		for slot in range(combination_reward_count):
			if not run.claimed_rewards.has("0:0:%d" % slot): return false
		return combination_reward_count>0 and minf(run.a.position.y,run.b.position.y)+run.world_origin >= segment.base+Run.Templates.SEGMENT and absf(run.a.position.x)<70 and absf(run.b.position.x)<70 and run.heights==[0.0,0.0] and run.rope.contacts.is_empty()
	return false
var paused_seen := false
var retry_seen := false
var frame_states := [{}, {}]
var gate_trace: FileAccess
var network_games: Array = []
var pause_requested := false

func record_frame(endpoint: int, frame_index: int, game) -> void:
	var gates: Array = game.run.charge_gates.filter(func(g): return g.get("kind", "charge") == "sync_plates")
	var state := {"hash": game.run.sync_hash(), "gates": var_to_str(gates)}
	frame_states[endpoint][frame_index] = state
	gate_trace.store_line(JSON.stringify({"endpoint": endpoint, "frame": frame_index, "state": state}))
	if frame_states[1-endpoint].has(frame_index):
		common_frames += 1
		common_equal = common_equal and state == frame_states[1-endpoint][frame_index]
		paused_seen = paused_seen or game.run.state == "paused"
		combination_collision_free = combination_collision_free and game.run.shield_uses == 0
		combination_exit_seen = combination_exit_seen or (combination_plate_open_seen and combination_exited(game.run))
		if not pause_requested and combination_exit_seen and game.run.next_segment >= 3:
			pause_requested = true
			Engine.time_scale = 1.0
			for endpoint_game in network_games: endpoint_game.clear_controls()
			network_games[0].command("pause")
			print("ONLINE_PAUSE_REQUEST frame=", frame_index, " distance=", game.run.total_distance(), " state=", game.run.state)
		for gate in gates:
			retry_seen = retry_seen or (plate_open_seen and not gate.open and gate.charge == 0 and gate.occupied == [false, false])
			plate_progress_seen = plate_progress_seen or (gate.occupied == [true, true] and gate.charge > 0 and not gate.open)
			plate_open_seen = plate_open_seen or gate.open
			if gate.id != "sync_tutorial":
				combination_plate_progress_seen = combination_plate_progress_seen or (gate.occupied == [true, true] and gate.charge > 0 and not gate.open)
				combination_plate_open_seen = combination_plate_open_seen or gate.open
		frame_states[0].erase(frame_index)
		frame_states[1].erase(frame_index)

func _initialize() -> void:
	call_deferred("verify")

# 传输方式由环境变量 ONLINE_TRANSPORT 选择：enet（默认）、ws（两端 WebSocket）、mixed（01 走 ENet、02 走 WebSocket）。
func client_address(index: int) -> String:
	var transport := OS.get_environment("ONLINE_TRANSPORT")
	if transport == "ws" or (transport == "mixed" and index == 1):
		return "ws://127.0.0.1:%d" % (PORT + 1)
	return "127.0.0.1:%d" % PORT

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
	for t in range(8400):
		var input: Array = Run.Templates.existing_route_input(runs[0])
		for k in range(2):
			# 第二个实例每帧故意晚一点轮询，模拟设备快慢不同。
			if k == 1 and t % 7 == 0: OS.delay_msec(2)
			runs[k].step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
		if runs[0].sync_hash() != runs[1].sync_hash() and mismatch < 0: mismatch = t
		if runs[0].state == "failed" or t == 2100:
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
	relay.ws_port = PORT + 1
	root.add_child(relay)
	var scene: PackedScene = load("res://scenes/road_demo.tscn")
	var games := [scene.instantiate(), scene.instantiate()]
	network_games = games
	for i in range(2):
		games[i].name = "Game%d" % i
		root.add_child(games[i])
	for i in range(2): games[i].net.connect_to(client_address(i))
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
	check("联机生产入口启用教学", games[0].run.charge_gate.active and games[1].run.charge_gate.active)
	for g in games:
		g.run.generator.bag = [combination_kind()]
		g.run.generator.bag_level = g.run.level_index
	Engine.time_scale = 1.0
	var t := 0
	var retries := 0
	var taught := [false, false]
	var combinations := [[], []]
	var output := OS.get_environment("ONLINE_GATES_EVIDENCE")
	if output.is_empty(): output = "user://online-gates.jsonl"
	gate_trace = FileAccess.open(output, FileAccess.WRITE)
	gate_trace.store_line(JSON.stringify({"source_binding": Run.Templates.source_binding()}))
	for i in range(2): games[i].online_frame_applied.connect(func(frame_index): record_frame(i, frame_index, games[i]))
	var deadline := Time.get_ticks_msec() + 70000
	while (not combination_exit_seen or combinations[0].is_empty() or combinations[1].is_empty() or games[0].net.next_frame < 2400 or games[0].run.next_segment < 3 or games[1].run.next_segment < 3 or games[0].run.state != "running" or games[1].run.state != "running") and Time.get_ticks_msec() < deadline:
		# 真实 UDP 控制按正常时间采样，避免批帧把网络回显延迟放大成按键过冲。
		Engine.time_scale = 1.0
		for i in range(2):
			var role: int = games[i].net.role
			var run = games[i].run
			for event in run.gate_events:
				if event.event == "opened" and event.id not in ["tutorial", "sync_tutorial"] and not combinations[i].has(event.id): combinations[i].append(event.id)
			taught[i] = taught[i] or run.gate_events.any(func(e): return e.id == "tutorial" and e.event == "opened")
			if pause_requested:
				games[i].clear_controls()
				continue
			if run.charge_gate.active and not run.charge_gate.open and run.distance >= run.charge_gate.receiver.y - 10:
				# 新教学必须用合法双人输入完成，保留原后台生成和同步断言。
				var point: Vector2 = run.a.position if role == 0 else run.b.position
				var plate: bool = run.charge_gate.get("kind", "charge") == "sync_plates"
				var inner: float = 42 if plate else 64
				var outer: float = 48 if plate else 70
				games[i].touch.move = Vector2.ZERO
				if run.distance >= run.charge_gate.receiver.y - 10:
					if role == 0 and point.x > -inner: games[i].touch.move = Vector2.LEFT
					if role == 0 and point.x < -outer: games[i].touch.move = Vector2.RIGHT
					if role == 1 and point.x < inner: games[i].touch.move = Vector2.RIGHT
					if role == 1 and point.x > outer: games[i].touch.move = Vector2.LEFT
					if point.y < run.charge_gate.receiver.y - 3: games[i].touch.move.y = 1
					if point.y > run.charge_gate.receiver.y + 3: games[i].touch.move.y = -1
					# 点按后等待网络帧回显，避免基于滞后坐标持续按键形成往返振荡。
					if t % 20 != 0: games[i].touch.move = Vector2.ZERO
			else:
				# 教学后复用地图证书路线。随意晃动会在截止帧前恰好失败重试，
				# 使原“当前已加载段落”断言测到刚清空的关卡，而非生成能力。
				var input: Array = Run.Templates.existing_route_input(run)
				games[i].touch.move = input[role]
				if input[role + 2]: games[i].touch.jump_tapped = true
		if games[0].run.state == "failed" and t % 30 == 0 and retries < 20:
			print("ONLINE_RETRY reason=",games[0].run.reason," distance=",games[0].run.total_distance()," count=",retries)
			games[0].command("retry")
			retries += 1
		t += 1
		await physics_frame
		# 首个组合双方安全退出并领取实际生成的完整金币链后暂停。
		if not combinations[0].is_empty() and not combinations[1].is_empty() and games.all(func(g): return g.run.state == "paused" and g.run.next_segment >= 3): break
	Engine.time_scale = 1.0
	# 达到帧数与生成覆盖后，同步暂停再核对快照；避免核对期间继续死亡重试清空段落。
	if not pause_requested: games[0].command("pause")
	await wait_until(func(): return games[0].run.state == "paused" and games[1].run.state == "paused", 3.0)
	check("联机同步暂停保留已加载段落", games[0].run.state == "paused" and games[1].run.state == "paused")
	# 暂停帧也必须保持同一快照；保留原 2400 帧同步覆盖阈值。
	Engine.time_scale = 4.0
	await wait_until(func(): return common_frames >= 2400 and games[0].net.next_frame >= 2400 and games[1].net.next_frame >= 2400, 15.0)
	Engine.time_scale = 1.0
	await wait_until(func(): return games[0].net.next_frame == games[1].net.next_frame and games[0].net.frames.is_empty(), 5.0)
	var frames: int = games[0].net.next_frame
	check("联机推进 %d 帧（失败后重试 %d 次）" % [frames, retries], frames >= 2400)
	check("两端最终状态指纹一致", games[0].net.next_frame == games[1].net.next_frame and games[0].run.sync_hash() == games[1].run.sync_hash())
	check("双方通过真实联机充能教学", taught[0] and taught[1])
	check("同步踏板逐共同帧占用计时开门一致", common_frames >= 2400 and common_equal and plate_progress_seen and plate_open_seen)
	check("随机踏板组合逐共同帧充能开启一致", common_equal and combination_plate_progress_seen and combination_plate_open_seen)
	check("联机组合绕箱领奖安全退出", combination_exit_seen and combination_collision_free and common_equal and retries==0)
	print("ONLINE_COMBINATION progress=", combination_plate_progress_seen, " opened=", combination_plate_open_seen, " exited=",combination_exit_seen," rewards=",combination_reward_count," collision_free=",combination_collision_free," retries=",retries," equal=", common_equal)
	print("ONLINE_SYNC common_frames=", common_frames, " equal=", common_equal, " occupied_progress=", plate_progress_seen, " opened=", plate_open_seen)
	check("双方实际通过同一随机组合机关", combinations[0].any(func(id): return combinations[1].has(id)))
	print("ONLINE_GATES opened=", combinations)
	check("服务器未报告不同步", not games[0].net.desynced and not games[1].net.desynced)
	for g in games: print("ONLINE_ROUTE segments=",g.run.next_segment," halted=",g.run.generation_halted," reason=",g.run.reason," position=",g.run.a.position," ",g.run.b.position," evidence=",g.run.generator.last_evidence.get("reason", ""))
	check("两端都装入了后台生成段落", games[0].run.next_segment >= 3 and games[0].run.next_segment == games[1].run.next_segment)
	if games[0].run.state != "running":
		games[0].command("retry")
		await wait_until(func(): return games[0].run.state == "running" and games[1].run.state == "running", 3.0)
	check("联机暂停重试共同帧保持一致并清空踏板", paused_seen and retry_seen and common_equal and games.all(func(g): return g.run.charge_gates.size() == 2 and not g.run.charge_gates[1].open and g.run.charge_gates[1].charge == 0 and g.touch.move == Vector2.ZERO and not g.touch.jump_tapped))
	print("ONLINE_LIFECYCLE paused=", paused_seen, " retry=", retry_seen, " equal=", common_equal)
	games[1].toggle_online()
	await wait_until(func(): return not games[0].net.in_match, 5.0)
	check("队友断开后本端停止对局并暂停", not games[0].net.in_match and games[0].run.state in ["paused", "failed", "settlement"])
	check("断开一方回到单机", not games[1].net.active() and not games[1].run.lockstep)
	games[0].net.disconnect_from()
	verify_extra()
	var failed := checks.filter(func(c): return not c.passed).size()
	print("RESULT %d/%d passed" % [checks.size() - failed, checks.size()])
	for g in games: g.queue_free()
	gate_trace.close()
	relay.queue_free()
	await process_frame
	quit(1 if failed > 0 else 0)

# 子类附加验证必须进入最终失败统计。
func verify_extra() -> void:
	pass
