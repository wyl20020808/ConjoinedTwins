extends "res://scripts/road_demo.gd"

const Journey = preload("res://scripts/journey_run.gd")
const CHUNK := 80.0
const Buddy=preload("res://scripts/journey_buddy.gd")
var buddy=Buddy.new()
var play_mode:="local"
var mode_buttons:Array[Button]=[]
var online_row:HBoxContainer
var input_override:Dictionary={}
var web_test_mode:=false
var web_verify:=false
var verify_clock:=1.0
const WEB_BUILD:="journey-web-solo-20261015"
var world_chunks := {}
var event_views := {}
var gate_views := {}
var static_views := {}
var floor_stamp := ""
var built_chapter := -1
var journey_hint: Label
var region_banner: Label
var progress_widget: ProgressBar
var credits_panel: PanelContainer
var canopy_light: DirectionalLight3D
var world_environment: Environment
var ambient: AudioStreamPlayer
var ambience_region := ""
var ambience_streams := {}
var sound_events := {}
var sound_clock := 0.0

func _ready() -> void:
	if OS.has_feature("web"):web_verify=bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('verify')",true))
	ThemeDB.fallback_font=preload("res://assets/fonts/web_ui_font.tres")
	run.dispose()
	finish_view.free()
	charge_gate_view.free()
	run=Journey.new()
	run.state="start"
	add_child(road)
	build_lighting()
	world_environment=get_children().filter(func(node): return node is WorldEnvironment)[0].environment
	world_environment.fog_light_color=Color("849d8b")
	world_environment.fog_density=0.003
	world_environment.ambient_light_energy=0.85
	for node in get_children():
		if node is DirectionalLight3D: canopy_light=node
	canopy_light.rotation_degrees=Vector3(-48,120,0)
	canopy_light.light_color=Color("fff1d4")
	canopy_light.light_energy=1.8
	camera.position=Vector3(0,13,23)
	camera.look_at(Vector3(0,0,-22))
	camera_home=camera.transform
	build_robots()
	sfx=Sfx.new()
	add_child(sfx)
	play_mode="solo" if OS.has_feature("web") else "local"
	net=NetClient.new()
	add_child(net)
	net.status_changed.connect(journey_net_status)
	net.match_started.connect(start_online_match)
	net.match_stopped.connect(stop_online_match)
	build_journey_ui()
	touch_device=OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	touch=TouchControls.new()
	get_node("JourneyCanvas").add_child(touch)
	touch.blockers.assign([panel,pause_button,net_button])
	build_ambience()
	sync_view()

func _exit_tree() -> void:
	if is_instance_valid(net):net.disconnect_from()
	if is_instance_valid(ambient):
		ambient.stop()
		ambient.stream=null
	ambience_streams.clear()
	run.dispose()

