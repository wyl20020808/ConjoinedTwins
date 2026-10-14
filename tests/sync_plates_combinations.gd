extends SceneTree

const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")
const Threats = preload("res://scripts/dynamic_threats.gd")
var failures := 0
var checks := 0
var output := OS.get_environment("SYNC_COMBINATIONS_EVIDENCE")

func check(label: String, passed: bool) -> void:
	checks += 1
	print("PASS " if passed else "FAIL ", label)
	if not passed: failures += 1

func _initialize() -> void:
	var bag_ok := true
	for seed_value in range(100):
		var generator=Templates.new()
		generator.reset(seed_value)
		generator.last_kind="sync_cargo"
		var found := false
		for index in range(8):
			var route: String=generator.candidate_block(index,0).route
			bag_ok=bag_ok and (index!=0 or route!="sync_cargo")
			found=found or route=="sync_cargo"
		bag_ok=bag_ok and found
	check("袋重洗不连抽且前八段有踏板",bag_ok)
	var threat := Threats.spec("fly_low", 1.9)
	Threats.warn(threat, Rect2(-28, 1100, 56, 24), [Vector2(-25,0),Vector2(25,0)], [Vector2(0,250),Vector2(0,250)], 300,180,14,0,550)
	check("合法前向换键前预警", threat.locked and threat.warning_evidence.ttc >= 1.875)
	var block := Templates.make_block("sync_cargo", 1, 0)
	check("随机踏板货箱组合存在", block.has("gate") and block.get("gate", {}).get("kind", "") == "sync_plates")
	if block.has("gate"):
		verify_routes()
		verify_lifecycle()
		verify_waiting()
	print("SYNC_COMBINATIONS checks=", checks, " failures=", failures)
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

