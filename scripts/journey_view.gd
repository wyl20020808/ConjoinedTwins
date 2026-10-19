extends "res://scripts/road_demo.gd"

const Journey = preload("res://scripts/journey_run.gd")
const ChunkPlan = preload("res://scripts/journey_chunk_plan.gd")
const AssetQueue = preload("res://scripts/road_asset_queue.gd")
const PreparationTask = preload("res://scripts/preparation_task.gd")
var parallel_chunk_plans := true
var chunk_parallel_peak := 0
var chunk_plan_tasks_started := 0
var chunk_assets = AssetQueue.new()
var chunk_jobs := {}
var scene_prepared := false
var scene_preparation_progress := 0.0
var preparation_peak_usec := 0
var preparation_waits := 0
var chunk_install_count := 0
const CHUNK := 80.0
# 单位为道路单位（20/米）。预热窗口比展示窗口多 40 米，退出窗口再留 20 米迟滞。
const MODEL_AHEAD := 2400.0
const MODEL_PREFETCH := 3200.0
const MODEL_RETAIN := 3600.0
const MODEL_BEHIND := 600.0
const Landscape = preload("res://scripts/journey_landscape.gd")
const TRIPO_BOULDER := "res://assets/journey/tripo_boulder.glb"
const TRIPO_TIMBER := "res://assets/journey/tripo_timber_ram.glb"
var landscape
const Atmosphere = preload("res://scripts/journey_atmosphere.gd")
var atmosphere
const Fx = preload("res://scripts/journey_fx.gd")
var fx
const Buddy=preload("res://scripts/journey_buddy.gd")
var buddy=Buddy.new()
var play_mode:="solo"
var mode_buttons:Array[Button]=[]
var online_row:HBoxContainer
var input_override:Dictionary={}
var web_test_mode:=false
var web_verify:=false
var verify_clock:=1.0
var last_fire_sent:=false
const WEB_BUILD:="journey-minimal-hud-damage-20261017"
var world_chunks := {}
var event_views := {}
var gate_views := {}
var static_views := {}
var floor_stamp := ""
var built_chapter := -1
var built_seed := -1
var built_training := false
var journey_hint: Label
var credits_panel: PanelContainer
var canopy_light: DirectionalLight3D
var world_environment: Environment
var ambient: AudioStreamPlayer
var ambience_region := ""
var ambience_streams := {}
var forest_birds:AudioStreamPlayer
var sound_events := {}
var sound_clock := 0.0
const CombatView = preload("res://scripts/journey_combat_view.gd")
@export var training_entry := false
var combat_view: Node3D
var combat_status: Label
var combat_health: ProgressBar
var partner_health: ProgressBar
var partner_status: Label
var weapon_ammo: Label
var weapon_detail: Label
var weapon_icon: TextureRect
var health_panel: PanelContainer
var weapon_panel: PanelContainer
var training_button: Button
var restart_button: Button
var fire_blocked := true
var reload_requested := false
var drop_requested := false
var frame_costs := {}
var view_pending:=false
var journey_camera_returning:=false

func create_run():
	# 旅程直接建立自己的模拟，避免先生成一份马上丢弃的旧道路关卡。
	return Journey.new(true)

func model_visible(y: float) -> bool:
	return y-run.distance >= -MODEL_BEHIND and y-run.distance < MODEL_AHEAD

func model_preload(y: float) -> bool:
	return y-run.distance >= -MODEL_BEHIND and y-run.distance < MODEL_PREFETCH

func model_resident(y: float) -> bool:
	return y-run.distance >= -MODEL_BEHIND-200 and y-run.distance < MODEL_RETAIN

func _ready() -> void:
	# 本地也限制长帧追赶，避免补算持续挤占输入和绘制。
	Engine.max_physics_steps_per_frame=3
	if OS.has_feature("web"):web_verify=bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('verify')",true))
	ThemeDB.fallback_font=preload("res://assets/fonts/web_ui_font.tres")
	finish_view.free()
	charge_gate_view.free()
	run.solo_control=true
	run.external_companion=not training_entry
	if training_entry:
		run.combat_trial=true
		run.retry()
	run.state="start"
	add_child(road)
	build_lighting()
	landscape=Landscape.new(self)
	if OS.has_feature("web"):
		apply_web_quality()
		get_viewport().size_changed.connect(apply_web_quality)
	elif landscape.mobile:
		get_viewport().scaling_3d_scale=.75
		get_viewport().msaa_3d=Viewport.MSAA_DISABLED
	world_environment=get_children().filter(func(node): return node is WorldEnvironment)[0].environment
	world_environment.fog_light_color=Color("849d8b")
	world_environment.fog_density=0.003
	world_environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color=Color("b8c5d0")
	world_environment.ambient_light_energy=0.85
	world_environment.sky.sky_material.energy_multiplier=0.12
	for node in get_children():
		if node is DirectionalLight3D: canopy_light=node
	canopy_light.directional_shadow_max_distance=65 if landscape.mobile else 110
	if OS.has_feature("web"):
		# 网页保留人物接触阴影，避免整片森林重复绘制动态阴影。
		canopy_light.shadow_enabled=false
		camera.far=200.0
	canopy_light.rotation_degrees=Vector3(-48,120,0)
	canopy_light.light_color=Color("fff1d4")
	canopy_light.light_energy=1.8
	camera.position=Vector3(0,11.5,22)
	camera.look_at(Vector3(0,1.2,-22))
	camera_home=camera.transform
	atmosphere=Atmosphere.new(self,world_environment,canopy_light,camera)
	fx=Fx.new();add_child(fx)
	if incremental_loading:
		set_physics_process(false)
		set_process_unhandled_key_input(false)
		await get_tree().process_frame
		await build_robots()
	else: build_robots()
	sfx=Sfx.new()
	add_child(sfx)
	net=NetClient.new()
	add_child(net)
	net.status_changed.connect(journey_net_status)
	net.match_started.connect(start_online_match)
	net.match_stopped.connect(stop_online_match)
	build_journey_ui()
	combat_view=CombatView.new()
	combat_view.game=self
	add_child(combat_view)
	build_ambience()
	if incremental_loading:
		while not prepare_journey_frame(): await get_tree().process_frame
	if OS.has_feature("web"):await warm_web_landscape()
	sync_view()
	scene_prepared = true
	set_physics_process(true)
	set_process_unhandled_key_input(true)

func warm_web_landscape()->void:
	# 首次绘制的 WebGL 上传/着色器编译放在加载页，避免走入森林时同步阻塞。
	var paths:Array=[]
	for kind in ["natural_oak_7","natural_oak_17","natural_birch","natural_oak_7_lod","natural_oak_17_lod","natural_birch_lod","grass","fern","shrub","woodpile"]:
		paths.append("res://assets/landscape/%s.glb"%kind)
	chunk_assets.request(paths)
	while not chunk_assets.ready(paths):
		chunk_assets.poll(Time.get_ticks_usec()+Run.PRELOAD_SLICE_USEC)
		if not chunk_assets.error.is_empty():return
		await get_tree().process_frame
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(32,32)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var eye:=Camera3D.new()
	viewport.add_child(eye)
	eye.projection=Camera3D.PROJECTION_ORTHOGONAL;eye.size=80;eye.far=200
	eye.position=Vector3(0,20,80);eye.look_at(Vector3(0,20,0));eye.current=true
	var environment:=WorldEnvironment.new();environment.environment=world_environment
	viewport.add_child(environment)
	for node in get_children():
		if node is DirectionalLight3D:viewport.add_child(node.duplicate())
	for path:String in paths:
		var sample:=Node3D.new();viewport.add_child(sample)
		landscape.batch(sample,path,[Transform3D.IDENTITY],180)
		# 等渲染提交后再释放；每个资源分帧准备。
		await RenderingServer.frame_post_draw
		sample.queue_free()
	viewport.queue_free()

func apply_web_quality() -> void:
	# 只缩放 3D，文字与触屏控件仍按浏览器原始分辨率绘制。
	Engine.max_fps=60
	# 一次长帧后最多补算三帧，避免八帧追赶反过来持续堵住浏览器输入与绘制。
	Engine.max_physics_steps_per_frame=3
	var size:=get_viewport().get_visible_rect().size
	get_viewport().scaling_3d_scale=minf(1.0,minf(960.0/maxf(size.x,1.0),540.0/maxf(size.y,1.0)))
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED

func _exit_tree() -> void:
	if is_instance_valid(net):net.disconnect_from()
	chunk_assets.dispose()
	for job in chunk_jobs.values():
		if job.task!=null: job.task.dispose()
	if is_instance_valid(ambient):
		ambient.stop()
		ambient.stream=null
	if is_instance_valid(forest_birds):
		forest_birds.stop();forest_birds.stream=null
	ambience_streams.clear()
	if landscape!=null:landscape.game=null
	run.dispose()

func ground_material(theme: String) -> Material:
	if materials.has("journey_ground_"+theme): return materials["journey_ground_"+theme]
	var village:=theme in ["village","facility","ruins"]
	var forest:=ResourceLoader.exists("res://assets/journey/forest_leaves_02_diff.jpg")
	var prefix:="res://assets/env/monastery_stone_floor" if village or not forest else "res://assets/journey/forest_leaves_02"
	if theme in ["mine","river"]:prefix="res://assets/env/rock_boulder_dry"
	var path:=prefix+"_diff.jpg"
	var result:=material("journey_ground_"+theme,Color("b8b7a2") if village else Color("acb6a0"))
	result.albedo_texture=load(path)
	result.uv1_triplanar=true
	result.uv1_scale=Vector3.ONE*0.3
	if ResourceLoader.exists(prefix+"_nor.jpg"):
		result.normal_enabled=true
		result.normal_texture=load(prefix+"_nor.jpg")
	if ResourceLoader.exists(prefix+"_rough.jpg"): result.roughness_texture=load(prefix+"_rough.jpg")
	result.roughness=0.95
	return result

func subtract_floor(pieces: Array,cut: Rect2) -> Array:
	var result:Array=[]
	for piece:Rect2 in pieces:
		if not piece.intersects(cut):
			result.append(piece)
			continue
		var hit:=piece.intersection(cut)
		for rect in [Rect2(piece.position,Vector2(hit.position.x-piece.position.x,piece.size.y)),Rect2(Vector2(hit.end.x,piece.position.y),Vector2(piece.end.x-hit.end.x,piece.size.y)),Rect2(Vector2(hit.position.x,piece.position.y),Vector2(hit.size.x,hit.position.y-piece.position.y)),Rect2(Vector2(hit.position.x,hit.end.y),Vector2(hit.size.x,piece.end.y-hit.end.y))]:
			if rect.size.x>0.01 and rect.size.y>0.01: result.append(rect)
	return result

