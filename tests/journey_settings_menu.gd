extends SceneTree
# 设置页、手柄与章节进度条：音量与战斗压低相乘、画质与帧率应用、设置保存兼容旧键、
# 手柄按设备分配角色、提示文字随设备切换、区域名淡入与存档标记；全部只读模拟状态。
const Settings=preload("res://scripts/journey_settings.gd")
const EnemyView=preload("res://scripts/journey_enemy_view.gd")
const Atmosphere=preload("res://scripts/journey_atmosphere.gd")
const Gamepad=preload("res://scripts/journey_gamepad.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:call_deferred("verify")

func key(code:int)->InputEventKey:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
	return event

func pad_button(device:int,button:int,pressed:bool)->void:
	var event:=InputEventJoypadButton.new();event.device=device;event.button_index=button;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()

func pad_axis(device:int,axis:int,value:float)->void:
	var event:=InputEventJoypadMotion.new();event.device=device;event.axis=axis;event.axis_value=value
	Input.parse_input_event(event);Input.flush_buffered_events()

func bus_linear(name:String)->float:
	return db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(name)))

func verify()->void:
	# 测试会写本机设置，结束时原样恢复玩家文件。
	var backup:=FileAccess.get_file_as_bytes(Settings.PATH) if FileAccess.file_exists(Settings.PATH) else PackedByteArray()
	var had_file:=FileAccess.file_exists(Settings.PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	var game=load("res://scenes/journey.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.frame_delta=1.0/60
	game.scene_prepared=true
	var run=game.run
	check(game.settings.quality=="high" and game.settings.fps_cap==0,"桌面默认高画质、帧率不限，与原画质一致")

	# 开始页进入设置，主面板收起；冲击开关已挪进设置页。
	run.state="start";game.update_journey_ui()
	check(game.settings_button.visible,"开始页显示设置入口")
	game.open_settings()
	check(game.settings_panel.visible and not game.panel.visible,"开始页打开设置页并收起主面板")
	check(game.impact_button.is_visible_in_tree() and game.settings_panel.is_ancestor_of(game.impact_button),"画面冲击开关位于设置页")
	check(game.volume_sliders.size()==4 and game.quality_buttons.size()==3 and game.fps_buttons.size()==4,"四个音量滑条、三档画质、四档帧率")

	# 音量：滑条写入总线；环境声与战斗压低相乘。
	game.volume_sliders.music.value=50
	check(absf(bus_linear("Music")-0.5)<0.01,"音乐滑条设置 Music 总线")
	game.set_volume("master",0.8);game.set_volume("sfx",0.6)
	check(absf(bus_linear("Master")-0.8)<0.01 and absf(bus_linear("SFX")-0.6)<0.01 and absf(bus_linear("UI")-0.6)<0.01,"总音量与音效写入对应总线")
	game.set_volume("ambience",0.5)
	game.ambience_level=game.AMBIENCE_DUCKED
	game.pump_ambience(0.0)
	check(absf(bus_linear("Ambience")-0.25)<0.01,"环境音量与战斗压低相乘")
	game.ambience_level=1.0;game.pump_ambience(0.0)
	check(absf(bus_linear("Ambience")-0.5)<0.01,"脱战后环境声回到用户音量")

	# 画质与帧率。
	game.set_quality("low")
	if Atmosphere.forward_plus():
		check(not game.canopy_light.shadow_enabled and not game.world_environment.ssao_enabled and not game.world_environment.volumetric_fog_enabled,"低画质关闭阴影、SSAO 与体积雾")
		game.set_quality("high")
		check(game.canopy_light.shadow_enabled and game.world_environment.ssao_enabled and game.world_environment.volumetric_fog_enabled,"高画质恢复阴影、SSAO 与体积雾")
		game.set_quality("low")
	else:print("SKIP 当前渲染器不是 Forward+，跳过阴影与雾效检查")
	game.set_fps_cap(30)
	check(Engine.max_fps==30,"帧率上限写入引擎")
	game.damage_numbers=false;game.impact_effects=false
	game.close_settings()
	check(not game.settings_panel.visible and game.panel.visible,"返回后回到开始页")
	var saved=Settings.new();saved.read_file()
	check(saved.quality=="low" and saved.fps_cap==30 and absf(saved.volumes.music-0.5)<0.01 and absf(saved.volumes.ambience-0.5)<0.01,"音量、画质与帧率保存到 settings.cfg")
	check(not saved.damage_numbers and not saved.impact_effects,"伤害数字与画面冲击开关一起保存")
	# 旧版只有 feel/impact_effects 键：读取后其余项取默认值。
	var legacy:=ConfigFile.new();legacy.set_value("feel","impact_effects",false);legacy.save(Settings.PATH)
	var old=Settings.new();old.read_file()
	check(not old.impact_effects and old.quality=="high" and old.volumes.master==1.0,"兼容旧版 feel/impact_effects 键")
	game.load_feel_settings()
	check(not game.impact_effects and game.damage_numbers,"旧设置文件读入游戏")
	game.settings=Settings.new();game.impact_effects=true;game.damage_numbers=true
	game.apply_audio_settings();game.apply_render_quality()

	# 暂停页进入设置；Esc 先关设置页，不恢复游戏；队友恢复游戏时自动收起。
	run.state="running";game.update_journey_ui()
	check(not game.settings_button.visible,"游玩时隐藏设置入口")
	run.pause();game.update_journey_ui()
	check(game.settings_button.visible and run.state=="paused","暂停页显示设置入口")
	game.open_settings()
	game._unhandled_key_input(key(KEY_ESCAPE))
	check(not game.settings_open and run.state=="paused","Esc 关闭设置页而不恢复游戏")
	game.open_settings();run.pause();game.update_journey_ui()
	check(not game.settings_open and not game.settings_panel.visible,"恢复游戏时设置页自动收起")

	# 伤害数字开关：关闭后不显示伤害，击败提示保留。
	var event:Dictionary={}
	for candidate in run.journey_events:
		if candidate.kind=="monster":event=candidate;break
	run.distance=event.y-300;run.a.position=Vector2(-42,event.y-300);run.b.position=Vector2(42,event.y-300)
	game.sync_view()
	var view:Node3D=game.event_views.get(event.id)
	check(view!=null,"敌人显示节点存在")
	if view!=null:
		event.hit_at=run.elapsed;event.hit_damage=10
		EnemyView.sync(game,view,event)
		check(view.get_node("HitNumber").visible,"默认显示伤害数字")
		game.damage_numbers=false;EnemyView.sync(game,view,event)
		check(not view.get_node("HitNumber").visible,"关闭后隐藏伤害数字")
		game.damage_numbers=true

	# 章节进度条：进入新区域时区域名淡入，约 2 秒后消失；存档标记跟随存档进度。
	run.retry();game.reset_journey_views();run.state="running"
	game.frame_delta=0.0;game.update_journey_ui()
	var bar=game.chapter_bar
	check(bar.visible and bar.zone_labels.size()==6,"顶部进度条显示六个区域分段")
	check(bar.zone_labels[1].text==run.CHAPTERS[run.level_index].zones[1],"分段标注区域名")
	check(bar.zone_title.visible and bar.zone_title.text==run.zone_name(),"出发时显示起始区域名")
	game.frame_delta=0.1
	for n in range(22):game.update_journey_ui()
	check(not bar.zone_title.visible,"区域名约 2 秒后消失")
	var zone_length:float=run.finish_distance()/6.0
	var y:float=zone_length*2+200
	run.distance=y;run.a.position=Vector2(-42,y);run.b.position=Vector2(42,y)
	game.frame_delta=0.0;game.update_journey_ui()
	check(run.zone_index()==2 and bar.zone_title.visible and bar.zone_title.text==run.zone_name(),"进入第三个区域时显示区域名")
	check(bar.title_alpha()<0.05,"区域名从透明开始淡入")
	game.frame_delta=0.5;game.update_journey_ui()
	check(bar.title_alpha()>0.95,"0.5 秒后区域名完全显示")
	check(absf(bar.fraction-run.progress()/run.finish_distance())<0.001,"进度条跟随本章进度")
	run.capture_checkpoint();game.update_journey_ui()
	check(absf(bar.checkpoint_fraction-run.checkpoint.progress/run.finish_distance())<0.001,"存档标记位于最近存档进度")
	run.pause();game.open_settings();game.update_journey_ui()
	check(not bar.visible,"设置页打开时隐藏进度条")
	game.close_settings();run.pause()

	# 手柄：本地双人第一个手柄控制 01、第二个控制 02；单人时只有第一个手柄控制本机角色。
	Gamepad.simulated_devices=[0,1]
	game.play_mode="local";run.state="running";game.pad_blocked=false
	pad_axis(0,JOY_AXIS_LEFT_X,1.0)
	pad_axis(1,JOY_AXIS_LEFT_Y,-1.0)
	pad_button(1,JOY_BUTTON_A,true)
	pad_axis(1,JOY_AXIS_TRIGGER_RIGHT,1.0)
	pad_button(1,JOY_BUTTON_X,true);pad_button(1,JOY_BUTTON_X,false)
	var input:Dictionary=game.sample_local_input()
	check(input.a==Vector2(1,0) and input.b==Vector2(0,1),"本地双人两个手柄分别移动 01 与 02")
	check(not input.ja and input.jb,"第二个手柄 A 只让 02 跳跃")
	check(input.fire_b and not input.fire and input.reload_b and not input.reload,"第二个手柄射击与换弹归 02")
	pad_axis(1,JOY_AXIS_TRIGGER_RIGHT,0.0);pad_button(1,JOY_BUTTON_A,false)
	pad_button(0,JOY_BUTTON_DPAD_UP,true)
	check(game.sample_local_input().a==Vector2(0,1),"十字键优先于摇杆")
	pad_button(0,JOY_BUTTON_DPAD_UP,false)
	game.play_mode="solo"
	pad_axis(1,JOY_AXIS_LEFT_Y,-1.0)
	input=game.sample_local_input()
	check(input.a==Vector2(1,0) and input.b==Vector2.ZERO,"单人时第一个手柄控制本机角色，第二个不接管搭档")
	pad_axis(0,JOY_AXIS_LEFT_X,0.0);pad_axis(1,JOY_AXIS_LEFT_Y,0.0)
	# 菜单确认后按着的 A 须先松开才跳跃。
	pad_button(0,JOY_BUTTON_A,true)
	game.clear_controls()
	check(not game.sample_local_input().ja,"菜单确认后按着的 A 不立即跳跃")
	pad_button(0,JOY_BUTTON_A,false);game.sample_local_input();pad_button(0,JOY_BUTTON_A,true)
	check(game.sample_local_input().ja,"松开后再按 A 跳跃")
	pad_button(0,JOY_BUTTON_A,false)

	# 提示文字随设备切换；手柄打开菜单时焦点落在主按钮上，Start 暂停，B 返回。
	check(game.gamepad_active,"手柄输入后切换为手柄提示")
	run.state="start";game.update_journey_ui()
	check(game.subtitle.text.contains("A 跳跃") and not game.subtitle.text.contains("WASD"),"开始页显示手柄按键")
	check(game.get_viewport().gui_get_focus_owner()==game.primary,"手柄时焦点落在主按钮")
	pad_button(0,JOY_BUTTON_A,true);pad_button(0,JOY_BUTTON_A,false)
	check(run.state=="running","手柄 A 确认焦点按钮出发")
	run.state="start";game.update_journey_ui()
	game.open_settings()
	check(game.get_viewport().gui_get_focus_owner()==game.volume_sliders.master,"设置页焦点落在总音量")
	pad_button(0,JOY_BUTTON_B,true);pad_button(0,JOY_BUTTON_B,false)
	check(not game.settings_open,"B 关闭设置页")
	run.state="running";game.update_journey_ui()
	pad_button(0,JOY_BUTTON_START,true);pad_button(0,JOY_BUTTON_START,false)
	check(run.state=="paused","Start 暂停游戏")
	game.update_journey_ui()
	check(game.subtitle.text.contains("Start 继续"),"暂停页显示手柄按键")
	pad_button(0,JOY_BUTTON_B,true);pad_button(0,JOY_BUTTON_B,false)
	check(run.state=="running","暂停页按 B 继续")
	Input.parse_input_event(key(KEY_W));Input.flush_buffered_events()
	run.state="start";game.update_journey_ui()
	check(not game.gamepad_active and game.subtitle.text.contains("WASD"),"按键盘后切回键盘提示")
	var release:=key(KEY_W);release.pressed=false;Input.parse_input_event(release);Input.flush_buffered_events()
	Gamepad.simulated_devices=[]

	for p in game.sfx.players:p.stop()
	game.settings_dirty=false
	game.queue_free();await process_frame;await create_timer(.2).timeout
	if had_file:
		var file:=FileAccess.open(Settings.PATH,FileAccess.WRITE);file.store_buffer(backup);file.close()
	else:DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	Engine.max_fps=0
	print("JOURNEY_SETTINGS_MENU failures=",failures)
	quit(1 if failures else 0)
