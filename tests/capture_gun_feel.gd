extends SceneTree
# 枪械动作审查截图（需要真实渲染，不能 headless）：抱枪、瞄准、换枪两段、换弹、霰弹枪逐发装填与泵动、
# 丢枪、捡枪、背枪。每组拼成一张对照图，输出到命令行 -- 之后给出的目录。
# 用法：Godot --path . --resolution 960x720 --script res://tests/capture_gun_feel.gd -- 输出目录
var game
var run
var camera:Camera3D
var out_dir:=""
var sheets:={}

func _initialize()->void:call_deferred("capture")

# 每帧两个角度并排：左为正面斜 ¾，右为游戏镜头方向（身后偏上）。
# 换弹与泵动只看正面近景（两格宽）。
const CLOSE:=["reload_smg","reload_shotgun","pump"]
func shot(sheet:String,label:String)->void:
	var pair:=Image.create(960,360,false,Image.FORMAT_RGBA8)
	var close:bool=sheet in CLOSE
	# 窗口失焦会自动暂停：截图前恢复运行并隐藏界面层。
	run.state="running"
	for layer in game.find_children("*","CanvasLayer",true,false):layer.visible=false
	for k in range(1 if close else 2):
		aim_camera(k==1,close)
		game.sync_view()
		await process_frame
		game.sync_view()
		await process_frame
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		if close:image=image.get_region(Rect2i(160,90,640,480))
		image.resize(480 if not close else 960,360 if not close else 720)
		image.convert(Image.FORMAT_RGBA8)
		if close:pair=image
		else:pair.blit_rect(image,Rect2i(0,0,480,360),Vector2i(480*k,0))
	if not sheets.has(sheet):sheets[sheet]=[]
	sheets[sheet].append([label,pair])

# 从左前方看胸口（搭档与绳子在右侧，避开遮挡）。
func aim_camera(behind_view:bool=false,close:bool=false)->void:
	var chest:Vector3=game.combat_view.chest_anchor(0,game.hand_skeletons.get(0)).origin
	var behind:Vector3=((game.camera.global_position-chest)*Vector3(1,0,1)).normalized()
	camera.global_position=chest+(behind.rotated(Vector3.UP,0.35)*3.6+Vector3.UP*1.4 if behind_view else behind.rotated(Vector3.UP,PI*0.62)*3.6+Vector3.UP*0.7)
	if close:camera.global_position=chest+behind.rotated(Vector3.UP,PI*0.7)*3.0+Vector3.UP*0.5
	camera.look_at(chest-Vector3.UP*0.35,Vector3.UP)

func tick()->void:
	run.Combat.tick(run,[run.a.position,run.b.position])

func phase(sheet:String,times:Array,setup:Callable)->void:
	var start:float=run.elapsed
	setup.call()
	for t in times:
		run.elapsed=start+float(t)
		await shot(sheet,"%.2fs"%t)
	run.elapsed=start+2.0
	game.sync_view()

