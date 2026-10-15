extends SceneTree

const Journey=preload("res://scripts/journey_run.gd")
var failures:Array=[]
func _initialize()->void:call_deferred("verify")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);push_error(message)
func reference_floor(run,point:Vector2)->float:
	var supported:bool=absf(point.x)<=run.EDGE
	for gap in run.ground_gaps(run.elapsed):
		if gap.has_point(point):supported=false
	for i in range(run.kinds.size()):
		if run.kinds[i] not in run.Terrain.KINDS:continue
		var patch:Dictionary=run.terrain_sample(i,run.elapsed,run.obstacles[i].get_center())
		if patch.rect.has_point(point) and patch.supported:return run.terrain_sample(i,run.elapsed,point).height
	return 0.0 if supported else -INF
func verify()->void:
	var checks:=0
	var rng:=RandomNumberGenerator.new();rng.seed=374112
	for chapter in range(3):
		var run=Journey.new();run.random_seed=false;run.seed_value=912733
		run.level_index=chapter;run.retry();run.elapsed=13.75
		var query:Callable=run.rope_floor_query()
		for rect:Rect2 in run.obstacles:
			for offset in [Vector2.ZERO,Vector2(60,80),Vector2(-40,-100)]:
				var p:Vector2=rect.get_center()+offset
				var q:=p+Vector2(90,70)
				for heights in [Vector2(26,26),Vector2(1,80),Vector2(-10,30)]:
					check(run.surface_rope_length(p,q,heights.x,heights.y)==reference_length(run,p,q,heights.x,heights.y),"局部平台绳长与原十二点采样完全一致")
					checks+=1
		# 与未裁剪的精确扫掠对照，覆盖远处、穿越、原地和不同高度。
		for sample in range(1200):
			var rect:Rect2=run.obstacles[sample%run.obstacles.size()]
			var from:=rect.get_center()+Vector2(rng.randf_range(-200,200),rng.randf_range(-200,200))
			var to:=rect.get_center()+Vector2(rng.randf_range(-200,200),rng.randf_range(-200,200)) if sample%4 else from
			var h0:=rng.randf_range(-20,200);var h1:=rng.randf_range(-20,200)
			check(run.solid_sweep_clear(from,to,h0,h1)==reference_solid(run,from,to,h0,h1),"实体索引和包围盒不漏判")
			checks+=1
		for sample in range(40):
			var time:float=run.elapsed+float(sample%20)*.13
			var expected:Array[Rect2]=[]
			for i in range(run.kinds.size()):
				if run.kinds[i]=="road_gap" or (run.kinds[i]=="collapse" and run.hazard_sample(i,time).stage=="collapsed"):expected.append(run.obstacles[i])
			check(run.ground_gaps(time)==expected,"多时间缓存与原始缺口逐次采样一致")
			check(run.ground_gap_queries.size()<=16,"预测查询缓存有界")
			checks+=2
		for rect:Rect2 in run.obstacles:
			for point:Vector2 in [rect.position,rect.end,rect.get_center(),rect.get_center()+Vector2(1,1)]:
				check(query.call(point)==reference_floor(run,point),"地面查询保留远处、边界及移动平台语义")
				checks+=1
		for i in range(run.kinds.size()):
			if run.kinds[i] not in run.Industrial.KINDS:continue
			var envelope:Rect2=run.Industrial.motion_envelope(run.kinds[i],run.obstacles[i],run.hazard_specs[i])
			for time in [0.0,0.4,1.5,3.0,8.0,29.0]:
				for part in run.hazard_sample(i,time).parts:
					check(envelope.grow(.001).encloses(part.rect),"保守包围盒包含完整分部运动")
					checks+=1
		run.dispose()
	# 独立构造全部类型，覆盖触发后的移动、摆动和高度相位。
	for kind in Journey.Industrial.KINDS:
		var rect:=Rect2(-40,-50,80,100)
		var state:Dictionary=Journey.Industrial.spec(kind,1,0)
		state.trigger=0.0
		var envelope:Rect2=Journey.Industrial.motion_envelope(kind,rect,state)
		for sample in range(121):
			for part in Journey.Industrial.sample(kind,rect,state,sample*.1).parts:
				check(envelope.grow(.001).encloses(part.rect),"独立运动包围盒："+kind)
				checks+=1
	print("WEB_PERFORMANCE_REGRESSION checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func reference_solid(run,from:Vector2,to:Vector2,h0:float,h1:float)->bool:
	if run.charge_gate.active and not run.charge_gate.open and run.segment_hits(from,to,run.charge_gate.door.grow(run.Motion.RADIUS-.001)):return false
	for i in range(run.kinds.size()):
		if run.solid_sweep_hits(i,from,to,h0,h1):return false
	return true

func reference_length(run,p:Vector2,q:Vector2,h0:float,h1:float)->float:
	var distance:=Vector2(p.distance_to(q),h1-h0).length()
	if not run.kinds.any(func(kind):return kind in run.Terrain.KINDS):return distance
	var previous:=Vector3(p.x,h0,p.y);var total:=0.0
	for i in range(1,13):
		var t:=float(i)/12;var point:=p.lerp(q,t);var height:=lerpf(h0,h1,t)
		if i<12:height=maxf(height,run.rope_floor(point)+run.RopePhysics.RADIUS)
		var current:=Vector3(point.x,height,point.y)
		total+=previous.distance_to(current);previous=current
	return maxf(total,distance)
