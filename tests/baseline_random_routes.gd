extends SceneTree

const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")
const Keyboard = preload("res://tests/keyboard_route_assertions.gd")

func _initialize() -> void:
	var failures := 0
	for difficulty in Templates.DIFFICULTIES:
		for level in range(3):
			var run = Run.new(true, true)
			run.difficulty = difficulty
			run.level_index = level
			run.seed_value = 4242
			run.retry()
			var illegal := 0
			var geometry_errors := 0
			var ticks := 0
			var trace := HashingContext.new()
			trace.start(HashingContext.HASH_SHA256)
			for tick in range(120 * 160):
				while run.async_thread != null and run.async_thread.is_alive(): OS.delay_msec(1)
				var input: Array = Templates.existing_route_input(run)
				var axes := [input[0].x, input[0].y, input[1].x, input[1].y, input[2], input[3]]
				if not Keyboard.legal(axes): illegal += 1
				run.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
				if run.rope.length > Run.LINK_LIMIT + 0.01: geometry_errors += 1
				trace.update(var_to_bytes([axes, run.a.position, run.b.position, run.heights, run.rope.path]))
				ticks = tick + 1
				if run.state != "running": break
			var passed: bool = run.state == "settlement" and illegal == 0 and geometry_errors == 0 and run.coins > 0
			if not passed: failures += 1
			print("PASS " if passed else "FAIL ", difficulty, " level=", level + 1, " seed=4242 state=", run.state, " ticks=", ticks, " illegal=", illegal, " geometry_errors=", geometry_errors, " coins=", run.coins, " segments=", run.next_segment, " trace_sha256=", trace.finish().hex_encode(), " reason=", run.reason)
			run.dispose()
	print("BASELINE_RANDOM failures=", failures)
	quit(1 if failures else 0)
