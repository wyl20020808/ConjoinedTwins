extends RefCounted

# 复用场景材质；怪物、血条与反馈都由模拟时间驱动，无逐怪物 _process / Tween。
# Tripo 文生 3D 静态模型（约 5.7k 三角面、1024 贴图）：[路径, 缩放, 实际高度(米)]。
# 原生最长边为 1、朝向 +X、脚底在原点；人形原生高 1，狼原生高约 0.73。
# rigged/ 下是 build-tools/journey/rig_npcs.py 自动绑定并手写动作（Idle/Walk/Run/Attack/Hit）后的版本。
const SCANNED := {
	"briar":["res://assets/monsters/rigged/bark_sprite.glb",2.5,2.5],
	"raider":["res://assets/monsters/rigged/raider.glb",3.1,3.1],
	"sentinel":["res://assets/monsters/rigged/stone_guard.glb",3.7,3.7],
	"archer":["res://assets/monsters/rigged/raider_slinger.glb",3.0,3.0],
	"dasher":["res://assets/monsters/rigged/brute_charger.glb",3.2,3.2],
	"wolf":["res://assets/monsters/rigged/grey_wolf.glb",2.8,2.0],
	# 2026-10-21 第二批：原生高度 根须蛛 0.70、地精 1.0、钳甲兵 0.98（最长边为 1）。
	"root_spider":["res://assets/monsters/rigged/root_spider.glb",2.6,1.8],
	"goblin_bomber":["res://assets/monsters/rigged/goblin_bomber.glb",2.4,2.4],
	"river_crab_knight":["res://assets/monsters/rigged/river_crab_knight.glb",3.6,3.5],
}
# 狼与树精的模型原生朝 +Z（其余朝 +X）。原先统一转 -90°，导致它们一直侧身朝玩家移动。
const NATIVE_FORWARD_Z := ["wolf","briar"]
const LOOPING := ["Idle","Walk","Run"]
# 命中碎屑颜色：树精木屑、石卫石粉、狼灰毛，其他怪物溅土。
# 命中停顿：只冻结被击中敌人的姿势（普通命中 50 ms、击败 90 ms），模拟和其余画面照常推进。
const HIT_STOP := 0.05
const KILL_STOP := 0.09
# 画面击退：沿射击方向后移最多 0.28 米，0.2 秒回位；碰撞仍按模拟位置。
const KNOCKBACK := 0.28
const KNOCKBACK_TIME := 0.2
# 转身追随速度（每秒）与转弯侧倾系数。
const TURN_RATE := 9.0
const TURN_LEAN := 0.05
# 特效只给离玩家较近的敌人（道路单位），远处不占粒子池。
const FX_RANGE := 900.0
const RUN_DUST_EVERY := 0.28
const DASH_DUST_EVERY := 0.08
const ALERT_COLORS := {"briar":Color("9bd36a"),"raider":Color("ff8a4a"),"sentinel":Color("8fd0ff"),"archer":Color("d8e27a"),"dasher":Color("ff5a3a"),"wolf":Color("ffcf6a"),
	"root_spider":Color("c7e070"),"goblin_bomber":Color("ffb347"),"river_crab_knight":Color("6fd6e0")}
const HIT_CHIPS := {"briar":Color("7a5532"),"sentinel":Color("8d8a7e"),"wolf":Color("8a8a86"),"root_spider":Color("5e4126"),"river_crab_knight":Color("4b6f86"),"goblin_bomber":Color("4a4f45")}
static var charge_material:ShaderMaterial

static func model_path(archetype: String) -> String:
	return SCANNED[archetype][0] if SCANNED.has(archetype) else ""

