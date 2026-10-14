extends "res://tests/cooperative_relay.gd"
# 提示必须反映真实缺失条件；错误复用门型、腾空误计时或恢复残留会使本测试失败。

func _initialize() -> void:
	var run = Run.new(false)
	if not run.has_method("gate_hint"):
		check("生产等待提示入口存在", false)
		run.dispose()
		print("RECOVERY checks=", checks, " failures=", failures)
		quit(1)
		return
	verify_conditions(run)
	run.dispose()
	verify_hint_routes()
	verify_matrix()
	verify_lifecycle()
	verify_failure_restore()
	print("RECOVERY checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func verify_conditions(run) -> void:
	var gate := Run.ChargeGate.make_tutorial()
	var path := PackedVector2Array([Vector2(-65, 60), Vector2(65, 60)])
	var heights := PackedFloat32Array([28, 28])
	Run.ChargeGate.advance(gate, path, heights, 0.9, true, 0.1)
	check("充能正确高度开始计时", gate.charge > 0 and run.gate_hint(gate).contains("持续"))
	check("正常等待中文完整", run.gate_hint(gate).contains("可安全等待 · 可回撤调整") and run.gate_hint(gate).contains(" 秒"))
	Run.ChargeGate.advance(gate, path, PackedFloat32Array([40, 40]), 0.9, true, 0.1)
	check("绳路过高清零并提示高度", gate.charge == 0 and run.gate_hint(gate).contains("高度"))
	Run.ChargeGate.advance(gate, path, heights, 0.5, true, 0.1)
	check("张紧不足清零并提示", gate.charge == 0 and run.gate_hint(gate).contains("张紧"))
	Run.ChargeGate.advance(gate, PackedVector2Array([Vector2(-10, 60), Vector2(10, 60)]), heights, 0.9, true, 0.1)
	check("站位不足提示绿区", gate.charge == 0 and run.gate_hint(gate).contains("绿区"))
	Run.ChargeGate.advance(gate, path, heights, 0.9, false, 0.1)
	check("绳路受阻提示调整", gate.charge == 0 and run.gate_hint(gate).contains("受阻"))
	check("真实受阻不承诺安全等待", not run.gate_hint(gate).contains("可安全等待"))
	check("受阻恢复中文完整", run.gate_hint(gate).contains("绳路受阻时请及时回撤调整"))
	Run.ChargeGate.advance(gate, path, heights, 0.9, true, 0.8)
	check("充能锁存显示已开启", gate.open and run.gate_hint(gate).contains("已开启"))
	Run.ChargeGate.advance(gate, path, heights, 0.1, false, 0.8)
	check("失去条件不覆盖已开提示", gate.open and run.gate_hint(gate).contains("已开启"))
	gate = Run.SyncPlates.make_tutorial()
	var left: Vector2 = gate.left.get_center()
	var right: Vector2 = gate.right.get_center()
	Run.SyncPlates.advance(gate, left, left, true, true, 0.4)
	check("同板不开并提示分别占板", not gate.open and run.gate_hint(gate).contains("各站一板"))
	Run.SyncPlates.advance(gate, left, right, false, true, 0.4)
	var hint: String = run.gate_hint(gate)
	check("腾空不计时提示落地", gate.charge == 0 and hint.contains("落地"))
	check("踏板无充能专属要求或失败倒计时", not hint.contains("张紧") and not hint.contains("高度") and not hint.contains("失败"))
	Run.SyncPlates.advance(gate, right, left, true, true, 0.1)
	check("交换板位计时提示站稳", gate.charge > 0 and run.gate_hint(gate).contains("站稳"))
	Run.SyncPlates.advance(gate, right, left, true, true, 0.25)
	check("踏板锁存显示已开启", gate.open and run.gate_hint(gate).contains("已开启"))

func verify_hint_routes() -> void:
	for difficulty in Templates.DIFFICULTIES:
		for swap in [false, true]:
			var run = Run.new(false)
			run.difficulty = difficulty
			run.retry()
			var block := Templates.make_block("charge_sync_relay", 1, 0)
			run.install_block(block, 0, "recovery")
			run.route_segments.append({"base": 0.0, "block": block})
			var first_progress := false
			var second_progress := false
			var retreated := false
			var paused := false
			var hints_valid := true
			var legal := true
			for tick in range(3200):
				var gate: Dictionary = run.charge_gate
				var axes := route(run, swap)
				if gate.get("relay_index", -1) == 1 and gate.charge > 0.05 and not retreated:
					var frozen: String = run.gate_hint(gate)
					run.pause()
					var state := fingerprint(run, 0)
					for frame in range(30): run.step(Run.FIXED_STEP, Vector2.UP, Vector2.UP, true, true)
					paused = fingerprint(run, 0) == state and run.gate_hint(gate) == frozen
					run.pause()
					var before: float = run.a.position.y
					for frame in range(30): run.step(Run.FIXED_STEP, Vector2.UP, Vector2.UP)
					retreated = run.a.position.y < before and gate.charge == 0 and not gate.open
					axes = route(run, swap)
				legal = legal and Templates.keyboard_legal(axes[0]) and Templates.keyboard_legal(axes[1])
				run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
				for current in run.charge_gates:
					var hint: String = run.gate_hint(current)
					hints_valid = hints_valid and not hint.contains("失败倒计时")
					if current.open: hints_valid = hints_valid and hint.contains("已开启")
					if current.get("kind", "charge") == "sync_plates":
						hints_valid = hints_valid and not hint.contains("张紧") and not hint.contains("高度")
						second_progress = second_progress or current.charge > 0
					else: first_progress = first_progress or current.charge > 0
				if run.total_distance() > 1000 or run.state != "running": break
			check("提示与合法接力路线 " + difficulty + str(swap), legal and hints_valid and first_progress and second_progress and retreated and paused and run.state == "running" and run.gate_events.filter(func(e): return e.event == "opened").size() == 2)
			run.fail_threat("提示恢复夹具")
			run.retry(true)
			run.install_block(block, 0, "recovery")
			check("失败重试提示重置 " + difficulty + str(swap), run.charge_gates.all(func(g): return not g.open and g.charge == 0 and not run.gate_hint(g).contains("已开启")))
			run.dispose()
