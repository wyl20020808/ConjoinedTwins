extends SceneTree
# 开场运镜与 Boss 巢穴暗示：只在打开开关、章节从头开始时排上；期间两人不能动、HUD 收起；
# 镜头先在巢穴、分镜特写不出路面、结束时正好落回正常镜头；跳跃可跳过；存档恢复不重播；
# 沉睡 Boss 的浓烟与每 0.5 秒一拍的地面震动在场地附近生效。
const Boss = preload("res://scripts/journey_boss.gd")
const Opening = preload("res://scripts/journey_opening.gd")
var failures := 0
var game
var run

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize() -> void: call_deferred("verify")

func advance(seconds: float, move := Vector2.ZERO, jump := false) -> void:
	var steps := int(round(seconds/run.FIXED_STEP))
	for n in range(steps):
		run.step(run.FIXED_STEP, move, move, jump and n == 0, false)
		if n%2 == 1: game.sync_view()

func place(y: float) -> void:
	run.a.position = Vector2(-42, y)
	run.b.position = Vector2(42, y)
	run.distance = y
	run.rope.reset(run.a.position, run.b.position)

func verify() -> void:
	game = load("res://scenes/journey.tscn").instantiate()
	game.start_chapter = 0
	game.opening_enabled = true
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.set_physics_process(false); game.set_process(false)
	game.frame_delta = 1.0/60
	run = game.run
	check(run.opening_at == 0.0 and run.state == "start", "第一章开始页已排上开场")
	run.opening_enabled = false
	run.retry()
	check(run.opening_age() < 0.0, "开关关闭时不排开场")
	run.opening_enabled = true
	run.random_seed = false
	run.seed_value = 20261021
	run.retry()
	run.state = "start"
	game.sync_view()
	check(not game.opening_foci.is_empty(), "开始页就提前载入巢穴一带")
	game.apply_journey_primary()
	check(run.state == "running" and run.opening_active(), "按出发后开始播放")
	var start_a: Vector2 = run.a.position
	advance(0.5, Vector2(0, 1))
	check(run.a.position.distance_to(start_a) < 0.01, "开场期间按方向键不移动")
	check(not game.get_node("JourneyCanvas").visible, "开场期间 HUD 收起")
	var smoke := Opening.smoke_center(run)
	check(game.camera_shot().origin.distance_to(smoke) < 60.0, "镜头先在 Boss 巢穴")
	var shots: Array = game.opening_keys(game.opening_home())
	check(shots.size() == 6 and shots[0][2] == "lair" and shots[-1][2] == "heroes", "分镜：巢穴、四处特写、两人")
	var npc := 0
	for i in range(1, shots.size()-1):
		var hit := false
		for event in run.journey_events:
			if event.kind == "monster" and Opening.world(event.rect.get_center(), 1.0).distance_to(shots[i][3]) < 0.01: hit = true
		if hit: npc += 1
	check(npc >= 1 and npc <= 3, "特写里怪物与机关都有（怪物 %d 处）" % npc)
	var inside := true
	var t := 0.5
	while t < shots[-1][0]:
		var eye: Vector3 = Opening.pose(game, game.opening_home(), shots, t).transform.origin
		if shots[Opening.current(shots, t)][2] == "close" and absf(eye.x) > Opening.ROAD_HALF+0.01: inside = false
		t += 0.1
	check(inside, "特写机位不出路面")
	# 完整播放：结束前一刻镜头已与正常镜头重合，结束后恢复操作。
	advance(run.OPENING-0.55)
	var home: Transform3D = game.opening_home()
	check(game.camera_shot().origin.distance_to(home.origin) < 0.3, "结尾落回正常镜头")
	advance(0.1)
	check(not run.opening_active(), "开场按时结束")
	var before: Vector2 = run.a.position
	advance(0.5, Vector2(0, 1))
	check(run.a.position.y > before.y+10.0, "开场结束后可以前进")
	# 跳过：0.6 秒后按跳跃，剩下交还镜头的时间后结束。
	run.retry()
	advance(0.7)
	advance(run.FIXED_STEP*2, Vector2.ZERO, true)
	check(run.opening_skipped_age > 0.0 and run.opening_active(), "按跳跃进入交还段")
	advance(run.OPENING_RETURN+0.05)
	check(not run.opening_active(), "跳过后交还完毕")
	check(game.camera_shot().origin.distance_to(game.opening_home().origin) < 0.05, "跳过后镜头回到正常位置")
	# 存档恢复不重播开场。
	run.retry()
	advance(0.3)
	run.capture_checkpoint()
	run.state = "failed"
	check(run.restore_checkpoint() and not run.opening_active() and run.opening_age() < 0.0, "开场期间记下的存档恢复后不重播开场")
	# 巢穴暗示：沉睡时浓烟持续喷出，走近场地每 0.5 秒一拍地面震动。
	for gate in run.charge_gates:
		gate.open = true
		gate.opened_at = -10.0
	run.select_charge_gate()
	var boss: Dictionary = Boss.boss(run)
	place(boss.arena + 100)
	advance(0.6)
	check(game.opening_smoke.visible and game.opening_smoke.emitting, "沉睡 Boss 巢穴冒浓烟")
	var beat: int = game.get_meta("lair_thump", -1)
	advance(0.5)
	check(beat >= 0 and game.get_meta("lair_thump", -1) == beat+1, "每 0.5 秒一拍地面震动")
	place(boss.arena + 320)
	advance(0.2)
	check(boss.phase == "intro", "开战后照常进入 Boss 入场")
	advance(Boss.INTRO_RISE+0.2)
	check(not game.opening_smoke.emitting, "破土后浓烟停止喷出")
	for p in game.sfx.players: p.stop()
	game.queue_free()
	await process_frame
	print("JOURNEY_OPENING failures=", failures)
	quit(1 if failures else 0)
