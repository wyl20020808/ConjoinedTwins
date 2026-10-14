extends "res://tests/cooperative_relay_recovery.gd"

# 真实固定步输入制造踏板腾空与落地；保存双方轴值及分侧反馈后逐帧复放。
func setup_route(difficulty: String):
	var run = Run.new(false)
	run.difficulty = difficulty
	run.random_seed = false
	run.seed_value = 4242
	run.retry()
	var block := Templates.make_block("charge_sync_relay", 1, 0)
	run.install_block(block, 0, "side-route")
	run.route_segments.append({"base": 0.0, "block": block})
	return run

func side_snapshot(run) -> Array:
	var values := []
	for gate in run.charge_gates:
		values.append([gate.id, gate.get("conditions", {}), run.gate_side_feedback(gate), run.gate_hint(gate)])
	return values

func _initialize() -> void:
	var output := OS.get_environment("COOPERATIVE_RELAY_EVIDENCE")
	if output.is_empty():
		check("分侧路线必须显式隔离证据", false)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	for difficulty in Templates.DIFFICULTIES:
		for swap in [false, true]:
			var path: String = output + "/" + difficulty + ("-swap" if swap else "-normal") + ".jsonl"
			if FileAccess.file_exists(path):
				check("拒绝覆盖已有分侧路线", false)
				continue
			var run = setup_route(difficulty)
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_line(JSON.stringify({"source_binding": Templates.source_binding(), "difficulty": difficulty, "swap": swap, "seed": 4242}))
			var observed := {}
			var jumped := false
			var legal := true
			var tick := 0
			while tick < 3200 and run.state == "running" and run.total_distance() < 1000:
				var axes := route(run, swap)
				if run.charge_gate.get("kind", "charge") == "sync_plates" and run.charge_gate.charge > 0.05 and not jumped:
					axes[2] = true
					jumped = true
				legal = legal and Templates.keyboard_legal(axes[0]) and Templates.keyboard_legal(axes[1])
				run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
				tick += 1
				legal = legal and run.rope.required <= Run.LINK_LIMIT + 0.01 and not run.rope_failed
				for gate in run.charge_gates:
					for side in run.gate_side_feedback(gate): observed[side.state] = true
				file.store_line(JSON.stringify({"input": [axes[0].x, axes[0].y, axes[1].x, axes[1].y, axes[2], axes[3]], "sides": side_snapshot(run), "state": fingerprint(run, tick)}))
			file.close()
			var replay = setup_route(difficulty)
			file = FileAccess.open(path, FileAccess.READ)
			var header: Dictionary = JSON.parse_string(file.get_line())
			var same: bool = header.source_binding == Templates.source_binding()
			var replay_tick := 0
			while file.get_position() < file.get_length():
				var entry: Dictionary = JSON.parse_string(file.get_line())
				var axes: Array = entry.input
				replay.step(Run.FIXED_STEP, Vector2(axes[0], axes[1]), Vector2(axes[2], axes[3]), axes[4], axes[5])
				replay_tick += 1
				same = same and entry.state == fingerprint(replay, replay_tick) and JSON.stringify(entry.sides) == JSON.stringify(side_snapshot(replay))
			file.close()
			var opened: Array = run.gate_events.filter(func(e): return e.event == "opened")
			check("三难度正反角色分侧含真实腾空复放 " + difficulty + str(swap), legal and same and jumped and observed.has("airborne") and observed.has("holding") and observed.has("positioned") and observed.has("missing") and observed.has("opened") and run.state == "running" and run.total_distance() >= 1000 and opened.size() == 2)
			print("SIDE_ROUTE ", difficulty, " swap=", swap, " ticks=", tick, " legal=", legal, " replay=", same, " observed=", observed.keys(), " state=", run.state, " distance=", run.total_distance(), " events=", run.gate_events)
			run.dispose()
			replay.dispose()
	print("SIDE_ROUTES checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
