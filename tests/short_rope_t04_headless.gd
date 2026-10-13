extends SceneTree

const Run = preload("res://scripts/road_run.gd")
const DT := 1.0 / 120.0
var checks: Array = []
var metrics := {}
var game
var r

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)

func empty_fixture() -> void:
	r.streaming = false
	r.state = "running"
	r.obstacles.clear()
	r.kinds.clear()
	r.obstacle_heights.clear()
	r.hazard_specs.clear()
	r.obstacle_ids.clear()
	r.level_index = 0
	r.results.clear()
	r.retry()
	r.step(0)

func reward(id: String, kind: String, point: Vector2, radius: float = 44, staggered: bool = false) -> Dictionary:
	return {"id": id, "kind": kind, "position": point, "radius": radius, "staggered": staggered, "claimed": false}

func verify() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.capture_mode = true
	r = game.run
	empty_fixture()
	r.rewards.assign([reward("coin", "coin", Vector2.ZERO), reward("prize", "prize", Vector2.ZERO), reward("shield", "shield", Vector2.ZERO)])
	for tick in range(12): r.step(DT)
	check("同时接触及跨帧每个实例仅领取一次", r.coins == 1 and r.prizes == 1 and r.shield and r.claimed_rewards.size() == 3)
	r.rewards.clear()
	r.rewards.append(reward("coin", "coin", r.a.position))
	r.step(DT)
	check("回收槽复用相同实例不能重复领取", r.coins == 1 and r.rewards[0].claimed)
	r.rewards.assign([reward("next-coin", "coin", r.a.position), reward("next-shield", "shield", r.a.position)])
	r.step(DT)
	check("新实例可领取，满盾不叠加", r.coins == 2 and r.shield and not r.rewards[1].claimed)
	var before_time: float = r.elapsed
	r.pause()
	var before_rewards: Array = r.rewards.duplicate(true)
	r.step(0.25)
	check("暂停冻结奖励和计时", r.elapsed == before_time and r.rewards == before_rewards)
	r.pause()
	check("首次稳定事件吸收角色伤害", not r.damage("event-1", "hit") and not r.shield and r.shield_uses == 1 and r.state == "running")
	var immunity: float = r.invulnerable_until - r.elapsed
	r.pause()
	r.step(0.25)
	r.pause()
	check("暂停不消耗无敌剩余时间", is_equal_approx(r.invulnerable_until - r.elapsed, immunity))
	r.damage("event-1", "hit")
	r.damage("event-2", "hit")
	check("同事件和同时第二角色不重复消耗", r.shield_uses == 1 and r.state == "running")
	r.rewards.clear()
	for tick in range(119): r.step(DT)
	check("无敌持续不到一秒仍有效", r.elapsed < r.invulnerable_until and not r.damage("event-3", "hit"))
	for tick in range(2): r.step(DT)
	r.shield = true
	check("无敌到期同一事件不再次消耗护盾且正常失败", r.damage("event-1", "hit") and r.state == "failed" and r.shield and r.shield_uses == 1)
	r.retry(true)
	check("失败重试清空当前关收益/免伤/事件/输入", r.coins == 0 and r.prizes == 0 and not r.shield and r.absorbed_events.is_empty() and r.invulnerable_until == 0 and r.jump_buffer == [0, 0] and r.rope.contacts.is_empty())
	empty_fixture()
	r.a.position = Vector2(-5, 100)
	r.b.position = Vector2(5, 160)
	r.rewards.assign([reward("stagger", "prize", Vector2(0, 130), 26, true)])
	r.collect_rewards(r.a.position, r.b.position)
	check("前后合作奖品双方不同站位领取", r.prizes == 1)
	empty_fixture()
	r.a.position = Vector2(-42, 0)
	r.b.position = Vector2(160, 0)
	r.rewards.assign([reward("joint", "prize", r.a.position)])
	r.collect_rewards(r.a.position, r.b.position)
	check("合作奖品单人不能领取", r.prizes == 0)
	# 生产危险碰撞，而非仅调用免伤函数。
	empty_fixture()
	r.shield = true
	r.obstacles.assign([Rect2(-65, 30, 46, 12)])
	r.kinds.assign(["spikes"])
	r.obstacle_heights.assign([10.0])
	r.hazard_specs.assign([{}])
	for tick in range(120): r.step(DT)
	check("真实角色危险消耗一次护盾后继续运行", r.state == "running" and r.shield_uses == 1 and not r.shield)
	empty_fixture()
	r.shield = true
	r.obstacles.assign([Rect2(-12, 20, 24, 24)])
	r.kinds.assign(["pillar"])
	r.obstacle_heights.assign([100.0])
	r.hazard_specs.assign([{}])
	for tick in range(700): r.step(DT)
	check("团队护盾不解除分侧绕柱失败", r.state == "failed" and r.rope_failed and r.shield and r.shield_uses == 0)
	empty_fixture()
	r.shield = true
	r.obstacles.assign([Rect2(-65, 24, 46, 60)])
	r.kinds.assign(["cargo"])
	r.obstacle_heights.assign([60.0])
	r.hazard_specs.assign([{}])
	for tick in range(100): r.step(DT)
	check("护盾期间不穿过高货箱", r.shield_uses == 1 and r.a.position.y < 12.01)
	empty_fixture()
	r.shield = true
	r.obstacles.assign([Rect2(-45, 175, 90, 90)])
	r.kinds.assign(["stone_ball"])
	r.obstacle_heights.assign([90.0])
	r.hazard_specs.assign([Run.Threats.spec("stone_ball", 2)])
	r.a.position.x = -65
	r.b.position.x = 65
	r.rope.reset(r.a.position, r.b.position)
	for tick in range(720): r.step(DT)
	check("护盾不解除滚球带绳约束耗尽", r.state == "failed" and r.rope_failed and r.shield and r.shield_uses == 0)
	# 共同终点与确认边沿。
	empty_fixture()
	r.coins = 7
	r.prizes = 2
	r.a.position.y = r.finish_distance()
	r.b.position.y = r.finish_distance() - 1
	r.check_finish()
	check("只有单人到达不会通关", r.state == "running" and r.results.is_empty())
	r.b.position.y += 1
	r.check_finish()
	r.check_finish()
	check("双方到达只结算一次且评分准确", r.state == "settlement" and r.results.size() == 1 and r.total_score() == 270)
	check("结算清除活动危险奖励接触与免伤", r.obstacles.is_empty() and r.rewards.is_empty() and r.rope.contacts.is_empty() and not r.shield and r.invulnerable_until == 0)
	r.step(DT, Vector2.ZERO, Vector2.ZERO, true, true)
	check("旧按住的跳跃键不能确认下一关", r.level_index == 0 and r.confirmations == [false, false])
	r.step(DT)
	r.step(DT, Vector2.ZERO, Vector2.ZERO, true, false)
	check("仅01确认不能跨关", r.level_index == 0 and r.confirmations == [true, false])
	r.retry()
	check("结算不能重试刷分", r.state == "settlement" and r.total_score() == 270)
	r.step(DT, Vector2.ZERO, Vector2.ZERO, true, true)
	check("两人分别确认才进入下一关并清理本关状态", r.level_index == 1 and r.state == "running" and r.coins == 0 and r.prizes == 0 and r.results.size() == 1 and r.confirmations == [false, false] and r.rope.contacts.is_empty())
	r.coins = 3
	r.fail_threat("测试失败")
	r.retry(true)
	check("后续关失败保留关号种子和已完成总分", r.level_index == 1 and r.total_score() == 270 and r.coins == 0)
	# 三关完整真实生产输入，不跳过推进、生成、危险和回收。
	for difficulty in ["简单", "普通", "困难"]:
		r.streaming = true
		r.seed_value = 20261013
		r.set_difficulty(difficulty)
		r.retry()
		var peak_rewards := 0
		var peak_hazards := 0
		var times: Array = []
		var routes: Array = []
		for level in range(3):
			var side: float = Run.Levels.safe_side(r.seed_value, level)
			var lane: float = side * 154
			var path_samples: Array = []
			var input_changes: Array = []
			var last_input: Array = []
			var route_valid := true
			for tick in range(15000):
				var first := Vector2(clampf((lane - 25 - r.a.position.x) / (Run.LATERAL * DT), -1, 1), 0)
				var second := Vector2(clampf((lane + 25 - r.b.position.x) / (Run.LATERAL * DT), -1, 1), 0)
				# 第三关奖品的前后站位；在安全同侧路径上由真实输入调节。
				if level == 2:
					for entry in r.rewards:
						if entry.kind == "prize" and not entry.claimed and absf(entry.position.y - r.distance) < 90:
							first.y = clampf((entry.position.y + 30 - r.a.position.y - r.speed() * DT) / (Run.LATERAL * DT), -1, 1)
							second.y = clampf((entry.position.y - 30 - r.b.position.y - r.speed() * DT) / (Run.LATERAL * DT), -1, 1)
							break
				var input: Array = [first.x, first.y, second.x, second.y]
				if input != last_input:
					input_changes.append({"tick": tick, "input": input})
					last_input = input
				r.step(DT, first, second)
				route_valid = route_valid and r.rope.required <= Run.LINK_LIMIT + 0.01 and absf(r.a.position.x) <= Run.EDGE and absf(r.b.position.x) <= Run.EDGE
				peak_rewards = maxi(peak_rewards, r.rewards.size())
				peak_hazards = maxi(peak_hazards, r.obstacles.size())
				if tick % 120 == 0: path_samples.append({"tick": tick, "a": [r.a.position.x, r.a.position.y], "b": [r.b.position.x, r.b.position.y], "height": r.heights.duplicate(), "origin": r.world_origin, "rope": r.rope.required, "contacts": r.rope.touching()})
				if r.state != "running": break
			check("%s 第%d关生产双人路线通关" % [difficulty, level + 1], r.state == "settlement")
			check("%s 第%d关目标时长及共同终点" % [difficulty, level + 1], r.elapsed >= 90 and r.elapsed <= 120 and r.progress() >= r.finish_distance())
			check("%s 第%d关奖励可达且资源有界" % [difficulty, level + 1], r.coins > 20 and r.prizes >= 3 and peak_rewards <= Run.Levels.MAX_REWARDS and peak_hazards <= Run.Templates.MAX_HAZARDS)
			check("%s 第%d关实际输入全程短绳及横向合法" % [difficulty, level + 1], route_valid)
			times.append(r.elapsed)
			routes.append({"positions": path_samples, "input_changes": input_changes, "fixed_step": DT})
			game.sync_view()
			if r.state != "settlement": break
			r.step(DT)
			r.step(DT, Vector2.ZERO, Vector2.ZERO, true, true)
		var expected := 0
		for result in r.results: expected += result.coins * 10 + result.prizes * 100
		check(difficulty + "三关总成绩准确且完成冻结", r.state == "complete" and r.results.size() == 3 and r.total_score() == expected)
		var frozen := [r.elapsed, r.distance, r.coins, r.total_score()]
		r.step(0.25, Vector2.ONE, Vector2.ONE, true, true)
		check(difficulty + "完成状态停止全部推进", frozen == [r.elapsed, r.distance, r.coins, r.total_score()])
		metrics[difficulty] = {"seconds": times, "score": r.total_score(), "peak_rewards": peak_rewards, "peak_hazards": peak_hazards, "routes": routes}
		game.sync_view()
		check(difficulty + "界面展示三关总成绩及固定奖励池", game.title.text == "三关归航完成" and game.reward_views.size() == Run.Levels.MAX_REWARDS)
	# 流式重试复现：对象稳定编号和位置一致，当前关收益恢复到零。
	r.new_campaign()
	var layout: Array = r.rewards.duplicate(true)
	var shapes: Array = r.obstacles.duplicate()
	var seed_before: int = r.seed_value
	r.coins = 8
	r.prizes = 1
	r.shield = true
	r.claimed_rewards[layout[0].id] = true
	r.fail_threat("测试失败")
	r.retry(true)
	check("流式重试相同种子布局编号且不能累计刷收益", r.seed_value == seed_before and r.rewards == layout and r.obstacles == shapes and r.coins == 0 and r.prizes == 0 and not r.shield)
	game.sync_view()
	check("重试同步显示奖励及终点", game.reward_views[0].visible and game.finish_view.position.z == -r.finish_distance() / game.SCALE)
	var failed := 0
	for entry in checks:
		if not entry.passed: failed += 1
	var report := {"passed": failed == 0, "checks": checks, "failed": failed, "metrics": metrics, "executor_self_test": true, "controller_tests": [], "gui": "not_run", "user_playtest": "pending"}
	var file := FileAccess.open("res://tests/short-rope-t04-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	game.queue_free()
	quit(0 if failed == 0 else 1)