func rebuild_floor(chunk: Node3D,number: int) -> void:
	# 坍塌只使相交区块失效；其他区块继续复用原节点和网格。
	var y0:=number*CHUNK*SCALE
	var bounds := Rect2(-Run.EDGE,y0,Run.EDGE*2,CHUNK*SCALE)
	var gaps: Array[Rect2] = []
	var cracks: Array[Rect2] = []
	for gap in run.ground_gaps():
		if bounds.intersects(gap): gaps.append(gap)
	for index in range(run.kinds.size()):
		if run.kinds[index]!="collapse": continue
		var rect: Rect2=run.obstacles[index]
		if rect.position.y>=y0 and rect.position.y<bounds.end.y and run.hazard_sample(index,run.elapsed).stage in ["crack","grace"]: cracks.append(rect)
	var signature := [gaps,cracks,run.theme_at(y0)]
	if chunk.get_meta("floor_signature",[])==signature: return
	chunk.set_meta("floor_signature",signature)
	var old:=chunk.get_node_or_null("Floor")
	if old:
		chunk.remove_child(old)
		old.queue_free()
	var floor_node:=Node3D.new()
	floor_node.name="Floor"
	chunk.add_child(floor_node)
	var pieces:Array=[Rect2(-Run.EDGE,y0,Run.EDGE*2,CHUNK*SCALE)]
	for gap:Rect2 in gaps: pieces=subtract_floor(pieces,gap)
	var theme: String=run.theme_at(y0)
	landscape.ground(floor_node,pieces,run.level_index,landscape.road_material(run.level_index,theme,run.level_index==0 and not run.combat_trial))
	landscape.surface_details(floor_node,pieces,number,run.level_index,theme,gaps)
	for i in range(run.kinds.size()):
		if run.kinds[i]!="collapse": continue
		var rect:Rect2=run.obstacles[i]
		if rect.position.y<y0 or rect.position.y>=y0+CHUNK*SCALE: continue
		var sample:Dictionary=run.hazard_sample(i,run.elapsed)
		if sample.stage not in ["crack","grace"]: continue
		for k in range(6):
			var crack:=box(floor_node,Vector3((rect.position.x+k*rect.size.x/6)/SCALE,0.025,-rect.get_center().y/SCALE),Vector3(0.09,0.025,rect.size.y/SCALE),material("crack",Color("351f16")))
			crack.rotation.y=0.17 if k%2==0 else -0.17

func add_sign(parent: Node3D,text: String,position: Vector3,size: int=32) -> Label3D:
	var sign:=Label3D.new()
	sign.text=text
	sign.position=position
	sign.font_size=size
	sign.pixel_size=0.018
	sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate=Color("fff1d0")
	parent.add_child(sign)
	return sign

func asset(parent: Node3D,name: String,pos: Vector3,height: float,yaw: float=0.0) -> Node3D:
	var path:="res://assets/journey/"+name+".glb"
	if not ResourceLoader.exists(path): return null
	if name=="drawbridge":
		var bridge:Node3D=load(path).instantiate()
		parent.add_child(bridge)
		bridge.position=pos
		bridge.rotation.y=yaw
		bridge.scale.z=1.325
		return bridge
	return model(path,parent,pos,height,yaw,20)

func build_chunk(number: int) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "World_%d"%number
	road.add_child(chunk)
	for item in ChunkPlan.make(number,run.level_index,chunk_chapter(number),Run.EDGE): install_chunk_item(chunk,item)
	rebuild_floor(chunk,number)
	return chunk

func install_chunk_item(chunk: Node3D, item: Array) -> void:
	match item[0]:
		"landscape_terrain":landscape.sides(chunk,item[1],item[2],item[3])
		"landscape_batch":
			var path:="res://assets/landscape/%s.glb"%item[1]
			if item[1] in ["natural_oak_7","natural_oak_17","natural_birch"]:
				var split:=45.0 if landscape.mobile or OS.has_feature("web") else 70.0
				landscape.batch(chunk,path,item[2],split)
				landscape.batch(chunk,"res://assets/landscape/%s_lod.glb"%item[1],item[2],220,split)
			else:landscape.batch(chunk,path,item[2],110 if landscape.mobile or OS.has_feature("web") else 170)
		"landscape_rock":
			var cliff:Material=tex_material("cliff_face","rock_face_03",.11,Color("a89a90"))
			var mesh:Mesh=rock_mesh("ridge_spire",44,8,2.8,70,.2) if item[3] else rock_mesh("ridge_buttress",60,3.6,1.8,24,.24)
			rock(chunk,mesh,cliff,item[1],item[2],item[4])
		"land":
			var surface:Material=landscape.terrain if item[3] in ["village","farm"] else material("land_"+item[3],Color("48513b") if item[4] else Color("77765b"))
			box(chunk,item[1],item[2],surface)
		"water": box(chunk,item[1],item[2],material("water",Color("345f67")))
		"model":
			var node := model("res://assets/decor/%s.glb"%item[1],chunk,item[2],item[3],item[4],item[5])
			if item.size()>6 and node:
				node.set_meta("wind",item[6])
				var moving:Array=chunk.get_meta("wind_nodes",[]);moving.append(node);chunk.set_meta("wind_nodes",moving)
		"rock": rock(chunk,rock_mesh("journey_rock_%d"%item[1],item[1]+31,3,1.8,8,0.5),ground_material("ruins"),item[2],item[3])
		"asset": asset(chunk,item[1],item[2],item[3],item[4])
		"building": model("res://assets/industrial/building-k.glb",chunk,item[1],14,item[2],15)
		"farm": box(chunk,item[1],Vector3(12,0.1,1.2),material("farmland",Color("51412c")))
		"sign": add_sign(chunk,item[1],item[2],38)

func prepare_journey_frame() -> bool:
	var started := Time.get_ticks_usec()
	var deadline := started + Run.PRELOAD_SLICE_USEC
	sync_world()
	var current := int(run.distance/SCALE/CHUNK)
	for number in range(maxi(-1,current-1),current+4):
		if number*CHUNK*SCALE>run.finish_distance()+400 or world_chunks.has(number): continue
		if not chunk_jobs.has(number):
			chunk_jobs[number] = {"items":null,"cursor":0,"node":null,"paths":[],"task":null}
	var active := 0
	for job in chunk_jobs.values():
		if job.task!=null and not job.task.done: active+=1
	for number in chunk_jobs:
		var job: Dictionary=chunk_jobs[number]
		if job.items!=null: continue
		if job.task!=null:
			if not job.task.done: continue
			job.items=job.task.result
			job.task.dispose()
			job.task=null
		elif parallel_chunk_plans and run.supports_background_generation():
			if active>=2: continue
			job.task=PreparationTask.new(ChunkPlan.make.bind(number,run.level_index,chunk_chapter(number).duplicate(true),Run.EDGE))
			chunk_plan_tasks_started+=1
			active+=1
			continue
		else:
			if Time.get_ticks_usec()>=deadline: break
			job.items=ChunkPlan.make(number,run.level_index,chunk_chapter(number),Run.EDGE)
		job.paths=ChunkPlan.paths(job.items)
		chunk_assets.request(job.paths)
	chunk_parallel_peak=maxi(chunk_parallel_peak,active)
	var retained:Array=[]
	for chunk in world_chunks.values():retained.append_array(chunk.get_meta("asset_paths",[]))
	for job in chunk_jobs.values():retained.append_array(job.paths)
	# 动态攻击与机关的资源仅在当前邻域保留，不随章节永久累积。
	for event in run.journey_events:
		if not model_resident(event.y):continue
		match event.kind:
			"tree":retained.append("res://assets/landscape/oak_7.glb")
			"boar":retained.append("res://assets/journey/boar.glb")
			"cart":retained.append("res://assets/journey/cart.glb")
			"swing":retained.append_array(["res://assets/journey/waterwheel.glb","res://assets/journey/wood_planks_diff.jpg"])
		if event.kind in ["cart","stone"]:retained.append("res://assets/journey/villager_actions.glb")
		if event.kind=="monster" and not CombatView.EnemyView.model_path(event.archetype).is_empty():retained.append(CombatView.EnemyView.model_path(event.archetype))
	for gate in run.charge_gates:
		if model_resident(gate.receiver.y):retained.append_array(["res://assets/journey/gate.glb","res://assets/journey/waterwheel.glb","res://assets/journey/drawbridge.glb"])
	retained.append_array(chunk_assets.pending);retained.append_array(chunk_assets.active)
	var hazard_assets:Array=[]
	for index in visual_hazard_candidates():
		for path in hazard_asset_paths(index):
			if not hazard_assets.has(path):hazard_assets.append(path)
	retained.append_array(hazard_assets);chunk_assets.request(hazard_assets)
	chunk_assets.retain(retained)
	chunk_assets.poll(deadline)
	var events_ready := prepare_event_views(deadline)
	for number in chunk_jobs.keys():
		if Time.get_ticks_usec()>=deadline: break
		var job: Dictionary = chunk_jobs[number]
		if job.items==null: continue
		chunk_assets.request(job.paths)
		if not chunk_assets.ready(job.paths): continue
		if job.node==null:
			job.node=Node3D.new()
			job.node.name="World_%d"%number
			job.node.set_meta("asset_paths",job.paths)
			job.node.hide()
			road.add_child(job.node)
		while job.cursor<job.items.size() and Time.get_ticks_usec()<deadline:
			install_chunk_item(job.node,job.items[job.cursor])
			job.cursor+=1
		if job.cursor==job.items.size() and Time.get_ticks_usec()<deadline:
			rebuild_floor(job.node,number)
			world_chunks[number]=job.node
			job.node.visible=number<=current+3
			chunk_jobs.erase(number)
			chunk_install_count+=1
	var ready := events_ready and prepare_hazard_views(deadline)
	var completed := 0
	var required := 0
	for number in range(maxi(-1,current-1),current+4):
		if number*CHUNK*SCALE>run.finish_distance()+400: continue
		required+=1
		if world_chunks.has(number): completed+=1
		else: ready=false
	scene_preparation_progress=float(completed)/maxi(1,required)
	preparation_peak_usec=maxi(preparation_peak_usec,Time.get_ticks_usec()-started)
	if not chunk_assets.error.is_empty():
		journey_hint.text="场景资源读取失败，请刷新网页重试："+chunk_assets.error.get_file()
	if not ready: preparation_waits+=1
	return ready

