extends SceneTree

# 存档点专项：生产 road_run（后台生成、固定种子）按已证明路线推进。
# 1. 推进中按段落自动存档，存档时两人站稳、附近无危险；
# 2. 失败后恢复：位置、计时、金币、障碍布局与存档时刻一致，种子不变；
# 3. 存档之后已生成的段落原样重装，继续推进能到达结算；
# 4. 同一存档可多次恢复；整关重试清空存档；
# 5. 联机锁步两端失败恢复后状态指纹一致；
# 6. 生产场景失败页主按钮走存档恢复。
# 用法：Godot --headless --path . -s res://tests/checkpoint.gd
const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")
var failures := 0
var report: Array = []

func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	report.append({"name": label, "passed": ok})
	if not ok: failures += 1

func wait_worker(run) -> void:
	while run.async_thread != null and run.async_thread.is_alive(): OS.delay_msec(1)

func make_run(difficulty: String, level: int, seed_value: int, lockstep := false):
	var run = Run.new(true, true)
	run.lockstep = lockstep
	run.difficulty = difficulty
	run.level_index = level
	run.seed_value = seed_value
	run.retry()
	return run

func tick(run) -> void:
	wait_worker(run)
	var input: Array = Templates.existing_route_input(run)
	run.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])

func layout(run) -> Array:
	var rows: Array = []
	for i in range(run.obstacles.size()): rows.append([run.obstacle_ids[i], run.kinds[i], run.obstacles[i]])
	return rows

func reward_ids(run) -> Array:
	var ids: Array = []
	for reward in run.rewards: ids.append([reward.id, reward.position])
	return ids

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	verify_level("普通", 0, 4242)
	verify_level("困难", 2, 777)
	verify_lockstep()
	await verify_scene()
	var file := FileAccess.open("res://tests/checkpoint-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": report, "failures": failures}, "\t"))
	file.close()
	print("CHECKPOINT failures=", failures)
	quit(1 if failures else 0)

