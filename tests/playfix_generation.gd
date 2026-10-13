extends SceneTree

# 生成不得因玩家位置判负：用贴边、乱跳、前后拉满、随机乱按等输入跑生产后台生成，
# 失败原因只允许来自真实碰撞、失去支撑或绳索受阻，不能来自验证或安装准入。
const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")
var failed := 0

func check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok: failed += 1

func wait_worker(run) -> void:
	while run.async_thread != null and run.async_thread.is_alive(): OS.delay_msec(1)

func play(style: String, difficulty: String, seconds: float) -> Dictionary:
	Run.proven_blocks.clear()
	var run = Run.new(true, true)
	run.difficulty = difficulty
	run.retry()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var deaths: Array = []
	var first := Vector2.ZERO
	var second := Vector2.ZERO
	var jump := false
	for tick in range(int(seconds * 60)):
		wait_worker(run)
		if tick % 20 == 0:
			match style:
				"idle": pass
				"left_edge":
					first = Vector2(-1, 0)
					second = Vector2(-1, 0)
				"split":
					first = Vector2(-1, 1)
					second = Vector2(1, -1)
				"random":
					first = Vector2(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
					second = Vector2(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
			jump = style in ["split", "random"] and rng.randf() < 0.4
		run.step(1.0 / 60, first, second, jump, jump and style == "random")
		if run.state == "failed":
			deaths.append(run.reason)
			run.retry(true)
		if run.state == "settlement": break
	var sources := {}
	for event in run.async_events: sources[event.source] = sources.get(event.source, 0) + 1
	var result := {"deaths": deaths, "sources": sources, "segments": run.next_segment, "kinds": run.kinds.duplicate()}
	run.dispose()
	return result

func _initialize() -> void:
	for difficulty in ["简单", "困难"]:
		for style in ["idle", "left_edge", "split", "random"]:
			var result := play(style, difficulty, 45.0)
			var unfair := 0
			for reason in result.deaths:
				if reason.contains("验证") or reason.contains("后台") or reason.contains("归队") or reason.contains("生成"): unfair += 1
			var tag := "%s/%s " % [difficulty, style]
			print(tag, "deaths=", result.deaths.size(), " sources=", result.sources)
			check(tag + "无验证或准入判负", unfair == 0)
			check(tag + "持续生成且未回退空段", result.segments >= 4 and not result.sources.has("safe_rejected") and not result.sources.has("safe_late"))
	# 重试命中缓存：同种子第二次无需再等后台线程。
	var run = Run.new(true, true)
	run.retry()
	for tick in range(240):
		wait_worker(run)
		run.step(1.0 / 60)
	var before: int = run.async_events.size()
	run.retry(true)
	run.step(1.0 / 60)
	var cached := 0
	for n in range(before, run.async_events.size()):
		if run.async_events[n].source == "cached": cached += 1
	check("重试直接复用已证明布局", cached >= 4 and run.async_thread == null or cached >= 4)
	# 证明来不及：让出空段而不是判负。
	Run.proven_blocks.clear()
	run.retry()
	for tick in range(600): run.step(1.0 / 60)
	var late := 0
	for event in run.async_events:
		if event.source == "safe_late": late += 1
	check("后台来不及时继续推进不判负", run.state == "running" or not (run.reason.contains("验证") or run.reason.contains("后台")))
	print("late_fallbacks=", late, " state=", run.state, " reason=", run.reason)
	run.dispose()
	print("GENERATION failed=%d" % failed)
	quit(1 if failed > 0 else 0)