static func make_monster(game, parent: Node3D, archetype: String) -> Node3D:
	if SCANNED.has(archetype) and ResourceLoader.exists(SCANNED[archetype][0]):
		return make_scanned(parent,archetype)
	var models:Dictionary=game.get_meta("enemy_models",{})
	if models.has(archetype):
		var instance:Node3D=models[archetype].instantiate();parent.add_child(instance);return instance
	var actor := Node3D.new();actor.name="Monster";parent.add_child(actor)
	var color: Color={"briar":Color("617648"),"raider":Color("9a5342"),"sentinel":Color("647b88"),"archer":Color("4e6449"),"dasher":Color("88533c"),"wolf":Color("777b75")}.get(archetype,Color("6b6b5a"))
	var hide: Material=game.material("monster_"+archetype,color)
	var dark: Material=game.material("monster_dark",Color("293537"))
	var trim: Material=game.material("monster_trim",Color("c6ad77"))
	var glow: Material=game.material("monster_eyes",Color("ffcc68"),1.4)
	if archetype=="wolf":
		volume(actor,Vector3(0,.95,-.15),Vector3(.95,1.1,1.85),hide)
		volume(actor,Vector3(0,1.35,.75),Vector3(.8,.9,.9),hide)
		volume(actor,Vector3(0,1.12,1.28),Vector3(.5,.4,.65),dark)
		for side in [-1,1]:
			var ear:Node3D=game.box(actor,Vector3(side*.28,1.86,.7),Vector3(.23,.5,.28),dark);ear.rotation.z=-side*.2
			game.box(actor,Vector3(side*.27,1.4,1.12),Vector3(.13,.09,.07),glow)
			for front in [false,true]:
				var leg:=Node3D.new();actor.add_child(leg)
				leg.name=("Left" if side<0 else "Right")+("Arm" if front else "Leg")
				leg.position=Vector3(side*.36,.85,.5 if front else -.85)
				volume(leg,Vector3(0,-.36,.03),Vector3(.25,.8,.3),hide)
		var tail:Node3D=game.box(actor,Vector3(0,.9,-1.3),Vector3(.3,.3,1.1),hide);tail.rotation.x=-.35
		cache_model(game,actor,archetype)
		return actor
	volume(actor,Vector3(0,1.5,0),Vector3(1.25,1.6,.9),hide)
	game.box(actor,Vector3(0,1.35,.4),Vector3(.8,.55,.09),dark)
	volume(actor,Vector3(0,2.45,.12),Vector3(1.1,.95,.95),hide)
	game.box(actor,Vector3(0,2.4,.54),Vector3(.8,.23,.08),dark)
	for side in [-1,1]:
		game.box(actor,Vector3(side*.23,2.42,.6),Vector3(.18,.12,.06),glow)
		var leg:=Node3D.new();leg.name="LeftLeg" if side==-1 else "RightLeg"
		actor.add_child(leg);leg.position=Vector3(side*.35,.85,0)
		game.box(leg,Vector3(0,-.45,.05),Vector3(.36,.8,.48),dark)
		var arm:=Node3D.new();arm.name="LeftArm" if side==-1 else "RightArm"
		actor.add_child(arm);arm.position=Vector3(side*.7,2.0,0)
		game.box(arm,Vector3(0,-.4,0),Vector3(.35,1.0,.4),hide)
		game.box(arm,Vector3(0,-.9,.05),Vector3(.46,.32,.48),trim)
		if archetype=="briar":
			var horn:Node3D=game.cylinder(actor,Vector3(side*.45,3.05,.03),.12,.9,trim)
			horn.rotation.z=-side*.4
		elif archetype=="sentinel":
			game.box(actor,Vector3(side*.75,2.1,0),Vector3(.6,.45,.85),trim)
		else:
			game.box(actor,Vector3(side*.61,2.5,.12),Vector3(.22,.34,.8),dark)
	if archetype=="raider":
		game.box(actor,Vector3(0,2.85,.13),Vector3(1.14,.16,.9),trim)
		var scarf:Node3D=game.box(actor,Vector3(.45,1.9,-.25),Vector3(.28,.9,.13),hide)
		scarf.rotation.z=-.3
	elif archetype=="sentinel":
		game.box(actor,Vector3(0,2.95,.08),Vector3(.3,.4,.65),glow)
	elif archetype=="archer":
		var bow:=Node3D.new();bow.name="Bow";actor.get_node("LeftArm").add_child(bow);bow.position=Vector3(0,-.8,.2)
		for n in range(7):
			var a:float=-1.2+n*.4
			var segment:Node3D=game.box(bow,Vector3(0,sin(a)*.8,cos(a)*.3),Vector3(.09,.37,.09),trim);segment.rotation.x=a*.4
		game.box(bow,Vector3(0,0,.1),Vector3(.025,1.5,.025),dark)
		game.box(actor,Vector3(.35,1.8,-.6),Vector3(.4,1.1,.4),dark)
	elif archetype=="dasher":
		game.box(actor,Vector3(0,2.8,.1),Vector3(1.2,.5,1),trim)
		for side in [-1,1]:
			game.box(actor,Vector3(side*.85,2.15,.1),Vector3(.65,.65,.9),dark)
	cache_model(game,actor,archetype)
	return actor

