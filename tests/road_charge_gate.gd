extends SceneTree

# 这些检查捕获：端点直线替代真绳路、角色触碰替代穿线、松绳误充能、
# 非连续计时、暂停继续计时、门跳过扫掠、重试残留及角色身份不对称。
const Run = preload("res://scripts/road_run.gd")
var failures := 0
var checks := 0
var route: Array = []

func check(label: String, passed: bool) -> void:
	checks += 1
	print("PASS " if passed else "FAIL ", label)
	if not passed: failures += 1

func _initialize() -> void:
	call_deferred("verify")

func ticks(run, count: int, first := Vector2.ZERO, second := Vector2.ZERO, jump := false) -> void:
	for i in range(count):
		var pa: Vector2 = run.a.position
		var pb: Vector2 = run.b.position
		run.step(Run.FIXED_STEP, first, second, jump, jump)
		if run.a.position.distance_to(pa) > 5.0 or run.b.position.distance_to(pb) > 5.0:
			check("合法路线无瞬移", false)
		if run.rope.length > 146.61: check("合法路线无超长", false)
		route.append({"a": [run.a.position.x, run.a.position.y], "b": [run.b.position.x, run.b.position.y], "input_a": [first.x, first.y], "input_b": [second.x, second.y], "charge": run.charge_gate.charge, "open": run.charge_gate.open, "path": str(run.rope.path)})

func test_rules(Gate) -> void:
	# 手算夹具：130 单位横跨 (0,60)，超过 146.6 的 85%，双方在左右操作区。
	var straight := PackedVector2Array([Vector2(-65,60),Vector2(65,60)])
	var z := PackedFloat32Array([28,28])
	var valid = Gate.make_tutorial()
	Gate.advance(valid, straight, z, 130.0 / 146.6, true, 0.79)
	check("0.79 秒不能开门", not valid.open and valid.charge > 0.78)
	Gate.advance(valid, straight, z, 130.0 / 146.6, true, 0.01)
	check("连续 0.8 秒锁存开门", valid.open)
	Gate.advance(valid, PackedVector2Array(), PackedFloat32Array(), 0, false, 1)
	check("开门后条件丢失仍保持通路", valid.open)
	var reversed := PackedVector2Array([straight[1], straight[0]])
	var swapped = Gate.make_tutorial()
	Gate.advance(swapped, reversed, z, 130.0 / 146.6, true, 0.8)
	check("交换角色仍可充能", swapped.open)
	var tilted = Gate.make_tutorial()
	Gate.advance(tilted, straight, PackedFloat32Array([28,37]), 130.0/146.6, true, 0.8)
	check("斜绳在接收圆盘边缘满足高度仍充能", tilted.open)
	var negatives := [
		["单人触碰接收器", PackedVector2Array([Vector2(0,60),Vector2(130,60)]), z, 130.0/146.6, true],
		["连接未穿过接收器", PackedVector2Array([Vector2(-65,80),Vector2(65,80)]), z, 130.0/146.6, true],
		["张紧不足", PackedVector2Array([Vector2(-40,60),Vector2(40,60)]), z, 80.0/146.6, true],
		["端点直线穿过而真路径绕开", PackedVector2Array([Vector2(-65,60),Vector2(0,85),Vector2(65,60)]), PackedFloat32Array([28,28,28]), 0.95, true],
		["障碍遮断", straight, z, 130.0/146.6, false],
		["绳索从接收器上方跳过", straight, PackedFloat32Array([64,64]), 130.0/146.6, true],
		["斜绳高度区间与圆盘不相交", straight, PackedFloat32Array([28,38]), 130.0/146.6, true]
	]
	for entry in negatives:
		var gate = Gate.make_tutorial()
		Gate.advance(gate, straight, z, 130.0/146.6, true, 0.4)
		Gate.advance(gate, entry[1], entry[2], entry[3], entry[4], 1.0)
		check(entry[0] + "不能开门且充能归零", not gate.open and gate.charge == 0.0)
		Gate.advance(gate, straight, z, 130.0/146.6, true, 0.4)
		check(entry[0] + "不累计断开的旧进度", not gate.open)

