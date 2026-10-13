extends SceneTree
const Run = preload("res://scripts/road_run.gd")

func _initialize() -> void:
	call_deferred("probe")

func probe() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var r = game.run
	var index: int = r.kinds.find("active_spikes")
	var spec: Dictionary = r.hazard_specs[index].duplicate(true)
	var top: float = r.obstacle_heights[index]
	# 明确夹具：生产尺寸、周期和高度，位置调整到可核对的跳跃接触时刻。
	r.obstacles.assign([Rect2(-55, 149.333333333333, 26, 8)])
	r.kinds.assign(["active_spikes"])
	r.obstacle_heights.assign([top])
	r.hazard_specs.assign([spec])
	r.retry()
	r.step(0.0)
	for frame in range(120):
		r.step(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO, frame >= 63, false)
		if r.state == "failed":
			break
	var physical_time: float = r.a.position.y / Run.FORWARD
	var sample: Dictionary = r.hazard_sample(0, physical_time)
	var result := {"state": r.state, "distance": r.distance, "physical_time": physical_time, "height": r.heights[0], "top_at_physical_time": sample.top, "clearance": r.heights[0] - sample.top, "reason": r.reason}
	var output := FileAccess.open("res://tests/decision-dynamic-hazard-probe.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	print(JSON.stringify(result))
	game.queue_free()
	await process_frame
	quit(0 if result.state == "running" else 1)
