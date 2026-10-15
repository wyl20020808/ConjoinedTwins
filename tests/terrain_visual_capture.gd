extends SceneTree

var game
var records:Array=[]
const OUT="res://build-tools/rope-terrain-evidence/screenshots/"

func _initialize()->void:
	call_deferred("capture")

func shot(name:String)->void:
	for frame in range(10):
		game.sync_view()
		await process_frame
	await RenderingServer.frame_post_draw
	var path:=OUT+name+".png"
	var error:=root.get_texture().get_image().save_png(path)
	records.append({"path":path,"error":error,"state":game.run.state,"distance":game.run.distance,"rope_stretch":game.run.rope.physical.get("stretch",0.0)})
	print("CAPTURE ",name," error=",error)

func fixture()->void:
	game.run.retry()
	game.fail_clock=0
	game.fall_clock=0
	game.run.a.position=Vector2(-25,0)
	game.run.b.position=Vector2(25,0)
	game.run.rope.reset(game.run.a.position,game.run.b.position)
	game.run.step(0)
	game.frame_delta=1.0/60

func capture()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	game=load("res://scenes/road_demo.tscn").instantiate()
	game.run.generation_enabled=false
	game.run.async_enabled=false
	root.add_child(game)
	game.set_physics_process(false)
	game.run.charge_tutorial=false
	fixture()
	for tick in range(160): game.run.step(game.run.FIXED_STEP)
	await shot("01-slack-hemp")
	for tick in range(160): game.run.step(game.run.FIXED_STEP,Vector2.LEFT,Vector2.RIGHT)
	await shot("02-taut-hemp")
	var home:Transform3D=game.camera_home
	game.camera_home=Transform3D.IDENTITY.translated(Vector3(0,4.8,8)).looking_at(Vector3(0,1.4,0),Vector3.UP)
	game.camera.transform=game.camera_home
	await shot("03-hemp-detail")
	game.camera_home=home
	for route in ["ridge_turn","steps_path","tilt_path","ferry_crossing","steam_corridor","pressure_bridge","winch_bridge"]:
		fixture()
		var block:Dictionary=game.run.Templates.make_block(route,1,1)
		var base:float=game.run.speed()*1.6 if route=="steam_corridor" else 0.0
		game.run.install_block(block,base,route)
		game.run.revision+=1
		var target:float=base+(310.0 if not route.ends_with("bridge") else 110.0)
		for tick in range(2600):
			var input:Array=game.run.Templates.route_input(game.run,block,base)
			game.run.step(game.run.FIXED_STEP,input[0],input[1],input[2],input[3])
			if tick%12==0:
				game.sync_view()
				await process_frame
			if game.run.distance>=target or game.run.state!="running": break
		await shot(route)
	fixture()
	game.run.install_block({"hazards":[{"kind":"road_gap","rect":Rect2(-360,-50,720,400)}],"rewards":[]},0,"fall")
	game.run.revision+=1
	game.run.fallen=[true,true]
	game.run.fail_threat("坠落演出验收")
	for tick in range(70):
		game.run.step(game.run.FIXED_STEP)
		game.fail_clock=game.run.death_time
		game.fall_clock=game.run.death_time
		if tick%2==0:
			game.sync_view()
			await process_frame
	await shot("10-fall-rope")
	fixture()
	game.run.fail_threat("撞击脱扣验收")
	for tick in range(150): game.run.step(game.run.FIXED_STEP)
	await shot("11-released-rope")
	var file:=FileAccess.open(OUT+"captures.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t"))
	var failed:=records.any(func(record): return record.error!=OK)
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
