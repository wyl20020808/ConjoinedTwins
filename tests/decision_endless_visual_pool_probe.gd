extends SceneTree
const Run = preload("res://scripts/road_run.gd")

func _initialize() -> void:
	call_deferred("probe")

func probe() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var r = game.run
	r.difficulty = "困难"
	r.seed_value = 42
	r.retry()
	var errors: Array = []
	for frame in range(7200):
		var first := Vector2(clampf((175 - r.a.position.x) / 10, -1, 1), clampf((r.distance + 35 - r.a.position.y) / 15, -1, 1))
		var second := Vector2(clampf((215 - r.b.position.x) / 10, -1, 1), clampf((r.distance - 35 - r.b.position.y) / 15, -1, 1))
		r.step(1.0 / 60.0, first, second)
		if frame % 60 != 0:
			continue
		game.sync_view()
		for index in range(r.kinds.size()):
			if r.kinds[index] == "cargo":
				continue
			var sample: Dictionary = r.hazard_sample(index, r.elapsed)
			var footprint: MeshInstance3D = game.hazard_views[index].get_node("WarningFootprint")
			var expected := Color("ffcb55") if sample.warning else (Color("e9553a") if sample.active else Color("51cdb6"))
			var actual: Color = footprint.material_override.albedo_color
			if not actual.is_equal_approx(expected):
				errors.append({"index": index, "kind": r.kinds[index], "stage": sample.stage, "material_id": footprint.material_override.get_instance_id(), "expected": expected.to_html(), "actual": actual.to_html()})
		if not errors.is_empty() or r.state != "running":
			break
	var result := {"passed": errors.is_empty() and r.state == "running", "distance": r.total_distance(), "rebases": r.rebases, "state": r.state, "errors": errors}
	var file := FileAccess.open("res://tests/decision-endless-visual-pool-probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print(JSON.stringify(result))
	game.queue_free()
	await process_frame
	quit(0 if result.passed else 1)
