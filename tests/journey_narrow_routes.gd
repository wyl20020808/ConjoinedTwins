extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
const Buddy=preload("res://scripts/journey_buddy.gd")
const Route=preload("res://tests/fixtures/journey_route.gd")
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var shapes:={}
	for chapter in range(3):
		var run=Journey.new();run.level_index=chapter;run.retry()
		var routes:={}
		for marker in run.encounter_markers:
			if marker.has("lanes"):routes[marker.narrow_start]=marker;shapes[marker.kind]=true
		check(routes.size()>=3,"chapter %d repeated narrow terrain"%chapter)
		var small:=0
		for i in range(run.kinds.size()):
			if not run.hazard_specs[i].get("small",false):continue
			small+=1
			check(run.obstacles[i].size.x<=52 and run.obstacles[i].size.y<=30,"small physical footprint")
			check(run.obstacles[i].end.y+run.Motion.RADIUS<run.hazard_specs[i].beat_end,"small hazard leaves complete side-change clearance")
			for point in [run.obstacles[i].position,run.obstacles[i].end,run.obstacles[i].get_center()]:check(run.surface_at(point,0).supported,"small mechanism stays over real ground")
		check(small>=50,"chapter %d at least 50 small mechanisms"%chapter)
		for route:Dictionary in routes.values():
			for y in range(int(route.narrow_start+20),int(route.narrow_end-20),20):
				for x in range(-int(run.EDGE)+1,int(run.EDGE),4):
					var expected:bool=route.lanes.any(func(lane):return x>=lane-22 and x<lane+22)
					check(run.surface_at(Vector2(x,y),0).supported==expected,"only marked lanes have ground")
		print("NARROW CHAPTER ",chapter," routes=",routes.size()," small=",small)
		run.dispose()
	check(shapes.size()==4,"central, edge, double and triple paths all deployed")
	var case_index:=0
	for lanes in [[0.0],[-245.0],[245.0],[-55.0,55.0],[-66.0,0.0,66.0],[0.0],[-245.0]]:
		var run=Journey.new()
		run.journey_events.clear();run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear();run.encounter_markers.clear()
		run.charge_gates.clear();run.select_charge_gate();run.rewards.clear();run.combat=run.Combat.fresh()
		var route:={"start":400.0,"end":840.0,"lanes":lanes}
		run.Encounters.narrow_terrain(run,route)
		run.encounter_markers.append({"y":400.0,"kind":"center_path","blocked":1.0,"formation":true,"lanes":lanes,"narrow_start":400.0,"narrow_end":840.0})
		run.a.position=Vector2(-42,220);run.b.position=Vector2(42,220);run.distance=220
		if case_index>=5:run.a.position=Vector2(lanes[0],220);run.b.position=Vector2(lanes[0],260)
		case_index+=1
		run.rope.reset(run.a.position,run.b.position);run.last_support=[run.a.position,run.b.position]
		run.state="running";run.clear_input=false;run.external_companion=true
		var buddy=Buddy.new();var frames:=0;var max_rope:=0.0
		while run.state=="running" and run.progress()<910 and frames<1800:
			var human:Dictionary=Route.input(run)
			var choice:Dictionary=buddy.think(run,run.FIXED_STEP,human.move,human.jump)
			run.step(run.FIXED_STEP,human.move,choice.move,human.jump,choice.jump)
			max_rope=maxf(max_rope,run.rope.length);frames+=1
		check(run.state=="running" and run.progress()>=910,"normal inputs cross lanes %s state=%s pos=%s/%s"%[lanes,run.state,run.a.position,run.b.position])
		check(max_rope<=run.LINK_LIMIT+.02,"narrow passage retains rope constraint")
		run.dispose()
	print("NARROW CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
