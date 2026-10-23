extends SceneTree

# 生产展示的分项探针。观察点按夹具移动，不是物理通关或真实键盘验收。

var rows:Array=[]
var output:String
var game

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	call_deferred("measure")

func measure()->void:
	Engine.max_fps=60
	output=OS.get_environment("STUTTER_RENDER_REPORT")
	assert(not output.is_empty())
	game=load("res://tests/fixtures/stutter_timed_view.gd").new()
	game.incremental_loading=true
	game.opening_enabled=false
	root.add_child(game)
	while not game.scene_prepared:await process_frame
	game.set_physics_process(false);game.set_process(false)
	game.run.random_seed=false;game.run.seed_value=8123
	game.play_mode="local"
	var monitors:Dictionary={}
	for key in ClassDB.class_get_integer_constant_list("Performance"):
		if "PIPELINE_COMPILATIONS" in key:monitors[key]=ClassDB.class_get_integer_constant("Performance",key)
	for chapter in range(3):
		game.run.level_index=chapter;game.run.retry();game.reset_journey_views()
		for location in [0.0,6000.0,16000.0]:
			game.run.a.position=Vector2(-42,location);game.run.b.position=Vector2(42,location)
			game.run.distance=location;game.run.rope.reset(game.run.a.position,game.run.b.position)
			for frame in range(120):
				game.run.state="running";game.run.elapsed+=1.0/60
				game.timings.clear()
				var begin:=Time.get_ticks_usec()
				var ready:bool=game.prepare_journey_frame()
				var prepared:=Time.get_ticks_usec()
				game.frame_delta=1.0/60;game.view_pending=false
				game.sync_view()
				var submitted:=Time.get_ticks_usec()
				var costs:Dictionary=game.timings.duplicate()
				await process_frame
				var row:={"chapter":chapter,"location":location,"frame":frame,"ready":ready,
					"prepare_us":prepared-begin,"view_us":submitted-prepared,"interval_us":Time.get_ticks_usec()-begin,
					"parts":costs,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
				for key in monitors:row[key]=Performance.get_monitor(monitors[key])
				rows.append(row)
			print("PROFILE_POINT chapter=",chapter," location=",location)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"scope":"production presentation at fixed observation points; no gameplay or input acceptance","rows":rows},"\t"))
	for player in game.sfx.players:player.stop()
	game.queue_free()
	for frame in range(6):await process_frame
	print("STUTTER_RENDER_PROFILE samples=",rows.size())
	quit()
