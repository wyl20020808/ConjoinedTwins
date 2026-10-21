extends SceneTree
# 怪物表现：狼头已摆正朝前；转身平滑与侧倾；察觉玩家、近战出手各触发一次特效；远处敌人不占粒子池。
const EnemyView=preload("res://scripts/journey_enemy_view.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:call_deferred("verify")

# 狼的绑骨模型：原模型鼻尖向侧面伸出（侧向约 0.32，身体半宽约 0.16）；摆正后头部前段不再向侧面突出，且到达身体最前端。
func wolf_head_extent()->Vector2:
	var scene:Node3D=load("res://assets/monsters/rigged/grey_wolf.glb").instantiate()
	var top:=-INF;var points:=[]
	for mesh:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		for v:Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var p:Vector3=mesh.transform*v;points.append(p);top=maxf(top,p.y)
	scene.free()
	# glTF 为 Y 向上；绑骨脚本的前方（Blender -Y）导出后为 +Z。
	var side:=0.0;var reach:=-INF
	for p in points:
		if p.y>0.55*top and p.z>0.3: side=maxf(side,absf(p.x));reach=maxf(reach,p.z)
	return Vector2(side,reach)

func verify()->void:
	var head:=wolf_head_extent()
	check(head.x<0.2 and head.y>0.45,"狼头摆正朝前（头部侧向 %.2f、最前 %.2f）"%[head.x,head.y])
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.frame_delta=1.0/60
	var run=game.run
	run.state="running"
	var event:Dictionary={}
	for candidate in run.journey_events:
		if candidate.kind=="monster" and candidate.archetype not in ["archer","dasher","wolf"]: event=candidate;break
	run.distance=event.y-300;run.a.position=Vector2(-42,event.y-300);run.b.position=Vector2(42,event.y-300)
	game.sync_view()
	var view:Node3D=game.event_views.get(event.id)
	check(view!=null,"敌人显示节点存在")
	if view!=null:
		var actor:Node3D=view.get_meta("enemy_body")
		event.facing=Vector2(0,-1);EnemyView.sync(game,view,event)
		var start:float=actor.rotation.y
		event.facing=Vector2(1,0);event.velocity=Vector2(200,0)
		EnemyView.sync(game,view,event)
		var step:float=angle_difference(start,actor.rotation.y)
		check(absf(step)>0.01 and absf(step)<PI/2-0.1,"转身逐帧追随而不是瞬间转向")
		check(absf(actor.rotation.z)>0.01,"转弯时身体侧倾")
		for n in range(120): EnemyView.sync(game,view,event)
		check(absf(angle_difference(actor.rotation.y,atan2(1.0,0.0)))<0.05,"约 2 秒内转到模拟朝向")
		# 察觉玩家：只触发一次光环。
		var rings:int=game.fx.ring_cursor
		event.alert=false;EnemyView.sync(game,view,event)
		event.alert=true;EnemyView.sync(game,view,event)
		var after:int=game.fx.ring_cursor
		check(after!=rings,"察觉玩家时出现光环")
		EnemyView.sync(game,view,event)
		check(game.fx.ring_cursor==after,"持续察觉不重复触发")
		# 近战出手：同一次攻击只在落点冲击一次。
		event.phase="active";event.trigger=run.elapsed-0.8;event.landing=event.origin
		EnemyView.sync(game,view,event)
		var hit:int=game.fx.ring_cursor
		check(hit!=after,"近战出手在落点冲击")
		EnemyView.sync(game,view,event)
		check(game.fx.ring_cursor==hit,"同一次出手不重复冲击")
		event.attack_seq+=1;EnemyView.sync(game,view,event)
		check(game.fx.ring_cursor!=hit,"下一次出手再次冲击")
		# 远处敌人不触发特效。
		event.phase="ready";event.alert=false;EnemyView.sync(game,view,event)
		run.a.position.y=event.y-3000;run.b.position.y=event.y-3000
		var far_ring:int=game.fx.ring_cursor
		event.alert=true;EnemyView.monster_fx(game,view,event,Vector3.ZERO,true,false)
		check(game.fx.ring_cursor==far_ring,"远处敌人不占粒子池")
	for p in game.sfx.players:p.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("JOURNEY_MONSTER_POLISH failures=",failures)
	quit(1 if failures else 0)
