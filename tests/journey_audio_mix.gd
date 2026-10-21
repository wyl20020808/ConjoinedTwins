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
		sfx.started_frame.clear()
		sfx.play("gunshot",-10.0,1.0)
		var player:AudioStreamPlayer=sfx.players[(sfx.next_player-1+sfx.players.size())%sfx.players.size()]
		check(player.bus=="SFX" and absf(player.pitch_scale-1.0)<=0.0501 and absf(player.volume_db+10.0)<=2.001,"枪声随机变化在范围内")
		pitches[snappedf(player.pitch_scale,0.001)]=true
	check(pitches.size()>3,"连续播放音高不完全相同")
	sfx.play("click",-8.0)
	check(sfx.players[(sfx.next_player-1+sfx.players.size())%sfx.players.size()].bus=="UI","界面音效走 UI 总线")
	# 同一帧内每个播放器只启动一次，超出池容量的声音直接丢弃。
	sfx.started_frame.clear()
	var cursor:int=sfx.next_player_3d
	for n in range(sfx.POOL_3D+3): sfx.play_at("metal_light",Vector3.ZERO)
	check(sfx.next_player_3d==cursor and sfx.started_frame.size()==sfx.POOL_3D,"同帧最多启动整个定位池一次")
	sfx.started_frame.clear()
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
		sfx.started_frame.clear();var before:int=sfx.next_player_3d
		event.trigger=run.elapsed;event.phase="warning"
		EnemyView.sync(game,view,event)
		check(sfx.next_player_3d!=before,"敌人前摇在敌人位置发声")
		var after:int=sfx.next_player_3d
		EnemyView.sync(game,view,event)
		check(sfx.next_player_3d==after,"同一次攻击不重复发声")
		event.attack_seq+=1;sfx.started_frame.clear();EnemyView.sync(game,view,event)
		check(sfx.next_player_3d!=after,"下一次攻击再次提示")
		event.phase="ready";event.trigger=-1.0
	# 机关阶段切换在机关位置发声。
	var marker:=Node3D.new();game.add_child(marker);marker.global_position=Vector3(2,0,-30)
	game.hazard_fx.track(99999,"press",{"stage":"open","rect":Rect2(0,0,80,80)},marker)
	sfx.started_frame.clear();var quiet:int=sfx.next_player_3d
	game.hazard_fx.track(99999,"press",{"stage":"hold","rect":Rect2(0,0,80,80)},marker)
	var last3d:AudioStreamPlayer3D=sfx.players_3d[(sfx.next_player_3d-1+sfx.players_3d.size())%sfx.players_3d.size()]
	check(sfx.next_player_3d!=quiet and last3d.global_position==marker.global_position and str(last3d.stream.resource_path).contains("impactMetal_heavy"),"压机落下在机关位置播放金属重击")
	marker.queue_free()
	# 录制音效：每组都能加载，同名随机选一条。
	for group in sfx.VARIANTS:
		check(sfx.variants[group].size()==sfx.VARIANTS[group].size() and not sfx.variants[group].has(null),"录制音效组 %s 全部加载"%group)
	var picked:={}
	for n in range(40): picked[sfx.pick("punch")]=true
	check(picked.size()>2,"同名音效随机选取不同录音")
	# 脚步：贴地行走约 1.7 米一步，起跳与落地各一声。
	run.state="running";run.heights[0]=0.0
	game.visual_last_heights[0]=0.0;game.step_travel[0]=0.0;game.step_last[0]=Vector2.INF
	game.robots[0].global_position=Vector3(0,0,-10);game.play_footsteps(0)
	sfx.started_frame.clear();var step_before:int=sfx.next_player_3d
	game.robots[0].global_position=Vector3(0,0,-11);game.play_footsteps(0)
	check(sfx.next_player_3d==step_before,"不足一步不发声")
	sfx.started_frame.clear();game.robots[0].global_position=Vector3(0,0,-11.8);game.play_footsteps(0)
	var foot:AudioStreamPlayer3D=sfx.players_3d[(sfx.next_player_3d-1+sfx.players_3d.size())%sfx.players_3d.size()]
	check(sfx.next_player_3d!=step_before and str(foot.stream.resource_path).contains("footstep"),"走满一步播放脚步录音")
	sfx.started_frame.clear();run.heights[0]=4.0;game.play_footsteps(0);game.visual_last_heights[0]=8.0
	sfx.started_frame.clear();run.heights[0]=0.0;game.play_footsteps(0)
	var landed:AudioStreamPlayer3D=sfx.players_3d[(sfx.next_player_3d-1+sfx.players_3d.size())%sfx.players_3d.size()]
	check(str(landed.stream.resource_path).contains("impactSoft_heavy"),"落地播放落地录音")
	game.visual_last_heights[0]=0.0
	# 战斗时压低环境声，脱战后恢复。
	event.alert=true
	for n in range(60): game.pump_ambience(1.0/60)
	check(is_equal_approx(game.ambience_level,game.AMBIENCE_DUCKED),"附近敌人察觉时环境声压低")
	event.alert=false
	for n in range(240): game.pump_ambience(1.0/60)
	check(is_equal_approx(game.ambience_level,1.0),"脱战后环境声恢复")
	# 章节音乐：探索层按章节选曲并循环，战斗层随敌人察觉淡入淡出，暂停冻结。
	for path in game.MUSIC_EXPLORE+[game.MUSIC_COMBAT]:
		var music:AudioStream=load(path)
		check(music!=null and music.get("loop")==true,"音乐导入为循环 %s"%path.get_file())
	check(game.music_explore.bus=="Music" and game.music_combat.bus=="Music","音乐走 Music 总线")
	run.state="running";run.level_index=0;event.alert=false
	for n in range(240): game.pump_music(1.0/60,false)
	check(game.music_chapter==0 and str(game.music_explore.stream.resource_path).ends_with("forest_ambience.mp3"),"第一章播放森林曲")
	check(is_equal_approx(game.explore_level,1.0) and game.combat_level==0.0,"脱战时只有探索层")
	for n in range(60): game.pump_music(1.0/60,true)
	check(game.combat_level>0.9 and is_equal_approx(game.explore_level,0.6),"战斗时战斗层淡入、探索层降低")
	for n in range(240): game.pump_music(1.0/60,false)
	check(game.combat_level==0.0 and game.music_combat.stream_paused,"脱战后战斗层淡出并暂停")
	run.level_index=2
	for n in range(600): game.pump_music(1.0/60,false)
	check(game.music_chapter==2 and str(game.music_explore.stream.resource_path).ends_with("cathedral_forest.ogg") and game.explore_level>0.9,"换到第三章淡出后换曲再淡入")
	run.pause();game.pump_music(1.0/60,false)
	check(game.music_explore.stream_paused,"暂停时音乐冻结")
	run.pause()
	game.music_explore.stop();game.music_combat.stop()
	for p in sfx.players:p.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("JOURNEY_AUDIO_MIX failures=",failures)
	quit(1 if failures else 0)
