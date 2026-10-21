extends SceneTree
# 混音与定位音效：四条总线与限幅、播放随机变化、世界位置发声、敌人前摇提示、战斗时压低环境声。
const EnemyView=preload("res://scripts/journey_enemy_view.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:call_deferred("verify")

func verify()->void:
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.frame_delta=1.0/60
	var run=game.run
	var sfx=game.sfx
	for name in ["Music","SFX","Ambience","UI"]:
		var index:=AudioServer.get_bus_index(name)
		check(index>0 and AudioServer.get_bus_send(index)=="Master","总线 %s 存在并送往 Master"%name)
	var master:=AudioServer.get_bus_index("Master")
	var limited:=false
	for n in range(AudioServer.get_bus_effect_count(master)):
		if AudioServer.get_bus_effect(master,n) is AudioEffectHardLimiter: limited=true
	check(limited,"Master 有限幅器")
	sfx.ensure_buses()
	check(AudioServer.bus_count==5,"重复初始化不重复建总线")
	check(game.ambient.bus=="Ambience" and game.forest_birds.bus=="Ambience","环境声走 Ambience 总线")
	# 随机变化：音高 ±5%、音量 ±2 dB，路由按音效类别。
	var pitches:={}
	for n in range(12):
		sfx.play("gunshot",-10.0,1.0)
		var player:AudioStreamPlayer=sfx.players[(sfx.next_player-1+sfx.players.size())%sfx.players.size()]
		check(player.bus=="SFX" and absf(player.pitch_scale-1.0)<=0.0501 and absf(player.volume_db+10.0)<=2.001,"枪声随机变化在范围内")
		pitches[snappedf(player.pitch_scale,0.001)]=true
	check(pitches.size()>3,"连续播放音高不完全相同")
	sfx.play("click",-8.0)
	check(sfx.players[(sfx.next_player-1+sfx.players.size())%sfx.players.size()].bus=="UI","界面音效走 UI 总线")
	sfx.play_at("land",Vector3(3,0,-40),-2.0,0.5)
	var spatial:AudioStreamPlayer3D=sfx.players_3d[(sfx.next_player_3d-1+sfx.players_3d.size())%sfx.players_3d.size()]
	check(spatial.global_position==Vector3(3,0,-40) and spatial.stream==sfx.streams.land and spatial.bus=="SFX","定位音效在世界位置播放")
	# 敌人前摇：同一次攻击只响一次。
	run.state="running"
	var event:Dictionary={}
	for candidate in run.journey_events:
		if candidate.kind=="monster": event=candidate;break
	run.distance=event.y-300;run.a.position=Vector2(-42,event.y-300);run.b.position=Vector2(42,event.y-300)
	game.sync_view()
	var view:Node3D=game.event_views.get(event.id)
	check(view!=null,"敌人显示节点存在")
	if view!=null:
		var before:int=sfx.next_player_3d
		event.trigger=run.elapsed;event.phase="warning"
		EnemyView.sync(game,view,event)
		check(sfx.next_player_3d!=before,"敌人前摇在敌人位置发声")
		var after:int=sfx.next_player_3d
		EnemyView.sync(game,view,event)
		check(sfx.next_player_3d==after,"同一次攻击不重复发声")
		event.attack_seq+=1;EnemyView.sync(game,view,event)
		check(sfx.next_player_3d!=after,"下一次攻击再次提示")
		event.phase="ready";event.trigger=-1.0
	# 机关阶段切换在机关位置发声。
	var marker:=Node3D.new();game.add_child(marker);marker.global_position=Vector3(2,0,-30)
	game.hazard_fx.track(99999,"press",{"stage":"open","rect":Rect2(0,0,80,80)},marker)
	var quiet:int=sfx.next_player_3d
	game.hazard_fx.track(99999,"press",{"stage":"hold","rect":Rect2(0,0,80,80)},marker)
	var last3d:AudioStreamPlayer3D=sfx.players_3d[(sfx.next_player_3d-1+sfx.players_3d.size())%sfx.players_3d.size()]
	check(sfx.next_player_3d!=quiet and last3d.global_position==marker.global_position,"压机落下在机关位置发声")
	marker.queue_free()
	# 战斗时压低环境声，脱战后恢复。
	event.alert=true
	for n in range(60): game.pump_ambience(1.0/60)
	check(is_equal_approx(game.ambience_level,game.AMBIENCE_DUCKED),"附近敌人察觉时环境声压低")
	event.alert=false
	for n in range(240): game.pump_ambience(1.0/60)
	check(is_equal_approx(game.ambience_level,1.0),"脱战后环境声恢复")
	for p in sfx.players:p.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("JOURNEY_AUDIO_MIX failures=",failures)
	quit(1 if failures else 0)
