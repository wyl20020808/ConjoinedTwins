extends SceneTree
const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")
const Keyboard = preload("res://tests/keyboard_route_assertions.gd")
var checks: Array = []
var campaigns: Array = []
var game
var run
var result_path := "res://tests/short-rope-t05-result.json"

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, ok: bool) -> void:
	checks.append({"name": name, "passed": ok})
	print("PASS " if ok else "FAIL ", name)

func scene_count(node: Node) -> int:
	var count := 1
	for child in node.get_children(): count += scene_count(child)
	return count

func signature() -> String:
	# 包含每步双方、跳跃、接触路径、动态规格、奖励、跨段/回收/重定位状态。
	return str(hash([run.a.position, run.b.position, run.heights, run.vertical_speed, run.rope.path, run.rope.contacts, run.rope.required, run.hazard_specs, run.obstacles, run.obstacle_ids, run.rewards, run.claimed_rewards, run.coins, run.prizes, run.shield, run.shield_uses, run.distance, run.world_origin, run.next_segment, run.recycled, run.rebases, run.state, run.results]))

func drive() -> Array:
	for segment in run.route_segments:
		if run.total_distance() >= segment.base and run.total_distance() < segment.base + Templates.SEGMENT:
			return Templates.route_input(run, segment.block, segment.base - run.world_origin)
	return Templates.route_input(run, Templates.make_block("safe", 0, run.level_index), run.distance)