func verify_routes() -> void:
	if output.is_empty(): output = "user://sync-combinations"
	DirAccess.make_dir_recursive_absolute(output)
	var binding := Templates.source_binding()
	for difficulty in Templates.DIFFICULTIES:
		for level in range(3):
			for seed_value in [4242, 812208, 20261014]:
				if OS.get_environment("SYNC_CASE") != "" and OS.get_environment("SYNC_CASE") != "%s-%d-%d" % [difficulty, level+1, seed_value]: continue
				var stem := "%s-%d-%d" % [difficulty, level+1, seed_value]
				var run = new_run(difficulty, level, seed_value)
				var initial_shield_uses: int=run.shield_uses
				var file := FileAccess.open(output + "/" + stem + ".jsonl", FileAccess.WRITE)
				file.store_line(JSON.stringify({"source_binding": binding, "difficulty": difficulty, "level": level, "seed": seed_value, "initial": fingerprint(run, 0)}))
				var target := {}
				var valid := true
				var tick := 0
				var claimed := false
				while tick < 22000 and run.state == "running":
					for segment in run.route_segments:
						if target.is_empty() and segment.block.route == "sync_cargo": target = segment.duplicate(true)
					var axes := Templates.existing_route_input(run)
					valid = valid and Templates.keyboard_legal(axes[0]) and Templates.keyboard_legal(axes[1])
					var previous := [run.a.position, run.b.position]
					var origin: float = run.world_origin
					var closed: Dictionary = run.charge_gate.duplicate(true)
					run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
					tick += 1
					valid = valid and run.rope.required <= Run.LINK_LIMIT + 0.01 and not run.rope_failed and run.shield_uses==initial_shield_uses
					for role in range(2):
						var point: Vector2 = run.a.position if role == 0 else run.b.position
						valid = valid and previous[role].distance_to(point + Vector2(0, run.world_origin-origin)) <= 7.0
						if closed.active and not closed.open: valid = valid and point.y + run.world_origin <= closed.door.position.y + origin - Run.Motion.RADIUS + 0.01
					file.store_line(JSON.stringify({"input": [axes[0].x, axes[0].y, axes[1].x, axes[1].y, axes[2], axes[3]], "state": fingerprint(run, tick)}))
					if not target.is_empty() and run.total_distance() >= target.base + Templates.SEGMENT:
						claimed = true
						for slot in range(target.block.rewards.size()):
							claimed = claimed and run.claimed_rewards.has("%d:%d:%d" % [level, target.number, slot])
						break
				file.close()
				if run.state != "running":
					print("SYNC_DEBUG ", stem, " route=",run.generator.last_evidence.get("route")," reason=",run.generator.last_evidence.get("reason")," shield=",run.generator.last_evidence.get("shield_uses_before"),"/",run.generator.last_evidence.get("shield_uses_after")," rejects=",run.generator.rejection_evidence.size())
					print("SYNC_WARNING ",var_to_str(run.generator.last_evidence.get("warnings", {})))
					var collision: Dictionary = run.generator.last_evidence.get("shield_collision", {})
					if not collision.is_empty(): print("SYNC_COLLISION tick=",collision.tick," local=",collision.local_y," a=",collision.state.a," b=",collision.state.b," events=",collision.events)
					if OS.get_environment("SYNC_DEBUG_ONE") == "1":
						run.dispose()
						failures += 1
						return
				var replay = new_run(difficulty, level, seed_value)
				file = FileAccess.open(output + "/" + stem + ".jsonl", FileAccess.READ)
				var header: Dictionary = JSON.parse_string(file.get_line())
				var same: bool = header.source_binding == Templates.source_binding() and header.initial == fingerprint(replay, 0)
				var replay_tick := 0
				while file.get_position() < file.get_length():
					var entry: Dictionary = JSON.parse_string(file.get_line())
					var axes: Array = entry.input
					replay.step(Run.FIXED_STEP, Vector2(axes[0], axes[1]), Vector2(axes[2], axes[3]), axes[4], axes[5])
					replay_tick += 1
					same = same and entry.state == fingerprint(replay, replay_tick)
				file.close()
				var id := "" if target.is_empty() else "%d:%d:gate" % [level, target.number]
				var opens: Array = run.gate_events.filter(func(e): return e.event == "opened")
				var opened: bool = opens.filter(func(e): return e.id == id).size() == 1
				var ordered: bool = level != 0 or (opens.size() >= 3 and opens[0].id == "tutorial" and opens[1].id == "sync_tutorial")
				check("生产随机池落盘复放 " + stem, not target.is_empty() and valid and same and opened and ordered and claimed and run.state == "running")
				print("SYNC_COMBO ", stem, " ticks=",tick," replay=",same," legal=",valid," opened=",opened," claimed=",claimed," segment=",target.get("number",-1)," state=",run.state," reason=",run.reason)
				var certificate := FileAccess.open(output + "/" + stem + ".certificate", FileAccess.WRITE)
				certificate.store_string(var_to_str({"target": target, "source_binding": binding, "ticks": tick, "events": run.gate_events, "rejections": run.generator.rejection_evidence, "state": Templates.snapshot(run,tick), "claimed": run.claimed_rewards,"shield_uses":run.shield_uses,"initial_shield_uses":initial_shield_uses}))
				certificate.close()
				run.dispose()
				replay.dispose()

func walk(run, target: float, limit: int = 2400, swap := false) -> bool:
	for tick in range(limit):
		var axes := Templates.existing_route_input(run)
		if swap and run.charge_gate.active and not run.charge_gate.open and run.charge_gate.get("kind", "charge") == "sync_plates" and run.distance >= run.charge_gate.receiver.y - 100:
			axes = [Templates.keyboard_direction(run.charge_gate.right.get_center()-run.a.position), Templates.keyboard_direction(run.charge_gate.left.get_center()-run.b.position), false, false]
		if not Templates.keyboard_legal(axes[0]) or not Templates.keyboard_legal(axes[1]): return false
		run.step(Run.FIXED_STEP, axes[0], axes[1], axes[2], axes[3])
		if run.state != "running" or run.rope.required > Run.LINK_LIMIT+0.01: return false
		if run.total_distance() >= target: return true
	return false