func ground_material(theme: String) -> Material:
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
	var old:=chunk.get_node_or_null("Floor")
	if old:
		chunk.remove_child(old)
		old.queue_free()
	var floor_node:=Node3D.new()
	floor_node.name="Floor"
	chunk.add_child(floor_node)
	var y0:=number*CHUNK*SCALE
	var pieces:Array=[Rect2(-Run.EDGE,y0,Run.EDGE*2,CHUNK*SCALE)]
	for gap:Rect2 in run.ground_gaps(): pieces=subtract_floor(pieces,gap)
	var theme: String=run.theme_at(y0)
	for piece:Rect2 in pieces:
		box(floor_node,Vector3(piece.get_center().x/SCALE,-0.32,-piece.get_center().y/SCALE),Vector3(piece.size.x/SCALE,0.64,piece.size.y/SCALE),ground_material(theme))
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
	var chunk:=Node3D.new()
	chunk.name="World_%d"%number
	road.add_child(chunk)
	var rng:=RandomNumberGenerator.new()
	rng.seed=number*109+run.level_index*7919+42
	var start:=number*CHUNK
	var theme: String=run.theme_at(start*SCALE)
	var forest:=theme in ["forest","broken","edge","meadow"]
	var village:=theme in ["village","farm"]
	var land:=material("land_"+theme,Color("48513b") if forest else Color("77765b"))
	for side in [-1.0,1.0]:
		box(chunk,Vector3(side*(Run.EDGE/SCALE+24),-0.65,-start-CHUNK/2),Vector3(48,1.0,CHUNK),land)
		if theme=="river":
			box(chunk,Vector3(side*30,-2.2,-start-CHUNK/2),Vector3(26,0.15,CHUNK),material("water",Color("345f67")))
		for n in range(8):
			var z:=-start-n*10-rng.randf_range(0,4)
			var x:float=side*rng.randf_range(18,36)
			if forest or theme in ["farm","river"]:
				var pine:=model("res://assets/decor/Pine.glb",chunk,Vector3(x,0,z),rng.randf_range(8,15),rng.randf()*TAU,12)
				if pine: pine.set_meta("wind",rng.randf()*TAU)
				if n%2==0: model("res://assets/decor/Bush.glb",chunk,Vector3(side*rng.randf_range(16.5,22),0,z+3),rng.randf_range(1.0,2.3),rng.randf()*TAU)
				if n%2==1: model("res://assets/decor/TallGrass.glb",chunk,Vector3(side*rng.randf_range(16,19),0,z),rng.randf_range(0.7,1.6),rng.randf()*TAU)
			elif theme in ["mine","ruins"]:
				rock(chunk,rock_mesh("journey_rock_%d"%n,n+31,3,1.8,8,0.5),ground_material("ruins"),Vector3(x,-1,z),rng.randf_range(0.8,2.0))
				if theme=="ruins" and n%2==0: model("res://assets/decor/Column.glb",chunk,Vector3(side*18,0,z),6.5)
		if village:
			for n in range(3):
				var name:="house_%d"%((number+n+300)%3)
				asset(chunk,name,Vector3(side*23,0,-start-n*27-10),rng.randf_range(8,11),-side*PI/2)
				asset(chunk,"fence",Vector3(side*17,0,-start-n*27-18),1.6,0)
				asset(chunk,"cart",Vector3(side*19,0,-start-n*27-3),2.3,side*PI/2)
		if theme=="facility":
			for n in range(3): model("res://assets/industrial/building-k.glb",chunk,Vector3(side*27,0,-start-n*28),14,side*PI/2,15)
	if theme=="farm":
		for n in range(12): box(chunk,Vector3(25,-0.05,-start-n*6),Vector3(12,0.1,1.2),material("farmland",Color("51412c")))
	if theme=="river": asset(chunk,"waterwheel",Vector3(19,-1,-start-40),8,PI/2)
	# 固定世界中的路边标牌，提前呈现下一区域。
	var zone_length:float=run.finish_distance()/6.0
	for zone in range(6):
		var y:float=zone*zone_length/SCALE
		if y>=start and y<start+CHUNK:
			asset(chunk,"sign",Vector3(-15,0,-y-6),3.0)
			add_sign(chunk,run.CHAPTERS[run.level_index].zones[zone],Vector3(-12,4,-y-8),38)
	rebuild_floor(chunk,number)
	return chunk

