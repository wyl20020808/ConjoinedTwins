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
# 失败演出 0.6 秒后即可按跳跃从存档继续；完整演出仍按原时长播放，直到玩家确认。
const FAIL_SKIP_AFTER := 0.6
const RESTORE_FADE := 0.25
const CHECKPOINT_TOAST := 0.8
# 受击画面冲击只持续约 3 帧；触觉反馈与之共用“画面冲击与震动”开关，保存在本机设置。
const IMPACT_TIME := 0.05
const SETTINGS_PATH := "user://settings.cfg"
const AMBIENCE_DUCKED := 0.5
# Run 片段 0.8 秒迈两步：每步距离 = 自然步速 × 0.4 秒，脚步声与画面步频一致（01 约 1.8 米、02 约 2.1 米）。
const RUN_STEP_TIME := 0.4
const STEP_TELEPORT := 3.0
# 联机积压追帧：单个物理帧最多补 8 帧、最多占 8 毫秒，避免一次追帧把网页卡住。
const ONLINE_CATCHUP_FRAMES := 8
const ONLINE_CATCHUP_USEC := 8000
# 单位为道路单位（20/米）。预热窗口比展示窗口多 40 米，退出窗口再留 20 米迟滞。
const MODEL_AHEAD := 2400.0
const MODEL_PREFETCH := 3200.0
const MODEL_RETAIN := 3600.0
const MODEL_BEHIND := 600.0
const Landscape = preload("res://scripts/journey_landscape.gd")
const TRIPO_BOULDER := "res://assets/journey/tripo_boulder.glb"
const TRIPO_TIMBER := "res://assets/journey/tripo_timber_ram.glb"
# 双人机关模型（Tripo 文生 3D，1K 贴图）。
const MECH_PIVOT := "res://assets/mechanisms/pivot_pillar.glb"
const MECH_CRUSHER := "res://assets/mechanisms/crusher.glb"
const MECH_PLATE := "res://assets/mechanisms/pressure_plate.glb"
const MECH_ARCH := ["res://assets/mechanisms/arch_teal.glb","res://assets/mechanisms/arch_amber.glb"]
# 机关外观统一批次（Tripo 文生 3D，1K 贴图）；只替换外观，碰撞与运动仍由模拟矩形驱动。
const MECH_SPIKED_BALL := "res://assets/mechanisms/spiked_ball.glb"
const MECH_STONE_POST := "res://assets/mechanisms/stone_post.glb"
const MECH_SPIKE_TRAP := "res://assets/mechanisms/spike_trap.glb"
const MECH_FIRE_BOLT := "res://assets/mechanisms/fire_bolt.glb"
const MECH_FLYING_ROCK := "res://assets/mechanisms/flying_rock.glb"
const MECH_STEAM_VENT := "res://assets/mechanisms/steam_vent.glb"
const MECH_SPIKED_LOG := "res://assets/mechanisms/spiked_log.glb"
const MECH_LIFT := "res://assets/mechanisms/lift_platform.glb"
const BARREL_MODEL := "res://assets/mechanisms/barrel.glb"
# 跳绳木杆：转轴高度与转动半径（米），最低点离地约 0.15 米。
const THREAT_APPEAR_TIME := 0.45
const THREAT_DROP_HEIGHT := 7.0
const JUMP_BAR_AXLE := 1.75
const JUMP_BAR_RADIUS := 1.6
var landscape
const Atmosphere = preload("res://scripts/journey_atmosphere.gd")
const HazardFx = preload("res://scripts/journey_hazard_fx.gd")
const CoopFx = preload("res://scripts/journey_coop_fx.gd")
var hazard_fx
var coop_fx
var atmosphere
const Fx = preload("res://scripts/journey_fx.gd")
var fx
const Buddy=preload("res://scripts/journey_buddy.gd")
const BossView=preload("res://scripts/journey_boss_view.gd")
# Boss 战镜头：比旅程镜头更高更远、视角更宽，跟随两人中点在场地内前后移动，朝向仍固定向前。
const BOSS_EYE_HEIGHT := 12.5
const BOSS_EYE_BACK := 420.0
const BOSS_LOOK_HEIGHT := 5.5
const BOSS_LOOK_AHEAD := 620.0
const BOSS_FOV := 62.0
var boss_camera_blend := 0.0
var boss_camera_focus := -1.0
var buddy=Buddy.new()
var play_mode:="solo"
var mode_buttons:Array[Button]=[]
var online_row:HBoxContainer
var input_override:Dictionary={}
var web_test_mode:=false
var web_verify:=false
var verify_clock:=1.0
var last_fire_sent:=false
const WEB_BUILD:="chapter-menu-online-cache-20261021"
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
var ambience_level := 1.0
# 章节音乐（OpenGameArt，CC0，见 ASSET_SOURCES.md）：探索层按章节切换，战斗层在附近敌人察觉时淡入。
const MUSIC_EXPLORE := ["res://assets/audio/music/forest_ambience.mp3","res://assets/audio/music/village_2018.mp3","res://assets/audio/music/cathedral_forest.ogg"]
const MUSIC_COMBAT := "res://assets/audio/music/cynic_battle_loop.ogg"
const MUSIC_EXPLORE_DB := -16.0
const MUSIC_COMBAT_DB := -15.0
var music_explore: AudioStreamPlayer
var music_combat: AudioStreamPlayer
var music_chapter := -1
var explore_level := 0.0
var combat_level := 0.0
var step_travel := [0.0,0.0]
var step_last := [Vector2.INF,Vector2.INF]
var ambience_streams := {}
var forest_birds:AudioStreamPlayer
var sound_events := {}
var sound_clock := 0.0
const CombatView = preload("res://scripts/journey_combat_view.gd")
const PAD_HELP := "左摇杆 / 十字键移动 · A 跳跃 · RT 射击\nX 换弹 · LB 换枪 · Y 丢枪"
const WEAPON_ICONS := {"smg":preload("res://assets/ui/smg.svg"),"shotgun":preload("res://assets/ui/shotgun.svg"),"flamer":preload("res://assets/ui/flamer.svg"),"launcher":preload("res://assets/ui/launcher.svg")}
@export var training_entry := false
@export var start_chapter := 0
# 由主界面启动时连接：回到主页即回到章节选择。
signal home_requested
var menu_entry := false
const LoadingScreen = preload("res://scripts/loading_screen.gd")
const Catalog = preload("res://scripts/chapter_catalog.gd")
# 章节数据未就绪（网页按章下载）或联机入场时覆盖全屏的载入画面。
var pack_overlay
var pack_overlay_key := ""
# 联机章节同步：开局或 01 号换章后，两端各自确认本章数据与场景就绪，“出发”等双方都就绪才生效。
# 这些状态只在应用共同帧时修改，两端一致。
var online_ready := [true,true]
var online_start_pending := false
var partner_load := [-1,-1]
var chapter_epoch := 0
var ready_sent_epoch := -1
var load_sent := -1
var online_entry := false
var last_prepare_ok := false
var prefetch_clock := 0.0
var net_diag: Label
var camera_smoothed := false
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
var post_canvas: CanvasLayer
var vignette_mat: ShaderMaterial
var damage_flash := 0.0
var impact_flash := 0.0
var impact_effects := true
var impact_button: Button
const Settings = preload("res://scripts/journey_settings.gd")
const Gamepad = preload("res://scripts/journey_gamepad.gd")
const ChapterBar = preload("res://scripts/journey_chapter_bar.gd")
var settings = Settings.new()
var damage_numbers := true
var settings_open := false
var settings_dirty := false
var settings_button: Button
var settings_panel: PanelContainer
var settings_close: Button
var volume_sliders := {}
var volume_values := {}
var quality_buttons: Array[Button] = []
var fps_buttons: Array[Button] = []
var damage_button: Button
var chapter_bar: Control
var gamepad_active := false
var pad_blocked := true
var reload_requested_b := false
var drop_requested_b := false
var swap_requested_b := false
var focus_style: StyleBoxFlat
var last_kills := 0
var last_open_gates := 0
var low_health := 0.0
var last_health := [100, 100]
# 主角步态：Run 片段的自然步速（世界单位/秒，按支撑脚滑过地面的速度测得，tests/hero_locomotion.gd 复核）。
# 播放倍率 = 实际水平速度 / 自然步速，脚不打滑；02 腿更长，步速更高。
const HERO_STRIDE_SPEED := [4.56, 5.16]
const HeroLocomotion = preload("res://scripts/hero_locomotion.gd")
# 落地缓冲：下落高度超过普通跳跃顶点的 1.25 倍改用重落地。
const HEAVY_LANDING := 1.25
var hero_rigs := [null, null]
var hero_velocity := [Vector2.ZERO, Vector2.ZERO]
var hero_last_pos := [Vector2.ZERO, Vector2.ZERO]
var hero_last_time := [-1.0, -1.0]
var hero_strafe := [{"Run_Back": 0.0, "Run_Left": 0.0, "Run_Right": 0.0}, {"Run_Back": 0.0, "Run_Left": 0.0, "Run_Right": 0.0}]
var air_top := [0.0, 0.0]
var landing_clip := ["", ""]
var landing_left := [0.0, 0.0]
# 持枪攻击身后或侧后方的敌人时整个身体转过去开火，停火后转回道路前方。
var body_yaw := [0.0, 0.0]
const BODY_TURN_RATE := 12.0
const BODY_TURN_MIN := 0.6
const BODY_TURN_HOLD := 0.45
var landing_strength := [0.0, 0.0]
var visual_last_heights := [0.0, 0.0]
var land_impact := [0.0, 0.0]
var training_button: Button
var restart_button: Button
var checkpoint_button: Button
var home_button: Button
var fire_blocked := true
var reload_requested := false
var drop_requested := false
var swap_requested := false
var frame_costs := {}
var restore_fade: ColorRect
var restore_fade_left := 0.0
var checkpoint_toast: Label
var checkpoint_toast_left := 0.0
var toasted_checkpoint := -INF
var view_pending:=false
var journey_camera_returning:=false
const UNDERSTORY:=["fern","shrub","grass","detail_fern_bed"]

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
	settings=Settings.new("web" if OS.has_feature("web") else ("mobile" if OS.has_feature("mobile") else "desktop"))
	load_feel_settings()
	Gamepad.ensure_ui_accept()
	if OS.has_feature("web"):web_verify=bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('verify')",true))
	ThemeDB.fallback_font=preload("res://assets/fonts/web_ui_font.tres")
	finish_view.free()
	charge_gate_view.free()
	run.solo_control=true
	run.external_companion=not training_entry
	if training_entry:
		run.combat_trial=true
		run.retry()
	elif start_chapter>0:
		# 主界面选定的章节：只准备这一章，其余章节数据按需下载。
		run.level_index=clampi(start_chapter,0,Journey.CHAPTERS.size()-1)
		run.retry()
	run.state="start"
	add_child(road)
	build_lighting()
	landscape=Landscape.new(self)
	if OS.has_feature("web"):
		apply_web_quality()
		get_viewport().size_changed.connect(apply_web_quality)
	elif landscape.mobile:
		get_viewport().scaling_3d_scale=Settings.MOBILE_SCALE[settings.quality]
		get_viewport().msaa_3d=Viewport.MSAA_DISABLED
	elif Atmosphere.forward_plus():
		apply_desktop_quality()
		get_viewport().size_changed.connect(apply_desktop_quality)
	# 默认“不限”时不改引擎设置，保留启动入口或测试预设的上限。
	if not OS.has_feature("web") and settings.fps_cap>0:Engine.max_fps=settings.fps_cap
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
	# 镜头比旧版更近更低：角色在画面中约占八分之一高，空路面减少；
	# FOV 收窄到 57°，保持固定朝向、不旋转不晃动。
	camera.position=Vector3(0,9.6,18)
	camera.look_at(Vector3(0,1.4,-22))
	camera.fov=57
	camera_home=camera.transform
	atmosphere=Atmosphere.new(self,world_environment,canopy_light,camera)
	apply_quality_effects()
	fx=Fx.new();add_child(fx)
	hazard_fx=HazardFx.new(self,fx);add_child(hazard_fx)
	coop_fx=CoopFx.new(self,fx,hazard_fx);add_child(coop_fx)
	if incremental_loading:
		set_physics_process(false)
		set_process_unhandled_key_input(false)
		await get_tree().process_frame
		await build_robots()
	else: build_robots()
	sfx=Sfx.new()
	add_child(sfx)
	apply_audio_settings()
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

# 网页首帧预热的植被模型；章节拆包巡检把它们并入每一章的用量（见 build-tools/chapter_usage.py）。
const WEB_WARM_PATHS:=["res://assets/landscape/natural_oak_7.glb","res://assets/landscape/natural_oak_17.glb","res://assets/landscape/natural_birch.glb","res://assets/landscape/natural_oak_7_lod.glb","res://assets/landscape/natural_oak_17_lod.glb","res://assets/landscape/natural_birch_lod.glb","res://assets/landscape/grass.glb","res://assets/landscape/fern.glb","res://assets/landscape/shrub.glb","res://assets/landscape/woodpile.glb"]
func warm_web_landscape()->void:
	# 首次绘制的 WebGL 上传/着色器编译放在加载页，避免走入森林时同步阻塞。
	var paths:Array=WEB_WARM_PATHS
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
	Engine.max_fps=settings.fps_cap
	# 一次长帧后最多补算三帧，避免八帧追赶反过来持续堵住浏览器输入与绘制。
	Engine.max_physics_steps_per_frame=3
	var size:=get_viewport().get_visible_rect().size
	var target:Vector2=Settings.WEB_RESOLUTION[settings.quality]
	get_viewport().scaling_3d_scale=minf(1.0,minf(target.x/maxf(size.x,1.0),target.y/maxf(size.y,1.0)))
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED

func apply_desktop_quality() -> void:
	# 桌面 Forward+ 的森林段受像素填充限制（茂密双面树叶 + 全屏后期）：
	# 720p 以下保持原生 + MSAA；更高分辨率改用时间性超分，内部渲染高度约 800 像素，
	# 同时获得时间性抗锯齿，压住树叶与细绳的闪烁。macOS 用 MetalFX，其余平台用 FSR2。
	var viewport:=get_viewport()
	# canvas_items 拉伸下可见矩形固定为 1280×720，3D 实际按窗口像素渲染，故取窗口尺寸。
	var height:=float(get_window().size.y)
	# 画质预设只改内部渲染高度与 MSAA；高档即原有 800 像素。
	var preset:Dictionary=Settings.DESKTOP[settings.quality]
	var render_height:float=preset.height
	if height<=render_height:
		viewport.scaling_3d_mode=Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale=1.0
		viewport.msaa_3d=Viewport.MSAA_2X if preset.msaa else Viewport.MSAA_DISABLED
		return
	viewport.msaa_3d=Viewport.MSAA_DISABLED
	viewport.scaling_3d_mode=Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if OS.get_name()=="macOS" else Viewport.SCALING_3D_MODE_FSR2
	viewport.scaling_3d_scale=clampf(render_height/height,0.34,1.0)

# 阴影、体积雾与 SSAO 只在桌面 Forward+ 可调；网页与移动端保持原有关闭状态。
func apply_quality_effects() -> void:
	if OS.has_feature("web") or landscape==null or landscape.mobile or not Atmosphere.forward_plus():return
	var preset:Dictionary=Settings.DESKTOP[settings.quality]
	if is_instance_valid(canopy_light):canopy_light.shadow_enabled=preset.shadows
	if world_environment!=null:
		world_environment.volumetric_fog_enabled=preset.fog
		world_environment.ssao_enabled=preset.ssao

func apply_render_quality() -> void:
	if OS.has_feature("web"):apply_web_quality()
	elif landscape!=null and landscape.mobile:get_viewport().scaling_3d_scale=Settings.MOBILE_SCALE[settings.quality]
	elif Atmosphere.forward_plus():apply_desktop_quality()
	apply_quality_effects()

# 用户音量按线性乘到各总线；环境声在 pump_ambience 里再乘战斗压低，二者不互相覆盖。
func apply_audio_settings() -> void:
	Sfx.ensure_buses()
	Sfx.set_bus_level("Master",settings.volumes.master)
	Sfx.set_bus_level("Music",settings.volumes.music)
	Sfx.set_bus_level("SFX",settings.volumes.sfx)
	Sfx.set_bus_level("UI",settings.volumes.sfx)
	Sfx.set_bus_level("Ambience",ambience_level*settings.volumes.ambience)

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
	# 暂停中的播放句柄要先恢复再停止，否则退出时 OGG 播放对象会残留。
	for player in [music_explore,music_combat]:
		if is_instance_valid(player):player.stream_paused=false;player.stop();player.stream=null
	ambience_streams.clear()
	if landscape!=null:landscape.game=null
	if settings_dirty:save_feel_settings()
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

func add_lamp(parent: Node3D,pos: Vector3,kind: String) -> void:
	# 木杆 + 铁臂 + 发光灯芯；灯芯 HDR 超过 1 才会晕开。灯光不投影，远处淡出。
	var level:float=atmosphere.lamp_level(run.level_index) if atmosphere else 0.0
	if level<=0.0:return
	var root:=Node3D.new();root.name="Lamp";root.position=pos;parent.add_child(root)
	var inward:=-signf(pos.x)
	var torch:=kind=="torch"
	var height:=2.3 if torch else 3.4
	var wood:=material("lamp_post",Color("4a3828"))
	cylinder(root,Vector3(0,height*.5,0),0.075 if torch else 0.09,height,wood)
	var head:=Vector3(0,height+.12,0)
	if not torch:
		box(root,Vector3(inward*.32,height-.05,0),Vector3(.7,.06,.06),material("lamp_iron",Color("2b2b2c")))
		head=Vector3(inward*.62,height-.36,0)
		box(root,head+Vector3(0,.2,0),Vector3(.32,.06,.32),material("lamp_iron",Color("2b2b2c")))
	else:
		cylinder(root,head+Vector3(0,-.12,0),.13,.16,material("lamp_iron",Color("2b2b2c")))
	var flame_color:=Color("ff8a3c") if torch else Color("ffc77a")
	var flame:=MeshInstance3D.new();var sphere:=SphereMesh.new()
	sphere.radius=.17 if torch else .15;sphere.height=sphere.radius*(2.6 if torch else 2.0)
	sphere.radial_segments=10;sphere.rings=6
	flame.mesh=sphere;flame.position=head;flame.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.material_override=material("lamp_flame_"+kind,flame_color,6.0)
	root.add_child(flame)
	var light:=OmniLight3D.new()
	light.position=head+Vector3(0,.15,0)
	light.light_color=flame_color
	light.light_energy=(4.2 if torch else 2.6)*level
	light.omni_range=11.0 if torch else 9.0
	light.omni_attenuation=1.4
	light.shadow_enabled=false
	light.light_volumetric_fog_energy=2.5
	light.distance_fade_enabled=true
	light.distance_fade_begin=70.0
	light.distance_fade_length=20.0
	if torch:light.set_meta("flicker",pos.z*.37)
	root.add_child(light)
	if torch:
		var lights:Array=parent.get_meta("flicker_lights",[]);lights.append(light);parent.set_meta("flicker_lights",lights)