func prepare_event_views(deadline: int) -> bool:
	var ready := true
	for event in run.journey_events:
		if not model_preload(event.y) or event_views.has(event.id): continue
		var paths: Array=[]
		match event.kind:
			"tree": paths.append("res://assets/landscape/oak_7.glb")
			"boar": paths.append("res://assets/journey/boar.glb")
			"cart": paths.append("res://assets/journey/cart.glb")
			"swing": paths.append_array(["res://assets/journey/waterwheel.glb","res://assets/journey/wood_planks_diff.jpg"])
		if event.kind in ["stone","cart"]: paths.append("res://assets/journey/villager_actions.glb")
		if event.kind=="monster" and not CombatView.EnemyView.model_path(event.archetype).is_empty():paths.append(CombatView.EnemyView.model_path(event.archetype))
		chunk_assets.request(paths)
		if chunk_assets.ready(paths) and Time.get_ticks_usec()<deadline:
			event_views[event.id]=build_event(event)
			event_views[event.id].hide()
		elif model_visible(event.y): ready=false
	for gate in run.charge_gates:
		if not model_preload(gate.receiver.y) or gate_views.has(gate.id): continue
		var paths: Array=["res://assets/journey/gate.glb", "res://assets/journey/%s.glb"%("waterwheel" if gate.id=="waterwheel" else "drawbridge")]
		chunk_assets.request(paths)
		if chunk_assets.ready(paths) and Time.get_ticks_usec()<deadline:
			gate_views[gate.id]=build_gate(gate)
			gate_views[gate.id].hide()
		elif model_visible(gate.receiver.y): ready=false
	return ready

func sync_world() -> void:
	if built_chapter!=run.level_index or built_training!=run.combat_trial or built_seed!=run.seed_value:
		for chunk in world_chunks.values(): chunk.queue_free()
		world_chunks.clear()
		for job in chunk_jobs.values():
			if job.task!=null: job.task.dispose()
			if is_instance_valid(job.node): job.node.queue_free()
		chunk_jobs.clear()
		for view in event_views.values(): view.queue_free()
		event_views.clear()
		for view in gate_views.values(): view.queue_free()
		gate_views.clear()
		built_chapter=run.level_index
		built_seed=run.seed_value
		built_training=run.combat_trial
		floor_stamp=""
		for view in static_views.values():view.queue_free()
		static_views.clear()
	var current:=int(run.distance/SCALE/CHUNK)
	for number in range(maxi(-1,current-1),current+4):
		if number*CHUNK*SCALE>run.finish_distance()+400: continue
		if not world_chunks.has(number) and not incremental_loading: world_chunks[number]=build_chunk(number)
	for number in world_chunks.keys():
		if number<current-1 or number>current+(5 if incremental_loading else 3):
			world_chunks[number].queue_free()
			world_chunks.erase(number)
	for number in world_chunks: world_chunks[number].visible=number<=current+3
	for number in chunk_jobs.keys():
		if number<current-1 or number>current+5:
			if chunk_jobs[number].task!=null: chunk_jobs[number].task.dispose()
			if is_instance_valid(chunk_jobs[number].node): chunk_jobs[number].node.queue_free()
			chunk_jobs.erase(number)
	var stamp:="%d:"%run.revision
	for i in range(run.kinds.size()):
		if run.kinds[i]=="collapse": stamp+=str(run.hazard_sample(i,run.elapsed).stage)
	if floor_stamp!=stamp:
		for number in world_chunks: rebuild_floor(world_chunks[number],number)
		floor_stamp=stamp

func build_event(event: Dictionary) -> Node3D:
	var root:=Node3D.new()
	road.add_child(root)
	root.set_meta("id",event.id)
	var kind:String=event.kind
	var body:=Node3D.new()
	body.name="Body"
	root.add_child(body)
	if kind=="tree": landscape.batch(body,"res://assets/landscape/oak_7.glb",[Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.8),Vector3.ZERO)],240)
	elif kind=="boar":
		var boar:=asset(body,"boar",Vector3.ZERO,1.7,PI)
		if boar:
			var player:=animation_player(boar)
			if player:
				for clip in player.get_animation_list():
					if "Charge" in clip: player.play(clip)
	elif kind in ["stone","monster"]:
		if kind=="monster": CombatView.EnemyView.make_monster(self,root,event.archetype)
		var ball:=MeshInstance3D.new()
		ball.mesh=SphereMesh.new()
		ball.scale=Vector3.ONE*(.65 if kind=="monster" else 1.2)
		ball.material_override=ground_material("ruins")
		body.add_child(ball)
		if kind=="monster" and event.archetype=="archer":
			ball.hide()
			box(body,Vector3.ZERO,Vector3(.08,.08,1.2),material("arrow_wood",Color("b7a176")))
			box(body,Vector3(0,0,.65),Vector3(.24,.1,.3),material("arrow_tip",Color("bec8c8")))
	elif kind=="cart": asset(body,"cart",Vector3.ZERO,3.2,PI/2)
	else:
		var wood:=material("swing_wood",Color("9c805c"))
		wood.albedo_texture=load("res://assets/journey/wood_planks_diff.jpg")
		wood.uv1_triplanar=true
		wood.uv1_scale=Vector3.ONE*0.5
		var log:=cylinder(body,Vector3(0,2,0),2,4,wood)
		log.rotation.z=PI/2
		var arm:=cylinder(root,Vector3(0,6,0),0.18,8,wood)
		arm.name="SwingArm"
		if run.theme_at(event.y) in ["village","river"]:asset(root,"waterwheel",Vector3(19,0,0),7,PI/2)
		else:
			for side in [-1,1]:cylinder(root,Vector3(side*12,5,0),.24,10,wood)
			var beam:=cylinder(root,Vector3(0,10,0),.3,24,wood);beam.rotation.z=PI/2
	if kind in ["cart","stone"]:
		var actor:=model("res://assets/journey/villager_actions.glb",root,Vector3(event.side*18,0,0),3.0,-event.side*PI/2)
		actor.name="Villager"
		var player:=animation_player(actor)
		if player:
			for clip in player.get_animation_list():
				if clip.ends_with("Idle"): player.play(clip);break
	var warning:=box(root,Vector3.ZERO,Vector3(event.rect.size.x/SCALE,0.035,2.5),material("danger_warning",Color(1,0.55,0.08,0.38),0.2))
	warning.name="Warning"
	warning.material_override.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	add_sign(root,run.EVENT_NAMES[kind],Vector3(0,5,0),24).name="Hint"
	return root

func sync_events() -> void:
	for event in run.journey_events:
		var near:bool=model_visible(event.y)
		if not near:
			if event_views.has(event.id):
				if incremental_loading and model_resident(event.y): event_views[event.id].hide()
				else:
					event_views[event.id].queue_free()
					event_views.erase(event.id)
			continue
		if not event_views.has(event.id):
			if incremental_loading: continue
			event_views[event.id]=build_event(event)
		var view:Node3D=event_views[event.id]
		view.show()
		view.position=Vector3(0,0,-event.y/SCALE)
		var body:Node3D=view.get_node("Body")
		var rect:Rect2=event.sample
		body.position=Vector3(rect.get_center().x/SCALE,event.bottom/SCALE,-(rect.get_center().y-event.y)/SCALE)
		body.visible=event.phase!="spent"
		if event.kind=="tree":
			# 树根位于倒伏范围的一端，最终树干与实心碰撞矩形对齐。
			var age:float=run.elapsed-event.trigger
			var fall:float=clampf((age-2.8)/0.65,0,1) if event.trigger>=0 else 0.0
			body.position.x=event.rect.get_center().x/SCALE-event.side*5.5
			body.rotation.z=-event.side*fall*PI/2
			if event.phase=="warning": body.rotation.z=sin(run.elapsed*14)*0.025
		elif event.kind=="swing":
			var pivot:=Vector3(0,10,0)
			var tip:=body.position+Vector3(0,2,0)
			var arm:MeshInstance3D=view.get_node("SwingArm")
			arm.position=(pivot+tip)*0.5
			arm.quaternion=Quaternion(Vector3.UP,(tip-pivot).normalized())
			arm.scale.y=pivot.distance_to(tip)/arm.mesh.height
			sample_animation(view,"WheelTurn",run.elapsed)
		elif event.kind=="boar":
			sample_animation(body,"Charge",run.elapsed if event.phase=="active" else 0)
			body.position.y+=absf(sin(run.elapsed*18))*0.07 if event.phase=="active" else 0.0
		if event.kind=="cart": sample_animation(body,"WheelTurn",maxf(0,run.elapsed-event.trigger-2.8)*2.0)
		var warning:Node3D=view.get_node("Warning")
		warning.visible=event.phase in ["warning","falling"]
		warning.position.x=event.locked_x/SCALE if event.kind in ["stone","monster"] else event.rect.get_center().x/SCALE
		if event.kind=="monster":
			warning.position.z=-(event.landing.y-event.y)/SCALE
			if event.archetype in ["archer","dasher","wolf"]:
				var data:Dictionary=run.Monsters.profile(event)
				var length:float=data.speed*data.active/SCALE
				var center:Vector2=event.launch+event.attack_direction*length*SCALE/2
				warning.position=Vector3(center.x/SCALE,.04+event.get("ground_height",0.0)/SCALE,-(center.y-event.y)/SCALE)
				warning.rotation.y=atan2(event.attack_direction.x,-event.attack_direction.y)
				warning.scale=Vector3(.32 if event.archetype=="archer" else 1.0,1,length/2.5)
				body.rotation.y=warning.rotation.y
		view.get_node("Hint").visible=event.phase=="warning"
		if view.has_node("Villager"):
			var actor:Node3D=view.get_node("Villager")
			var age:float=maxf(0,run.elapsed-event.trigger) if event.trigger>=0 else 0.0
			sample_animation(actor,"Throw" if event.kind=="stone" else "Push",age if event.phase in ["warning","active"] else 0)
			if event.kind=="cart" and event.phase=="active":
				actor.position.x=body.position.x-event.side*3.5
			else:actor.position.x=-event.side*25.5 if event.kind=="cart" else event.side*18

		if event.phase=="warning" and not sound_events.has(event.id):
			sound_events[event.id]=true
			sfx.play("warning",-8.0,0.75 if event.kind=="boar" else 1.0)

func build_gate(gate: Dictionary) -> Node3D:
	var root:=Node3D.new()
	road.add_child(root)
	var door:=Node3D.new()
	door.name="Door"
	root.add_child(door)
	asset(door,"gate",Vector3.ZERO,5.5)
	# 碰撞是全宽门，外观栅栏同样封住完整道路。
	for side in [-1,1]:
		var barrier:=box(door,Vector3(side*10,2.4,0),Vector3(12,4.8,0.4),material("gatewood",Color("6d5033")))
		barrier.name="SideBarrier%d"%side
	for side in ["left","right"]:
		var rect:Rect2=gate[side]
		var center:Vector2=rect.get_center()
		var plate:=box(root,Vector3(center.x/SCALE,0.045,-(center.y-gate.door.position.y)/SCALE),Vector3(rect.size.x/SCALE,0.08,rect.size.y/SCALE),material("plate_"+side,Color("4baba0") if side=="left" else Color("d8a45c"),0.25))
		plate.name=side
	add_sign(root,gate.title,Vector3(0,6,0),32)
	if gate.id=="waterwheel": asset(root,"waterwheel",Vector3(19,0,0),9,PI/2)
	elif "bridge" in gate.id:
		asset(root,"drawbridge",Vector3(0,-0.1,-9),0.8)
	return root