func sync_world() -> void:
	if built_chapter!=run.level_index:
		for chunk in world_chunks.values(): chunk.queue_free()
		world_chunks.clear()
		for view in event_views.values(): view.queue_free()
		event_views.clear()
		for view in gate_views.values(): view.queue_free()
		gate_views.clear()
		built_chapter=run.level_index
		floor_stamp=""
		for view in static_views.values():view.queue_free()
		static_views.clear()
	var current:=int(run.distance/SCALE/CHUNK)
	for number in range(maxi(-1,current-1),current+4):
		if number*CHUNK*SCALE>run.finish_distance()+400: continue
		if not world_chunks.has(number): world_chunks[number]=build_chunk(number)
	for number in world_chunks.keys():
		if number<current-1 or number>current+3:
			world_chunks[number].queue_free()
			world_chunks.erase(number)
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
	if kind=="tree": asset(body,"falling_tree",Vector3.ZERO,12)
	elif kind=="boar":
		var boar:=asset(body,"boar",Vector3.ZERO,1.7,PI)
		if boar:
			var player:=animation_player(boar)
			if player:
				for clip in player.get_animation_list():
					if "Charge" in clip: player.play(clip)
	elif kind=="stone":
		var ball:=MeshInstance3D.new()
		ball.mesh=SphereMesh.new()
		ball.scale=Vector3.ONE*1.2
		ball.material_override=ground_material("ruins")
		body.add_child(ball)
	elif kind=="cart": asset(body,"cart",Vector3.ZERO,3.2,PI/2)
	else:
		var wood:=material("swing_wood",Color("9c805c"))
		wood.albedo_texture=load("res://assets/journey/wood_planks_diff.jpg")
		wood.uv1_triplanar=true
		wood.uv1_scale=Vector3.ONE*0.5
		box(body,Vector3(0,2,0),Vector3(4,4,3.5),wood)
		var arm:=cylinder(root,Vector3(0,6,0),0.18,8,wood)
		arm.name="SwingArm"
		asset(root,"waterwheel",Vector3(19,0,0),7,PI/2)
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
		var near:bool=event.y-run.distance>-900 and event.y-run.distance<4200
		if not near:
			if event_views.has(event.id):
				event_views[event.id].queue_free()
				event_views.erase(event.id)
			continue
		if not event_views.has(event.id): event_views[event.id]=build_event(event)
		var view:Node3D=event_views[event.id]
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
			arm.mesh.height=pivot.distance_to(tip)
			sample_animation(view,"WheelTurn",run.elapsed)
		elif event.kind=="boar":
			sample_animation(body,"Charge",run.elapsed if event.phase=="active" else 0)
			body.position.y+=absf(sin(run.elapsed*18))*0.07 if event.phase=="active" else 0.0
		if event.kind=="cart": sample_animation(body,"WheelTurn",maxf(0,run.elapsed-event.trigger-2.8)*2.0)
		var warning:Node3D=view.get_node("Warning")
		warning.visible=event.phase in ["warning","falling"]
		warning.position.x=event.locked_x/SCALE if event.kind=="stone" else event.rect.get_center().x/SCALE
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
	else:
		asset(root,"drawbridge",Vector3(0,-0.1,-9),0.8)
	return root

