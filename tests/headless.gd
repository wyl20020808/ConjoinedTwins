extends SceneTree

const Motion = preload("res://scripts/link_motion.gd")
const Partner = preload("res://scripts/partner_ai.gd")
var game
var failures: Array[String] = []
var checks := 0
var frames := 0
var max_distance := 0.0
var max_step := 0.0
const DT := 1.0 / 60.0

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): print("FAIL: watchdog timeout"); quit(2))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)
	else:
		print("PASS: ", message)
	if not condition and game != null:
		print("  state: level=", game.level_index, " a=", game.a.position, " b=", game.b.position, " time=", game.clock, " AI=", game.ai.feedback)

func tick(first := Vector2.ZERO, second := Vector2.ZERO, delta := DT) -> void:
	frames += 1
	if frames > 30000:
		print("FAIL: frame budget exceeded")
		quit(2)
		return
	var old_a: Vector2 = game.a.position
	var old_b: Vector2 = game.b.position
	var old_level: int = game.level_index
	var old_deaths: int = game.deaths
	game.simulate(delta, first, second)
	var distance: float = game.a.position.distance_to(game.b.position)
	max_distance = maxf(max_distance, distance)
	if distance > 220.001 or not Motion.free_at(game.a.position, game.walls()) or not Motion.free_at(game.b.position, game.walls()):
		if not failures.has("逐帧距离/碰撞不变量"):
			failures.append("逐帧距离/碰撞不变量")
	if game.level_index == old_level and game.deaths == old_deaths:
		var displacement := maxf(old_a.distance_to(game.a.position), old_b.distance_to(game.b.position))
		max_step = maxf(max_step, displacement)
		if displacement > Motion.SPEED * delta + 0.02 and not failures.has("无瞬移/拖拽步长"):
			failures.append("无瞬移/拖拽步长")

func idle(count: int) -> void:
	for i in range(count):
		tick()

func wait_phase(offset: float, low: float, high: float) -> void:
	for i in range(370):
		var phase: float = fposmod(game.clock + offset, 6.0)
		if phase >= low and phase <= high:
			return
		tick()
	check(false, "有界等待危险相位")

func walk(target: Vector2, budget := 800) -> bool:
	var index: int = game.level_index
	for i in range(budget):
		if game.level_index != index or game.won:
			return true
		if game.a.position.distance_to(target) < 4.0:
			return true
		tick(game.a.position.direction_to(target))
	print("walk blocked: ", target, " a=", game.a.position, " b=", game.b.position, " ", game.ai.feedback)
	return false

