extends SceneTree

const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")
var failures := 0
var checks := 0
var EVIDENCE := OS.get_environment("GATE_COMBINATIONS_EVIDENCE")

func check(label: String, passed: bool) -> void:
	checks += 1
	print("PASS " if passed else "FAIL ", label)
	if not passed: failures += 1

func _initialize() -> void:
	if EVIDENCE.is_empty(): EVIDENCE = "user://gate-combinations"
	DirAccess.make_dir_recursive_absolute(EVIDENCE)
	var block := Templates.make_block("charge_cargo", 1, 0)
	check("随机闸门布局包含机关与货箱", block.has("gate") and block.hazards.any(func(h): return h.kind == "cargo"))
	if not block.has("gate"):
		print("GATE_COMBINATIONS checks=", checks, " failures=", failures)
		quit(1)
		return
	verify_routes()
	verify_lifecycle()
	print("GATE_COMBINATIONS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func verify_routes() -> void:
	for difficulty in Templates.DIFFICULTIES:
		for level in range(3):
			for seed_value in [4242, 812208, 20261014]:
				var generator = Templates.new()
				generator.reset(seed_value)
				var block: Dictionary = generator.prove(generator.candidate_of("charge_cargo", level), difficulty, level)
				check("路线证明 %s/%d/%d" % [difficulty, level+1, seed_value], not block.is_empty())
				if block.is_empty():
					print("REASON ", generator.last_evidence.get("reason"), " ", generator.last_evidence.get("exit"))
					continue
				var run = Run.new(false)
				run.difficulty = difficulty
				run.level_index = level
				run.retry()
				run.a.position = Vector2(-25, 0)
				run.b.position = Vector2(25, 0)
				run.rope.reset(run.a.position, run.b.position)
				run.install_block(block, 0, "replay")
				var opened := false
				var legal := true
				var stem := "%s-%d-%d" % [difficulty, level+1, seed_value]
				var certificate := FileAccess.open(EVIDENCE + "/" + stem + ".certificate", FileAccess.WRITE)
				certificate.store_string(var_to_str(generator.last_evidence))
				certificate.close()
				var trace := FileAccess.open(EVIDENCE + "/" + stem + ".jsonl", FileAccess.WRITE)
				trace.store_line(JSON.stringify({"installed": Templates.snapshot(run, 0), "block": block, "source_binding": Templates.source_binding()}))
				var tick := 0
				for axes in generator.last_evidence.inputs:
					var first := Vector2(axes[0], axes[1])
					var second := Vector2(axes[2], axes[3])
					legal = legal and Templates.keyboard_legal(first) and Templates.keyboard_legal(second)
					run.step(Run.FIXED_STEP, first, second, axes[4], axes[5])
					opened = opened or run.charge_gate.open
					tick += 1
					trace.store_line(JSON.stringify({"input": axes, "state": Templates.snapshot(run, tick)}))
				trace.close()
				check("逐步复放 %s/%d/%d" % [difficulty, level+1, seed_value], legal and opened and run.state == "running" and run.distance >= Templates.SEGMENT)
				run.dispose()
				var campaign = Run.new(false)
				campaign.difficulty = difficulty
				campaign.level_index = level
				campaign.charge_tutorial = true
				# 教学只在第一关；第二、三关沿用已完成教学的关卡规则。
				campaign.retry()
				var sequence := FileAccess.open(EVIDENCE + "/" + stem + "-sequence.jsonl", FileAccess.WRITE)
				sequence.store_line(JSON.stringify({"installed": Templates.snapshot(campaign, 0), "source_binding": Templates.source_binding()}))
				var arrived := walk(campaign, 600, 450, sequence)
				campaign.install_block(block, 500, "sequence")
				campaign.route_segments.append({"base": 500.0, "block": block})
				sequence.store_line(JSON.stringify({"installed": Templates.snapshot(campaign, 0), "block": block}))
				var exited := walk(campaign, 1600, 1340, sequence)
				var events: Array = campaign.gate_events.filter(func(e): return e.event == "opened")
				var ordered: bool = events.size() == (3 if level == 0 else 1) and events.back().id == "sequence:gate"
				if level == 0: ordered = ordered and events[0].id == "tutorial" and events[1].id == "sync_tutorial"
				check("教学与跨段合法路线 %s/%d/%d" % [difficulty, level+1, seed_value], arrived and exited and ordered)
				sequence.close()
				campaign.dispose()

func walk(run, limit: int, target: float, trace: FileAccess = null) -> bool:
	for tick in range(limit):
		var input := Templates.existing_route_input(run)
		if not Templates.keyboard_legal(input[0]) or not Templates.keyboard_legal(input[1]): return false
		run.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
		if trace != null: trace.store_line(JSON.stringify({"input": [input[0].x, input[0].y, input[1].x, input[1].y, input[2], input[3]], "state": Templates.snapshot(run, tick)}))
		if run.state != "running": return false
		if run.total_distance() >= target: return true
	return false

func verify_lifecycle() -> void:
	var run = Run.new(false)
	run.charge_tutorial = true
	run.retry()
	check("教学前不安装随机组合", run.charge_gate.id == "tutorial" and run.route_segments.is_empty())
	check("合法输入先完成两种教学", walk(run, 600, 450))
	var block := Templates.make_block("charge_cargo", 1, 0)
	run.install_block(block, 500, "first")
	run.route_segments.append({"base": 500.0, "block": block})
	run.install_block(Templates.make_block("charge_cargo", -1, 0), 1340, "second")
	run.route_segments.append({"base": 1340.0, "block": Templates.make_block("charge_cargo", -1, 0)})
	check("预加载两个机关状态独立", run.charge_gates.size() == 3 and run.charge_gates[1].id != run.charge_gates[2].id)
	var clone = Templates.clone_state(Templates.capture_state(run))
	clone.charge_gate.charge = 0.4
	check("克隆机关与本地队列保持同一状态", clone.charge_gates.any(func(g): return g.id == clone.charge_gate.id and g.charge == 0.4))
	check("克隆不修改生产机关", run.charge_gate.charge == 0.0)
	clone.dispose()
	check("跨段进入第二组合并退出", walk(run, 2200, 2180))
	var opens: Array = run.gate_events.filter(func(e): return e.event == "opened")
	check("教学开门先于两次组合", opens.size() == 4 and opens[0].id == "tutorial" and opens[1].id == "sync_tutorial" and opens[2].id == "first:gate" and opens[3].id == "second:gate")
	check("门回收且不重复开门奖励", run.charge_gates.is_empty() and opens.size() == 4 and run.coins == 4)
	var coins: int = run.coins
	for tick in range(10): run.step(Run.FIXED_STEP)
	check("重复帧不重复奖励", run.coins == coins)
	# 重定位夹具只平移世界参考；路线证明和复放不直接改角色坐标。
	run.install_block(block, 6100, "rebase")
	run.distance = 6000
	run.a.position.y = 6000
	run.b.position.y = 6000
	run.rope.reset(run.a.position, run.b.position)
	var absolute_receiver: float = run.charge_gate.receiver.y + run.world_origin
	run.update_stream()
	check("重定位保持机关世界位置", run.rebases == 1 and is_equal_approx(run.charge_gate.receiver.y + run.world_origin, absolute_receiver))
	check("联机哈希包含未到达机关", test_hash(run))
	run.pause()
	var frozen := run.sync_hash()
	for tick in range(30): run.step(Run.FIXED_STEP, Vector2.LEFT, Vector2.RIGHT)
	check("暂停冻结队列及充能", run.sync_hash() == frozen)
	run.pause()
	run.retry(true)
	check("重试清空组合与奖励并恢复教学", run.charge_gates.size() == 2 and run.charge_gate.id == "tutorial" and run.coins == 0)
	run.level_index = 1
	run.retry()
	check("下一关不残留机关或重复教学", run.charge_gates.is_empty() and not run.charge_gate.active)
	run.dispose()
	var background = Run.new(true, true)
	background.cancel_generation()
	check("取消后台生成无残留线程与机关", background.async_thread == null and background.async_job.is_empty() and background.charge_gates.is_empty())
	background.dispose()

func test_hash(run) -> bool:
	var before: int = run.sync_hash()
	run.charge_gates.back().charge = 0.3
	return before != run.sync_hash()
