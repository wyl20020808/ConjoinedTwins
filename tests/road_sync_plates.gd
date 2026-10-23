extends SceneTree

const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")
var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	print("PASS " if passed else "FAIL ", label)
	if not passed: failures += 1

func _initialize() -> void:
	call_deferred("verify")

func rules(Plates) -> void:
	var gate: Dictionary = Plates.make_tutorial()
	var left: Vector2 = gate.left.get_center()
	var right: Vector2 = gate.right.get_center()
	for tick in range(41): Plates.advance(gate, left, right, true, true, Run.FIXED_STEP)
	check("连续 41 步不足 0.35 秒不开门", not gate.open and gate.charge > 0)
	Plates.advance(gate, left, right, true, true, Run.FIXED_STEP)
	check("连续第 42 步锁存开启", gate.open)
	Plates.advance(gate, Vector2.ZERO, Vector2.ZERO, false, false, 1.0)
	check("离板后保持开启", gate.open)
	for invalid in ["single", "same", "air", "edge", "leave"]:
		gate = Plates.make_tutorial()
		for tick in range(41): Plates.advance(gate, left, right, true, true, Run.FIXED_STEP)
		var invalid_b := right
		if invalid == "single": invalid_b = Vector2.ZERO
		if invalid == "same": invalid_b = left
		if invalid in ["edge", "leave"]: invalid_b = right + Vector2(Plates.PLATE_RADIUS + 0.01 if invalid == "edge" else 40, 0)
		Plates.advance(gate, left, invalid_b, true, invalid != "air", Run.FIXED_STEP)
		check("失效归零 " + invalid, not gate.open and gate.charge == 0)
		for tick in range(41): Plates.advance(gate, left, right, true, true, Run.FIXED_STEP)
		check("中断后不能累计旧计时 " + invalid, not gate.open)
	gate = Plates.make_tutorial()
	for tick in range(42): Plates.advance(gate, right, left, true, true, Run.FIXED_STEP)
	check("交换角色同样开门", gate.open)

