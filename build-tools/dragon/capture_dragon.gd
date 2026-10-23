extends SceneTree
# 第二章魔龙取景：真实生产场景（journey.tscn）里触发开战，按入场时间轴截图，再逐个推进招式状态截图，
# 检查模型、飞行姿态、动作、预警、火焰与锁链等特效和血条。截图完毕自动退出。
#   Godot --path . --resolution 1280x720 --script res://build-tools/dragon/capture_dragon.gd
# 输出目录取环境变量 DRAGON_CAPTURE_DIR（默认 user://dragon-capture/），不写入工程。
# 环境变量 DRAGON_CAPTURE_ONLY=intro|fight|air 只截其中一部分（air：悬空炎息与召唤火蝠）；DRAGON_CAPTURE_MOMENTS 指定入场时刻（逗号分隔秒数）。
# 角色直接放到场地内只是取景夹具，不代表通关路线。
const Boss = preload("res://scripts/journey_boss.gd")
const Dragon = preload("res://scripts/journey_dragon.gd")
const MOMENTS := [0.6, 2.0, 3.2, 4.4, 5.6, 7.2, 8.0, 8.5, 9.9, 10.6, 12.6, 14.6]
var game
var out := ""

func _initialize() -> void:
	call_deferred("capture")

func place(y: float, ax: float = -42.0, bx: float = 42.0) -> void:
	var run = game.run
	run.a.position = Vector2(ax, y)
	run.b.position = Vector2(bx, y)
	run.distance = y
	run.rope.reset(run.a.position, run.b.position)

func settle() -> void:
	var waits := 0
	while waits < 3000:
		var ready: bool = game.prepare_journey_frame()
		if ready and game.chunk_jobs.is_empty() and game.chunk_assets.pending.is_empty() and game.chunk_assets.active.is_empty(): break
		waits += 1
		await process_frame

func shot(name: String) -> void:
	await settle()
	game.sync_view()
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	var error := root.get_texture().get_image().save_png(path)
	var boss: Dictionary = Boss.boss(game.run)
	print("DRAGON_CAPTURE ", path, " error=", error, " state=", boss.state, " t=", snappedf(game.run.elapsed-boss.state_at, 0.01))

# 逐帧推进模拟（每渲染一帧推进 1/60 秒），粒子与动作按真实节奏运动；角色保持满血。
func advance(seconds: float) -> void:
	var run = game.run
	var until: float = run.elapsed+seconds
	while run.elapsed < until-0.0001:
		run.step(run.FIXED_STEP)
		run.step(run.FIXED_STEP)
		run.combat.health = [100, 100]
		run.combat.invulnerable = [0.0, 0.0]
		game.sync_view()
		await process_frame

func begin(boss: Dictionary, state: String) -> void:
	boss.skill_seq += 1
	Dragon.enter(game.run, boss, state)

