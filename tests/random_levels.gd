extends SceneTree

# 随机关卡检查：
# 1. 每种难度、每关抽大量随机候选（随机种类顺序、左右、相位、奖励、散布陷阱），后台证明入口 prove 的通过率与耗时；
# 2. 用生产 road_run（后台生成、随机种子）按已证明路线跑完整关，必须到达结算，失败只能来自真实危险；
# 3. 不同种子的段落顺序与陷阱布局不同。
# 用法：Godot --headless --path . -s res://tests/random_levels.gd [-- 难度名]
const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")
var failed := 0

func check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok: failed += 1

func wait_worker(run) -> void:
	while run.async_thread != null and run.async_thread.is_alive(): OS.delay_msec(1)

func proof_rate(difficulty: String, level: int, count: int) -> void:
	var generator = Templates.new()
	generator.source_override = "runtime"
	generator.reset(1000 + level)
	var accepted := 0
	var dressed := 0
	var extras := 0
	var slowest := 0
	var rejected: Array = []
	for n in range(count):
		var candidate: Dictionary = generator.candidate_block(n, level)
		var started := Time.get_ticks_usec()
		var block: Dictionary = generator.prove(candidate, difficulty, level)
		slowest = maxi(slowest, Time.get_ticks_usec() - started)
		if block.is_empty():
			rejected.append(candidate.route)
			continue
		accepted += 1
		var added := 0
		for hazard in block.hazards: if hazard.get("extra", false): added += 1
		extras += added
		if added > 0: dressed += 1
	var tag := "%s 第%d关 " % [difficulty, level + 1]
	print(tag, "候选 %d 通过 %d 带陷阱 %d 平均陷阱 %.1f 最慢 %d ms 未通过 %s" % [count, accepted, dressed, float(extras) / maxi(1, accepted), slowest / 1000, rejected])
	# 未通过的候选在生产中还有两个同种变体可换，这里只要求绝大多数直接通过。
	check(tag + "随机候选通过率不低于 85%", accepted >= count * 0.85)
	check(tag + "多数段落带有散布陷阱", dressed >= accepted * 0.8)
	check(tag + "单段证明耗时低于 1.5 秒", slowest < 1500000)

func play_level(difficulty: String, level: int, seed_value: int) -> Dictionary:
	var run = Run.new(true, true)
	run.difficulty = difficulty
	run.level_index = level
	run.seed_value = seed_value
	run.retry()
	var routes: Array = []
	var extras := 0
	var seen := {}
	for tick in range(120 * 160):
		wait_worker(run)
		var input: Array = Templates.existing_route_input(run)
		run.step(1.0 / 120, input[0], input[1], input[2], input[3])
		for segment in run.route_segments:
			if seen.has(segment.number): continue
			seen[segment.number] = true
			routes.append(segment.block.route)
			for hazard in segment.block.hazards: if hazard.get("extra", false): extras += 1
		if run.state != "running": break
	var sources := {}
	for event in run.async_events: sources[event.source] = sources.get(event.source, 0) + 1
	var result := {"state": run.state, "reason": run.reason, "routes": routes, "extras": extras, "sources": sources, "coins": run.coins, "progress": run.progress() / 20.0}
	run.dispose()
	return result

func _initialize() -> void:
	var only: Array = OS.get_cmdline_user_args()
	for difficulty in Templates.DIFFICULTIES:
		if not only.is_empty() and difficulty not in only: continue
		for level in range(3): proof_rate(difficulty, level, 40)
	var orders := {}
	for difficulty in Templates.DIFFICULTIES:
		if not only.is_empty() and difficulty not in only: continue
		for level in range(3):
			for seed_value in [11, 4242]:
				Run.proven_blocks.clear()
				var result := play_level(difficulty, level, seed_value)
				var tag := "%s 第%d关 种子%d " % [difficulty, level + 1, seed_value]
				print(tag, result.state, " ", result.reason, " 前进 %.0f 米 段落 %d 陷阱 %d 金币 %d 来源 %s" % [result.progress, result.routes.size(), result.extras, result.coins, result.sources])
				check(tag + "按已证明路线到达结算", result.state == "settlement")
				check(tag + "没有让出空段", not result.sources.has("safe_rejected") and not result.sources.has("safe_late"))
				orders["%s:%d:%d" % [difficulty, level, seed_value]] = result.routes
			check("%s 第%d关 两个种子段落顺序不同" % [difficulty, level + 1], orders["%s:%d:11" % [difficulty, level]] != orders["%s:%d:4242" % [difficulty, level]])
	print("RANDOM failed=%d" % failed)
	quit(1 if failed > 0 else 0)
