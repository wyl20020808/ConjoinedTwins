extends SceneTree

# 每条生产段落从中央入口独立验证：与玩家实时位置无关，运行时后台证明使用同一入口。
# 用法：Godot --headless --path . -s res://tests/playfix_routes.gd [-- 难度名]
const Templates = preload("res://scripts/road_templates.gd")

func _initialize() -> void:
	var only: Array = OS.get_cmdline_user_args()
	var failed := 0
	var total := 0
	var slowest := 0
	for difficulty in Templates.DIFFICULTIES:
		if not only.is_empty() and difficulty not in only: continue
		for level in range(Templates.LEVEL_ROUTES.size()):
			var seen := {}
			for route in Templates.LEVEL_ROUTES[level]:
				for side in [-1.0, 1.0]:
					if route == "left" and side > 0: continue
					if route == "right" and side < 0: continue
					var name := "%s:%s" % [route, side]
					if seen.has(name): continue
					seen[name] = true
					var generator = Templates.new()
					generator.source_override = "runtime"
					var block: Dictionary = Templates.decorate(Templates.make_block(route, side, level), route, side)
					var started := Time.get_ticks_usec()
					var accepted: bool = generator.validate_block(block, difficulty, level, {}, 0.0, true)
					slowest = maxi(slowest, Time.get_ticks_usec() - started)
					total += 1
					if not accepted:
						failed += 1
						print("FAIL %s L%d %s side=%d : %s" % [difficulty, level + 1, route, int(side), generator.last_evidence.reason])
	print("ROUTES total=%d failed=%d slowest_ms=%d" % [total, failed, slowest / 1000])
	quit(1 if failed > 0 else 0)