func sync_gates() -> void:
	for gate in run.charge_gates:
		if not model_visible(gate.receiver.y):
			if gate_views.has(gate.id):
				if model_resident(gate.receiver.y):gate_views[gate.id].hide()
				else:gate_views[gate.id].queue_free();gate_views.erase(gate.id)
			continue
		if not gate_views.has(gate.id):
			if incremental_loading: continue
			gate_views[gate.id]=build_gate(gate)
		var view:Node3D=gate_views[gate.id]
		view.show()
		sample_animation(view,"BridgeLower",clampf((run.elapsed-gate.opened_at)/0.6,0,1) if gate.open else 0)
		if gate.id=="waterwheel":sample_animation(view,"WheelTurn",run.elapsed)
		view.position=Vector3(0,0,-gate.door.position.y/SCALE)
		var opening:float=clampf((run.elapsed-gate.opened_at)/0.8,0,1) if gate.open else 0
		sample_animation(view.get_node("Door"),"GateOpen",opening)
		for side in [-1,1]:view.get_node("Door/SideBarrier%d"%side).position.y=2.4+opening*6.5
		for side in ["left","right"]:
			view.get_node(side).visible=not gate.open
	# 终点固定在世界中，双方都到达才结算。
	if not model_resident(run.finish_distance()):
		if road.has_node("JourneyFinish"):road.get_node("JourneyFinish").queue_free()
		return
	if not road.has_node("JourneyFinish"):
		var end:=Node3D.new()
		end.name="JourneyFinish"
		road.add_child(end)
		asset(end,"gate",Vector3.ZERO,6)
		add_sign(end,"共同抵达 · 前方是下一段旅程",Vector3(0,7,0),36)
	road.get_node("JourneyFinish").position.z=-run.finish_distance()/SCALE

func build_journey_ui() -> void:
	var canvas:=CanvasLayer.new()
	canvas.name="JourneyCanvas"
	add_child(canvas)
	health_panel=hud_panel(canvas)
	var column:=VBoxContainer.new()
	column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation",5)
	health_panel.add_child(column)
	hud=label("",18)
	column.add_child(hud)
	combat_health=health_bar(Color("9cdeb9"),12)
	column.add_child(combat_health)
	partner_status=label("",15,Color("e4c7a7"))
	column.add_child(partner_status)
	partner_health=health_bar(Color("e4b883"),6)
	column.add_child(partner_health)
	weapon_panel=hud_panel(canvas)
	var weapon_column:=VBoxContainer.new()
	weapon_column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	weapon_column.add_theme_constant_override("separation",2)
	weapon_panel.add_child(weapon_column)
	combat_status=label("",18)
	weapon_column.add_child(combat_status)
	weapon_icon=TextureRect.new()
	weapon_icon.texture=preload("res://assets/ui/smg.svg")
	weapon_icon.custom_minimum_size=Vector2(108,40)
	weapon_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	weapon_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon_icon.size_flags_horizontal=Control.SIZE_SHRINK_END
	weapon_icon.tooltip_text="冲锋枪"
	weapon_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	weapon_column.add_child(weapon_icon)
	weapon_ammo=label("",30)
	weapon_column.add_child(weapon_ammo)
	weapon_detail=label("",15,Color("e4c7a7"))
	weapon_column.add_child(weapon_detail)
	for text_label in [combat_status,weapon_ammo,weapon_detail]:
		text_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	journey_hint=label("",19,Color("ffe2a0"))
	journey_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	journey_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	journey_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(journey_hint)
	for text_label in [hud,partner_status,combat_status,weapon_ammo,weapon_detail,journey_hint]:
		text_label.add_theme_color_override("font_outline_color",Color(0.06,0.09,0.07,0.9))
		text_label.add_theme_constant_override("outline_size",4)
	touch_device=DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	touch=TouchControls.new()
	touch.combat_buttons=true
	canvas.add_child(touch)
	pause_button=Button.new()
	for state_name in ["normal","hover","pressed","disabled"]:
		pause_button.add_theme_stylebox_override(state_name,StyleBoxEmpty.new())
	pause_button.tooltip_text="暂停 · Esc"
	pause_button.draw.connect(func():
		for x in [14.0,24.0]:
			pause_button.draw_rect(Rect2(x-1,11,6,18),Color("24332b"))
			pause_button.draw_rect(Rect2(x,12,4,16),Color("eff4ec")))
	pause_button.pressed.connect(func():
		command("pause")
		clear_controls())
	canvas.add_child(pause_button)
	build_rescue_hud(canvas)
	panel=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position=Vector2(240,170)
	panel.size=Vector2(800,360)
	canvas.add_child(panel)
	var inner:=VBoxContainer.new()
	inner.add_theme_constant_override("separation",10)
	panel.add_child(inner)
	title=label("",32)
	inner.add_child(title)
	subtitle=label("",17)
	subtitle.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(subtitle)
	primary=Button.new()
	primary.custom_minimum_size=Vector2(0,52)
	primary.pressed.connect(journey_primary)
	inner.add_child(primary)
	training_button=Button.new()
	training_button.text="战斗训练 · 持枪步行约 90 秒"
	training_button.custom_minimum_size=Vector2(0,46)
	training_button.pressed.connect(func():
		run.combat_trial=not run.combat_trial
		run.new_campaign()
		reset_journey_views())
	inner.add_child(training_button)
	restart_button=Button.new()
	restart_button.text="重新开始本关"
	restart_button.custom_minimum_size=Vector2(0,42)
	restart_button.pressed.connect(func():
		command("retry"))
	inner.add_child(restart_button)
	touch.blockers.assign([panel,pause_button])
	var modes:=HBoxContainer.new()
	inner.add_child(modes)
	for entry in [["solo","单人＋搭档"],["online","远程双人"]]:
		var button:=Button.new()
		button.text=entry[1]
		button.set_meta("mode",entry[0])
		button.pressed.connect(func():choose_mode(entry[0]))
		modes.add_child(button)
		mode_buttons.append(button)
	online_row=HBoxContainer.new()
	inner.add_child(online_row)
	net_address=LineEdit.new()
	net_address.custom_minimum_size=Vector2(300,42)
	net_address.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	net_address.text=NetClient.page_default_address()
	if net_address.text.is_empty():net_address.text="ws://127.0.0.1:24681"
	online_row.add_child(net_address)
	net_button=Button.new()
	net_button.text="连接队友"
	net_button.pressed.connect(toggle_online)
	online_row.add_child(net_button)
	net_status=label("远程双人：连接同一版本网页",16)
	inner.add_child(net_status)
	touch.blockers.append(net_button)
	var choice:=HBoxContainer.new()
	inner.add_child(choice)
	for name in ["简单","普通","困难"]:
		var button:=Button.new()
		button.text=name
		button.pressed.connect(func():
			command("difficulty",name))
		choice.add_child(button)
		difficulty_buttons.append(button)

func hud_panel(canvas: CanvasLayer) -> PanelContainer:
	var result:=PanelContainer.new()
	var style:=StyleBoxEmpty.new()
	result.add_theme_stylebox_override("panel",style)
	result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(result)
	return result

func health_bar(color: Color, height: float) -> ProgressBar:
	var result:=ProgressBar.new()
	result.custom_minimum_size=Vector2(0,height)
	result.show_percentage=false
	result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var back:=StyleBoxFlat.new()
	back.bg_color=Color(0.92,0.96,0.91,0.18)
	var fill:=StyleBoxFlat.new()
	fill.bg_color=color
	result.add_theme_stylebox_override("background",back)
	result.add_theme_stylebox_override("fill",fill)
	return result

func reset_journey_views() -> void:
	buddy.reset()
	failed_animation_started=[false,false]
	rescue_seen=[0,0]
	rescue_pulse=[0.0,0.0]
	last_fire_sent=false
	prepared_online_frame=-1
	# 固定关卡重试只需刷新阶段和反馈，不重建相同的环境模型。
	floor_stamp=""
	sound_events.clear()
	clear_controls()
	if is_instance_valid(combat_view): combat_view.reset()

func apply_journey_primary() -> void:
	if fail_showing():return
	match run.state:
		"start": run.state="running";run.reset_input()
		"paused": run.pause()
		"failed":
			if not run.restore_checkpoint(): run.retry(true)
			reset_journey_views()
		"complete": run.new_campaign();reset_journey_views()
		"settlement":
			run.confirm_step(false,false)
			run.confirm_step(true,true)
			reset_journey_views()
	clear_controls()

func _unhandled_key_input(event: InputEvent) -> void:
	if not scene_prepared: return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode==KEY_ESCAPE:
		command("pause")
		clear_controls()
	elif event.keycode==KEY_R and run.state=="running": reload_requested=true
	elif event.keycode==KEY_G and run.state=="running": drop_requested=true
	elif event.keycode==KEY_ENTER and run.state in ["start","failed","complete"]: journey_primary()
	elif event.keycode==KEY_F1:
		if run.state in ["running","rescue"]: command("pause")
		elif run.state=="start":run.paused_from="start";run.state="paused"
		title.text="素材与制作"
		subtitle.text="角色、松树、草与灌木：Quaternius，CC0。\n扫描地面与石材、天空：Poly Haven，CC0。\n工业建筑：Kenney，CC0。\n房屋、野猪、推车、水车、门与吊桥：项目 Blender 制作脚本。\n字体：Noto Sans SC，SIL OFL 1.1。\n完整来源与修改记录见 ASSET_SOURCES.md。"
		set_meta("credits",true)

