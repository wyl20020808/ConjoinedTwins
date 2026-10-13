extends SceneTree
const Run = preload("res://scripts/road_run.gd")
func _initialize() -> void:
	var run = Run.new(false)
	run.install_block(Run.Templates.make_block("hammer", 1, 0), 0, "bounds")
	var supported := run.has_method("industrial_sweep_bounds")
	print("PASS " if supported else "FAIL ", "生产分部连续粗检入口")
	var valid := supported
	if supported:
		run.hazard_specs[0].trigger = 0.0
		var bounds: Rect2 = run.industrial_sweep_bounds(0, 3.0, 3.01)
		for tick in range(101):
			var sample: Dictionary = run.hazard_sample(0, 3.0 + tick * 0.0001)
			for part in sample.parts:
				valid = valid and bounds.encloses(part.rect)
		print("PASS " if valid else "FAIL ", "包络覆盖全部柄锤支架和期间姿态")
	run.dispose()
	var ball = Run.new(false)
	ball.retry()
	ball.install_block(Run.Templates.make_block("stone_ball", 1, 0), 500, "far")
	ball.distance = 500
	ball.rope.required = 123.0
	ball.advance_threats(Run.FIXED_STEP)
	var far_unchanged: bool = ball.rope.required == 123.0 and ball.hazard_specs[0].travel > 0
	print("PASS " if far_unchanged else "FAIL ", "远离任何合法绳路的球仅推进自身不反复求解绳索")
	valid = valid and far_unchanged
	ball.dispose()
	quit(0 if valid else 1)
