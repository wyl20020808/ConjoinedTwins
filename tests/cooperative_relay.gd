extends SceneTree

const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")
var failures := 0
var checks := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	print("PASS " if passed else "FAIL ", label)
	if not passed: failures += 1

func _initialize() -> void:
	var block := Templates.make_block("charge_sync_relay", 1, 0)
	check("生产双门模板", block.get("gates", []).size() == 2)
	check("生产退出区有完整奖励链", block.rewards.size() == 3 and block.rewards.all(func(r): return r.position.y > 600 and r.position.y < Templates.SEGMENT))
	if block.get("gates", []).size() == 2:
		var run = Run.new(false)
		run.install_block(block, 0, "relay")
		check("双门安装", run.charge_gates.size() == 2)
		check("首门选择", run.charge_gate.get("id", "") == "relay:gate:0")
		run.install_block(block, 0, "relay")
		check("安装幂等", run.charge_gates.size() == 2)
		run.dispose()
		verify_bags()
		verify_matrix()
		verify_lifecycle()
		verify_failure_restore()
	print("RELAY checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func new_run(difficulty: String, level: int, seed_value: int):
	var run = Run.new(false)
	run.difficulty = difficulty
	run.level_index = level
	run.random_seed = false
	run.seed_value = seed_value
	run.charge_tutorial = true
	run.generation_enabled = true
	run.retry()
	return run

func fingerprint(run, tick: int) -> String:
	return var_to_str([Templates.snapshot(run, tick), run.claimed_rewards, run.sync_hash()]).sha256_text()

func route(run, swap: bool) -> Array:
	var axes := Templates.existing_route_input(run)
	var gate: Dictionary = run.charge_gate
	if swap and gate.active and not gate.open and gate.has("relay_index") and run.distance >= gate.receiver.y - 100:
		var left: Vector2 = gate.left.get_center() if gate.get("kind", "charge") == "sync_plates" else Vector2(-65, gate.receiver.y)
		var right: Vector2 = gate.right.get_center() if gate.get("kind", "charge") == "sync_plates" else Vector2(65, gate.receiver.y)
		axes = [Templates.keyboard_direction(right - run.a.position), Templates.keyboard_direction(left - run.b.position), false, false]
	return axes

func verify_bags() -> void:
	var valid := true
	for level in range(3):
		for seed_value in range(100):
			for previous in ["sync_cargo", "charge_sync_relay"]:
				var generator = Templates.new()
				generator.reset(seed_value)
				generator.last_kind = previous
				var plates := false
				var relay := false
				for index in range(12):
					var block: Dictionary = generator.candidate_block(index, level)
					valid = valid and (index != 0 or block.route != previous)
					if index < 8: plates = plates or block.route == "sync_cargo"
					relay = relay or block.route == "charge_sync_relay"
					valid = valid and (block.route != "charge_sync_relay" or block.hazards.is_empty())
				valid = valid and plates and relay
	check("三关100种子保留踏板及接力袋契约", valid)

func verify_matrix() -> void:
	if OS.get_environment("RELAY_SKIP_MATRIX") == "1": return
	var output := OS.get_environment("COOPERATIVE_RELAY_EVIDENCE")
	if output.is_empty():
		check("必须显式隔离证据目录", false)
		return
	DirAccess.make_dir_recursive_absolute(output)
	for difficulty in Templates.DIFFICULTIES:
		if OS.get_environment("RELAY_DIFFICULTY") != "" and OS.get_environment("RELAY_DIFFICULTY") != difficulty: continue
		for level in range(3):
			for seed_value in [4242, 812208, 20261014]:
				for swap in [false, true]:
					var stem := "%s-%d-%d-%s" % [difficulty, level + 1, seed_value, "swap" if swap else "normal"]
					if OS.get_environment("RELAY_CASE") != "" and OS.get_environment("RELAY_CASE") != stem: continue
					var path := output + "/" + stem + ".jsonl"
					if FileAccess.file_exists(path):
						check("拒绝覆盖既有路线 " + stem, false)
						continue
					var run = new_run(difficulty, level, seed_value)
					var file := FileAccess.open(path, FileAccess.WRITE)
					file.store_line(JSON.stringify({"source_binding": Templates.source_binding(), "difficulty": difficulty, "level": level, "seed": seed_value, "swap": swap, "initial": fingerprint(run, 0)}))
					var target := {}
					var valid := true
					var tick := 0
					var claimed := false
					while tick < 24000 and run.state == "running":
						for segment in run.route_segments:
							if target.is_empty() and segment.block.route == "charge_sync_relay": target = segment.duplicate(true)
						var axes := route(run, swap)
						valid = valid and Templates.keyboard_legal(axes[0]) and Templates.keyboard_legal(axes[1])
						var previous := [run.a.position, run.b.position]
						var origin: float = run.world_origin
						var closed: Dictionary = run.charge_gate.duplicate(true)
						run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
						tick += 1
						valid = valid and run.rope.required <= Run.LINK_LIMIT + 0.01 and not run.rope_failed and run.shield_uses == 0
						for role in range(2):
							var point: Vector2 = run.a.position if role == 0 else run.b.position
							valid = valid and previous[role].distance_to(point + Vector2(0, run.world_origin - origin)) <= 7.0
							if closed.active and not closed.open: valid = valid and point.y + run.world_origin <= closed.door.position.y + origin - Run.Motion.RADIUS + 0.01
						var gates := []
						for gate in run.charge_gates:
							gates.append({"id": gate.id, "open": gate.open, "charge": gate.charge, "occupied": gate.get("occupied", [])})
						file.store_line(JSON.stringify({"input": [axes[0].x, axes[0].y, axes[1].x, axes[1].y, axes[2], axes[3]], "state": fingerprint(run, tick), "gates": gates,
							"a": [run.a.position.x, run.a.position.y], "b": [run.b.position.x, run.b.position.y], "origin": run.world_origin, "heights": run.heights, "rope_length": run.rope.required}))
						if not target.is_empty() and run.total_distance() >= target.base + Templates.SEGMENT:
							claimed = true
							for slot in range(target.block.rewards.size()):
								claimed = claimed and run.claimed_rewards.has("%d:%d:%d" % [level, target.number, slot])
							break
					file.close()
					var replay = new_run(difficulty, level, seed_value)
					file = FileAccess.open(path, FileAccess.READ)
					var header: Dictionary = JSON.parse_string(file.get_line())
					var same: bool = header.initial == fingerprint(replay, 0) and header.source_binding == Templates.source_binding()
					var replay_tick := 0
					while file.get_position() < file.get_length():
						var entry: Dictionary = JSON.parse_string(file.get_line())
						var axes: Array = entry.input
						replay.step(Run.FIXED_STEP, Vector2(axes[0], axes[1]), Vector2(axes[2], axes[3]), axes[4], axes[5])
						replay_tick += 1
						same = same and entry.state == fingerprint(replay, replay_tick)
					file.close()
					var id := "" if target.is_empty() else "%d:%d:gate:" % [level, target.number]
					var opens: Array = run.gate_events.filter(func(e): return e.event == "opened" and e.id.begins_with(id)) if not id.is_empty() else []
					var opened: bool = opens.size() == 2 and opens[0].id == id + "0" and opens[1].id == id + "1"
					check("生产接力落盘复放 " + stem, not target.is_empty() and valid and same and opened and claimed and run.state == "running")
					print("RELAY_ROUTE ", stem, " ticks=", tick, " replay=", same, " legal=", valid, " opened=", opened, " claimed=", claimed, " state=", run.state, " reason=", run.reason)
					var certificate := FileAccess.open(output + "/" + stem + ".certificate", FileAccess.WRITE)
					certificate.store_string(var_to_str({"target": target, "source_binding": Templates.source_binding(), "ticks": tick, "events": run.gate_events, "state": Templates.snapshot(run, tick), "claimed": run.claimed_rewards, "rejections": run.generator.rejection_evidence}))
					certificate.close()
					run.dispose()
					replay.dispose()

func walk(run, target: float, swap := false) -> bool:
	for tick in range(3200):
		var axes := route(run, swap)
		if not Templates.keyboard_legal(axes[0]) or not Templates.keyboard_legal(axes[1]): return false
		run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
		if run.state != "running" or run.rope.required > Run.LINK_LIMIT + 0.01: return false
		if run.total_distance() >= target: return true
	return false

func verify_lifecycle() -> void:
	for swap in [false, true]:
		var run = Run.new(false)
		run.retry()
		var block := Templates.make_block("charge_sync_relay", 1, 0)
		block.rewards = [{"kind": "coin", "position": Vector2(-25, 720), "radius": 20.0}]
		run.install_block(block, 0, "first")
		run.route_segments.append({"base": 0.0, "block": block})
		run.install_block(block, 840, "second")
		run.route_segments.append({"base": 840.0, "block": block})
		check("四门初态独立", run.charge_gates.size() == 4 and run.charge_gates[1].charge == 0 and not run.charge_gates[1].open)
		var clone = Templates.clone_state(Templates.capture_state(run))
		clone.charge_gate.charge = 0.1
		clone.charge_gates[1].occupied[0] = true
		check("克隆队列绑定及隔离", clone.charge_gates[0].charge == 0.1 and run.charge_gate.charge == 0 and not run.charge_gates[1].occupied[0])
		clone.dispose()
		for tick in range(180): run.step(Run.FIXED_STEP, Vector2.DOWN, Vector2.DOWN)
		check("未协作时门挡人且次门不计时", run.state == "running" and run.charge_gates.all(func(g): return not g.open and g.charge == 0) and maxf(run.a.position.y, run.b.position.y) <= run.charge_gate.door.position.y - Run.Motion.RADIUS + 0.01 and not run.rope_failed)
		check("首门合法到达", walk(run, 120, swap))
		var before := fingerprint(run, 0)
		run.pause()
		var frozen := fingerprint(run, 0)
		for tick in range(120): run.step(Run.FIXED_STEP, Vector2.LEFT, Vector2.RIGHT, true, true)
		check("充能暂停冻结", fingerprint(run, 0) == frozen and before != frozen)
		run.pause()
		var partial := false
		for tick in range(1600):
			var axes := route(run, swap)
			run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
			if run.charge_gate.get("relay_index", -1) == 1 and run.charge_gate.charge > 0.1 and not run.charge_gate.open:
				partial = true
				break
		check("首门锁存且次门独立开始计时", partial and run.gate_events.filter(func(e): return e.event == "opened").size() == 1 and run.coins == 0)
		run.pause()
		frozen = fingerprint(run, 0)
		for tick in range(120): run.step(Run.FIXED_STEP, Vector2.DOWN, Vector2.DOWN, true, true)
		check("次门充能暂停冻结", fingerprint(run, 0) == frozen)
		run.pause()
		for tick in range(120): run.step(Run.FIXED_STEP, Vector2.DOWN, Vector2.DOWN, tick == 0, tick == 0)
		check("离板跳跃不误开不夹人", not run.charge_gate.open and run.charge_gate.charge == 0 and run.gate_events.filter(func(e): return e.event == "opened").size() == 1 and run.state == "running" and not run.rope_failed and run.coins == 0)
		check("两接力交换角色退出", walk(run, 1840, swap))
		check("四门各开一次与回收", run.gate_events.filter(func(e): return e.event == "opened").size() == 4 and run.charge_gates.is_empty())
		check("金币不重复", run.coins == 2 and run.claimed_rewards.size() == 2)
		for tick in range(30): run.step(Run.FIXED_STEP)
		check("重复帧不再奖励", run.coins == 2)
		var events: int = run.gate_events.size()
		run.install_block(block, 0, "first")
		check("回收后同ID重装仍幂等", run.charge_gates.is_empty() and run.gate_events.size() == events)
		run.install_block(block, 2000, "reuse")
		check("新实例重置", run.charge_gates.size() == 2 and run.charge_gates[1].occupied == [false, false] and not run.charge_gate.open)
		run.retry()
		check("重试清空门及奖励", run.charge_gates.is_empty() and run.coins == 0 and run.claimed_rewards.is_empty())
		# 以下为独立坐标重定位夹具，不纳入生产无瞬移路线证明。
		run.install_block(block, 6100, "rebase")
		run.charge_gates[0].open = true
		run.charge_gates[1].charge = 0.123
		run.select_charge_gate()
		run.distance = 6000
		run.a.position.y = 6000
		run.b.position.y = 6000
		run.rope.reset(run.a.position, run.b.position)
		var world: float = run.charge_gates[1].left.position.y + run.world_origin
		run.update_stream()
		check("两门重定位保留锁存计时", run.rebases == 1 and run.charge_gates[0].open and run.charge_gate.charge == 0.123 and run.charge_gate.left.position.y + run.world_origin == world)
		run.dispose()

func verify_failure_restore() -> void:
	for swap in [false, true]:
		var run = Run.new(false)
		run.retry()
		var block := Templates.make_block("charge_sync_relay", 1, 0)
		run.install_block(block, 0, "failure")
		run.route_segments.append({"base": 0.0, "block": block})
		for tick in range(1600):
			var axes := route(run, swap)
			run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
			if run.charge_gate.get("relay_index", -1) == 1 and run.charge_gate.charge > 0.1: break
		check("恢复夹具真实输入完成首门", run.gate_events.filter(func(e): return e.event == "opened").size() == 1 and not run.charge_gate.open)
		# 直接触发生产失败入口，独立测试恢复，不充当无瞬移路线或碰撞证明。
		run.fail_threat("接力恢复夹具")
		run.retry(true)
		run.install_block(block, 0, "failure")
		check("次门前失败重试重置两门", run.state == "running" and run.failures == 1 and run.charge_gates.size() == 2 and run.charge_gates.all(func(g): return not g.open and g.charge == 0) and run.claimed_rewards.is_empty() and run.heights == [0.0, 0.0])
		# 独立结算状态夹具验证生产双人确认入口。
		run.state = "settlement"
		run.confirm_step(false, false)
		run.confirm_step(true, true)
		check("双人确认换关清空旧门", run.level_index == 1 and run.state == "running" and run.charge_gates.is_empty())
		run.dispose()