# 扫描模型没有骨骼：四肢关节为空节点以兼容同步逻辑，步态改由 Figure 整体摇摆/前倾表现。
# 同类实例共享导入后的网格与贴图资源。
static func make_scanned(parent: Node3D, archetype: String) -> Node3D:
	var actor := Node3D.new();actor.name="Monster";parent.add_child(actor)
	var figure:Node3D=load(SCANNED[archetype][0]).instantiate();figure.name="Figure"
	figure.scale=Vector3.ONE*SCANNED[archetype][1]
	figure.rotation.y=0.0 if archetype in NATIVE_FORWARD_Z else -PI/2
	actor.add_child(figure)
	var players:=figure.find_children("*","AnimationPlayer",true,false)
	if not players.is_empty():
		var player:AnimationPlayer=players[0]
		for clip in player.get_animation_list():
			if clip.get_slice("|",clip.get_slice_count("|")-1) in LOOPING:
				player.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
		player.speed_scale=0.0
		actor.set_meta("anim",player)
	for limb in ["LeftLeg","RightLeg","LeftArm","RightArm"]:
		var joint:=Node3D.new();joint.name=limb;actor.add_child(joint)
	actor.set_meta("figure_height",SCANNED[archetype][2])
	return actor

# 静态躯干按材质合并，四肢保留独立关节；同类实例共享网格资源。
static func cache_model(game,actor:Node3D,archetype:String)->void:
	var groups:={}
	for child in actor.get_children():
		if not child is MeshInstance3D:continue
		var mat:Material=child.material_override
		if not groups.has(mat):
			var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES);groups[mat]=tool
		groups[mat].append_from(child.mesh,0,child.transform)
		child.free()
	for mat:Material in groups:
		var mesh:=MeshInstance3D.new();mesh.mesh=groups[mat].commit();mesh.material_override=mat;actor.add_child(mesh)
	assign_owner(actor,actor)
	var packed:=PackedScene.new();packed.pack(actor)
	var models:Dictionary=game.get_meta("enemy_models",{});models[archetype]=packed;game.set_meta("enemy_models",models)

static func assign_owner(node:Node,owner_node:Node)->void:
	for child in node.get_children():
		child.owner=owner_node;assign_owner(child,owner_node)

static func volume(parent:Node3D,position:Vector3,size:Vector3,mat:Material)->void:
	var mesh:=MeshInstance3D.new();var shape:=SphereMesh.new()
	shape.radius=.5;shape.height=1;shape.radial_segments=8;shape.rings=4
	mesh.mesh=shape;mesh.material_override=mat;mesh.position=position;mesh.scale=size
	parent.add_child(mesh)

static func meshes(node: Node, result: Array) -> void:
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): meshes(child,result)