func verify() -> void:
	var exists := FileAccess.file_exists("res://scripts/road_sync_plates.gd")
	check("道路同步踏板模块存在", exists)
	if not exists:
		print("SYNC_PLATES checks=", checks, " failures=", failures)
		quit(1)
		return
	rules(load("res://scripts/road_sync_plates.gd"))
	var run = Run.new(false)
	run.charge_tutorial = true
	run.retry()
	check("首关安装两种教学", run.charge_gates.size() == 2)
	run.dispose()
	verify_routes()
	await verify_scene()
	print("SYNC_PLATES checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func new_run(difficulty: String, seed_value: int):
	var run = Run.new(false)
	run.difficulty = difficulty
	run.random_seed = false
	run.seed_value = seed_value
	run.charge_tutorial = true
	run.retry()
	return run

func verify_routes() -> void:
	var output := OS.get_environment("SYNC_PLATES_EVIDENCE")
	var binding := Templates.source_binding()
	for difficulty in Templates.DIFFICULTIES:
		for seed_value in [4242, 812208, 20261014]:
			for swapped in [false, true]:
				var run = new_run(difficulty, seed_value)
				var replay = new_run(difficulty, seed_value)
				var file: FileAccess = null
				var stem := "%s-%d-%s" % [difficulty, seed_value, "swap" if swapped else "normal"]
				if not output.is_empty():
					file = FileAccess.open(output + "/tutorial-" + stem + ".jsonl", FileAccess.WRITE)
					file.store_line(JSON.stringify({"source_binding": binding, "difficulty": difficulty, "seed": seed_value, "swapped": swapped, "initial": var_to_str(Templates.snapshot(run, 0))}))
				var valid := true
				var tick := 0
				var inputs: Array = []
				var states: Array[String] = []
				while run.total_distance() < 510 and tick < 1800 and run.state == "running":
					var axes := Templates.existing_route_input(run)
					if swapped and run.charge_gate.active and not run.charge_gate.open:
						var gate: Dictionary = run.charge_gate
						var target_a: Vector2 = gate.right.get_center() if gate.get("kind", "charge") == "sync_plates" else Vector2(65, gate.receiver.y)
						var target_b: Vector2 = gate.left.get_center() if gate.get("kind", "charge") == "sync_plates" else Vector2(-65, gate.receiver.y)
						if run.distance >= gate.receiver.y - 100:
							axes = [Templates.keyboard_direction(target_a-run.a.position), Templates.keyboard_direction(target_b-run.b.position), false, false]
					valid = valid and Templates.keyboard_legal(axes[0]) and Templates.keyboard_legal(axes[1])
					var before := [run.a.position, run.b.position]
					var closed: Dictionary = run.charge_gate.duplicate(true)
					run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
					tick += 1
					valid = valid and run.rope.required <= Run.LINK_LIMIT + 0.01 and not run.rope_failed
					valid = valid and before[0].distance_to(run.a.position) <= 6.0 and before[1].distance_to(run.b.position) <= 6.0
					if closed.active and not closed.open:
						valid = valid and maxf(run.a.position.y, run.b.position.y) <= closed.door.position.y - Run.Motion.RADIUS + 0.01
					inputs.append([axes[0].x, axes[0].y, axes[1].x, axes[1].y, axes[2], axes[3]])
					states.append(var_to_str(Templates.snapshot(run, tick)))
					if file != null: file.store_line(JSON.stringify({"input": inputs.back(), "state": states.back()}))
				if file != null: file.close()
				# 从保存的文件读取再复放，不能仅比较同一次循环的内存结果。
				if not output.is_empty():
					inputs.clear()
					states.clear()
					file = FileAccess.open(output + "/tutorial-" + stem + ".jsonl", FileAccess.READ)
					file.get_line()
					while file.get_position() < file.get_length():
						var entry: Dictionary = JSON.parse_string(file.get_line())
						inputs.append(entry.input)
						states.append(entry.state)
					file.close()
				var same := true
				for index in range(inputs.size()):
					var axes: Array = inputs[index]
					replay.step(Run.FIXED_STEP, Vector2(axes[0], axes[1]), Vector2(axes[2], axes[3]), axes[4], axes[5])
					same = same and var_to_str(Templates.snapshot(replay, index+1)) == states[index]
				var opens: Array = run.gate_events.filter(func(e): return e.event == "opened")
				var ordered: bool = opens.size() == 2 and opens[0].id == "tutorial" and opens[1].id == "sync_tutorial"
				check("合法教学保存复放 " + stem, valid and same and ordered and run.total_distance() >= 510 and run.state == "running")
				print("SYNC_ROUTE ", stem, " ticks=", tick, " replay=", same, " legal_geometry=", valid, " ordered=", ordered, " distance=", run.total_distance())
				run.dispose()
				replay.dispose()

func ticks(run, count: int, a := Vector2.ZERO, b := Vector2.ZERO, jump := false) -> void:
	for tick in range(count): run.step(Run.FIXED_STEP, a, b, jump, false)

func verify_scene() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.generation_enabled = false
	game.primary_action()
	var run = game.run
	for tick in range(400):
		var axes := Templates.existing_route_input(run)
		run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
		if run.charge_gate.get("kind", "charge") == "sync_plates": break
	# 扩大的踏板已覆盖充能后的横向位置；先用合法输入离开板边再验证等待。
	ticks(run, 4, Vector2.LEFT, Vector2.RIGHT)
	ticks(run, 240)
	check("踏板等待停止推进且不安装危险", run.distance == 290.0 and run.obstacles.is_empty() and not run.charge_gate.open)
	# 单独的世界坐标重定位夹具；教学路线与复放不使用坐标赋值。
	var rebase = Templates.clone_state(Templates.capture_state(run))
	rebase.distance += 6000
	rebase.a.position.y += 6000
	rebase.b.position.y += 6000
	rebase.rope.reset(rebase.a.position, rebase.b.position)
	for item in rebase.charge_gates: Run.ChargeGate.relocate(item, 6000)
	rebase.charge_gate.charge = 0.123
	var world_left: Vector2 = rebase.charge_gate.left.get_center() + Vector2(0, rebase.world_origin)
	var world_door: Vector2 = rebase.charge_gate.door.position + Vector2(0, rebase.world_origin)
	rebase.update_stream()
	check("重定位保留踏板门世界位置及状态", rebase.rebases == 1 and rebase.charge_gate.id == "sync_tutorial" and rebase.charge_gate.charge == 0.123 and rebase.charge_gate.left.get_center() + Vector2(0, rebase.world_origin) == world_left and rebase.charge_gate.door.position + Vector2(0, rebase.world_origin) == world_door)
	rebase.dispose()
	game.sync_view()
	var view: Node3D = game.charge_gate_views[1]
	check("独立踏板教学显示地面规则", view.get_node("Status").text.contains("踏板") and view.get_node("Status").text.contains("0.35") and not view.get_node("Receiver").visible)
	ticks(run, 3, Vector2.RIGHT, Vector2.LEFT)
	check("合法靠近两板开始同步", run.charge_gate.charge > 0)
	run.pause()
	var frozen := var_to_str(Templates.snapshot(run, 0))
	ticks(run, 120)
	check("暂停冻结同步计时和占用", frozen == var_to_str(Templates.snapshot(run, 0)))
	run.pause()
	ticks(run, 1)
	ticks(run, 1, Vector2.ZERO, Vector2.ZERO, true)
	check("生产起跳立即归零且不打开门", run.heights[0] > 0 and run.charge_gate.charge == 0 and not run.charge_gate.open)
	for tick in range(120):
		ticks(run, 1)
		if run.charge_gate.open: break
	check("落地后重新连续站位开门", run.gate_events.any(func(e): return e.id == "sync_tutorial" and e.event == "opened"))
	game.sync_view()
	check("开门反馈与占用独立显示", not view.get_node("Door").visible and view.get_node("Status").text.contains("开启"))
	var opens: Array = run.gate_events.filter(func(e): return e.id == "sync_tutorial" and e.event == "opened")
	ticks(run, 3)
	check("后续帧仅一次开启事件", opens.size() == 1 and run.gate_events.filter(func(e): return e.id == "sync_tutorial" and e.event == "opened").size() == 1)
	var captured := Templates.capture_state(run)
	var clone = Templates.clone_state(captured)
	var original: bool = run.charge_gate.open
	clone.charge_gate.open = not original
	check("克隆重新绑定队列且不共享状态", run.charge_gate.open == original and clone.charge_gates.any(func(g): return g.id == clone.charge_gate.id and g.open != original))
	clone.dispose()
	var gate: Dictionary = run.charge_gates.filter(func(g): return g.id == "sync_tutorial")[0]
	var hash_before: int = run.sync_hash()
	gate.occupied[0] = not gate.occupied[0]
	check("联机哈希包含占用", run.sync_hash() != hash_before)
	gate.occupied[0] = not gate.occupied[0]
	hash_before = run.sync_hash()
	gate.charge = 0.123
	check("联机哈希包含同步计时", run.sync_hash() != hash_before)
	game.touch.move = Vector2.RIGHT
	game.touch.jump_tapped = true
	game.apply_command("retry")
	check("重试清空两种教学和旧输入", run.charge_gates.size() == 2 and run.charge_gate.id == "tutorial" and run.charge_gates[1].charge == 0 and not run.charge_gates[1].open and game.touch.move == Vector2.ZERO and not game.touch.jump_tapped)
	run.level_index = 1
	run.retry()
	check("第二关不残留踏板教学", run.charge_gates.is_empty())
	# 从生产出生点用键盘轴走到关闭的踏板门；不改变角色坐标。
	run.level_index = 0
	run.retry()
	for tick in range(400):
		var axes := Templates.existing_route_input(run)
		run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
		if run.charge_gate.get("kind", "charge") == "sync_plates": break
	ticks(run, 240, Vector2.DOWN, Vector2.DOWN, true)
	check("关闭踏板门连续碰撞且跳跃不能穿门", run.state == "running" and not run.charge_gate.open and maxf(run.a.position.y, run.b.position.y) <= 368.01)
	for tick in range(400):
		if maxf(run.a.position.y, run.b.position.y) <= 292: break
		ticks(run, 1, Vector2.UP, Vector2.UP)
	for tick in range(700):
		var axes := Templates.existing_route_input(run)
		run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
		if run.total_distance() >= 650: break
	print("SYNC_RECOVERY state=", run.state, " distance=", run.total_distance(), " gates=", run.charge_gates, " positions=", run.a.position, " / ", run.b.position, " events=", run.gate_events)
	check("门前合法回撤后可开门且教学回收", run.state == "running" and run.total_distance() >= 650 and run.charge_gates.is_empty() and run.gate_events.filter(func(e): return e.id == "sync_tutorial" and e.event == "opened").size() == 1)
	for player in game.sfx.players:
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