func verify_lifecycle() -> void:
	for side in [-1, 1]:
		var run = Run.new(false)
		run.charge_tutorial = true
		run.retry()
		check("教学合法到达组合 " + str(side), walk(run,450))
		var block := Templates.make_block("sync_cargo",side,0)
		run.install_block(block,500,"first")
		run.route_segments.append({"base":500.0,"block":block})
		run.install_block(Templates.make_block("sync_cargo",-side,0),1340,"second")
		run.route_segments.append({"base":1340.0,"block":Templates.make_block("sync_cargo",-side,0)})
		check("预加载踏板门独立 " + str(side), run.charge_gates.size()==3 and run.charge_gates[1].id != run.charge_gates[2].id and run.charge_gates[2].charge==0)
		var clone = Templates.clone_state(Templates.capture_state(run))
		clone.charge_gate.charge=0.2
		clone.charge_gate.occupied[0]=true
		check("克隆绑定队列且隔离 " + str(side), clone.charge_gates.any(func(g): return g.id==clone.charge_gate.id and g.charge==0.2) and run.charge_gate.charge==0 and not run.charge_gate.occupied[0])
		clone.dispose()
		check("交换站板及同侧绕行 " + str(side), walk(run,2180,2400,true))
		check("回收及奖励只领取一次 " + str(side), run.charge_gates.is_empty() and run.coins==4 and run.gate_events.filter(func(e): return e.event=="opened").size()==4)
		var coins: int=run.coins
		for tick in range(10): run.step(Run.FIXED_STEP)
		check("重复帧无奖励 " + str(side), run.coins==coins)
		run.install_block(block,2300,"reuse")
		check("新实例无旧占用 " + str(side), run.charge_gate.id=="reuse:gate" and run.charge_gate.charge==0 and run.charge_gate.occupied==[false,false] and not run.charge_gate.open)
		var count: int=run.charge_gates.size()
		run.install_block(block,2300,"reuse")
		check("相同门 ID 幂等 " + str(side), run.charge_gates.size()==count)
		run.pause()
		var frozen := fingerprint(run,0)
		for tick in range(30): run.step(Run.FIXED_STEP,Vector2.LEFT,Vector2.RIGHT)
		check("暂停冻结多门 " + str(side), fingerprint(run,0)==frozen)
		run.pause()
		run.retry()
		check("重试恢复教学清空奖励 " + str(side), run.charge_gates.size()==2 and run.coins==0 and run.claimed_rewards.is_empty())
		run.level_index=1
		run.retry()
		check("关卡切换不串门 " + str(side), run.charge_gates.is_empty())
		# 独立重定位夹具，不纳入合法路线证据。
		run.install_block(block,6100,"rebase")
		run.charge_gate.charge=0.123
		run.distance=6000
		run.a.position.y=6000
		run.b.position.y=6000
		run.rope.reset(run.a.position,run.b.position)
		var absolute: float=run.charge_gate.left.position.y+run.world_origin
		run.update_stream()
		check("重定位保留实例状态 " + str(side),run.rebases==1 and run.charge_gate.id=="rebase:gate" and run.charge_gate.charge==0.123 and run.charge_gate.left.position.y+run.world_origin==absolute)
		run.dispose()

func verify_waiting() -> void:
	var run = Run.new(false)
	run.charge_tutorial = true
	run.retry()
	check("等待夹具合法到达", walk(run,450))
	var block := Templates.make_block("sync_cargo",1,0)
	run.install_block(block,500,"waiting")
	run.route_segments.append({"base":500.0,"block":block})
	for tick in range(240): run.step(Run.FIXED_STEP)
	var stopped: float = run.distance
	for tick in range(120): run.step(Run.FIXED_STEP)
	check("关闭组合可安全等待", run.state=="running" and not run.charge_gate.open and run.distance==stopped and run.shield_uses==0)
	var before: float=run.a.position.y
	for tick in range(24): run.step(Run.FIXED_STEP,Vector2.UP,Vector2.UP)
	check("关闭组合合法回撤", run.a.position.y<before-40 and run.b.position.y<before-40 and not run.charge_gate.open)
	for tick in range(120): run.step(Run.FIXED_STEP,Vector2.DOWN,Vector2.DOWN,true,true)
	check("关闭门保持身体与绳路碰撞", not run.charge_gate.open and maxf(run.a.position.y,run.b.position.y)<=run.charge_gate.door.position.y-Run.Motion.RADIUS+0.01 and run.rope.required<=Run.LINK_LIMIT+0.01)
	check("等待回撤后仍能合作退出", walk(run,1340) and run.coins==2 and run.shield_uses==0)
	run.dispose()