var water_shader_material:ShaderMaterial
func water_material()->Material:
	if water_shader_material==null:
		water_shader_material=ShaderMaterial.new()
		water_shader_material.shader=preload("res://scripts/journey_water.gdshader")
		water_shader_material.set_shader_parameter("bank_near",Run.EDGE/SCALE+3.0)
		water_shader_material.set_shader_parameter("bank_far",Run.EDGE/SCALE+29.0)
	return water_shader_material

const CRYSTAL_COLORS:=[Color("6fe9ff"),Color("b48cff"),Color("7dffc4")]
func add_crystals(parent: Node3D,pos: Vector3,seed_value: int) -> void:
	# 路缘外的一簇发光矿晶：六棱锥，HDR 自发光晕开，配一盏不投影的小灯。只作展示。
	var rng:=RandomNumberGenerator.new();rng.seed=seed_value*977+int(pos.z)
	var tint:Color=CRYSTAL_COLORS[seed_value%CRYSTAL_COLORS.size()]
	var root:=Node3D.new();root.name="Crystals";root.position=pos;parent.add_child(root)
	var glow:=material("crystal_%s"%tint.to_html(false),tint.darkened(.35),5.0)
	glow.emission=tint;glow.roughness=.15;glow.metallic_specular=.9
	for n in range(rng.randi_range(4,7)):
		var shard:=MeshInstance3D.new();var cone:=CylinderMesh.new()
		cone.top_radius=0.0;cone.bottom_radius=rng.randf_range(.12,.26);cone.height=rng.randf_range(.6,1.7)
		cone.radial_segments=6;cone.rings=1
		shard.mesh=cone;shard.material_override=glow
		shard.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.position=Vector3(rng.randf_range(-.5,.5),cone.height*.42,rng.randf_range(-.6,.6))
		shard.rotation=Vector3(rng.randf_range(-.45,.45),rng.randf()*TAU,rng.randf_range(-.45,.45))
		root.add_child(shard)
	var light:=OmniLight3D.new()
	light.position=Vector3(0,1.0,0);light.light_color=tint
	light.light_energy=2.2;light.omni_range=7.0;light.omni_attenuation=1.5
	light.shadow_enabled=false;light.light_volumetric_fog_energy=1.8
	light.distance_fade_enabled=true;light.distance_fade_begin=70.0;light.distance_fade_length=20.0
	root.add_child(light)

func light_building(chunk: Node3D,building: Node3D,side: float) -> void:
	# 夜间厂房：朝路一面加两排窗灯（冷白为主、少量暖黄、部分熄灭），屋顶一盏红色航空信标。
	var bounds:=model_bounds(chunk,building)
	if bounds.size==Vector3.ZERO:return
	var face_x:=bounds.position.x-.05 if side>0 else bounds.end.x+.05
	var rng:=RandomNumberGenerator.new();rng.seed=int(bounds.position.z*13.0)
	var cool:=material("window_cool",Color("1c2a33"),2.0);cool.emission=Color("a9d6ff")
	var warm:=material("window_warm",Color("332616"),2.2);warm.emission=Color("ffc07a")
	var columns:=maxi(3,int(bounds.size.z/2.4))
	for row in range(2):
		for column in range(columns):
			if rng.randf()<.4:continue
			var z:=bounds.position.z+(column+.5)*bounds.size.z/columns
			var y:=bounds.position.y+bounds.size.y*(.28+row*.3)
			var pane:=box(chunk,Vector3(face_x,y,z),Vector3(.06,bounds.size.y*.08,bounds.size.z/columns*.4),warm if rng.randf()<.22 else cool)
			pane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var beacon_pos:=Vector3(bounds.get_center().x,bounds.end.y+.25,bounds.get_center().z)
	var beacon:=MeshInstance3D.new();var orb:=SphereMesh.new();orb.radius=.22;orb.height=.44;orb.radial_segments=8;orb.rings=4
	beacon.mesh=orb;beacon.position=beacon_pos;beacon.material_override=material("beacon_red",Color("ff2a1a"),8.0)
	beacon.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(beacon)
	var light:=OmniLight3D.new();light.position=beacon_pos;light.light_color=Color("ff3020")
	light.omni_range=6.0;light.light_energy=1.6;light.shadow_enabled=false;light.light_volumetric_fog_energy=2.0
	light.distance_fade_enabled=true;light.distance_fade_begin=90.0;light.distance_fade_length=20.0
	chunk.add_child(light)
	var beacons:Array=chunk.get_meta("beacons",[]);beacons.append([beacon,light,rng.randf()]);chunk.set_meta("beacons",beacons)
	# 路侧一盏冷白泛光灯打在墙面上，给厂房一个可读的轮廓。
	var flood:=SpotLight3D.new()
	flood.position=Vector3(face_x-side*3.5,.6,bounds.get_center().z)
	flood.light_color=Color("cfe2ff");flood.light_energy=3.0;flood.spot_range=16.0;flood.spot_angle=38.0
	flood.shadow_enabled=false;flood.light_volumetric_fog_energy=1.2
	flood.distance_fade_enabled=true;flood.distance_fade_begin=80.0;flood.distance_fade_length=20.0
	chunk.add_child(flood)
	flood.look_at(Vector3(face_x,bounds.position.y+bounds.size.y*.65,bounds.get_center().z),Vector3.UP)

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
			elif item[1] in UNDERSTORY:
				# 蕨类每株约千面、灌木约五百面，70 米外被树干与林雾遮住，不再远距离整批绘制。
				landscape.batch(chunk,path,item[2],60 if landscape.mobile or OS.has_feature("web") else 75)
			else:landscape.batch(chunk,path,item[2],110 if landscape.mobile or OS.has_feature("web") else 170)
		"landscape_rock":
			var cliff:Material=tex_material("cliff_face","rock_face_03",.11,Color("a89a90"))
			var mesh:Mesh=rock_mesh("ridge_spire",44,8,2.8,70,.2) if item[3] else rock_mesh("ridge_buttress",60,3.6,1.8,24,.24)
			rock(chunk,mesh,cliff,item[1],item[2],item[4])
		"land":
			var surface:Material=landscape.terrain if item[3] in ["village","farm","river"] else material("land_"+item[3],Color("48513b") if item[4] else Color("77765b"))
			# 矿道与设施两侧原是纯色平面，夜里像一片灰板；改为碎石岩面。
			if item[3] in ["mine","ruins","facility"]:surface=tex_material("night_gravel","rock_boulder_dry",.22,Color("6e675f"))
			box(chunk,item[1],item[2],surface)
		"water":
			var surface:=box(chunk,item[1],item[2],water_material())
			surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"riverbed": box(chunk,item[1],item[2],tex_material("riverbed","rock_boulder_dry",.3,Color("3c3a32")))
		"model":
			var node := model("res://assets/decor/%s.glb"%item[1],chunk,item[2],item[3],item[4],item[5])
			if item.size()>6 and node:
				node.set_meta("wind",item[6])
				var moving:Array=chunk.get_meta("wind_nodes",[]);moving.append(node);chunk.set_meta("wind_nodes",moving)
		"rock":
			# 原用铺地石材质，大石块上出现方砖纹；改为三平面岩面。每三块配一簇发光矿晶。
			rock(chunk,rock_mesh("journey_rock_%d"%item[1],item[1]+31,3,1.8,8,0.5),tex_material("mine_rock","rock_face_03",.16,Color("958a80")),item[2],item[3])
			if run.level_index==2 and item[1]%3==0:add_crystals(chunk,Vector3(signf(item[2].x)*17.9,0,item[2].z),item[1])
		"asset": asset(chunk,item[1],item[2],item[3],item[4])
		"building":
			var building:=model("res://assets/industrial/building-k.glb",chunk,item[1],14,item[2],15)
			if run.level_index==2:light_building(chunk,building,signf(item[1].x))
		"lamp": add_lamp(chunk,item[1],item[2])
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
		if event.kind=="boss":retained.append_array(BossView.PATHS)
	for gate in run.charge_gates:
		if model_resident(gate.receiver.y):
			retained.append_array(["res://assets/journey/gate.glb","res://assets/journey/waterwheel.glb","res://assets/journey/drawbridge.glb"])
			if gate.get("kind","")=="relay":retained.append(MECH_PLATE)
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
		if event.kind=="boss":paths.append_array(BossView.PATHS)
		chunk_assets.request(paths)
		if chunk_assets.ready(paths) and Time.get_ticks_usec()<deadline:
			event_views[event.id]=build_event(event)
			event_views[event.id].hide()
		elif model_visible(event.y): ready=false
	for gate in run.charge_gates:
		if not model_preload(gate.receiver.y) or gate_views.has(gate.id): continue
		var paths: Array=["res://assets/journey/gate.glb", "res://assets/journey/%s.glb"%("waterwheel" if gate.id=="waterwheel" else "drawbridge")]
		if gate.get("kind","")=="relay":paths.append(MECH_PLATE)
		chunk_assets.request(paths)
		if chunk_assets.ready(paths) and Time.get_ticks_usec()<deadline:
			gate_views[gate.id]=quiet_world_text(build_gate(gate))
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
	if kind=="boss":
		BossView.build(self,root,event)
		return root
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
		elif kind=="monster" and event.archetype=="goblin_bomber":
			# 炸药包：黑色圆弹加一截发光引信。
			ball.scale=Vector3.ONE*.42
			ball.material_override=material("bomb_shell",Color("202326"))
			var fuse:Node3D=box(body,Vector3(0,.26,0),Vector3(.05,.16,.05),material("bomb_fuse",Color("ffb347"),2.5))
			fuse.rotation.z=.4
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
	quiet_world_text(root)
	return root

func sync_events() -> void:
	var rolling_cart=null
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
		if event.kind=="boss":
			BossView.sync(self,view,event)
			continue
		var body:Node3D=view.get_node("Body")
		var rect:Rect2=event.sample
		body.position=Vector3(rect.get_center().x/SCALE,event.bottom/SCALE,-(rect.get_center().y-event.y)/SCALE)
		body.visible=event.phase!="spent"
		if event.kind=="tree":
			# 树根位于倒伏范围的一端，最终树干与实心碰撞矩形对齐。
			var age:float=run.elapsed-event.trigger
			var fall:float=clampf((age-Journey.TREE_WARNING)/0.65,0,1) if event.trigger>=0 else 0.0
			body.position.x=event.rect.get_center().x/SCALE-event.side*5.5
			body.rotation.z=-event.side*fall*PI/2
			# 预警期越来越晃，最后一刻先向倒伏方向歪一下。
			if event.phase=="warning":
				var crack:float=clampf(age/Journey.TREE_WARNING,0,1)
				body.rotation.z=sin(run.elapsed*14)*(0.02+0.05*crack)-event.side*0.08*crack*crack
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
			if run.Monsters.ranged(event) or run.Monsters.charges(event):
				var data:Dictionary=run.Monsters.profile(event)
				var length:float=data.speed*data.active/SCALE
				var center:Vector2=event.launch+event.attack_direction*length*SCALE/2
				warning.position=Vector3(center.x/SCALE,.04+event.get("ground_height",0.0)/SCALE,-(center.y-event.y)/SCALE)
				warning.rotation.y=atan2(event.attack_direction.x,-event.attack_direction.y)
				warning.scale=Vector3({"archer":.32,"goblin_bomber":.5}.get(event.archetype,1.0),1,length/2.5)
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
			var center:Vector2=event.rect.get_center()
			var at:=Vector3(center.x/SCALE,1.0,-center.y/SCALE)
			sfx.play_at("warning",at,-4.0,0.75 if event.kind=="boar" else 1.0)
			# 预警期叠加真实机关声：大树根部断裂吱嘎、摆锤木梁受力。
			if event.kind in ["tree","swing"]: sfx.play_at("wood_creak_heavy",at,-3.0,0.8 if event.kind=="tree" else 1.0)
			# 野猪刨地哼叫；推车村民吆喝一声开始推。
			elif event.kind=="boar": sfx.play_at("growl",at+Vector3(0,0.3,0),-6.0,1.7)
			elif event.kind=="cart": sfx.play_at("grunt",Vector3(-event.side*25.5,1.4,-event.y/SCALE),-8.0,0.9)
		var phase_key:="%s:%s"%[event.id,event.phase]
		if event.phase in ["falling","fallen","spent","active"] and event.kind in ["tree","stone","boar"] and not sound_events.has(phase_key):
			sound_events[phase_key]=true
			var hit:Vector2=event.rect.get_center() if event.kind=="tree" else Vector2(event.locked_x,event.y)
			var hit_at:=Vector3(hit.x/SCALE,0.5,-hit.y/SCALE)
			if event.kind=="tree" and event.phase=="falling": sfx.play_at("tree_fall",hit_at,0.0)
			# 树干砸地：沉闷的撞击加碎枝。
			elif event.kind=="tree" and event.phase=="fallen":
				sfx.play_at("punch_heavy",hit_at,-3.0,0.55)
				sfx.play_at("rubble",hit_at,-8.0,0.7)
			# 野猪冲出时尖叫；村民出手时"嘿"一声，石块破空。
			elif event.kind=="boar" and event.phase=="active": sfx.play_at("snarl",hit_at,-5.0,1.6)
			elif event.kind=="stone" and event.phase=="active":
				sfx.play_at("grunt",Vector3(event.side*18,1.4,-event.y/SCALE),-7.0,1.05)
				sfx.play_at("whoosh",hit_at+Vector3(0,2.0,0),-10.0,1.3)
			elif event.kind=="stone" and event.phase=="spent" and int(event.get("hp",1))>0 and event.trigger>=0: sfx.play_at("rubble",hit_at,-4.0,0.9)
		if event.kind=="cart" and event.phase=="active" and view.visible:
			var cart_at:Vector3=body.global_position
			if rolling_cart==null or camera.global_position.distance_to(cart_at)<camera.global_position.distance_to(rolling_cart): rolling_cart=cart_at
	# 推车滚动声只保留离镜头最近的一辆。
	sfx.loop_at("event_cart","cart_roll",rolling_cart!=null and run.state=="running",rolling_cart if rolling_cart!=null else Vector3.ZERO,-5.0)

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
	if gate.get("kind","")=="relay":
		# 接力门：门前、门后各一块石踏板；有人踩住时符文发光。
		for side in ["near","far"]:
			var rect:Rect2=gate[side]
			var center:Vector2=rect.get_center()
			var plate:=Node3D.new();plate.name=side;root.add_child(plate)
			plate.position=Vector3(center.x/SCALE,0,-(center.y-gate.door.position.y)/SCALE)
			tripo_model(plate,MECH_PLATE,Vector3(rect.size.x/SCALE*1.15,.32,rect.size.y/SCALE*1.15),Vector3(0,.12,0))
			var glow:=cylinder(plate,Vector3(0,.3,0),rect.size.x/SCALE*.42,.03,material("relay_glow_"+side,Color("57dbea") if side=="near" else Color("ffb95e"),1.2))
			glow.name="Glow"
		add_sign(root,gate.title,Vector3(0,6,0),32).name="GateTitle"
		return root
	for side in ["left","right"]:
		var rect:Rect2=gate[side]
		var center:Vector2=rect.get_center()
		var plate:=box(root,Vector3(center.x/SCALE,0.045,-(center.y-gate.door.position.y)/SCALE),Vector3(rect.size.x/SCALE,0.08,rect.size.y/SCALE),material("plate_"+side,Color("4baba0") if side=="left" else Color("d8a45c"),0.25))
		plate.name=side
	add_sign(root,gate.title,Vector3(0,6,0),32).name="GateTitle"
	if gate.id=="waterwheel": asset(root,"waterwheel",Vector3(19,0,0),9,PI/2)
	elif "bridge" in gate.id:
		# 桥面中心对准模拟吊桥（门后 140 单位，长 212 单位）；转 180° 让铰链在对岸，桥板朝玩家放下。
		asset(root,"drawbridge",Vector3(0,-0.1,-7),0.8,PI)
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
			gate_views[gate.id]=quiet_world_text(build_gate(gate))
		var view:Node3D=gate_views[gate.id]
		view.show()
		var lowered:float=clampf((run.elapsed-gate.opened_at)/0.6,0,1) if gate.open else 0.0
		sample_animation(view,"BridgeLower",lowered)
		# 吊桥：开始放下时铁链哗啦作响，落平时桥板砸在对岸一声闷响。
		if gate.get("bridge",false):
			var stage:int=0 if lowered<=0.0 else (1 if lowered<1.0 else 2)
			var heard:int=view.get_meta("bridge_stage",stage)
			if stage!=heard and run.state=="running":
				var deck:=view.global_position+Vector3(0,1.0,-7.0)
				if stage==1:
					sfx.play_at("chain_rattle",deck+Vector3(0,2.0,0),-6.0,1.0)
					sfx.play_at("wood_creak_heavy",deck,-8.0,1.1)
				elif stage==2:
					sfx.play_at("wood_knock",deck,-2.0,0.6)
					sfx.play_at("plate_heavy",deck,-9.0,0.7)
			view.set_meta("bridge_stage",stage)
		if gate.id=="waterwheel":sample_animation(view,"WheelTurn",run.elapsed)
		view.position=Vector3(0,0,-gate.door.position.y/SCALE)
		var opening:float=clampf((run.elapsed-gate.opened_at)/0.8,0,1) if gate.open else 0
		# 接力门守板期间门板升起；离开踏板后落下（门洞里有人时模拟会保持打开）。
		if gate.get("kind","")=="relay":
			var target:=1.0 if gate.open or gate.get("ajar",false) else 0.0
			var current:float=view.get_meta("relay_opening",0.0)
			current=move_toward(current,target,get_process_delta_time()*4.0)
			view.set_meta("relay_opening",current)
			opening=maxf(opening,current)
		sample_animation(view.get_node("Door"),"GateOpen",opening)
		# 栅栏开门后沉入地面而不是升到半空，免得悬在镜头与角色之间挡住视线。
		for side in [-1,1]:view.get_node("Door/SideBarrier%d"%side).position.y=2.4-opening*4.9
		# 门开后，后面的人走近门前 8 米起整座门框逐渐淡出，穿过门洞时不再遮挡角色。
		if gate.open:fade_passed_color_gate(view,gate.door.position.y-200.0)
		elif view.has_meta("faded"):
			view.remove_meta("faded")
			for node in view.find_children("*","GeometryInstance3D",true,false):
				if node is Label3D:node.modulate=node.get_meta("look_base_modulate",node.modulate)
				else:(node as GeometryInstance3D).transparency=0.0
		if gate.get("kind","")=="relay":
			for n in range(2):
				var plate:Node3D=view.get_node(["near","far"][n])
				plate.get_node("Glow").visible=gate.occupied[n] and not gate.open
			continue
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
	# 终点门就在 Boss 身后：Boss 倒下前不显示，入场运镜和战斗画面里不出现“共同抵达”。
	road.get_node("JourneyFinish").visible=not run.Boss.alive(run.Boss.boss(run))

