extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
const Physics=preload("res://scripts/rope_physics.gd")
var checks:=0
var failures:=0
func check(ok:bool)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL floor projection differs")
func _initialize()->void:
	var rng:=RandomNumberGenerator.new();rng.seed=193214
	var run=Journey.new();run.random_seed=false;run.seed_value=8123
	for chapter in range(3):
		run.level_index=chapter;run.retry()
		for location in [0.0,6000.0,9600.0,16000.0]:
			run.a.position=Vector2(-42,location);run.b.position=Vector2(42,location)
			for time in [0.0,3.25,14.25]:
				run.elapsed=time
				var hint:Dictionary={};var floor_query:=run.rope_floor_query(hint)
				var colliders:Array=run.rope_colliders()
				var fast=Physics.ContactQuery.new(floor_query,colliders,hint.bounds,hint.ceiling)
				var reference=Physics.ContactQuery.new(floor_query,colliders)
				for n in range(400):
					var p:=Vector3(rng.randf_range(-380,380),rng.randf_range(-60,150),location+rng.randf_range(-400,400))
					if n<4:p=Vector3(hint.bounds.end.x,1.0,location)
					check(fast.project(p,p+Vector3(0,2,0))==reference.project(p,p+Vector3(0,2,0)))
				var a:=Vector3(-42,28,location);var b:=Vector3(42,28,location)
				var chain:=Physics.create(a,b,run.LINK_LIMIT);var original:Dictionary=chain.duplicate(true)
				for frame in range(30):
					var guide:=PackedVector3Array([a,b])
					Physics.advance(chain,a,b,run.FIXED_STEP,floor_query,colliders,guide,hint)
					Physics.advance(original,a,b,run.FIXED_STEP,floor_query,colliders,guide)
					check(chain==original)
	# 有高度的平面、斜坡回退、区域外高台和边界接触。
	var callback:Callable=func(p:Vector2)->float:return 50.0 if p.x>=10 else (20.0 if p.y>0 else -INF)
	for ceiling in [20.0,INF]:
		var fast=Physics.ContactQuery.new(callback,[],Rect2(-10,-10,20,20),ceiling)
		var reference=Physics.ContactQuery.new(callback,[])
		for x in [-11.0,-10.0,0.0,9.999,10.0,11.0]:
			for height in [19.0,20.999,21.0,21.001,49.0,51.0]:
				var p:=Vector3(x,height,1)
				check(fast.project(p,p+Vector3.UP*3)==reference.project(p,p+Vector3.UP*3))
	run.dispose()
	print("STUTTER_FLOOR checks=",checks," failures=",failures)
	quit(1 if failures else 0)
