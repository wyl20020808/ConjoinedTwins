extends SceneTree

const Journey=preload("res://scripts/journey_run.gd")
const View=preload("res://scripts/journey_view.gd")

class TimedRun extends Journey:
	var fixed_usec:=0
	var fixed_calls:=0
	var rope_usec:=0
	var rope_calls:=0
	var skip_rope_solver:=false
	var detail:={}
	func record_cost(key: String,start: int) -> void:
		var row:Dictionary=detail.get(key,{"calls":0,"usec":0})
		row.calls+=1;row.usec+=Time.get_ticks_usec()-start;detail[key]=row
	func fixed_step(a_input: Vector2,b_input: Vector2) -> void:
		var start:=Time.get_ticks_usec();super(a_input,b_input)
		fixed_usec+=Time.get_ticks_usec()-start;fixed_calls+=1
	func advance_rope(dt: float) -> void:
		if skip_rope_solver:return
		var start:=Time.get_ticks_usec();super(dt)
		rope_usec+=Time.get_ticks_usec()-start;rope_calls+=1
	func industrial_hits(index: int,start: float,end: float,pa: Vector2,ca: Vector2,pb: Vector2,cb: Vector2,old_heights: Array,old_path: PackedVector2Array,old_z: PackedFloat32Array) -> Dictionary:
		var began:=Time.get_ticks_usec();var result:Dictionary=super(index,start,end,pa,ca,pb,cb,old_heights,old_path,old_z);record_cost("industrial",began);return result
	func surface_at(point:Vector2,time:float,radius:float=0.0)->Dictionary:
		var start:=Time.get_ticks_usec();var result:Dictionary=super(point,time,radius);record_cost("surface",start);return result
	func rope_circles()->Array:
		var start:=Time.get_ticks_usec();var result:Array=super();record_cost("rope_circles",start);return result
	func surface_rope_length(p:Vector2,q:Vector2,h0:float,h1:float)->float:
		var start:=Time.get_ticks_usec();var result:float=super(p,q,h0,h1);record_cost("rope_length",start);return result
	func sweeper_rope_hits(index:int,start:float,end:float,old_path:PackedVector2Array,old_z:PackedFloat32Array)->bool:
		var began:=Time.get_ticks_usec();var result:bool=super(index,start,end,old_path,old_z);record_cost("sweeper_rope",began);return result
	func timed_hazard_hits(index:int,start:float,end:float,from:Vector2,to:Vector2,h0:float,h1:float)->bool:
		var began:=Time.get_ticks_usec();var result:bool=super(index,start,end,from,to,h0,h1);record_cost("timed_body",began);return result
	func solid_sweep_clear(from:Vector2,to:Vector2,h0:float,h1:float)->bool:
		var start:=Time.get_ticks_usec();var result:bool=super(from,to,h0,h1);record_cost("solid_sweep",start);return result
	func charge_path_clear()->bool:
		var start:=Time.get_ticks_usec();var result:bool=super();record_cost("charge_path",start);return result

class FrameView extends View:
	var physics_usec:=0
	var physics_calls:=0
	var view_usec:=0
	var view_calls:=0
	func create_run():return TimedRun.new()
	func _physics_process(delta: float) -> void:
		var start:=Time.get_ticks_usec();super(delta)
		physics_usec+=Time.get_ticks_usec()-start;physics_calls+=1
	func sync_view() -> void:
		var start:=Time.get_ticks_usec();super()
		view_usec+=Time.get_ticks_usec()-start;view_calls+=1

var game
var report:={}
var output:=""

func summary(values: Array) -> Dictionary:
	if values.is_empty():return {}
	values.sort()
	return {"median":values[values.size()/2],"p95":values[int((values.size()-1)*.95)],"max":values[-1]}

func save_report() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))

func _initialize() -> void:call_deferred("measure")

func place() -> void:
	game.set_physics_process(false);game.set_process(false)
	var chapter_text:=OS.get_environment("DENSE_FRAME_CHAPTER")
	var chapter:=1 if chapter_text.is_empty() else int(chapter_text)
	assert(chapter>=0 and chapter<3)
	game.run.random_seed=false;game.run.seed_value=8123;game.run.level_index=chapter;game.run.retry()
	game.run.elapsed=10
	var found:=false
	for offset in [0,100,200,-100,-200,400,600]:
		for x in [-42,-120,80,-200,180]:
			var point:=Vector2(x,9600+offset)
			if game.run.Monsters.safe_spawn(game.run,point) and game.run.Monsters.safe_spawn(game.run,point+Vector2(56,0)):
				game.run.a.position=point;game.run.b.position=point+Vector2(56,0);found=true;break
		if found:break
	assert(found)
	game.run.distance=game.run.a.position.y
	for gate in game.run.charge_gates:
		gate.open=gate.receiver.y<game.run.distance-180;gate.opened_at=0 if gate.open else -1
	game.run.select_charge_gate();game.run.rope.reset(game.run.a.position,game.run.b.position)
	game.run.state="running";game.run.clear_input=false;game.buddy.reset();game.reset_journey_views();game.sync_view()