func sync_gates() -> void:
	for gate in run.charge_gates:
		if absf(gate.receiver.y-run.distance)>4200: continue
		if not gate_views.has(gate.id): gate_views[gate.id]=build_gate(gate)
		var view:Node3D=gate_views[gate.id]
		sample_animation(view,"BridgeLower",clampf((run.elapsed-gate.opened_at)/0.6,0,1) if gate.open else 0)
		if gate.id=="waterwheel":sample_animation(view,"WheelTurn",run.elapsed)
		view.position=Vector3(0,0,-gate.door.position.y/SCALE)
		var opening:float=clampf((run.elapsed-gate.opened_at)/0.8,0,1) if gate.open else 0
		sample_animation(view.get_node("Door"),"GateOpen",opening)
		for side in [-1,1]:view.get_node("Door/SideBarrier%d"%side).position.y=2.4+opening*6.5
		for side in ["left","right"]:
			view.get_node(side).visible=not gate.open
	# 终点固定在世界中，双方都到达才结算。
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
	for band in [Rect2(0,0,1280,132),Rect2(0,640,1280,80)]:
		var shade:=ColorRect.new()
		shade.position=band.position
		shade.size=band.size
		shade.color=Color(0.025,0.04,0.035,0.82)
		shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
		canvas.add_child(shade)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",24)
	margin.add_theme_constant_override("margin_top",20)
	margin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(margin)
	var column:=VBoxContainer.new()
	column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	region_banner=label("",26)
	column.add_child(region_banner)
	hud=label("",17)
	column.add_child(hud)
	journey_hint=label("",19,Color("ffe2a0"))
	column.add_child(journey_hint)
	progress_widget=ProgressBar.new()
	progress_widget.custom_minimum_size=Vector2(0,5)
	progress_widget.show_percentage=false
	column.add_child(progress_widget)
	var controls:=label("01：W 前进 · A/D 左右 · 空格跳跃    02：上 前进 · 左/右 左右 · 回车跳跃\n松开停步 · S/下 不后退 · Esc 暂停 · R 重开本关 · F1 素材署名",16)
	controls.position=Vector2(24,652)
	controls.name="ControlsHint"
	canvas.add_child(controls)
	panel=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position=Vector2(200,130)
	panel.size=Vector2(880,470)
	canvas.add_child(panel)
	var panel_style:=StyleBoxFlat.new()
	panel_style.bg_color=Color(0.035,0.05,0.045,0.95)
	panel_style.content_margin_left=24
	panel_style.content_margin_right=24
	panel_style.content_margin_top=18
	panel_style.content_margin_bottom=18
	panel.add_theme_stylebox_override("panel",panel_style)
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
	var modes:=HBoxContainer.new()
	inner.add_child(modes)
	for entry in [["solo","单人＋人机"],["local","本地双人"],["online","远程双人"]]:
		var button:=Button.new()
		button.text=entry[1]
		button.set_meta("mode",entry[0])
		button.pressed.connect(func():choose_mode(entry[0]))
		modes.add_child(button)
		mode_buttons.append(button)
	online_row=HBoxContainer.new()
	inner.add_child(online_row)
	net_address=LineEdit.new()
	net_address.custom_minimum_size=Vector2(600,42)
	net_address.placeholder_text="服务器地址，例如 wss://网页所在主机/ws"
	net_address.text=NetClient.page_default_address()
	if net_address.text.is_empty():net_address.text="ws://127.0.0.1:24681"
	online_row.add_child(net_address)
	net_button=Button.new()
	net_button.text="连接队友"
	net_button.pressed.connect(toggle_online)
	online_row.add_child(net_button)
	net_status=label("远程双人：两人连接同一个地址",16)
	inner.add_child(net_status)
	pause_button=Button.new()
	pause_button.text="暂停 / 继续"
	pause_button.position=Vector2(1100,20)
	pause_button.pressed.connect(func():command("pause"))
	canvas.add_child(pause_button)
	var choice:=HBoxContainer.new()
	inner.add_child(choice)
	for name in ["简单","普通","困难"]:
		var button:=Button.new()
		button.text=name
		button.pressed.connect(func():
			command("difficulty",name))
		choice.add_child(button)
		difficulty_buttons.append(button)

func reset_journey_views() -> void:
	built_chapter=-1
	sound_events.clear()
	buddy.reset()
	clear_controls()
	if is_instance_valid(touch):touch.reset()

func apply_journey_primary() -> void:
	match run.state:
		"start": run.state="running";run.reset_input()
		"paused": run.pause()
		"failed":
			if not run.restore_checkpoint(): run.retry(true)
			reset_journey_views()
		"complete": run.new_campaign();reset_journey_views()
	clear_controls()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode==KEY_ESCAPE:
		command("pause")
	elif event.keycode==KEY_R and run.state in ["running","failed","paused"]:
		command("retry")
	elif event.keycode==KEY_ENTER and run.state in ["start","failed","complete"]: journey_primary()
	elif event.keycode==KEY_F1:
		if run.state in ["running","rescue"]: command("pause")
		elif run.state=="start":run.paused_from="start";run.state="paused"
		title.text="素材与制作"
		subtitle.text="角色、松树、草与灌木：Quaternius，CC0。\n扫描地面与石材、天空：Poly Haven，CC0。\n工业建筑：Kenney，CC0。\n房屋、野猪、推车、水车、门与吊桥：项目 Blender 制作脚本。\n字体：Noto Sans SC，SIL OFL 1.1。\n完整来源与修改记录见 ASSET_SOURCES.md。"
		set_meta("credits",true)

func journey_primary() -> void:
	command("primary")

