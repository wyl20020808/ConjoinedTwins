extends SceneTree
var failures:=0
var mesh_changes:=0
func check(ok:bool,message:String)->void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	var run=game.run
	run.state="running";run.combat.weapons[0]=run.Combat.gun()
	var beam:MeshInstance3D=game.combat_view.beams[0]
	var mesh:Mesh=beam.mesh
	mesh.changed.connect(func():mesh_changes+=1)
	for meters in [1.0,8.0,30.0,0.0,12.5]:
		run.combat.shots[0]={"from":Vector2(0,100),"to":Vector2(0,100+meters*20),"height":30.0,"target_height":30.0,"time":run.elapsed,"id":1}
		game.combat_view.sync()
		var half:float=beam.mesh.height*.5
		var first:Vector3=beam.to_global(Vector3(0,-half,0))
		var last:Vector3=beam.to_global(Vector3(0,half,0))
		check(beam.transform.is_finite() and absf(first.distance_to(last)-maxf(.001,meters))<.002,"光束端点匹配射击距离，零长度仍保持有限变换")
	check(beam.mesh==mesh and mesh_changes==0,"多次改变射击距离不重建光束渲染表面")
	for player in game.sfx.players:player.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("JOURNEY_DYNAMIC_GEOMETRY failures=",failures)
	quit(1 if failures else 0)