func settle_ai(budget := 600) -> bool:
	for i in range(budget):
		if game.ai.mode == "wait":
			return true
		tick()
	print("AI blocked: ", game.a.position, " / ", game.b.position, " ", game.ai.feedback)
	return false

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.manual_tick = true
	check(not game.local_two and game.ai.mode == "follow", "默认离线 AI")
	game.ai.wait()
	var stationary: Vector2 = game.b.position
	for i in range(180):
		tick(Vector2.LEFT)
	check(game.b.position == stationary, "等待队友不被强制拖拽")
	game.respawn()
	game.set_mode(true)
	for i in range(240):
		tick(Vector2.LEFT, Vector2.RIGHT)
	check(game.a.position.distance_to(game.b.position) > 219, "真实反向移动到达连接上限")
	for i in range(32):
		tick(Vector2.RIGHT, Vector2.LEFT)
	check(game.a.position.distance_to(game.b.position) < 50, "张紧后允许靠近")
	game.load_level(0)
	game.set_mode(false)
	game.ai.wait()
	check(walk(Vector2(140, 280)), "进入绕墙通道")
	game.ai.reset()
	check(walk(Vector2(520, 280)), "AI 跟随绕过真实墙体")
	idle(160)
	check(game.b.position.x > 404, "队友到达墙另一侧")
	game.command_target(Vector2(380, 380))
	idle(40)
	check(game.ai.feedback.contains("不可达"), "墙内不可达目标反馈")
	game.command_target(Vector2(780, 300))
	idle(180)
	check(game.ai.feedback.contains("连接限制"), "远目标在连接范围停止")
	game.command_target(Vector2(690, 300))
	check(walk(Vector2(600, 390)), "玩家靠近远目标")
	check(settle_ai(), "玩家靠近后 AI 继续并等待")
	check(walk(Vector2(690, 480)), "玩家进入第二块压力板")
	idle(2)
	check(game.level.gates[0].open, "两块真实压力板打开锁存门")
	game.ai.reset()
	check(walk(Vector2(760, 390)), "召回后可离开机关")
	check(game.level.gates[0].open, "离开压力板门保持开启")
	check(walk(Vector2(1010, 390)), "第一关出口路线")
	idle(150)
	check(game.level_index == 1, "第一关单人 + AI 实际通关")
	# L2 is traversed using real movement, observing the deterministic hazard phase.
	check(walk(Vector2(305, 390)), "第二关到第一激光等待区")
	game.ai.reset()
	idle(100)
	wait_phase(0.0, 0.0, 0.05)
	check(walk(Vector2(570, 390)), "关闭窗口穿过第一激光")
	idle(110)
	check(game.mechanisms.checkpoint_active, "两人到安全岛激活检查点")
	var deaths: int = game.deaths
	# Deliberately move into an active laser: still uses production motion/death logic.
	game.ai.wait()
	wait_phase(2.4, 4.45, 4.50)
	for i in range(100):
		tick(Vector2.RIGHT)
		if game.deaths > deaths:
			break
	check(game.deaths == deaths + 1 and game.a.position == Vector2(510, 370) and game.b.position == Vector2(560, 420), "任一角色死亡后共同恢复检查点")
	game.ai.reset()
	check(walk(Vector2(590, 390)), "恢复后到第二激光等待区")
	idle(60)
	wait_phase(2.4, 0.0, 0.05)
	check(walk(Vector2(825, 390)), "错时关闭窗口穿过第二激光")
	check(walk(Vector2(1035, 390)), "第二关出口路线")
	idle(150)
	check(game.level_index == 2, "第二关单人 + AI 实际通关")
	if game.level_index != 2:
		finish()
		return
	check(walk(Vector2(600, 390)), "第三关到接收器")
	game.command_target(Vector2(650, 285))
	check(settle_ai(), "AI 到接收器上操作区等待")
	check(walk(Vector2(650, 495)), "人类到下操作区形成张紧线段")
	idle(60)
	check(game.level.gates[0].open, "真实连线穿过接收器持续 0.8 秒开门")
	game.ai.reset()
	check(walk(Vector2(730, 390)), "召回接收器队友")
	check(walk(Vector2(850, 390)), "通过接收器门")
	game.command_target(Vector2(890, 300))
	check(settle_ai(), "AI 到最终合作板")
	check(walk(Vector2(890, 480)), "人类到最终合作板")
	idle(2)
	check(game.level.gates[1].open, "第三关组合压力板打开第二门")
	game.ai.reset()
	check(walk(Vector2(915, 390)), "召回准备最终出口")
	game.ai.wait()
	check(walk(Vector2(1020, 390)), "单角色可进入出口区域")
	check(not game.won, "单角色不能触发出口")
	game.command_target(Vector2(1010, 410))
	idle(200)
	check(game.won, "三关单人 + AI 全流程完成")
	# Independent production-scene scenarios start only through normal level/reset APIs.
	game.load_level(0)
	game.set_mode(true)
	for i in range(150):
		tick(Vector2.UP, Vector2.UP)
	for i in range(100):
		tick(Vector2.LEFT, Vector2.RIGHT)
	for i in range(100):
		tick(Vector2.DOWN, Vector2.UP)
	check(game.a.position.distance_to(game.b.position) <= 220.001, "贴墙与反向移动距离约束")
	game.load_level(0)
	game.set_mode(true)
	for i in range(40):
		tick(Vector2.UP, Vector2.UP)
	for i in range(100):
		tick(Vector2.RIGHT, Vector2.RIGHT)
	for i in range(100):
		tick(Vector2.DOWN, Vector2.RIGHT)
	check(Motion.free_at(game.a.position, game.walls()) and Motion.free_at(game.b.position, game.walls()), "真实墙角滑动无穿墙")
	game.load_level(0)
	game.set_mode(true)
	for i in range(40):
		tick(Vector2.LEFT, Vector2.RIGHT)
	var old_a: Vector2 = game.a.position
	var old_b: Vector2 = game.b.position
	for i in range(35):
		tick(Vector2.UP, Vector2.DOWN)
	check(game.a.position.distance_to(old_a) > 30 and game.b.position.distance_to(old_b) > 30, "沿张紧边界切向移动")
	game.set_mode(false)
	game.command_target(Vector2(280, 250))
	old_a = game.a.position
	old_b = game.b.position
	game.set_mode(true)
	idle(30)
	check(game.a.position == old_a and game.b.position == old_b and not game.ai.has_target, "双人切换清理目标并停用 AI，不改变位置")
	game.set_mode(false)
	idle(80)
	check(game.b.position != old_b, "切回 AI 恢复跟随驱动")
	game.paused = true
	old_a = game.a.position
	var old_clock: float = game.clock
	tick(Vector2.RIGHT)
	check(game.a.position == old_a and game.clock == old_clock, "暂停冻结世界与危险时钟")
	game.paused = false
	game.load_level(2)
	check(walk(Vector2(600, 390)), "接收器失效测试走到开放区域")
	game.command_target(Vector2(650, 285))
	check(settle_ai(), "失效测试队友定位")
	check(walk(Vector2(650, 495)), "失效测试形成连线")
	game.mechanisms.charge = 0.0
	idle(20)
	check(game.mechanisms.charge > 0 and not game.level.gates[0].open, "接收器未满 0.8 秒不打开")
	check(walk(Vector2(580, 450)), "移开线段破坏充能条件")
	check(game.mechanisms.charge == 0.0, "失去线段/张紧条件充能立即归零")
	game.load_level(2)
	check(walk(Vector2(630, 390)), "接收器反例走近中心")
	game.command_target(Vector2(650, 410))
	check(settle_ai(), "接收器反例队友靠近中心")
	idle(60)
	check(not game.level.gates[0].open and game.mechanisms.charge == 0, "角色触碰接收器但连线松弛不充能")
	game.load_level(0)
	check(walk(Vector2(140, 280)), "单板反例绕墙起步")
	check(walk(Vector2(600, 280)), "单板反例进入机关区")
	game.command_target(Vector2(690, 300))
	check(settle_ai(), "仅队友占用一块板")
	idle(60)
	check(not game.level.gates[0].open, "单块压力板不能打开门")
	game.load_level(1)
	check(walk(Vector2(300, 390)), "AI 避险到激光前")
	wait_phase(0, 3.65, 3.7)
	game.command_target(Vector2(420, 390))
	idle(40)
	check(game.ai.feedback.contains("避险") or game.b.position.x < 340, "AI 在预警/开启阶段停在危险外")
	wait_phase(0, 0.0, 0.05)
	check(settle_ai(), "关闭后 AI 继续通过危险")
	# AI waits inside the laser, proving partner death also resets the human.
	game.command_target(Vector2(384, 390))
	check(settle_ai(), "队友通过真实移动进入关闭危险区")
	deaths = game.deaths
	for i in range(370):
		tick()
		if game.deaths > deaths:
			break
	check(game.deaths > deaths and game.a.position.distance_to(game.checkpoint[0]) < 1 and game.b.position.distance_to(game.checkpoint[1]) < 1, "队友死亡触发共同重生")
	game.ai.wait()
	old_a = game.a.position
	old_b = game.b.position
	idle(60)
	check(game.b.position == old_b, "Q 对应等待行为保持静止")
	game.respawn()
	check(game.ai.mode == "follow" and not game.ai.has_target, "检查点重开清理指令并恢复跟随")
	# Tick size variation on the same production movement implementation.
	for delta in [1.0 / 30.0, 1.0 / 120.0]:
		game.load_level(0)
		game.set_mode(true)
		for i in range(150):
			tick(Vector2.LEFT, Vector2.RIGHT, delta)
	check(not failures.has("逐帧距离/碰撞不变量") and not failures.has("无瞬移/拖拽步长"), "所有帧合法且步长有界（30/60/120 Hz）")
	finish()

func finish() -> void:
	var report := {"checks": checks, "failures": failures, "frames": frames, "maximum_distance": max_distance, "maximum_step": max_step, "status": "PASS" if failures.is_empty() else "FAIL"}
	var output := FileAccess.open("res://tests/latest_result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("RESULT ", JSON.stringify(report))
	game.queue_free()
	quit(0 if failures.is_empty() else 1)
