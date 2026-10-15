extends SceneTree

const T = preload("res://scripts/road_templates.gd")
var failures := 0

func _initialize() -> void:
	var generator := T.new()
	var routes: Array = []
	for pool in T.Challenges.POOLS:
		for route in pool:
			if route not in routes: routes.append(route)
	var matrix := "--matrix" in OS.get_cmdline_user_args()
	var selected_route:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--route="): selected_route=argument.trim_prefix("--route=")
	for level in range(3 if matrix else 1):
		for route: String in T.Challenges.POOLS[level] if matrix else routes:
			if not selected_route.is_empty() and route!=selected_route: continue
			for mode: String in T.DIFFICULTIES.keys() if matrix else ["普通"]:
				for side: float in [-1.0,1.0] if matrix else [1.0]:
					var block := T.make_block(route,side,level)
					var started := Time.get_ticks_msec()
					var ok := generator.validate_block(block,mode,level)
					print("PASS " if ok else "FAIL ",route," L",level+1," ",mode," side=",side," reason=",generator.last_evidence.get("reason")," exit=",generator.last_evidence.get("exit",{}).get("a")," seconds=",(Time.get_ticks_msec()-started)/1000.0)
					if not ok: failures += 1
	print("TERRAIN_CATALOG failures=",failures)
	quit(1 if failures else 0)
