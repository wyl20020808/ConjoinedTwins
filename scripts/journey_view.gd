extends "res://scripts/road_demo.gd"

const Journey = preload("res://scripts/journey_run.gd")
const CHUNK := 80.0
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
const CombatView = preload("res://scripts/journey_combat_view.gd")
@export var training_entry := false
var combat_view: Node3D
var combat_status: Label
var combat_health: ProgressBar
var training_button: Button
var restart_button: Button
var fire_blocked := true
var reload_requested := false
var drop_requested := false
var controls_hint: Label

func _ready() -> void:
	ThemeDB.fallback_font=preload("res://assets/fonts/web_ui_font.tres")
	run.dispose()
	finish_view.free()
	charge_gate_view.free()
	run=Journey.new()
	run.solo_control=true
	if training_entry:
		run.combat_trial=true
		run.retry()
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
	build_journey_ui()
	combat_view=CombatView.new()
	combat_view.game=self
	add_child(combat_view)
	build_ambience()
	sync_view()

func _exit_tree() -> void:
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
				var name:="house_%d"%((number+n)%3)
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
			add_sign(chunk,run.TRIAL_ZONES[zone] if run.combat_trial else run.CHAPTERS[run.level_index].zones[zone],Vector3(-12,4,-y-8),38)
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
	for number in range(maxi(0,current-1),current+4):
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
	add_child(canvas)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",24)
	margin.add_theme_constant_override("margin_top",20)
	margin.add_theme_constant_override("margin_right",24)
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
	combat_status=label("",20,Color("a1ead5"))
	column.add_child(combat_status)
	combat_health=ProgressBar.new()
	combat_health.custom_minimum_size=Vector2(260,12)
	combat_health.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	combat_health.show_percentage=false
	column.add_child(combat_health)
	for text_label in [region_banner,hud,journey_hint,combat_status]:
		text_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		text_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var controls:=label("W / ↑ 前进 · A/D / ←→ 左右 · 空格跳跃 · 松开停步\n鼠标左键射击 · R 换弹 · G 丢枪 · Esc 暂停 · F1 素材署名",16)
	controls.position=Vector2(24,652)
	controls_hint=controls
	canvas.add_child(controls)
	controls.mouse_filter=Control.MOUSE_FILTER_IGNORE
	touch_device=DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	touch=TouchControls.new()
	touch.combat_buttons=true
	canvas.add_child(touch)
	pause_button=Button.new()
	pause_button.text="暂停"
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left=-120
	pause_button.offset_right=-24
	pause_button.offset_top=22
	pause_button.offset_bottom=70
	pause_button.pressed.connect(func():
		run.pause()
		clear_controls())
	canvas.add_child(pause_button)
	controls.visible=not touch_device
	panel=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position=Vector2(240,170)
	panel.size=Vector2(800,360)
	canvas.add_child(panel)
	var inner:=VBoxContainer.new()
	inner.add_theme_constant_override("separation",18)
	panel.add_child(inner)
	title=label("",32)
	inner.add_child(title)
	subtitle=label("",19)
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
		run.retry(run.state=="failed")
		reset_journey_views())
	inner.add_child(restart_button)
	touch.blockers.assign([panel,pause_button])
	var choice:=HBoxContainer.new()
	inner.add_child(choice)
	for name in ["简单","普通","困难"]:
		var button:=Button.new()
		button.text=name
		button.pressed.connect(func():
			run.set_difficulty(name)
			reset_journey_views())
		choice.add_child(button)
		difficulty_buttons.append(button)

func reset_journey_views() -> void:
	built_chapter=-1
	sound_events.clear()
	clear_controls()
	if is_instance_valid(combat_view): combat_view.reset()

func journey_primary() -> void:
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
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode==KEY_ESCAPE:
		run.pause()
		clear_controls()
	elif event.keycode==KEY_R and run.state=="running": reload_requested=true
	elif event.keycode==KEY_G and run.state=="running": drop_requested=true
	elif event.keycode==KEY_ENTER and run.state in ["start","failed","complete"]: journey_primary()
	elif event.keycode==KEY_F1:
		if run.state in ["running","rescue"]: run.pause()
		elif run.state=="start":run.paused_from="start";run.state="paused"
		title.text="素材与制作"
		subtitle.text="角色、松树、草与灌木：Quaternius，CC0。\n扫描地面与石材、天空：Poly Haven，CC0。\n工业建筑：Kenney，CC0。\n房屋、野猪、推车、水车、门与吊桥：项目 Blender 制作脚本。\n字体：Noto Sans SC，SIL OFL 1.1。\n完整来源与修改记录见 ASSET_SOURCES.md。"
		set_meta("credits",true)