func campaign(seed_value: int, difficulty: String, playback: Dictionary = {}) -> Dictionary:
	run.seed_value = seed_value
	run.difficulty = difficulty
	run.new_campaign()
	run.step(0)
	var levels: Array = []
	var overall_valid := true
	var peak_hazards := 0
	var peak_rewards := 0
	var peak_nodes := 0
	var peak_routes := 0
	var final_nodes: Array = []
	for level in range(3):
		var inputs: Array = []
		var hashes: Array = []
		var samples: Array = []
		var warnings := {}
		var route_names := {}
		var boundaries: Array = []
		var last_segment := -1
		var jump_seen := false
		var left_seen := false
		var right_seen := false
		var stagger_seen := false
		var double_seen := false
		var observed_kinds := {}
		var standalone_body := false
		var real_double := false
		var real_stagger := false
		var valid := true
		var illegal_inputs := 0
		var replay_level: Dictionary = playback.levels[level] if not playback.is_empty() else {}
		for tick in range(15000):
			var input: Array
			if not replay_level.is_empty():
				if tick >= replay_level.inputs.size():
					valid = false
					break
				var saved: Array = replay_level.inputs[tick]
				input = [Vector2(saved[0], saved[1]), Vector2(saved[2], saved[3]), saved[4], saved[5]]
			else: input = drive()
			inputs.append([input[0].x, input[0].y, input[1].x, input[1].y, input[2], input[3]])
			if not Keyboard.legal(inputs[-1]): illegal_inputs += 1
			run.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
			var digest := signature()
			hashes.append(digest)
			if not replay_level.is_empty(): valid = valid and digest == replay_level.hashes[tick]
			valid = valid and run.rope.required <= Run.LINK_LIMIT + 0.01 and run.shield_uses == 0 and absf(run.a.position.y - run.distance) <= Run.RELATIVE_RANGE + 0.01 and absf(run.b.position.y - run.distance) <= Run.RELATIVE_RANGE + 0.01
			jump_seen = jump_seen or (run.heights[0] > 20 and run.heights[1] > 20)
			left_seen = left_seen or (run.a.position.x < -80 and run.b.position.x < -80)
			right_seen = right_seen or (run.a.position.x > 80 and run.b.position.x > 80)
			stagger_seen = stagger_seen or absf(run.a.position.y - run.b.position.y) > 50
			for segment in run.route_segments:
				if run.total_distance() >= segment.base and run.total_distance() < segment.base + Templates.SEGMENT:
					# 检查正在经过的实际安装对象，不以路线名称或配置列表代替内容证明。
					var active_kinds := {}
					for hazard in segment.block.hazards:
						var present := false
						for index in range(run.kinds.size()):
							present = present or (run.kinds[index] == hazard.kind and is_equal_approx(run.obstacles[index].position.y + run.world_origin, segment.base + hazard.rect.position.y))
						if present:
							observed_kinds[hazard.kind] = true
							active_kinds[hazard.kind] = true
					standalone_body = standalone_body or (active_kinds.has("fly_body") and segment.block.hazards.size() == 1)
					real_double = real_double or (active_kinds.has("fly_body") and active_kinds.has("iron_ball"))
					for reward in run.rewards:
						if reward.get("staggered", false) and reward.position.y + run.world_origin >= segment.base and reward.position.y + run.world_origin < segment.base + Templates.SEGMENT and reward.claimed:
							real_stagger = true
					route_names[segment.block.route] = true
					double_seen = double_seen or segment.block.route == "double"
					if segment.number != last_segment:
						boundaries.append(Templates.snapshot(run, tick))
						last_segment = segment.number
			for i in range(run.hazard_specs.size()):
				var spec: Dictionary = run.hazard_specs[i]
				if spec.get("locked", false): warnings[str(run.obstacle_ids[i])] = {"kind": run.kinds[i], "evidence": spec.warning_evidence.duplicate(true)}
			peak_hazards = maxi(peak_hazards, run.kinds.size())
			peak_rewards = maxi(peak_rewards, run.rewards.size())
			peak_routes = maxi(peak_routes, run.route_segments.size())
			if tick % 60 == 0:
				samples.append(Templates.snapshot(run, tick))
				game.sync_view()
				peak_nodes = maxi(peak_nodes, scene_count(game))
			if run.state != "running": break
		var name := "%s 种子%d 关%d%s" % [difficulty, seed_value, level + 1, "复放" if not playback.is_empty() else ""]
		valid = valid and illegal_inputs == 0
		check(name + "全部输入为生产键盘轴值", illegal_inputs == 0)
		check(name + "生产路线通关且无伤/短绳合法", valid and run.state == "settlement" and run.elapsed >= 90 and run.elapsed <= 120)
		check(name + "左右换边/双人跳跃/合作奖励", left_seen and right_seen and jump_seen and run.coins >= 20 and run.prizes >= 3)
		if level >= 1: check(name + "前后配合", stagger_seen)
		if level == 2: check(name + "双威胁组合", double_seen)
		var content_ok := observed_kinds.has("pillar") and observed_kinds.has("stone_ball") and observed_kinds.has("fly_low")
		if level >= 1: content_ok = content_ok and observed_kinds.has("iron_ball") and observed_kinds.has("fly_body") and standalone_body and real_stagger
		if level == 2: content_ok = content_ok and real_double
		check(name + "实际安装威胁及教学内容覆盖", content_ok)
		var warning_ok := not warnings.is_empty()
		for entry in warnings.values():
			var evidence: Dictionary = entry.evidence
			warning_ok = warning_ok and evidence.ttc >= evidence.joint_change_time + 0.35 - 0.025 and evidence.ttc >= Templates.DIFFICULTIES[difficulty].front_warning - 0.025
		check(name + "真实TTC预警与换边时间", warning_ok)
		overall_valid = overall_valid and valid and content_ok and run.state == "settlement"
		levels.append({"inputs": inputs, "input_encoding": "01横/纵、02横/纵原始键盘轴值-1/0/1；空格、回车按下状态", "illegal_inputs": illegal_inputs, "hashes": hashes, "samples": samples, "boundaries": boundaries, "warnings": warnings, "routes": route_names.keys(), "seconds": run.elapsed, "coins": run.coins, "prizes": run.prizes, "rejections": run.generator.rejection_evidence.duplicate(true), "rebases": run.rebases, "recycled": run.recycled})
		levels[-1].content = {"installed_kinds": observed_kinds.keys(), "standalone_body": standalone_body, "double_threats": real_double, "staggered_prize_claimed": real_stagger, "passed": content_ok}
		game.sync_view()
		final_nodes.append(scene_count(game))
		if run.state != "settlement": break
		run.step(Run.FIXED_STEP)
		run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, true, true)
		run.step(0)
	check("%s 种子%d三关完成" % [difficulty, seed_value], run.state == "complete" and run.results.size() == 3)
	check("%s 种子%d资源上限" % [difficulty, seed_value], peak_hazards <= Templates.MAX_HAZARDS and peak_rewards <= Run.Levels.MAX_REWARDS and peak_nodes < Templates.MAX_SCENE_NODES and peak_routes <= 8)
	print("PEAK ", peak_hazards, " ", peak_rewards, " ", peak_nodes, " ", peak_routes, " nodes=", final_nodes)
	return {"seed": seed_value, "difficulty": difficulty, "valid": overall_valid, "levels": levels, "peak_hazards": peak_hazards, "peak_rewards": peak_rewards, "peak_nodes": peak_nodes, "peak_routes": peak_routes, "final_nodes": final_nodes, "score": run.total_score()}