func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var exists := false
	for property in game.run.get_property_list():
		if property.name == "charge_gate": exists = true
	check("生产入口安装独立充能教学", exists)
	if not exists:
		game.queue_free()
		await process_frame
		print("CHARGE_GATE checks=",checks," failures=",failures)
		quit(1)
		return
	var Gate = load("res://scripts/road_charge_gate.gd")
	test_rules(Gate)
	test_obstruction(Gate)
	var run = game.run
	game.primary_action()
	# 到达及站位仅用生产合法键盘轴；没有位置赋值或测试替代推进。
	ticks(run, 180)
	check("安全教学允许无限等待", run.state == "running" and is_equal_approx(run.distance, 60.0) and not run.charge_gate.open)
	check("双方抵达接收器且无危险进入操作区", absf(run.a.position.y-60)<0.02 and absf(run.b.position.y-60)<0.02 and run.obstacles.is_empty())
	ticks(run, 9, Vector2.LEFT, Vector2.RIGHT)
	check("合法双人横移满足张紧并开始充能", run.charge_gate.charge > 0 and run.rope.length >= 124.61)
	var charge: float = run.charge_gate.charge
	var pa: Vector2 = run.a.position
	run.pause()
	ticks(run, 180)
	check("暂停冻结充能与位置", run.charge_gate.charge == charge and run.a.position == pa)
	run.pause()
	ticks(run, 110)
	check("恢复后连续充能开门且恢复推进", run.charge_gates[0].id == "tutorial" and run.charge_gates[0].open and run.distance > 60)
	game.sync_view()
	check("生产显示操作区及开启反馈", game.charge_gate_view.visible and not game.charge_gate_view.get_node("Door").visible and game.charge_gate_view.get_node("Status").text.contains("开启"))
	var open_state := Run.Templates.capture_state(run)
	var clone = Run.Templates.clone_state(open_state)
	clone.charge_gate.charge = 0.123
	check("状态克隆不共享机关字典", run.charge_gate.charge != clone.charge_gate.charge)
	clone.dispose()
	run.fail_threat("机关重试夹具")
	game.primary_action()
	check("失败重试关闭门并归零进度", run.state == "running" and not run.charge_gate.open and run.charge_gate.charge == 0 and run.distance == 0)
	ticks(run, 180)
	# 同侧向门移动并跳跃，禁止门被单人触碰或跳跃绕过。
	ticks(run, 240, Vector2.DOWN, Vector2.DOWN, true)
	check("关闭门连续碰撞且不杀死或穿透", run.state == "running" and maxf(run.a.position.y,run.b.position.y) <= 138.01 and not run.charge_gate.open)
	game.sync_view()
	check("关闭门与充能进度显示", game.charge_gate_view.get_node("Door").visible and game.charge_gate_view.get_node("Status").text.contains("0%"))
	# 靠门后可合法回退再充能，没有空间死锁。
	while minf(run.a.position.y,run.b.position.y) > 62.0 and run.state == "running":
		ticks(run, 1, Vector2.UP, Vector2.UP)
	ticks(run, 9, Vector2.LEFT, Vector2.RIGHT)
	ticks(run, 110)
	check("门前回退调整可恢复开门", run.charge_gates[0].id == "tutorial" and run.charge_gates[0].open and run.state == "running")
	# 状态哈希必须包含机关，避免相同坐标的开闭状态假一致。
	var old_hash: int = run.sync_hash()
	run.charge_gate.open = not run.charge_gate.open
	check("联机状态哈希包含开闭状态", run.sync_hash() != old_hash)
	run.charge_gate.open = not run.charge_gate.open
	# 重试恢复；交换角色通过合法绕行（保留真实绳路）。
	run.retry()
	ticks(run, 180)
	ticks(run, 43, Vector2.RIGHT, Vector2.LEFT)
	ticks(run, 110)
	check("合法交换角色路线仍开门", run.charge_gates[0].id == "tutorial" and run.charge_gates[0].open and run.state == "running")
	game.sync_view()
	check("没有主玩法 AI", run.move_directions == [Vector2.ZERO,Vector2.ZERO])
	# 关卡切换不把首次教学重复装到后续关卡。
	run.level_index = 1
	run.retry()
	check("下一关不重复首次教学", not run.charge_gate.active)
	var out := OS.get_environment("CHARGE_GATE_EVIDENCE")
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"route":route}))
		file.close()
	for player in game.sfx.players:
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	print("CHARGE_GATE checks=",checks," failures=",failures," legal_axes=true")
	quit(0 if failures == 0 else 1)

func test_obstruction(Gate) -> void:
	var run = Run.new(false)
	run.charge_tutorial = true
	run.retry()
	run.distance = 60
	run.a.position = Vector2(-65,60)
	run.b.position = Vector2(65,60)
	run.rope.straight(run.a.position,run.b.position,28,28)
	# 实体货箱在两角色之间；端点都未碰到，但连线被实体遮断。
	run.obstacles.assign([Rect2(-10,50,20,20)])
	run.kinds.assign(["cargo"])
	run.obstacle_heights.assign([60.0])
	run.hazard_specs.assign([{}])
	check("真实障碍检测拒绝穿货箱的绳路", not run.charge_path_clear())
	for i in range(120): run.step(Run.FIXED_STEP)
	check("生产遮断路径不能充能", not run.charge_gate.open and run.charge_gate.charge == 0)
	# 改用生产柱子求解，真实路径必须绕开接收器，不能退回端点直线判定。
	run.obstacles[0] = Rect2(-12,48,24,24)
	run.kinds[0] = "pillar"
	run.obstacle_heights[0] = 100
	run.rope.reset(run.a.position,run.b.position)
	run.rope.solve(run.a.position,run.b.position,28,28,run.rope_circles(),true)
	check("反例使用真实绕柱路径", run.rope.path.size()>2 and run.rope.contacts.size()>0)
	Gate.advance(run.charge_gate,run.rope.path,run.rope.path_heights(),run.rope_tension(),run.charge_path_clear(),1)
	check("真实绕柱不能借端点直线开门", not run.charge_gate.open)
	run.dispose()
