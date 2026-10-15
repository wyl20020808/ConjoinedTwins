extends SceneTree

const Run = preload("res://scripts/road_run.gd")
var failures := 0

func _initialize() -> void:
	var levels:Array=range(3)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--level="): levels=[int(argument.trim_prefix("--level="))]
	for level in levels:
		var run=Run.new(true,false)
		run.level_index=level
		run.seed_value=61015+level
		run.retry()
		var routes: Array=[]
		var ticks:=0
		while run.state=="running" and ticks<22000:
			var input: Array=Run.Templates.existing_route_input(run)
			run.step(Run.FIXED_STEP,input[0],input[1],input[2],input[3])
			for entry in run.route_segments:
				if entry.block.route not in routes: routes.append(entry.block.route)
			ticks+=1
			if ticks%3600==0: print("PROGRESS L",level+1," distance=",run.total_distance()," segments=",run.next_segment)
		var ok: bool=run.state=="settlement" and not run.generation_halted
		print("PASS " if ok else "FAIL ","生产关卡 L",level+1," state=",run.state," reason=",run.reason," distance=",run.total_distance()," routes=",routes)
		if not ok:
			failures+=1
			for rejection in run.generator.rejection_evidence: print("REJECTION ",rejection.route," ",rejection.reason," exit=",rejection.exit.get("a"))
		run.dispose()
	print("TERRAIN_CAMPAIGN failures=",failures)
	quit(1 if failures else 0)