func verify() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.capture_mode = true
	run = game.run
	check("独立输入断言拒绝比例轴及任意角度", not Keyboard.legal([0.5379, 0, 0, 0, false, false]) and not Keyboard.legal([0.640185, 0.768221, 0, 0, false, false]) and Keyboard.legal([1, -1, 0, 1, true, false]))
	var difficulties: Array = Templates.DIFFICULTIES.keys()
	var batches := {"easy": "简单", "normal": "普通", "hard": "困难"}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--batch="):
			var batch: String = argument.trim_prefix("--batch=")
			assert(batches.has(batch))
			difficulties = [batches[batch]]
			result_path = "res://tests/short-rope-t05-batch-%s.json" % batch
	write_checkpoint()
	for difficulty in difficulties:
		for seed_value in [20261013, 7, 42]:
			var recorded := campaign(seed_value, difficulty)
			campaigns.append(recorded)
			if recorded.valid and recorded.levels.size() == 3:
				var replayed := campaign(seed_value, difficulty, recorded)
				check("%s 种子%d逐固定步完整复现" % [difficulty, seed_value], replayed.valid and replayed.score == recorded.score)
				check("%s 种子%d场景池稳定不增长" % [difficulty, seed_value], replayed.final_nodes[-1] <= recorded.final_nodes[-1])
			write_checkpoint()
	var generator = Templates.new()
	var impossible := Templates.make_block("safe", 0, 0)
	impossible.hazards.append({"kind": "cargo", "rect": Rect2(-246, 180, 492, 65)})
	check("人为无解宽墙经生产输入拒绝", not generator.validate_block(impossible, "普通", 0) and not generator.last_evidence.reason.is_empty())
	var failure_evidence: Dictionary = generator.last_evidence.duplicate(true)
	generator.reset(42)
	var rejected := false
	var fallback := false
	for number in range(100):
		var block: Dictionary = generator.generate_block(number, "普通", 2)
		if block.route == "safe":
			rejected = generator.rejected > 0 and not generator.rejection_evidence.is_empty()
			fallback = generator.validate_block(block, "普通", 2)
			break
	check("无解候选留下拒绝原因且回退经生产验证", rejected and fallback)
	var fallback_legal := true
	for input in generator.last_evidence.inputs: fallback_legal = fallback_legal and Keyboard.legal(input)
	check("无解及安全回退证书均为合法键盘输入", fallback_legal and failure_evidence.illegal_inputs == 0)
	var failed := 0
	for entry in checks:
		if not entry.passed: failed += 1
	write_checkpoint(true, {"impossible": failure_evidence, "fallbacks": generator.rejection_evidence, "fallback_certificate": generator.last_evidence})
	print("RESULT failed=", failed)
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)

func write_checkpoint(completed: bool = false, extra: Dictionary = {}) -> void:
	var failed := 0
	for entry in checks:
		if not entry.passed: failed += 1
	var report := {"completed": completed, "passed": completed and failed == 0, "failed": failed, "checks": checks, "campaigns": campaigns, "executor_self_test": true, "controller_tests": [], "gui": "not_run_by_user_instruction", "user_playtest": "pending"}
	report.merge(extra)
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
