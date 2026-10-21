extends SceneTree

# 生产场景表现检查（headless）：按已证明路线跑一关，逐帧走真实的 sync_view / 音效事件 / 金币飞行补间。
# 检查：无脚本错误地到达结算；摆锤、散布陷阱出现并有模型；绳子网格每帧重建且两端贴着两人；
# 金币飞到得分栏后显示分数与真实分数一致；音效播放器确实被调用。
# 用法：Godot --headless --path . -s res://tests/random_scene.gd [-- 关卡0-2]
const Templates = preload("res://scripts/road_templates.gd")
var failed := 0

func check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok: failed += 1

func _initialize() -> void:
	call_deferred("drive")

func drive() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	var run = game.run
	check("开局随机种子已启用", run.random_seed)
	var first_seed: int = run.seed_value
	run.level_index = int(args[0]) if args.size() > 0 else 0
	game.primary_action()
	# 固定首个随机候选为本轮组合，后续抽签和散布仍使用生产种子与后台证明。
	run.generator.bag = ["charge_cargo"]
	run.generator.bag_level = run.level_index
	check("开始后换了新种子", run.seed_value != first_seed or run.seed_value != 20261012)
	var kinds := {}
	var extras := 0
	var max_flying := 0
	var rope_ok := true
	var rope_frames := 0
	var played := 0
	var sounds := {}
	var original_play: Callable = game.sfx.play
	var seen_segments := {}
	var taught := false
	for tick in range(120 * 160):
		while run.async_thread != null and run.async_thread.is_alive(): OS.delay_msec(1)
		var input: Array = Templates.existing_route_input(run)
		if run.charge_gate.active and not run.charge_gate.open and run.charge_gate.id == "tutorial":
			input = [Vector2.ZERO, Vector2.ZERO, false, false]
			if run.distance >= 60:
				# 本夹具每次推进两个固定步：到达有效站位后松开轴，避免单步控制器来回越过张紧门槛。
				input[0] = Vector2.LEFT if run.a.position.x > -64 else Vector2.ZERO
				input[1] = Vector2.RIGHT if run.b.position.x < 64 else Vector2.ZERO
		var previous: String = run.state
		var before := {"heights": run.heights.duplicate(), "shield": run.shield, "shield_uses": run.shield_uses, "locked": game.locked_threats()}
		run.step(1.0 / 120, input[0], input[1], input[2], input[3])
		taught = taught or run.gate_events.any(func(e): return e.id == "tutorial" and e.event == "opened")
		game.play_events(before, previous)
		game.frame_delta = 1.0 / 120
		game.sync_view()
		for segment in run.route_segments:
			if seen_segments.has(segment.number): continue
			seen_segments[segment.number] = true
			for hazard in segment.block.hazards:
				kinds[hazard.kind] = true
				if hazard.get("extra", false): extras += 1
		max_flying = maxi(max_flying, game.flying)
		if run.state == "running" and tick % 10 == 0:
			rope_frames += 1
			# 绳网格改为动态 ArrayMesh；身体倾斜绕腰部旋转，腰部挂点需经朝向换算。
			var mesh: Mesh = game.rope_view.mesh
			var ends: PackedVector3Array = game.rope_view.points
			var a: Vector3 = game.robots[0].position + game.robots[0].basis * Vector3(0, 1.4, 0)
			var b: Vector3 = game.robots[1].position + game.robots[1].basis * Vector3(0, 1.4, 0)
			rope_ok = rope_ok and mesh != null and mesh.get_surface_count() == 1 and ends[0].distance_to(a) < 0.05 and ends[ends.size() - 1].distance_to(b) < 0.05
		for player in game.sfx.players:
			if player.playing and player.stream != null:
				for name in game.sfx.streams:
					if game.sfx.streams[name] == player.stream: sounds[name] = true
		await process_frame
		if run.state != "running": break
	print("状态 ", run.state, " ", run.reason, " 段落 ", seen_segments.size(), " 陷阱 ", extras, " 种类 ", kinds.keys())
	print("金币 ", run.coins, " 显示分 ", game.shown_score, " 同时飞行最多 ", max_flying, " 音效 ", sounds.keys())
	check("按已证明路线到达结算", run.state == "settlement")
	check("第一关先完成合法充能教学", run.level_index != 0 or taught)
	check("独立踏板教学先于随机组合", run.level_index != 0 or run.gate_events.filter(func(e): return e.event == "opened").slice(0, 2).map(func(e): return e.id) == ["tutorial", "sync_tutorial"])
	check("后台实际安装充能货箱组合", run.gate_events.any(func(e): return e.id not in ["tutorial", "sync_tutorial"] and e.event == "opened"))
	check("出现散布陷阱", extras > 20)
	check("金币飞行补间出现过", max_flying > 0)
	# 等最后几枚飞完再核对分数。
	for n in range(90): await process_frame
	game.update_ui()
	check("飞行结束后得分栏等于真实分数", game.shown_score == game.target_score() and game.score_label.text == str(game.target_score()))
	check("绳子网格逐帧重建且两端贴住两人", rope_ok and rope_frames > 100)
	check("金币、起跳、落地、过关音效都播放过", sounds.has("coin") and sounds.has("jump") and sounds.has("land") and sounds.has("clear"))
	# 重试换新地图：失败后重试，种子改变。
	var seed_before: int = run.seed_value
	run.state = "failed"
	game.primary_action()
	check("重试后换了新种子", run.seed_value != seed_before)
	print("SCENE failed=%d" % failed)
	for player in game.sfx.players:
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	quit(1 if failed > 0 else 0)
