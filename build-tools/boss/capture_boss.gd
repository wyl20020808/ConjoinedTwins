extends SceneTree
# Boss 战取景：用真实生产场景（journey.tscn）在场地内逐个推进 Boss 状态并截图，检查模型、动作、
# 地面预警、特效与血条。只通过 build-tools/capture_hidden.py 在隐藏窗口中运行：
#   python build-tools/capture_hidden.py res://build-tools/boss/capture_boss.gd
# 输出目录取环境变量 BOSS_CAPTURE_DIR（默认 user://boss-capture/），不写入工程。
# 角色直接放到场地内只是取景夹具，不代表通关路线。
const Boss = preload("res://scripts/journey_boss.gd")
const Combat = preload("res://scripts/journey_combat.gd")
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

func steps(count: int) -> void:
	for n in range(count):
		game.run.step(game.run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO)
		game.run.combat.health = [100, 100]
		game.run.combat.invulnerable = [0.0, 0.0]

func settle() -> void:
	var waits := 0
	while waits < 3000:
		var ready: bool = game.prepare_journey_frame()
		if ready and game.chunk_jobs.is_empty() and game.chunk_assets.pending.is_empty() and game.chunk_assets.active.is_empty(): break
		waits += 1
		await process_frame

func shot(name: String) -> void:
	await settle()
	for n in range(6):
		game.sync_view()
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	var error := root.get_texture().get_image().save_png(path)
	print("BOSS_CAPTURE ", path, " error=", error, " state=", Boss.boss(game.run).get("state", ""))

func capture() -> void:
	out = OS.get_environment("BOSS_CAPTURE_DIR")
	if out.is_empty(): out = ProjectSettings.globalize_path("user://boss-capture")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading = true
	game.start_chapter = 0
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.set_physics_process(false)
	var run = game.run
	run.random_seed = false
	run.seed_value = 20261021
	run.retry()
	run.state = "running"
	for gate in run.charge_gates:
		gate.open = true
		gate.opened_at = -10.0
	run.select_charge_gate()
	var boss: Dictionary = Boss.boss(run)
	run.combat.weapons = [Combat.gun("smg"), Combat.gun("shotgun")]
	place(boss.arena - 200)
	steps(2)
	await shot("01_approach")
	place(boss.arena + 320)
	steps(int(1.6 / run.FIXED_STEP))
	await shot("02_intro_roar")
	steps(int(2.0 / run.FIXED_STEP))
	place(boss.arena + 1150)
	steps(1)
	boss.skill_seq += 1
	Boss.start_spikes(run, boss)
	steps(int(0.9 / run.FIXED_STEP))
	await shot("03_spikes_warning")
	steps(int(0.75 / run.FIXED_STEP))
	await shot("04_spikes_erupt")
	boss.skill_seq += 1
	boss.sweep_side = 1.0
	Boss.enter(run, boss, "sweep")
	steps(int(1.0 / run.FIXED_STEP))
	await shot("05_sweep_warning")
	steps(int(0.65 / run.FIXED_STEP))
	await shot("06_sweep_wave")
	boss.skill_seq += 1
	Boss.start_seeds(run, boss)
	steps(int(1.75 / run.FIXED_STEP))
	await shot("07_seeds_flight")
	boss.skill_seq += 1
	Boss.start_root(run, boss)
	place(boss.binding.y, -70, 70)
	steps(int(2.0 / run.FIXED_STEP))
	await shot("08_root_burning")
	steps(int(1.4 / run.FIXED_STEP))
	await shot("09_stagger_exposed")
	boss.hp = int(boss.max_hp * 0.25)
	Boss.enter(run, boss, "idle")
	boss.stage = 1
	steps(int(3.5 / run.FIXED_STEP))
	place(boss.arena + 1150)
	steps(int(1.5 / run.FIXED_STEP))
	await shot("10_stage3_thorns")
	Boss.enter(run, boss, "stagger")
	Combat.damage(run, boss, boss.max_hp)
	steps(int(2.0 / run.FIXED_STEP))
	await shot("11_defeated")
	game.queue_free()
	for n in range(4): await process_frame
	quit(0)