func _physics_process(delta: float) -> void:
	if web_test_mode:return
	var measured_start:=Time.get_ticks_usec() if web_verify else 0
	touch.set_enabled(touch_device and play_mode!="local" and run.state in ["running","rescue","settlement"])
	if net.active():
		online_process(delta)
		return
	if incremental_loading and not prepare_journey_frame():
		update_journey_ui()
		journey_hint.text="正在准备前方路段…" if chunk_assets.error.is_empty() else "资源读取失败，请刷新网页重试："+chunk_assets.error.get_file()
		return
	var measured_prepared:=Time.get_ticks_usec() if web_verify else 0
	var input:=sample_local_input()
	run.solo_control=play_mode=="solo"
	run.external_companion=not run.combat_trial
	run.set_combat_input(input.get("fire",false),input.get("reload",false),input.get("drop",false))
	var second:Vector2=input.b
	var second_jump:bool=input.jb
	if play_mode=="solo" and not run.combat_trial:
		var choice:Dictionary=buddy.think(run,delta,input.a,input.ja)
		second=choice.move;second_jump=choice.jump
	var measured_thought:=Time.get_ticks_usec() if web_verify else 0
	var before:String=run.state
	run.step(delta,input.a,second,input.ja,second_jump)
	var measured_stepped:=Time.get_ticks_usec() if web_verify else 0
	if run.state!=before:
		clear_controls()
		# 救援完成仍是同一局，保留拾取物、攻击反馈和伙伴状态。
		# 开局、重试与换章由各自命令重置，不能把恢复奔跑当作整局重建。
		if run.state=="running" and before not in ["rescue","paused"]: reset_journey_views()
	frame_delta=delta
	view_pending=true
	if web_verify:
		for sample in [["prepare",measured_prepared-measured_start],["buddy",measured_thought-measured_prepared],["simulation",measured_stepped-measured_thought],["view",Time.get_ticks_usec()-measured_stepped]]:
			var cost:Dictionary=frame_costs.get(sample[0],{"samples":0,"total_usec":0,"max_usec":0})
			cost.samples+=1;cost.total_usec+=sample[1];cost.max_usec=maxi(cost.max_usec,sample[1])
			frame_costs[sample[0]]=cost

func _process(_delta:float)->void:
	# 每个画面帧只提交一次最终状态，本地与网页使用同一规则。
	if scene_prepared and view_pending:
		view_pending=false
		var started:=Time.get_ticks_usec()
		frame_delta=_delta
		sync_view()
		pump_ambience(_delta)
		if web_verify:
			var cost:Dictionary=frame_costs.get("render_view",{"samples":0,"total_usec":0,"max_usec":0})
			var duration:=Time.get_ticks_usec()-started
			cost.samples+=1;cost.total_usec+=duration;cost.max_usec=maxi(cost.max_usec,duration)
			frame_costs.render_view=cost

func clear_controls() -> void:
	if is_instance_valid(net) and net.active() and net.in_match:
		# 联机模拟状态只在共同帧修改，本地只清理设备输入。
		blocked_keys.assign(MOVE_KEYS)
		if is_instance_valid(touch):touch.reset()
	else:super()
	reload_requested=false
	drop_requested=false
	fire_blocked=true

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and is_instance_valid(touch):
		touch_device=true
		touch.set_enabled(run.state in ["running","rescue","settlement"])

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(touch):
		if run.state in ["running","rescue"]: command("pause")
		clear_controls()

func sync_view() -> void:
	if robots.size()<2: return
	sync_world()
	sync_events()
	sync_static_hazards()
	sync_gates()
	road.position=Vector3.ZERO
	for i in range(2):
		var point:Vector2=run.a.position if i==0 else run.b.position
		robots[i].position=Vector3(point.x/SCALE,run.foot_height(i)/SCALE,-point.y/SCALE)
		if run.state=="rescue":
			var hanging:Vector3=run.rescue_body_position(i)
			robots[i].position=Vector3(hanging.x/SCALE,hanging.y/SCALE,-hanging.z/SCALE)
		elif run.state=="failed" and run.death_positions.size()==2:
			var dead:Vector3=run.death_positions[i]
			robots[i].position=Vector3(dead.x/SCALE,dead.y/SCALE,-dead.z/SCALE)
			# 普通死亡的物理 y 降低的是绳索腰扣；Death 骨骼已经自行倒地，
			# 不能再把整个模型一起下移。坠落仍完整使用真实物理高度。
			if not falling():robots[i].position.y=run.floor_heights[i]/SCALE
		shadows[i].position=Vector3(point.x/SCALE,0.02,-point.y/SCALE)
		shadows[i].scale=Vector3.ONE*(1.0-run.heights[i]/Run.JUMP_APEX*0.35)
		sync_journey_character(i)
		# 只在正常行进时出扬尘；救援、失败、暂停与坠落不出。
		fx.sync_player(i,Vector3(point.x/SCALE,run.floor_heights[i]/SCALE+.05,-point.y/SCALE),run.heights[i],run.state=="running" and not falling(),get_process_delta_time())
	var path:Array[Vector3]=[]
	var points:PackedVector2Array=run.rope.physical_path()
	var zs:PackedFloat32Array=run.rope.physical_heights()
	for n in range(points.size()): path.append(Vector3(points[n].x/SCALE,zs[n]/SCALE,-points[n].y/SCALE))
	if path.size()>1:
		rope_view.set_tension(run.rope_tension(),run.rope_status(),get_process_delta_time())
		rope_view.simulate(path,0,Color.WHITE,0)
	update_journey_camera()
	var theme:String=run.theme_at(run.distance)
	var forest_weight:float=Landscape.profile(run.distance/SCALE,run.level_index).y if not run.combat_trial else 0.65
	canopy_light.light_energy=lerpf(1.25,1.05,forest_weight)*(Atmosphere.SUN_SCALE if atmosphere.enabled else 1.0)
	canopy_light.light_color=Color("ffe2bd").lerp(Color("e7edce"),forest_weight)
	world_environment.ambient_light_energy=lerpf(0.66,0.58,forest_weight)*(Atmosphere.AMBIENT_SCALE if atmosphere.enabled else 1.0)
	world_environment.fog_density=lerpf(0.0032,0.0065,forest_weight)
	world_environment.fog_sky_affect=forest_weight*.85
	landscape.leaf_material.set_shader_parameter("phase",run.elapsed)
	landscape.palette.NaturalLeaf.set_shader_parameter("phase",run.elapsed)
	world_environment.fog_light_color=Color("a19a8b").lerp(Color("7e9182"),forest_weight)
	atmosphere.sync(camera,run.distance/SCALE,run.level_index,forest_weight)
	var middle:Vector2=(run.a.position+run.b.position)*.5
	fx.sync_ambient(Vector3(middle.x/SCALE,0,-middle.y/SCALE),forest_weight,1.0-forest_weight)
	for chunk in world_chunks.values():
		if not chunk.visible:continue
		for node in chunk.get_meta("wind_nodes",[]):
			node.rotation.z=sin(run.elapsed*1.1+float(node.get_meta("wind")))*0.008
	sync_journey_rewards()
	if is_instance_valid(combat_view): combat_view.sync()
	update_journey_ui()
	publish_web_verification()

# 旅程使用固定世界坐标；沿用道路版动作与腰部旋转，身体仍由真实物理位置驱动。
func sync_journey_character(i:int)->void:
	var visual_state:String=run.paused_from if run.state=="paused" else run.state
	var rescuing:bool=visual_state=="rescue" and not run.rescue.is_empty()
	var hanging:bool=rescuing and i==run.rescue.role
	for child in robots[i].get_children():
		if child is Label3D:child.visible=visual_state not in ["rescue","failed"]
	robots[i].rotation=Vector3.ZERO
	if visual_state=="running":
		robots[i].rotation.x=-0.13-run.move_directions[i].y*0.07 if run.actions[i]=="Run" else 0.0
		robots[i].rotation.z=-run.move_directions[i].x*0.06
	if rescuing:
		var body:Vector3=run.rescue_body_position(i)
		robots[i].position=Vector3(body.x/SCALE,body.y/SCALE,-body.z/SCALE)
		var presses:int=run.rescue.presses[i]
		if presses>rescue_seen[i]:rescue_pulse[i]=1.0
		rescue_seen[i]=presses
		if run.state!="paused":rescue_pulse[i]=maxf(0,rescue_pulse[i]-frame_delta*6.0)
		var climb:float=clampf(run.rescue.get("climb",0.0)/Run.RESCUE_CLIMB_TIME,0,1)
		var holder:Vector2=run.b.position if run.rescue.role==0 else run.a.position
		var facing:Vector2=(run.rescue.hang-holder)*(-1.0 if hanging else 1.0)
		if facing.length()>1.0 and climb<0.5:robots[i].rotation.y=atan2(-facing.x,facing.y)
		robots[i].rotation.x=lerpf(-0.08-rescue_pulse[i]*0.12 if hanging else 0.08+rescue_pulse[i]*0.25,0.0,climb)
	else:
		rescue_seen[i]=0
		rescue_pulse[i]=0.0
	if falling():
		# 坠落只作一次受力倾斜，随后保持下坠姿势，不在落地后持续自转。
		var tilt:float=smoothstep(0.0,0.65,run.death_time)
		robots[i].rotation.x=tilt*0.65
		robots[i].rotation.z=tilt*(0.25 if i==0 else -0.25)
	# 旋转绕腰部进行，让绳索物理挂点仍落在角色腰上。
	robots[i].position+=Vector3(0,1.4,0)-robots[i].basis*Vector3(0,1.4,0)
	robots[i].get_node("RopeKnot").visible=run.rope.physical.is_empty() or run.rope.physical.bound[i]
	shadows[i].visible=not falling() and not hanging
	if i>=animation_players.size():return
	var player:AnimationPlayer=animation_players[i]
	if run.state=="paused":
		player.speed_scale=0
		return
	player.speed_scale=1.0
	if run.state=="failed":
		if not failed_animation_started[i]:
			play_action(player,"HitRecieve_1")
			failed_animation_started[i]=true
		return
	failed_animation_started[i]=false
	if rescuing:
		var climb:float=run.rescue.get("climb",0.0)/Run.RESCUE_CLIMB_TIME
		play_action(player,"RopePull" if not hanging else ("Run" if climb>0.5 else "Climb"))
		player.speed_scale=1.1 if player.current_animation.ends_with("Run") else 0.8+rescue_pulse[i]*1.6+(0.6 if climb>0 else 0.0)
		return
	var action:String="Jump" if run.heights[i]>0 else run.actions[i]
	if run.state in ["start","settlement","complete"]:action="Idle"
	play_action(player,action)
	var pace:float=run.WALK_SPEED/160.0*(run.Combat.MOVE_SCALE if not run.combat.weapons[i].is_empty() else 1.0)
	player.speed_scale=1.1*pace if action=="Run" else 1.0
	if run.heights[i]>0:
		player.seek(clampf((Run.JUMP_SPEED-run.vertical_speed[i])/Run.GRAVITY/(2*Run.JUMP_SPEED/Run.GRAVITY),0,1)*player.current_animation_length,true)

func fail_showing()->bool:
	# 使用模拟死亡时间，联机双方对重试时机的判断一致。
	return run.state=="failed" and run.death_time<(FAIL_FALL_SHOW if falling() else FAIL_HIT_SHOW)

