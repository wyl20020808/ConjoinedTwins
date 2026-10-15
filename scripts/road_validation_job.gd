extends RefCounted
# 同一生产验证器的可暂停固定步任务：后台线程和无线程 Web 共享全部断言与结果。
var rules
var block: Dictionary
var difficulty: String
var level: int
var build_chain: bool
var from_entrance := false
var done := false
var accepted := false
var tick := 0
var tick_limit := 0
var run
var source_state: Dictionary
var absolute_base: float
var source_shield_uses: int
var shield_collision: Dictionary
var reward_prefix: String
var expected_coins := 0
var expected_prizes := 0
var entry_sample := {}
var inputs: Array = []
var samples: Array = []
var warnings := {}
var jump_events: Array = []
var valid := true
var illegal_inputs := 0
var next_coin_y := 90.0
var coin_role := 0
var corridor: Array = []
var duration: float

func _init(templates, candidate: Dictionary, mode: String, stage: int, entrance: Dictionary, base: float, chain: bool) -> void:
	rules = templates
	block = candidate
	difficulty = mode
	level = stage
	build_chain = chain
	from_entrance = not entrance.is_empty()
	# 使用实际 road_run；仅关闭递归生成，仍执行生产流式回收、固定步、奖励与连续碰撞。
	if entrance.is_empty():
		run = load("res://scripts/road_run.gd").new(false)
		run.difficulty = difficulty
		run.level_index = level
		run.retry()
		run.a.position = Vector2(-25, 0)
		run.b.position = Vector2(25, 0)
		run.rope.reset(run.a.position, run.b.position)
		run.step(0)
	else: run = rules.clone_state(entrance)
	source_state = rules.capture_state(run)
	absolute_base = base + run.world_origin
	if not rules.combination_allowed(block):
		rules.last_evidence = {"accepted": false, "reason": "禁区组合", "exit": rules.snapshot(run, 0), "source_entry": source_state, "source_entry_hash": var_to_str(source_state).sha256_text(), "source_binding": rules.binding(), "layout_hash": var_to_str(block).sha256_text(), "base": absolute_base}
		run.dispose()
		done = true
		run = null
		return
	source_shield_uses = run.shield_uses
	shield_collision = {}
	reward_prefix = "certificate:%d" % run.next_obstacle_id
	if build_chain:
		block.rewards = block.rewards.filter(func(reward): return reward.kind != "coin")
		block.coin_chain = "生产安全足点在线建链；实际领取；金币仅计分，不改变物理或路线输入"
	run.install_block(block, base, reward_prefix)
	expected_coins = 0
	expected_prizes = 0
	for reward in block.rewards:
		if reward.kind == "coin": expected_coins += 1
		if reward.kind == "prize": expected_prizes += 1
	entry_sample = {}
	inputs = []
	samples = []
	warnings = {}
	jump_events = []
	valid = true
	illegal_inputs = 0
	next_coin_y = 90.0
	coin_role = 0
	# 本段实际走过的双人位置（段内局部坐标），供之后在路线外散布陷阱。
	corridor = []
	duration = maxf(0.0, absolute_base + rules.SEGMENT - run.total_distance())
	# 预算包含每个预加载机关的充能及调整；不改变生产固定步。
	tick_limit = int(ceil(duration / run.speed() / run.FIXED_STEP)) + 180 + 240 * run.charge_gates.size() + int(ceil(block.get("wait_budget",0.0)/run.FIXED_STEP))

func _advance_one() -> void:
	if rules.canceled():
		rules.last_evidence = {"accepted": false, "reason": "后台验证已取消", "exit": rules.snapshot(run, tick), "source_entry_hash": var_to_str(source_state).sha256_text()}
		run.dispose()
		done = true
		run = null
		return
	var in_block: bool = run.total_distance() >= absolute_base
	if in_block and entry_sample.is_empty(): entry_sample = rules.snapshot(run, tick)
	var input: Array = rules.route_input(run, block, absolute_base - run.world_origin) if in_block else rules.existing_route_input(run)
	if not rules.keyboard_legal(input[0]) or not rules.keyboard_legal(input[1]): illegal_inputs += 1
	inputs.append([input[0].x, input[0].y, input[1].x, input[1].y, input[2], input[3]])
	var before_jump: Array = run.heights.duplicate()
	var local_y: float = run.total_distance() - absolute_base
	if build_chain and local_y >= next_coin_y and local_y < 800 and run.heights[coin_role] == 0 and run.ground_support[coin_role]:
		var point: Vector2 = run.a.position if coin_role == 0 else run.b.position
		var reward := {"kind": "coin", "position": Vector2(point.x, point.y + run.world_origin - absolute_base), "radius": 20.0}
		var entry: Dictionary = reward.duplicate(true)
		entry.position = point
		entry.id = "%s:%d" % [reward_prefix, block.rewards.size()]
		entry.claimed = false
		run.rewards.append(entry)
		block.rewards.append(reward)
		expected_coins += 1
		next_coin_y = local_y + 90.0
		coin_role = 1 - coin_role
	run.step(run.FIXED_STEP, input[0], input[1], input[2], input[3])
	if run.shield_uses > source_shield_uses and shield_collision.is_empty():
		shield_collision = {"tick": tick, "local_y": local_y, "events": run.absorbed_events.duplicate(true), "state": rules.snapshot(run, tick)}
	if in_block: corridor.append([Vector2(run.a.position.x, run.a.position.y + run.world_origin - absolute_base), Vector2(run.b.position.x, run.b.position.y + run.world_origin - absolute_base)])
	for role in range(2):
		if (before_jump[role] == 0 and run.heights[role] > 0) or (before_jump[role] > 0 and run.heights[role] == 0):
			var point: Vector2 = run.a.position if role == 0 else run.b.position
			jump_events.append({"tick": tick, "role": role + 1, "event": "起跳" if run.heights[role] > 0 else "落地", "position": [point.x, point.y], "support": run.ground_support[role], "rope_heights": Array(run.rope.path_heights())})
	valid = valid and run.rope.required <= run.LINK_LIMIT + 0.01 and run.shield_uses == source_shield_uses
	for i in range(run.hazard_specs.size()):
		var spec: Dictionary = run.hazard_specs[i]
		if spec.get("extra", false): continue
		if spec.get("locked", false) or (spec.get("industrial", false) and run.kinds[i] != "collapse" and spec.trigger >= 0): warnings[str(run.obstacle_ids[i])] = spec.warning_evidence.duplicate(true)
	if tick % 30 == 0: samples.append(rules.snapshot(run, tick))
	if run.state != "running" or run.total_distance() >= absolute_base + rules.SEGMENT:
		_finish()
		return
	tick += 1
	if tick >= tick_limit: _finish()

