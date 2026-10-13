extends SceneTree

const Run = preload("res://scripts/road_run.gd")
const Keyboard = preload("res://tests/keyboard_route_assertions.gd")
const OUTPUT := "res://build-tools/obstacle-expansion-6377e8b8/t05/campaign/final"
const TEACHING := ["drone", "forklift", "press", "sweeper", "road_gap", "hammer", "collapse", "steam"]
const BASELINE := "res://build-tools/obstacle-expansion-6377e8b8/t05/baseline-density.json"
const COIN_GAP_LIMIT := 240.0 # 12 米；正式验证前固定，包含跨段归队区。
var checks: Array = []
var summaries: Array = []
var run_properties: Array = []
var rope_properties: Array = []

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, ok: bool) -> void:
	checks.append({"name": name, "passed": ok})
	print("PASS " if ok else "FAIL ", name)

func save(name: String, value: Dictionary) -> void:
	FileAccess.open(OUTPUT + "/" + name + ".json", FileAccess.WRITE).store_string(JSON.stringify(value))

func signature(run) -> String:
	# 真实运行状态含输入边沿、缓冲、支撑、危险相位及绳段高度；随机状态另外绑定。
	# 哈希立即计算，无需为每步深拷贝整个已加载布局。仍包含所有运行和绳求解变量。
	if run_properties.is_empty():
		for property in run.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name not in ["a", "b", "rope", "generator"] and not property.name.begins_with("async"): run_properties.append(property.name)
		for property in run.rope.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: rope_properties.append(property.name)
	var values: Array = [run.a.position, run.b.position, run.generator.rng.state, run.generator.rejected, run.generator.fallbacks]
	for name in run_properties: values.append(run.get(name))
	for name in rope_properties: values.append(run.rope.get(name))
	return str(hash(values))

func drive(run) -> Array:
	for segment in run.route_segments:
		if run.total_distance() >= segment.base and run.total_distance() < segment.base + Run.Templates.SEGMENT:
			return Run.Templates.route_input(run, segment.block, segment.base - run.world_origin)
	return Run.Templates.route_input(run, Run.Templates.make_block("safe", 0, run.level_index), run.distance)

func encode(input: Array) -> Array:
	return [input[0].x, input[0].y, input[1].x, input[1].y, input[2], input[3]]

func decode(input: Array) -> Array:
	return [Vector2(input[0], input[1]), Vector2(input[2], input[3]), input[4], input[5]]

func geometry(run) -> bool:
	return run.rope.required <= Run.LINK_LIMIT + 0.01 and run.shield_uses == 0 and absf(run.a.position.x) <= Run.EDGE and absf(run.b.position.x) <= Run.EDGE and absf(run.a.position.y - run.distance) <= Run.RELATIVE_RANGE + 0.01 and absf(run.b.position.y - run.distance) <= Run.RELATIVE_RANGE + 0.01

func baseline_density(difficulty: String, level: int, finish: float) -> Dictionary:
	if not FileAccess.file_exists(BASELINE): return {}
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	for record in saved.get("records", []):
		if record.difficulty != difficulty or int(record.level) != level + 1: continue
		return {"source": BASELINE, "sha256": FileAccess.get_sha256(BASELINE), "seed": 20261013, "observed_ids": record.observed_ids, "observed_count": record.observed_count, "finish_units": record.finish_units, "state": record.state, "per_1000_units": record.observed_count * 1000.0 / record.finish_units, "finish_matches": absf(record.finish_units - finish) < 0.01}
	return {}

func collect_certificates(run, captured: Dictionary) -> void:
	for key in run.generator.verified:
		if captured.has(key): continue
		var evidence: Dictionary = run.generator.verified[key]
		var name := "certificate-" + str(key).sha256_text()
		captured[key] = {"certificate_key": key, "path": OUTPUT + "/" + name + ".json", "layout_hash": evidence.get("layout_hash", ""), "base": evidence.get("base", -1), "source_binding": evidence.get("source_binding", ""), "source_entry_hash": evidence.get("source_entry_hash", ""), "accepted": evidence.get("accepted", false)}
		var certificate := evidence.duplicate(true)
		certificate.certificate_key = key
		certificate.source_entry_serialized = var_to_str(evidence.get("source_entry", {}))
		save(name, certificate)