func measure() -> void:
	output=OS.get_environment("DENSE_FRAME_REPORT");assert(not output.is_empty())
	var cap_text:=OS.get_environment("DENSE_FRAME_CAP")
	Engine.max_fps=0 if cap_text.is_empty() else int(cap_text)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	game=FrameView.new();root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.input_override={"a":Vector2.ZERO,"b":Vector2.ZERO,"ja":false,"jb":false}
	report={"adapter":RenderingServer.get_video_adapter_name(),"vendor":RenderingServer.get_video_adapter_vendor(),"api":RenderingServer.get_video_adapter_api_version(),"driver":RenderingServer.get_current_rendering_driver_name(),"method":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info(),"physics_hz":Engine.physics_ticks_per_second,"max_physics_steps":Engine.max_physics_steps_per_frame,"viewport":str(root.size),"phases":[],"note":"任务独占隐藏窗口；夹具恢复并记录自己游戏的自动失焦暂停；非用户桌面输入或试玩验收"}
	var phases:=OS.get_environment("DENSE_FRAME_PHASES")
	if phases.is_empty():phases="static,full,no_shadows,half_resolution,no_view,physics_only"
	for phase in phases.split(","):
		place()
		game.play_mode="local" if phase in ["full_no_buddy","no_rope"] else "solo"
		game.run.skip_rope_solver=phase=="no_rope"
		root.disable_3d=phase=="physics_only"
		root.scaling_3d_scale=.5 if phase=="half_resolution" else 1.0
		game.canopy_light.shadow_enabled=phase!="no_shadows"
		var running: bool=phase!="static"
		game.set_physics_process(running)
		game.set_process(phase not in ["static","no_view","physics_only"])
		for frame in range(15):
			await process_frame
			if game.run.state=="paused":game.run.pause()
		game.physics_usec=0;game.physics_calls=0;game.view_usec=0;game.view_calls=0
		game.run.fixed_usec=0;game.run.fixed_calls=0
		game.run.rope_usec=0;game.run.rope_calls=0
		game.run.detail.clear()
		var frames: Array=[];var cpu: Array=[];var gpu: Array=[];var setup: Array=[];var monitors: Array=[]
		var start:=Time.get_ticks_usec();var previous:=start;var simulation:float=game.run.elapsed
		var duration:=float(OS.get_environment("DENSE_FRAME_SECONDS"))
		if duration<=0:duration=1.0
		var automatic_pauses:=0
		while frames.size()<60 or Time.get_ticks_usec()-start<duration*1000000:
			await process_frame
			if game.run.state=="paused":
				automatic_pauses+=1;game.run.pause()
			var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			setup.append(RenderingServer.get_frame_setup_time_cpu())
			monitors.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
			if Time.get_ticks_usec()-start>12000000:break
		var seconds:float=(previous-start)/1000000.0
		var row:={"phase":phase,"fps":frames.size()/seconds,"frame_ms":summary(frames),"render_cpu_ms":summary(cpu),"render_gpu_ms":summary(gpu),"render_setup_ms":summary(setup),"physics_monitor_ms":summary(monitors),"physics_cpu_ms_per_second":game.physics_usec/1000.0/seconds,"physics_calls":game.physics_calls,"view_cpu_ms_per_second":game.view_usec/1000.0/seconds,"view_calls":game.view_calls,"fixed_usec_per_call":float(game.run.fixed_usec)/maxi(1,game.run.fixed_calls),"fixed_calls":game.run.fixed_calls,"simulation_seconds":game.run.elapsed-simulation,"wall_seconds":seconds,"state":game.run.state,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()}
		row.rope_cpu_ms_per_second=game.run.rope_usec/1000.0/seconds
		row.rope_usec_per_call=float(game.run.rope_usec)/maxi(1,game.run.rope_calls)
		row.automatic_pauses=automatic_pauses
		row.chapter=game.run.level_index
		row.detail=game.run.detail.duplicate(true)
		row.positions=[str(game.run.a.position),str(game.run.b.position)]
		row.heights=game.run.heights.duplicate()
		row.reason=game.run.reason
		row.rescue=game.run.rescue.duplicate(true)
		row.local_gaps=[]
		for gap in game.run.ground_gaps():
			if absf(gap.get_center().y-game.run.a.position.y)<200:row.local_gaps.append(str(gap))
		report.phases.append(row);save_report();print("DIAGNOSE ",JSON.stringify(row))
		var capture:=OS.get_environment("DENSE_FRAME_CAPTURE")
		if not capture.is_empty():
			game.sync_view();await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png(capture)==OK)
	game.queue_free();await process_frame;await create_timer(.2).timeout;quit()