func camera_shot()->Transform3D:
	if not run.rescue.is_empty() and run.state in ["rescue","paused"]:
		var hanging:Vector3=robots[run.rescue.role].position
		var holder:Vector3=robots[1-run.rescue.role].position
		var away:=Vector3(hanging.x-holder.x,0,hanging.z-holder.z).normalized()
		if away.is_zero_approx():away=Vector3.BACK
		# 从两人中点向崖外斜看，避免沿绳子直视时近端角色遮挡或被裁掉。
		var side:=Vector3(-away.z,0,away.x)
		var focus:Vector3=(hanging+holder)*.5+Vector3.UP*1.35
		var reach:=maxf(11.0,hanging.distance_to(holder)*1.4)
		var eye:Vector3=focus+(away+side).normalized()*reach+Vector3.UP*5.0
		return Transform3D.IDENTITY.translated(eye).looking_at(focus,Vector3.UP)
	if run.state=="failed":return super()
	var home:=camera_home
	home.origin.z-=run.distance/SCALE
	return home

func update_journey_camera()->void:
	if run.state=="paused":return
	var dramatic:bool=run.state in ["rescue","failed"]
	if dramatic:journey_camera_returning=true
	if dramatic or journey_camera_returning:
		update_camera()
		var target:=camera_shot()
		if not dramatic and camera.transform.origin.distance_to(target.origin)<.01:
			camera.transform=target;journey_camera_returning=false
	else:camera.transform=camera_shot()

func sync_journey_rewards() -> void:
	while reward_views.size()<run.rewards.size():
		var view:=MeshInstance3D.new()
		var sphere:=SphereMesh.new()
		sphere.radius=0.26
		sphere.height=0.52
		view.mesh=sphere
		view.material_override=material("journey_gold",Color("ffc866"),0.2)
		road.add_child(view)
		reward_views.append(view)
	for i in range(reward_views.size()):
		var view:Node3D=reward_views[i]
		if i>=run.rewards.size(): view.visible=false;continue
		var reward:Dictionary=run.rewards[i]
		view.visible=not reward.claimed and absf(reward.position.y-run.distance)<4000
		view.position=Vector3(reward.position.x/SCALE,0.8,-reward.position.y/SCALE)
		view.scale=Vector3.ONE*(1.8 if reward.kind!="coin" else 1.0)
		view.material_override=material("reward_"+reward.kind,{"coin":Color("efc36a"),"shield":Color("63bfd0"),"prize":Color("b58fea")}[reward.kind],0.2)

# 独立救援提示，沿用原来的大进度条和小倒计时条；不捕获跳跃输入。
func build_rescue_hud(canvas:CanvasLayer)->void:
	rescue_box=Control.new()
	rescue_box.name="RescueHUD"
	rescue_box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rescue_box.hide()
	canvas.add_child(rescue_box)
	var backdrop:=ColorRect.new()
	backdrop.name="Backdrop"
	backdrop.position=Vector2(-16,-80)
	backdrop.color=Color(0,0,0,0)
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rescue_box.add_child(backdrop)
	rescue_label=label("",21,Color("ffe2a0"))
	rescue_label.add_theme_color_override("font_outline_color",Color(0.06,0.09,0.07,0.9))
	rescue_label.add_theme_constant_override("outline_size",4)
	rescue_label.position=Vector2(0,-68)
	rescue_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	rescue_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	rescue_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rescue_box.add_child(rescue_label)
	for entry in [["ProgressBack",0,24],["TimerBack",32,7]]:
		var bar:=ColorRect.new()
		bar.name=entry[0];bar.position.y=entry[1];bar.size.y=entry[2]
		bar.color=Color("263733");bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
		rescue_box.add_child(bar)
	rescue_fill=ColorRect.new();rescue_fill.size.y=24
	rescue_fill.color=Color("ffc06b");rescue_fill.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rescue_box.add_child(rescue_fill)
	rescue_timer_fill=ColorRect.new();rescue_timer_fill.position.y=32;rescue_timer_fill.size.y=7
	rescue_timer_fill.color=Color("ff6b52");rescue_timer_fill.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rescue_box.add_child(rescue_timer_fill)

func sync_rescue_hud()->void:
	if not is_instance_valid(rescue_box):return
	rescue_box.visible=run.state=="rescue" and not run.rescue.is_empty()
	if not rescue_box.visible:return
	var viewport:=get_viewport().get_visible_rect().size
	var width:=minf(620,viewport.x-48)
	rescue_box.position=Vector2((viewport.x-width)/2,viewport.y-160)
	rescue_box.get_node("Backdrop").size=Vector2(width+32,132)
	rescue_label.size=Vector2(width,64)
	for name in ["ProgressBack","TimerBack"]:rescue_box.get_node(name).size.x=width
	rescue_fill.size.x=width*clampf(run.rescue.progress,0,1)
	rescue_timer_fill.size.x=width*clampf(1.0-run.rescue.time/Run.RESCUE_TIME,0,1)
	var instruction:String="连点空格拉人 / 攀爬，搭档同步协助"
	if play_mode=="local":
		var holder:int=1-run.rescue.role
		var keys:=["空格","回车"]
		instruction="%02d 连点%s拉人 · %02d 连点%s向上爬"%[holder+1,keys[holder],run.rescue.role+1,keys[run.rescue.role]]
	elif play_mode=="online":instruction="连点空格拉人 / 攀爬，与队友一起用力"
	if touch_device:instruction="连点右侧跳跃按钮，拉人 / 向上攀爬"
	if run.rescue.has("climb"):instruction="拉住了！正在爬回路面"
	rescue_label.text="救援进度 %d%%  ·  剩余 %.1f 秒\n%s"%[roundi(run.rescue.progress*100),maxf(0,Run.RESCUE_TIME-run.rescue.time),instruction]

func update_journey_ui() -> void:
	if not is_instance_valid(hud): return
	sync_rescue_hud()
	for button in mode_buttons:
		button.visible=run.state=="start" and not run.combat_trial
		button.disabled=net.active()
	online_row.visible=play_mode=="online" and run.state in ["start","paused"]
	net_status.visible=play_mode=="online"
	net_button.text="断开连接" if net.active() else "连接队友"
	net_address.editable=not net.active()
	primary.disabled=play_mode=="online" and not net.in_match
	var viewport := get_viewport().get_visible_rect().size
	var inset:=12.0 if viewport.x<700 or viewport.y<500 else 24.0
	var hud_width:=minf(244,(viewport.x-2*inset-64)/2)
	health_panel.position=Vector2(inset,inset)
	health_panel.size=Vector2(hud_width,0)
	weapon_panel.size=Vector2(hud_width,0)
	weapon_panel.position=Vector2(viewport.x-inset-hud_width,inset)
	pause_button.position=Vector2(viewport.x/2-20,inset)
	pause_button.size=Vector2(40,40)
	panel.size.x=minf(800,viewport.x-32)
	panel.position=Vector2((viewport.x-panel.size.x)/2,maxf(12,(viewport.y-panel.size.y)/2))
	var role: int=net.role if play_mode=="online" and net.in_match else 0
	combat_health.value=run.combat.health[role]
	partner_health.value=run.combat.health[1-role]
	hud.text="%02d   %d / 100%s"%[role+1,run.combat.health[role],"  护盾" if run.shield else ""]
	partner_status.text="%02d   %d / 100"%[2-role,run.combat.health[1-role]]
	for entry in [[combat_health,role],[partner_health,1-role]]:
		var fill: StyleBoxFlat=entry[0].get_theme_stylebox("fill")
		fill.bg_color=Color("ef8078") if run.combat.health[entry[1]]<=30 else (Color("9cdeb9") if entry[1]==role else Color("e4b883"))
	var weapon: Dictionary=run.combat.weapons[role]
	combat_status.text="空手" if weapon.is_empty() else "冲锋枪"
	combat_status.visible=weapon.is_empty()
	weapon_icon.visible=not weapon.is_empty()
	weapon_ammo.text="" if weapon.is_empty() else "%02d / %d"%[weapon.ammo,weapon.reserve]
	weapon_ammo.visible=not weapon.is_empty()
	weapon_detail.text=""
	if not weapon.is_empty():
		if weapon.reload>0: weapon_detail.text="换弹 %.1f 秒"%(weapon.reload*Run.FIXED_STEP)
		elif weapon.ammo==0 and weapon.reserve==0: weapon_detail.text="弹药耗尽"
	weapon_detail.visible=not weapon_detail.text.is_empty()
	var playing: bool=run.state in ["running","rescue"]
	health_panel.visible=playing
	weapon_panel.visible=playing
	journey_hint.position=Vector2(inset,viewport.y-100 if not touch_device else viewport.y*.58)
	journey_hint.size=Vector2(viewport.x-2*inset,56)
	journey_hint.text=""
	journey_hint.visible=run.state=="rescue" or (run.state=="running" and run.charge_gate.get("active",false) and not run.charge_gate.open and absf(run.a.position.y-run.charge_gate.receiver.y)<180)
	if journey_hint.visible: journey_hint.text=run.active_hint()
	panel.visible=run.state in ["start","paused","failed","settlement","complete"] and not fail_showing()
	primary.visible=true
	training_button.visible=run.state=="start" and play_mode=="solo"
	training_button.text="返回三关旅程" if run.combat_trial else "战斗训练 · 持枪步行约 90 秒"
	restart_button.visible=run.state in ["paused","failed"]
	pause_button.visible=run.state in ["running","rescue"]
	if is_instance_valid(touch): touch.set_enabled(touch_device and run.state in ["running","rescue","settlement"])
	for button in difficulty_buttons: button.visible=run.state=="start" and play_mode!="online"
	if get_meta("credits",false) and run.state=="paused": return
	set_meta("credits",false)
	match run.state:
		"start":
			title.text="共生连线 · 战斗训练" if run.combat_trial else "共生连线 · 连续旅程"
			subtitle.text="WASD 移动 · 空格跳跃 · 鼠标左键射击\nR 换弹 · G 丢枪 · Esc 暂停\n靠近自动拾取。机关分级扣血，重型机关危险更高。"
			if touch_device: subtitle.text="左侧滑动移动；右侧大按钮跳跃、按住射击。\n小按钮换弹、丢枪，靠近枪械自动拾取。\n搭档跟随并共同跳跃，踩空时连点跳跃救援。\n可停步观察敌人，持枪移动稍慢；血量耗尽从存档继续。"
			primary.text="开始训练" if run.combat_trial else "出发"
		"paused":
			title.text="暂停"
			subtitle.text="WASD 移动 · 空格跳跃 · 鼠标左键射击\nR 换弹 · G 丢枪 · Esc 继续 · F1 素材署名\n金币 %d · 奖品 %d · %.0f / %.0f 米"%[run.coins,run.prizes,run.progress()/SCALE,run.finish_distance()/SCALE]
			if touch_device: subtitle.text="左侧摇杆移动 · 右侧跳跃、射击、换弹、丢枪\n金币 %d · 奖品 %d"%[run.coins,run.prizes]
			primary.text="继续旅程"
		"failed": title.text="两人共同重试";subtitle.text=run.reason+"\n回到本区域的安全存档点，危险与奖励恢复原状态。";primary.text="从存档点继续"
		"settlement":
			title.text="共同抵达 · "+run.CHAPTERS[run.level_index].name
			subtitle.text="本关 %.1f 秒 · 金币 %d · 奖品 %d\n点击按钮或松开后按跳跃键，进入下一关。"%[run.elapsed,run.coins,run.prizes]
			primary.text="下一关"
		"complete": title.text="训练完成" if run.combat_trial else "归航完成";subtitle.text="击退 %d 个敌人 · 团队总分 %d。\n可以重新出发。"%[run.combat.kills,run.total_score()];primary.text="重新出发"
	if run.state=="rescue": journey_hint.text="连点跳跃救援！进度 %.0f%% · 剩余 %.1f 秒"%[run.rescue.progress*100,maxf(0,Run.RESCUE_TIME-run.rescue.time)]