func build_journey_ui() -> void:
	build_post_fx()
	var canvas:=CanvasLayer.new()
	canvas.name="JourneyCanvas"
	add_child(canvas)
	health_panel=hud_panel(canvas)
	var column:=VBoxContainer.new()
	column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation",5)
	health_panel.add_child(column)
	hud=label("",17,Color("8fe3d2"))
	column.add_child(hud)
	combat_health=health_bar(Color("9cdeb9"),10)
	column.add_child(combat_health)
	var divider:=ColorRect.new()
	divider.custom_minimum_size=Vector2(0,1)
	divider.color=Color(1,1,1,0.12)
	divider.mouse_filter=Control.MOUSE_FILTER_IGNORE
	column.add_child(divider)
	partner_status=label("",13,Color("e4c7a7"))
	column.add_child(partner_status)
	partner_health=health_bar(Color("e4b883"),5)
	column.add_child(partner_health)
	weapon_panel=hud_panel(canvas)
	var weapon_column:=VBoxContainer.new()
	weapon_column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	weapon_column.add_theme_constant_override("separation",2)
	weapon_panel.add_child(weapon_column)
	var weapon_caption:=label("武器",11,Color("9fb0a6"))
	weapon_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	weapon_column.add_child(weapon_caption)
	combat_status=label("",15,Color("cfd6cc"))
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
	weapon_ammo=label("",34)
	weapon_column.add_child(weapon_ammo)
	weapon_detail=label("",13,Color("e4c7a7"))
	weapon_column.add_child(weapon_detail)
	for text_label in [combat_status,weapon_ammo,weapon_detail]:
		text_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	journey_hint=label("",19,Color("ffe2a0"))
	journey_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	journey_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	journey_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(journey_hint)
	# 联机质量小字：延迟、抖动、缓冲、卡顿次数与帧率，卡的时候截图即可判断是网络还是电脑性能。
	net_diag=label("",13,Color(0.85,0.9,0.85,0.75))
	net_diag.name="NetDiagnostics"
	net_diag.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(net_diag)
	for text_label in [hud,partner_status,combat_status,weapon_ammo,weapon_detail,journey_hint]:
		text_label.add_theme_color_override("font_outline_color",Color(0.06,0.09,0.07,0.9))
		text_label.add_theme_constant_override("outline_size",4)
	touch_device=DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	touch=TouchControls.new()
	touch.combat_buttons=true
	canvas.add_child(touch)
	pause_button=Button.new()
	var pause_normal:=glass_style(0.55,0.30,0,20)
	pause_normal.content_margin_left=0;pause_normal.content_margin_right=0
	pause_normal.content_margin_top=0;pause_normal.content_margin_bottom=0
	var pause_hover:StyleBoxFlat=pause_normal.duplicate()
	pause_hover.bg_color=Color(0.10,0.13,0.14,0.72)
	pause_hover.border_color=Color(0.95,0.82,0.60,0.55)
	pause_button.add_theme_stylebox_override("normal",pause_normal)
	pause_button.add_theme_stylebox_override("hover",pause_hover)
	pause_button.add_theme_stylebox_override("pressed",pause_normal)
	pause_button.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
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
	checkpoint_toast=label("已存档",15,Color("f3e3b5"))
	checkpoint_toast.name="CheckpointToast"
	checkpoint_toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	checkpoint_toast.mouse_filter=Control.MOUSE_FILTER_IGNORE
	checkpoint_toast.add_theme_stylebox_override("normal",glass_style(0.5,0.3,10,6))
	checkpoint_toast.visible=false
	canvas.add_child(checkpoint_toast)
	panel=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position=Vector2(240,170)
	panel.size=Vector2(800,360)
	canvas.add_child(panel)
	panel.add_theme_stylebox_override("panel",glass_style(0.82,0.36,24,14))
	var inner:=VBoxContainer.new()
	inner.add_theme_constant_override("separation",12)
	panel.add_child(inner)
	title=label("",38,Color("f7f2e6"))
	inner.add_child(title)
	subtitle=label("",16,Color("cfd6cc"))
	subtitle.add_theme_constant_override("line_spacing",4)
	subtitle.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size.x=752
	inner.add_child(subtitle)
	primary=Button.new()
	primary.custom_minimum_size=Vector2(0,54)
	primary.pressed.connect(journey_primary)
	inner.add_child(primary)
	style_button(primary,true)
	training_button=Button.new()
	training_button.text="战斗训练 · 持枪步行约 90 秒"
	training_button.custom_minimum_size=Vector2(0,46)
	training_button.pressed.connect(func():
		# 主界面启动时这里是“选择其他章节”；独立运行生产场景时保留原来的训练切换。
		if from_menu():
			return_home()
			return
		run.combat_trial=not run.combat_trial
		run.new_campaign()
		# new_campaign 内部的 retry 会把状态置为 running；切换地图后仍停在开始页，由玩家确认出发。
		run.state="start"
		reset_journey_views())
	inner.add_child(training_button)
	style_button(training_button)
	checkpoint_button=Button.new()
	checkpoint_button.text="回到存档点继续"
	checkpoint_button.custom_minimum_size=Vector2(0,42)
	checkpoint_button.pressed.connect(func():
		command("checkpoint"))
	checkpoint_button.visible=false
	inner.add_child(checkpoint_button)
	style_button(checkpoint_button)
	home_button=Button.new()
	home_button.text="回到主页 · 重新选择单人或联机"
	home_button.custom_minimum_size=Vector2(0,42)
	home_button.pressed.connect(return_home)
	home_button.visible=false
	# “回到主页”与“重新开始本关”并排一行，失败条和暂停页都更紧凑。
	var secondary_row:=HBoxContainer.new()
	secondary_row.add_theme_constant_override("separation",8)
	inner.add_child(secondary_row)
	home_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	secondary_row.add_child(home_button)
	style_button(home_button)
	restart_button=Button.new()
	restart_button.text="重新开始本关"
	restart_button.custom_minimum_size=Vector2(0,42)
	restart_button.pressed.connect(func():
		command("retry"))
	restart_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	secondary_row.add_child(restart_button)
	style_button(restart_button)
	settings_button=Button.new()
	settings_button.text="设置 · 音量、画质、手柄"
	settings_button.custom_minimum_size=Vector2(0,40)
	settings_button.pressed.connect(open_settings)
	inner.add_child(settings_button)
	style_button(settings_button)
	build_settings_panel(canvas)
	chapter_bar=ChapterBar.new()
	canvas.add_child(chapter_bar)
	canvas.move_child(chapter_bar,0)
	touch.blockers.assign([panel,pause_button,settings_panel])
	restore_fade=ColorRect.new()
	restore_fade.name="RestoreFade"
	restore_fade.color=Color(0,0,0,0)
	restore_fade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	restore_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	restore_fade.visible=false
	var fade_layer:=CanvasLayer.new()
	fade_layer.name="RestoreFadeLayer"
	fade_layer.layer=100
	add_child(fade_layer)
	fade_layer.add_child(restore_fade)
	var pack_layer:=CanvasLayer.new()
	pack_layer.name="ChapterLoadingLayer"
	pack_layer.layer=110
	add_child(pack_layer)
	pack_overlay=LoadingScreen.new()
	pack_overlay.visible=false
	pack_layer.add_child(pack_overlay)
	pack_overlay.retry_pressed.connect(func():ChapterPacks.request(chapter_key(),true))
	pack_overlay.cancel_pressed.connect(func():
		online_entry=false
		if net.active():toggle_online())
	var modes:=HBoxContainer.new()
	modes.add_theme_constant_override("separation",8)
	inner.add_child(modes)
	for entry in [["solo","单人＋搭档"],["online","远程双人"]]:
		var button:=Button.new()
		button.text=entry[1]
		button.set_meta("mode",entry[0])
		button.pressed.connect(func():choose_mode(entry[0]))
		modes.add_child(button)
		style_button(button,false,16,true)
		mode_buttons.append(button)
	online_row=HBoxContainer.new()
	inner.add_child(online_row)
	net_address=LineEdit.new()
	net_address.custom_minimum_size=Vector2(300,42)
	net_address.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	net_address.text=NetClient.default_address()
	online_row.add_child(net_address)
	net_address.add_theme_stylebox_override("normal",glass_style(0.72,0.24,10,8))
	net_address.add_theme_color_override("font_color",Color("f2ede0"))
	net_address.add_theme_color_override("caret_color",Color("e8bd7d"))
	net_button=Button.new()
	net_button.text="连接队友"
	net_button.pressed.connect(toggle_online)
	online_row.add_child(net_button)
	style_button(net_button,false,16,true)
	net_status=label("远程双人：连接同一版本网页",16)
	inner.add_child(net_status)
	touch.blockers.append(net_button)
	var choice:=HBoxContainer.new()
	choice.add_theme_constant_override("separation",8)
	inner.add_child(choice)
	for name in ["简单","普通","困难"]:
		var button:=Button.new()
		button.text=name
		button.pressed.connect(func():
			command("difficulty",name))
		choice.add_child(button)
		style_button(button,false,16,true)
		difficulty_buttons.append(button)

# 设置页：开始页与暂停页共用，只改本机表现与音量，不发送联机命令。
func build_settings_panel(canvas:CanvasLayer) -> void:
	settings_panel=PanelContainer.new()
	settings_panel.name="SettingsPanel"
	settings_panel.add_theme_stylebox_override("panel",glass_style(0.86,0.36,22,14))
	settings_panel.visible=false
	canvas.add_child(settings_panel)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	settings_panel.add_child(column)
	column.add_child(label("设置",30,Color("f7f2e6")))
	for key:String in Settings.VOLUMES:
		var row:=settings_row(column,Settings.VOLUME_NAMES[key])
		var slider:=HSlider.new()
		slider.name="Volume_"+key
		slider.min_value=0;slider.max_value=100;slider.step=5
		slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size.y=28
		style_slider(slider)
		slider.value=settings.volumes[key]*100.0
		slider.value_changed.connect(func(value:float):set_volume(key,value/100.0))
		row.add_child(slider)
		var value_label:=label("",16,Color("cfd6cc"))
		value_label.custom_minimum_size.x=56
		value_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		volume_sliders[key]=slider
		volume_values[key]=value_label
	var quality_row:=settings_row(column,"画质")
	for quality:String in Settings.QUALITIES:
		var button:=Button.new()
		button.text=Settings.QUALITY_NAMES[quality]
		button.set_meta("quality",quality)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():set_quality(quality))
		quality_row.add_child(button)
		style_button(button,false,16,true)
		quality_buttons.append(button)
	var fps_row:=settings_row(column,"帧率上限")
	for cap:int in settings.fps_options():
		var button:=Button.new()
		button.text=Settings.fps_name(cap)
		button.set_meta("fps",cap)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():set_fps_cap(cap))
		fps_row.add_child(button)
		style_button(button,false,16,true)
		fps_buttons.append(button)
	var toggles:=HBoxContainer.new()
	toggles.add_theme_constant_override("separation",8)
	column.add_child(toggles)
	damage_button=Button.new()
	damage_button.pressed.connect(func():
		damage_numbers=not damage_numbers
		save_feel_settings()
		update_journey_ui())
	impact_button=Button.new()
	impact_button.pressed.connect(func():
		impact_effects=not impact_effects
		save_feel_settings()
		update_journey_ui())
	for button in [damage_button,impact_button]:
		button.custom_minimum_size=Vector2(0,40)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		toggles.add_child(button)
		style_button(button,false,16)
	var device_hint:=label("手柄：本地双人时第一个手柄控制 01、第二个控制 02；\n单人与联机时控制本机角色。",13,Color("9fb0a6"))
	device_hint.name="DeviceHint"
	column.add_child(device_hint)
	settings_close=Button.new()
	settings_close.text="返回"
	settings_close.custom_minimum_size=Vector2(0,46)
	settings_close.pressed.connect(close_settings)
	column.add_child(settings_close)
	style_button(settings_close,true)

func settings_row(column:VBoxContainer,caption:String) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	column.add_child(row)
	var caption_label:=label(caption,17,Color("e8e2d2"))
	caption_label.custom_minimum_size.x=96
	row.add_child(caption_label)
	return row

func style_slider(slider:HSlider) -> void:
	var track:=StyleBoxFlat.new()
	track.bg_color=Color(0.015,0.02,0.022,0.85)
	track.border_color=Color(1,1,1,0.12)
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	track.content_margin_top=3;track.content_margin_bottom=3
	var fill:=StyleBoxFlat.new()
	fill.bg_color=Color("e8bd7d")
	fill.set_corner_radius_all(4)
	fill.content_margin_top=3;fill.content_margin_bottom=3
	slider.add_theme_stylebox_override("slider",track)
	slider.add_theme_stylebox_override("grabber_area",fill)
	slider.add_theme_stylebox_override("grabber_area_highlight",fill)
	slider.add_theme_stylebox_override("focus",focus_box())

func open_settings() -> void:
	if run.state not in ["start","paused"]:return
	settings_open=true
	for key in Settings.VOLUMES:volume_sliders[key].set_value_no_signal(settings.volumes[key]*100.0)
	update_journey_ui()
	if gamepad_active:volume_sliders.master.grab_focus()

func close_settings() -> void:
	if not settings_open:return
	settings_open=false
	if settings_dirty:save_feel_settings()
	update_journey_ui()
	if gamepad_active and settings_button.is_visible_in_tree():settings_button.grab_focus()

func set_volume(key:String,value:float) -> void:
	settings.volumes[key]=clampf(value,0.0,1.0)
	settings_dirty=true
	apply_audio_settings()
	update_settings_panel()

func set_quality(value:String) -> void:
	if value not in Settings.QUALITIES:return
	settings.quality=value
	settings_dirty=true
	apply_render_quality()
	update_settings_panel()

func set_fps_cap(value:int) -> void:
	if value not in settings.fps_options():return
	settings.fps_cap=value
	settings_dirty=true
	if OS.has_feature("web"):apply_web_quality()
	else:Engine.max_fps=value
	update_settings_panel()

# 设置页只在开始页与暂停页存在；联机队友恢复游戏时自动收起并保存。
func update_settings_panel() -> void:
	if not is_instance_valid(settings_panel):return
	if settings_open and (run.state not in ["start","paused"] or get_meta("credits",false)):
		settings_open=false
		if settings_dirty:save_feel_settings()
	settings_panel.visible=settings_open
	if not settings_open:return
	for key in Settings.VOLUMES:volume_values[key].text="%d%%"%roundi(settings.volumes[key]*100.0)
	for button in quality_buttons:mark_choice(button,button.get_meta("quality")==settings.quality)
	for button in fps_buttons:mark_choice(button,int(button.get_meta("fps"))==settings.fps_cap)
	damage_button.text="伤害数字：%s"%("开" if damage_numbers else "关")
	impact_button.text="画面冲击与震动：%s"%("开" if impact_effects else "关")
	var viewport:=get_viewport().get_visible_rect().size
	var width:=minf(640.0,viewport.x-32)
	settings_panel.size=Vector2(width,0)
	var height:=minf(settings_panel.get_combined_minimum_size().y,viewport.y-24)
	settings_panel.size=Vector2(width,height)
	settings_panel.position=Vector2((viewport.x-width)/2,maxf(12.0,(viewport.y-height)/2))

# 手柄导航时才显示焦点描边；鼠标点击后的焦点保持不可见，与原有按钮外观一致。
func focus_box() -> StyleBox:
	if not gamepad_active:return StyleBoxEmpty.new()
	if focus_style==null:
		focus_style=StyleBoxFlat.new()
		focus_style.draw_center=false
		focus_style.border_color=Color("fff0cd")
		focus_style.set_border_width_all(2)
		focus_style.set_corner_radius_all(8)
		focus_style.expand_margin_left=3;focus_style.expand_margin_right=3
		focus_style.expand_margin_top=3;focus_style.expand_margin_bottom=3
	return focus_style

func set_gamepad_active(value:bool) -> void:
	if gamepad_active==value:return
	gamepad_active=value
	for host in [panel,settings_panel]:
		if not is_instance_valid(host):continue
		for control in host.find_children("*","Control",true,false):
			if control is Button or control is HSlider:control.add_theme_stylebox_override("focus",focus_box())
	if is_instance_valid(hud):update_journey_ui()

