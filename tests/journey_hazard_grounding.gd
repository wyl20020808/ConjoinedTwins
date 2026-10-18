extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
var failures:=0
func check(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("FAIL ",message)
func _initialize()->void:
	for chapter in range(3):
		var run=Journey.new();run.level_index=chapter;run.retry()
		var small:=0;var balls:=0;var gaps:Array=run.ground_gaps()
		for i in range(run.kinds.size()):
			var kind:String=run.kinds[i]
			if run.hazard_specs[i].get("small",false):small+=1
			if run.hazard_specs[i].get("rolling_pair",false):
				balls+=1
				check(absf(run.hazard_specs[i].velocity.y)>=620,"rolling wave speed")
			if kind in ["road_gap","drawbridge","ferry","drone"] or run.hazard_specs[i].get("front",false):continue
			for gap:Rect2 in gaps:
				check(not gap.intersects(run.obstacles[i].grow(-.1)),"grounded %s chapter=%d index=%d rect=%s gap=%s"%[kind,chapter,i,run.obstacles[i],gap])
		check(small>=75,"small mechanisms per chapter")
		check(balls>=20,"rolling pairs per chapter")
		print("GROUNDING chapter=",chapter," small=",small," fast_balls=",balls)
		run.dispose()
	print("JOURNEY_HAZARD_GROUNDING failures=",failures)
	quit(1 if failures else 0)
