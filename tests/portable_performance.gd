extends SceneTree

const Journey = preload("res://scripts/journey_run.gd")

class MeasuredRun extends Journey:
	var hit_calls := 0
	var industrial_calls := 0
	func timed_hazard_hits(index: int, start: float, end: float, from: Vector2, to: Vector2, h0: float, h1: float) -> bool:
		hit_calls += 1
		return super(index, start, end, from, to, h0, h1)
	func industrial_hits(index: int, start: float, end: float, pa: Vector2, ca: Vector2, pb: Vector2, cb: Vector2, old_heights: Array, old_path: PackedVector2Array, old_z: PackedFloat32Array) -> Dictionary:
		industrial_calls += 1
		return super(index, start, end, pa, ca, pb, cb, old_heights, old_path, old_z)

func _initialize() -> void:
	var rows: Array = []
	for chapter in range(3):
		var run = MeasuredRun.new()
		run.random_seed = false; run.seed_value = 8123; run.level_index = chapter; run.retry()
		run.state = "running"; run.clear_input = false; run.elapsed = 10.0
		var found := false
		for offset in [0, 100, -100, 200, -200]:
			for x in [80, -42, -120, -200, 180]:
				var point := Vector2(x, 9600 + offset)
				if run.Monsters.safe_spawn(run, point) and run.Monsters.safe_spawn(run, point + Vector2(56, 0)):
					run.a.position = point; run.b.position = point + Vector2(56, 0); found = true; break
			if found: break
		assert(found)
		run.distance = run.a.position.y
		for gate in run.charge_gates:
			gate.open = gate.receiver.y < run.distance - 180
			gate.opened_at = 0 if gate.open else -1
		run.select_charge_gate(); run.rope.reset(run.a.position, run.b.position)
		for frame in range(24): run.step(run.FIXED_STEP)
		assert(run.state == "running")
		run.hit_calls = 0; run.industrial_calls = 0
		var samples: Array[int] = []
		var before: float = run.elapsed
		for frame in range(360):
			var start := Time.get_ticks_usec()
			run.step(run.FIXED_STEP)
			samples.append(Time.get_ticks_usec() - start)
		assert(run.state == "running" and absf(run.elapsed - before - 3.0) < 0.000001)
		samples.sort()
		rows.append({"chapter": chapter, "median_usec": samples[180], "p95_usec": samples[341], "total_usec": samples.reduce(func(a, b): return a+b, 0), "timed_calls": run.hit_calls, "industrial_calls": run.industrial_calls, "state": run.state, "hash": run.sync_hash(), "hazards": run.kinds.size(), "events": run.journey_events.size()})
		run.dispose()
	var output := OS.get_environment("PORTABLE_PERFORMANCE_REPORT")
	assert(not output.is_empty())
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(rows, "\t"))
	print("PORTABLE PERFORMANCE ", JSON.stringify(rows))
	quit()
