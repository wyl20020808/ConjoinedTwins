extends SceneTree

const Run = preload("res://scripts/road_run.gd")
const Keyboard = preload("res://tests/keyboard_route_assertions.gd")
var checks: Array = []
var metrics := {}
var game
var run

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, ok: bool) -> void:
	checks.append({"name": name, "passed": ok})
	print("PASS " if ok else "FAIL ", name)

# 只调用场景方法，不注入系统或 Godot 全局键盘状态。
func logical_key(code: int, echo_event: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo_event
	game._unhandled_key_input(event)

func signature() -> String:
	return str(hash([run.a.position, run.b.position, run.heights, run.vertical_speed, run.rope.path, run.rope.contacts, run.rope.required, run.hazard_specs, run.obstacles, run.obstacle_ids, run.rewards, run.claimed_rewards, run.coins, run.prizes, run.shield, run.shield_uses, run.distance, run.world_origin, run.next_segment, run.recycled, run.rebases, run.state, run.results]))

func verify() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.capture_mode = true
	run = game.run
	check("默认生产入口为本地双人开始页", run.state == "start" and game.robots.size() == 2 and game.title.text == "共生归航")
	# 安全夹具用于界面入口、暂停及重试；完整生成在下方记录路线复放中启用。
	run.generation_enabled = false
	run.streaming = false
	run.obstacles.clear()
	run.kinds.clear()
	run.obstacle_heights.clear()
	run.obstacle_ids.clear()
	run.hazard_specs.clear()
	game.primary_action()
	check("开始按钮启动并屏蔽十个旧移动/跳跃键", run.state == "running" and game.blocked_keys.size() == 10)
	run.step(0)
	run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, true, false)
	game.sync_view()
	check("开始后独立跳跃进入生产表现", run.heights[0] > 0 and run.heights[1] == 0 and game.robots[0].position.y > game.robots[1].position.y)
	logical_key(KEY_ESCAPE)
	var frozen := var_to_str([run.a.position, run.b.position, run.heights, run.distance, run.elapsed, run.rope.contacts])
	run.step(0.25, Vector2.LEFT, Vector2.RIGHT, true, true)
	check("Esc入口冻结跳跃/位置/推进/接触", run.state == "paused" and frozen == var_to_str([run.a.position, run.b.position, run.heights, run.distance, run.elapsed, run.rope.contacts]))
	logical_key(KEY_ESCAPE, true)
	check("重复按键事件不恢复暂停", run.state == "paused")
	game.primary_action()
	check("继续按钮恢复并清理缓冲与旧输入", run.state == "running" and run.jump_buffer == [0, 0] and game.blocked_keys.size() == 10)
	logical_key(KEY_R)
	game.sync_view()
	check("R入口重试双人合法地面状态", run.heights == [0.0, 0.0] and run.coins == 0 and run.prizes == 0 and run.rope.contacts.is_empty() and run.a.position.distance_to(run.b.position) <= Run.LINK_LIMIT)
	run.fail_threat("集成验证失败夹具")
	game.sync_view()
	check("共同失败界面展示重试入口", game.title.text == "连接中断" and game.primary.visible)
	game.primary_action()
	check("失败按钮保留种子并计一次重试", run.state == "running" and run.failures == 1)
	# 迁移 t02 固定柱间隔与 t04 固定同侧整关契约。回放已保存的普通种子7路线，
	# 每一步使用当前生产物理和原始按键，逐步对比已有结果，不吸附或改写玩家位置。
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/short-rope-t05-result.json"))
	var campaign: Dictionary = saved.campaigns[4]
	run.streaming = true
	run.generation_enabled = true
	run.difficulty = campaign.difficulty
	run.seed_value = campaign.seed
	run.new_campaign()
	run.step(0)
	var camera_transform: Transform3D = game.camera.transform
	var peak_hazards := 0
	var peak_rewards := 0
	var seen_pillar := false
	var visible_pillar := false
	var summaries: Array = []
	for level in range(3):
		var record: Dictionary = campaign.levels[level]
		var valid := true
		var geometry := true
		var view_ok := true
		var fixed_camera := true
		var installed_kinds := {}
		for tick in range(record.inputs.size()):
			var input: Array = record.inputs[tick]
			valid = Keyboard.legal(input) and valid
			run.step(Run.FIXED_STEP, Vector2(input[0], input[1]), Vector2(input[2], input[3]), input[4], input[5])
			for kind in run.kinds: installed_kinds[kind] = true
			valid = valid and signature() == record.hashes[tick]
			geometry = geometry and run.rope.required <= Run.LINK_LIMIT + 0.01 and absf(run.a.position.x) <= Run.EDGE and absf(run.b.position.x) <= Run.EDGE and absf(run.a.position.y - run.distance) <= Run.RELATIVE_RANGE + 0.01 and absf(run.b.position.y - run.distance) <= Run.RELATIVE_RANGE + 0.01
			peak_hazards = maxi(peak_hazards, run.obstacles.size())
			peak_rewards = maxi(peak_rewards, run.rewards.size())
			seen_pillar = seen_pillar or run.kinds.has("pillar")
			if tick % 120 == 0 or run.state != "running":
				game.sync_view()
				view_ok = view_ok and game.hazard_views.size() == run.obstacles.size() and game.reward_views.size() == 24
				fixed_camera = fixed_camera and game.camera.transform.is_equal_approx(camera_transform)
				var index: int = run.kinds.find("pillar")
				if index >= 0: visible_pillar = visible_pillar or game.hazard_views[index].has_node("ContactRing")
		check("迁移整关%d：原始键盘与逐步状态哈希一致" % [level + 1], valid and run.state == "settlement")
		check("迁移整关%d：短绳/前后/横向边界及无护盾抵伤" % [level + 1], geometry and run.shield_uses == 0)
		check("迁移整关%d：共同终点/90至120秒/奖励" % [level + 1], run.progress() >= run.finish_distance() and run.elapsed >= 90 and run.elapsed <= 120 and run.coins >= 20 and run.prizes >= 3)
		check("迁移整关%d：池同步及固定镜头" % [level + 1], view_ok and fixed_camera and game.primary.visible == false)
		var content_ok := installed_kinds.has("pillar") and installed_kinds.has("stone_ball") and installed_kinds.has("fly_low")
		if level >= 1: content_ok = content_ok and installed_kinds.has("fly_body") and installed_kinds.has("iron_ball")
		check("迁移整关%d：实际安装关卡威胁覆盖" % [level + 1], content_ok)
		summaries.append({"level": level + 1, "seconds": run.elapsed, "coins": run.coins, "prizes": run.prizes, "rebases": run.rebases, "input_steps": record.inputs.size()})
		logical_key(KEY_R)
		logical_key(KEY_ESCAPE)
		check("结算%d屏蔽R与Esc" % [level + 1], run.state == "settlement" and run.level_index == level)
		run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, true, true)
		check("结算%d旧按住键不确认" % [level + 1], run.confirmations == [false, false])
		run.step(Run.FIXED_STEP)
		run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, true, false)
		game.sync_view()
		check("结算%d单人确认等待队友" % [level + 1], run.state == "settlement" and run.confirmations == [true, false] and game.subtitle.text.contains("已确认"))
		run.step(Run.FIXED_STEP, Vector2.ZERO, Vector2.ZERO, true, true)
		run.step(0)
		game.sync_view()
	check("迁移生成：高柱稳定编号/接触视图且活动对象有界", seen_pillar and visible_pillar and peak_hazards <= Run.Templates.MAX_HAZARDS and peak_rewards <= Run.Levels.MAX_REWARDS)
	check("三关总分与原记录一致并展示总成绩", run.state == "complete" and run.total_score() == campaign.score and game.title.text == "三关归航完成")
	var score: int = run.total_score()
	logical_key(KEY_R)
	check("完成页R不重领收益", run.state == "complete" and run.total_score() == score)
	game.primary_action()
	check("重新开始按钮清空三关成绩并保留双人入口", run.state == "running" and run.level_index == 0 and run.results.is_empty() and run.total_score() == 0 and game.blocked_keys.size() == 10)
	metrics = {"difficulty": campaign.difficulty, "seed": campaign.seed, "route_source": "tests/short-rope-t05-result.json campaigns[4]", "levels": summaries, "score": score, "peak_hazards": peak_hazards, "peak_rewards": peak_rewards}
	var failed := 0
	for entry in checks:
		if not entry.passed: failed += 1
	var file := FileAccess.open("res://tests/short-rope-t06-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failed": failed, "passed": failed == 0, "metrics": metrics, "controller_tests": [], "gui": "not_run_by_user_instruction", "real_input": "not_run", "user_playtest": "pending"}, "\t"))
	file.close()
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