func coin_spacing(positions: Dictionary) -> Dictionary:
	var chain: Array = positions.values()
	chain.sort_custom(func(first, second): return first.y < second.y)
	var maximum := 0.0
	var crossing := 0.0
	var pair: Array = []
	for index in range(1, chain.size()):
		var gap: float = chain[index].y - chain[index - 1].y
		if gap > maximum:
			maximum = gap
			pair = [chain[index - 1], chain[index]]
		if chain[index].segment != chain[index - 1].segment: crossing = maxf(crossing, gap)
	return {"max_gap_units": maximum, "max_cross_segment_gap_units": crossing, "max_gap_pair": pair, "chain": chain, "warmup_and_finish_zones_excluded": true}

func campaign(difficulty: String, seed_value: int, playback: Dictionary = {}) -> Dictionary:
	var run = Run.new(false)
	run.generation_enabled = true
	run.difficulty = difficulty
	run.seed_value = seed_value
	var beginning := Time.get_ticks_usec()
	run.new_campaign()
	run.step(0)
	var level_start_generation_us := Time.get_ticks_usec() - beginning
	var levels: Array = []
	var valid := true
	for level in range(3):
		var old: Dictionary = playback.levels[level] if not playback.is_empty() else {}
		var inputs: Array = []
		var hashes: Array = []
		var samples: Array = []
		var warnings := {}
		var boundaries: Array = []
		var crossed := {}
		var installed_coins := {}
		var coin_positions := {}
		var hazard_ids := {}
		var crossed_hazard_ids := {}
		var crossed_routes := {}
		var certificates := {}
		var claimed := {}
		var teaching := {}
		var installed_kinds := {}
		var combinations := {}
		var peak_rewards := 0
		var peak_hazards := 0
		var illegal := 0
		var step_valid := true
		var mismatch := -1
		var generation_steps: Array = []
		var max_generation_step_us := 0
		var entry: Dictionary = Run.Templates.snapshot(run, 0)
		collect_certificates(run, certificates)
		for tick in range(16000):
			if not old.is_empty() and tick >= old.inputs.size():
				step_valid = false
				break
			var input: Array = decode(old.inputs[tick]) if not old.is_empty() else drive(run)
			inputs.append(encode(input))
			if not Keyboard.legal(inputs[-1]): illegal += 1
			for reward in run.rewards:
				if reward.kind == "coin":
					installed_coins[reward.id] = true
					coin_positions[reward.id] = {"id": reward.id, "x": reward.position.x, "y": reward.position.y + run.world_origin, "segment": str(reward.id).rsplit(":", true, 1)[0]}
			for kind in run.kinds: installed_kinds[kind] = true
			for id in run.obstacle_ids: hazard_ids[str(id)] = true
			for segment in run.route_segments:
				if run.progress() < segment.base + Run.Templates.SEGMENT or crossed.has(segment.number): continue
				crossed[segment.number] = true
				crossed_routes[segment.block.route] = true
				for index in range(segment.block.hazards.size()):
					teaching[segment.block.hazards[index].kind] = true
					crossed_hazard_ids["%s:%d" % [str(segment.number), index]] = true
				if segment.block.get("combination", "") in ["pillar_press", "low_steam"]: combinations[segment.block.combination] = true
				var layout_hash := var_to_str(segment.block).sha256_text()
				var certificate_refs: Array = []
				for certificate in certificates.values():
					if certificate.layout_hash == layout_hash and absf(certificate.base - segment.base) < 0.01: certificate_refs.append(certificate)
				boundaries.append({"number": segment.number, "route": segment.block.route, "layout_hash": layout_hash, "certificates": certificate_refs, "state": Run.Templates.snapshot(run, tick)})
			var before_segment: int = run.next_segment
			var started := Time.get_ticks_usec()
			run.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
			var step_us := Time.get_ticks_usec() - started
			collect_certificates(run, certificates)
			if run.next_segment != before_segment:
				generation_steps.append({"tick": tick, "microseconds": step_us, "segments": run.next_segment - before_segment})
				max_generation_step_us = maxi(max_generation_step_us, step_us)
			for id in run.claimed_rewards: claimed[id] = true
			var digest := signature(run)
			hashes.append(digest)
			if not old.is_empty() and digest != old.hashes[tick]:
				step_valid = false
				if mismatch < 0: mismatch = tick
			step_valid = step_valid and geometry(run)
			peak_rewards = maxi(peak_rewards, run.rewards.size())
			peak_hazards = maxi(peak_hazards, run.kinds.size())
			for index in range(run.hazard_specs.size()):
				var spec: Dictionary = run.hazard_specs[index]
				if not spec.get("warning_evidence", {}).is_empty(): warnings[str(run.obstacle_ids[index])] = {"kind": run.kinds[index], "evidence": spec.warning_evidence.duplicate(true)}
			if tick % 120 == 0 or run.state != "running": samples.append(Run.Templates.snapshot(run, tick))
			if tick % 2000 == 0: print("PROGRESS ", difficulty, "/", seed_value, "/", level + 1, " tick=", tick, " distance=", run.total_distance())
			if run.state != "running": break
		var tag := "%s/%d/%d%s" % [difficulty, seed_value, level + 1, "/复放" if not playback.is_empty() else ""]
		check(tag + "合法输入及逐步物理通关", step_valid and illegal == 0 and run.state == "settlement")
		var taught := true
		for kind in TEACHING: taught = taught and teaching.has(kind) and installed_kinds.has(kind)
		check(tag + "八类教学实际经过", taught)
		check(tag + "白名单组合实际经过", combinations.has("pillar_press") and combinations.has("low_steam"))
		var all_coins := not installed_coins.is_empty()
		for id in installed_coins: all_coins = all_coins and claimed.has(id)
		check(tag + "连续金币实际全部领取且编号不重领", all_coins and run.coins == installed_coins.size() and run.prizes >= 3)
		check(tag + "共同终点时长与池上限", run.progress() >= run.finish_distance() and run.elapsed >= 90 and run.elapsed <= 120 and peak_rewards <= Run.Levels.MAX_REWARDS and peak_hazards <= Run.Templates.MAX_HAZARDS)
		var warning_ok := not warnings.is_empty()
		for warning in warnings.values():
			var evidence: Dictionary = warning.evidence
			if evidence.has("reaction_margin"): warning_ok = warning_ok and evidence.reaction_margin >= 0.325
			elif evidence.has("ttc"): warning_ok = warning_ok and evidence.ttc >= evidence.joint_change_time + 0.325
		check(tag + "共同实际预警余量", warning_ok)
		var baseline := baseline_density(difficulty, level, run.finish_distance())
		check(tag + "实际危险密度高于改前全固定步基线", not baseline.is_empty() and baseline.state == "settlement" and baseline.finish_matches and hazard_ids.size() > baseline.observed_count)
		var old_routes: Array = ["body", "ball", "rocket", "stagger", "double"] if level == 2 else (["body", "ball", "rocket"] if level == 1 else [])
		var old_play_ok := true
		for route in old_routes: old_play_ok = old_play_ok and crossed_routes.has(route)
		if level > 0:
			for kind in ["fly_body", "iron_ball", "rocket"]: old_play_ok = old_play_ok and installed_kinds.has(kind)
		if level == 2: old_play_ok = old_play_ok and installed_kinds.has("cargo")
		check(tag + "旧玩法实际跨段保留", old_play_ok)
		var spacing := coin_spacing(coin_positions)
		spacing.limit_units = COIN_GAP_LIMIT
		check(tag + "金币连续引导含跨段间距不超过12米", spacing.max_gap_units <= COIN_GAP_LIMIT and spacing.max_cross_segment_gap_units <= COIN_GAP_LIMIT)
		var certificate_ok := not boundaries.is_empty()
		for boundary in boundaries: certificate_ok = certificate_ok and not boundary.certificates.is_empty()
		check(tag + "每个实际跨段布局有真实入口证书", certificate_ok)
		print("GENERATION_TIME ", tag, " max_step_us=", max_generation_step_us, " level_start_us=", level_start_generation_us, " generating_steps=", generation_steps.size())
		levels.append({"entry": entry, "inputs": inputs, "hashes": hashes, "samples": samples, "boundaries": boundaries, "warnings": warnings, "first_mismatch": mismatch, "state": run.state, "reason": run.reason, "seconds": run.elapsed, "coins": run.coins, "prizes": run.prizes, "installed_coin_ids": installed_coins.keys(), "claimed_ids": claimed.keys(), "teaching": teaching.keys(), "combinations": combinations.keys(), "peak_rewards": peak_rewards, "peak_hazards": peak_hazards, "rejections": run.generator.rejection_evidence.duplicate(true), "generation_steps": generation_steps, "max_generation_step_us": max_generation_step_us})
		levels[-1].level_start_generation_us = level_start_generation_us
		levels[-1].danger_density = {"baseline": baseline, "observed_ids": hazard_ids.keys(), "observed_count": hazard_ids.size(), "per_1000_units": hazard_ids.size() * 1000.0 / run.finish_distance()}
		levels[-1].crossed_hazard_count = crossed_hazard_ids.size()
		levels[-1].crossed_hazard_ids = crossed_hazard_ids.keys()
		levels[-1].crossed_routes = crossed_routes.keys()
		levels[-1].certificates = certificates.values()
		levels[-1].coin_spacing = spacing
		save("%s-%d-%s-checkpoint" % [difficulty, seed_value, "replay" if not playback.is_empty() else "record"], {"levels": levels, "completed_levels": levels.size()})
		valid = valid and step_valid and illegal == 0 and run.state == "settlement" and taught and all_coins
		if run.state != "settlement": break
		# 只通过生产共同确认换关；关内没有任何重置或位置修正。
		run.step(Run.FIXED_STEP)
		beginning = Time.get_ticks_usec()
		run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, true, true)
		run.step(0)
		level_start_generation_us = Time.get_ticks_usec() - beginning
	check("%s/%d三关生产共同确认%s" % [difficulty, seed_value, "/复放" if not playback.is_empty() else ""], run.state == "complete" and run.results.size() == 3)
	var result := {"difficulty": difficulty, "seed": seed_value, "valid": valid and run.state == "complete", "levels": levels, "score": run.total_score(), "results": run.results.duplicate(true)}
	run.dispose()
	return result

