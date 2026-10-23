extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
func reference(run,index:int,start:float,end:float,old:PackedVector2Array,z:PackedFloat32Array)->bool:
	var current:PackedVector2Array=run.rope.physical_path();var heights:PackedFloat32Array=run.rope.physical_heights()
	var margin:=0.0
	if old.size()==current.size():
		for i in range(old.size()):margin=maxf(margin,old[i].distance_to(current[i]))
	else:margin=(run.speed()+run.LATERAL)*(end-start)
	for pass_index in range(2):
		var path:PackedVector2Array=old if pass_index==0 else current
		var low:PackedFloat32Array=(z if pass_index==0 else heights).duplicate()
		if z.size()==heights.size():
			for i in range(low.size()):low[i]=minf(z[i],heights[i])
		if run.Surfaces.rope_hits(run.obstacles[index].get_center(),run.hazard_specs[index],start,end,path,low,margin):return true
	return false
func _initialize()->void:
	var run=Journey.new();var index:int=run.add_hazard("sweeper",Rect2(-5,-5,10,10))
	var rng:=RandomNumberGenerator.new();rng.seed=7421
	var failures:=0;var positives:=0
	for sample in range(900):
		var points:=PackedVector3Array();var old:=PackedVector2Array();var z:=PackedFloat32Array()
		var center:=Vector2(rng.randf_range(-240,240),rng.randf_range(-180,180))
		for i in range(5):
			var p:Vector2=center+Vector2(i*22-44,rng.randf_range(-15,15))
			old.append(p);z.append(rng.randf_range(-5,50))
			var shift:=Vector2(rng.randf_range(-90,90),rng.randf_range(-90,90))
			points.append(Vector3(p.x+shift.x,rng.randf_range(-5,50),p.y+shift.y))
		if sample%3==0:points.remove_at(4)
		run.rope.physical={"points":points}
		var start:=rng.randf()*8;var end:=start+rng.randf_range(.001,.2)
		var expected:=reference(run,index,start,end,old,z)
		if expected:positives+=1
		if run.sweeper_rope_hits(index,start,end,old,z)!=expected:failures+=1
	run.dispose();print("SWEEPER BOUNDS checks=900 hits=",positives," failures=",failures)
	quit(0 if failures==0 and positives>0 else 1)