func verify_level(difficulty: String, level: int, seed_value: int) -> void:
	var tag := "%s 第%d关 " % [difficulty, level + 1]
	var run = make_run(difficulty, level, seed_value)
	check(tag + "开局即有起点存档", not run.checkpoint.is_empty() and run.checkpoint.progress == 0.0)
	# 推进到约 60% 路程，记录每次存档时刻的布局。
	var saves: Array = []
	var captures: Array = []
	var last_progress := -1.0
	var safe_ok := true
	var snapshots: Array = []
	while run.state == "running" and run.progress() < run.finish_distance() * 0.6:
		tick(run)
		if run.checkpoint.progress != last_progress:
			last_progress = run.checkpoint.progress
			captures.append(last_progress)
			safe_ok = safe_ok and run.checkpoint_safe()
			snapshots.append(run.checkpoint.duplicate(true))
			saves.append({"layout": layout(run), "rewards": reward_ids(run), "coins": run.coins, "elapsed": run.elapsed,
				"a": run.a.position, "b": run.b.position, "progress": run.progress(), "seed": run.seed_value})
	check(tag + "推进中途未失败 state=%s reason=%s" % [run.state, run.reason], run.state == "running")
	var segments: int = run.next_segment
	print(tag, "存档进度(米)=", captures.map(func(p): return int(p / 20.0)), " 已生成段=", segments)
	check(tag + "按段落多次存档 次数=%d" % captures.size(), captures.size() >= 4)
	check(tag + "存档时刻两人站稳且附近无危险", safe_ok)
	var widest := 0.0
	for n in range(1, captures.size()): widest = maxf(widest, captures[n] - captures[n - 1])
	var average: float = captures[-1] / maxf(1.0, captures.size() - 1)
	check(tag + "平均每 %.2f 段一个存档（≤2）" % [average / Templates.SEGMENT], average <= Templates.SEGMENT * 2.0)
	check(tag + "最大存档间距 %.1f 段（≤5）" % [widest / Templates.SEGMENT], widest <= Templates.SEGMENT * 5)
	var history_before: Dictionary = run.block_history.duplicate(true)

	# 人为失败后恢复。取倒数第三个存档，使存档之后已生成的多个段落必须从记录重装。
	var pick: int = maxi(0, snapshots.size() - 3)
	var saved: Dictionary = saves[pick]
	run.fail_threat("测试失败")
	run.checkpoint = snapshots[pick].duplicate(true)
	check(tag + "回退存档之后已有段落 存档段=%d 已生成=%d" % [snapshots[pick].run.next_segment, segments], snapshots[pick].run.next_segment < segments)
	check(tag + "失败后保留存档", run.state == "failed" and not run.checkpoint.is_empty())
	check(tag + "恢复成功", run.restore_checkpoint())
	check(tag + "恢复后进入推进", run.state == "running" and run.reason == "")
	check(tag + "位置回到存档点", run.a.position == saved.a and run.b.position == saved.b and is_equal_approx(run.progress(), saved.progress))
	check(tag + "计时与金币回到存档时刻", run.elapsed == saved.elapsed and run.coins == saved.coins)
	check(tag + "种子不变", run.seed_value == saved.seed)
	var restored: Array = layout(run)
	check(tag + "存档时已加载障碍原样恢复 %d/%d" % [saved.layout.size(), restored.size()], restored.slice(0, saved.layout.size()) == saved.layout)
	var restored_rewards: Array = reward_ids(run)
	check(tag + "存档时已加载奖励原样恢复", restored_rewards.slice(0, saved.rewards.size()) == saved.rewards)
	check(tag + "恢复给予短暂无敌", run.invulnerable_until > run.elapsed)
	check(tag + "失败计数与恢复次数", run.failures == 1 and run.checkpoint_restores == 1)

	# 继续推进：存档后的段落按记录原样重装，最终到达结算。
	var reinstalled := true
	while run.state == "running":
		tick(run)
		for segment in run.route_segments:
			if history_before.has(segment.number) and var_to_str(segment.block) != var_to_str(history_before[segment.number]): reinstalled = false
	for number in history_before:
		if var_to_str(run.block_history.get(number)) != var_to_str(history_before[number]): reinstalled = false
	check(tag + "存档后段落按原布局重装", reinstalled)
	var sources := {}
	for event in run.async_events: sources[event.source] = sources.get(event.source, 0) + 1
	check(tag + "恢复后使用段落记录重装 %s" % [sources], sources.get("checkpoint_history", 0) > 0)
	check(tag + "恢复后到达结算 state=%s reason=%s" % [run.state, run.reason], run.state == "settlement")
	# 从每个存档恢复后完全不按键走完整个安全窗口，不能立刻失败。
	var deaths: Array = []
	for snapshot in snapshots:
		run.state = "failed"
		run.checkpoint = snapshot.duplicate(true)
		run.restore_checkpoint()
		for n in range(int(Run.CHECKPOINT_CLEAR_AHEAD * 120)):
			wait_worker(run)
			run.step(Run.FIXED_STEP)
			if run.state != "running": break
		if run.state != "running": deaths.append("%dm:%s" % [int(snapshot.progress / 20.0), run.reason])
	check(tag + "每个存档恢复后不按键 %.1f 秒不失败 %d 个 %s" % [Run.CHECKPOINT_CLEAR_AHEAD, snapshots.size(), deaths], deaths.is_empty())
	run.dispose()

	# 同一存档可多次恢复；真实坠落也能恢复。
	run = make_run(difficulty, level, seed_value)
	while run.state == "running" and run.progress() < Templates.START_DISTANCE + Templates.SEGMENT * 2: tick(run)
	var first_save: Dictionary = run.checkpoint.duplicate(true)
	var walked_off := false
	for attempt in range(2):
		run.fail_threat("测试失败 %d" % attempt)
		run.restore_checkpoint()
		for n in range(240):
			wait_worker(run)
			run.step(Run.FIXED_STEP, Vector2(1, 0), Vector2(1, 0), false, false)
			if run.state != "running": break
		# 一人踩空、队友站稳时先进入坠落救援；不按键则 3 秒后共同坠落。
		for n in range(480):
			if run.state != "rescue": break
			run.step(Run.FIXED_STEP)
		walked_off = walked_off or run.fallen[0] or run.fallen[1]
	check(tag + "走出路面坠落失败 reason=%s" % run.reason, run.state == "failed" and walked_off)
	check(tag + "坠落后存档未被覆盖", var_to_str(run.checkpoint) == var_to_str(first_save))
	check(tag + "坠落后可再次恢复", run.restore_checkpoint() and run.state == "running" and run.a.position == first_save.a and run.checkpoint_restores == 3)
	run.fail_threat("测试失败")
	run.retry(true)
	check(tag + "整关重试清空存档记录", run.checkpoint_restores == 0 and run.checkpoint.progress == 0.0 and run.next_segment == run.block_history.size())
	run.dispose()

func verify_lockstep() -> void:
	var ends: Array = [make_run("普通", 1, 99, true), make_run("普通", 1, 99, true)]
	var same := true
	for phase in range(2):
		for n in range(120 * 25):
			for run in ends: tick(run)
			if ends[0].state != "running": break
		same = same and ends[0].sync_hash() == ends[1].sync_hash()
		for run in ends:
			if run.state == "running": run.fail_threat("测试失败")
			run.restore_checkpoint()
		same = same and ends[0].sync_hash() == ends[1].sync_hash()
	for n in range(120 * 10):
		for run in ends: tick(run)
	check("联机锁步两端恢复后状态一致 restores=%d" % ends[0].checkpoint_restores, same and ends[0].sync_hash() == ends[1].sync_hash() and ends[0].checkpoint_restores == 2)
	for run in ends: run.dispose()

func verify_scene() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.random_seed = false
	game.run.charge_tutorial = false
	game.run.seed_value = 4242
	game.run.retry()
	for n in range(120 * 8): tick(game.run)
	var saved: Dictionary = game.run.checkpoint.duplicate(true)
	game.run.fail_threat("测试失败")
	game.fail_clock = 10.0
	game.update_ui()
	check("失败页主按钮提示存档继续", game.primary.text.begins_with("从存档点继续") and game.subtitle.text.contains("存档点"))
	game.apply_command("primary")
	check("主按钮恢复存档", game.run.state == "running" and game.run.checkpoint_restores == 1 and game.run.a.position == saved.a)
	game.run.fail_threat("测试失败")
	game.apply_command("retry")
	check("R 整关重开清空存档", game.run.state == "running" and game.run.checkpoint_restores == 0 and game.run.checkpoint.progress == 0.0)
	game.queue_free()
	await process_frame
