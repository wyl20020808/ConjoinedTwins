extends SceneTree
const Run = preload("res://scripts/road_run.gd")
const Keyboard = preload("res://tests/keyboard_route_assertions.gd")
var checks: Array = []
func _initialize() -> void:
	call_deferred("verify")
func check(name: String, ok: bool) -> void:
	checks.append({"name": name, "passed": ok})
	print("PASS " if ok else "FAIL ", name)
func verify() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/short-rope-t05-result.json"))
	var campaign: Dictionary = saved.campaigns[-1]
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.capture_mode = true
	var run = game.run
	run.seed_value = campaign.seed
	run.difficulty = campaign.difficulty
	run.new_campaign()
	run.step(0)
	for level in range(3):
		var valid := true
		var record: Dictionary = campaign.levels[level]
		for tick in range(record.inputs.size()):
			var input: Array = record.inputs[tick]
			valid = Keyboard.legal(input) and valid
			run.step(Run.FIXED_STEP, Vector2(input[0], input[1]), Vector2(input[2], input[3]), input[4], input[5])
			var digest := str(hash([run.a.position, run.b.position, run.heights, run.vertical_speed, run.rope.path, run.rope.contacts, run.rope.required, run.hazard_specs, run.obstacles, run.obstacle_ids, run.rewards, run.claimed_rewards, run.coins, run.prizes, run.shield, run.shield_uses, run.distance, run.world_origin, run.next_segment, run.recycled, run.rebases, run.state, run.results]))
			valid = valid and digest == record.hashes[tick]
			if tick % 120 == 0: game.sync_view()
		check("最终源码关%d输入/逐步状态复现" % [level + 1], valid and run.state == "settlement")
		var road_slots := 0
		for node in game.scenery:
			if node.has_meta("road_slot"): road_slots += 1
		check("关%d道路63槽与奖励24槽固定" % [level + 1], road_slots == 63 and game.reward_views.size() == 24)
		run.step(Run.FIXED_STEP)
		run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, true, true)
		run.step(0)
	check("最终源码三关总分一致", run.state == "complete" and run.total_score() == campaign.score)
	var generator = Run.Templates.new()
	generator.reset(42)
	var fallback_evidence := {}
	for number in range(100):
		var block: Dictionary = generator.generate_block(number, "困难", 2)
		if block.route == "safe":
			fallback_evidence = generator.verified["困难:2:safe"].duplicate(true)
			break
	check("最终源码安全回退显式生产验证并留下证据", not fallback_evidence.is_empty() and fallback_evidence.accepted and generator.rejected > 0 and not generator.rejection_evidence.is_empty())
	var legal := true
	for input in fallback_evidence.get("inputs", []): legal = Keyboard.legal(input) and legal
	check("最终源码回退证书键盘输入合法", legal and not fallback_evidence.is_empty())
	var failed := 0
	for entry in checks:
		if not entry.passed: failed += 1
	var file := FileAccess.open("res://tests/short-rope-t05-final-replay.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failed": failed, "checks": checks, "fallback_certificate": fallback_evidence, "rejections": generator.rejection_evidence}))
	file.close()
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