func tight_sequence(difficulty: String, side: int, swapped: bool, playback: Dictionary = {}) -> Dictionary:
	var run = Run.new(false)
	run.generation_enabled = false
	run.difficulty = difficulty
	run.level_index = 2
	run.retry()
	var blocks: Array = []
	run.a.position = Vector2(-5, -73 if swapped else 73)
	run.b.position = Vector2(5, 73 if swapped else -73)
	run.rope.reset(run.a.position, run.b.position)
	run.step(0)
	var initial: Dictionary = Run.Templates.snapshot(run, 0)
	var inputs: Array = []
	var hashes: Array = []
	var samples: Array = []
	var peak: float = run.rope.required
	var valid := true
	var mismatch := -1
	var generated_entries: Array = []
	var certificates := {}
	for tick in range(4000):
		var number := mini(2, int(run.distance / Run.Templates.SEGMENT))
		if blocks.size() <= number:
			# 为镜像固定候选随机侧；只配置 RNG，不改变实际入口或运动状态。
			var candidate_number: int = Run.Templates.LEVEL_ROUTES[2].find(["drone", "forklift", "press"][number])
			for attempt in range(64):
				var rng_state: int = run.generator.rng.state
				var candidate: Dictionary = run.generator.candidate_block(candidate_number, 2)
				if candidate.hazards[0].get("side", 0) == side:
					run.generator.rng.state = rng_state
					break
			var entrance: Dictionary = Run.Templates.capture_state(run)
			var base: float = number * Run.Templates.SEGMENT - run.world_origin
			var block: Dictionary = run.generator.generate_block(candidate_number, difficulty, 2, run, base)
			var entry_hash := var_to_str(entrance).sha256_text()
			var evidence: Dictionary = run.generator.last_evidence
			valid = valid and not block.is_empty() and evidence.get("accepted", false) and evidence.get("source_entry_hash", "") == entry_hash
			generated_entries.append({"number": number, "source_entry_hash": entry_hash, "source_entry": entrance, "evidence_entry_hash": evidence.get("source_entry_hash", ""), "accepted": evidence.get("accepted", false), "layout_hash": evidence.get("layout_hash", ""), "reason": evidence.get("reason", "")})
			collect_certificates(run, certificates)
			if block.is_empty(): break
			run.install_block(block, base, "tight-%d" % number)
			blocks.append(block)
		var input: Array = decode(playback.inputs[tick]) if not playback.is_empty() and tick < playback.inputs.size() else Run.Templates.route_input(run, blocks[number], number * Run.Templates.SEGMENT - run.world_origin)
		inputs.append(encode(input))
		run.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
		hashes.append(signature(run))
		valid = valid and Keyboard.legal(inputs[-1]) and geometry(run)
		if not playback.is_empty() and (tick >= playback.hashes.size() or hashes[-1] != playback.hashes[tick]):
			valid = false
			if mismatch < 0: mismatch = tick
		peak = maxf(peak, run.rope.required)
		if tick % 30 == 0 or run.state != "running": samples.append(Run.Templates.snapshot(run, tick))
		if run.state != "running" or run.progress() >= 3 * Run.Templates.SEGMENT: break
	valid = valid and generated_entries.size() == 3 and run.state == "running" and run.progress() >= 3 * Run.Templates.SEGMENT and peak >= Run.LINK_LIMIT - 0.5
	check("近绳限连续三段/%s/镜像%d/交换%s%s" % [difficulty, side, str(swapped), "/复放" if not playback.is_empty() else ""], valid)
	var result := {"initial": initial, "valid": valid, "inputs": inputs, "hashes": hashes, "samples": samples, "generated_entries": generated_entries, "certificates": certificates.values(), "peak_rope": peak, "first_mismatch": mismatch, "exit": Run.Templates.snapshot(run, inputs.size()), "reason": run.reason}
	run.dispose()
	return result

