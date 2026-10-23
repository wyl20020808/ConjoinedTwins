extends SceneTree
# 第三章海神取景：真实生产场景（journey.tscn）里触发开战，按入场时间轴截图，再逐个推进招式状态截图，
# 检查模型、悬浮、动作、预警、激流、巨浪缺口、涌泉、震环、潮汐之心、雷光、海水与血条。截图完毕自动退出。
#   Godot --path . --resolution 1280x720 --script res://build-tools/poseidon/capture_poseidon.gd
# 输出目录取环境变量 POSEIDON_CAPTURE_DIR（默认 user://poseidon-capture/），不写入工程。
# 环境变量 POSEIDON_CAPTURE_ONLY=intro|fight 只截其中一部分。角色直接放到场地内只是取景夹具，不代表通关路线。
const Boss = preload("res://scripts/journey_boss.gd")
const Poseidon = preload("res://scripts/journey_poseidon.gd")
const MOMENTS := [0.6, 2.4, 4.2, 4.8, 5.8, 7.0, 8.6, 9.6, 10.6, 11.4, 12.4]
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
	print("POSEIDON_CAPTURE ", path, " error=", error, " state=", boss.state, " t=", snappedf(game.run.elapsed-boss.state_at, 0.01))

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
	Poseidon.enter(game.run, boss, state)

func capture() -> void:
	out = OS.get_environment("POSEIDON_CAPTURE_DIR")
	if out.is_empty(): out = ProjectSettings.globalize_path("user://poseidon-capture")
	DirAccess.make_dir_recursive_absolute(out)
	var only := OS.get_environment("POSEIDON_CAPTURE_ONLY")
	game = load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading = true
	game.start_chapter = 2
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.set_physics_process(false)
	var run = game.run
	run.random_seed = false
	run.seed_value = 20261023
	run.level_index = 2
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
	await shot("00_pool")
	place(boss.arena + 320)
	run.step(run.FIXED_STEP)
	var start: float = boss.state_at
	if only != "fight":
		for moment in MOMENTS:
			while run.elapsed - start < moment - 0.0001: await advance(1.0/60.0)
			await shot("intro_%02d_t%.1f" % [MOMENTS.find(moment) + 1, moment])
	if only == "intro":
		await finish()
		return
	run.step(run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, true, false)
	while boss.state != "idle": await advance(1.0/60.0)
	place(boss.arena + 900, -60, 10)
	await advance(0.3)
	await shot("fight_01_idle")
	begin(boss, "lance"); Poseidon.aim_lances(run, boss)
	await advance(1.0)
	await shot("fight_02_lance_aim")
	await advance(0.65)
	await shot("fight_03_lance_fire")
	await advance(1.2)
	begin(boss, "wave"); Poseidon.plan_gaps(run, boss)
	await advance(1.0)
	await shot("fight_04_wave_windup")
	await advance(1.2)
	await shot("fight_05_wave")
	await advance(0.8)
	await shot("fight_06_wave_pass")
	await advance(1.0)
	begin(boss, "geysers"); Poseidon.aim_geysers(run, boss)
	await advance(1.0)
	await shot("fight_07_geyser_aim")
	await advance(1.05)
	await shot("fight_08_geyser_erupt")
	await advance(0.8)
	await shot("fight_09_puddles")
	begin(boss, "summon")
	await advance(1.7)
	await shot("fight_10_summon")
	await advance(2.0)
	await shot("fight_11_jellies")
	for e in run.journey_events:
		if e.kind == "monster" and e.get("boss_add", false): run.Combat.damage(run, e, e.hp)
	boss.skill_seq += 1; Poseidon.start_channel(run, boss)
	await advance(1.0)
	await shot("fight_12_channel")
	await advance(1.6)
	await shot("fight_13_orb")
	while boss.state == "channel":
		var c := Poseidon.orb_center(boss, run.elapsed)
		run.step(run.FIXED_STEP, ((Vector2(c.x-55, c.y)-run.a.position)/12.0).limit_length(1.0), ((Vector2(c.x+55, c.y)-run.b.position)/12.0).limit_length(1.0))
		run.step(run.FIXED_STEP, ((Vector2(c.x-55, c.y)-run.a.position)/12.0).limit_length(1.0), ((Vector2(c.x+55, c.y)-run.b.position)/12.0).limit_length(1.0))
		run.combat.health = [100, 100]
		game.sync_view()
		await process_frame
		if Poseidon.hold_ratio(boss) > 0.5 and not FileAccess.file_exists(out.path_join("fight_14_rope_through.png")): await shot("fight_14_rope_through")
	await advance(0.6)
	await shot("fight_15_stagger")
	boss.hp = int(boss.max_hp*0.6)
	Poseidon.enter(run, boss, "idle")
	while boss.state != "roar": await advance(1.0/60.0)
	await advance(0.9)
	await shot("fight_16_stage_roar")
	while boss.state != "idle": await advance(1.0/60.0)
	place(boss.arena + 900, -60, 10)
	begin(boss, "ring")
	await advance(1.3)
	await shot("fight_17_ring")
	await advance(1.5)
	boss.hp = int(boss.max_hp*0.25)
	Poseidon.enter(run, boss, "idle")
	while boss.state != "roar": await advance(1.0/60.0)
	while boss.state != "idle": await advance(1.0/60.0)
	place(boss.arena + 900, -60, 10)
	begin(boss, "lance"); Poseidon.aim_lances(run, boss)
	await advance(1.25)
	await shot("fight_18_stage3_lances")
	boss.skill_seq += 1; Poseidon.start_channel(run, boss)
	while boss.state != "tsunami": await advance(1.0/60.0)
	await advance(0.4)
	await shot("fight_19_tsunami")
	run.Combat.damage(run, boss, boss.max_hp)
	await advance(1.5)
	await shot("fight_20_death")
	await advance(3.0)
	await shot("fight_21_sunk")
	await finish()

func finish() -> void:
	game.queue_free()
	for n in range(4): await process_frame
	quit(0)
