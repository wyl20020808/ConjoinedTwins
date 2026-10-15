extends SceneTree

const T=preload("res://scripts/road_templates.gd")
var failures:=0

func check(label:String,ok:bool)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1

func _initialize()->void:
	call_deferred("verify")

func verify()->void:
	var game=load("res://scenes/road_demo.tscn").instantiate()
	game.run.generation_enabled=false
	root.add_child(game)
	game.set_physics_process(false)
	var run=game.run
	run.charge_tutorial=false
	var routes:Array=[]
	for pool in T.Challenges.POOLS:
		for route in pool:
			if route not in routes: routes.append(route)
	for route in routes:
		run.retry()
		run.install_block(T.make_block(route,1,0),0,route)
		run.revision+=1
		run.step(run.FIXED_STEP)
		game.sync_view()
		check("生产视图完整创建 "+route,game.hazard_views.size()==run.obstacles.size())
		for i in range(run.kinds.size()):
			if run.kinds[i] in run.Terrain.MOVING:
				check("平台显示与生产高度一致 "+route,absf(game.hazard_views[i].position.y-run.terrain_sample(i,run.elapsed,run.obstacles[i].get_center()).height/20.0)<0.001)
		check("麻绳画面消费生产质点 "+route,game.rope_view.points.size()==run.rope.physical.points.size())
		check("麻绳无自发光 "+route,not game.rope_view.rope_material.emission_enabled)
	run.fallen=[true,true]
	run.fail_threat("坠落视图")
	for tick in range(90): run.step(run.FIXED_STEP)
	game.sync_view()
	for role in range(2):
		var index:int=0 if role==0 else game.rope_view.points.size()-1
		var waist:Vector3=game.robots[role].position+game.robots[role].basis*Vector3(0,1.4,0)
		check("死亡翻滚时绳端贴合腰部 P%d"%(role+1),waist.distance_to(game.rope_view.points[index])<0.01)
	game.queue_free()
	await process_frame
	print("TERRAIN_VIEW failures=",failures," visual_acceptance=separate_render_capture")
	quit(1 if failures else 0)
