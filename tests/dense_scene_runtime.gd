extends SceneTree

func _initialize() -> void:call_deferred("measure")

func measure() -> void:
	Engine.max_fps=60
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game);game.set_physics_process(false)
	game.input_override={"a":Vector2.ZERO,"b":Vector2.ZERO,"ja":false,"jb":false}
	var rows: Array=[]
	for chapter in range(3):
		game.run.random_seed=false;game.run.seed_value=8123;game.run.level_index=chapter;game.run.retry()
		var found:=false
		for offset in [0,100,-100,200,-200]:
			for x in [-42,-120,80,-200,180]:
				var point:=Vector2(x,9600+offset)
				if game.run.Monsters.safe_spawn(game.run,point) and game.run.Monsters.safe_spawn(game.run,point+Vector2(56,0)):
					game.run.a.position=point;game.run.b.position=point+Vector2(56,0);found=true;break
			if found:break
		assert(found)
		game.run.distance=game.run.a.position.y;game.run.elapsed=10
		for gate in game.run.charge_gates:
			gate.open=gate.receiver.y<game.run.distance-180;gate.opened_at=0 if gate.open else -1
		game.run.select_charge_gate();game.run.rope.reset(game.run.a.position,game.run.b.position)
		game.run.state="running";game.run.clear_input=false;game.buddy.reset();game.reset_journey_views()
		game.sync_view()
		for frame in range(12):await process_frame
		game.set_physics_process(true)
		for frame in range(12):await process_frame
		var start:=Time.get_ticks_usec();var previous:=start;var elapsed:float=game.run.elapsed;var samples: Array=[]
		for frame in range(120):
			await process_frame
			var now:=Time.get_ticks_usec();samples.append(now-previous);previous=now
		var seconds:float=(previous-start)/1000000.0
		samples.sort()
		rows.append({"chapter":chapter,"valid":game.run.state=="running","wall_seconds":seconds,"simulation_seconds":game.run.elapsed-elapsed,"fps":120/seconds,"frame_p95_ms":samples[113]/1000.0,"frame_max_ms":samples[-1]/1000.0,"state":game.run.state,"hazards":game.run.kinds.size(),"events":game.run.journey_events.size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		game.set_physics_process(false)
	var report:={"method":"隐藏1280x720 ANGLE窗口，生产物理/搭档/渲染均启用，60FPS上限，每章120绘制帧；非用户实机验收","rows":rows}
	var output:=OS.get_environment("DENSE_RUNTIME_REPORT");assert(not output.is_empty())
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DENSE RUNTIME ",JSON.stringify(report))
	game.queue_free();await process_frame;await create_timer(.15).timeout;quit()