func _finish() -> void:
	var claimed_coins := 0
	var claimed_prizes := 0
	for slot in range(block.rewards.size()):
		if not run.claimed_rewards.has("%s:%d" % [reward_prefix, slot]): continue
		if block.rewards[slot].kind == "coin": claimed_coins += 1
		if block.rewards[slot].kind == "prize": claimed_prizes += 1
	var all_rewards: bool = claimed_coins == expected_coins and claimed_prizes == expected_prizes
	for reward in block.rewards:
		if reward.kind == "shield": all_rewards = all_rewards and run.shield
	var warning_ok := true
	for evidence in warnings.values():
		if evidence.has("earliest_approach"):
			warning_ok = warning_ok and evidence.reaction_margin >= 0.35 - 0.025
		else:
			warning_ok = warning_ok and evidence.ttc >= evidence.joint_change_time + 0.35 - 0.025 and evidence.ttc >= rules.DIFFICULTIES[difficulty].front_warning - 0.025
	var exit_ok: bool = absf(run.a.position.x + 25) <= rules.EXIT_TOLERANCE and absf(run.b.position.x - 25) <= rules.EXIT_TOLERANCE and absf(run.a.position.y - run.distance) <= rules.EXIT_TOLERANCE and absf(run.b.position.y - run.distance) <= rules.EXIT_TOLERANCE and run.rope.contacts.is_empty() and run.heights == [0.0, 0.0]
	valid = valid and illegal_inputs == 0 and run.state == "running" and run.total_distance() >= absolute_base + rules.SEGMENT and all_rewards and exit_ok and warning_ok
	rules.last_evidence = {"accepted": valid, "reason": run.reason if run.state != "running" else ("奖励未全部可达" if not all_rewards else ("段尾状态不兼容" if not exit_ok else ("预警不足" if not warning_ok else "生产回放"))), "route": block.route, "difficulty": difficulty, "level": level, "inputs": inputs, "samples": samples, "warnings": warnings, "exit": rules.snapshot(run, inputs.size()), "coins": run.coins, "prizes": run.prizes, "shield_uses": run.shield_uses}
	rules.last_evidence.input_encoding = "原始键盘轴值：01横/纵、02横/纵各为-1/0/1；空格、回车按下状态"
	rules.last_evidence.illegal_inputs = illegal_inputs
	rules.last_evidence.exit_tolerance = rules.EXIT_TOLERANCE
	rules.last_evidence.jump_events = jump_events
	rules.last_evidence.source_entry_hash = var_to_str(source_state).sha256_text()
	rules.last_evidence.source_entry = source_state
	rules.last_evidence.predicted_entry = entry_sample
	rules.last_evidence.source_binding = rules.binding()
	rules.last_evidence.base = absolute_base
	rules.last_evidence.entry_mode = "生产预加载状态连续预测" if from_entrance else "历史中心夹具"
	rules.last_evidence.expected_rewards = [expected_coins, expected_prizes]
	rules.last_evidence.claimed_block_rewards = [claimed_coins, claimed_prizes]
	rules.last_evidence.speed = run.speed()
	rules.last_evidence.layout_hash = var_to_str(block).sha256_text()
	rules.last_evidence.support_rule = "实际固定步角色地面支撑；绳索不承重；连续扫掠"
	rules.last_evidence.shield_uses_before = source_shield_uses
	rules.last_evidence.shield_uses_after = run.shield_uses
	rules.last_evidence.shield_collision = shield_collision
	rules.last_evidence.corridor = corridor
	if illegal_inputs > 0: rules.last_evidence.reason = "非生产键盘输入"
	run.dispose()
	run = null
	accepted = valid
	done = true

func advance(steps: int) -> void:
	for index in range(steps):
		if done: return
		_advance_one()

func dispose() -> void:
	if run != null:
		run.dispose()
		run = null
	done = true
