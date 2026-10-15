extends SceneTree

const Run=preload("res://scripts/road_run.gd")
var failures:=0

func check(label:String,ok:bool)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1

func _initialize()->void:
	var run=Run.new(false)
	run.streaming=false
	run.retry()
	var worst_bound:=0.0
	var worst_rope:=0.0
	var phases:=[
		[3.0,Vector2.UP,Vector2.UP],
		[4.0,Vector2.DOWN,Vector2.DOWN],
		[4.0,Vector2.UP,Vector2.DOWN],
		[5.0,Vector2.DOWN,Vector2.UP],
		[4.0,Vector2.LEFT,Vector2.RIGHT]]
	for phase in phases:
		for tick in range(int(phase[0]*120)):
			run.step(Run.FIXED_STEP,phase[1],phase[2])
			worst_bound=maxf(worst_bound,maxf(absf(run.a.position.y-run.distance),absf(run.b.position.y-run.distance)))
			worst_rope=maxf(worst_rope,run.rope.required)
		check("共同推进及接触不会无障碍判失败 "+str(phase[1])+" / "+str(phase[2]),run.state=="running")
	check("接触中仍保持前后各五米边界",worst_bound<=Run.RELATIVE_RANGE+0.002)
	check("全程三维绳长不超限",worst_rope<=Run.LINK_LIMIT+0.01)
	check("前后顶住后仍可横向解开并拉紧",run.a.position.distance_to(run.b.position)>=Run.LINK_LIMIT-0.1)
	run.dispose()
	print("PHYSICAL_COOPERATION_MOTION failures=",failures)
	quit(1 if failures else 0)
