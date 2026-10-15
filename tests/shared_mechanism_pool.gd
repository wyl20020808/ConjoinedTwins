extends SceneTree

const T = preload("res://scripts/road_templates.gd")
var failures := 0

func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize() -> void:
	var expected: Array = T.SHARED_ROUTES.duplicate()
	expected.append_array(["charge_cargo", "sync_cargo", "charge_sync_relay"])
	for level in range(3):
		check("shared catalog L%d" % (level+1), T.LEVEL_ROUTES[level] == T.SHARED_ROUTES and T.Challenges.POOLS[level] == T.Challenges.ROUTES)
		var openings := {}
		for seed_value in range(8):
			var generator := T.new()
			var replica := T.new()
			generator.reset(seed_value)
			replica.reset(seed_value)
			var seen := {}
			var deterministic := true
			var distinct := true
			var previous := ""
			for number in range(expected.size()*2):
				var candidate: Dictionary = generator.candidate_block(number,level)
				deterministic = deterministic and candidate == replica.candidate_block(number,level)
				distinct = distinct and candidate.route != previous
				previous = candidate.route
				if number == 0: openings[candidate.route] = true
				seen[candidate.route] = true
				if number%expected.size() == expected.size()-1:
					check("complete shuffled bag L%d seed=%d cycle=%d" % [level+1,seed_value,number/expected.size()], seen.size() == expected.size() and expected.all(func(route): return seen.has(route)))
					seen.clear()
			check("deterministic and no adjacent repeats L%d seed=%d" % [level+1,seed_value],deterministic and distinct)
		check("varied opening L%d" % (level+1),openings.size()>1)
		if "--prove" in OS.get_cmdline_user_args():
			var verifier := T.new()
			for route in expected:
				var filter := ""
				for argument in OS.get_cmdline_user_args():
					if argument.begins_with("--route="): filter = argument.trim_prefix("--route=")
				if not filter.is_empty() and route != filter: continue
				var matrix := "--matrix" in OS.get_cmdline_user_args()
				for mode: String in T.DIFFICULTIES.keys() if matrix else ["普通"]:
					for side: float in [-1.0,1.0] if matrix else [1.0]:
						var ok: bool = verifier.validate_block(T.make_block(route,side,level),mode,level)
						check("production passage %s L%d %s side=%s reason=%s" % [route,level+1,mode,side,verifier.last_evidence.get("reason","")],ok)
						if not ok: print("EXIT ",verifier.last_evidence.get("exit"))
	print("SHARED_MECHANISM_POOL failures=",failures)
	quit(1 if failures else 0)
