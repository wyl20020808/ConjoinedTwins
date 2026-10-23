extends SceneTree
var failures:Array=[]
var samples:Array=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func count_nodes(node:Node)->int:
	var count:=1
	for child in node.get_children():count+=count_nodes(child)
	return count
func _initialize()->void:call_deferred("validate")
func validate()->void:
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	var basis:Basis=game.camera.basis
	for chapter in range(3):
		game.run.level_index=chapter;game.run.retry();game.reset_journey_views()
		for zone in range(6):
			var y:float=game.run.finish_distance()/6*zone+400
			game.run.a.position=Vector2(-42,y);game.run.b.position=Vector2(42,y)
			game.run.rope.reset(game.run.a.position,game.run.b.position)
			game.run.distance=y
			game.sync_view()
			await process_frame
			game.sync_view()
			await process_frame
			var nodes:=count_nodes(game)
			check(nodes<6000,"scene node budget chapter %d zone %d: %d"%[chapter,zone,nodes])
			check(game.road.position==Vector3.ZERO,"map remains fixed")
			check(game.camera.basis.is_equal_approx(basis),"camera never rotates")
			check(absf(game.camera.position.z-(game.camera_home.origin.z-y/20))<0.001,"camera follows actual forward progress")
			samples.append({"chapter":chapter,"zone":zone,"nodes":nodes,"chunks":game.world_chunks.size(),"events":game.event_views.size()})
		# 接近出口并采样真实资源动画。
		for gate in game.run.charge_gates:
			game.run.distance=gate.receiver.y-100
			game.run.elapsed=10
			gate.open=true;gate.opened_at=9.6
			game.sync_view()
			await process_frame
	for filename in ["boar","cart","house_0","house_1","house_2","falling_tree","waterwheel","gate","drawbridge","fence","sign","villager_actions"]:
		check(ResourceLoader.exists("res://assets/journey/%s.glb"%filename),"actual asset exists "+filename)
	# 固定地图进度与暂停不漂移。
	game.run.state="paused"
	var camera_position:Vector3=game.camera.position
	game.run.step(0.2,Vector2(0,1),Vector2(0,1))
	game.sync_view()
	check(game.camera.position==camera_position,"paused camera stable")
	print("JOURNEY SCENE ",JSON.stringify(samples))
	print("JOURNEY SCENE FAILURES ",failures.size())
	var file:=FileAccess.open("res://build-tools/journey/evidence/scene.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"samples":samples,"failures":failures,"visual_gui":"deferred_by_work_mode"},"\t"))
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