func choose_mode(value:String)->void:
	if run.state!="start" or net.active():return
	play_mode=value
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
		"retry":run.retry(run.state=="failed");reset_journey_views()
		"difficulty":
			if run.state=="start" and not net.active():run.set_difficulty(arg);reset_journey_views()

func sample_local_input()->Dictionary:
	if not input_override.is_empty():return input_override
	var first:=Vector2(float(key_down(KEY_D))-float(key_down(KEY_A)),float(key_down(KEY_W)))
	var second:=Vector2(float(key_down(KEY_RIGHT))-float(key_down(KEY_LEFT)),float(key_down(KEY_UP)))
	var jump:bool=key_down(KEY_SPACE)
	if is_instance_valid(touch):
		if touch.move!=Vector2.ZERO:first=Vector2(touch.move.x,maxf(0,touch.move.y))
		jump=jump or touch.take_jump()
	if play_mode=="online":
		first=Vector2(float(key_down(KEY_D) or key_down(KEY_RIGHT))-float(key_down(KEY_A) or key_down(KEY_LEFT)),float(key_down(KEY_W) or key_down(KEY_UP))) if not touch_device else first
		jump=jump or key_down(KEY_ENTER)
	return {"a":first,"b":second,"ja":jump,"jb":key_down(KEY_ENTER)}

func _physics_process(delta: float) -> void:
	if web_test_mode:return
	touch.set_enabled(touch_device and play_mode!="local" and run.state in ["running","rescue","settlement"])
	if net.active():
		online_process(delta)
		return
	var input:=sample_local_input()
	var second:Vector2=input.b
	var second_jump:bool=input.jb
	if play_mode=="solo":
		var choice:Dictionary=buddy.think(run,delta,input.a,input.ja)
		second=choice.move;second_jump=choice.jump
	var before:String=run.state
	run.step(delta,input.a,second,input.ja,second_jump)
	if run.state!=before:
		clear_controls()
		if run.state=="running":reset_journey_views()
	frame_delta=delta
	sync_view()
	pump_ambience(delta)

func online_process(delta:float)->void:
	if not net.in_match:
		sync_view()
		return
	var input:=sample_local_input()
	net.send_input(input.a,input.ja)
	var applied:=0
	var start:=Time.get_ticks_usec()
	while not net.frames.is_empty() and applied<4:
		var index:int=net.next_frame
		var frame:Dictionary=net.take_frames(1)[0]
		var seen:={}
		for entry in frame.cmds:
			var key:=str(entry[1])+":"+str(entry[2])
			if not seen.has(key):apply_command(entry[1],entry[2]);seen[key]=true
		var before:String=run.state
		run.step(Run.FIXED_STEP*2,frame.a,frame.b,frame.ja,frame.jb)
		if run.state!=before:clear_controls()
		net.report(index,run.sync_hash())
		online_frame_applied.emit(index)
		applied+=1
		if Time.get_ticks_usec()-start>6000:break
	frame_delta=delta
	sync_view()
	pump_ambience(delta)

func start_online_match(seed:int)->void:
	play_mode="online"
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
		run.new_campaign();run.state="start"
		reset_journey_views()
		net_status.text="已断开，可重新连接或选择单人模式"
	else:
		play_mode="online"
		net.connect_to(net_address.text)
	update_journey_ui()

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
		shadows[i].position=Vector3(point.x/SCALE,0.02,-point.y/SCALE)
		shadows[i].scale=Vector3.ONE*(1.0-run.heights[i]/Run.JUMP_APEX*0.35)
		if i<animation_players.size():
			var action:String=run.actions[i]
			if run.state=="start" or run.state in ["settlement","complete"]: action="Idle"
			play_action(animation_players[i],action)
			animation_players[i].speed_scale=0 if run.state=="paused" else (1.1 if action=="Run" else 1.0)
	var path:Array[Vector3]=[]
	var points:PackedVector2Array=run.rope.physical_path()
	var zs:PackedFloat32Array=run.rope.physical_heights()
	for n in range(points.size()): path.append(Vector3(points[n].x/SCALE,zs[n]/SCALE,-points[n].y/SCALE))
	if path.size()>1: rope_view.simulate(path,0,Color.WHITE,0)
	camera.transform=camera_home
	camera.position.z=camera_home.origin.z-run.distance/SCALE
	var theme:String=run.theme_at(run.distance)
	var dark:=theme in ["forest","mine"]
	canopy_light.light_energy=lerpf(canopy_light.light_energy,0.7 if dark else 1.8,clampf(frame_delta*0.8,0,1))
	world_environment.fog_light_color=world_environment.fog_light_color.lerp(Color("405546") if dark else Color("a6b1a1"),clampf(frame_delta,0,1))
	for chunk in world_chunks.values():
		for node in chunk.get_children():
			if node.has_meta("wind"):node.rotation.z=sin(run.elapsed*1.1+float(node.get_meta("wind")))*0.008
	sync_journey_rewards()
	update_journey_ui()
	publish_web_verification()

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