func capture()->void:
	var args:=OS.get_cmdline_user_args()
	out_dir=args[0] if args.size()>0 else "user://gun_feel"
	DirAccess.make_dir_recursive_absolute(out_dir)
	game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.frame_delta=1.0/60
	run=game.run
	for n in range(30):await process_frame
	run.state="running"
	run.combat.pickups.clear()
	camera=Camera3D.new();camera.fov=40;root.add_child(camera);camera.current=true
	aim_camera()
	# 审查只看枪和手：隐藏绳子、粒子特效和搭档。
	game.rope_view.visible=false
	game.fx.visible=false
	game.coop_fx.visible=false
	game.robots[1].visible=false
	run.combat.weapons[0]=run.Combat.gun("smg");run.combat.backups[0]=run.Combat.gun("shotgun")
	for n in range(10):
		game.sync_view();await process_frame
	aim_camera()
	await shot("hold","抱枪 冲锋枪")
	run.combat.fire[0]=true
	for n in range(12):game.sync_view();await process_frame
	await shot("hold","瞄准 冲锋枪")
	run.combat.fire[0]=false
	for type in ["shotgun","flamer","launcher"]:
		run.combat.weapons[0]=run.Combat.gun(type)
		await shot("hold","抱枪 "+type)
	run.combat.weapons[0]=run.Combat.gun("smg")
	# 换枪：冲锋枪收上背、霰弹枪取下来。
	await phase("swap",[0.05,0.12,0.2,0.25,0.32,0.4,0.48,0.55],func():run.combat.swap[0]=true;tick())
	# 冲锋枪空仓换弹（按剩余帧数直接设置进度）。
	run.combat.weapons[0]=run.Combat.gun("smg");run.combat.weapons[0].ammo=0
	run.Combat.start_reload(run,0)
	var smg:Dictionary=run.combat.weapons[0]
	for t in [0.05,0.15,0.25,0.33,0.45,0.55,0.65,0.74,0.85,0.95]:
		smg.reload=int(168*(1.0-t))
		await shot("reload_smg","t=%.2f"%t)
	smg.reload=0;smg.ammo=24
	# 霰弹枪逐发装填一轮，然后泵动。
	run.combat.weapons[0]=run.Combat.gun("shotgun");run.combat.weapons[0].ammo=0
	run.Combat.start_reload(run,0)
	var sg:Dictionary=run.combat.weapons[0]
	for done in [8,20,26,34,42,48,56]:
		sg.reload=60-done
		await shot("reload_shotgun","first shell %d/60"%done)
	sg.reload=0;sg.ammo=6
	var start:float=run.elapsed
	run.combat.shots[0]={"id":777,"type":"shotgun","from":run.a.position,"to":run.a.position+Vector2(0,200),"height":36.0,"target_height":36.0,"time":start,"hit":false}
	for t in [0.02,0.18,0.24,0.3,0.36,0.45]:
		run.elapsed=start+t
		await shot("pump","pump %.2fs"%t)
	run.elapsed=start+2.0
	# 丢枪：手上霰弹枪抛出，背上冲锋枪取下。
	run.combat.weapons[0]=run.Combat.gun("shotgun");run.combat.backups[0]=run.Combat.gun("smg")
	game.sync_view()
	await phase("drop",[0.05,0.12,0.2,0.28,0.36,0.46,0.58],func():run.combat.drop[0]=true;tick())
	# 捡枪：空手捡起拿到手上，再捡一把甩到背上。
	run.combat.weapons[0]={};run.combat.backups[0]={};run.combat.pickups.clear()
	game.sync_view()
	await phase("pickup",[0.03,0.08,0.13,0.2,0.27,0.34],func():run.Combat.add_pickup(run,"gun",run.a.position+Vector2(14,4),{},"smg");tick())
	await phase("stow",[0.04,0.1,0.18,0.26,0.34,0.44],func():run.Combat.add_pickup(run,"gun",run.a.position+Vector2(-14,4),{},"flamer");tick())
	for sheet in sheets:
		var frames:Array=sheets[sheet]
		var columns:=2
		var cell:Vector2i=frames[0][1].get_size()
		var rows:=int(ceil(frames.size()/float(columns)))
		var grid:=Image.create(cell.x*columns,cell.y*rows,false,Image.FORMAT_RGBA8)
		grid.fill(Color.BLACK)
		for n in range(frames.size()):
			var image:Image=frames[n][1]
			image.convert(Image.FORMAT_RGBA8)
			grid.blit_rect(image,Rect2i(Vector2i.ZERO,cell),Vector2i((n%columns)*cell.x,(n/columns)*cell.y))
		grid.save_png(out_dir.path_join(sheet+".png"))
		print("SHEET ",sheet," ",[frames.map(func(f):return f[0])])
	for p in game.sfx.players:p.stop()
	game.queue_free()
	await process_frame
	quit(0)
