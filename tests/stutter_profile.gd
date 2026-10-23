extends SceneTree

const Journey=preload("res://scripts/journey_run.gd")
const Buddy=preload("res://scripts/journey_buddy.gd")

class TimedRun extends Journey:
	var costs:={}
	func record_cost(key: String, started: int) -> void:
		var row: Dictionary=costs.get(key,{"calls":0,"usec":0})
		row.calls+=1;row.usec+=Time.get_ticks_usec()-started;costs[key]=row
	func advance_events(dt: float) -> void:
		var start:=Time.get_ticks_usec();super(dt);record_cost("events",start)
	func check_event_hits(previous: Array) -> void:
		var start:=Time.get_ticks_usec();super(previous);record_cost("event_hits",start)
	func surface_at(point: Vector2,time: float,radius: float=0.0) -> Dictionary:
		var start:=Time.get_ticks_usec();var result: Dictionary=super(point,time,radius);record_cost("surface",start);return result
	func industrial_hits(index: int,start: float,end: float,pa: Vector2,ca: Vector2,pb: Vector2,cb: Vector2,old_heights: Array,old_path: PackedVector2Array,old_z: PackedFloat32Array) -> Dictionary:
		var began:=Time.get_ticks_usec();var result: Dictionary=super(index,start,end,pa,ca,pb,cb,old_heights,old_path,old_z);record_cost("industrial",began);return result
	func rope_circles() -> Array:
		var start:=Time.get_ticks_usec();var result: Array=super();record_cost("rope_circles",start);return result
	func advance_rope(dt: float) -> void:
		var start:=Time.get_ticks_usec();super(dt);record_cost("rope_physics",start)

	func bounded(point: Vector2, floor: float = INF) -> Vector2:
		var start:=Time.get_ticks_usec();var result: Vector2=super(point,floor);record_cost("bounded",start);return result
	func surface_rope_length(p: Vector2,q: Vector2,h0: float,h1: float) -> float:
		var start:=Time.get_ticks_usec();var result: float=super(p,q,h0,h1);record_cost("surface_rope_length",start);return result
	func ground_gaps(time: float = -1.0) -> Array[Rect2]:
		var start:=Time.get_ticks_usec();var result: Array[Rect2]=super(time);record_cost("ground_gaps",start);return result
	func indexed_kinds(wanted: Array) -> Array[int]:
		var start:=Time.get_ticks_usec();var result: Array[int]=super(wanted);record_cost("indexed_kinds",start);return result
	func obstacles_in_bounds(bounds: Rect2) -> Array[int]:
		var start:=Time.get_ticks_usec();var result: Array[int]=super(bounds);record_cost("obstacles_in_bounds",start);return result
	func update_checkpoint() -> void:
		var start:=Time.get_ticks_usec();super();record_cost("update_checkpoint",start)

	func advance_threats(dt: float) -> Dictionary:
		var started:=Time.get_ticks_usec();var result: Dictionary=super(dt);record_cost("advance_threats",started);return result
	func rope_floor_query(hint:Dictionary={}) -> Callable:
		var started:=Time.get_ticks_usec();var result: Callable=super(hint);record_cost("rope_floor_query",started);return result
	func rope_colliders() -> Array:
		var started:=Time.get_ticks_usec();var result: Array=super();record_cost("rope_colliders",started);return result
	func surface_rope_guide() -> PackedVector3Array:
		var started:=Time.get_ticks_usec();var result: PackedVector3Array=super();record_cost("surface_rope_guide",started);return result
	func hazard_sample(index: int, time: float) -> Dictionary:
		var started:=Time.get_ticks_usec();var result: Dictionary=super(index,time);record_cost("hazard_sample",started);return result
	func plank_assist(point: Vector2, input: Vector2) -> Vector2:
		var started:=Time.get_ticks_usec();var result: Vector2=super(point,input);record_cost("plank_assist",started);return result
	func color_gate_block(role: int, from: Vector2, to: Vector2) -> Vector2:
		var started:=Time.get_ticks_usec();var result: Vector2=super(role,from,to);record_cost("color_gate_block",started);return result
	func advance_collapse(start: float, end: float, pa: Vector2, ca: Vector2, pb: Vector2, cb: Vector2, old_heights: Array) -> void:
		var started:=Time.get_ticks_usec();super(start,end,pa,ca,pb,cb,old_heights);record_cost("advance_collapse",started)
	func resolve_cargo(from: Vector2, to: Vector2, h0: float, h1: float) -> Vector2:
		var started:=Time.get_ticks_usec();var result: Vector2=super(from,to,h0,h1);record_cost("resolve_cargo",started);return result
	func separate_bodies(pa: Vector2, pb: Vector2, ca: Vector2, cb: Vector2, floor_a: float = INF, floor_b: float = INF) -> Array:
		var started:=Time.get_ticks_usec();var result: Array=super(pa,pb,ca,cb,floor_a,floor_b);record_cost("separate_bodies",started);return result
	func terrain_move(from: Vector2, to: Vector2, foot: float, time: float) -> Vector2:
		var started:=Time.get_ticks_usec();var result: Vector2=super(from,to,foot,time);record_cost("terrain_move",started);return result
	func platform_motion(point:Vector2,start:float,end:float) -> Vector2:
		var started:=Time.get_ticks_usec();var result: Vector2=super(point,start,end);record_cost("platform_motion",started);return result
	func has_ground_support(point:Vector2,time:float=-1.0) -> bool:
		var started:=Time.get_ticks_usec();var result: bool=super(point,time);record_cost("has_ground_support",started);return result
	func ground_sweep_supported(from: Vector2, to: Vector2, time: float = -1.0) -> bool:
		var started:=Time.get_ticks_usec();var result: bool=super(from,to,time);record_cost("ground_sweep_supported",started);return result
	func damage_candidates(pa: Vector2, ca: Vector2, pb: Vector2, cb: Vector2,   old_path: PackedVector2Array) -> Array[int]:
		var started:=Time.get_ticks_usec();var result: Array[int]=super(pa,ca,pb,cb,old_path);record_cost("damage_candidates",started);return result
	func industrial_sweep_bounds(index: int, start: float, end: float) -> Rect2:
		var started:=Time.get_ticks_usec();var result: Rect2=super(index,start,end);record_cost("industrial_sweep_bounds",started);return result
	func solid_sweep_clear(from: Vector2, to: Vector2, h0: float, h1: float) -> bool:
		var started:=Time.get_ticks_usec();var result: bool=super(from,to,h0,h1);record_cost("solid_sweep_clear",started);return result
	func rope_span(p: Vector2, q: Vector2, rope_a: float, rope_b: float, circles: Array) -> float:
		var started:=Time.get_ticks_usec();var result: float=super(p,q,rope_a,rope_b,circles);record_cost("rope_span",started);return result