func update_journey_ui() -> void:
	if not is_instance_valid(hud): return
	var mode_name:String={"solo":"单人＋人机","local":"本地双人","online":"远程双人"}[play_mode]
	for button in mode_buttons:
		button.visible=run.state=="start"
		button.disabled=net.active()
		button.text=("✓ " if button.get_meta("mode")==play_mode else "")+{"solo":"单人＋人机","local":"本地双人","online":"远程双人"}[button.get_meta("mode")]
	online_row.visible=play_mode=="online" and run.state in ["start","paused"]
	net_status.visible=play_mode=="online"
	net_button.text="断开连接" if net.active() else "连接队友"
	net_address.editable=not net.active()
	primary.disabled=play_mode=="online" and not net.in_match
	region_banner.text="%d / 3   %s  ·  %s"%[run.level_index+1,run.CHAPTERS[run.level_index].name,run.zone_name()]
	hud.text="%.0f / %.0f 米  ·  绳索 %.2f 米  ·  金币 %d  ·  奖品 %d  ·  护盾 %s"%[run.progress()/SCALE,run.finish_distance()/SCALE,run.rope.length/SCALE,run.coins,run.prizes,"有" if run.shield else "无"]
	hud.text+=" · "+mode_name
	if play_mode=="online" and net.in_match:hud.text+=" · 你是 %02d"%(net.role+1)
	journey_hint.text=run.active_hint()
	if play_mode=="solo":journey_hint.text+=" · 人机："+buddy.feedback
	progress_widget.value=run.progress()/run.finish_distance()*100
	panel.visible=run.state in ["start","paused","failed","settlement","complete"]
	primary.visible=run.state!="settlement"
	for button in difficulty_buttons: button.visible=run.state=="start" and play_mode!="online"
	if get_meta("credits",false) and run.state=="paused": return
	set_meta("credits",false)
	match run.state:
		"start":
			title.text="共生连线 · 连续旅程"
			subtitle.text="穿过森林与村庄，再沿河谷进入矿道。\n两人主动按键前进，松手停步，只能向前或左右移动。\n单人：W/A/D＋空格，人机操作 02；触屏左侧移动、右侧跳跃。\n本地双人：02 使用 上/左/右＋回车；远程双人各控一人。\n倒树、野猪与村民都会预警。共同绕行，保护连接绳索。\n区域入口自动存档，出口需要供能和双人踏板。"
			primary.text="共同出发"
		"paused": title.text="旅程暂停";subtitle.text="人物、危险与计时均已暂停。\n恢复后请松开旧按键再操作。";primary.text="继续旅程"
		"failed": title.text="两人共同重试";subtitle.text=run.reason+"\n回到本区域的安全存档点，危险与奖励恢复原状态。";primary.text="从存档点继续"
		"settlement":
			title.text="共同抵达 · "+run.CHAPTERS[run.level_index].name
			subtitle.text="本关 %.1f 秒 · 金币 %d · 奖品 %d\n松开按键，再分别确认：01 空格 %s，02 回车 %s。"%[run.elapsed,run.coins,run.prizes,"✓" if run.confirmations[0] else "待确认","✓" if run.confirmations[1] else "待确认"]
		"complete": title.text="归航完成";subtitle.text="三段旅程全部完成。团队总分：%d。\n重新开始会清空本轮成绩。"%run.total_score();primary.text="重新出发"
	if run.state=="rescue": journey_hint.text="有人坠落！两人连按各自跳跃键，合力把队友拉上来。"

