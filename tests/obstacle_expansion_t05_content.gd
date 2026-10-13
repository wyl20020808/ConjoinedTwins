extends SceneTree
const Run = preload("res://scripts/road_run.gd")
class RejectedCandidate:
	extends "res://scripts/road_templates.gd"
	var injected_variant := true
	func candidate_block(_number: int, _level: int) -> Dictionary:
		var block := make_block("collapse", 1, 0)
		block.hazards.append({"kind": "press", "rect": Rect2(-80, 520, 160, 60)})
		block.injected = injected_variant
		return block
var checks: Array = []
func _initialize() -> void:
	call_deferred("verify")
func check(name: String, ok: bool) -> void:
	checks.append({"name": name, "passed": ok})
	print("PASS " if ok else "FAIL ", name)
func verify() -> void:
	var generator = Run.Templates.new()
	var has_combinations: bool = generator.has_method("combination_allowed")
	check("组合白名单有生产拒绝入口", has_combinations)
	if has_combinations:
		var forbidden: Dictionary = Run.Templates.make_block("gap_double", 1, 0)
		forbidden.hazards.append({"kind": "sweeper", "rect": Rect2(-26, 310, 52, 52)})
		check("缺口叠低扫杆禁区拒绝", not generator.combination_allowed(forbidden))
		forbidden = Run.Templates.make_block("collapse", 1, 0)
		forbidden.hazards.append({"kind": "press", "rect": Rect2(-80, 520, 160, 60)})
		check("塌陷板叠等待机关禁区拒绝", not generator.combination_allowed(forbidden))
		forbidden = Run.Templates.make_block("rocket", 1, 0)
		forbidden.hazards.append({"kind": "steam", "rect": Rect2(160, 560, 30, 40)})
		check("高速火箭叠新障碍首轮拒绝", not generator.combination_allowed(forbidden))
	var combos := {}
	var teaching_clean := true
	var baseline_count := 0
	var actual_count := 0
	for number in range(16):
		var block: Dictionary = generator.candidate_block(number, 0)
		actual_count += block.hazards.size()
		baseline_count += 2 if block.route == "steam" else 1
		if block.has("combination"): combos[block.combination] = true
		if number < 14: teaching_clean = teaching_clean and not block.has("combination")
	check("八类首轮独立教学不混入组合", teaching_clean)
	check("教学后实际增加压机高柱和蒸汽低空组合", combos.has("pillar_press") and combos.has("low_steam") and actual_count > baseline_count)
	var rejected := RejectedCandidate.new()
	var source = Run.new(false)
	source.retry()
	source.step(0)
	var fallback: Dictionary = rejected.generate_block(30, "普通", 0, source, 500)
	var denial: Dictionary = rejected.rejection_evidence.back()
	check("禁区通过生产验证拒绝且回退沿用同一入口", not fallback.is_empty() and denial.reason == "禁区组合" and denial.source_entry_hash == denial.fallback_source_entry_hash)
	rejected.injected_variant = false
	check("首轮教学拒绝停止而不吞教学", rejected.generate_block(0, "普通", 0, source, 500).is_empty() and rejected.rejection_evidence.back().fallback == "teaching_rejected_generation_stopped")
	rejected.injected_variant = true
	source.state = "failed"
	check("同入口安全回退失败停止并保留支撑接触", rejected.generate_block(30, "普通", 0, source, 500).is_empty() and rejected.rejection_evidence.back().fallback == "failed_generation_stopped" and rejected.rejection_evidence.back().fallback_exit.has("support"))
	FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t05/negative-generation.json", FileAccess.WRITE).store_string(JSON.stringify(rejected.rejection_evidence, "\t"))
	source.dispose()
	var run = Run.new()
	run.step(0)
	var chains := true
	for segment in run.route_segments:
		var count := 0
		for reward in segment.block.rewards:
			if reward.kind == "coin": count += 1
		chains = chains and count >= 6
	check("真实生产安装连续引导金币链", chains and not run.route_segments.is_empty())
	check("奖励池有足够空间且实际受限", Run.Levels.MAX_REWARDS >= 48 and run.rewards.size() <= Run.Levels.MAX_REWARDS)
	run.dispose()
	var failed: int = checks.filter(func(c): return not c.passed).size()
	FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t05/content-result.json", FileAccess.WRITE).store_string(JSON.stringify({"passed": failed == 0, "checks": checks}, "\t"))
	quit(1 if failed else 0)