# 手柄打开菜单时把焦点放到可见的第一个控件上，十字键 / 摇杆即可导航，A 确认。
func ensure_menu_focus() -> void:
	var host:Control=null
	if settings_panel.visible:host=settings_panel
	elif panel.visible:host=panel
	if host==null:return
	var focused:=get_viewport().gui_get_focus_owner()
	if focused!=null and focused.is_visible_in_tree() and host.is_ancestor_of(focused):return
	var target:Control=volume_sliders.master if host==settings_panel else null
	if target==null and primary.is_visible_in_tree() and not primary.disabled:target=primary
	if target==null:
		for control in host.find_children("*","Button",true,false):
			if control.is_visible_in_tree() and not control.disabled:target=control;break
	if target!=null:target.grab_focus()

func handle_pad_button(event:InputEventJoypadButton) -> void:
	var role:=Gamepad.role_for(event.device,play_mode=="local")
	match event.button_index:
		JOY_BUTTON_START:
			if settings_open:close_settings()
			else:
				command("pause")
				clear_controls()
			get_viewport().set_input_as_handled()
		JOY_BUTTON_B:
			if settings_open:
				close_settings()
				get_viewport().set_input_as_handled()
			elif run.state=="paused" and not get_meta("credits",false):
				command("pause")
				clear_controls()
				get_viewport().set_input_as_handled()
		JOY_BUTTON_X:
			if run.state=="running":
				if role==0:reload_requested=true
				elif role==1:reload_requested_b=true
		JOY_BUTTON_Y:
			if run.state=="running":
				if role==0:drop_requested=true
				elif role==1:drop_requested_b=true
		JOY_BUTTON_LEFT_SHOULDER:
			if run.state=="running":
				if role==0:swap_requested=true
				elif role==1:swap_requested_b=true

func glass_style(alpha:float=0.72,border_alpha:float=0.30,pad:int=16,radius:int=10) -> StyleBoxFlat:
	# 统一的暗色玻璃面板：深底、细暖边、圆角和轻微投影。
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(0.045,0.06,0.07,alpha)
	style.border_color=Color(0.92,0.78,0.52,border_alpha)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left=pad
	style.content_margin_right=pad
	style.content_margin_top=pad
	style.content_margin_bottom=pad
	style.shadow_color=Color(0,0,0,0.35)
	style.shadow_size=10
	return style

func mark_choice(button:Button,selected:bool) -> void:
	# 模式/难度当前项的选中态；重复调用只在状态变化时改样式。
	if button.get_meta("choice_selected",false)==selected:return
	button.set_meta("choice_selected",selected)
	if selected:
		var style:=glass_style(0.98,0.80,10,8)
		style.bg_color=Color("e8bd7d")
		style.border_color=Color("fff0cd")
		button.add_theme_stylebox_override("normal",style)
		button.add_theme_stylebox_override("hover",style)
		button.add_theme_color_override("font_color",Color("211d16"))
		button.add_theme_color_override("font_hover_color",Color("211d16"))
	else:
		style_button(button,false,16,true)

func style_button(button:Button,accent:bool=false,font_size:int=19,compact:bool=false) -> void:
	# 主按钮用暖金实心，其余用暗色玻璃；悬停和按下只改亮度和描边。
	var normal:=glass_style(0.86 if not accent else 1.0,0.30,12 if compact else 16,8)
	normal.bg_color=Color("e8bd7d") if accent else Color(0.06,0.08,0.09,0.80)
	normal.border_color=Color("f4d9a6") if accent else Color(0.80,0.68,0.48,0.34)
	normal.content_margin_top=8 if compact else 12
	normal.content_margin_bottom=8 if compact else 12
	var hover:StyleBoxFlat=normal.duplicate()
	hover.bg_color=Color("f2cd90") if accent else Color(0.10,0.13,0.14,0.90)
	hover.border_color=Color("fff0cd") if accent else Color(0.95,0.82,0.60,0.58)
	var pressed:StyleBoxFlat=normal.duplicate()
	pressed.bg_color=Color("d8ad6e") if accent else Color(0.035,0.045,0.05,0.94)
	var disabled:StyleBoxFlat=normal.duplicate()
	disabled.bg_color=Color(0.08,0.09,0.10,0.45)
	disabled.border_color=Color(1,1,1,0.08)
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",pressed)
	button.add_theme_stylebox_override("disabled",disabled)
	button.add_theme_stylebox_override("focus",focus_box())
	button.add_theme_color_override("font_color",Color("211d16") if accent else Color("f2ede0"))
	button.add_theme_color_override("font_hover_color",Color("211d16") if accent else Color("ffffff"))
	button.add_theme_color_override("font_pressed_color",Color("211d16") if accent else Color("efe6d4"))
	button.add_theme_color_override("font_disabled_color",Color(0.7,0.7,0.7,0.5))
	button.add_theme_font_size_override("font_size",font_size)
	if compact:
		button.custom_minimum_size=Vector2(0,36)

func build_post_fx() -> void:
	# HUD 在 CanvasLayer 1，后处理放在 0：只压 3D 画面，不压界面。
	post_canvas=CanvasLayer.new()
	post_canvas.name="PostFX"
	post_canvas.layer=0
	add_child(post_canvas)
	var vignette:=ColorRect.new()
	vignette.name="Vignette"
	vignette.mouse_filter=Control.MOUSE_FILTER_IGNORE
	vignette_mat=ShaderMaterial.new()
	vignette_mat.shader=preload("res://scripts/journey_vignette.gdshader")
	vignette_mat.set_shader_parameter("damage",0.0)
	vignette_mat.set_shader_parameter("low",0.0)
	vignette_mat.set_shader_parameter("impact",0.0)
	vignette.material=vignette_mat
	post_canvas.add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func hud_panel(canvas: CanvasLayer) -> PanelContainer:
	var result:=PanelContainer.new()
	result.add_theme_stylebox_override("panel",glass_style(0.58,0.26,12,10))
	result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(result)
	return result

func health_bar(color: Color, height: float) -> ProgressBar:
	var result:=ProgressBar.new()
	result.custom_minimum_size=Vector2(0,height)
	result.show_percentage=false
	result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var back:=StyleBoxFlat.new()
	back.bg_color=Color(0.015,0.02,0.022,0.85)
	back.set_corner_radius_all(int(height*0.5))
	back.border_color=Color(1,1,1,0.10)
	back.set_border_width_all(1)
	var fill:=StyleBoxFlat.new()
	fill.bg_color=color
	fill.set_corner_radius_all(int(height*0.5))
	fill.shadow_color=Color(color.r,color.g,color.b,0.40)
	fill.shadow_size=5
	result.add_theme_stylebox_override("background",back)
	result.add_theme_stylebox_override("fill",fill)
	return result

func reset_journey_views() -> void:
	buddy.reset()
	failed_animation_started=[false,false]
	rescue_seen=[0,0]
	rescue_pulse=[0.0,0.0]
	body_yaw=[0.0,0.0]
	last_fire_sent=false
	prepared_online_frame=-1
	# 固定关卡重试只需刷新阶段和反馈，不重建相同的环境模型。
	floor_stamp=""
	sound_events.clear()
	if is_instance_valid(sfx): sfx.stop_loops()
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
			# 纯画面转场：从黑场淡入，位置与判定已由快照恢复完成。
			restore_fade_left=RESTORE_FADE
			toasted_checkpoint=run.checkpoint.get("progress",-INF)
		"complete": run.new_campaign();reset_journey_views()
		"settlement":
			run.confirm_step(false,false)
			run.confirm_step(true,true)
			reset_journey_views()
	clear_controls()

func _unhandled_key_input(event: InputEvent) -> void:
	if not scene_prepared: return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if settings_open:
		if event.keycode==KEY_ESCAPE:close_settings()
		return
	if event.keycode==KEY_ESCAPE:
		command("pause")
		clear_controls()
	elif event.keycode==KEY_R and run.state=="running": reload_requested=true
	elif event.keycode==KEY_G and run.state=="running": drop_requested=true
	elif event.keycode==KEY_Q and run.state=="running": swap_requested=true
	elif event.keycode==KEY_ENTER and run.state in ["start","failed","complete"]: journey_primary()
	elif event.keycode==KEY_SPACE and run.state=="failed": journey_primary()
	elif event.keycode==KEY_F1:
		if run.state in ["running","rescue"]: command("pause")
		elif run.state=="start":run.paused_from="start";run.state="paused"
		title.text="素材与制作"
		subtitle.text="角色、松树、草与灌木：Quaternius，CC0。\n扫描地面与石材、天空：Poly Haven，CC0。\n工业建筑：Kenney，CC0。\n房屋、野猪、推车、水车、门与吊桥：项目 Blender 制作脚本。\n音效：Kenney，CC0。音乐：TinyWorlds《Forest Ambience》、Komiku《Village, 2018》、congusbongus《Cathedral in the Forest》、Ferk 循环版《Cynic Battle Loop》（原曲 Alex Smith / cynicmusic），均 CC0。\n字体：Noto Sans SC，SIL OFL 1.1。\n完整来源与修改记录见 ASSET_SOURCES.md。"
		set_meta("credits",true)

func _physics_process(delta: float) -> void:
	if web_test_mode:return
	var measured_start:=Time.get_ticks_usec() if web_verify else 0
	touch.set_enabled(touch_device and play_mode!="local" and run.state in ["running","rescue","settlement"])
	if net.active():
		online_process(delta)
		return
	# 本局章节的数据还没挂载（网页按章下载，例如结算后进入下一章）：暂停模拟，载入画面显示下载进度。
	if not ChapterPacks.is_ready(chapter_key()):
		ChapterPacks.request(chapter_key(),true)
		return
	if incremental_loading and not prepare_journey_frame():
		update_journey_ui()
		journey_hint.text="正在准备前方路段…" if chunk_assets.error.is_empty() else "资源读取失败，请刷新网页重试："+chunk_assets.error.get_file()
		return
	var measured_prepared:=Time.get_ticks_usec() if web_verify else 0
	var input:=sample_local_input()
	run.solo_control=play_mode=="solo"
	run.external_companion=not run.combat_trial
	run.set_combat_input(input.get("fire",false),input.get("reload",false),input.get("drop",false),input.get("swap",false))
	# 本地双人的 02 由第二个手柄射击；沿用联机的战斗命令格式写入角色 1。
	if play_mode=="local" and input.has("fire_b"):apply_combat_command(1,"%d,%d,%d,%d"%[int(input.fire_b),int(input.reload_b),int(input.drop_b),int(input.get("swap_b",false))])
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

func _process(delta:float)->void:
	# 受击红边和低血量暗角先于视图更新，暂停时也自然衰减。
	if is_instance_valid(vignette_mat):
		damage_flash=maxf(0.0,damage_flash-delta*2.4)
		impact_flash=maxf(0.0,impact_flash-delta/IMPACT_TIME)
		vignette_mat.set_shader_parameter("damage",damage_flash)
		vignette_mat.set_shader_parameter("impact",impact_flash if impact_effects else 0.0)
		vignette_mat.set_shader_parameter("low",low_health)
	update_restore_feedback(delta)
	update_pack_overlay()
	prefetch_next_chapter(delta)
	# 每个画面帧只提交一次最终状态，本地与网页使用同一规则。
	if scene_prepared and view_pending:
		view_pending=false
		var started:=Time.get_ticks_usec()
		frame_delta=delta
		sync_view()
		pump_ambience(delta)
		if web_verify:
			var cost:Dictionary=frame_costs.get("render_view",{"samples":0,"total_usec":0,"max_usec":0})
			var duration:=Time.get_ticks_usec()-started
			cost.samples+=1;cost.total_usec+=duration;cost.max_usec=maxi(cost.max_usec,duration)
			frame_costs.render_view=cost
	# 暂停、失败、救援、结算与开始页时，喷火/滚石/机械等持续声一律停下。
	if run.state!="running" and is_instance_valid(sfx): sfx.stop_loops()

# 面板尺寸按本帧可见按钮和文字计算；失败时改为底部紧凑条，不挡住仍在播放的失败演出。
func layout_panel() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var compact: bool=run.state=="failed"
	title.add_theme_font_size_override("font_size",24 if compact else 38)
	# 失败条收紧行距，保持在屏幕下方四成以内。
	panel.get_child(0).add_theme_constant_override("separation",6 if compact else 12)
	var panel_width:=minf(640.0 if compact else 800.0,viewport.x-32)
	# 自动换行的文字要先给定宽度，最小高度才按实际行数计算；之后再收缩面板，避免容器按 1 像素宽的文字撑高。
	var style:StyleBox=panel.get_theme_stylebox("panel")
	var text_width:=maxf(0.0,panel_width-style.get_content_margin(SIDE_LEFT)-style.get_content_margin(SIDE_RIGHT))
	subtitle.custom_minimum_size.x=text_width
	subtitle.size.x=text_width
	panel.size=Vector2(panel_width,0)
	var panel_height:=clampf(panel.get_combined_minimum_size().y,0.0 if compact else 260.0,maxf(0.0,viewport.y-24))
	panel.size=Vector2(panel_width,panel_height)
	var panel_y:=viewport.y-panel_height-24 if compact else (viewport.y-panel_height)/2
	panel.position=Vector2((viewport.x-panel_width)/2,maxf(12,panel_y))

# 恢复转场与存档提示只读模拟状态，不影响联机同步。
func update_restore_feedback(delta: float) -> void:
	if is_instance_valid(restore_fade):
		restore_fade_left=maxf(0.0,restore_fade_left-delta)
		restore_fade.visible=restore_fade_left>0.0
		restore_fade.color.a=restore_fade_left/RESTORE_FADE
	if not is_instance_valid(checkpoint_toast) or not scene_prepared: return
	var saved: float=run.checkpoint.get("progress",-INF)
	if run.checkpoint.is_empty(): toasted_checkpoint=-INF
	elif saved!=toasted_checkpoint and run.state=="running":
		toasted_checkpoint=saved
		checkpoint_toast_left=CHECKPOINT_TOAST
		if is_instance_valid(sfx): sfx.play("coin_land",-14.0,0.7)
	checkpoint_toast_left=maxf(0.0,checkpoint_toast_left-delta)
	checkpoint_toast.visible=checkpoint_toast_left>0.0
	checkpoint_toast.modulate.a=clampf(checkpoint_toast_left/0.25,0.0,1.0)