func build_ambience() -> void:
	ambient=AudioStreamPlayer.new()
	ambient.volume_db=-23
	add_child(ambient)
	# 缓存有限 PCM 循环，避免流式生成器在退出时遗留音频播放句柄。
	for kind in ["wind","forest","river"]:
		var stream:AudioStreamWAV=sfx.render(7.0,func(t):return ambience_wave(t,kind))
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin=0
		stream.loop_end=7*22050
		ambience_streams[kind]=stream

func ambience_wave(t:float,kind:String)->float:
	var wind:=sin(t*TAU*49)*sin(t*TAU*65)*0.08+sin(t*TAU*112)*0.03
	var bird:=0.0
	if kind=="forest" and t<0.35:bird=sin(t*(3100+sin(t*36)*600))*sin(t/0.35*PI)*0.18
	var water:=sin(t*TAU*101)*sin(t*TAU*67)*0.12 if kind=="river" else 0.0
	return wind+bird+water

func pump_ambience(_delta: float) -> void:
	if not is_instance_valid(ambient):return
	var theme:String=run.theme_at(run.distance)
	var kind:="forest" if theme in ["forest","edge","meadow","farm"] else ("river" if theme=="river" else "wind")
	if ambience_region!=kind:
		ambient.stream=ambience_streams[kind]
		ambient.play()
		ambience_region=kind
	ambient.stream_paused=run.state!="running"

# 资源动画由生产时间采样；暂停、存档恢复和重试均与物理相位一致。
func sample_animation(node:Node,token:String,time:float)->void:
	if node is AnimationPlayer:
		for clip in node.get_animation_list():
			if token in clip:
				var animation:Animation=node.get_animation(clip)
				node.play(clip)
				node.seek(fposmod(time,animation.length) if token in ["Charge","WheelTurn"] else clampf(time,0,animation.length),true)
				node.pause()
	for child in node.get_children():sample_animation(child,token,time)

func sync_static_hazards()->void:
	for i in range(run.kinds.size()):
		var kind:String=run.kinds[i]
		if kind not in ["rail","pillar"]:continue
		var rect:Rect2=run.obstacles[i]
		if absf(rect.position.y-run.distance)>4200:
			if static_views.has(i):static_views[i].queue_free();static_views.erase(i)
			continue
		if not static_views.has(i):
			var view:=Node3D.new()
			road.add_child(view)
			if kind=="rail":
				var log:=cylinder(view,Vector3(0,0.3,0),0.3,rect.size.x/SCALE,material("log",Color("67482a")))
				log.rotation.z=PI/2
			else:cylinder(view,Vector3(0,1.2,0),rect.size.x/SCALE/2,2.4,material("stump",Color("59412d")))
			static_views[i]=view
		static_views[i].position=Vector3(rect.get_center().x/SCALE,0,-rect.get_center().y/SCALE)

# 仅在 ?verify=1 下提供只读状态，用于独立 headless WebAssembly 验收。
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
	var payload:={"build":WEB_BUILD,"protocol":NetClient.Relay.PROTOCOL,"mode":play_mode,"state":run.state,"chapter":run.level_index,"zone":run.zone_name(),"progress":run.progress(),"a":[run.a.position.x,run.a.position.y],"b":[run.b.position.x,run.b.position.y],"height":run.heights,"ai":buddy.feedback,"network":net.in_match,"desynced":net.desynced,"role":net.role,"network_frame":net.next_frame,"nodes":get_tree().get_node_count(),"fps":Engine.get_frames_per_second(),"controls":buttons}
	JavaScriptBridge.eval("window.__ctJourney="+JSON.stringify(payload),true)

func control_rect(control:Control)->Array:
	var rect:=control.get_global_rect()
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]
