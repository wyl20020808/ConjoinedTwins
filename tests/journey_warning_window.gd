extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
var failures:Array=[]
var checks:=0
func _initialize()->void:
	var run=Journey.new()
	for items in [run.kinds,run.obstacles,run.hazard_specs,run.obstacle_ids,run.obstacle_heights]:items.clear()
	var rng:=RandomNumberGenerator.new();rng.seed=20261018
	for kind in ["fly_low","fly_body","rocket","stone_ball","iron_ball"]:
		var index:int=run.add_hazard(kind,Rect2(Vector2.ZERO,run.Threats.CONFIG[kind].size))
		for sample in range(1000):
			run.a.position=Vector2(rng.randf_range(-run.EDGE,run.EDGE),rng.randf_range(-150,150))
			run.b.position=Vector2(rng.randf_range(-run.EDGE,run.EDGE),rng.randf_range(-150,150))
			var spec:Dictionary=run.hazard_specs[index]
			spec.locked=false;spec.offset=Vector2(rng.randf_range(-1000,1000),rng.randf_range(-2000,20000))
			spec.warning=rng.randf_range(.1,4)
			var before:Dictionary=spec.duplicate(true)
			var speed:float=run.speed()
			var near:bool=run.front_warning_near(index,speed)
			var velocities:Array=[Vector2(0,speed+rng.randf_range(-run.LATERAL,run.LATERAL)),Vector2(0,speed+rng.randf_range(-run.LATERAL,run.LATERAL))]
			run.Threats.warn(before,run.hazard_sample(index,run.elapsed).rect,[run.a.position,run.b.position],velocities,run.LATERAL,run.EDGE,run.Motion.RADIUS,run.elapsed,run.level_speed()+run.LATERAL)
			checks+=1
			if before.locked and not near:failures.append([kind,sample]);printerr("FAIL omitted warning lock ",kind," ",sample)
	run.dispose()
	print("JOURNEY_WARNING_WINDOW checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