func clear_controls() -> void:
	if is_instance_valid(net) and net.active() and net.in_match:
		# 联机模拟状态只在共同帧修改，本地只清理设备输入。
		blocked_keys.assign(MOVE_KEYS)
		if is_instance_valid(touch):touch.reset()
	else:super()
	reload_requested=false
	drop_requested=false
	swap_requested=false
	reload_requested_b=false
	drop_requested_b=false
	swap_requested_b=false
	fire_blocked=true
	pad_blocked=true

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and is_instance_valid(touch):
		touch_device=true
		touch.set_enabled(run.state in ["running","rescue","settlement"])
	# 最近一次使用的设备决定提示文字：手柄按键或摇杆切到手柄，键盘或鼠标按下切回键鼠。
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value)>0.5):
		set_gamepad_active(true)
	elif (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		set_gamepad_active(false)
	if event is InputEventJoypadButton and event.pressed and scene_prepared:handle_pad_button(event)

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
		var night:float=float(atmosphere.palette_for(run.level_index).hero_light) if atmosphere and atmosphere.enabled else 0.0
		rope_view.energy_level=1.0+night*0.6
		rope_view.set_tension(run.rope_tension(),run.rope_status(),get_process_delta_time() if run.state=="running" else 0.0)
		rope_view.simulate(path,0,Color.WHITE,0)
		sync_rope_light(path,night)
	update_journey_camera()
	var theme:String=run.theme_at(run.distance)
	var forest_weight:float=Landscape.profile(run.distance/SCALE,run.level_index).y if not run.combat_trial else 0.65
	canopy_light.light_energy=lerpf(1.25,1.05,forest_weight)*(Atmosphere.SUN_SCALE if atmosphere.enabled else 1.0)
	canopy_light.light_color=Color("ffe2bd").lerp(Color("e7edce"),forest_weight)
	world_environment.ambient_light_energy=lerpf(0.66,0.58,forest_weight)*(Atmosphere.AMBIENT_SCALE if atmosphere.enabled else 1.0)
	# 旧值 0.0032/0.0065 让中景整片发灰；保留空气透视但把层次还给模型和阴影。
	world_environment.fog_density=lerpf(0.0021,0.0042,forest_weight)
	world_environment.fog_sky_affect=forest_weight*.85
	landscape.leaf_material.set_shader_parameter("phase",run.elapsed)
	landscape.palette.NaturalLeaf.set_shader_parameter("phase",run.elapsed)
	world_environment.fog_light_color=Color("a19a8b").lerp(Color("7e9182"),forest_weight)
	atmosphere.sync(camera,run.distance/SCALE,run.level_index,forest_weight)
	var middle:Vector2=(run.a.position+run.b.position)*.5
	fx.sync_ambient(Vector3(middle.x/SCALE,0,-middle.y/SCALE),forest_weight,1.0-forest_weight,1.0 if run.level_index==2 else 0.0)
	fx.sync_time_of_day(Vector3(middle.x/SCALE,0,-middle.y/SCALE),run.level_index,forest_weight)
	var lamp:float=atmosphere.lamp_level(run.level_index) if atmosphere else 0.0
	for chunk in world_chunks.values():
		if not chunk.visible:continue
		for node in chunk.get_meta("wind_nodes",[]):
			node.rotation.z=sin(run.elapsed*1.1+float(node.get_meta("wind")))*0.008
		for entry in chunk.get_meta("beacons",[]):
			var on:bool=fmod(run.elapsed*.8+float(entry[2]),1.0)<.18
			entry[0].visible=on;entry[1].visible=on
		for light:OmniLight3D in chunk.get_meta("flicker_lights",[]):
			var seed:float=light.get_meta("flicker")
			light.light_energy=4.2*lamp*(0.86+0.1*sin(run.elapsed*13.0+seed)+0.06*sin(run.elapsed*29.0+seed*2.3))
	sync_hero_lights(float(atmosphere.palette_for(run.level_index).hero_light) if atmosphere and atmosphere.enabled else 0.0)
	sync_journey_rewards()
	if is_instance_valid(combat_view): combat_view.sync()
	if path.size()>1:sync_rescue_hands(path)
	if coop_fx:coop_fx.sync(path)
	update_journey_ui()
	publish_web_verification()

# 救援时双手握绳：被救者双手握在头顶上方的绳段并交替倒手，拉绳者双手握在身前的绳段。
# 必须在战斗视图之后调用（它每帧清除骨骼覆盖）；只改表现，不改模拟。
func sync_rescue_hands(path:Array[Vector3])->void:
	if run.rescue.is_empty() or not (run.state=="rescue" or (run.state=="paused" and run.paused_from=="rescue")):return
	var hanging:int=run.rescue.role
	var total:=0.0
	for n in range(1,path.size()):total+=path[n-1].distance_to(path[n])
	var phase:float=float(run.rescue.progress)*TAU*3.0+float(run.rescue.get("climb",0.0))*TAU*1.6
	for role in range(2):
		hand_point(role)
		var skeleton:Skeleton3D=hand_skeletons.get(role)
		if not is_instance_valid(skeleton):continue
		# 从本人一端沿绳子量取握点；被救者握在腰部以上 0.5–1.0 米，拉绳者握在身前 0.45–0.8 米。
		var near:=0.0 if role==0 else total
		var sign:=1.0 if role==0 else -1.0
		var grips:Array[float]
		if role==hanging:
			grips=[0.75+0.22*sin(phase),0.75+0.22*sin(phase+PI)]
		else:
			grips=[0.45+0.08*sin(phase*0.5),0.8+0.08*sin(phase*0.5)]
		for k in range(2):
			var target:=RopeView.along(path,clampf(near+sign*grips[k],0.0,total))
			combat_view.reach_hand(skeleton,"L" if k==0 else "R",target)

var rope_light:OmniLight3D
func sync_rope_light(path:Array[Vector3],night:float)->void:
	if OS.has_feature("web") or landscape.mobile:return
	if rope_light==null:
		rope_light=OmniLight3D.new();rope_light.name="RopeLight"
		rope_light.shadow_enabled=false;rope_light.omni_range=4.5;rope_light.omni_attenuation=1.3
		rope_light.light_volumetric_fog_energy=0.0
		add_child(rope_light)
	var total:=0.0
	for n in range(1,path.size()):total+=path[n-1].distance_to(path[n])
	rope_light.position=RopeView.along(path,total*.5)+Vector3(0,.25,0)
	var tension:=clampf(run.rope_tension(),0.0,1.0)
	var blocked:bool=run.rope_status() in ["blocked","unwinding","failed"]
	rope_light.light_color=Color("ff4a3a") if blocked else Color("9fe8ff").lerp(Color("ffc58a"),.5)
	rope_light.light_energy=(0.35+0.5*tension+night*0.6)*(1.6 if blocked else 1.0)

# 夜间随身灯：两人头顶各一盏暖/冷色小灯照亮自身与绳索，
# 再各绑一盏朝前方路面的头灯（聚光），把前方约 20 米内的机关照出来。
var hero_lights:Array[OmniLight3D]=[]
var head_lamps:Array[SpotLight3D]=[]
func sync_hero_lights(level:float)->void:
	if hero_lights.is_empty():
		if level<=0.0:return
		for i in range(2):
			var light:=OmniLight3D.new()
			light.light_color=Color("bfeaff") if i==0 else Color("ffe2c4")
			light.omni_range=9.0;light.omni_attenuation=1.0
			light.shadow_enabled=false
			light.light_volumetric_fog_energy=0.6
			add_child(light);hero_lights.append(light)
			var lamp:=SpotLight3D.new()
			lamp.light_color=Color("e6f4ff") if i==0 else Color("fff0dc")
			lamp.spot_range=22.0;lamp.spot_angle=32.0;lamp.spot_angle_attenuation=0.7;lamp.spot_attenuation=0.45
			lamp.shadow_enabled=false;lamp.light_volumetric_fog_energy=1.4
			add_child(lamp);head_lamps.append(lamp)
	for i in range(2):
		var light:=hero_lights[i]
		light.visible=level>0.0 and is_instance_valid(robots[i])
		head_lamps[i].visible=light.visible
		if not light.visible:continue
		light.light_energy=0.75*level
		light.global_position=robots[i].global_position+Vector3(0,3.6,1.6)
		var lamp:=head_lamps[i]
		lamp.visible=true;lamp.light_energy=10.0*level
		var head:=robots[i].global_position+Vector3(0,2.0,0.2)
		lamp.global_position=head
		lamp.look_at(robots[i].global_position+Vector3(0,0,-9.0),Vector3.UP)

# 旅程使用固定世界坐标；沿用道路版动作与腰部旋转，身体仍由真实物理位置驱动。
func sync_journey_character(i:int)->void:
	var visual_state:String=run.paused_from if run.state=="paused" else run.state
	var rescuing:bool=visual_state=="rescue" and not run.rescue.is_empty()
	var hanging:bool=rescuing and i==run.rescue.role
	for child in robots[i].get_children():
		if child is Label3D:child.visible=visual_state not in ["rescue","failed"]
	robots[i].rotation=Vector3.ZERO
	track_hero_motion(i)
	if run.state!="paused":body_yaw[i]=lerp_angle(body_yaw[i],combat_body_yaw(i,visual_state),clampf(frame_delta*BODY_TURN_RATE,0.0,1.0))
	if absf(body_yaw[i])>0.001:robots[i].rotation.y=body_yaw[i]
	# 横移与后退由侧步/后退步混合表现，身体保持朝前；前进时上身前倾，后退时近乎直立。
	if visual_state=="running" and run.actions[i]=="Run":
		var direction:Vector2=run.move_directions[i]
		robots[i].rotation.x=-0.06-0.14*maxf(direction.y,0.0)+0.05*maxf(-direction.y,0.0)
		robots[i].rotation.z=-direction.x*0.06
	# 落地缓冲：下落高度决定轻/重缓冲动作和整体压缩幅度；只改画面，不改物理高度和碰撞。
	if run.heights[i]>0.0:air_top[i]=maxf(air_top[i],run.foot_height(i))
	if visual_last_heights[i]>0.0 and run.heights[i]<=0.0:
		var drop:float=maxf(0.0,air_top[i]-run.floor_heights[i])
		landing_strength[i]=clampf(drop/(Run.JUMP_APEX*2.0),0.0,1.0)
		landing_clip[i]="Jump_Land_Heavy" if drop>Run.JUMP_APEX*HEAVY_LANDING else "Jump_Land"
		landing_left[i]=1.0
		if visual_last_heights[i]>6.0:
			land_impact[i]=landing_strength[i]
			if i==(net.role if play_mode=="online" and net.in_match else 0): rumble(0.25,0.15,0.06)
	if run.heights[i]<=0.0:air_top[i]=run.floor_heights[i]
	if visual_state=="running": play_footsteps(i)
	visual_last_heights[i]=run.heights[i]
	land_impact[i]=maxf(0.0,land_impact[i]-frame_delta*7.0)
	if i<character_models.size():
		var model_node:Node3D=character_models[i]
		var base:Vector3=model_node.get_meta("base_scale",model_node.scale)
		# 缓冲动作已经屈膝，整体压缩只留一点重量感。
		var squash:float=land_impact[i]
		var target_scale:Vector3=base*Vector3(1.0+squash*0.05,1.0-squash*0.08,1.0+squash*0.05)
		if not model_node.scale.is_equal_approx(target_scale):model_node.scale=target_scale
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
	var rig=hero_rig(i)
	# 救援、受击/死亡与坠落只播放原有整段动作，步态层全部让位。
	var locomotion:bool=visual_state in ["running","start","settlement","complete"] and not rescuing and not falling()
	if rig!=null:sync_hero_rig(i,rig,locomotion,visual_state)
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
	var action:String=run.actions[i]
	if action not in ["Idle","Run"]:action="Run"
	if run.state in ["start","settlement","complete"]:action="Idle"
	if run.heights[i]>0.0:
		landing_left[i]=0.0
		# 起跳段：竖直速度从起跳速度降到 60%；腾空段：从 60% 一直到落地前的下落速度。
		var rising:float=run.vertical_speed[i]
		action="Jump_Start" if rising>Run.JUMP_SPEED*0.6 else "Jump_Air"
		var phase:float=(Run.JUMP_SPEED-rising)/(Run.JUMP_SPEED*0.4) if action=="Jump_Start" else (Run.JUMP_SPEED*0.6-rising)/(Run.JUMP_SPEED*1.6)
		play_action(player,action)
		player.seek(clampf(phase,0,1)*player.current_animation_length,true)
		return
	if landing_left[i]>0.0 and visual_state=="running":
		# 轻落地 0.25–0.4 秒，重落地约 0.7 秒；轻缓冲越轻播得越快。
		play_action(player,landing_clip[i])
		var heavy:bool=landing_clip[i]=="Jump_Land_Heavy"
		player.speed_scale=lerpf(1.6,1.0,landing_strength[i]/0.625) if not heavy else lerpf(1.1,0.9,landing_strength[i])
		landing_left[i]=maxf(0.0,landing_left[i]-frame_delta*player.speed_scale/maxf(player.current_animation_length,0.01))
		return
	play_action(player,action)
	if action=="Run":
		player.speed_scale=clampf(hero_velocity[i].length()/HERO_STRIDE_SPEED[i],0.6,4.0)

# 开火锁定的目标偏离道路前方较多时，返回身体应转向的偏航；否则回到 0（面朝前方）。
func combat_body_yaw(i:int,visual_state:String)->float:
	if visual_state!="running" or run.combat.is_empty() or falling():return 0.0
	var weapon:Dictionary=run.combat.weapons[i]
	if weapon.is_empty():return 0.0
	var shot:Dictionary=run.combat.shots[i]
	var firing:bool=run.combat.fire[i] or (not shot.is_empty() and run.elapsed-float(shot.time)<BODY_TURN_HOLD)
	if not firing:return 0.0
	var from:Vector2=run.a.position if i==0 else run.b.position
	for event in run.journey_events:
		if event.id!=weapon.target:continue
		var direction:Vector2=run.Combat.enemy_position(event)-from
		if direction.length()<1.0:break
		var yaw:=atan2(-direction.x,direction.y)
		# 已经转身时放宽门槛，目标在门槛附近摆动不会让身体来回抽动。
		if absf(yaw)>BODY_TURN_MIN or absf(body_yaw[i])>BODY_TURN_MIN*0.5:return yaw
		break
	return 0.0

# 水平速度取模拟时间内的真实位移；重试、读档或换章的整段位移不计。
func track_hero_motion(i:int)->void:
	var point:Vector2=run.a.position if i==0 else run.b.position
	var elapsed:float=run.elapsed
	var dt:float=elapsed-hero_last_time[i]
	if hero_last_time[i]<0.0 or dt<0.0 or (dt>0.0 and point.distance_to(hero_last_pos[i])/SCALE>STEP_TELEPORT):
		hero_velocity[i]=Vector2.ZERO
	elif dt>0.0:
		hero_velocity[i]=(point-hero_last_pos[i])/dt/SCALE
	if dt!=0.0 or hero_last_time[i]<0.0:
		hero_last_pos[i]=point
		hero_last_time[i]=elapsed

func hero_rig(i:int):
	if hero_rigs[i]!=null and is_instance_valid(hero_rigs[i]):return hero_rigs[i]
	hand_point(i)
	var skeleton:Skeleton3D=hand_skeletons.get(i)
	if not is_instance_valid(skeleton) or i>=animation_players.size():return null
	var rig:=HeroLocomotion.new()
	rig.name="HeroLocomotion"
	skeleton.add_child(rig)
	rig.setup(animation_players[i])
	rig.ground=hero_ground
	hero_rigs[i]=rig
	return rig

func hero_ground(world:Vector3)->float:
	var surface:Dictionary=run.surface_at(Vector2(world.x*SCALE,-world.z*SCALE),run.elapsed)
	return float(surface.height)/SCALE if surface.supported else NAN

func sync_hero_rig(i:int,rig,locomotion:bool,visual_state:String)->void:
	var player:AnimationPlayer=animation_players[i]
	var blend:float=clampf(frame_delta*10.0,0.0,1.0)
	# 侧步权重：以实际水平速度方向分解为前/后/左/右，前后先合成，再按侧向占比混入侧步。
	var targets:={"Run_Back":0.0,"Run_Left":0.0,"Run_Right":0.0}
	var velocity:Vector2=hero_velocity[i]
	# 身体转向开火时，步态按身体自身的前后左右分解，倒退着走就播后退步。
	if absf(body_yaw[i])>0.001:
		var yaw:float=body_yaw[i]
		velocity=Vector2(velocity.dot(Vector2(cos(yaw),sin(yaw))),velocity.dot(Vector2(-sin(yaw),cos(yaw))))
	if locomotion and visual_state=="running" and run.heights[i]<=0.0 and run.actions[i]=="Run" and velocity.length()>0.5:
		var forward:float=velocity.y/velocity.length()
		var side:float=velocity.x/velocity.length()
		var total:float=absf(forward)+absf(side)
		var back:float=maxf(-forward,0.0)/total
		targets.Run_Back=back/maxf(back+maxf(forward,0.0)/total,0.001)
		targets.Run_Right=maxf(side,0.0)/total
		targets.Run_Left=maxf(-side,0.0)/total
	for clip in targets:hero_strafe[i][clip]=lerpf(hero_strafe[i][clip],targets[clip],blend)
	rig.strafe=hero_strafe[i] if player.current_animation.ends_with("Run") else {"Run_Back":0.0,"Run_Left":0.0,"Run_Right":0.0}
	if player.current_animation!="":rig.run_phase=player.current_animation_position/maxf(player.current_animation_length,0.001)
	var weapon:Dictionary=run.combat.weapons[i]
	var armed:bool=not weapon.is_empty() and visual_state not in ["rescue","failed","complete","settlement"] and not falling()
	rig.gun_weight=move_toward(rig.gun_weight,1.0,frame_delta*6.0) if armed else 0.0
	# 双臂由战斗画面的手部 IK 握住枪（抱枪跑、瞄准、换弹），持枪层只带胸口。
	rig.gun_arms=false
	# 双脚贴地只在着地行进时启用；离地、救援、死亡与坠落立即关闭。
	rig.foot_weight=1.0 if locomotion and run.heights[i]<=0.0 else 0.0
	rig.ground_ref=run.floor_heights[i]/SCALE

# 战斗画面按此读取手腕：持枪层改过手臂时取修改后的最终姿势，枪不会脱手。
func final_bone_pose(skeleton:Skeleton3D,bone:int)->Transform3D:
	var rig=skeleton.get_node_or_null("HeroLocomotion")
	if rig!=null and rig.has_pose(bone):return rig.final_pose(bone)
	return skeleton.get_bone_global_pose(bone)

# 手柄与手机触觉，只在本机执行，不进入联机状态。
func rumble(weak: float, strong: float, seconds: float) -> void:
	if not impact_effects: return
	for device in Input.get_connected_joypads(): Input.start_joy_vibration(device,weak,strong,seconds)
	if touch_device: Input.vibrate_handheld(int(seconds*1000.0),clampf(maxf(weak,strong),0.1,1.0))

func load_feel_settings() -> void:
	# 以文件为准：缺失的键回到默认值。
	settings=Settings.new(settings.platform)
	settings.read_file(SETTINGS_PATH)
	impact_effects=settings.impact_effects
	damage_numbers=settings.damage_numbers

func save_feel_settings() -> void:
	settings.impact_effects=impact_effects
	settings.damage_numbers=damage_numbers
	settings.write_file(SETTINGS_PATH)
	settings_dirty=false

func fail_showing()->bool:
	# 使用模拟死亡时间，联机双方对重试时机的判断一致；演出开头 0.6 秒不接受确认，避免误触。
	return run.state=="failed" and run.death_time<FAIL_SKIP_AFTER

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
	return boss_camera(home)

# 开战后到离开场地前都用 Boss 镜头：场地内可以后退，旅程镜头按最远进度定位会把人甩到画面外。
# 入场动画期间由 BossView 的运镜接管，结束时正好落在 Boss 镜头上。
func boss_camera(home:Transform3D)->Transform3D:
	var event:Dictionary=run.Boss.boss(run)
	if run.Boss.cinematic(run):
		boss_camera_blend=1.0
		var shot:Dictionary=BossView.intro_camera(self,event,home,boss_shot(event))
		camera.fov=shot.fov
		return shot.transform
	var active:bool=not event.is_empty() and event.phase!="dormant" and run.progress()<run.finish_distance()
	boss_camera_blend=move_toward(boss_camera_blend,1.0 if active else 0.0,frame_delta*0.7)
	camera.fov=lerpf(57.0,BOSS_FOV,smoothstep(0.0,1.0,boss_camera_blend))
	if boss_camera_blend<=0.0:
		boss_camera_focus=-1.0
		return home
	return home.interpolate_with(boss_shot(event),smoothstep(0.0,1.0,boss_camera_blend))

func boss_shot(event:Dictionary)->Transform3D:
	var middle:float=clampf((run.a.position.y+run.b.position.y)*0.5,event.arena+run.Boss.FLOOR,event.arena+run.Boss.HOLD+200.0)
	boss_camera_focus=middle if boss_camera_focus<0.0 else lerpf(boss_camera_focus,middle,clampf(frame_delta*2.5,0.0,1.0))
	var eye:=Vector3(0,BOSS_EYE_HEIGHT,-(boss_camera_focus-BOSS_EYE_BACK)/SCALE)
	var look:=Vector3(0,BOSS_LOOK_HEIGHT,-(boss_camera_focus+BOSS_LOOK_AHEAD)/SCALE)
	return Transform3D.IDENTITY.translated(eye).looking_at(look,Vector3.UP)

func update_journey_camera()->void:
	if run.state=="paused":return
	var dramatic:bool=run.state in ["rescue","failed"]
	if dramatic:journey_camera_returning=true
	if dramatic or journey_camera_returning:
		update_camera()
		var target:=camera_shot()
		if not dramatic and camera.transform.origin.distance_to(target.origin)<.01:
			camera.transform=target;journey_camera_returning=false
	else:
		var shot:=camera_shot()
		# 联机时模拟偶尔少走或多走一帧（缓冲变速），镜头直接贴着进度会整屏一顿；
		# 这里只让镜头前后方向平滑跟随，约 60 毫秒收敛，大跳变（重试、存档恢复）直接贴上。不影响模拟与同步。
		if play_mode=="online" and is_instance_valid(net) and net.in_match:
			var gap:=shot.origin.z-camera.transform.origin.z
			if absf(gap)<3.0 and camera_smoothed:
				shot.origin.z=camera.transform.origin.z+gap*(1.0-exp(-frame_delta*16.0))
			camera_smoothed=true
		else:camera_smoothed=false
		camera.transform=shot

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
	var jump_key:="A" if gamepad_active else "空格"
	var instruction:String="连点%s拉人 / 攀爬，搭档同步协助"%jump_key
	if play_mode=="local":
		var holder:int=1-run.rescue.role
		var keys:=["A","A"] if gamepad_active else ["空格","回车"]
		instruction="%02d 连点%s拉人 · %02d 连点%s向上爬"%[holder+1,keys[holder],run.rescue.role+1,keys[run.rescue.role]]
	elif play_mode=="online":instruction="连点%s拉人 / 攀爬，与队友一起用力"%jump_key
	if touch_device:instruction="连点右侧跳跃按钮，拉人 / 向上攀爬"
	if run.rescue.has("climb"):instruction="拉住了！正在爬回路面"
	rescue_label.text="救援进度 %d%%  ·  剩余 %.1f 秒\n%s"%[roundi(run.rescue.progress*100),maxf(0,Run.RESCUE_TIME-run.rescue.time),instruction]

func update_journey_ui() -> void:
	if not is_instance_valid(hud): return
	sync_rescue_hud()
	for button in mode_buttons:
		button.visible=run.state=="start" and not run.combat_trial
		button.disabled=net.active()
		mark_choice(button,button.get_meta("mode","")==play_mode)
	for button in difficulty_buttons:
		mark_choice(button,button.text==run.difficulty)
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
	# 开始页和暂停页的按钮数量不同，面板高度跟内容走，避免底部留一大块空板。
	checkpoint_toast.position=Vector2(viewport.x/2-60,inset+48)
	checkpoint_toast.size=Vector2(120,0)
	var role: int=net.role if play_mode=="online" and net.in_match else 0
	combat_health.value=run.combat.health[role]
	partner_health.value=run.combat.health[1-role]
	hud.text="%02d   %d / 100%s"%[role+1,run.combat.health[role],"  护盾" if run.shield else ""]
	partner_status.text="%02d   %d / 100"%[2-role,run.combat.health[1-role]]
	# 受击红边与低血量暗角：只读取同步后的真实血量，不参与判定。
	var top_health: int = run.combat.health[role]
	var second_health: int = run.combat.health[1-role]
	if top_health<last_health[0]:
		# 只有本机角色受击才做画面冲击和震动，队友受击保留红边与特效。
		impact_flash=1.0
		rumble(0.55,0.9,0.18)
	if top_health<last_health[0] or second_health<last_health[1]:
		damage_flash=1.0
		for hurt_role in range(2):
			var before:int=last_health[0] if hurt_role==role else last_health[1]
			if run.combat.health[hurt_role]<before and is_instance_valid(fx):
				fx.impact(robots[hurt_role].global_position,Color("ff3b2a"),1.8,2.6)
	last_health[0]=top_health;last_health[1]=second_health
	if run.combat.kills>last_kills: rumble(0.35,0.0,0.07)
	last_kills=run.combat.kills
	var open_gates:int=run.charge_gates.filter(func(g):return g.open).size()
	if open_gates>last_open_gates and run.state=="running": rumble(0.4,0.4,0.22)
	last_open_gates=open_gates
	low_health=clampf((35.0-minf(top_health,second_health))/35.0,0.0,1.0)
	var role_color:=Color("8fe3d2") if role==0 else Color("f0c089")
	if hud.get_meta("role_color",Color(-1,-1,-1))!=role_color:
		hud.set_meta("role_color",role_color)
		hud.add_theme_color_override("font_color",role_color)
		partner_status.add_theme_color_override("font_color",Color("f0c089") if role==0 else Color("8fe3d2"))
	for entry in [[combat_health,role],[partner_health,1-role]]:
		var fill: StyleBoxFlat=entry[0].get_theme_stylebox("fill")
		fill.bg_color=Color("ef8078") if run.combat.health[entry[1]]<=30 else (Color("9cdeb9") if entry[1]==role else Color("e4b883"))
	var weapon: Dictionary=run.combat.weapons[role]
	combat_status.text="空手" if weapon.is_empty() else run.Combat.weapon_name(weapon)
	if not weapon.is_empty():
		var weapon_type:String=weapon.get("type","smg")
		if weapon_icon.get_meta("weapon_type","smg")!=weapon_type:
			weapon_icon.set_meta("weapon_type",weapon_type)
			weapon_icon.texture=WEAPON_ICONS[weapon_type]
			weapon_icon.tooltip_text=run.Combat.weapon_name(weapon)
	combat_status.visible=weapon.is_empty()
	weapon_icon.visible=not weapon.is_empty()
	weapon_ammo.text="" if weapon.is_empty() else "%02d / %d"%[weapon.ammo,weapon.reserve]
	weapon_ammo.visible=not weapon.is_empty()
	weapon_detail.text=""
	if not weapon.is_empty():
		if weapon.reload>0: weapon_detail.text="换弹 %.1f 秒"%(weapon.reload*Run.FIXED_STEP)
		elif weapon.ammo==0 and weapon.reserve==0: weapon_detail.text="弹药耗尽"
	# 背上的第二把枪：显示名称与换枪键。
	var spare: Dictionary=run.Combat.backup(run,role) if not run.combat.is_empty() else {}
	if not spare.is_empty():
		var swap_key:="LB" if gamepad_active else ("换枪" if touch_device else "Q")
		var line:="背后：%s · %s 换枪"%[run.Combat.weapon_name(spare),swap_key]
		weapon_detail.text=line if weapon_detail.text.is_empty() else weapon_detail.text+"\n"+line
	weapon_detail.visible=not weapon_detail.text.is_empty()
	var playing: bool=run.state in ["running","rescue"]
	health_panel.visible=playing
	weapon_panel.visible=playing
	if is_instance_valid(net_diag):
		net_diag.visible=net.in_match
		if net_diag.visible:net_diag.text=net.diagnostics_text()
		net_diag.position=Vector2(inset,viewport.y-inset-18)
	journey_hint.position=Vector2(inset,viewport.y-100 if not touch_device else viewport.y*.58)
	journey_hint.size=Vector2(viewport.x-2*inset,56)
	journey_hint.text=""
	journey_hint.visible=run.state=="rescue" or (run.state=="running" and run.charge_gate.get("active",false) and not run.charge_gate.open and absf(run.a.position.y-run.charge_gate.receiver.y)<180)
	# 怪物潮专区显示剩余敌人数，离开专区后自动收起。
	if run.state=="running" and not run.combat_trial and not run.arena_at(run.progress()).is_empty():journey_hint.visible=true
	# Boss 战全程显示当前招式的躲避提示。
	if run.state=="running" and not run.Boss.hint(run).is_empty():journey_hint.visible=true
	if journey_hint.visible: journey_hint.text=run.active_hint()
	# Boss 入场动画按电影画面呈现：整个游戏界面层收起，只留黑边和标题（由 BossView 绘制）；暂停时照常显示菜单。
	if has_node("JourneyCanvas"):get_node("JourneyCanvas").visible=not (run.state=="running" and run.Boss.cinematic(run))
	update_settings_panel()
	panel.visible=run.state in ["start","paused","failed","settlement","complete"] and not fail_showing() and not settings_open
	update_chapter_bar(viewport,inset,hud_width)
	primary.visible=true
	training_button.visible=run.state=="start" and (play_mode=="solo" or (from_menu() and not net.active()))
	training_button.text="返回三关旅程" if run.combat_trial else "战斗训练 · 持枪步行约 90 秒"
	if from_menu():training_button.text="返回主界面 · 选择其他章节"
	home_button.text="回到主界面 · 重新选择章节" if from_menu() else "回到主页 · 重新选择单人或联机"
	restart_button.visible=run.state in ["paused","failed"]
	checkpoint_button.visible=run.state=="paused"
	checkpoint_button.text="回到存档点继续" if not run.checkpoint.is_empty() else "从本关开头继续"
	home_button.visible=run.state in ["paused","failed","complete"]
	settings_button.visible=run.state in ["start","paused"] and not get_meta("credits",false)
	if gamepad_active:ensure_menu_focus()
	pause_button.visible=run.state in ["running","rescue"]
	if is_instance_valid(touch): touch.set_enabled(touch_device and run.state in ["running","rescue","settlement"])
	for button in difficulty_buttons: button.visible=run.state=="start" and play_mode!="online"
	if get_meta("credits",false) and run.state=="paused": return
	set_meta("credits",false)
	match run.state:
		"start":
			title.text="共生连线 · 战斗训练" if run.combat_trial else "共生连线 · 连续旅程"
			if from_menu() or run.level_index>0:title.text=Catalog.title(chapter_key())
			subtitle.text="WASD 移动 · 空格跳跃 · 鼠标左键射击\nR 换弹 · Q 换枪 · G 丢枪 · Esc 暂停\n靠近自动拾取。机关分级扣血，重型机关危险更高。"
			if gamepad_active: subtitle.text=PAD_HELP+" · Start 暂停\n靠近自动拾取。机关分级扣血，重型机关危险更高。"
			if touch_device: subtitle.text="左侧滑动移动；右侧大按钮跳跃、按住射击。\n小按钮换弹、丢枪，靠近枪械自动拾取。\n搭档跟随并共同跳跃，踩空时连点跳跃救援。\n可停步观察敌人，持枪移动稍慢；血量耗尽从存档继续。"
			primary.text="开始训练" if run.combat_trial else "出发"
			if play_mode=="online" and net.in_match and online_start_pending:primary.text="等待队友载入完成…"
		"paused":
			title.text="暂停"
			subtitle.text="WASD 移动 · 空格跳跃 · 鼠标左键射击\nR 换弹 · Q 换枪 · G 丢枪 · Esc 继续 · F1 素材署名\n金币 %d · 奖品 %d · %.0f / %.0f 米"%[run.coins,run.prizes,run.progress()/SCALE,run.finish_distance()/SCALE]
			if gamepad_active: subtitle.text=PAD_HELP+" · Start 继续 · B 返回\n金币 %d · 奖品 %d · %.0f / %.0f 米"%[run.coins,run.prizes,run.progress()/SCALE,run.finish_distance()/SCALE]
			elif touch_device: subtitle.text="左侧摇杆移动 · 右侧跳跃、射击、换弹、丢枪\n金币 %d · 奖品 %d"%[run.coins,run.prizes]
			primary.text="继续旅程"
		"failed":
			title.text=run.reason
			subtitle.text="回到最近的安全存档点，危险与奖励恢复原状态。" if not run.checkpoint.is_empty() else "本关还没有存档，将从起点重新开始。"
			primary.text=("从存档继续" if not run.checkpoint.is_empty() else "从起点重试")+("  ·  A" if gamepad_active else ("" if touch_device else "  ·  空格 / 回车"))
		"settlement":
			title.text="共同抵达 · "+run.CHAPTERS[run.level_index].name
			subtitle.text="本关 %.1f 秒 · 金币 %d · 奖品 %d\n点击按钮或松开后按跳跃键，进入下一关。"%[run.elapsed,run.coins,run.prizes]
			primary.text="下一关"
			var next:=next_chapter_key()
			if next>=0 and not ChapterPacks.is_ready(next):
				subtitle.text+="\n下一章数据下载中 %d%%，完成后即可继续。"%int(ChapterPacks.progress(next)*100)
		"complete": title.text="训练完成" if run.combat_trial else "归航完成";subtitle.text="击退 %d 个敌人 · 团队总分 %d。\n可以重新出发。"%[run.combat.kills,run.total_score()];primary.text="重新出发"
	layout_panel()
	if run.state=="rescue": journey_hint.text="连点跳跃救援！进度 %.0f%% · 剩余 %.1f 秒"%[run.rescue.progress*100,maxf(0,Run.RESCUE_TIME-run.rescue.time)]

# 顶部细条放在两块 HUD 面板之间；窄屏放不下六段文字时铺满顶部，只写当前区域名。
func update_chapter_bar(viewport:Vector2,inset:float,hud_width:float) -> void:
	if not is_instance_valid(chapter_bar):return
	var left:=inset+hud_width+20.0
	var width:=viewport.x-2.0*left
	var compact:=width<360.0
	if compact:
		left=inset
		width=viewport.x-2.0*inset
	var rect:=Rect2(left,6.0 if compact else 10.0,width,ChapterBar.BAR_HEIGHT)
	chapter_bar.refresh(run,frame_delta,rect,run.state in ["running","rescue","paused"] and not settings_open,compact)

func build_ambience() -> void:
	ambient=AudioStreamPlayer.new()
	ambient.volume_db=-23
	ambient.bus="Ambience"
	add_child(ambient)
	forest_birds=AudioStreamPlayer.new()
	var birds:AudioStreamOggVorbis=load("res://assets/audio/forest_birds.ogg")
	birds.loop=true
	forest_birds.stream=birds
	forest_birds.volume_db=-60
	forest_birds.bus="Ambience"
	add_child(forest_birds)
	music_explore=AudioStreamPlayer.new();music_explore.bus="Music";music_explore.volume_db=-80.0
	add_child(music_explore)
	music_combat=AudioStreamPlayer.new();music_combat.bus="Music";music_combat.volume_db=-80.0
	music_combat.stream=load(MUSIC_COMBAT)
	add_child(music_combat)
	# 缓存有限 PCM 循环，避免流式生成器在退出时遗留音频播放句柄。
	for kind in ["wind","forest","river"]:
		var stream:AudioStreamWAV=load("res://assets/audio/ambience_%s.wav"%kind).duplicate()
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin=0
		stream.loop_end=7*22050
		ambience_streams[kind]=stream

# 脚步、起跳与落地：按画面帧读取模拟位置与高度，只发声，不影响判定。
# 每走一个 Run 步幅发一声，地面材质按当前地貌选草地、木板或石路。
func play_footsteps(i:int)->void:
	var body:Vector3=robots[i].global_position
	if visual_last_heights[i]==0.0 and run.heights[i]>0.0:
		sfx.play_at("step_wood",body,-6.0,1.25)
	elif visual_last_heights[i]>0.0 and run.heights[i]==0.0:
		sfx.play_at("land_soft",body,-4.0 if visual_last_heights[i]>6.0 else -9.0,1.0)
		step_travel[i]=0.0
	if run.heights[i]>0.0:return
	var flat:=Vector2(body.x,body.z)
	var moved:float=flat.distance_to(step_last[i]) if step_last[i]!=Vector2.INF else 0.0
	step_last[i]=flat
	# 读档、重试或换章时整段位移，不算脚步。
	if moved>STEP_TELEPORT:
		step_travel[i]=0.0
		return
	step_travel[i]+=moved
	if step_travel[i]<HERO_STRIDE_SPEED[i]*RUN_STEP_TIME:return
	step_travel[i]=0.0
	var theme:String=run.theme_at(run.distance)
	var surface:="step_grass" if theme in ["forest","edge","meadow","farm","ridge","broken"] else ("step_wood" if theme=="river" else "step_stone")
	sfx.play_at(surface,body,-10.0,1.0 if i==0 else 1.08)

# 探索层：游玩时满音量，菜单、失败与结算时降到一半，暂停时冻结；换章先淡出再换曲。
# 战斗层：附近敌人察觉时 0.8 秒淡入、探索层同时降到 0.6；脱战后约 3 秒淡出，停在原处下次接着放。
func pump_music(delta: float, fighting: bool) -> void:
	if not is_instance_valid(music_explore):return
	var paused: bool=run.state=="paused"
	music_explore.stream_paused=paused and music_explore.playing
	music_combat.stream_paused=paused and music_combat.playing
	if paused:return
	var chapter: int=clampi(run.level_index,0,MUSIC_EXPLORE.size()-1)
	var explore_target: float=(0.6 if fighting else 1.0) if run.state in ["running","rescue"] else 0.5
	if chapter!=music_chapter:explore_target=0.0
	explore_level=move_toward(explore_level,explore_target,delta*(0.8 if explore_target<explore_level else 0.4))
	if chapter!=music_chapter and explore_level<=0.0:
		music_chapter=chapter
		music_explore.stream=load(MUSIC_EXPLORE[chapter])
		music_explore.play()
	if music_explore.stream!=null and not music_explore.playing:music_explore.play()
	music_explore.volume_db=MUSIC_EXPLORE_DB+linear_to_db(maxf(0.0001,explore_level))
	combat_level=move_toward(combat_level,1.0 if fighting else 0.0,delta*(1.25 if fighting else 0.33))
	if combat_level>0.0 and not music_combat.playing:music_combat.play()
	music_combat.stream_paused=combat_level<=0.0 and music_combat.playing
	music_combat.volume_db=MUSIC_COMBAT_DB+linear_to_db(maxf(0.0001,combat_level))

func combat_nearby() -> bool:
	for event in run.journey_events:
		if event.kind=="monster" and event.hp>0 and event.alert and absf(event.y-run.distance)<900.0: return true
		if event.kind=="boss" and event.hp>0 and event.phase!="dormant": return true
	return false

static func ambience_wave(t:float,kind:String)->float:
	var wind:=sin(t*TAU*49)*sin(t*TAU*65)*0.08+sin(t*TAU*112)*0.03
	var bird:=0.0
	if kind=="forest" and t<0.35:bird=sin(t*(3100+sin(t*36)*600))*sin(t/0.35*PI)*0.18
	var water:=sin(t*TAU*101)*sin(t*TAU*67)*0.12 if kind=="river" else 0.0
	return wind+bird+water

func pump_ambience(delta: float) -> void:
	if not is_instance_valid(ambient):return
	# 附近有已察觉玩家的存活敌人时，环境声 0.4 秒内压低约 6 dB，脱战后 1.5 秒恢复。
	var target:=AMBIENCE_DUCKED if run.state=="running" and combat_nearby() else 1.0
	ambience_level=move_toward(ambience_level,target,delta*(1.5 if target<ambience_level else 0.35))
	Sfx.set_bus_level("Ambience",ambience_level*settings.volumes.ambience)
	pump_music(delta,target<1.0)
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
	return run.hazard_specs[index].get("front",false) or run.kinds[index] in ["drone","rail","pillar","cargo","active_spikes","jump_bar","color_gate","collapse","sweeper","hammer","press","steam","shuttle","piston","lift","slope","steps","tilt"]

func hazard_asset_paths(index:int)->Array:
	match run.kinds[index]:
		"drone":return ["res://assets/props/Eagle_Flying.glb"]
		"stone_ball":return [TRIPO_BOULDER]
		"iron_ball":return [MECH_SPIKED_BALL]
		"pillar":return [MECH_STONE_POST]
		"active_spikes":return [MECH_SPIKE_TRAP]
		"rocket":return [MECH_FIRE_BOLT]
		"fly_low","fly_body":return [MECH_FLYING_ROCK]
		"steam":return [MECH_STEAM_VENT]
		"sweeper":return [MECH_SPIKED_LOG,MECH_PIVOT]
		"lift":return [MECH_LIFT]
		"rail":return [TRIPO_TIMBER]
		"jump_bar":return [MECH_PIVOT]
		"barrel":return [BARREL_MODEL]
		"color_gate":return [MECH_ARCH[int(run.hazard_specs[index].get("role",0))]]
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
	if run.kinds[index] not in ["stone_ball","iron_ball"]:return
	var body:MeshInstance3D=chunk.get_node("BallBody")
	for child in body.get_children():child.free()
	body.material_override=zone_material("hidden_tripo_ball",Color(0,0,0,0))
	var diameter:float=run.obstacles[index].size.x/SCALE
	# 铁球换成带刺铁锤球；刺尖略超出碰撞球体约 6%，对玩家从宽。
	tripo_model(body,TRIPO_BOULDER if run.kinds[index]=="stone_ball" else MECH_SPIKED_BALL,Vector3.ONE*diameter*(1.0 if run.kinds[index]=="stone_ball" else 1.12),Vector3.ZERO)

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
		if hazard_fx and static_views.has(index):hazard_fx.track(index,run.kinds[index],run.hazard_sample(index,run.elapsed),static_views[index])
	if hazard_fx:hazard_fx.release_missing()

func sync_static_hazard(i: int) -> void:
	var kind:String=run.kinds[i]
	if kind=="drone" or run.hazard_specs[i].get("front",false):
		sync_moving_threat(i)
		return
	if kind not in ["rail","pillar","cargo","active_spikes","jump_bar","color_gate","collapse","sweeper","hammer","press","steam","shuttle","piston","lift","slope","steps","tilt"]:return
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
		elif kind=="pillar":
			# 立柱换成雕刻石界桩；方柱外接碰撞圆柱，高度与碰撞顶高（5 米）一致。
			tripo_model(view,MECH_STONE_POST,Vector3(rect.size.x/SCALE*1.25,5.0,rect.size.x/SCALE*1.25),Vector3(0,2.5,0))
		elif kind=="jump_bar":build_jump_bar(view,rect)
		elif kind=="color_gate":build_color_gate(view,rect,int(run.hazard_specs[i].get("role",0)))
		elif kind=="cargo" and run.hazard_specs[i].get("rope_passable",false):
			# 中间隔墩：矮石座低于绳高，上方是只挡身体的能量帘，绳索从帘中穿过。
			box(view,Vector3(0,.25,0),Vector3(rect.size.x/SCALE,.5,rect.size.y/SCALE+.2),landscape.palette.Stone)
			var curtain:=box(view,Vector3(0,1.75,0),Vector3(rect.size.x/SCALE*.9,2.5,.08),material("color_gate_curtain",Color(.78,.86,1.0,.28),1.4))
			curtain.material_override.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			curtain.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
			curtain.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif kind=="cargo" and run.hazard_specs[i].get("color_wall",false):
			# 颜色门两侧的石墙：整齐砌石，与门拱同高同色。
			box(view,Vector3(0,1.5,0),Vector3(rect.size.x/SCALE,3.0,rect.size.y/SCALE+.2),landscape.palette.Stone)
		elif kind=="cargo" and not run.hazard_specs[i].get("color_wall",false):
			rock(view,rock_mesh("encounter_boulder",321,1,1,1,.25,"round"),ground_material("ruins"),Vector3.ZERO,1)
			# 圆石网格底部在 y=0、总高 1.5（含顶盖）；按碰撞高度缩放并下沉三成，
			# 最宽处贴地，不再整块悬在路面上方。
			var height:float=run.obstacle_heights[i]/SCALE if run.hazard_specs[i].get("small",false) else 3.0
			view.get_child(0).scale=Vector3(rect.size.x/SCALE/2,height*1.3/1.5,rect.size.y/SCALE/2)
			view.get_child(0).position.y=-height*0.3
		elif kind=="collapse":
			box(view,Vector3(0,.012,0),Vector3(rect.size.x/SCALE,.02,rect.size.y/SCALE),material("fragile_ground",Color("5e5943")))
			for n in range(7):
				var crack:=box(view,Vector3(-rect.size.x/SCALE/2+n*1.6,.027,0),Vector3(.08,.025,rect.size.y/SCALE),material("fragile_cracks",Color("25261d")));crack.rotation.y=.18 if n%2==0 else -.18
		else:
			# 活动地刺：铁刺陷阱板模型（原模型竖放、刺尖朝 +X，绕 Z 轴放平使刺尖朝上），伸缩时整块升降。
			var trap:=Node3D.new();trap.name="TrapModel";view.add_child(trap)
			var holder:=Node3D.new();trap.add_child(holder);holder.rotation.z=PI/2
			tripo_model(holder,MECH_SPIKE_TRAP,Vector3(.8,rect.size.x/SCALE,rect.size.y/SCALE*1.05),Vector3.ZERO)
			holder.position.y=.4
			var warning:=box(view,Vector3(0,.065,0),Vector3(rect.size.x/SCALE+.08,.025,rect.size.y/SCALE+.08),material("small_trap_warning",Color("e7ae43"),.25))
			warning.name="SpikeWarning"
		static_views[i]=quiet_world_text(view)
	static_views[i].position=Vector3(rect.get_center().x/SCALE,0,-rect.get_center().y/SCALE)
	static_views[i].visible=model_visible(rect.get_center().y)
	if kind=="color_gate" or run.hazard_specs[i].get("color_wall",false):fade_passed_color_gate(static_views[i],rect.get_center().y)
	if kind=="collapse":static_views[i].visible=static_views[i].visible and run.hazard_sample(i,run.elapsed).stage!="collapsed"
	if kind=="jump_bar":sync_jump_bar(static_views[i],i)
	if kind=="active_spikes":
		var sample:Dictionary=run.hazard_sample(i,run.elapsed)
		static_views[i].get_node("SpikeWarning").visible=sample.warning
		# 收回时刺板沉到路面以下，伸出量与模拟顶高同步。
		static_views[i].get_node("TrapModel").position.y=(clampf(sample.top/16.0,0.0,1.0)-1.0)*.75

# 两侧石质转轴柱 + 横贯全路的木杆；木杆绕 X 轴整圈旋转，最低点对齐模拟中贴地窗口的中点。
func build_jump_bar(view:Node3D,rect:Rect2)->void:
	var half:float=rect.size.x/SCALE/2
	for side in [-1.0,1.0]:
		var post:=Node3D.new();view.add_child(post);post.position=Vector3(side*(half+.9),0,0)
		tripo_model(post,MECH_PIVOT,Vector3(1.3,JUMP_BAR_AXLE+.45,1.3),Vector3(0,(JUMP_BAR_AXLE+.45)/2,0))
	var axle:=Node3D.new();axle.name="Axle";view.add_child(axle);axle.position.y=JUMP_BAR_AXLE
	var arm:=Node3D.new();arm.name="Arm";axle.add_child(arm)
	var wood:Material=landscape.palette.Wood
	var log:=cylinder(arm,Vector3(0,JUMP_BAR_RADIUS,0),.28,half*2+1.8,wood);log.rotation.z=PI/2
	for side in [-1.0,1.0]:
		var spoke:=cylinder(arm,Vector3(side*(half+.9),JUMP_BAR_RADIUS/2,0),.09,JUMP_BAR_RADIUS,landscape.palette.Iron)
	var warning:=box(view,Vector3(0,.02,0),Vector3(half*2,.02,rect.size.y/SCALE+.6),material("jump_bar_warning",Color(1,.45,.12,.45),.35))
	warning.material_override.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	warning.name="Warning"

func sync_jump_bar(view:Node3D,index:int)->void:
	var spec:Dictionary=run.hazard_specs[index]
	var period:float=spec.get("period",2.4)
	var cycle:=fposmod(run.elapsed+float(spec.get("phase",0.0)),period)
	var bottom_time:float=float(spec.get("warning",.9))+float(spec.get("active",.22))*.5
	# θ=0 木杆在正上方，θ=π 贴地；匀速一圈一周期。
	view.get_node("Axle/Arm").rotation.x=PI+TAU*(cycle-bottom_time)/period
	view.get_node("Warning").visible=run.hazard_sample(index,run.elapsed).warning

# ---- 预警表现：地面图形取代世界文字 ----
# 机关说明、事件提示与合作门标题不在场景里渲染（顶部提示栏仍显示当前最近的危险与做法）；
# 所有地面预警片统一为红橙斜纹、呼吸闪烁的着色器，按世界坐标铺纹，不随尺寸拉伸。
const QUIET_LABELS := ["WarningLabel","Hint","GateTitle","TerrainSign"]
const TELEGRAPH_NODES := ["WarningFootprint","FlightRoute","TrajectoryCorridor","Warning","HammerZone","SpikeWarning"]
var telegraph_material:ShaderMaterial

func telegraph()->ShaderMaterial:
	if telegraph_material==null:
		var shader:=Shader.new()
		shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
varying vec3 world;
void vertex(){ world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	float stripe=step(0.5,fract((world.x+world.z)*0.55-TIME*0.9));
	float pulse=0.62+0.38*sin(TIME*7.0);
	ALBEDO=mix(vec3(0.95,0.18,0.07),vec3(1.0,0.6,0.12),stripe);
	ALPHA=(0.30+0.32*stripe)*pulse;
}"""
		telegraph_material=ShaderMaterial.new();telegraph_material.shader=shader
	return telegraph_material

func quiet_world_text(node:Node)->Node:
	if node is Label3D and node.name in QUIET_LABELS:node.layers=0
	elif node is MeshInstance3D and node.name in TELEGRAPH_NODES:node.material_override=telegraph()
	for child in node.get_children():quiet_world_text(child)
	return node

func make_hazard_view(index:int)->Node3D:
	var view:Node3D=super.make_hazard_view(index)
	if run.kinds[index]=="rocket":dress_rocket(view,index)
	return quiet_world_text(view)

# 火箭的方块机身与尾翼换成火焰弩箭；箭头朝向镜头（+Z，迎面飞来），长度与危险盒一致。
func dress_rocket(view:Node3D,index:int)->void:
	for child in view.get_children():
		if child is MeshInstance3D and child.name not in TELEGRAPH_NODES and child.name!="DangerVolume" and child.name!="ThreatShadow":child.visible=false
		if child.name=="DangerVolume":child.material_override=zone_material("hidden_volume",Color(0,0,0,0))
	var rect:Rect2=run.obstacles[index]
	var spec:Dictionary=run.hazard_specs[index]
	var holder:=Node3D.new();holder.name="Bolt";view.add_child(holder)
	holder.position.y=(spec.bottom+run.obstacle_heights[index])/SCALE/2
	tripo_model(holder,MECH_FIRE_BOLT,Vector3(rect.size.x/SCALE*.9,(run.obstacle_heights[index]-spec.bottom)/SCALE*1.2,rect.size.y/SCALE*1.1),Vector3.ZERO)

# 压机、活塞、横移撞锤：保留同源碰撞尺寸与运动，只把纯色方块换成石块与木架材质，
# 危险部件为花岗岩并保留黄色警示条，支架为木料，不再是橙色占位方块。
func build_industrial_model(chunk:Node3D,index:int)->void:
	super.build_industrial_model(chunk,index)
	if run.kinds[index]=="steam":
		# 地火喷口：贴地喷嘴平板换成石圈铁栅喷口模型，喷流保持原样。
		var nozzle:MeshInstance3D=chunk.get_node("nozzle")
		nozzle.material_override=zone_material("hidden_volume",Color(0,0,0,0))
		var rect:Rect2=run.obstacles[index]
		var vent:=Node3D.new();vent.name="Vent";chunk.add_child(vent)
		tripo_model(vent,MECH_STEAM_VENT,Vector3(minf(rect.size.x,rect.size.y*2.2)/SCALE,.5,rect.size.y/SCALE*1.1),Vector3(0,.2,0))
		return
	if run.kinds[index]=="hammer":
		# 摆锤门架的钢柱、横梁改为木料，与村庄与林地的木构一致。
		for name in ["PostLeft","PostRight","Beam"]:
			if chunk.has_node(name):chunk.get_node(name).material_override=landscape.palette.Wood
		return
	if run.kinds[index] not in ["press","piston","shuttle"]:return
	for child in chunk.get_children():
		if not child is MeshInstance3D:continue
		if child.name in ["head","plate","ram"]:
			child.material_override=landscape.palette.Stone
			if run.kinds[index]=="press":
				for band in [-.32,.32]:
					var strip:=box(child,Vector3(band,0,.505),Vector3(.1,.9,.01),material("mechanical_stripe",Color("ffcf72")))
		elif child.name.begins_with("post_") or child.name in ["beam","shaft","track"]:
			child.material_override=landscape.palette.Wood

# 颜色门：水晶石拱（模型开口沿 Z，旋转 90° 后横跨门洞）+ 同色地面引导带。
func build_color_gate(view:Node3D,rect:Rect2,role:int)->void:
	var holder:=Node3D.new();view.add_child(holder);holder.rotation.y=PI/2
	tripo_model(holder,MECH_ARCH[role],Vector3(1.4,5.2,rect.size.x/SCALE+1.0),Vector3(0,2.6,0))
	var color:=Color("57dbea") if role==0 else Color("ffb95e")
	var lane:=box(view,Vector3(0,.025,1.6),Vector3(rect.size.x/SCALE*.8,.02,3.2),material("color_lane_%d"%role,Color(color.r,color.g,color.b,.5),.6))
	lane.material_override.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	add_sign(view,"01" if role==0 else "02",Vector3(0,5.8,0),40).modulate=color

# 角色通过水晶门后，拱门正落在镜头下缘，会挡住前路并和角色头顶的 01/02 重复。
# 按落后距离让整座门（含标签）逐渐淡出，最后直接隐藏；碰撞与判定完全不变。
func fade_passed_color_gate(view:Node3D,y:float)->void:
	var behind: float = run.distance-y
	var fade: float = clampf((behind-40.0)/180.0,0.0,1.0)
	if fade>0:view.set_meta("faded",true)
	view.visible=view.visible and fade<0.99
	if not view.visible:return
	for node in view.find_children("*","GeometryInstance3D",true,false):
		if node is Label3D:
			var base:Color=node.get_meta("look_base_modulate",node.modulate)
			node.set_meta("look_base_modulate",base)
			node.modulate=Color(base.r,base.g,base.b,base.a*(1.0-fade))
		else:
			(node as GeometryInstance3D).transparency=fade

# 升降平台：木板拼的台面换成带护栏的木质升降台模型，挂在随模拟升降的 TerrainDeck 下。
func build_terrain_model(view:Node3D,index:int)->void:
	super.build_terrain_model(view,index)
	if run.kinds[index]!="lift":return
	var deck:MeshInstance3D=view.get_node("TerrainDeck")
	deck.material_override=zone_material("hidden_volume",Color(0,0,0,0))
	for child in deck.get_children():
		if child is MeshInstance3D:child.visible=false
	var rect:Rect2=run.obstacles[index]
	var platform:=Node3D.new();deck.add_child(platform)
	tripo_model(platform,MECH_LIFT,Vector3(rect.size.x/SCALE,.9,rect.size.y/SCALE),Vector3(0,-.3,0))

# 旋转扫杆：立柱换成石质转轴，橙色杆体换成带刺圆木（模型长轴沿 Z，转 90° 对齐杆体 X 轴）。
func build_surface_hazard(chunk:Node3D,index:int)->void:
	super.build_surface_hazard(chunk,index)
	if run.kinds[index]!="sweeper":return
	var post:MeshInstance3D=chunk.get_node("SweeperPost")
	var arm:MeshInstance3D=chunk.get_node("SweeperArm")
	var post_size:Vector3=Vector3(post.mesh.top_radius*2,post.mesh.height,post.mesh.top_radius*2)
	post.material_override=zone_material("hidden_volume",Color(0,0,0,0))
	var pivot:=Node3D.new();chunk.add_child(pivot)
	tripo_model(pivot,MECH_PIVOT,Vector3(post_size.x*1.6,post_size.y,post_size.z*1.6),Vector3(0,post_size.y/2,0))
	var size:Vector3=arm.mesh.size
	arm.material_override=zone_material("hidden_volume",Color(0,0,0,0))
	for child in arm.get_children():
		if child is MeshInstance3D:child.visible=false
	var log:=Node3D.new();log.rotation.y=PI/2;arm.add_child(log)
	tripo_model(log,MECH_SPIKED_LOG,Vector3(size.y*1.6,size.y*1.6,size.x),Vector3.ZERO)

# 两个横躺木桶并排组成 4.5 米宽的滚桶；只替换外观，危险体仍按模拟矩形判定。
func build_barrel_row(view:Node3D,rect:Rect2,sample:Dictionary)->void:
	view.get_node("DangerVolume").visible=false
	var row:=Node3D.new();row.name="BarrelRow";view.add_child(row)
	var diameter:float=(sample.top-sample.bottom)/SCALE
	row.position.y=diameter/2
	var piece:float=rect.size.x/SCALE/2
	for n in range(2):
		var holder:=Node3D.new();row.add_child(holder);holder.position.x=(n-.5)*piece
		# 模型桶轴沿 Z，绕 Y 轴转 90° 后沿 X；桶长略短于每段宽度留出缝隙。
		tripo_model(holder,BARREL_MODEL,Vector3(diameter,diameter,piece*.94),Vector3.ZERO)
		holder.rotation.y=PI/2

func sync_barrel_row(view:Node3D,index:int,sample:Dictionary)->void:
	var row:Node3D=view.get_node("BarrelRow")
	var spec:Dictionary=run.hazard_specs[index]
	view.get_node("WarningFootprint").visible=sample.warning
	if sample.stage=="tripped":
		# 被绳子绊倒：向前翻倒、下沉并在 0.6 秒内消失。
		var age:float=run.elapsed-float(spec.get("tripped_at",run.elapsed))
		row.rotation.x=-smoothstep(0.0,.35,age)*1.1
		row.position.y=(sample.top-sample.bottom)/SCALE/2-smoothstep(.2,.6,age)*1.5
		view.visible=view.visible and age<.6
		return
	row.rotation.x=float(spec.travel)/((sample.top-sample.bottom)/2)

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
			var rock_size:=Vector3(rect.size.x/SCALE,(sample.top-sample.bottom)/SCALE,rect.size.y/SCALE)
			var spin:=Node3D.new();spin.name="Spin";volume.add_child(spin)
			tripo_model(spin,MECH_FLYING_ROCK,Vector3.ONE*maxf(rock_size.x,rock_size.y)*1.05,Vector3.ZERO)
		if kind=="barrel":build_barrel_row(created,rect,sample)
		static_views[index]=created
	var view:Node3D=static_views[index]
	view.position=Vector3(rect.get_center().x/SCALE,0,-rect.get_center().y/SCALE)
	# 未启动的远处威胁不摆在路上；启动瞬间从空中落入/放大出现，碰撞仍只由模拟决定。
	var dormant:=threat_dormant(index)
	if dormant:view.remove_meta("appear_at")
	elif not view.has_meta("appear_at"):view.set_meta("appear_at",run.elapsed)
	var appear:=1.0 if dormant else clampf((run.elapsed-float(view.get_meta("appear_at")))/THREAT_APPEAR_TIME,0,1)
	var ease_in:=1.0-pow(1.0-appear,3)
	view.scale=Vector3.ONE*lerpf(0.35,1.0,ease_in)
	# 落入偏移加在球体子节点上，节点本身始终与碰撞位置一致。
	if Run.Threats.is_ball(kind):
		var ball_body:Node3D=view.get_node("BallBody")
		if not ball_body.has_meta("rest_y"):ball_body.set_meta("rest_y",ball_body.position.y)
		ball_body.position.y=float(ball_body.get_meta("rest_y"))+(1.0-ease_in)*THREAT_DROP_HEIGHT
	if kind=="drone":
		view.visible=model_visible(rect.get_center().y) and not dormant
		sync_industrial_model(view,index,sample)
		return
	view.visible=model_visible(rect.get_center().y) and not dormant
	var route:MeshInstance3D=view.get_node("FlightRoute")
	var length:float=clampf(absf(run.hazard_specs[index].velocity.y)*sample.ttc/SCALE,.05,80)
	route.scale.z=length/route.mesh.size.z;route.position.z=length/2;route.visible=sample.warning
	var sign:Label3D=view.get_node("WarningLabel")
	sign.text=Run.hazard_name(kind);sign.visible=sample.warning
	if Run.Threats.is_ball(kind):
		view.get_node("BallBody").rotation.x=run.hazard_specs[index].travel/(rect.size.x/2)
		view.get_node("ContactRing").visible=run.rope.touches(run.obstacle_ids[index])
	elif kind=="barrel":sync_barrel_row(view,index,sample)
	else:
		var volume:Node3D=view.get_node("DangerVolume")
		volume.position.y=(sample.bottom+sample.top)/SCALE/2
		volume.visible=sample.active
		if volume.has_node("Spin"):volume.get_node("Spin").rotation=Vector3(run.elapsed*5.0,run.elapsed*2.0,0)
		view.get_node("WarningFootprint").visible=sample.warning

# 迎面威胁在道路推进到启动距离前、飞鹰在触发前都处于休眠。
func threat_dormant(index:int)->bool:
	var spec:Dictionary=run.hazard_specs[index]
	if run.kinds[index]=="drone":return float(spec.get("trigger",-1.0))<0
	return spec.get("front",false) and run.distance<float(spec.get("start_distance",-INF))

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
		"primary":
			# 联机开局要等两端都确认本章数据与场景就绪；先按下的“出发”记为待定，就绪后自动出发。
			if run.state=="start" and play_mode=="online" and net.in_match and not online_ready.all(func(value):return value):
				online_start_pending=true
				return
			apply_journey_primary()
		"chapter":
			# 联机章节由 01 号决定；只在开始页生效，两端在同一帧换章并重新确认就绪。
			if run.state!="start":return
			run.combat_trial=false
			run.level_index=clampi(int(arg),0,Journey.CHAPTERS.size()-1)
			run.retry()
			run.state="start"
			begin_chapter_sync()
			reset_journey_views()
		"pause":
			if (arg=="paused" and run.state in ["running","rescue"]) or (arg!="paused" and run.state=="paused"):run.pause()
			clear_controls()
		"retry":
			if not fail_showing():run.retry(run.state=="failed");reset_journey_views()
		"checkpoint":
			if run.state=="paused":run.resume_from_checkpoint();reset_journey_views()
		"difficulty":
			if run.state=="start" and not net.active():run.set_difficulty(arg);reset_journey_views()

func online_process(delta:float)->void:
	if not net.in_match:
		sync_view()
		return
	var input:=sample_local_input()
	announce_chapter_readiness()
	# 结算时本机还没拿到下一章数据，就先不确认，队友会等到双方都按下。
	var next:=next_chapter_key()
	var confirm_blocked:bool=run.state=="settlement" and next>=0 and not ChapterPacks.is_ready(next)
	if confirm_blocked:ChapterPacks.request(next,true)
	net.send_input(input.a,input.ja and not confirm_blocked)
	var fire: bool=input.get("fire",false)
	if fire!=last_fire_sent or input.get("reload",false) or input.get("drop",false) or input.get("swap",false):
		net.send_command("combat","%d,%d,%d,%d"%[int(fire),int(input.get("reload",false)),int(input.get("drop",false)),int(input.get("swap",false))])
		last_fire_sent=fire
	var applied:=0
	var start:=Time.get_ticks_usec()
	# 服务器每秒固定发 60 帧；只消化 1 帧/物理帧时，加载或卡顿造成的积压会变成永久输入延迟。
	# 稳态只留约 2 帧缓冲（实测隧道抖动 p99 约 22 毫秒）；积压时放宽单次帧数与时间预算追帧，不丢帧也不改变模拟结果。
	var queued:int=net.frames.size()
	# 自适应缓冲：按实测抖动留 2–6 帧，断流后攒够再继续，避免一卡一顿（见 net_client.gd playout_limit）。
	var limit:int=net.playout_limit(ONLINE_CATCHUP_FRAMES)
	var budget:int=Run.PRELOAD_SLICE_USEC if queued<=net.playout_target() else ONLINE_CATCHUP_USEC
	while not net.frames.is_empty() and applied<limit:
		var index:int=net.next_frame
		var frame:Dictionary=net.frames[0]
		if prepared_online_frame!=index:
			var seen:={}
			for entry in frame.cmds:
				var key:=str(entry[0])+":"+str(entry[1])+":"+str(entry[2])
				if not seen.has(key):
					if entry[1]=="combat":apply_combat_command(int(entry[0]),str(entry[2]))
					elif entry[1] in ["ready","load"]:apply_peer_status(int(entry[0]),entry[1],str(entry[2]))
					else:apply_command(entry[1],entry[2])
					seen[key]=true
			prepared_online_frame=index
		# 本章数据未挂载时同样保留整帧：下载完成后按原编号追帧，两端模拟结果不变。
		if not ChapterPacks.is_ready(chapter_key()):
			ChapterPacks.request(chapter_key(),true)
			last_prepare_ok=false
			break
		# 保留完整帧等待分帧准备，命令只执行一次，不跳帧或推进模拟时间。
		last_prepare_ok=not incremental_loading or prepare_journey_frame()
		if not last_prepare_ok: break
		net.take_frames(1)
		var before:String=run.state
		run.step(Run.FIXED_STEP*2,frame.a,frame.b,frame.ja,frame.jb)
		if run.state!=before:clear_controls()
		# 状态指纹要序列化整局状态，只在需要上报的帧计算。
		if index%NetClient.HASH_INTERVAL==0:net.report(index,run.sync_hash())
		net.acknowledge(index+1)
		online_frame_applied.emit(index)
		applied+=1
		if Time.get_ticks_usec()-start>=budget:break
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
	begin_chapter_sync()
	reset_journey_views()
	# 01 号把自己在主界面选的章节告诉双方；02 号的选择以 01 号为准。
	if net.role==0 and start_chapter>0 and start_chapter<Journey.CHAPTERS.size():
		net.send_command("chapter",str(start_chapter))

func begin_chapter_sync()->void:
	chapter_epoch+=1
	online_ready=[false,false]
	partner_load=[-1,-1]
	online_start_pending=false
	online_entry=true

func chapter_key()->int:
	return Catalog.TRAINING if run.combat_trial else run.level_index

func next_chapter_key()->int:
	if run.combat_trial or run.state!="settlement" or run.level_index>=Journey.CHAPTERS.size()-1:return -1
	return run.level_index+1

# 本机就绪后告诉对方（带换章序号，旧章节的确认不会算到新章节上）；下载中每 10% 报一次进度供对方显示。
func announce_chapter_readiness()->void:
	if run.state!="start":return
	if ChapterPacks.is_ready(chapter_key()) and last_prepare_ok:
		if ready_sent_epoch!=chapter_epoch:
			net.send_command("ready",str(chapter_epoch))
			ready_sent_epoch=chapter_epoch
		return
	var percent:=int(ChapterPacks.progress(chapter_key())*10.0)*10
	if percent!=load_sent:
		net.send_command("load",str(percent))
		load_sent=percent

func apply_peer_status(role:int,name:String,arg:String)->void:
	if role<0 or role>1:return
	if name=="load":
		partner_load[role]=int(arg)
		return
	if int(arg)!=chapter_epoch:return
	online_ready[role]=true
	partner_load[role]=100
	if online_start_pending and online_ready.all(func(value):return value) and run.state=="start":
		online_start_pending=false
		apply_journey_primary()

# 预取下一章：本章游玩期间在后台排队下载，结算时通常已就绪，不打断两人。
func prefetch_next_chapter(delta:float)->void:
	if not ChapterPacks.enabled or run.combat_trial:return
	prefetch_clock+=delta
	if prefetch_clock<2.0:return
	prefetch_clock=0.0
	if run.state in ["running","rescue","settlement","paused"] and run.level_index<Journey.CHAPTERS.size()-1:
		ChapterPacks.request(run.level_index+1,false)

func update_pack_overlay()->void:
	if pack_overlay==null:return
	var key:=chapter_key()
	var need_data:=not ChapterPacks.is_ready(key)
	var online:bool=online_entry and net.active()
	if online and net.in_match and run.state!="start":online_entry=false;online=false
	if not need_data and not online:
		pack_overlay.visible=false
		pack_overlay_key=""
		return
	var kind:="online" if online else "between"
	if pack_overlay_key!="%s:%d"%[kind,key]:
		pack_overlay_key="%s:%d"%[kind,key]
		pack_overlay.setup(key,kind)
	pack_overlay.visible=true
	var total:=ChapterPacks.bytes_total(key)
	var done:=ChapterPacks.bytes_done(key)
	var sizes:="%s / %s"%[ChapterPacks.megabytes(done),ChapterPacks.megabytes(total)] if total>0 else ""
	pack_overlay.show_error(ChapterPacks.failure)
	if not online:
		pack_overlay.set_stage("正在下载 %s 的章节数据"%Catalog.title(key),ChapterPacks.progress(key),sizes)
		return
	# 联机入场：连接 → 等队友 → 同步章节 → 下载 → 准备场景 → 双方就绪。
	var steps:=[]
	var connected:bool=net.connected
	var matched:bool=net.in_match
	var synced:bool=matched and net.next_frame>0
	var data_ready:bool=synced and not need_data
	var scene_ready:bool=data_ready and last_prepare_ok
	var both:bool=scene_ready and online_ready.all(func(value):return value)
	steps.append(["连接联机服务器","done" if connected else "active"])
	steps.append(["等待队友加入","done" if matched else ("active" if connected else "pending")])
	steps.append(["同步章节：%s"%Catalog.title(key),"done" if synced else ("active" if matched else "pending")])
	if ChapterPacks.enabled:steps.append(["下载章节数据 %s"%sizes,"done" if data_ready else ("active" if synced else "pending")])
	steps.append(["准备沿途场景","done" if scene_ready else ("active" if data_ready else "pending")])
	steps.append(["等待双方就绪","done" if both else ("active" if scene_ready else "pending")])
	pack_overlay.set_steps(steps)
	var players:=[]
	for role in range(2):
		var mine:bool=role==net.role
		var status:="未加入"
		if online_ready[role] and matched:status="已就绪"
		elif mine and matched:status="下载中 %d%%"%int(ChapterPacks.progress(key)*100) if need_data else "准备场景中"
		elif matched:status="载入中 %d%%"%partner_load[role] if partner_load[role]>=0 else "载入中"
		elif mine or (net.role<0 and role==0):status="连接中"
		players.append({"role":role,"name":"你" if mine else "队友","status":status,"ready":online_ready[role] and matched})
	pack_overlay.set_players(players)
	var done_steps:=steps.filter(func(step):return step[1]=="done").size()
	var stage:String=steps.filter(func(step):return step[1]!="done").map(func(step):return step[0]).front() if done_steps<steps.size() else "准备完成"
	var fraction:=(float(done_steps)+(ChapterPacks.progress(key) if synced and need_data else 0.0))/steps.size()
	pack_overlay.set_stage(stage,fraction,net_status.text if is_instance_valid(net_status) else "",not connected)
	if both:online_entry=false

func stop_online_match(_reason:String)->void:
	if run.state in ["running","rescue"]:run.pause()
	clear_controls()

func journey_net_status(message:String)->void:
	if is_instance_valid(net_status):net_status.text=message

# 回到开始页：联机时先断开（对方会收到断线提示），单人直接回到标题，可重新选择模式与难度。
# 不重新加载游戏资源，已准备的场景继续复用。
func return_home()->void:
	if fail_showing():return
	# 由主界面启动时回到章节选择；联机先断开，对方会收到断线提示。
	if from_menu():
		if net.active():net.disconnect_from()
		home_requested.emit()
		return
	if net.active():
		toggle_online()
	else:
		run.combat_trial=false
		run.new_campaign()
		# new_campaign 内部的 retry 会把状态置为 running，必须显式回到开始页，才会显示模式与难度选项。
		run.state="start"
		reset_journey_views()
	if is_instance_valid(net_status):net_status.text="远程双人：连接同一版本网页"
	clear_controls()

# 只有真正经过主界面进入时，开始页按钮才改为“返回主界面”；自动化入口跳过主界面时保留原训练切换。
func from_menu()->bool:
	return menu_entry and not home_requested.get_connections().is_empty()

func toggle_online()->void:
	if net.active():
		online_entry=false
		net.disconnect_from()
		run.lockstep=false
		run.random_seed=true
		run.new_campaign();run.state="start"
		reset_journey_views()
		net_status.text="已断开，可重新连接或选择单人模式"
	else:
		play_mode="online"
		online_entry=true
		net.connect_auto(net_address.text)
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
	var local_pair:=play_mode=="local"
	if local_pair:
		first=Vector2(float(key_down(KEY_D))-float(key_down(KEY_A)),float(key_down(KEY_W))-float(key_down(KEY_S)))
		second=Vector2(float(key_down(KEY_RIGHT))-float(key_down(KEY_LEFT)),float(key_down(KEY_UP))-float(key_down(KEY_DOWN)))
	# 手柄：菜单确认后的跳跃 / 射击键要先松开，移动不受影响。
	if pad_blocked and not Gamepad.any_held():pad_blocked=false
	var pad_a:Dictionary=Gamepad.read(Gamepad.device_for(0,local_pair))
	var pad_b:Dictionary=Gamepad.read(Gamepad.device_for(1,local_pair))
	if pad_a.move!=Vector2.ZERO:first=pad_a.move
	if pad_b.move!=Vector2.ZERO:second=pad_b.move
	if touch.move!=Vector2.ZERO: first=touch.move
	var touch_jump: bool=touch.take_jump()
	var actions: Dictionary=touch.take_combat()
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): fire_blocked=false
	var fire: bool=(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not fire_blocked and not touch_device) or actions.fire
	var pad_live:=not pad_blocked
	var input:={"a":first,"b":second,"ja":key_down(KEY_SPACE) or touch_jump or (play_mode=="online" and key_down(KEY_ENTER)) or (pad_live and pad_a.jump),"jb":key_down(KEY_ENTER) or (pad_live and pad_b.jump),"fire":fire or (pad_live and pad_a.fire),"reload":reload_requested or actions.reload,"drop":drop_requested or actions.drop,"swap":swap_requested or actions.get("swap",false)}
	if local_pair:
		input.fire_b=pad_live and pad_b.fire
		input.reload_b=reload_requested_b
		input.drop_b=drop_requested_b
		input.swap_b=swap_requested_b
	reload_requested=false
	drop_requested=false
	swap_requested=false
	reload_requested_b=false
	drop_requested_b=false
	swap_requested_b=false
	return input

func apply_combat_command(role: int, value: String) -> void:
	if run.state!="running" or role not in [0,1]: return
	var fields:=value.split(",")
	# 3 个字段为旧版客户端（没有换枪），4 个字段带换枪。
	if fields.size() not in [3,4]: return
	run.Combat.ensure_slots(run)
	run.combat.fire[role]=fields[0]=="1"
	run.combat.reload[role]=run.combat.reload[role] or fields[1]=="1"
	run.combat.drop[role]=run.combat.drop[role] or fields[2]=="1"
	if fields.size()==4: run.combat.swap[role]=run.combat.swap[role] or fields[3]=="1"

func chunk_chapter(number: int) -> Dictionary:
	if not run.combat_trial: return run.CHAPTERS[run.level_index]
	var themes: Array=[]
	for zone in range(6): themes.append(run.theme_at(number*CHUNK*SCALE))
	return {"length":run.finish_distance(),"zones":run.TRIAL_ZONES,"themes":themes}
