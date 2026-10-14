extends SceneTree

const Run = preload("res://scripts/road_run.gd")

func _initialize() -> void:
	var landed := 0
	var hooked := 0
	var geometry_errors := 0
	for timing in [226, 230, 234, 238, 242, 246]:
		var run = Run.new(false)
		run.streaming = false
		run.obstacles.assign([Rect2(-12, 288, 24, 24)])
		run.kinds.assign(["pillar"])
		run.obstacle_heights.assign([40.0])
		run.hazard_specs.assign([{}])
		run.retry()
		var touched := false
		var above := false
		for tick in range(1, 620):
			# 当前手动速度下七步分离仍有余量；旧夹具十四步已拉满。
			var airborne: bool = run.heights[0] > 0 or run.heights[1] > 0
			run.step(1.0 / 120.0, Vector2.LEFT if tick < 8 else Vector2.ZERO, Vector2.RIGHT if tick < 8 else Vector2.ZERO, tick == timing, tick == timing)
			if run.rope.length > 146.61: geometry_errors += 1
			if 28.0 + minf(run.heights[0], run.heights[1]) < 40.0:
				var path: PackedVector2Array = run.rope.path
				for n in range(1, path.size()):
					if Geometry2D.get_closest_point_to_segment(Vector2(0, 300), path[n - 1], path[n]).distance_to(Vector2(0, 300)) < 11.99: geometry_errors += 1
			if run.rope.touching() > 0:
				var nearest := Geometry2D.get_closest_point_to_segment(Vector2(0, 300), run.a.position, run.b.position)
				if not touched and airborne and nearest.distance_to(Vector2(0, 300)) < 11.0: above = true
				touched = true
			if run.state != "running": break
		if above: landed += 1
		if touched: hooked += 1
		print("LANDING timing=", timing, " landed=", above, " hooked=", touched)
		run.dispose()
	var passed := landed >= 3 and hooked >= landed and geometry_errors == 0
	print("BASELINE_LANDING landed=", landed, " hooked=", hooked, " geometry_errors=", geometry_errors, " passed=", passed)
	quit(0 if passed else 1)
