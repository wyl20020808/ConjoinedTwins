extends SceneTree
const Templates = preload("res://scripts/road_templates.gd")
const Keyboard = preload("res://tests/keyboard_route_assertions.gd")
func _initialize() -> void:
	var generator = Templates.new()
	var results: Array = []
	var failed := 0
	for difficulty in Templates.DIFFICULTIES:
		for level in range(3):
			# 保留历史目录检查并追加新教学布局，不删除既有布局断言。
			var kinds: Array = Templates.ROUTES.duplicate()
			if level >= 1: kinds.append_array(["body", "stone_ball"])
			kinds.append("safe")
			for kind in kinds:
				if level == 0 and kind in ["stagger", "double"]: continue
				if level == 1 and kind == "double": continue
				for side in [-1.0, 1.0]:
					var ok: bool = generator.validate_block(Templates.make_block(kind, side, level), difficulty, level)
					for input in generator.last_evidence.inputs: ok = Keyboard.legal(input) and ok
					results.append(generator.last_evidence.duplicate(true))
					if not ok:
						failed += 1
						print("FAIL ", difficulty, " ", level, " ", kind, " ", side, " ", generator.last_evidence.reason, " ", generator.last_evidence.exit)
	var file := FileAccess.open("res://tests/short-rope-t05-catalog.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failed": failed, "routes": results}))
	file.close()
	print("CATALOG failed=", failed, " count=", results.size())
	quit(1 if failed else 0)