func verify() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var source_hashes := {}
	for name in DirAccess.open("res://scripts").get_files():
		if name.ends_with(".gd"): source_hashes["res://scripts/" + name] = FileAccess.get_sha256("res://scripts/" + name)
	for path in ["res://scenes/road_demo.tscn", "res://project.godot", "res://assets/mechs/George.gltf", "res://assets/mechs/Leela.gltf", BASELINE, "res://tests/obstacle_expansion_t05_campaign.gd"]: source_hashes[path] = FileAccess.get_sha256(path)
	save("source-hashes", {"source_binding": Run.Templates.source_binding(), "files": source_hashes})
	var difficulties: Array = Run.Templates.DIFFICULTIES.keys()
	var seeds: Array = [20261013, 7, 42]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--difficulty="): difficulties = [argument.trim_prefix("--difficulty=")]
		if argument.begins_with("--seed="): seeds = [int(argument.trim_prefix("--seed="))]
	for difficulty in difficulties:
		for seed_value in seeds:
			var name := "%s-%d" % [difficulty, seed_value]
			var recorded := campaign(difficulty, seed_value)
			save(name + "-record", recorded)
			var replayed := campaign(difficulty, seed_value, recorded) if recorded.levels.size() == 3 and recorded.valid else {}
			check(name + "三关逐固定步复放总分一致", not replayed.is_empty() and replayed.valid and replayed.score == recorded.score)
			if not replayed.is_empty(): save(name + "-replay", replayed)
			summaries.append({"name": name, "record_valid": recorded.valid, "replay_valid": replayed.get("valid", false)})
		for side in [-1, 1]:
			for swapped in [false, true]:
				var name := "tight-%s-%d-%s" % [difficulty, side, str(swapped)]
				var recorded := tight_sequence(difficulty, side, swapped)
				save(name + "-record", recorded)
				if recorded.valid: save(name + "-replay", tight_sequence(difficulty, side, swapped, recorded))
	var failed: int = checks.filter(func(entry): return not entry.passed).size()
	save("result", {"passed": failed == 0, "failed": failed, "checks": checks, "summaries": summaries, "source_binding": Run.Templates.source_binding(), "executor_self_test": true, "decision_review": "pending", "controller_tests": [], "gui": "not_run", "real_keyboard": "not_run", "user_playtest": "pending"})
	quit(1 if failed else 0)