func build_ambience() -> void:
	ambient=AudioStreamPlayer.new()
	ambient.volume_db=-23
	add_child(ambient)
	forest_birds=AudioStreamPlayer.new()
	var birds:AudioStreamOggVorbis=load("res://assets/audio/forest_birds.ogg")
	birds.loop=true
	forest_birds.stream=birds
	forest_birds.volume_db=-60
	add_child(forest_birds)
	# 缓存有限 PCM 循环，避免流式生成器在退出时遗留音频播放句柄。
	for kind in ["wind","forest","river"]:
		var stream:AudioStreamWAV=load("res://assets/audio/ambience_%s.wav"%kind).duplicate()
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin=0
		stream.loop_end=7*22050
		ambience_streams[kind]=stream

static func ambience_wave(t:float,kind:String)->float:
	var wind:=sin(t*TAU*49)*sin(t*TAU*65)*0.08+sin(t*TAU*112)*0.03
	var bird:=0.0
	if kind=="forest" and t<0.35:bird=sin(t*(3100+sin(t*36)*600))*sin(t/0.35*PI)*0.18
	var water:=sin(t*TAU*101)*sin(t*TAU*67)*0.12 if kind=="river" else 0.0
	return wind+bird+water

func pump_ambience(_delta: float) -> void:
	if not is_instance_valid(ambient):return
	# 开始页和加载页无需创建一个立即暂停的播放句柄。
	if run.state!="running":
		if not ambient.stream_paused:ambient.stream_paused=true
		if not forest_birds.stream_paused:forest_birds.stream_paused=true
		return
	var weight:float=Landscape.profile(run.distance/SCALE,run.level_index).y
	if not forest_birds.playing:forest_birds.play()
	var volume:=linear_to_db(maxf(.001,weight*.33))
	if not is_equal_approx(forest_birds.volume_db,volume):forest_birds.volume_db=volume
	if forest_birds.stream_paused:forest_birds.stream_paused=false
	var theme:String=run.theme_at(run.distance)
	var kind:="forest" if theme in ["forest","edge","meadow","farm"] else ("river" if theme=="river" else "wind")
	if ambience_region!=kind:
		ambient.stream=ambience_streams[kind]
		ambient.play()
		ambience_region=kind
	if ambient.stream_paused:ambient.stream_paused=false

# 资源动画由生产时间采样；暂停、存档恢复和重试均与物理相位一致。
func animation_targets(node: Node, token: String) -> Array:
	var targets: Array=[]
	if node is AnimationPlayer:
		for clip in node.get_animation_list():
			if token in clip: targets.append([node,clip,node.get_animation(clip).length])
	for child in node.get_children(): targets.append_array(animation_targets(child,token))
	return targets

func sample_animation(node:Node,token:String,time:float)->void:
	var key := "animation_targets_"+token
	if not node.has_meta(key): node.set_meta(key,animation_targets(node,token))
	for target in node.get_meta(key):
		var player: AnimationPlayer=target[0]
		var sample_time:float=fposmod(time,target[2]) if token in ["Charge","WheelTurn"] else clampf(time,0,target[2])
		if not player.is_playing() and player.current_animation==target[1] and player.current_animation_position==sample_time:continue
		player.play(target[1])
		player.seek(sample_time,true)
		player.pause()

func visual_hazard_candidates() -> Array[int]:
	var bounds:=Rect2(-Run.EDGE-1000,run.distance-MODEL_BEHIND,Run.EDGE*2+2000,MODEL_PREFETCH+MODEL_BEHIND)
	return run.obstacles_in_bounds(bounds)

func hazard_view_y(index: int) -> float:
	if run.hazard_specs[index].get("front",false):return run.obstacles[index].get_center().y+run.hazard_specs[index].offset.y
	if run.kinds[index] in ["drone","forklift"]:return run.hazard_sample(index,run.elapsed).rect.get_center().y
	return run.obstacles[index].get_center().y

func hazard_has_view(index: int) -> bool:
	return run.hazard_specs[index].get("front",false) or run.kinds[index] in ["drone","rail","pillar","cargo","active_spikes","collapse","sweeper","hammer","press","steam","shuttle","piston","lift","slope","steps","tilt"]

func hazard_asset_paths(index:int)->Array:
	match run.kinds[index]:
		"drone":return ["res://assets/props/Eagle_Flying.glb"]
		"stone_ball":return [TRIPO_BOULDER]
		"rail":return [TRIPO_TIMBER]
	return []

# 模型只适配已有危险体；轮廓中心、旋转轴和碰撞规则不随美术替换变化。
func tripo_model(parent:Node3D,path:String,size:Vector3,center:Vector3)->Node3D:
	var instance:Node3D=load(path).instantiate()
	parent.add_child(instance)
	if not model_bounds_cache.has(path):model_bounds_cache[path]=model_bounds(instance,instance)
	var bounds:AABB=model_bounds_cache[path]
	var factor:=size/bounds.size
	instance.scale=factor
	instance.position=center-bounds.get_center()*factor
	instance.name="TripoModel"
	instance.set_meta("asset_path",path)
	return instance

func build_ball_model(chunk:Node3D,index:int)->void:
	super.build_ball_model(chunk,index)
	if run.kinds[index]!="stone_ball":return
	var body:MeshInstance3D=chunk.get_node("BallBody")
	for child in body.get_children():child.free()
	body.material_override=zone_material("hidden_tripo_ball",Color(0,0,0,0))
	var diameter:float=run.obstacles[index].size.x/SCALE
	tripo_model(body,TRIPO_BOULDER,Vector3.ONE*diameter,Vector3.ZERO)

func prepare_hazard_views(deadline: int) -> bool:
	var ready:=true
	for index in visual_hazard_candidates():
		if static_views.has(index) or not hazard_has_view(index):continue
		if Time.get_ticks_usec()>=deadline:
			if model_visible(hazard_view_y(index)):ready=false
			continue
		if not chunk_assets.ready(hazard_asset_paths(index)):
			if model_visible(hazard_view_y(index)):ready=false
			continue
		sync_static_hazard(index)
	return ready

func sync_static_hazards()->void:
	for index in static_views.keys():
		if index>=run.kinds.size() or not model_resident(hazard_view_y(index)):
			static_views[index].queue_free();static_views.erase(index)
		elif not model_visible(hazard_view_y(index)):static_views[index].hide()
	for index in visual_hazard_candidates():
		if incremental_loading and not static_views.has(index):continue
		sync_static_hazard(index)

func sync_static_hazard(i: int) -> void:
	var kind:String=run.kinds[i]
	if kind=="drone" or run.hazard_specs[i].get("front",false):
		sync_moving_threat(i)
		return
	if kind not in ["rail","pillar","cargo","active_spikes","collapse","sweeper","hammer","press","steam","shuttle","piston","lift","slope","steps","tilt"]:return
	var rect:Rect2=run.obstacles[i]
	if not model_preload(rect.get_center().y):
		if static_views.has(i):static_views[i].hide()
		return
	if kind in ["sweeper","hammer","press","steam","shuttle","piston","lift","slope","steps","tilt"]:
		if not static_views.has(i):static_views[i]=make_hazard_view(i)
		var old_view:Node3D=static_views[i]
		var sample:Dictionary=run.hazard_sample(i,run.elapsed)
		old_view.position=Vector3(sample.rect.get_center().x/SCALE,0,-sample.rect.get_center().y/SCALE)
		if kind in Run.Terrain.KINDS:sync_terrain_model(old_view,i)
		elif kind in Run.Industrial.KINDS:sync_industrial_model(old_view,i,sample)
		else:
			old_view.get_node("SweeperArm").rotation.y=sample.geometry.angle
			old_view.get_node("WarningFootprint").visible=true
		old_view.visible=model_visible(sample.rect.get_center().y)
		return
	if not static_views.has(i):
		var view:=Node3D.new()
		road.add_child(view)
		if kind=="rail":
			tripo_model(view,TRIPO_TIMBER,Vector3(rect.size.x/SCALE,.6,rect.size.y/SCALE),Vector3(0,.3,0))
		elif kind=="pillar":cylinder(view,Vector3(0,2.5,0),rect.size.x/SCALE/2,5.0,landscape.palette.Stone)
		elif kind=="cargo":
			rock(view,rock_mesh("encounter_boulder",321,1,1,1,.25,"round"),ground_material("ruins"),Vector3.ZERO,1)
			var half_height:float=run.obstacle_heights[i]/SCALE/2 if run.hazard_specs[i].get("small",false) else 1.5
			view.get_child(0).scale=Vector3(rect.size.x/SCALE/2,half_height,rect.size.y/SCALE/2)
			view.get_child(0).position.y=half_height
		elif kind=="collapse":
			box(view,Vector3(0,.012,0),Vector3(rect.size.x/SCALE,.02,rect.size.y/SCALE),material("fragile_ground",Color("5e5943")))
			for n in range(7):
				var crack:=box(view,Vector3(-rect.size.x/SCALE/2+n*1.6,.027,0),Vector3(.08,.025,rect.size.y/SCALE),material("fragile_cracks",Color("25261d")));crack.rotation.y=.18 if n%2==0 else -.18
		else:
			box(view,Vector3(0,.03,0),Vector3(rect.size.x/SCALE,.06,rect.size.y/SCALE),material("trap_base",Color("524935")))
			var spike_count:int=maxi(1,floori(rect.size.x/SCALE/.65))
			for n in range(spike_count):
				var spike:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=0;mesh.bottom_radius=.18;mesh.height=.8;mesh.radial_segments=5
				spike.mesh=mesh;spike.material_override=material("trap_tip",Color("c0b89f"));spike.position=Vector3((float(n)+.5)/spike_count*rect.size.x/SCALE-rect.size.x/SCALE/2,.4,0);view.add_child(spike)
			var warning:=box(view,Vector3(0,.065,0),Vector3(rect.size.x/SCALE+.08,.025,rect.size.y/SCALE+.08),material("small_trap_warning",Color("e7ae43"),.25))
			warning.name="SpikeWarning"
		static_views[i]=view
	static_views[i].position=Vector3(rect.get_center().x/SCALE,0,-rect.get_center().y/SCALE)
	static_views[i].visible=model_visible(rect.get_center().y)
	if kind=="collapse":static_views[i].visible=static_views[i].visible and run.hazard_sample(i,run.elapsed).stage!="collapsed"
	if kind=="active_spikes":
		var sample:Dictionary=run.hazard_sample(i,run.elapsed)
		for n in range(1,static_views[i].get_child_count()):
			var spike:Node3D=static_views[i].get_child(n)
			if spike.name=="SpikeWarning":
				spike.visible=sample.warning
				continue
			spike.scale.y=maxf(.01,sample.top/16);spike.position.y=sample.top/SCALE/2

