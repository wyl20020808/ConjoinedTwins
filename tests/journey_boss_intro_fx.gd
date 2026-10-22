extends SceneTree
# Boss 入场一次性特效：三次泼土与三道咆哮冲击波各记一次标记（标记名不能含小数点，否则写不进元数据、每帧重复触发）；
# 回到沉睡后清掉标记，下次开战重新播放。
const Boss = preload("res://scripts/journey_boss.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _initialize() -> void: call_deferred("verify")

func place(run, y: float) -> void:
	run.a.position = Vector2(-42, y)
	run.b.position = Vector2(42, y)
	run.distance = y
	run.rope.reset(run.a.position, run.b.position)

func verify() -> void:
	var game = load("res://scenes/journey.tscn").instantiate()
	game.start_chapter = 0
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.set_physics_process(false); game.set_process(false)
	game.frame_delta = 1.0/60
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
	place(run, boss.arena + 200)
	run.step(run.FIXED_STEP)
	game.sync_view()
	place(run, boss.arena + 320)
	run.step(run.FIXED_STEP)
	check(boss.phase == "intro", "越过开战线开始入场")
	var start: float = boss.state_at
	while run.elapsed - start < Boss.INTRO - 0.05:
		run.step(run.FIXED_STEP); run.step(run.FIXED_STEP)
		game.sync_view()
	var view: Node3D = game.event_views.get(boss.id)
	check(view != null, "Boss 画面已建立")
	if view != null:
		for n in range(3):
			check(view.has_meta("fx_intro_soil%d" % n), "第 %d 次泼土记下一次性标记" % (n + 1))
			check(view.has_meta("fx_intro_wave%d" % n), "第 %d 道冲击波记下一次性标记" % (n + 1))
		boss.phase = "dormant"
		game.sync_view()
		check(not view.has_meta("fx_intro_soil0") and not view.has_meta("fx_intro_wave0"), "回到沉睡清掉入场标记")
	for p in game.sfx.players: p.stop()
	game.queue_free()
	await process_frame
	print("JOURNEY_BOSS_INTRO_FX failures=", failures)
	quit(1 if failures else 0)
