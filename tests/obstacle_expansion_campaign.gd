extends SceneTree
const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
var records: Array = []
func _initialize() -> void:
	call_deferred("verify")
func check(name: String, ok: bool) -> void:
	checks.append({"name": name, "passed": ok})
	print("PASS " if ok else "FAIL ", name)
func drive(r) -> Array:
	for segment in r.route_segments:
		if r.total_distance() >= segment.base and r.total_distance() < segment.base + Run.Templates.SEGMENT:
			return Run.Templates.route_input(r, segment.block, segment.base - r.world_origin)
	return Run.Templates.route_input(r, Run.Templates.make_block("safe", 0, r.level_index), r.distance)
func verify() -> void:
	for difficulty in Run.Templates.DIFFICULTIES:
		var r = Run.new(false)
		r.generation_enabled = true
		r.difficulty = difficulty
		r.seed_value = 20261013
		r.new_campaign()
		r.step(0)
		for level in range(3):
			var valid := true
			var kinds := {}
			var peak_hazards := 0
			var peak_rewards := 0
			var warnings := {}
			var boundaries: Array = []
			var previous_segment := -1
			for tick in range(15000):
				var input := drive(r)
				valid = valid and Run.Templates.keyboard_legal(input[0]) and Run.Templates.keyboard_legal(input[1])
				r.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
				valid = valid and r.rope.required <= Run.LINK_LIMIT + 0.01 and r.shield_uses == 0 and absf(r.a.position.y - r.distance) <= Run.RELATIVE_RANGE + 0.01 and absf(r.b.position.y - r.distance) <= Run.RELATIVE_RANGE + 0.01
				for kind in r.kinds: kinds[kind] = true
				for i in range(r.hazard_specs.size()):
					var spec: Dictionary = r.hazard_specs[i]
					if spec.get("locked", false): warnings[str(r.obstacle_ids[i])] = spec.warning_evidence.duplicate(true)
				peak_hazards = maxi(peak_hazards, r.kinds.size())
				peak_rewards = maxi(peak_rewards, r.rewards.size())
				var segment := int((r.total_distance() - 600) / Run.Templates.SEGMENT)
				if segment != previous_segment:
					boundaries.append(Run.Templates.snapshot(r, tick))
					previous_segment = segment
				if r.state != "running": break
			var name := "%s/%d" % [difficulty, level + 1]
			check(name + "生产固定步共同通关", valid and r.state == "settlement" and r.elapsed >= 90 and r.elapsed <= 120)
			check(name + "实际安装提速滚球与火箭", kinds.has("stone_ball") and (level == 0 or kinds.has("iron_ball") and kinds.has("rocket")))
			var warning_ok := not warnings.is_empty()
			for warning in warnings.values(): warning_ok = warning_ok and warning.ttc >= warning.joint_change_time + 0.35 - 0.025
			check(name + "共同换边预警余量", warning_ok)
			check(name + "奖励与回收上限", r.coins >= 20 and r.prizes >= 3 and peak_rewards <= Run.Levels.MAX_REWARDS and peak_hazards <= Run.Templates.MAX_HAZARDS)
			records.append({"difficulty": difficulty, "level": level + 1, "state": r.state, "reason": r.reason, "seconds": r.elapsed, "speed": r.speed() / 20, "finish": r.finish_distance() / 20, "kinds": kinds.keys(), "warnings": warnings, "boundaries": boundaries, "peak_rewards": peak_rewards, "peak_hazards": peak_hazards, "rebases": r.rebases, "recycled": r.recycled, "rejections": r.generator.rejection_evidence})
			if r.state != "settlement": break
			r.step(Run.FIXED_STEP)
			r.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, true, true)
			r.step(0)
		check(difficulty + "三关共同确认完成", r.state == "complete" and r.results.size() == 3)
		r.dispose()
	var failed := checks.filter(func(c): return not c.passed).size()
	FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t01/campaign-result.json", FileAccess.WRITE).store_string(JSON.stringify({"passed": failed == 0, "checks": checks, "records": records}, "\t"))
	quit(1 if failed else 0)