func sync_moving_threat(index:int)->void:
	var kind:String=run.kinds[index]
	var sample:Dictionary=run.hazard_sample(index,run.elapsed)
	var rect:Rect2=sample.rect
	if not model_resident(rect.get_center().y) or (kind=="drone" and sample.stage=="spent"):
		if static_views.has(index):static_views[index].queue_free();static_views.erase(index)
		return
	if not static_views.has(index):
		var created:=make_hazard_view(index)
		if kind.begins_with("fly_"):
			var volume:MeshInstance3D=created.get_node("DangerVolume")
			volume.material_override=zone_material("hidden_flying_stone",Color(0,0,0,0))
			CombatView.EnemyView.volume(volume,Vector3.ZERO,Vector3(rect.size.x/SCALE,(sample.top-sample.bottom)/SCALE,rect.size.y/SCALE),landscape.palette.Stone)
		static_views[index]=created
	var view:Node3D=static_views[index]
	view.position=Vector3(rect.get_center().x/SCALE,0,-rect.get_center().y/SCALE)
	if kind=="drone":
		view.visible=model_visible(rect.get_center().y)
		sync_industrial_model(view,index,sample)
		return
	view.visible=model_visible(rect.get_center().y)
	var route:MeshInstance3D=view.get_node("FlightRoute")
	var length:float=clampf(absf(run.hazard_specs[index].velocity.y)*sample.ttc/SCALE,.05,80)
	route.scale.z=length/route.mesh.size.z;route.position.z=length/2;route.visible=sample.warning
	var sign:Label3D=view.get_node("WarningLabel")
	sign.text=Run.hazard_name(kind);sign.visible=sample.warning
	if Run.Threats.is_ball(kind):
		view.get_node("BallBody").rotation.x=run.hazard_specs[index].travel/(rect.size.x/2)
		view.get_node("ContactRing").visible=run.rope.touches(run.obstacle_ids[index])
	else:
		var volume:Node3D=view.get_node("DangerVolume")
		volume.position.y=(sample.bottom+sample.top)/SCALE/2
		volume.visible=sample.active
		view.get_node("WarningFootprint").visible=sample.warning

func choose_mode(value:String)->void:
	if run.state!="start" or net.active():return
	play_mode=value
	run.solo_control=value=="solo"
	run.external_companion=not run.combat_trial
	buddy.reset()
	clear_controls()
	update_journey_ui()

func command(name:String,arg:="")->void:
	if name=="pause" and arg.is_empty():arg="paused" if run.state in ["running","rescue"] else run.paused_from
	if play_mode=="online" and net.active():
		if net.in_match:net.send_command(name,arg)
		return
	apply_command(name,arg)

func apply_command(name:String,arg:="")->void:
	match name:
		"primary":apply_journey_primary()
		"pause":
			if (arg=="paused" and run.state in ["running","rescue"]) or (arg!="paused" and run.state=="paused"):run.pause()
			clear_controls()
		"retry":
			if not fail_showing():run.retry(run.state=="failed");reset_journey_views()
		"difficulty":
			if run.state=="start" and not net.active():run.set_difficulty(arg);reset_journey_views()

func online_process(delta:float)->void:
	if not net.in_match:
		sync_view()
		return
	var input:=sample_local_input()
	net.send_input(input.a,input.ja)
	var fire: bool=input.get("fire",false)
	if fire!=last_fire_sent or input.get("reload",false) or input.get("drop",false):
		net.send_command("combat","%d,%d,%d"%[int(fire),int(input.get("reload",false)),int(input.get("drop",false))])
		last_fire_sent=fire
	var applied:=0
	var start:=Time.get_ticks_usec()
	while not net.frames.is_empty() and applied<4:
		var index:int=net.next_frame
		var frame:Dictionary=net.frames[0]
		if prepared_online_frame!=index:
			var seen:={}
			for entry in frame.cmds:
				var key:=str(entry[0])+":"+str(entry[1])+":"+str(entry[2])
				if not seen.has(key):
					if entry[1]=="combat":apply_combat_command(int(entry[0]),str(entry[2]))
					else:apply_command(entry[1],entry[2])
					seen[key]=true
			prepared_online_frame=index
		# 保留完整帧等待分帧准备，命令只执行一次，不跳帧或推进模拟时间。
		if incremental_loading and not prepare_journey_frame(): break
		net.take_frames(1)
		var before:String=run.state
		run.step(Run.FIXED_STEP*2,frame.a,frame.b,frame.ja,frame.jb)
		if run.state!=before:clear_controls()
		net.report(index,run.sync_hash())
		online_frame_applied.emit(index)
		applied+=1
		if Time.get_ticks_usec()-start>=Run.PRELOAD_SLICE_USEC:break
	frame_delta=delta
	view_pending=true

func start_online_match(seed:int)->void:
	play_mode="online"
	run.solo_control=false
	run.external_companion=true
	run.combat_trial=false
	run.lockstep=true
	run.random_seed=false
	run.difficulty="普通"
	run.seed_value=seed
	run.new_campaign()
	run.state="start"
	reset_journey_views()

func stop_online_match(_reason:String)->void:
	if run.state in ["running","rescue"]:run.pause()
	clear_controls()

func journey_net_status(message:String)->void:
	if is_instance_valid(net_status):net_status.text=message

func toggle_online()->void:
	if net.active():
		net.disconnect_from()
		run.lockstep=false
		run.random_seed=true
		run.new_campaign();run.state="start"
		reset_journey_views()
		net_status.text="已断开，可重新连接或选择单人模式"
	else:
		play_mode="online"
		net.connect_to(net_address.text)
	update_journey_ui()

func publish_web_verification()->void:
	if not web_verify:return
	verify_clock+=frame_delta
	if verify_clock<0.25:return
	verify_clock=0
	var buttons:={}
	for button in mode_buttons:buttons[str(button.get_meta("mode"))]=control_rect(button)
	buttons.primary=control_rect(primary)
	buttons.connect=control_rect(net_button)
	buttons.address=control_rect(net_address)
	buttons.pause=control_rect(pause_button)
	buttons.training=control_rect(training_button)
	var circles:={}
	for action in touch.action_circles():
		var circle:Vector3=touch.action_circles()[action]
		circles[action]=[circle.x,circle.y,circle.z]
	var payload:={"build":WEB_BUILD,"protocol":NetClient.Relay.PROTOCOL,"mode":play_mode,"state":run.state,"chapter":run.level_index,"zone":run.zone_name(),"progress":run.progress(),"a":[run.a.position.x,run.a.position.y],"b":[run.b.position.x,run.b.position.y],"height":run.heights,"ai":buddy.feedback,"network":net.in_match,"desynced":net.desynced,"role":net.role,"network_frame":net.next_frame,"nodes":get_tree().get_node_count(),"fps":Engine.get_frames_per_second(),"controls":buttons}
	payload.render={"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"mobile":landscape.mobile,"cached_assets":chunk_assets.resources.size(),"chunks":world_chunks.size(),"jobs":chunk_jobs.size()}
	payload.render.merge({"scale":get_viewport().scaling_3d_scale,"shadows":canopy_light.shadow_enabled,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"prepare_peak_usec":preparation_peak_usec})
	payload.costs=frame_costs
	payload.combat={"health":run.combat.health,"weapon":run.combat.weapons[0],"kills":run.combat.kills,"training":run.combat_trial,"touch":touch_device,"buttons":circles,"input":{"enabled":touch.enabled,"move":[touch.move.x,touch.move.y],"fire":touch.action_fingers.values(),"jump":touch.jump_fingers.size()}}
	var viewport:=get_viewport().get_visible_rect().size
	payload.viewport=[viewport.x,viewport.y]
	JavaScriptBridge.eval("window.__ctJourney="+JSON.stringify(payload),true)

func control_rect(control:Control)->Array:
	var rect:=control.get_global_rect()
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func journey_primary() -> void:
	command("primary")

func sample_local_input() -> Dictionary:
	if not input_override.is_empty(): return input_override
	var first:=Vector2(float(key_down(KEY_D) or key_down(KEY_RIGHT))-float(key_down(KEY_A) or key_down(KEY_LEFT)),float(key_down(KEY_W) or key_down(KEY_UP))-float(key_down(KEY_S) or key_down(KEY_DOWN)))
	var second:=Vector2.ZERO
	if play_mode=="local":
		first=Vector2(float(key_down(KEY_D))-float(key_down(KEY_A)),float(key_down(KEY_W))-float(key_down(KEY_S)))
		second=Vector2(float(key_down(KEY_RIGHT))-float(key_down(KEY_LEFT)),float(key_down(KEY_UP))-float(key_down(KEY_DOWN)))
	if touch.move!=Vector2.ZERO: first=touch.move
	var touch_jump: bool=touch.take_jump()
	var actions: Dictionary=touch.take_combat()
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): fire_blocked=false
	var fire: bool=(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not fire_blocked and not touch_device) or actions.fire
	var input:={"a":first,"b":second,"ja":key_down(KEY_SPACE) or touch_jump or (play_mode=="online" and key_down(KEY_ENTER)),"jb":key_down(KEY_ENTER),"fire":fire,"reload":reload_requested or actions.reload,"drop":drop_requested or actions.drop}
	reload_requested=false
	drop_requested=false
	return input

func apply_combat_command(role: int, value: String) -> void:
	if run.state!="running" or role not in [0,1]: return
	var fields:=value.split(",")
	if fields.size()!=3: return
	run.combat.fire[role]=fields[0]=="1"
	run.combat.reload[role]=run.combat.reload[role] or fields[1]=="1"
	run.combat.drop[role]=run.combat.drop[role] or fields[2]=="1"

func chunk_chapter(number: int) -> Dictionary:
	if not run.combat_trial: return run.CHAPTERS[run.level_index]
	var themes: Array=[]
	for zone in range(6): themes.append(run.theme_at(number*CHUNK*SCALE))
	return {"length":run.finish_distance(),"zones":run.TRIAL_ZONES,"themes":themes}