func _physics_process(delta: float) -> void:
	touch.set_enabled(touch_device and run.state in ["running","rescue","settlement"])
	var first:=Vector2(float(key_down(KEY_D) or key_down(KEY_RIGHT))-float(key_down(KEY_A) or key_down(KEY_LEFT)),float(key_down(KEY_W) or key_down(KEY_UP)))
	if touch.move!=Vector2.ZERO: first=touch.move
	var touch_jump: bool=touch.take_jump()
	var touch_actions: Dictionary=touch.take_combat()
	var jump: bool=key_down(KEY_SPACE) or touch_jump
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): fire_blocked=false
	var fire: bool=(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not fire_blocked and not touch_device) or touch_actions.fire
	run.set_combat_input(fire,reload_requested or touch_actions.reload,drop_requested or touch_actions.drop)
	reload_requested=false
	drop_requested=false
	var before:String=run.state
	run.step(delta,first,Vector2.ZERO,jump,jump)
	if run.state!=before:
		clear_controls()
		if run.state=="running": reset_journey_views()
	frame_delta=delta
	sync_view()
	pump_ambience(delta)

func clear_controls() -> void:
	super()
	reload_requested=false
	drop_requested=false
	fire_blocked=true

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and is_instance_valid(touch):
		touch_device=true
		touch.set_enabled(run.state in ["running","rescue","settlement"])

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(touch):
		if run.state in ["running","rescue"]: run.pause()
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
	if is_instance_valid(combat_view): combat_view.sync()
	update_journey_ui()

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
	var viewport := get_viewport().get_visible_rect().size
	panel.size.x=minf(800,viewport.x-32)
	panel.position=Vector2((viewport.x-panel.size.x)/2,maxf(12,(viewport.y-panel.size.y)/2))
	controls_hint.position=Vector2(24,viewport.y-68)
	controls_hint.visible=not touch_device
	region_banner.text=("战斗训练 · "+run.zone_name()) if run.combat_trial else "%d / 3   %s  ·  %s"%[run.level_index+1,run.CHAPTERS[run.level_index].name,run.zone_name()]
	hud.text="%.0f / %.0f 米  ·  绳索 %.2f 米  ·  金币 %d  ·  奖品 %d  ·  护盾 %s"%[run.progress()/SCALE,run.finish_distance()/SCALE,run.rope.length/SCALE,run.coins,run.prizes,"有" if run.shield else "无"]
	journey_hint.text=run.active_hint()
	combat_health.value=run.combat.health[0]
	var weapon: Dictionary=run.combat.weapons[0]
	combat_status.text="生命 %d / 100 · 搭档 %d / 100 · 空手 · 自动拾取枪械"%[run.combat.health[0],run.combat.health[1]] if weapon.is_empty() else "生命 %d / 100 · 搭档 %d / 100 · 冲锋枪 %d / %d · %s"%[run.combat.health[0],run.combat.health[1],weapon.ammo,weapon.reserve,"换弹 %.1f 秒"%(weapon.reload*Run.FIXED_STEP) if weapon.reload>0 else "移动 85%"]
	progress_widget.value=run.progress()/run.finish_distance()*100
	panel.visible=run.state in ["start","paused","failed","settlement","complete"]
	primary.visible=true
	training_button.visible=run.state=="start"
	training_button.text="返回三关旅程" if run.combat_trial else "战斗训练 · 持枪步行约 90 秒"
	restart_button.visible=run.state in ["paused","failed"]
	pause_button.visible=run.state in ["running","rescue"]
	if is_instance_valid(touch): touch.set_enabled(touch_device and run.state in ["running","rescue","settlement"])
	for button in difficulty_buttons: button.visible=run.state=="start"
	if get_meta("credits",false) and run.state=="paused": return
	set_meta("credits",false)
	match run.state:
		"start":
			title.text="共生连线 · 战斗训练" if run.combat_trial else "共生连线 · 连续旅程"
			subtitle.text="主动前进，松开停步；搭档自动跟随、共同跳跃与协助机关。\n靠近枪械自动拾取，开火自动锁定前方敌人。\n鼠标左键射击，R 换弹，G 丢枪；持枪移动速度为 85%。\n野猪与投掷攻击扣血；地形与重型机关仍需躲避。\n建议先进入短战斗训练，再开始三关旅程。"
			if touch_device: subtitle.text="左侧滑动移动；右侧大按钮跳跃、按住射击。\n小按钮换弹、丢枪，靠近枪械自动拾取。\n搭档跟随并共同跳跃，踩空时连点跳跃救援。\n可停步观察敌人，持枪移动稍慢；血量耗尽从存档继续。"
			primary.text="开始训练" if run.combat_trial else "出发"
		"paused": title.text="旅程暂停";subtitle.text="人物、危险与计时均已暂停。\n恢复后请松开旧按键再操作。";primary.text="继续旅程"
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
