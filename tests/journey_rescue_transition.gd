extends SceneTree

# 可在 headless 或真实渲染器运行；输入直接进入生产采样口，不发送系统按键。
var failures:=0
var surface_changes:=0
var frame_ms:Array[float]=[]
var cycle_metrics:Array=[]
var previous_frame_usec:=0
var report_dir:=""
func record_frame()->void:
	var now:=Time.get_ticks_usec()
	if previous_frame_usec>0:frame_ms.append((now-previous_frame_usec)/1000.0)
	previous_frame_usec=now
func screenshot(label:String)->void:
	if report_dir.is_empty() or DisplayServer.get_name()=="headless":return
	var capture:=root.get_texture().get_image()
	var visible_samples:=0
	for y in range(1,5):
		for x in range(1,5):
			if capture.get_pixel(capture.get_width()*x/5,capture.get_height()*y/5).v>0.1:visible_samples+=1
	check(visible_samples>0,"%s 截图包含实际画面，不能用全黑帧通过"%label)
	capture.save_png(report_dir.path_join(label+".png"))
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	call_deferred("verify")
func verify()->void:
	Engine.max_fps=60
	report_dir=OS.get_environment("RESCUE_REPORT_DIR")
	var started:=Time.get_ticks_usec()
	var boot=load("res://scenes/journey_boot.tscn").instantiate()
	root.add_child(boot)
	while not is_instance_valid(boot.game) or not boot.game.scene_prepared:await process_frame
	var game=boot.game
	game.set_physics_process(false)
	game.play_mode="local"
	var run=game.run
	# 本检查专测救援及回镜，不让章节开场在救援结束后插入黑场与另一套镜头。
	game.opening_enabled=false
	run.opening_enabled=false
	run.opening_at=run.NO_OPENING
	var cycles:=8
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cycles="):cycles=clampi(int(arg.get_slice("=",1)),1,128)
	for cycle in range(cycles):
		run.retry();game.reset_journey_views();run.state="running"
		var role:=cycle%2
		var side:=1.0 if cycle%4<2 else -1.0
		var start_y:=100.0 if cycle%8<4 else 600.0
		run.a.position=Vector2(side*(run.EDGE-70),start_y)
		run.b.position=Vector2(side*(run.EDGE-30),start_y)
		run.distance=start_y;run.last_support=[run.a.position,run.b.position];run.ground_support=[true,true]
		run.rope.reset(run.a.position,run.b.position)
		for actor in range(2):run.combat.weapons[actor]=run.Combat.gun()
		run.Combat.add_pickup(run,"ammo",Vector2(-side*150,start_y+500))
		var pickup_id:int=run.combat.pickups[-1].id
		while not game.prepare_journey_frame():await process_frame
		game.sync_view()
		var pickup=game.combat_view.pickup_views[pickup_id]
		var rope_mesh:Mesh=game.rope_view.mesh
		surface_changes=0
		var changed:=func():surface_changes+=1
		rope_mesh.changed.connect(changed)
		run.begin_fall(role,Vector2(side*(run.EDGE+12),start_y))
		print("RESCUE_BEGIN cycle=",cycle," role=",role," side=",side," y=",start_y)
		var completed:=false
		previous_frame_usec=0
		for frame in range(360):
			# 无焦点窗口仍可能收到桌面切换通知；恢复测试自己的暂停状态。
			if run.state=="paused":game.command("pause",run.paused_from)
			var period:=4 if cycle%8<4 else 16
			game.input_override={"a":Vector2.ZERO,"b":Vector2.ZERO,"ja":frame%period<2,"jb":frame%period<2,"fire":false,"reload":false,"drop":false}
			game._physics_process(run.FIXED_STEP)
			await process_frame
			record_frame()
			if cycle==0 and frame==30:screenshot("rescue")
			if run.state=="running":completed=true;break
			if run.state=="failed":break
		check(completed,"救援完成 cycle=%d state=%s"%[cycle,run.state])
		if not completed:break
		check(is_instance_valid(pickup) and game.combat_view.pickup_views.get(pickup_id)==pickup,"救援不销毁同局拾取物")
		check(game.rope_view.mesh==rope_mesh and surface_changes==0,"救援全程复用网格表面与拓扑 changed=%d same=%s"%[surface_changes,game.rope_view.mesh==rope_mesh])
		rope_mesh.changed.disconnect(changed)
		game.input_override={"a":Vector2.ZERO,"b":Vector2.ZERO,"ja":false,"jb":false,"fire":true,"reload":false,"drop":false}
		for frame in range(45):
			if run.state=="paused":game.command("pause",run.paused_from)
			game._physics_process(run.FIXED_STEP)
			await process_frame
			record_frame()
		check(game.camera.transform.is_finite(),"救援后镜头保持有效")
		if cycle==0:screenshot("returned")
		cycle_metrics.append({"cycle":cycle,"nodes":get_node_count(),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
		print("RESCUE_DONE cycle=",cycle," nodes=",get_node_count()," objects=",Performance.get_monitor(Performance.OBJECT_COUNT))
	if not report_dir.is_empty():
		frame_ms.sort()
		var metrics:={"cycles":cycle_metrics,"elapsed_seconds":(Time.get_ticks_usec()-started)/1000000.0,"frame_count":frame_ms.size(),"frame_ms_p50":frame_ms[int(frame_ms.size()*.5)],"frame_ms_p95":frame_ms[int(frame_ms.size()*.95)],"frame_ms_max":frame_ms.back(),"cull_threshold":ProjectSettings.get_setting_with_override("rendering/limits/spatial_indexer/threaded_cull_minimum_instances"),"driver":RenderingServer.get_current_rendering_driver_name()}
		var file:=FileAccess.open(report_dir.path_join("metrics.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(metrics,"  "));file.close()
	for player in game.sfx.players:player.stop()
	boot.queue_free()
	for frame in range(4):await process_frame
	await create_timer(.2).timeout
	print("JOURNEY_RESCUE_TRANSITION failures=",failures," cycles=",cycles)
	quit(1 if failures else 0)
