extends SceneTree
const Landscape=preload("res://scripts/journey_landscape.gd")
const Plans=preload("res://scripts/journey_chunk_plan.gd")
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	var new_assets:={};var maximum:=0
	for chapter in range(3):
		for number in [3,6,10,13,15,17,20]:
			var plan:Array=Plans.make(number,chapter,game.run.CHAPTERS[chapter],game.run.EDGE)
			check(plan==Plans.make(number,chapter,game.run.CHAPTERS[chapter],game.run.EDGE),"identical chunk plan for identical seed")
			var instances:=0
			for item in plan:
				if item[0]!="landscape_batch":continue
				instances+=item[2].size()
				if not item[1].begins_with("detail_"):continue
				new_assets[item[1]]=true
				var parts:Array=game.landscape.load_parts("res://assets/landscape/%s.glb"%item[1])
				for transform:Transform3D in item[2]:
					for part in parts:
						var bounds:AABB=(transform*part.transform)*part.mesh.get_aabb()
						check(bounds.position.x>16.0 or bounds.end.x< -16.0,"decoration mesh stays outside physical road "+item[1])
			maximum=maxi(maximum,instances)
	check(new_assets.size()==8,"all eight new assets are installed in real chunk plans")
	check(maximum<1500,"bounded per-chunk instance budget")
	# 村庄近处让出住宅，树带后移；验证真实实例位置而非只检查配置常量。
	var village:Array=Landscape.plan(17,0)
	for item in village:
		if item[0]=="landscape_batch" and item[1].begins_with("grove_"):
			check(item[2].all(func(t):return absf(t.origin.x)>=49),"village trees leave front-row houses visible")
	var before:int=game.run.sync_hash();game.sync_view()
	check(before==game.run.sync_hash(),"visual sync does not mutate gameplay state")
	check(game.run.journey_events.filter(func(e):return e.kind=="monster").size()==63,"existing monster population unchanged")
	print("ATMOSPHERE CHECKS ",checks," FAILURES ",failures.size()," max_chunk_instances=",maximum," assets=",new_assets.keys())
	game.queue_free();await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