func capture() -> void:
	out = OS.get_environment("DRAGON_CAPTURE_DIR")
	if out.is_empty(): out = ProjectSettings.globalize_path("user://dragon-capture")
	DirAccess.make_dir_recursive_absolute(out)
	var only := OS.get_environment("DRAGON_CAPTURE_ONLY")
	var moments: Array = MOMENTS
	if not OS.get_environment("DRAGON_CAPTURE_MOMENTS").is_empty():
		moments = Array(OS.get_environment("DRAGON_CAPTURE_MOMENTS").split(",")).map(func(x): return float(x))
	game = load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading = true
	game.start_chapter = 1
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.set_physics_process(false)
	var run = game.run
	run.random_seed = false
	run.seed_value = 20261022
	run.level_index = 1
	run.retry()
	run.state = "running"
	for gate in run.charge_gates:
		gate.open = true
		gate.opened_at = -10.0
	run.select_charge_gate()
	var boss: Dictionary = Boss.boss(run)
	Engine.max_fps = 60
	place(boss.arena + 200)
	run.step(run.FIXED_STEP)
	await shot("00_lair")
	place(boss.arena + 320)
	run.step(run.FIXED_STEP)
	var start: float = boss.state_at
	if only != "fight":
		for moment in moments:
			while run.elapsed - start < moment - 0.0001: await advance(1.0/60.0)
			await shot("intro_%02d_t%.1f" % [moments.find(moment) + 1, moment])
	if only == "intro":
		await finish()
		return
	# 跳过入场，进入战斗。
	run.step(run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, true, false)
	while boss.state != "idle": await advance(1.0/60.0)
	place(boss.arena + 900, -110, -40)
	await advance(0.3)
	await shot("fight_01_idle")
	if only == "air":
		await air(boss)
		await finish()
		return
	begin(boss, "breath"); boss.breath_side = 1.0
	await advance(0.9)
	await shot("fight_02_breath_windup")
	await advance(0.9)
	await shot("fight_03_breath_fire")
	await advance(0.6)
	await shot("fight_04_breath_late")
	await advance(1.0)
	begin(boss, "tail")
	await advance(0.7)
	await shot("fight_05_tail_windup")
	await advance(0.65)
	await shot("fight_06_tail_ring")
	await advance(1.6)
	begin(boss, "meteors"); Dragon.aim_meteors(run, boss)
	await advance(1.0)
	await shot("fight_07_meteor_call")
	await advance(0.85)
	await shot("fight_08_meteor_fall")
	await advance(0.6)
	await shot("fight_09_meteor_pools")
	await advance(1.5)
	boss.skill_seq += 1; Dragon.start_charge(run, boss)
	var p0 := Dragon.plate_center(boss, 0)
	var p1 := Dragon.plate_center(boss, 1)
	await advance(1.2)
	await shot("fight_10_charge")
	place(p0.y, p0.x, p1.x)
	while boss.state == "charge": await advance(1.0/60.0)
	await advance(0.6)
	await shot("fight_11_pinned")
	place(boss.arena + 900, -110, -40)
	await advance(1.5)
	await shot("fight_12_pinned_core")
	boss.hp = int(boss.max_hp*0.6)
	Dragon.enter(run, boss, "idle")
	while boss.state != "roar": await advance(1.0/60.0)
	await advance(0.9)
	await shot("fight_13_stage_roar")
	while boss.state != "idle": await advance(1.0/60.0)
	place(boss.arena + 700, -42, 42)
	boss.skill_seq += 1; boss.lane_side = 1.0; boss.lane_y = Dragon.lane_target(run, boss); Dragon.enter(run, boss, "strafe")
	await advance(0.7)
	await shot("fight_14_takeoff")
	await advance(1.3)
	await shot("fight_15_flying")
	await advance(1.2)
	await shot("fight_16_strafe")
	await advance(0.7)
	await shot("fight_17_strafe_late")
	await advance(2.2)
	await shot("fight_18_landing")
	await advance(1.6)
	boss.hp = int(boss.max_hp*0.25)
	Dragon.enter(run, boss, "idle")
	while boss.state != "roar": await advance(1.0/60.0)
	while boss.state != "idle": await advance(1.0/60.0)
	place(boss.arena + 900, -110, -40)
	begin(boss, "breath"); boss.breath_side = -1.0
	await advance(2.2)
	await shot("fight_19_stage3_walls_breath")
	boss.skill_seq += 1; Dragon.start_charge(run, boss)
	place(boss.arena + 900, -110, -40)
	while boss.state != "nova": await advance(1.0/60.0)
	await advance(0.35)
	await shot("fight_20_nova")
	run.Combat.damage(run, boss, boss.max_hp)
	await advance(1.0)
	await shot("fight_21_death")
	await advance(2.5)
	await shot("fight_22_dead")
	await finish()

# 悬空炎息：起飞 → 悬停 → 火柱追人 → 飞回降落；召唤火蝠：咆哮 → 火蝠飞出 → 扑向两人。
func air(boss: Dictionary) -> void:
	var run = game.run
	boss.skill_seq += 1; Dragon.start_hover(run, boss)
	await advance(0.7)
	await shot("air_01_takeoff")
	await advance(1.4)
	await shot("air_02_hover_aim")
	await advance(1.2)
	await shot("air_03_beam")
	await advance(1.4)
	await shot("air_04_beam_trail")
	while boss.state == "hover" and run.elapsed-boss.state_at < Dragon.hover_beam_end(boss)+0.5: await advance(1.0/60.0)
	await shot("air_05_return")
	while boss.state == "hover": await advance(1.0/60.0)
	await shot("air_06_landed")
	await advance(1.0)
	begin(boss, "bats")
	await advance(0.8)
	await shot("air_07_bats_roar")
	await advance(0.9)
	await shot("air_08_bats_out")
	await advance(1.6)
	await shot("air_09_bats_dive")
	await advance(1.2)
	await shot("air_10_bats_close")

func finish() -> void:
	game.queue_free()
	for n in range(4): await process_frame
	quit(0)