static func panel(game, parent: Node3D, name: String, size: Vector2, color: Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=name
	var quad:=QuadMesh.new();quad.size=size;node.mesh=quad
	var mat:StandardMaterial3D=game.material("enemy_ui_"+color.to_html(),color)
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override=mat;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func prepare(game, view: Node3D, event: Dictionary) -> void:
	var body:Node3D=view.get_node("Monster" if event.kind=="monster" else ("Villager" if event.kind=="stone" else "Body"))
	var parts:Array=[];meshes(body,parts)
	view.set_meta("enemy_meshes",parts)
	view.set_meta("enemy_body",body)
	view.set_meta("enemy_scale",body.scale)
	view.set_meta("enemy_rotation",body.rotation)
	view.set_meta("bar_height",body.get_meta("figure_height",2.9)+.6)
	view.set_meta("last_hit_at",-1.0)
	view.set_meta("hit_flash",false)
	var health:=Node3D.new();health.name="EnemyHealth";view.add_child(health)
	panel(game,health,"Back",Vector2(3.35,.26),Color("0d1418"))
	var fill:=panel(game,health,"Fill",Vector2(3.2,.13),Color("a9d39b"));fill.position.z=.02
	var title:Label3D=game.add_sign(health,"",Vector3(0,.7,0),28);title.name="Title";title.pixel_size=.03
	var damage:Label3D=game.add_sign(view,"",Vector3.ZERO,30);damage.name="HitNumber";damage.pixel_size=.03;damage.modulate=Color("fff1b5")
	var burst:=Node3D.new();burst.name="HitBurst";view.add_child(burst)
	for angle in [PI/4,-PI/4]:
		var ray:=panel(game,burst,"Spark",Vector2(.75,.09),Color("ffe8a0"));ray.rotation.z=angle

# 骨骼动作完全由模拟量决定播放位置（不让动画自己走时间）：暂停自然定格，脚步与移动相位同步。
# 走/跑用移动相位 stride；预警期播攻击的蓄力段，出手期播挥击段；受击与倒地播 Hit。
static func sync_animation(run, actor: Node3D, event: Dictionary, died: bool, hit_age: float) -> void:
	var player:AnimationPlayer=actor.get_meta("anim")
	var figure:Node3D=actor.get_node("Figure")
	figure.rotation.x=0.0;figure.rotation.z=0.0
	actor.rotation.x=0.0
	var moving:bool=event.get("velocity",Vector2.ZERO).length_squared()>1 and not died
	var clip:="Idle"
	var phase:=fposmod(run.elapsed*0.5+float(event.id)*0.37,1.0)
	if died or hit_age<.32:
		clip="Hit";phase=clampf((hit_age if not died else run.elapsed-event.get("defeated_at",run.elapsed))/.32,0,1)
	elif event.phase=="warning":
		clip="Attack";phase=clampf((run.elapsed-event.trigger)/run.Monsters.profile(event).windup,0,1)*.45
	elif event.phase=="active":
		var start:float=event.trigger+run.Monsters.profile(event).windup
		clip="Attack";phase=.45+clampf((run.elapsed-start)/.5,0,1)*.55
	elif moving:
		clip="Run" if run.Monsters.charges(event) else "Walk"
		phase=fposmod(event.get("stride",0.0)/TAU,1.0)
	var name:String=actor.get_meta("anim_names",{}).get(clip,"")
	if name.is_empty():
		for candidate in player.get_animation_list():
			if candidate.get_slice("|",candidate.get_slice_count("|")-1)==clip:name=candidate
		var names:Dictionary=actor.get_meta("anim_names",{});names[clip]=name;actor.set_meta("anim_names",names)
	if name.is_empty():return
	if player.current_animation!=name:player.play(name)
	player.seek(phase*player.current_animation_length,true)

# 怪物特效：察觉玩家时扬尘加光环；奔跑扬尘（四足与冲锋者更密）；近战出手时在落点冲击加碎屑；
# 冲锋、扑咬途中拖尘；弓手放箭时手部火花。全部按模拟状态的变化沿触发一次，只读状态。
static func monster_fx(game, view: Node3D, event: Dictionary, location: Vector3, moving: bool, died: bool) -> void:
	var run=game.run
	var fx=game.get("fx")
	if fx==null or died: return
	var near:bool=absf(event.y-maxf(run.a.position.y,run.b.position.y))<FX_RANGE
	var feet:=location+Vector3(0,0.05,0)
	var alerted:bool=event.get("alert",false)
	if alerted and not view.get_meta("fx_alert",false) and near:
		fx.burst("dust",feet)
		fx.impact(location,ALERT_COLORS.get(event.archetype,Color("ffb35a")),1.3,0.0,false)
	view.set_meta("fx_alert",alerted)
	if not near: return
	var phase:String=event.get("phase","")
	var seq:int=event.get("attack_seq",0)
	var charging:bool=run.Monsters.charges(event) and phase=="active"
	var every:float=DASH_DUST_EVERY if charging else RUN_DUST_EVERY
	if (moving or charging) and (run.Monsters.charges(event) or event.archetype=="briar" or charging) and run.elapsed-float(view.get_meta("fx_dust_at",-10.0))>=every:
		view.set_meta("fx_dust_at",run.elapsed)
		fx.burst("dust",feet)
	if phase=="active" and view.get_meta("fx_active_seq",-1)!=seq:
		view.set_meta("fx_active_seq",seq)
		if run.Monsters.ranged(event):
			fx.burst("spark",location+Vector3(0,2.2,0))
		elif not run.Monsters.charges(event):
			var land:Vector2=event.get("landing",event.origin)
			var ground:=Vector3(land.x/20.0,run.surface_at(land,run.elapsed).height/20.0,-land.y/20.0)
			fx.impact(ground,Color("ffcf9a"),2.2 if event.archetype in ["sentinel","river_crab_knight"] else 1.6,1.2)
			var hazard_fx=game.get("hazard_fx")
			if hazard_fx!=null: hazard_fx.burst_debris(ground+Vector3(0,0.15,0),HIT_CHIPS.get(event.archetype,Color("6b5843")),0.45)

static func sync(game, view: Node3D, event: Dictionary) -> void:
	var run=game.run
	if not view.has_node("EnemyHealth"): prepare(game,view,event)
	var died:bool=event.hp<=0
	var death_age:float=run.elapsed-event.get("defeated_at",-10.0)
	if died and death_age>.48:
		view.hide();return
	# 不把加载队列中尚未进入显示窗口的敌人重新显示出来。
	if not game.model_visible(event.y): return
	# 模拟窗口外的敌人尚未行动，静止远景只初始化一次；进入近景立即恢复动画。
	var far:bool=event.kind=="monster" and absf(event.y-run.distance)>1400
	if far and view.get_meta("enemy_far_ready",false):return
	view.set_meta("enemy_far_ready",far)
	var point:Vector2=run.Combat.enemy_position(event)
	var location:=Vector3(point.x/20,0,-point.y/20)
	var actor:Node3D=view.get_meta("enemy_body")
	actor.rotation=view.get_meta("enemy_rotation");actor.scale=view.get_meta("enemy_scale")
	if event.kind=="monster":
		actor.position=Vector3(event.origin.x/20,0,0)
		var target:Vector2=event.get("facing",Vector2(0,-1))
		var stride:float=event.get("stride",0.0)
		var moving:bool=event.get("velocity",Vector2.ZERO).length_squared()>1 and not died
		# 转身平滑：朝向按 TURN_RATE 追随模拟朝向，转弯时身体向内侧倾；只改画面。
		var target_yaw:=atan2(target.x,-target.y)
		var yaw:float=view.get_meta("yaw",target_yaw)
		var dt:float=maxf(0.0,game.frame_delta) if run.state!="paused" else 0.0
		var turned:=lerp_angle(yaw,target_yaw,clampf(dt*TURN_RATE,0.0,1.0))
		var turn_speed:=angle_difference(yaw,turned)/dt if dt>0.0 else 0.0
		view.set_meta("yaw",turned)
		actor.rotation.y=turned
		actor.rotation.z=clampf(-turn_speed*TURN_LEAN,-0.22,0.22)*(1.0 if moving else 0.35)
		var swing:float=sin(stride)*.85 if moving else 0.0
		actor.position.y=run.surface_at(event.origin,run.elapsed).height/20.0+(absf(sin(stride))*.12 if moving else 0.0)
		actor.rotation.x=-.16 if moving else 0.0
		actor.get_node("LeftLeg").rotation.x=swing
		actor.get_node("RightLeg").rotation.x=-swing
		var charge:=sin(clampf((run.elapsed-event.trigger)/run.Monsters.profile(event).windup,0,1)*PI/2) if event.phase=="warning" else 0.0
		actor.get_node("LeftArm").rotation.x=-charge*1.7-swing*.7
		actor.get_node("RightArm").rotation.x=-charge*1.7+swing*.7
		if run.Monsters.ranged(event) and event.phase in ["warning","active"]:
			actor.get_node("LeftArm").rotation.x=-1.5
			actor.get_node("RightArm").rotation.x=-1.5+charge*.65
		elif run.Monsters.charges(event):
			actor.position.y-=charge*.22
			actor.rotation.x=-charge*.3-(.25 if event.phase=="active" else 0.0)
			if event.archetype=="wolf":
				actor.get_node("LeftArm").rotation.x=-swing
				actor.get_node("RightArm").rotation.x=swing
		if actor.has_node("Figure"):
			# Figure 原生朝 +X：绕本地 X 为左右摇摆，绕本地 Z 为前后俯仰（正值后仰蓄力）。
			var figure:Node3D=actor.get_node("Figure")
			figure.rotation.x=swing*.11
			figure.rotation.z=charge*.28
		view.get_node("Body").visible=event.phase=="active" and not died and not run.Monsters.charges(event)
		monster_fx(game,view,event,location,moving,died)
		view.get_node("Hint").hide()
	var hit_age:float=run.elapsed-event.get("hit_at",-10.0)
	var stop:float=KILL_STOP if died else HIT_STOP
	# 停顿期间保留上一帧骨骼姿势，结束后按模拟时间继续，不累计偏差。
	if event.kind=="monster" and actor.has_meta("anim") and not (hit_age>=0.0 and hit_age<stop):sync_animation(run,actor,event,died,hit_age)
	if hit_age>=0.0 and hit_age<KNOCKBACK_TIME and event.kind=="monster":
		var away:Vector2=point-(run.a.position+run.b.position)*0.5
		if away.length_squared()>1.0:
			var push:float=KNOCKBACK*(1.0-smoothstep(0.0,KNOCKBACK_TIME,hit_age))*(1.4 if died else 1.0)
			away=away.normalized()
			actor.position+=Vector3(away.x,0,-away.y)*push
		# 命中瞬间轻微放大再回弹，强调确认感。
		actor.scale*=1.0+0.08*(1.0-smoothstep(0.0,stop*1.6,hit_age))
	# 命中火花与倒地尘爆：按模拟命中/击败时间各触发一次，只读状态。
	var fx=game.get("fx")
	if fx!=null and event.kind=="monster":
		var body_height:float=actor.get_meta("figure_height",2.9)
		if event.get("hit_at",-10.0)>view.get_meta("fx_hit_at",-10.0) and hit_age<.1:
			view.set_meta("fx_hit_at",event.hit_at);fx.burst("spark",location+Vector3(0,body_height*.6,0))
			var hazard_fx=game.get("hazard_fx")
			if hazard_fx!=null:hazard_fx.burst_debris(location+Vector3(0,body_height*.55,0),HIT_CHIPS.get(event.archetype,Color("6b5843")),0.3)
		if died and not view.get_meta("fx_dead",false):
			view.set_meta("fx_dead",true);fx.burst("dust",location+Vector3(0,.1,0))
			fx.impact(location,Color("ffb35a"),3.2,3.5)
			var coop_fx=game.get("coop_fx")
			if coop_fx!=null:
				coop_fx.shard_burst(location+Vector3(0,body_height*.5,0),0.6)
				coop_fx.shard_burst(location+Vector3(0,body_height*.9,0),0.5)
	var flashing:bool=hit_age<.09
	# 蓄力预警：预警阶段叠暖红边缘光，强度随蓄力进度上升；命中闪白优先。
	var windup:=0.0
	if event.kind=="monster" and event.get("phase","")=="warning" and not died:
		windup=clampf((run.elapsed-event.trigger)/run.Monsters.profile(event).windup,0,1)
	var overlay_state:=2 if flashing else (1 if windup>0.0 else 0)
	if overlay_state==1:
		if charge_material==null:
			charge_material=ShaderMaterial.new();charge_material.shader=preload("res://scripts/enemy_charge.gdshader")
		if not view.has_meta("charge_mat"):
			var own:ShaderMaterial=charge_material.duplicate();view.set_meta("charge_mat",own)
		view.get_meta("charge_mat").set_shader_parameter("charge",windup)
	if overlay_state!=view.get_meta("overlay_state",0):
		var overlay:Material=null
		if overlay_state==2:overlay=game.material("enemy_hit_flash",Color("ffe2ad"),.9)
		elif overlay_state==1:overlay=view.get_meta("charge_mat")
		for mesh in view.get_meta("enemy_meshes"): mesh.material_overlay=overlay
		view.set_meta("overlay_state",overlay_state)
		view.set_meta("hit_flash",flashing)
	if hit_age<.2: actor.rotation.x-=sin(hit_age/.2*PI)*.22
	if died:
		actor.show();actor.rotation.x-=smoothstep(0,.45,death_age)*1.2
		actor.scale*=maxf(.01,1.0-smoothstep(.18,.48,death_age))
		view.get_node("Warning").hide();view.get_node("Hint").hide()
	var health:Node3D=view.get_node("EnemyHealth")
	var locked:bool=run.combat.weapons.any(func(w):return not w.is_empty() and w.target==event.id)
	# 满血且未被锁定时不挂血条，减少世界内文字与条状元素。
	health.visible=not died and event.phase!="spent" and absf(point.y-run.distance)<800 and (event.hp<event.max_hp or locked or hit_age<1.0)
	if health.visible:
		health.global_position=location+Vector3(0,view.get_meta("bar_height",3.5)+event.get("ground_height",0.0)/20,0)
		health.global_basis=game.camera.global_basis
		var health_key:Vector2i=Vector2i(event.hp,event.max_hp)
		if view.get_meta("health_key",Vector2i(-1,-1))!=health_key:
			var ratio:=clampf(float(event.hp)/event.max_hp,0,1)
			var fill:MeshInstance3D=health.get_node("Fill");fill.scale.x=maxf(.001,ratio);fill.position.x=-1.6*(1-ratio)
			var color:=Color("a9d39b") if ratio>.5 else (Color("e8c07a") if ratio>.25 else Color("e08a7a"))
			fill.material_override=game.material("enemy_ui_"+color.to_html(),color)
			fill.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			view.set_meta("health_key",health_key)
	var title:Label3D=health.get_node("Title")
	var enemy_name:String=run.Monsters.NAMES[event.archetype] if event.kind=="monster" else ("野猪" if event.kind=="boar" else "投掷者")
	title.visible=locked or hit_age<.4
	title.text=("锁定 · " if locked else "")+enemy_name
	title.modulate=Color("ffe18b") if locked else Color("e8ebe2")
	# 设置里关闭伤害数字时仍保留“击败”提示。
	var number:Label3D=view.get_node("HitNumber");number.visible=hit_age<.4 and (died or game.damage_numbers)
	number.text="击败" if died else "-%d"%event.get("hit_damage",10)
	number.global_position=location+Vector3(0,3.0+hit_age*2,.1)
	number.modulate.a=clampf(1-hit_age/.4,0,1)
	var burst:Node3D=view.get_node("HitBurst");burst.visible=hit_age<.12
	burst.global_position=location+Vector3(0,run.Combat.enemy_height(event)/20,.1)
	burst.global_basis=game.camera.global_basis.scaled(Vector3.ONE*(1+maxf(0,hit_age)*5))
	# 敌人前摇：每次攻击在敌人位置响一声低沉的蓄力，方位可辨。
	if event.kind=="monster" and event.get("phase","")=="warning" and not died and view.get_meta("warned_seq",-1)!=event.get("attack_seq",0):
		view.set_meta("warned_seq",event.get("attack_seq",0))
		game.sfx.play_at("whoosh",location+Vector3(0,1.2,0),-6.0,0.65)
	if hit_age<.2 and event.hit_at!=view.get_meta("last_hit_at"):
		game.sfx.play_at("punch_heavy" if died else "punch",location+Vector3(0,1.4,0),-4.0 if died else -7.0,0.9 if died else 1.05)
	view.set_meta("last_hit_at",event.get("hit_at",-1.0))