func summary(samples: Array) -> Dictionary:
	samples.sort()
	return {"median_usec":samples[samples.size()/2],"p95_usec":samples[int((samples.size()-1)*.95)],"max_usec":samples[-1]}

func place(run,chapter: int, y: float) -> void:
	run.random_seed=false;run.seed_value=8123
	run.level_index=chapter;run.retry();run.state="running";run.clear_input=false
	var found:=false
	for offset in [0,100,-100,200,-200]:
		for x in [-42,-120,80,-200,180]:
			var point:=Vector2(x,y+offset)
			if run.Monsters.safe_spawn(run,point) and run.Monsters.safe_spawn(run,point+Vector2(56,0)):
				run.a.position=point;run.b.position=point+Vector2(56,0);found=true;break
		if found: break
	assert(found,"生产地图中应存在合法观察点")
	run.distance=run.a.position.y;run.elapsed=10
	for gate in run.charge_gates:
		gate.open=gate.receiver.y<run.distance-180;gate.opened_at=0 if gate.open else -1
	run.select_charge_gate();run.rope.reset(run.a.position,run.b.position)

func _initialize() -> void: call_deferred("measure")

func measure() -> void:
	var rows: Array=[]
	for chapter in range(3):
		var run=TimedRun.new();place(run,chapter,9600)
		for frame in range(12):run.step(run.FIXED_STEP)
		run.costs.clear()
		var fixed: Array=[];var planning: Array=[];var buddy=Buddy.new()
		for frame in range(120):
			var start:=Time.get_ticks_usec();run.step(run.FIXED_STEP);fixed.append(Time.get_ticks_usec()-start)
			if frame%2==0:
				start=Time.get_ticks_usec();buddy.think(run,1.0/60,Vector2(0,1));planning.append(Time.get_ticks_usec()-start)
		rows.append({"chapter":chapter,"distance":run.distance,"hazards":run.kinds.size(),"events":run.journey_events.size(),"hash":run.sync_hash(),"state":run.state,"health":run.combat.health.duplicate(),"fixed":summary(fixed),"buddy":summary(planning),"costs":run.costs})
		run.dispose()
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game);game.set_physics_process(false);game.set_process(false)
	var visual: Array=[]
	for chapter in range(3):
		place(game.run,chapter,9600);game.reset_journey_views()
		for frame in range(8):
			game.run.state="running";game.sync_view();await process_frame
		var frames: Array=[];var sections:={}
		for frame in range(60):
			# 手动观察夹具保持运行态，不把隐藏宿主的焦点通知当作暂停场景。
			game.run.state="running"
			game.run.elapsed+=1.0/60;game.run.advance_events(1.0/60)
			var start:=Time.get_ticks_usec();game.sync_view();frames.append(Time.get_ticks_usec()-start)
			for pair in [["events",game.sync_events],["hazards",game.sync_static_hazards],["combat",game.combat_view.sync],["world",game.sync_world]]:
				start=Time.get_ticks_usec();pair[1].call()
				sections[pair[0]]=sections.get(pair[0],0)+Time.get_ticks_usec()-start
			await process_frame
		visual.append({"chapter":chapter,"view":summary(frames),"sections_usec":sections,"event_views":game.event_views.size(),"hazard_views":game.static_views.size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
		var captures:=OS.get_environment("DENSE_CAPTURE_DIR")
		if not captures.is_empty() and DisplayServer.get_name()!="headless":
			DirAccess.make_dir_recursive_absolute(captures)
			game.run.state="running";game.sync_view()
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png(captures+"/chapter-%d.png"%chapter)==OK)
	var report:={"simulation":rows,"visual":visual,"renderer":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"method":"生产场景480米安全观察点；计时含探针开销；视图和模拟分开，非通关或真实输入验收"}
	var path:=OS.get_environment("DENSE_PERFORMANCE_REPORT")
	if path.is_empty():path=OS.get_environment("TEMP")+"/ConjoinedTwins-stutter-profile.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DENSE_PERFORMANCE ",JSON.stringify(report))
	game.queue_free();await process_frame;await create_timer(.15).timeout;quit()
