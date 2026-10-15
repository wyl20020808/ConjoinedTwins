extends RefCounted

# 20 地面单位为一米；双方使用同一个固定步、连接和高度判定。
const Motion = preload("res://scripts/link_motion.gd")
const Templates = preload("res://scripts/road_templates.gd")
const Rope = preload("res://scripts/rope_solver.gd")
const Levels = preload("res://scripts/road_levels.gd")
const Threats = preload("res://scripts/dynamic_threats.gd")
const Surfaces = preload("res://scripts/road_surfaces.gd")
const Industrial = preload("res://scripts/industrial_obstacles.gd")
const ChargeGate = preload("res://scripts/road_charge_gate.gd")
const SyncPlates = preload("res://scripts/road_sync_plates.gd")
const FINISH := 9000.0
const FORWARD := 120.0
const LATERAL := Templates.MANUAL_SPEED
# 山脊路面半宽 16 米（加宽后绳长约为路宽的四分之一，分开绕行时会被绳索拉住）。
# 两侧没有护栏：角色中心越过 EDGE 即失去支撑坠崖，最多走出 FALL_REACH。须与 Templates.ROAD_HALF_WIDTH 一致。
const EDGE := Templates.ROAD_HALF_WIDTH
const FALL_REACH := 30.0
# 两人身体互不穿透：中心间距不得小于两倍碰撞半径，窄桥上只能前后单列通过。
const BODY_GAP := 24.0
# 坠落救援（试玩初值）：一人踩空而队友稳稳站在地面时，坠落者挂在绳上，世界冻结。
# 救援者连按自己的跳跃键拉人，坠落者连按效果减半；进度持续回落，限时内拉满即救起，否则共同坠落。
# RESCUE_RATES 是恰好在限时内拉满所需的救援者按键频率（次/秒）；同关每多救一次提高 RESCUE_ESCALATION 倍。
const RESCUE_TIME := 3.0
const RESCUE_DECAY := 0.4
const RESCUE_CLIMB := 0.5
const RESCUE_RATES := {"简单": 4.0, "普通": 5.5, "困难": 7.0}
const RESCUE_ESCALATION := 1.15
const RESCUE_INVULNERABLE := 1.0
const RESCUE_CLIMB_TIME := 0.6
# 窄桥上横向速度倍率，以及松手后回正桥中线的最大横向输入。
const PLANK_LATERAL := 0.35
const PLANK_CENTERING := 0.25
const FIXED_STEP := Templates.FIXED_STEP
# 生产道路专用配置（试玩初值）；历史白盒继续使用 link_motion.gd 的 LIMIT，此处不改共用常量。
# 绳长 7.33 米、前后各 ±5 米、跳跃初速 12 米/秒、重力 40 米/秒²：最高 1.8 米、0.30 秒到顶、0.60 秒腾空。
const LINK_LIMIT := 146.6
const RELATIVE_RANGE := 100.0
# 巨岩不伤人，只是实心阻挡：被它挡住的人可落到后边界之后，落后超过 7 米即被挤出画面下沿。
const SQUEEZE_LIMIT := 140.0
const JUMP_SPEED := 240.0
const GRAVITY := 800.0
const JUMP_APEX := JUMP_SPEED * JUMP_SPEED / (2.0 * GRAVITY)
# 起跳输入缓冲 0.10 秒：按下后 12 个固定步内落地即起跳，过期作废。
const JUMP_BUFFER := 0.10
const JUMP_BUFFER_STEPS := 12
const BODY_HEIGHT := 58.0
# 危险顶部/底部高度；须绕行的高货箱必须高于 JUMP_APEX，不随跳跃提高变成可越过对象。
const HAZARD_TOPS := {"pillar": 100.0, "cargo": 60.0, "rail": 12.0, "spikes": 10.0, "active_spikes": 16.0, "scanner": 50.0, "fly_low": 10.0, "fly_body": 38.0, "fly_tall": 85.0}
# 复合几何和地面支撑不属于上述九类单盒高度契约，分别由 Surfaces 检测。
const SURFACE_TOPS := {"sweeper": Surfaces.POST_TOP, "road_gap": 0.0, "drone": 48.0, "forklift": 92.0, "press": 130.0, "hammer": 136.0, "collapse": 0.0, "steam": 100.0}
const HAZARD_BOTTOMS := {"scanner": 26.0, "fly_body": 18.0}
# 绳索（试玩初值）：挂点离脚底 1.4 米，随各自跳跃高度抬升；圆柱类障碍会挂住绳索。
# 有效长度按地面绕障路径计算，提交后的长度不超过 LINK_LIMIT + ROPE_LENGTH_TOLERANCE。
# 这是固定硬约束，没有例外：绳段腾空越过矮障碍时，求解模块按“此刻落下会被挂住”的路径计约束长度，
# 位移在腾空期间就受它限制，落下时不会出现超长。
const ROPE_BLOCKERS := ["pillar", "stone_ball", "iron_ball"]
# 位置固定、只伤身体的陷阱（绳索不受其影响）。高柱虽然固定，但会挂住绳索，所以不在其中。
const STATIC_KINDS := ["cargo", "spikes", "active_spikes", "rail"]
const ROPE_HEIGHT := 28.0
const ROPE_CLEARANCE := 1.0
const ROPE_LENGTH_TOLERANCE := 0.01
# 绕柱受阻：自动推进一个子步就会让绕障路径超出绳长（绳索压在障碍上，或再前进就压上），累计 0.8 秒共同失败。
# 缠绕角以不低于 ROPE_UNWIND_RATE 的速度减小视为正在解围，期间不累计；接触完全解除才清零。
const ROPE_BLOCK_LIMIT := 0.8
const ROPE_BLOCK_SUBSTEPS := 288
const ROPE_UNWIND_RATE := 0.3
# 受阻期间自动推进停滞，解围后在这段时间内线性恢复到全速，不把刚绕回的角色推向柱子。
const ROPE_RESUME_TIME := 0.5
# 后台生成提前四段（168 米）铺好，远处障碍提前可见；距入口不足 1 秒仍未证完则让出空段。
const ASYNC_AHEAD := 3360.0
const LATE_MARGIN := 1.0
# 联机帧同步：后台证明在道路推进到固定位置时才安装（必要时等待线程），两台设备安装时机一致。
const LOCKSTEP_LEAD := ASYNC_AHEAD - Templates.SEGMENT
# 存档点（试玩初值）：每到一个段落入口，两人贴地站稳、绳未挂障碍且直行走廊内没有危险时保存完整快照。
# 后方留 4 米、前方留 1 秒关速路程（另加身体半径与 1.5 米余量）、两侧各留 1.5 米；移动危险（迎面物、飞行物）不限左右，前方再多看 1.5 秒。
const CHECKPOINT_CLEAR_BEHIND := 80.0
const CHECKPOINT_CLEAR_AHEAD := 1.0
const CHECKPOINT_SIDE_MARGIN := 30.0
const CHECKPOINT_MOVING_AHEAD := 1.5
# 快照不保存的属性：对象句柄单独保存；跨存档累计的统计、运行模式和生成调度不随恢复回退。
const CHECKPOINT_EXCLUDED := ["a", "b", "rope", "generator", "checkpoint", "checkpoint_line", "checkpoint_restores",
	"cooperative_job", "block_history", "failures", "results", "revision", "proven_blocks", "lockstep", "random_seed", "streaming",
	"generation_enabled", "async_enabled", "charge_tutorial"]
# 已证明布局按候选内容缓存，只在主线程读写；重试同种子时直接复用。
static var proven_blocks := {}
var a := Node2D.new()
var b := Node2D.new()
var state := "start"
var elapsed := 0.0
var distance := 0.0
var failures := 0
var obstacles: Array[Rect2] = []
var kinds: Array[String] = []
var obstacle_heights: Array[float] = []
# 障碍的稳定标识：回收与重定位会改变列表下标，绳索接触按标识保存。
var obstacle_ids: Array[int] = []
var next_obstacle_id := 1
var rope = Rope.new()
var rope_bound := false
var rope_unwinding := false
var rope_block_substeps := 0
var rope_resume := 1.0
var rope_failed := false
var hazard_specs: Array[Dictionary] = []
var actions := ["Idle", "Idle"]
var land_time := [0.0, 0.0]
var move_directions := [Vector2.ZERO, Vector2.ZERO]
var heights := [0.0, 0.0]
var vertical_speed := [0.0, 0.0]
var jump_held := [true, true]
var jump_buffer := [0, 0]
var reason := ""
var clear_input := true
var accumulator := 0.0
var generator = Templates.new()
var seed_value := 20261012
var random_seed := false
var difficulty := "普通"
var world_origin := 0.0
var next_segment := 0
var revision := 0
var recycled := 0
var rebases := 0
var streaming := true
var generation_enabled := true
var generation_halted := false
var async_enabled := false
var async_thread: Thread = null
var cooperative_job = null
const GENERATION_STEPS_PER_POLL := 32
var async_cancel = null
var async_job := {}
var async_epoch := 0
var async_events: Array = []
var async_peak_poll_usec := 0
# 教学期间只证明、不安装。影子抽签器不消耗正式对局的随机序列。
const STREAM_PRELOAD_SEGMENTS := 4
const PRELOAD_SLICE_USEC := 2000
var async_startup_pending := false
var async_preload_started := false
var async_preload_cursor := -1
var async_nonblocking := false
var async_prepare_waits := 0
var async_preload_requests := {}
var async_preload_tasks := {}
var async_preload_order: Array = []
var async_deadline_steps := 0
var async_preload_peak_usec := 0
var route_segments: Array[Dictionary] = []
var level_index := 0
var rewards: Array[Dictionary] = []
var claimed_rewards := {}
var coins := 0
var prizes := 0
var shield := false
var invulnerable_until := 0.0
var absorbed_events := {}
var shield_uses := 0
var results: Array[Dictionary] = []
var confirmations := [false, false]
var confirmation_held := [true, true]
var ground_support := [true, true]
# 本次失败中先坠落的角色；队友被连线拖下去，仅供表现使用。
var fallen := [false, false]
# 进行中的救援（空字典表示没有）；last_support 为各角色最近一次有地面支撑的位置，救起后回到这里。
var rescue := {}
var rescue_count := 0
# 被救起者救起前按着的方向键须先松开才生效，防止救上来立刻又走回坑里。
var move_lock := [false, false]
const MOVE_LOCK_TIME := 0.6
var move_lock_until := 0.0
var last_support := [Vector2.ZERO, Vector2.ZERO]
var paused_from := "running"
# 联机模式：不读缓存、不按线程快慢安装、种子由上一个种子确定性推导，保证两端模拟逐帧一致。
var lockstep := false
var charge_tutorial := false
var charge_gate: Dictionary = {"active": false, "open": false, "charge": 0.0}
var charge_gates: Array[Dictionary] = []
var gate_events: Array[Dictionary] = []
# 最近一次存档点快照（空字典表示本关尚无存档）；checkpoint_line 为下一次尝试存档的进度线。
var checkpoint := {}
var checkpoint_line := 0.0
var checkpoint_restores := 0
# 本关已安装的段落按段号保存；从存档恢复后重新到达这些段时原样安装，不重新抽签，布局不会刷新。
var block_history := {}

# 联机两端定期比对的状态指纹；不一致说明两台设备的模拟已经分叉。
func sync_hash() -> int:
	return var_to_str([state, a.position, b.position, heights, vertical_speed, distance, world_origin, elapsed,
		coins, prizes, shield, level_index, next_segment, seed_value, obstacles.size(), rope.length, charge_gate,
		charge_gates, gate_events, claimed_rewards, checkpoint_line, checkpoint_restores, rescue, rescue_count, move_lock, move_lock_until]).hash()

func level_speed() -> float:
	return Templates.DIFFICULTIES[difficulty].speed * Levels.LEVELS[level_index].speed_scale

func finish_distance() -> float:
	return level_speed() * Levels.LEVELS[level_index].seconds

func total_score() -> int:
	var result := 0
	for entry in results: result += entry.score
	return result

func new_campaign() -> void:
	level_index = 0
	results.clear()
	failures = 0
	state = "start"
	retry()

func confirm_step(first: bool, second: bool) -> void:
	if state != "settlement": return
	var pressed := [first, second]
	for i in range(2):
		if pressed[i] and not confirmation_held[i]: confirmations[i] = true
		confirmation_held[i] = pressed[i]
	if confirmations[0] and confirmations[1]:
		if level_index == Levels.LEVELS.size() - 1:
			state = "complete"
			reset_input()
		else:
			level_index += 1
			state = "running"
			retry()

func check_finish() -> void:
	if state != "running" or progress() < finish_distance(): return
	cancel_generation()
	var score := coins * 10 + prizes * 100
	var rating := "默契" if prizes >= 3 and coins >= 20 else ("协作" if prizes > 0 else "抵达")
	results.append({"level": level_index + 1, "coins": coins, "prizes": prizes, "score": score, "rating": rating, "seconds": elapsed, "seed": seed_value})
	state = "settlement"
	confirmations = [false, false]
	confirmation_held = [true, true]
	# 结算只保留成绩快照。活动对象和接触立即退出，避免旧事件跨关生效。
	obstacles.clear()
	kinds.clear()
	obstacle_heights.clear()
	obstacle_ids.clear()
	hazard_specs.clear()
	rewards.clear()
	absorbed_events.clear()
	invulnerable_until = 0.0
	shield = false
	rope.reset(a.position, b.position)
	rope_bound = false
	rope_unwinding = false
	rope_block_substeps = 0
	revision += 1
	charge_gate.active = false
	reset_input()

# 事件号由稳定障碍标识与周期组成。护盾吸收后同一事件不能再次消耗另一护盾；
# 无敌到期仍留在危险中会正常失败，不将去重变成永久免伤。
func damage(event_id: String, message: String) -> bool:
	if elapsed < invulnerable_until: return false
	if shield and not absorbed_events.has(event_id):
		shield = false
		shield_uses += 1
		absorbed_events[event_id] = true
		invulnerable_until = elapsed + Levels.INVULNERABILITY
		return false
	fail_threat(message)
	return true

func collision_event(index: int) -> String:
	var spec: Dictionary = hazard_specs[index]
	var cycle := int(floor((elapsed + spec.get("phase", 0.0)) / spec.get("period", 4.0))) if kinds[index] in ["active_spikes", "scanner"] else 0
	return "%d:%d" % [obstacle_ids[index], cycle]

func collect_rewards(pa: Vector2, pb: Vector2) -> void:
	for reward in rewards:
		if claimed_rewards.has(reward.id): reward.claimed = true
		if reward.claimed: continue
		var center: Vector2 = reward.position
		var hit_a: bool = Rope.segment_distance(pa, a.position, center) <= reward.radius + Motion.RADIUS
		var hit_b: bool = Rope.segment_distance(pb, b.position, center) <= reward.radius + Motion.RADIUS
		if reward.kind == "prize":
			# 合作奖品要求同一固定子步双方到位；前后奖品允许交换两个站位。
			if reward.get("staggered", false):
				var front := center + Vector2(0, 30)
				var back := center - Vector2(0, 30)
				var radius: float = reward.radius + Motion.RADIUS
				# 光圈采用“角色中心进入”判据，半径最多为站距的一半减去安全间隙。
				# 不额外叠加角色半径，否则两圈会重叠，同点也能领取。
				radius = minf(reward.radius, Levels.PRIZE_SOCKET_MAX_RADIUS)
				if not ((a.position.distance_to(front) <= radius and b.position.distance_to(back) <= radius) or (b.position.distance_to(front) <= radius and a.position.distance_to(back) <= radius)): continue
			elif not (a.position.distance_to(center) <= reward.radius + Motion.RADIUS and b.position.distance_to(center) <= reward.radius + Motion.RADIUS): continue
		elif not hit_a and not hit_b: continue
		if reward.kind == "shield" and shield: continue
		reward.claimed = true
		claimed_rewards[reward.id] = true
		match reward.kind:
			"coin": coins += 1
			"prize": prizes += 1
			"shield": shield = true

func speed() -> float:
	return level_speed()

func total_distance() -> float:
	return world_origin + distance

func set_difficulty(value: String) -> void:
	if Templates.DIFFICULTIES.has(value):
		difficulty = value
		new_campaign()
		state = "start"

func _init(generate: bool = true, background_generation: bool = false) -> void:
	generation_enabled = generate
	async_enabled = background_generation
	retry()
	state = "start"

func dispose() -> void:
	cancel_generation()
	a.free()
	b.free()

func cancel_generation() -> void:
	async_startup_pending = false
	for task in async_preload_tasks.values(): task.dispose()
	async_preload_tasks.clear()
	async_preload_requests.clear()
	async_preload_order.clear()
	async_preload_started = false
	async_preload_cursor = -1
	async_prepare_waits = 0
	async_deadline_steps = 0
	async_preload_peak_usec = 0
	async_epoch += 1
	if cooperative_job != null:
		cooperative_job.dispose()
		cooperative_job = null
	if async_cancel != null: async_cancel.cancel()
	if async_thread != null and async_thread.is_started():
		async_thread.wait_to_finish()
	async_thread = null
	async_cancel = null
	async_job = {}

# 后台证明只回答“这个布局从中央入口是否存在合法双人路线”，与玩家此刻站在哪里无关。
# 玩家的实时位置、跳跃或绳索状态永远不会让生成中止，更不会因此判负。
static func verification_worker(job: Dictionary, cancellation) -> Dictionary:
	var started := Time.get_ticks_usec()
	var verifier = Templates.new()
	verifier.source_override = "runtime"
	verifier.cancellation = cancellation
	# 依次证明同一种段落的几个随机变体（含随机散布陷阱），第一个通过的安装；都不通过才让出空段。
	var block := {}
	for candidate in job.candidates:
		if cancellation.is_canceled(): break
		block = verifier.prove(candidate, job.difficulty, job.level)
		if not block.is_empty(): break
	return {"epoch": job.epoch, "number": job.number, "block": block,
		"canceled": cancellation.is_canceled(), "reason": verifier.last_evidence.get("reason", ""),
		"elapsed_usec": Time.get_ticks_usec() - started}

# 返回 true 表示本段已直接安装（命中历史或缓存），调用方可继续排下一段。
func schedule_generation(base: float) -> bool:
	if async_thread != null or cooperative_job != null: return false
	if block_history.has(next_segment):
		if async_nonblocking:
			async_job = {"epoch": async_epoch, "number": next_segment, "base": base + world_origin,
				"difficulty": difficulty, "level": level_index,
				"key": var_to_str([block_history[next_segment], difficulty, level_index]).sha256_text()}
			async_cancel = Templates.Cancellation.new()
			cooperative_job = preload("res://scripts/road_generation_job.gd").new(async_job, async_cancel, block_history[next_segment])
			return false
		async_job = {"number": next_segment, "base": base + world_origin}
		install_generated(block_history[next_segment].duplicate(true), "checkpoint_history")
		return true
	async_job = generation_request(generator, next_segment, base + world_origin)
	var preload_key := str(next_segment) + ":" + str(async_job.key)
	if async_preload_requests.has(preload_key):
		cooperative_job = async_preload_tasks.get(preload_key)
		if cooperative_job == null:
			cooperative_job = preload("res://scripts/road_generation_job.gd").new(async_job, Templates.Cancellation.new())
		async_cancel = cooperative_job.verifier.cancellation
		async_preload_tasks.erase(preload_key)
		async_preload_requests.erase(preload_key)
		async_preload_order.erase(preload_key)
		return false
	if not lockstep and proven_blocks.has(async_job.key):
		install_generated(proven_blocks[async_job.key].duplicate(true), "cached")
		return true
	async_cancel = Templates.Cancellation.new()
	if not supports_background_generation():
		start_cooperative_generation()
		return false
	async_thread = Thread.new()
	if async_thread.start(verification_worker.bind(async_job.duplicate(true), async_cancel)) != OK:
		async_thread = null
		start_cooperative_generation()
		return false
	return false

func generation_request(picker, number: int, absolute_base: float) -> Dictionary:
	var candidate: Dictionary = picker.candidate_block(number, level_index)
	var candidates := [candidate]
	for n in range(2): candidates.append(picker.candidate_of(candidate.route, level_index))
	return {"epoch": async_epoch, "number": number, "difficulty": difficulty, "level": level_index,
		"candidate": candidate, "candidates": candidates,
		"key": var_to_str([candidate, difficulty, level_index, Templates.source_binding(false)]).sha256_text(),
		"base": absolute_base}

func warm_tutorial_generation() -> void:
	if not generation_enabled or not async_enabled or not streaming or state != "running": return
	# 兼容旧调用名；现在对所有关卡持续维护前方四段，不再只预热开场教学。
	var first_number := next_segment + (0 if async_job.is_empty() else 1)
	if first_number != async_preload_cursor:
		async_preload_started = true
		async_preload_cursor = first_number
		var wanted: Array = []
		var picker = Templates.new()
		picker.rng.state = generator.rng.state
		picker.bag = generator.bag.duplicate()
		picker.bag_level = generator.bag_level
		picker.last_kind = generator.last_kind
		for number in range(first_number, first_number + STREAM_PRELOAD_SEGMENTS):
			var request := generation_request(picker, number, Templates.START_DISTANCE + number * Templates.SEGMENT)
			var key := str(number) + ":" + str(request.key)
			wanted.append(key)
			if request.base >= finish_distance() - Templates.SEGMENT: break
			if not async_preload_requests.has(key):
				async_preload_requests[key] = request
				async_preload_order.append(key)
		for key in async_preload_requests.keys():
			if wanted.has(key): continue
			if async_preload_tasks.has(key):
				async_preload_tasks[key].dispose()
				async_preload_tasks.erase(key)
			async_preload_requests.erase(key)
			async_preload_order.erase(key)
	if async_preload_order.is_empty(): return
	var started := Time.get_ticks_usec()
	var key: String = async_preload_order[0]
	if not async_preload_tasks.has(key):
		async_preload_tasks[key] = preload("res://scripts/road_generation_job.gd").new(async_preload_requests[key], Templates.Cancellation.new())
	var task = async_preload_tasks[key]
	# 按时间与验证步数双重限额让出主线程，不在开门事件里集中补算。
	for index in range(256 if async_startup_pending else GENERATION_STEPS_PER_POLL):
		if task.done or Time.get_ticks_usec() - started >= (6000 if async_startup_pending else PRELOAD_SLICE_USEC): break
		task.advance(1)
	if task.done: async_preload_order.pop_front()
	async_preload_peak_usec = maxi(async_preload_peak_usec, Time.get_ticks_usec() - started)

# 生产场景在消费联机帧/移动之前调用。来不及时只等待这一帧，不同步跑完整段证明。
# 验证速度仅影响真实等待时间；帧编号、命令、输入、地图安装时点均不变。
func generation_due() -> bool:
	if async_job.is_empty(): return false
	if lockstep: return total_distance() + LOCKSTEP_LEAD >= async_job.base
	return maxf(a.position.y, b.position.y) + world_origin + level_speed() * LATE_MARGIN >= async_job.base

func generation_ready() -> bool:
	if cooperative_job != null: return cooperative_job.done
	return async_thread == null or not async_thread.is_alive()

# 进度来自实际完成的段落证明；预计算不改变随机序列或正式安装时点。
func startup_progress() -> float:
	var total := async_preload_requests.size() + (0 if async_job.is_empty() else 1)
	if total == 0: return 1.0 if async_preload_cursor >= 0 or not async_startup_pending else 0.0
	var completed := 0 if async_job.is_empty() or not generation_ready() else 1
	for task in async_preload_tasks.values():
		if task.done: completed += 1
	return float(completed) / total

func prepare_frame() -> bool:
	async_nonblocking = true
	if state != "running": return true
	warm_tutorial_generation()
	if cooperative_job != null and not cooperative_job.done:
		var started := Time.get_ticks_usec()
		for index in range(GENERATION_STEPS_PER_POLL):
			if cooperative_job.done or Time.get_ticks_usec() - started >= PRELOAD_SLICE_USEC: break
			cooperative_job.advance(1)
	if async_startup_pending:
		if startup_progress() < 1.0: return false
		async_startup_pending = false
	var ready := not generation_due() or generation_ready()
	if not ready: async_prepare_waits += 1
	return ready

func install_generated(block: Dictionary, source: String, detail: String = "") -> void:
	var job: Dictionary = async_job
	async_job = {}
	install_block(block, job.base - world_origin, "%d:%d" % [level_index, job.number])
	block_history[job.number] = block.duplicate(true)
	route_segments.append({"number": job.number, "base": job.base, "block": block})
	next_segment += 1
	revision += 1
	async_events.append({"event": "installed", "number": job.number, "base": job.base,
		"route": block.route, "source": source, "detail": detail})

# Web 无论导出模板是否启用线程，都走同一个可暂停验证器；原生保留后台线程。
# 独立方法允许 headless 回归模拟真实 Web 能力，不改变生成参数或验证断言。
func supports_background_generation() -> bool:
	return not OS.has_feature("web")

func start_cooperative_generation() -> void:
	cooperative_job = preload("res://scripts/road_generation_job.gd").new(async_job, async_cancel)

func poll_cooperative_generation() -> void:
	var started := Time.get_ticks_usec()
	if not async_nonblocking: cooperative_job.advance(GENERATION_STEPS_PER_POLL)
	if lockstep:
		# 与原生 worker 完全相同的模拟安装时点；能力/帧率不能决定地图出现在哪一帧。
		if total_distance() + LOCKSTEP_LEAD < async_job.base: return
	elif not cooperative_job.done:
		var leading: float = maxf(a.position.y, b.position.y) + world_origin
		if leading + level_speed() * LATE_MARGIN < async_job.base: return
	if async_nonblocking and not cooperative_job.done: return
	# 兼容直接驱动Run的旧验证入口；生产场景已在prepare_frame分帧等待，不走集中补算。
	# 到达既定安装时点时只补完剩余证明，不因为平台没有 Thread 就吞掉障碍。
	while not cooperative_job.done:
		async_deadline_steps += 256
		cooperative_job.advance(256)
	var proven: Dictionary = cooperative_job.result
	cooperative_job.dispose()
	cooperative_job = null
	async_cancel = null
	if proven.canceled or proven.block.is_empty():
		install_generated(Templates.make_block("safe", 0, level_index), "safe_rejected", proven.reason)
	elif proven.get("source", "") == "checkpoint_history":
		install_generated(proven.block, "checkpoint_history")
	else:
		if not lockstep:
			if proven_blocks.size() > 256: proven_blocks.clear()
			proven_blocks[async_job.key] = proven.block.duplicate(true)
		install_generated(proven.block, "proven")
	async_events[-1].backend = "cooperative"
	async_peak_poll_usec = maxi(async_peak_poll_usec, Time.get_ticks_usec() - started)

func poll_generation() -> void:
	if async_enabled and cooperative_job != null:
		poll_cooperative_generation()
		return
	if not async_enabled or async_thread == null: return
	var started := Time.get_ticks_usec()
	if lockstep:
		if total_distance() + LOCKSTEP_LEAD < async_job.base: return
		if async_nonblocking and async_thread.is_alive(): return
		var proven: Dictionary = async_thread.wait_to_finish()
		async_thread = null
		async_cancel = null
		if proven.canceled or proven.block.is_empty():
			install_generated(Templates.make_block("safe", 0, level_index), "safe_rejected", proven.reason)
		else:
			install_generated(proven.block, "proven")
		async_peak_poll_usec = maxi(async_peak_poll_usec, Time.get_ticks_usec() - started)
		return
	var leading: float = maxf(a.position.y, b.position.y) + world_origin
	# 证明来不及时让出一段空路，不把障碍凭空放到玩家脚下；正常预生成四段，不会走到这里。
	if async_thread.is_alive() and leading + level_speed() * LATE_MARGIN < async_job.base: return
	var late: bool = async_thread.is_alive()
	if late: async_cancel.cancel()
	var result: Dictionary = async_thread.wait_to_finish()
	async_thread = null
	async_cancel = null
	if late or result.canceled or result.block.is_empty():
		install_generated(Templates.make_block("safe", 0, level_index), "safe_late" if late else "safe_rejected", result.reason)
	else:
		# 每局随机布局几乎不会重复，缓存只为同局重试；限制数量，不无限增长。
		if proven_blocks.size() > 256: proven_blocks.clear()
		proven_blocks[async_job.key] = result.block.duplicate(true)
		install_generated(result.block, "proven")
	async_peak_poll_usec = maxi(async_peak_poll_usec, Time.get_ticks_usec() - started)

func reset_input() -> void:
	clear_input = true
	jump_held = [true, true]
	jump_buffer = [0, 0]
	accumulator = 0.0

func retry(count_failure: bool = false) -> void:
	if state in ["settlement", "complete"]: return
	cancel_generation()
	charge_gate = ChargeGate.make_tutorial() if charge_tutorial and streaming and level_index == 0 else {"active": false, "open": false, "charge": 0.0}
	charge_gates.clear()
	gate_events.clear()
	if charge_gate.active:
		charge_gate.id = "tutorial"
		charge_gates.append(charge_gate)
		gate_events.append({"id": "tutorial", "event": "installed", "distance": 0.0})
		var plates := SyncPlates.make_tutorial()
		charge_gates.append(plates)
		gate_events.append({"id": plates.id, "event": "installed", "distance": 0.0})
	generation_halted = false
	coins = 0
	prizes = 0
	shield = false
	shield_uses = 0
	invulnerable_until = 0.0
	absorbed_events.clear()
	claimed_rewards.clear()
	rewards.clear()
	confirmations = [false, false]
	confirmation_held = [true, true]
	revision += 1
	if count_failure:
		failures += 1
	# 生产入口每次开局、重试、进下一关都换新种子，地图、陷阱和奖励每次不同；测试保持固定种子以便复现。
	if lockstep: seed_value = (seed_value * 1103515245 + 12345) & 0x7fffffff
	elif random_seed: seed_value = randi()
	a.position = Vector2(-42, 0)
	b.position = Vector2(42, 0)
	elapsed = 0.0
	distance = 0.0
	world_origin = 0.0
	next_segment = 0
	route_segments.clear()
	# 重试换新种子，旧存档和段落记录全部作废。
	block_history.clear()
	checkpoint = {}
	checkpoint_line = 0.0
	checkpoint_restores = 0
	next_obstacle_id = 1
	recycled = 0
	rebases = 0
	rope.reset(a.position, b.position)
	rope_bound = false
	rope_unwinding = false
	rope_block_substeps = 0
	rope_resume = 1.0
	rope_failed = false
	if streaming:
		obstacles.clear()
		kinds.clear()
		obstacle_heights.clear()
		obstacle_ids.clear()
		hazard_specs.clear()
		generator.reset(seed_value)
	else:
		for spec in hazard_specs:
			if spec.get("industrial", false):
				spec.trigger = -1.0
				spec.warning_evidence = {}
				spec.support_broken = false
			if spec.get("front", false):
				spec.offset = Vector2.ZERO
				spec.locked = false
				spec.trigger = -1.0
				spec.warning_evidence = {}
				spec.blocked = false
				spec.blocked_time = 0.0
				spec.travel = 0.0
	heights = [0.0, 0.0]
	ground_support = [true, true]
	fallen = [false, false]
	rescue = {}
	rescue_count = 0
	move_lock = [false, false]
	last_support = [a.position, b.position]
	rope.height_a = ROPE_HEIGHT
	rope.height_b = ROPE_HEIGHT
	vertical_speed = [0.0, 0.0]
	actions = ["Idle", "Idle"]
	land_time = [0.0, 0.0]
	move_directions = [Vector2.ZERO, Vector2.ZERO]
	reason = ""
	state = "running"
	reset_input()
	# 生产入口必须先完成跳跃、绳状态和输入重置，再生成真实入口证书。
	if streaming: update_stream()
	async_startup_pending = generation_enabled and async_enabled and streaming
	# 起点即第一个存档点：开局附近失败也按同一布局恢复。
	update_checkpoint()

func pause() -> void:
	if state in ["running", "rescue"]:
		paused_from = state
		state = "paused"
	elif state == "paused":
		state = paused_from
	reset_input()

func progress() -> float:
	return world_origin + minf(a.position.y, b.position.y)

func section() -> int:
	return clampi(int(progress() / 3000.0), 0, 2)

func step(delta: float, input_a: Vector2 = Vector2.ZERO, input_b: Vector2 = Vector2.ZERO, jump_a: bool = false, jump_b: bool = false) -> void:
	if not async_nonblocking: warm_tutorial_generation()
	poll_generation()
	if state == "settlement":
		confirm_step(jump_a, jump_b)
		return
	if state == "rescue":
		rescue_step(delta, jump_a, jump_b)
		return
	if state != "running":
		return
	# 用原始按键判断是否已松开；须在 clear_input 清零之前。
	for i in range(2):
		if move_lock[i] and ((input_a if i == 0 else input_b) == Vector2.ZERO or elapsed >= move_lock_until): move_lock[i] = false
	if clear_input:
		input_a = Vector2.ZERO
		input_b = Vector2.ZERO
		jump_held = [jump_a, jump_b]
		clear_input = false
	else:
		var pressed := [jump_a, jump_b]
		for i in range(2):
			if pressed[i] and not jump_held[i]:
				jump_buffer[i] = JUMP_BUFFER_STEPS + 1
			jump_held[i] = pressed[i]
	if move_lock[0]: input_a = Vector2.ZERO
	if move_lock[1]: input_b = Vector2.ZERO
	accumulator += clampf(delta, 0, 0.25)
	while accumulator + 0.0000001 >= FIXED_STEP and state == "running":
		accumulator -= FIXED_STEP
		fixed_step(input_a.limit_length(), input_b.limit_length())

func fixed_step(input_a: Vector2, input_b: Vector2) -> void:
	move_directions = [input_a, input_b]
	# 只辅助贴地站在桥面上的人；腾空越过断崖不受影响。
	if heights[0] == 0.0: input_a = plank_assist(a.position, input_a)
	if heights[1] == 0.0: input_b = plank_assist(b.position, input_b)
	elapsed += FIXED_STEP
	var forward_speed := speed() if streaming else FORWARD
	for index in range(hazard_specs.size()):
		var spec: Dictionary = hazard_specs[index]
		if spec.get("industrial", false) and kinds[index] != "collapse" and spec.trigger < 0 and maxf(a.position.y, b.position.y) >= spec.start_distance:
			spec.trigger = elapsed
			var maximum_forward := level_speed() + LATERAL
			var lane: float = spec.side * (-140 if kinds[index] == "hammer" else 140)
			var joint_change := maxf(absf(a.position.x - (lane - 25)), absf(b.position.x - (lane + 25))) / LATERAL
			var approach: float = (obstacles[index].position.y - maxf(a.position.y, b.position.y) - Motion.RADIUS) / maximum_forward
			if kinds[index] == "drone": approach = maxf(spec.warning, spec.warning + (approach * maximum_forward - maximum_forward * spec.warning) / (maximum_forward - spec.velocity.y))
			if kinds[index] in ["hammer", "steam"]: approach = maxf(spec.warning, approach)
			spec.warning_evidence = {"warning": spec.warning, "maximum_forward": maximum_forward, "joint_change_time": joint_change, "earliest_approach": approach, "reaction_margin": approach - joint_change, "side": spec.side, "locked_velocity": [spec.velocity.x, spec.velocity.y], "leading_y": maxf(a.position.y, b.position.y), "rear_y": minf(a.position.y, b.position.y)}
		if spec.get("front", false):
			Threats.warn(spec, hazard_sample(index, elapsed).rect, [a.position, b.position],
				[Vector2(0, forward_speed * rope_resume) + input_a * LATERAL, Vector2(0, forward_speed * rope_resume) + input_b * LATERAL], LATERAL, EDGE, Motion.RADIUS, elapsed, level_speed() + LATERAL)
	# 绕柱受阻期间自动推进停滞；解围后按 rope_resume 恢复，平时为 1（与原推进完全一致）。
	var step_speed := 0.0 if rope_bound else forward_speed * rope_resume
	# 独立教学允许无限等待。停推进中心，不夹推角色；手动前后和跳跃仍按生产规则处理。
	if charge_gate.active and not charge_gate.open:
		step_speed = minf(step_speed, maxf(0, charge_gate.receiver.y - distance) / FIXED_STEP)
	distance += step_speed * FIXED_STEP
	var circles := rope_circles()
	var roped: bool = not circles.is_empty() or not rope.contacts.is_empty()
	# 每子步地面位移小于碰撞半径，跳跃底部高度也做连续区间检测。
	for i in range(2):
		if jump_buffer[i] > 0:
			if heights[i] == 0.0 and vertical_speed[i] == 0.0:
				if not has_ground_support(a.position if i == 0 else b.position):
					begin_fall(i, a.position if i == 0 else b.position)
					return
				vertical_speed[i] = JUMP_SPEED
				jump_buffer[i] = 0
			else:
				jump_buffer[i] -= 1
	var count := 3
	var dt := FIXED_STEP / count
	for substep in range(count):
		var time_end := elapsed - FIXED_STEP + (substep + 1) * dt
		var time_start := time_end - dt
		var old_heights := heights.duplicate()
		var old_path: PackedVector2Array = rope.path.duplicate()
		var old_path_heights: PackedFloat32Array = rope.path_heights()
		var dynamic_before := advance_threats(dt)
		circles = rope_circles()
		roped = not circles.is_empty() or not rope.contacts.is_empty()
		for i in range(2):
			if heights[i] > 0 or vertical_speed[i] > 0:
				heights[i] = maxf(0, heights[i] + vertical_speed[i] * dt - GRAVITY * dt * dt * 0.5)
				vertical_speed[i] -= GRAVITY * dt
				if heights[i] == 0:
					vertical_speed[i] = 0.0
					land_time[i] = 0.12
			land_time[i] = maxf(0, land_time[i] - dt)
			actions[i] = ("Takeoff" if vertical_speed[i] > JUMP_SPEED * 0.6 else "Air") if heights[i] > 0 else ("Land" if land_time[i] > 0 else "Run")
		circles = rope_circles()
		var pa := a.position
		var pb := b.position
		var rope_a: float = ROPE_HEIGHT + heights[0]
		var rope_b: float = ROPE_HEIGHT + heights[1]
		var base := Vector2(0, step_speed * dt)
		# 被巨岩挡在后边界之后的人：本子步至少随道路推进的位置为下限，可向前追回，不能自行继续掉队。
		var floor_a := pa.y + base.y
		var floor_b := pb.y + base.y
		# 双方期望移动、自动推进和绳索约束在同一子步内求解：先看自动推进本身是否会让绕障路径超长。
		if roped and step_speed > 0.0 and rope.solve(bounded(pa + base, floor_a), bounded(pb + base, floor_b), rope_a, rope_b, circles, false) > LINK_LIMIT and rope.solved_blocking > 0:
			# 只推进绳索允许的比例，其余部分连同本步剩余子步一起停滞，前后边界随之停住，
			# 不会把被绳索拦住的角色强行推过障碍。
			var full := distance
			var refund := step_speed * dt
			var allowed := 0.0
			var denied := 1.0
			for iteration in range(20):
				var t := (allowed + denied) * 0.5
				distance = full - refund * (count - substep - t)
				if rope.solve(bounded(pa + base * t, pa.y + base.y * t), bounded(pb + base * t, pb.y + base.y * t), rope_a, rope_b, circles, false) <= LINK_LIMIT:
					allowed = t
				else:
					denied = t
			distance = full - refund * (count - substep - allowed)
			base *= allowed
			step_speed = 0.0
			rope_bound = true
			rope_resume = 0.0
			floor_a = pa.y + base.y
			floor_b = pb.y + base.y
		var ca := bounded(pa + base + input_a * LATERAL * dt, floor_a)
		var cb := bounded(pb + base + input_b * LATERAL * dt, floor_b)
		if charge_gate.active and not charge_gate.open:
			# 全宽高门不允许跳过；保留横向滑行和后撤，最终约束位移还需扫掠复核。
			var front: float = charge_gate.door.position.y - Motion.RADIUS - 0.01
			ca.y = minf(ca.y, front)
			cb.y = minf(cb.y, front)
		# 巨岩只阻挡不伤人：期望位移先沿岩面滑行或原地停住，道路照常推进。
		ca = resolve_cargo(pa, ca, old_heights[0], heights[0])
		cb = resolve_cargo(pb, cb, old_heights[1], heights[1])
		floor_a = minf(floor_a, ca.y)
		floor_b = minf(floor_b, cb.y)
		# 免伤不解除实体阻挡；先拒绝穿入柱子的期望位移，再求双方绳索。
		var solid_blocked := false
		if shield or elapsed < invulnerable_until:
			for index in range(kinds.size()):
				if not kinds[index] in ["pillar", "sweeper"]: continue
				for i in range(2):
					var from: Vector2 = pa if i == 0 else pb
					var to: Vector2 = ca if i == 0 else cb
					if solid_sweep_hits(index, from, to, old_heights[i], heights[i]):
						if damage(collision_event(index), "%02d 命中%s，两人共同重试" % [i + 1, hazard_name(kinds[index])]): return
						solid_blocked = true
		if solid_blocked:
			# 实体阻挡与推进中心共同停下；不能让前后边界在免伤期间强推角色穿墙。
			distance -= step_speed * dt * (count - substep)
			step_speed = 0.0
			base = Vector2.ZERO
			ca = bounded(pa + input_a * LATERAL * dt, pa.y)
			cb = bounded(pb + input_b * LATERAL * dt, pb.y)
			if not solid_sweep_clear(pa, ca, old_heights[0], heights[0]): ca = pa
			if not solid_sweep_clear(pb, cb, old_heights[1], heights[1]): cb = pb
		if rope_span(ca, cb, rope_a, rope_b, circles) > LINK_LIMIT:
			var ba := bounded(pa + base, floor_a)
			var bb := bounded(pb + base, floor_b)
			# 自动推进基准也必须已通过实体扫掠，禁止从穿入的位置开始绳索二分。
			if not solid_sweep_clear(pa, ba, old_heights[0], heights[0]) or not solid_sweep_clear(pb, bb, old_heights[1], heights[1]):
				ba = pa
				bb = pb
			var slack := rope_span(ba, bb, rope_a, rope_b, circles)
			if slack > LINK_LIMIT:
				if rope.solved_blocking == 0 and rope.solved_valid:
					# 单精度舍入会让自动推进后的间距逐步漂过绳长；对称收回到绳长内，
					# 修正量小于 0.01 单位、保持在边界盒内，不累积也不构成瞬移。
					var middle := (ba + bb) * 0.5
					var keep := (LINK_LIMIT - 0.002) / slack
					ba = middle + (ba - middle) * keep
					bb = middle + (bb - middle) * keep
					if not solid_sweep_clear(pa, ba, old_heights[0], heights[0]) or not solid_sweep_clear(pb, bb, old_heights[1], heights[1]):
						ba = pa
						bb = pb
				else:
					# 有接触时不做几何收回：退回上一子步已验证的位置，只接受可行的位移。
					ba = pa
					bb = pb
			var low := 0.0
			var high := 1.0
			for iteration in range(20):
				var t := (low + high) * 0.5
				if rope_span(ba.lerp(ca, t), bb.lerp(cb, t), rope_a, rope_b, circles) <= LINK_LIMIT:
					low = t
				else:
					high = t
			var want_a := ca
			var want_b := cb
			ca = ba.lerp(want_a, low)
			cb = bb.lerp(want_b, low)
			# 联合二分只取公共比例；再让每人单独沿自身期望位移推进，
			# 收紧绳索的一方（例如被巨岩卡住后横移脱困）不会被队友的前进拖住。
			if low < 1.0:
				for i in range(2):
					var from: Vector2 = ca if i == 0 else cb
					var to: Vector2 = want_a if i == 0 else want_b
					var other: Vector2 = cb if i == 0 else ca
					var own_low := 0.0
					var own_high := 1.0
					for iteration in range(20):
						var t := (own_low + own_high) * 0.5
						var trial := from.lerp(to, t)
						var span := rope_span(trial, other, rope_a, rope_b, circles) if i == 0 else rope_span(other, trial, rope_a, rope_b, circles)
						if span <= LINK_LIMIT:
							own_low = t
						else:
							own_high = t
					if i == 0: ca = from.lerp(to, own_low)
					else: cb = from.lerp(to, own_low)
		var bodies := separate_bodies(pa, pb, ca, cb, floor_a, floor_b)
		ca = bodies[0]
		cb = bodies[1]
		# 所有约束修正（含边界夹取、二分和舍入收回）均在提交前检查实际扫掠。
		# 失败时从上一合法位置联合缩短位移，不提交后再拉回角色。
		if not solid_sweep_clear(pa, ca, old_heights[0], heights[0]) or not solid_sweep_clear(pb, cb, old_heights[1], heights[1]):
			var solid_hit := false
			for index in range(kinds.size()):
				if kinds[index] == "cargo": continue
				if solid_sweep_hits(index, pa, ca, old_heights[0], heights[0]) or solid_sweep_hits(index, pb, cb, old_heights[1], heights[1]):
					solid_hit = true
					if damage(collision_event(index), "角色约束位移命中%s，两人共同重试" % hazard_name(kinds[index])): return
			# 只碰巨岩时道路继续推进，被挡的人落到后边界之后。
			if solid_hit or not charge_gate_clear(pa, ca, pb, cb):
				distance -= step_speed * dt * (count - substep)
				step_speed = 0.0
			var low_a := minf(floor_a, pa.y)
			var low_b := minf(floor_b, pb.y)
			var low := 0.0
			var high := 1.0
			for iteration in range(20):
				var t := (low + high) * 0.5
				var first := pa.lerp(ca, t)
				var second := pb.lerp(cb, t)
				if solid_sweep_clear(pa, first, old_heights[0], heights[0]) and solid_sweep_clear(pb, second, old_heights[1], heights[1]) and first.distance_to(bounded(first, low_a)) < 0.01 and second.distance_to(bounded(second, low_b)) < 0.01 and rope_span(first, second, rope_a, rope_b, circles) <= LINK_LIMIT:
					low = t
				else: high = t
			ca = pa.lerp(ca, low)
			cb = pb.lerp(cb, low)
		var wrap_before: float = rope.total_wrap
		if roped:
			rope.solve(ca, cb, rope_a, rope_b, circles, true)
		else:
			rope.straight(ca, cb, rope_a, rope_b)
		a.position = ca
		b.position = cb
		# 巨岩挡住不死；一直被挡到挤出画面下沿才失败，免伤也不能保住画面外的人。
		for i in range(2):
			if rear_bound() - (ca.y if i == 0 else cb.y) > SQUEEZE_LIMIT:
				fail_threat("%02d 被巨岩卡住挤出画面，两人共同重试" % (i + 1))
				return
		advance_collapse(time_start, time_end, pa, ca, pb, cb, old_heights)
		# 先求出双方支撑，再判定坠落：救援须知道队友此刻是否站稳。
		var dropping: Array[int] = []
		for i in range(2):
			var from: Vector2 = pa if i == 0 else pb
			var to: Vector2 = ca if i == 0 else cb
			ground_support[i] = has_ground_support(to, time_end)
			if heights[i] == 0.0:
				# 落地按最终脚下圆形支撑检查；贴地移动还检查全过程，不能跨过缺口。
				if not ground_support[i] or (old_heights[i] == 0.0 and not ground_sweep_supported(from, to, time_end)):
					dropping.append(i)
		if not dropping.is_empty():
			if dropping.size() == 2: fall(dropping[0], a.position if dropping[0] == 0 else b.position)
			else: begin_fall(dropping[0], a.position if dropping[0] == 0 else b.position)
			return
		for i in range(2):
			if ground_support[i] and heights[i] == 0.0: last_support[i] = a.position if i == 0 else b.position
		rope_unwinding = false
		if rope_bound:
			if rope.touching() > 0 and rope.total_wrap < wrap_before - ROPE_UNWIND_RATE * dt:
				rope_unwinding = true
			else:
				# 前向受阻的直接判定：从当前位置按全速自动推进一个子步，绕障路径是否超出绳长。
				var probe := Vector2(0, forward_speed * dt)
				if roped and rope.solve(bounded(ca + probe, ca.y + probe.y), bounded(cb + probe, cb.y + probe.y), rope_a, rope_b, circles, false) > LINK_LIMIT and rope.solved_blocking > 0:
					# 被真实接触（已压住，或拉满的绳索再前进就压上）挡住才累计；
					# 只是腾空越过矮障碍时被落点约束挡住，道路停住但不累计。
					if rope.solved_contacts > 0: rope_block_substeps += 1
				else:
					# 有余量又没有在解围：恢复自动推进，重新收紧后继续累计，计时不清零。
					rope_bound = false
		# 接触完全解除（含松脱待定结束）且不再受阻才清零。
		if not rope_bound and rope.contacts.is_empty(): rope_block_substeps = 0
		for index in range(obstacles.size()):
			if kinds[index] in Industrial.KINDS:
				var hit := industrial_hits(index, time_start, time_end, pa, ca, pb, cb, old_heights, old_path, old_path_heights)
				if not hit.is_empty():
					fail_threat("%s命中%s/%s，两人共同重试" % [hit.actor, hazard_name(kinds[index]), hit.part])
					return
				continue
			if kinds[index] in ["road_gap", "cargo"]: continue
			# 静止陷阱离两人和连线都远时跳过：每子步位移远小于 40 单位余量，只省计算不改判定。
			if kinds[index] in STATIC_KINDS and (obstacles[index].position.y > maxf(maxf(pa.y, ca.y), maxf(pb.y, cb.y)) + 40.0 or obstacles[index].end.y < minf(minf(pa.y, ca.y), minf(pb.y, cb.y)) - 40.0): continue
			if kinds[index] == "sweeper":
				if sweeper_rope_hits(index, time_start, time_end, old_path, old_path_heights):
					fail_threat("绳段命中旋转扫杆支座或杆体，两人共同重试")
					return
			if hazard_specs[index].get("front", false):
				var spec: Dictionary = hazard_specs[index]
				var previous: Rect2 = dynamic_before.get(index, hazard_sample(index, time_end).rect)
				var current: Rect2 = hazard_sample(index, time_end).rect
				for i in range(2):
					var from: Vector2 = pa if i == 0 else pb
					var to: Vector2 = ca if i == 0 else cb
					var hit: bool
					if Threats.is_ball(kinds[index]):
						hit = Threats.sphere_body(from, to, old_heights[i], heights[i], previous.get_center(), current.get_center(), current.size.x * 0.5, BODY_HEIGHT, Motion.RADIUS)
					else:
						hit = swept_body_hits(from, to - (current.position - previous.position), old_heights[i], heights[i], previous.grow(Motion.RADIUS), spec.bottom, obstacle_heights[index])
					if hit and damage(collision_event(index), "%02d 命中%s，两人共同重试" % [i + 1, hazard_name(kinds[index])]):
						return
				if not Threats.is_ball(kinds[index]) and front_rope_hits(index, previous, current, old_path, old_path_heights):
					fail_threat("绳段命中%s，两人共同重试" % hazard_name(kinds[index]))
					return
				if Threats.is_ball(kinds[index]):
					if spec.blocked and rope.touches(obstacle_ids[index]) and rope.required >= LINK_LIMIT - 0.02:
						spec.blocked_time += dt
					else: spec.blocked_time = 0.0
					if spec.blocked_time >= ROPE_BLOCK_LIMIT:
						rope_failed = true
						fail_threat("滚球带绳持续接触且约束耗尽 0.8 秒，两人共同重试")
						return
				continue
			for i in range(2):
				var from: Vector2 = pa if i == 0 else pb
				var to: Vector2 = ca if i == 0 else cb
				if timed_hazard_hits(index, time_start, time_end, from, to, old_heights[i], heights[i]):
					if damage(collision_event(index), "%02d 命中%s，两人共同重试" % [i + 1, hazard_name(kinds[index])]): return
		collect_rewards(pa, pb)
		if charge_gate.active:
			var was_open: bool = charge_gate.open
			if charge_gate.get("kind", "charge") == "sync_plates":
				# 起跳、腾空或落地的子步不计为连续地面站位。
				SyncPlates.advance(charge_gate, a.position, b.position,
					ground_support[0] and old_heights[0] == 0.0 and heights[0] == 0.0 and vertical_speed[0] == 0.0,
					ground_support[1] and old_heights[1] == 0.0 and heights[1] == 0.0 and vertical_speed[1] == 0.0, dt)
			else:
				ChargeGate.advance(charge_gate, rope.path, rope.path_heights(), rope_tension(), charge_path_clear(), dt)
			if not was_open and charge_gate.open:
				gate_events.append({"id": charge_gate.id, "event": "opened", "distance": total_distance()})
		if rope_block_substeps >= ROPE_BLOCK_SUBSTEPS:
			state = "failed"
			rope_failed = true
			actions = ["Hit", "Hit"]
			reason = ("滚球带绳持续接触且约束耗尽 %.1f 秒，两人共同重试" if ball_contact() else "绳索绕柱受阻 %.1f 秒未解围，两人共同重试") % ROPE_BLOCK_LIMIT
			reset_input()
			return
	if not rope_bound: rope_resume = minf(1.0, rope_resume + FIXED_STEP / ROPE_RESUME_TIME)
	if streaming: update_stream()
	check_finish()
	if state == "running": update_checkpoint()

func rope_span(p: Vector2, q: Vector2, rope_a: float, rope_b: float, circles: Array) -> float:
	if circles.is_empty() and rope.contacts.is_empty():
		rope.solved_contacts = 0
		rope.solved_blocking = 0
		rope.solved_valid = true
		return p.distance_to(q)
	return rope.solve(p, q, rope_a, rope_b, circles, false)

# 只削减本子步内“朝对方靠近”的位移分量，按各自靠近量分摊；不推动静止的队友，也不拉回已有间距。
# 上一子步已重叠时只禁止继续靠近。修正后的位置仍经过边界夹取和后续实体扫掠复核。
func separate_bodies(pa: Vector2, pb: Vector2, ca: Vector2, cb: Vector2, floor_a: float = INF, floor_b: float = INF) -> Array:
	var gap := ca.distance_to(cb)
	var floor_gap := minf(BODY_GAP, pa.distance_to(pb))
	if gap >= floor_gap - 0.00001: return [ca, cb]
	var normal := (cb - ca).normalized() if gap > 0.00001 else (pb - pa).normalized()
	if normal == Vector2.ZERO: normal = Vector2.RIGHT
	var ma := maxf(0.0, (ca - pa).dot(normal))
	var mb := maxf(0.0, (pb - cb).dot(normal))
	if ma + mb < 0.00001: return [pa, pb]
	var overlap := floor_gap - gap
	return [bounded(ca - normal * overlap * ma / (ma + mb), floor_a), bounded(cb + normal * overlap * mb / (ma + mb), floor_b)]

# 仅实体高障碍限制免伤位移；接触表面允许沿面滑行和向外回撤。
# 0.001 地面单位只消除浮点相切误判，远小于既有绳长容限。
func solid_sweep_hits(index: int, from: Vector2, to: Vector2, h0: float, h1: float) -> bool:
	if kinds[index] == "sweeper":
		return minf(h0, h1) <= Surfaces.POST_TOP and Surfaces.point_segment_distance(obstacles[index].get_center(), from, to) < Surfaces.POST_RADIUS + Motion.RADIUS - 0.001
	if not kinds[index] in ["cargo", "pillar"]: return false
	var rect: Rect2 = obstacles[index].grow(Motion.RADIUS - 0.001)
	if not swept_body_hits(from, to, h0, h1, rect, 0.0, obstacle_heights[index]): return false
	return kinds[index] == "cargo" or Rope.segment_distance(from, to, obstacles[index].get_center()) < obstacles[index].size.x * 0.5 + Motion.RADIUS - 0.001

func charge_gate_clear(pa: Vector2, ca: Vector2, pb: Vector2, cb: Vector2) -> bool:
	if not charge_gate.active or charge_gate.open: return true
	var door: Rect2 = charge_gate.door.grow(Motion.RADIUS - 0.001)
	return not segment_hits(pa, ca, door) and not segment_hits(pb, cb, door)

func solid_sweep_clear(from: Vector2, to: Vector2, h0: float, h1: float) -> bool:
	if charge_gate.active and not charge_gate.open and segment_hits(from, to, charge_gate.door.grow(Motion.RADIUS - 0.001)):
		return false
	for index in range(kinds.size()):
		if solid_sweep_hits(index, from, to, h0, h1): return false
	return true

func charge_path_clear() -> bool:
	# 判定整条实际路径和实际高度，不用角色端点连线替代绕障结果。
	if not rope.contacts.is_empty(): return false
	var path: PackedVector2Array = rope.path
	var z: PackedFloat32Array = rope.path_heights()
	for index in range(kinds.size()):
		var sample := hazard_sample(index, elapsed)
		if not sample.active or kinds[index] in ["road_gap", "collapse"]: continue
		for i in range(1, path.size()):
			if maxf(z[i-1], z[i]) < sample.bottom or minf(z[i-1], z[i]) > sample.top: continue
			if segment_hits(path[i-1], path[i], sample.rect): return false
	return true

# 存档只在安全时刻保存：两人贴地有支撑、绳索未挂障碍或受阻，且附近没有危险、缺口或正在逼近的移动物。
func checkpoint_safe() -> bool:
	for i in range(2):
		if heights[i] != 0.0 or vertical_speed[i] != 0.0 or not ground_support[i]: return false
	if rope.touching() > 0 or rope_block_substeps > 0 or rope_unwinding or rope_failed: return false
	var low: float = minf(a.position.y, b.position.y) - CHECKPOINT_CLEAR_BEHIND
	# 前方窗口从身体前缘算起，窗口内直行不会碰到缺口或障碍边缘。
	var high: float = maxf(a.position.y, b.position.y) + Motion.RADIUS + CHECKPOINT_SIDE_MARGIN + level_speed() * CHECKPOINT_CLEAR_AHEAD
	# 恢复后不按键会沿原横向位置直行：固定危险只看两人连同绳段直行扫过的走廊，移动危险不论左右都要远离。
	var margin: float = Motion.RADIUS + CHECKPOINT_SIDE_MARGIN
	var left: float = minf(a.position.x, b.position.x) - margin
	var corridor := Rect2(left, low, maxf(a.position.x, b.position.x) + margin - left, high - low)
	var far: float = high + level_speed() * CHECKPOINT_MOVING_AHEAD
	for i in range(obstacles.size()):
		var sample := hazard_sample(i, elapsed)
		var rect: Rect2 = sample.get("envelope", sample.rect)
		var moving: bool = hazard_specs[i].get("front", false) or kinds[i].begins_with("fly_") or kinds[i] in ["drone", "forklift"]
		if rect.intersects(corridor, true) or (moving and rect.end.y >= low and rect.position.y <= far): return false
		# 迎面物按相对速度估算到达时间，高速弩箭在更远处也算逼近。
		if sample.has("ttc") and rect.end.y >= low and sample.ttc < CHECKPOINT_CLEAR_AHEAD + CHECKPOINT_MOVING_AHEAD: return false
	return true

func update_checkpoint() -> void:
	if progress() < checkpoint_line or not checkpoint_safe(): return
	capture_checkpoint()
	# 下一条存档线是当前进度之后的下一个段落入口；入口不安全时在本段内顺延到首个安全时刻。
	var passed: float = floorf((progress() - Templates.START_DISTANCE) / Templates.SEGMENT) + 1.0
	checkpoint_line = Templates.START_DISTANCE + maxf(0.0, passed) * Templates.SEGMENT

# 完整深拷贝对局：危险相位、奖励领取、机关进度、绳索接触和计时全部随快照回到存档时刻。
func capture_checkpoint() -> void:
	var excluded: Array = CHECKPOINT_EXCLUDED.duplicate()
	for property in get_property_list():
		if str(property.name).begins_with("async_"): excluded.append(property.name)
	checkpoint = {"run": Templates.object_state(self, excluded), "a": a.position, "b": b.position,
		"rope": Templates.object_state(rope), "progress": progress()}

# 失败后从最近存档恢复：布局、已领奖励和金币回到存档时刻；存档之后已生成的段落按原样重新安装。
# 恢复给予短暂无敌，并屏蔽仍按住的旧输入。没有存档时返回 false，由调用方改为整关重试。
func restore_checkpoint() -> bool:
	if checkpoint.is_empty() or state != "failed": return false
	cancel_generation()
	for name in checkpoint.run:
		var value = checkpoint.run[name]
		set(name, value.duplicate(true) if value is Array or value is Dictionary else value)
	a.position = checkpoint.a
	b.position = checkpoint.b
	for name in checkpoint.rope:
		var value = checkpoint.rope[name]
		rope.set(name, value.duplicate(true) if value is Array or value is Dictionary else value)
	# 快照里当前机关是队列内字典的独立副本，需重新指向队列成员，充能才写回同一对象。
	select_charge_gate()
	failures += 1
	checkpoint_restores += 1
	revision += 1
	invulnerable_until = maxf(invulnerable_until, elapsed + Levels.INVULNERABILITY)
	state = "running"
	reset_input()
	if streaming: update_stream()
	async_startup_pending = generation_enabled and async_enabled and streaming
	return true

func fall(role: int, point: Vector2) -> void:
	fallen[role] = true
	fail_threat(("%02d 走出路面坠下悬崖，队友被连线一起拖了下去" if absf(point.x) > EDGE else "%02d 踩空坠落，绳索拉不住，两人共同重试") % [role + 1])

# 队友贴地站稳才能拉住绳子；队友腾空或也失去支撑时按原规则直接坠落。
func begin_fall(role: int, point: Vector2) -> void:
	var partner := 1 - role
	if heights[partner] > 0.0 or vertical_speed[partner] != 0.0 or not ground_support[partner]:
		fall(role, point)
		return
	var rate: float = RESCUE_RATES[difficulty] * pow(RESCUE_ESCALATION, rescue_count)
	rescue = {"role": role, "point": point, "hang": hang_point(point, last_support[role]), "progress": 0.0, "time": 0.0, "rate": rate,
		"gain": (1.0 / RESCUE_TIME + RESCUE_DECAY) / rate, "presses": [0, 0]}
	state = "rescue"
	actions[role] = "Hang"
	reset_input()

# 仅供表现：失足时身体中心可能仍在桥面上方，沿离开方向找到真正的崖沿，吊在崖沿外 0.4 米。
func hang_point(point: Vector2, from: Vector2) -> Vector2:
	var direction := (point - from).normalized()
	if direction == Vector2.ZERO: direction = Vector2(signf(point.x) if point.x != 0.0 else 1.0, 0)
	var gaps := ground_gaps()
	var probe := point
	for n in range(40):
		if absf(probe.x) > EDGE or not Surfaces.supported(probe, 0.5, gaps): break
		probe += direction * 2.0
	return probe + direction * 8.0

# 冻结世界，只推进救援计时；按键只计按下边沿，按住不算。
func rescue_step(delta: float, jump_a: bool, jump_b: bool) -> void:
	if clear_input:
		jump_held = [jump_a, jump_b]
		clear_input = false
	else:
		var pressed := [jump_a, jump_b]
		for i in range(2):
			if pressed[i] and not jump_held[i]:
				rescue.presses[i] += 1
				rescue.progress = minf(1.0, rescue.progress + rescue.gain * (RESCUE_CLIMB if i == rescue.role else 1.0))
			jump_held[i] = pressed[i]
	if rescue.progress >= 1.0 and not rescue.has("climb"):
		# 拉满后进入爬上阶段：世界仍冻结，表现层把人从崖下拉到落脚点。
		rescue.climb = 0.0
		rescue.anchor = rescue_anchor()
		if rescue.anchor == Vector2.INF:
			# 没有合法落脚点时保留失败结果，绝不把人放回坑边伪装救援成功。
			fall(rescue.role, rescue.point)
			rescue = {}
			return
	accumulator += clampf(delta, 0, 0.25)
	while accumulator + 0.0000001 >= FIXED_STEP and state == "rescue":
		accumulator -= FIXED_STEP
		if rescue.has("climb"):
			rescue.climb += FIXED_STEP
			if rescue.climb >= RESCUE_CLIMB_TIME - 0.000001: finish_rescue()
			continue
		rescue.time += FIXED_STEP
		rescue.progress = maxf(0.0, rescue.progress - RESCUE_DECAY * FIXED_STEP)
		if rescue.time >= RESCUE_TIME - 0.000001:
			var point: Vector2 = rescue.point
			var role: int = rescue.role
			rescue = {}
			fall(role, point)

# 落脚点：在队友（已站稳）附近找一块留有余量的地面，且之后一段自动推进路程内仍有支撑，
# 避免救上来站在坑沿、被推进或残余输入立刻带回坑里。优先队友正后方，其次靠近失足前的支撑点。
func rescue_anchor() -> Vector2:
	var role: int = rescue.role
	var partner_point: Vector2 = b.position if role == 0 else a.position
	var fallback: Vector2 = bounded(last_support[role])
	var lookahead: float = (speed() if streaming else FORWARD) * 1.0
	var best := Vector2.INF
	var best_score := INF
	var gaps := ground_gaps()
	for iy in range(-16, 17):
		for ix in range(-34, 35):
			var candidate := bounded(partner_point + Vector2(ix * 4.0, iy * 8.0))
			var gap := candidate.distance_to(partner_point)
			if gap < BODY_GAP + 2.0 or gap > LINK_LIMIT - 8.0: continue
			if absf(candidate.x) > EDGE - Motion.RADIUS - 4.0: continue
			var end := candidate + Vector2(0, lookahead)
			if not Surfaces.supported_sweep(candidate, end, Motion.RADIUS + 4.0, gaps): continue
			if not solid_sweep_clear(candidate, end, 0.0, 0.0): continue
			# 爬上落点与队友之间不能隔着实体，也不能重建一根穿柱的绳。
			if not solid_sweep_clear(partner_point, candidate, 0.0, 0.0): continue
			var score := absf(candidate.x - partner_point.x) * 2.0 + absf(candidate.y - (partner_point.y - BODY_GAP - 8.0)) + candidate.distance_to(fallback) * 0.25
			if score < best_score:
				best_score = score
				best = candidate
	return best

# 救起：爬上动画结束后站到安全落脚点，残余方向键须松开（或 0.6 秒后）才重新生效。
func finish_rescue() -> void:
	var role: int = rescue.role
	var anchor: Vector2 = rescue.anchor if rescue.has("anchor") else rescue_anchor()
	move_lock[role] = true
	move_lock_until = elapsed + MOVE_LOCK_TIME
	if role == 0: a.position = anchor
	else: b.position = anchor
	heights[role] = 0.0
	vertical_speed[role] = 0.0
	ground_support[role] = true
	last_support[role] = anchor
	rope.reset(a.position, b.position)
	invulnerable_until = elapsed + RESCUE_INVULNERABLE
	rope_resume = 0.0
	rescue_count += 1
	rescue = {}
	actions = ["Run", "Run"]
	state = "running"
	reset_input()

func fail_threat(message: String) -> void:
	cancel_generation()
	state = "failed"
	actions = ["Hit", "Hit"]
	reason = message
	reset_input()

# 分部盒可在同一子步内平移或升降；以相对三维坐标做连续检测。
# 绳索按新旧折线路程合并切分，保持每段真实高度，不使用端点高度包络。
func industrial_hits(index: int, start: float, end: float, pa: Vector2, ca: Vector2,
		pb: Vector2, cb: Vector2, old_heights: Array, old_path: PackedVector2Array,
		old_z: PackedFloat32Array) -> Dictionary:
	var actors := Rect2(pa, Vector2.ZERO)
	for point in [ca, pb, cb]: actors = actors.expand(point)
	for point in old_path: actors = actors.expand(point)
	for point in rope.path: actors = actors.expand(point)
	# 包括两帧全部绳接触点及角色半径；只有二维保守包络完全分离才省略昂贵分片。
	if not actors.grow(Motion.RADIUS + 1.0).intersects(industrial_sweep_bounds(index, start, end), true): return {}
	var old_f := path_fractions(old_path)
	var new_z: PackedFloat32Array = rope.path_heights()
	var new_f := path_fractions(rope.path)
	var cuts: Array = old_f.duplicate()
	for fraction in new_f:
		if not cuts.has(fraction): cuts.append(fraction)
	cuts.sort()
	var times: Array = Industrial.time_cuts(kinds[index], hazard_specs[index], start, end)
	for interval in range(times.size() - 1):
		var t0: float = times[interval]
		var t1: float = times[interval + 1]
		var f0 := (t0 - start) / (end - start) if end > start else 0.0
		var f1 := (t1 - start) / (end - start) if end > start else 1.0
		var before: Dictionary = hazard_sample(index, t0)
		var after: Dictionary = hazard_sample(index, t1)
		var middle: Dictionary = hazard_sample(index, (t0 + t1) * 0.5)
		for n in range(after.parts.size()):
			var first: Dictionary = before.parts[n]
			var last: Dictionary = after.parts[n]
			if not middle.parts[n].active: continue
			# 单摆锤头与摆臂都是随时间平移、升降的轴对齐盒，与其他分部障碍共用下面的相对运动检测。
			var c0: Vector2 = first.rect.get_center()
			var c1: Vector2 = last.rect.get_center()
			var shift0 := Vector3(c0.x, c0.y, first.bottom)
			var shift1 := Vector3(c1.x, c1.y, last.bottom)
			var half: Vector2 = first.rect.size * 0.5
			var top: float = maxf(first.top - first.bottom, last.top - last.bottom)
			for role in range(2):
				var from: Vector2 = pa if role == 0 else pb
				var to: Vector2 = ca if role == 0 else cb
				var a0 := Vector3(from.x, from.y, old_heights[role])
				var a1 := Vector3(to.x, to.y, heights[role])
				if Threats.line_box(a0.lerp(a1, f0) - shift0, a0.lerp(a1, f1) - shift1,
						Vector3(-half.x - Motion.RADIUS, -half.y - Motion.RADIUS, -BODY_HEIGHT),
						Vector3(half.x + Motion.RADIUS, half.y + Motion.RADIUS, top)):
					return {"actor": "%02d" % (role + 1), "part": last.name}
			for i in range(cuts.size() - 1):
				var p0 := path_at(old_path, old_z, old_f, cuts[i])
				var q0 := path_at(old_path, old_z, old_f, cuts[i + 1])
				var p1 := path_at(rope.path, new_z, new_f, cuts[i])
				var q1 := path_at(rope.path, new_z, new_f, cuts[i + 1])
				if Threats.rope_box_sweep(p0.lerp(p1, f0) - shift0, q0.lerp(q1, f0) - shift0,
						p0.lerp(p1, f1) - shift1, q0.lerp(q1, f1) - shift1,
						Vector3(-half.x - 1, -half.y - 1, -1), Vector3(half.x + 1, half.y + 1, top + 1)):
					return {"actor": "绳段", "part": last.name}
	return {}

func industrial_sweep_bounds(index: int, start: float, end: float) -> Rect2:
	var before: Dictionary = hazard_sample(index, start)
	var after: Dictionary = hazard_sample(index, end)
	var bounds: Rect2 = before.parts[0].rect
	for part in before.parts: bounds = bounds.merge(part.rect)
	for part in after.parts: bounds = bounds.merge(part.rect)
	# 平移分部为线性/夹断运动；锤头和柄再扩最大角速度位移，覆盖两端之间的弧线。
	var margin := Industrial.HAMMER_RATE * (Industrial.HAMMER_LENGTH + 22.0) * absf(end - start) if kinds[index] == "hammer" else 0.0
	return bounds.grow(margin + 0.001)

static func industrial_local(point: Vector3, center: Vector2, angle: float) -> Vector3:
	var flat := (Vector2(point.x, point.y) - center).rotated(-angle)
	return Vector3(flat.x, flat.y, point.z)

func advance_collapse(start: float, end: float, pa: Vector2, ca: Vector2, pb: Vector2, cb: Vector2, old_heights: Array) -> void:
	for index in range(kinds.size()):
		if kinds[index] != "collapse": continue
		var spec: Dictionary = hazard_specs[index]
		if spec.trigger < 0:
			var plate := obstacles[index]
			var entered := false
			for role in range(2):
				var from: Vector2 = pa if role == 0 else pb
				var to: Vector2 = ca if role == 0 else cb
				if old_heights[role] > 0 and heights[role] > 0: continue
				if old_heights[role] > 0: from = to
				if not Surfaces.supported(from, Motion.RADIUS, [plate]) or not Surfaces.supported(to, Motion.RADIUS, [plate]): entered = true
				var corners := [plate.position, Vector2(plate.end.x, plate.position.y), plate.end, Vector2(plate.position.x, plate.end.y)]
				for n in range(4):
					if Surfaces.segments_distance(from, to, corners[n], corners[(n + 1) % 4]) < Motion.RADIUS - 0.00001: entered = true
			if entered:
				spec.trigger = start
				spec.warning_evidence = {"grace": spec.grace, "rear_distance": absf(pa.y - pb.y), "rope": rope.required, "rope_heights": Array(rope.path_heights()),
					"positions": [pa, pb], "support": ground_support.duplicate(), "minimum_forward": level_speed() if streaming else FORWARD,
					"permitted_entry": not rope_bound and rope.contacts.is_empty() and absf(pa.y - pb.y) <= LINK_LIMIT + 0.01}
		if spec.trigger >= 0 and end >= spec.trigger + spec.grace and not spec.support_broken:
			spec.support_broken = true
			revision += 1

func ball_contact() -> bool:
	for index in range(kinds.size()):
		if Threats.is_ball(kinds[index]) and rope.touches(obstacle_ids[index]): return true
	return false

# 球的驱动与绳索硬约束共同求解：连续推进接触圆，长度耗尽时停在最后合法位置。
# 不把端点拉过障碍，不瞬移球或角色；这是有界运动驱动，非质量/弹性/摆荡物理。
func advance_threats(dt: float) -> Dictionary:
	var previous := {}
	for index in range(hazard_specs.size()):
		var spec: Dictionary = hazard_specs[index]
		if not spec.get("front", false): continue
		if distance < spec.get("start_distance", -INF): continue
		previous[index] = hazard_sample(index, elapsed).rect
		spec.blocked = false
		var move: Vector2 = spec.velocity * dt
		if not Threats.is_ball(kinds[index]):
			spec.offset += move
			spec.travel += move.length()
			continue
		var center: Vector2 = obstacles[index].get_center() + spec.offset
		var reach := LINK_LIMIT + obstacles[index].size.x * 0.5 + ROPE_CLEARANCE + 8.0
		# 任意合法绳点距端点不超过绳长；整条球运动胶囊都在两端可达域外时，不可能新接触。
		# 已有接触永不省略；靠近或跨过端点时仍逐单位推进并运行完整求解。
		if not rope.has_contact(obstacle_ids[index]) and Rope.segment_distance(center, center + move, a.position) > reach and Rope.segment_distance(center, center + move, b.position) > reach:
			spec.offset += move
			spec.travel += move.length()
			continue
		# 每个球内步最多 1 地面单位；把扫掠遇到的新接触连续提交，不能一步穿球后换绕行侧。
		var pieces := maxi(1, int(ceil(move.length())))
		for piece in range(pieces):
			var old: Vector2 = spec.offset
			var delta := move / pieces
			# 解析检测端点均未穿入的擦边接触，先提交中途接触点。最多少推进一个内步，
			# 该内步减少位移，随后继续按配置速度推进；不从接触前直接跳到接触后。
			var fraction := ball_contact_fraction(index, old, delta)
			delta *= fraction
			spec.offset = old + delta
			var circles := rope_circles()
			var length: float = rope.solve(a.position, b.position, ROPE_HEIGHT + heights[0], ROPE_HEIGHT + heights[1], circles, false)
			if length > LINK_LIMIT or not rope.solved_valid:
				var low := 0.0
				var high := 1.0
				for iteration in range(20):
					var middle := (low + high) * 0.5
					spec.offset = old + delta * middle
					if rope.solve(a.position, b.position, ROPE_HEIGHT + heights[0], ROPE_HEIGHT + heights[1], rope_circles(), false) <= LINK_LIMIT and rope.solved_valid: low = middle
					else: high = middle
				spec.offset = old + delta * low
				spec.blocked = true
				spec.travel += delta.length() * low
				rope.solve(a.position, b.position, ROPE_HEIGHT + heights[0], ROPE_HEIGHT + heights[1], rope_circles(), true)
				break
			spec.travel += delta.length()
			rope.solve(a.position, b.position, ROPE_HEIGHT + heights[0], ROPE_HEIGHT + heights[1], circles, true)
	return previous

func ball_contact_fraction(index: int, offset: Vector2, delta: Vector2) -> float:
	if rope.touches(obstacle_ids[index]): return 1.0
	var center := obstacles[index].get_center() + offset
	var radius := 0.0
	for circle in rope_circles():
		if circle.id == obstacle_ids[index]: radius = circle.radius - Rope.PENETRATION
	if radius <= 0: return 1.0
	var result := 1.0
	var z := rope.path_heights()
	for i in range(1, rope.path.size()):
		if minf(z[i - 1], z[i]) >= obstacle_heights[index]: continue
		# 普通端点已穿入由切线/弧段求解直接处理；此处专门捕获跨步擦入再离开。
		if Rope.segment_distance(rope.path[i - 1], rope.path[i], center + delta) < radius: continue
		result = minf(result, Threats.circle_contact_fraction(rope.path[i - 1], rope.path[i], center, center + delta, radius))
	return result

# 飞行物与绳段的三维相对连续扫掠；运动前后挂点高度参与检测。
func front_rope_hits(index: int, previous: Rect2, current: Rect2, old_path: PackedVector2Array, old_z: PackedFloat32Array) -> bool:
	var spec: Dictionary = hazard_specs[index]
	var c0 := previous.get_center()
	var c1 := current.get_center()
	var new_path: PackedVector2Array = rope.path
	var new_z: PackedFloat32Array = rope.path_heights()
	var old_f := path_fractions(old_path)
	var new_f := path_fractions(new_path)
	var cuts: Array = old_f.duplicate()
	for fraction in new_f:
		if not cuts.has(fraction): cuts.append(fraction)
	cuts.sort()
	for i in range(cuts.size() - 1):
		var first := path_at(old_path, old_z, old_f, cuts[i]) - Vector3(c0.x, c0.y, 0)
		var last := path_at(old_path, old_z, old_f, cuts[i + 1]) - Vector3(c0.x, c0.y, 0)
		var next_first := path_at(new_path, new_z, new_f, cuts[i]) - Vector3(c1.x, c1.y, 0)
		var next_last := path_at(new_path, new_z, new_f, cuts[i + 1]) - Vector3(c1.x, c1.y, 0)
		if Threats.rope_box_sweep(first, last, next_first, next_last, Vector3(-previous.size.x / 2, -previous.size.y / 2, spec.bottom), Vector3(previous.size.x / 2, previous.size.y / 2, obstacle_heights[index])): return true
	return false

static func path_fractions(points: PackedVector2Array) -> Array:
	var result: Array = [0.0]
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
		result.append(total)
	for i in range(1, result.size()): result[i] = result[i] / maxf(total, 0.000001)
	return result

static func path_at(points: PackedVector2Array, z: PackedFloat32Array, fractions: Array, t: float) -> Vector3:
	for i in range(1, points.size()):
		if t > fractions[i]: continue
		var part := clampf((t - fractions[i - 1]) / maxf(fractions[i] - fractions[i - 1], 0.000001), 0, 1)
		var p := points[i - 1].lerp(points[i], part)
		return Vector3(p.x, p.y, lerpf(z[i - 1], z[i], part))
	var last := points.size() - 1
	return Vector3(points[last].x, points[last].y, z[last])

func assign_obstacle_ids() -> void:
	# 测试夹具或外部直接改写障碍列表时补齐标识。
	if obstacle_ids.size() == obstacles.size(): return
	obstacle_ids.clear()
	for index in range(obstacles.size()):
		obstacle_ids.append(next_obstacle_id)
		next_obstacle_id += 1

# 可能挂住绳索的圆柱：圆心取碰撞盒中心，半径含绳索与表面的间隙。只取绳长可及范围内的。
func rope_circles() -> Array:
	assign_obstacle_ids()
	var result: Array = []
	for index in range(obstacles.size()):
		if not kinds[index] in ROPE_BLOCKERS: continue
		var center: Vector2 = hazard_sample(index, elapsed).rect.get_center()
		var radius := obstacles[index].size.x * 0.5 + ROPE_CLEARANCE
		if Threats.is_ball(kinds[index]):
			# 球体在绳段实际高度区间内的最大水平截面；随独立跳跃同步变化。
			var sphere := obstacles[index].size.x * 0.5
			var near_height := clampf(sphere, minf(ROPE_HEIGHT + heights[0], ROPE_HEIGHT + heights[1]), maxf(ROPE_HEIGHT + heights[0], ROPE_HEIGHT + heights[1]))
			radius = sqrt(maxf(0, sphere * sphere - pow(near_height - sphere, 2))) + ROPE_CLEARANCE
		if rope.has_contact(obstacle_ids[index]) or minf(center.distance_to(a.position), center.distance_to(b.position)) <= LINK_LIMIT + radius + 8.0:
			var bottom: float = hazard_specs[index].get("bottom", 0.0) if index < hazard_specs.size() else 0.0
			var circle := {"id": obstacle_ids[index], "center": center, "radius": radius, "top": obstacle_heights[index], "bottom": bottom}
			if Threats.is_ball(kinds[index]): circle.max_radius = obstacles[index].size.x * 0.5 + ROPE_CLEARANCE
			result.append(circle)
	return result

func rope_tension() -> float:
	return rope.required / LINK_LIMIT

func rope_block_time() -> float:
	return rope_block_substeps * FIXED_STEP / 3.0

# 界面反馈用的绳索状态：failed / unwinding / blocked / contact / taut / free。
func rope_status() -> String:
	if rope_failed: return "failed"
	if rope_bound: return "unwinding" if rope_unwinding else "blocked"
	if rope.touching() > 0: return "contact"
	return "taut" if rope.required > LINK_LIMIT * 0.85 else "free"

func update_stream() -> void:
	assign_obstacle_ids()
	if distance >= 6000:
		var shift := 4800.0
		distance -= shift
		a.position.y -= shift
		b.position.y -= shift
		world_origin += shift
		for gate in charge_gates: ChargeGate.relocate(gate, -shift)
		for i in range(obstacles.size()): obstacles[i].position.y -= shift
		for reward in rewards: reward.position.y -= shift
		for spec in hazard_specs:
			if spec.has("start_distance"): spec.start_distance -= shift
		rope.shift(Vector2(0, -shift))
		rebases += 1
		revision += 1
	for i in range(obstacles.size() - 1, -1, -1):
		var sample := hazard_sample(i, elapsed)
		# 巨锤暂时抬起或转离后，仍可能扫回道路；回收必须覆盖完整包络。
		var rear_extent: float = sample.envelope.end.y if kinds[i] == "hammer" else sample.rect.end.y
		if rear_extent < distance - Templates.BEHIND and not rope.has_contact(obstacle_ids[i]):
			obstacles.remove_at(i)
			obstacle_ids.remove_at(i)
			kinds.remove_at(i)
			obstacle_heights.remove_at(i)
			hazard_specs.remove_at(i)
			recycled += 1
			revision += 1
	for i in range(rewards.size() - 1, -1, -1):
		if rewards[i].position.y < distance - Templates.BEHIND:
			rewards.remove_at(i)
			revision += 1
	# 双方越过门后空间才回收；保留尚未到达的预加载机关。
	for i in range(charge_gates.size() - 1, -1, -1):
		var gate: Dictionary = charge_gates[i]
		if gate.open and gate.get("kind", "charge") == "sync_plates":
			SyncPlates.advance(gate, a.position, b.position,
				ground_support[0] and heights[0] == 0.0 and vertical_speed[0] == 0.0,
				ground_support[1] and heights[1] == 0.0 and vertical_speed[1] == 0.0, 0.0)
		if gate.open and gate.door.end.y < minf(a.position.y, b.position.y) - Templates.BEHIND:
			gate_events.append({"id": gate.id, "event": "recycled", "distance": total_distance()})
			charge_gates.remove_at(i)
	select_charge_gate()
	# 教学完成前不安装随机危险；证明已由独立克隆在教学期间分帧预计算。
	while generation_enabled and not generation_halted and not (charge_gate.active and not charge_gate.open) and Templates.START_DISTANCE + next_segment * Templates.SEGMENT < minf(total_distance() + (ASYNC_AHEAD if async_enabled else Templates.AHEAD), finish_distance() - Templates.SEGMENT):
		var base := Templates.START_DISTANCE + next_segment * Templates.SEGMENT - world_origin
		if async_enabled:
			if schedule_generation(base): continue
			break
		var block: Dictionary = block_history[next_segment].duplicate(true) if block_history.has(next_segment) else generator.generate_block(next_segment, difficulty, level_index, self, base)
		if block.is_empty():
			generation_halted = true
			fail_threat("安全段落验证失败，请重试")
			return
		install_block(block, base, "%d:%d" % [level_index, next_segment])
		block_history[next_segment] = block.duplicate(true)
		route_segments.append({"number": next_segment, "base": base + world_origin, "block": block})
		next_segment += 1
		revision += 1
	for i in range(kinds.size()):
		if kinds[i].begins_with("fly_") and not hazard_specs[i].get("front", false) and hazard_specs[i].trigger < 0 and obstacles[i].position.y - distance <= speed() * 2:
			hazard_specs[i].trigger = elapsed + Templates.DIFFICULTIES[difficulty].warning
	while not route_segments.is_empty() and route_segments[0].base + Templates.SEGMENT < total_distance() - Templates.BEHIND:
		route_segments.pop_front()

func install_block(block: Dictionary, base: float, prefix: String) -> void:
	var gates: Array = [block.gate] if block.has("gate") else block.get("gates", [])
	for slot in range(gates.size()):
		var id := prefix + ":gate" if block.has("gate") else "%s:gate:%d" % [prefix, slot]
		if not charge_gates.any(func(gate): return gate.id == id) and not gate_events.any(func(event): return event.event == "installed" and event.id == id):
			var gate: Dictionary = gates[slot].duplicate(true)
			ChargeGate.relocate(gate, base)
			gate.id = id
			charge_gates.append(gate)
			gate_events.append({"id": id, "event": "installed", "distance": total_distance()})
			select_charge_gate()
	for hazard in block.hazards:
		var rect: Rect2 = hazard.rect
		rect.position.y += base
		var kind: String = hazard.kind
		obstacles.append(rect)
		obstacle_ids.append(next_obstacle_id)
		next_obstacle_id += 1
		kinds.append(kind)
		obstacle_heights.append(Threats.CONFIG[kind].top if Threats.CONFIG.has(kind) else (SURFACE_TOPS[kind] if SURFACE_TOPS.has(kind) else HAZARD_TOPS[kind]))
		var spec: Dictionary = Threats.spec(kind, Templates.DIFFICULTIES[difficulty].front_warning) if Threats.CONFIG.has(kind) else {"bottom": HAZARD_BOTTOMS.get(kind, 0.0)}
		if kind in Industrial.KINDS:
			spec = Industrial.spec(kind, hazard.get("side", 1.0), base)
			spec.phase = hazard.get("phase", 0.0)
			if kind == "forklift":
				# 矿车按关速掐点出发：全速前进的两人刚通过它才冲到通道，慢一拍就会被撞上。
				spec.warning = maxf(0.8, (rect.end.y - base + 24.0) / (level_speed() if streaming else FORWARD) - 0.85)
			if kind == "collapse":
				# 最大地面绳长覆盖后方玩家及完整绳段，正常前进不依赖绳索承重。
				spec.grace = (rect.size.y + Motion.RADIUS * 2 + LINK_LIMIT) / (level_speed() if streaming else FORWARD) + 0.35
		if kind == "sweeper":
			spec.phase = hazard.get("phase", 0.0)
			spec.angular_speed = hazard.get("angular_speed", Surfaces.ANGULAR_SPEED)
		if hazard.get("filler", false): spec.filler = true
		if hazard.get("extra", false): spec.extra = true
		if kind == "active_spikes":
			spec.phase = hazard.get("phase", 0.0)
			spec.warning = Templates.DIFFICULTIES[difficulty].warning
		if hazard.get("timed_launch", false):
			# 以当前关速重算迎面起点，给最前角色保留 5 米前后调节余量。
			obstacles[-1].position.y = base + (speed() - spec.velocity.y) * (spec.warning + 0.05) + RELATIVE_RANGE + Motion.RADIUS
		# 提前加载时保持可见；段落入口开始运动，避免加载距离改变迎面组合时序。
		if spec.get("front", false): spec.start_distance = base
		hazard_specs.append(spec)
	for slot in range(block.rewards.size()):
		var entry: Dictionary = block.rewards[slot].duplicate(true)
		entry.position += Vector2(0, base)
		entry.id = "%s:%d" % [prefix, slot]
		entry.claimed = false
		rewards.append(entry)

# 高度分类：只有贴地且顶部低于跳跃最高点的危险可以跳过，其余必须绕行。
static func jump_clearable(kind: String) -> bool:
	if kind in Industrial.KINDS: return false
	# 缺口以实际跳程和完整支撑判定，不把高度为零当成任意缺口都可跳。
	if kind == "road_gap": return false
	if kind == "sweeper": return Surfaces.POST_TOP < JUMP_APEX
	if Threats.CONFIG.has(kind): return Threats.CONFIG[kind].bottom == 0.0 and Threats.CONFIG[kind].top < JUMP_APEX
	return HAZARD_BOTTOMS.get(kind, 0.0) == 0.0 and HAZARD_TOPS[kind] < JUMP_APEX

static func hazard_name(kind: String) -> String:
	if kind == "hammer": return "摆锤：锤头、柄、支架均须避让"
	if kind == "collapse": return "碎裂石板：裂开后快速通过，绳索不承重"
	if kind == "steam": return "地火喷口：共同绕行，连线须离开喷口"
	if kind == "drone": return "俯冲岩鹰：固定斜向轨迹与高度"
	if kind == "forklift": return "横冲矿车：车体、撞角和矿石均须避让"
	if kind == "press": return "落石闸：下压、停留、回升均须避让"
	if kind == "sweeper": return "旋转扫杆：低杆可跳，支座须绕行"
	if kind == "road_gap": return "断崖缺口：跳过或同侧绕行，绳索不承重"
	if kind == "rocket": return "弩箭：两人同侧避让"
	if kind == "stone_ball": return "滚石：两人同侧避让"
	if kind == "iron_ball": return "铁刺球：两人同侧避让"
	return {"pillar": "高柱：两人同侧绕行", "cargo": "巨岩：左右绕行", "rail": "矮石栏：跳跃或绕行", "spikes": "固定地刺：跳跃或绕行", "active_spikes": "活动地刺：伸出期间跳跃或绕行", "scanner": "高位扫描束：绕行或等待安全时窗", "fly_low": "低空飞石：跳跃或绕行", "fly_body": "飞石：四向避让", "fly_tall": "高大飞行物：四向避让"}.get(kind, "能量屏障")

# 仅消费最后一次生产子步的条件；暂停冻结、重试和实例重建自然保留或清空提示。
# 侧别由生产条件给出，与角色编号无关；HUD 和主题共用这份反馈。
func gate_side_feedback(gate: Dictionary) -> Array[Dictionary]:
	var result: Dictionary = gate.get("conditions", {})
	var plates: bool = gate.get("kind", "charge") == "sync_plates"
	var present: Array = result.get("side_present", [false, false])
	var occupied: Array = result.get("occupied", [false, false])
	var airborne: Array = result.get("airborne", [false, false])
	var feedback: Array[Dictionary] = []
	for side in range(2):
		var state := "missing"
		var text := "未占板" if plates else "未到位"
		if gate.get("open", false):
			state = "opened"
			text = "通路已开启"
		elif plates:
			if occupied[side]:
				state = "holding" if result.get("ready", false) else "standing"
				text = "持续站稳" if state == "holding" else "已落地 · 等待另一板"
			elif airborne[side]:
				state = "airborne"
				text = "腾空 · 请落地"
		elif present[side]:
			state = "positioned"
			text = "已到位"
		feedback.append({"state": state, "text": ("左" if side == 0 else "右") + ("板：" if plates else "绿区：") + text})
	return feedback

func gate_hint(gate: Dictionary) -> String:
	if not gate.get("active", false): return ""
	var plates: bool = gate.get("kind", "charge") == "sync_plates"
	var heading := "同步踏板" if plates else "双人充能"
	var text := ""
	if gate.open:
		text = "%s通路已开启 · 共同前进" % heading
	else:
		var result: Dictionary = gate.get("conditions", {})
		var duration: float = SyncPlates.HOLD_TIME if plates else ChargeGate.CHARGE_TIME
		var missing: Array[String] = []
		for side in gate_side_feedback(gate): missing.append(side.text)
		if plates:
			var grounded: Array = result.get("grounded", [true, true])
			if not grounded[0] or not grounded[1]: missing.append("两人先落地")
			var occupied: Array = result.get("occupied", [false, false])
			if not occupied[0] or not occupied[1]: missing.append("左右各站一板 · 可交换角色")
			if result.get("ready", false): missing.append("持续站稳 %.2f 秒" % duration)
		else:
			if not result.get("positioned", false): missing.append("分别站左右绿区（道路外侧） · 可交换角色")
			if not result.get("taut", false):
				missing.append("张紧不足：两人向外拉开 · 绳 %.1f/%.1fm" % [rope.required / 20.0, LINK_LIMIT * ChargeGate.TENSION / 20.0])
			if not result.get("clear", true): missing.append("绳路受阻 · 回撤调整")
			if not result.get("crosses", false):
				missing.append("让绳路穿过中心接收器")
			elif not result.get("at_height", false): missing.append("绳路高度需对准接收器 · 落地调整")
			if result.get("ready", false): missing.append("持续充能 %.1f 秒" % duration)
		var recovery := "可安全等待 · 可回撤调整"
		if not plates and not result.get("clear", true): recovery = "绳路受阻时请及时回撤调整"
		text = "%s %d%% · %.2f/%.2f 秒\n%s\n%s" % [heading,
			int(gate.charge / duration * 100), gate.charge, duration, " · ".join(missing), recovery]
	if gate.has("relay_index"):
		text = "接力 %d/%d · %s\n%s" % [gate.relay_index + 1, gate.relay_count, "踏板" if plates else "充能", text]
	return text

func select_charge_gate() -> void:
	charge_gate = {"active": false, "open": false, "charge": 0.0}
	for gate in charge_gates:
		if not gate.open and (not charge_gate.active or gate.receiver.y < charge_gate.receiver.y): charge_gate = gate
	if not charge_gate.active and not charge_gates.is_empty(): charge_gate = charge_gates.back()

func hazard_sample(index: int, time: float) -> Dictionary:
	var spec: Dictionary = hazard_specs[index] if index < hazard_specs.size() else {}
	var kind: String = kinds[index]
	var rect: Rect2 = obstacles[index]
	var bottom: float = spec.get("bottom", 0.0)
	var top: float = obstacle_heights[index]
	var active := true
	var warning := false
	var stage := "active"
	if kind in Industrial.KINDS: return Industrial.sample(kind, rect, spec, time)
	if kind == "sweeper":
		var geometry := Surfaces.sweeper(rect.get_center(), time, spec)
		return {"rect": rect, "bottom": 0.0, "top": Surfaces.ARM_TOP, "active": true, "warning": rect.position.y - maxf(a.position.y, b.position.y) <= speed() * 2.4, "stage": "rotate", "geometry": geometry}
	if kind == "road_gap":
		return {"rect": rect, "bottom": 0.0, "top": 0.0, "active": false, "warning": true, "stage": "unsupported"}
	if spec.get("front", false):
		rect.position += spec.offset
		var closing: float = (speed() if streaming else FORWARD) - spec.velocity.y
		var ttc := maxf(0, (rect.position.y - Motion.RADIUS - maxf(a.position.y, b.position.y)) / closing)
		warning = spec.locked and rect.end.y >= minf(a.position.y, b.position.y)
		return {"rect": rect, "bottom": bottom, "top": top, "active": true, "warning": warning, "stage": "warning" if warning else "active", "ttc": ttc}
	if kind in ["active_spikes", "scanner"]:
		var cycle := fposmod(time + float(spec.get("phase", 0)), float(spec.get("period", 4)))
		var warn: float = spec.get("warning", 1.0)
		var duration: float = spec.get("active", 1.5)
		warning = cycle < warn
		active = cycle >= warn and cycle < warn + duration
		stage = "warning" if warning else ("active" if active else "safe")
		if kind == "active_spikes":
			var extension := clampf((cycle - warn) / 0.25, 0, 1) * clampf((warn + duration - cycle) / 0.25, 0, 1)
			top *= extension
			stage = "extend" if active and cycle < warn + 0.25 else ("retract" if active and cycle > warn + duration - 0.25 else stage)
	if kind.begins_with("fly_"):
		var trigger: float = spec.get("trigger", 0)
		var duration: float = spec.get("flight_duration", 1)
		var velocity: Vector2 = spec.get("velocity", Vector2.ZERO)
		warning = trigger >= 0 and time >= trigger - float(spec.get("warning", 1.0)) and time < trigger
		active = trigger >= 0 and time >= trigger and time <= trigger + duration
		if trigger >= 0: rect.position += velocity * clampf(time - trigger, 0, duration)
		stage = "warning" if warning else ("active" if active else "safe")
	return {"rect": rect, "bottom": bottom, "top": top, "active": active, "warning": warning, "stage": stage}

# 将地面扫掠与高度区间在同一时间参数上求交，避免高速穿越和落地漏判。
static func swept_body_hits(from: Vector2, to: Vector2, h0: float, h1: float, rect: Rect2, bottom: float, top: float) -> bool:
	var origin := Vector3(from.x, from.y, h0)
	var end := Vector3(to.x, to.y, h1)
	var minimum := Vector3(rect.position.x, rect.position.y, bottom - BODY_HEIGHT)
	var maximum := Vector3(rect.end.x, rect.end.y, top)
	var low := 0.0
	var high := 1.0
	for axis in range(3):
		var d := end[axis] - origin[axis]
		if absf(d) < 0.000001:
			if origin[axis] < minimum[axis] or origin[axis] > maximum[axis]: return false
		else:
			var first := (minimum[axis] - origin[axis]) / d
			var last := (maximum[axis] - origin[axis]) / d
			low = maxf(low, minf(first, last))
			high = minf(high, maxf(first, last))
			if low > high: return false
	return true

# 在激活、失活及高度斜率改变处切段；每段六个边界都共享时间参数。
func timed_hazard_hits(index: int, start: float, end: float, from: Vector2, to: Vector2, h0: float, h1: float) -> bool:
	if kinds[index] == "road_gap": return false
	if kinds[index] == "sweeper":
		return Surfaces.body_hits(obstacles[index].get_center(), hazard_specs[index], start, end, from, to, h0, h1, Motion.RADIUS)
	var cuts: Array[float] = [start, end]
	var spec: Dictionary = hazard_specs[index] if index < hazard_specs.size() else {}
	var kind: String = kinds[index]
	if kind in ROPE_BLOCKERS:
		# 圆柱：先用含高度的包围盒扫掠，再按圆形截面精确判定。
		var pillar: Rect2 = obstacles[index]
		return swept_body_hits(from, to, h0, h1, pillar.grow(Motion.RADIUS), spec.get("bottom", 0.0), obstacle_heights[index]) and Rope.segment_distance(from, to, pillar.get_center()) <= pillar.size.x * 0.5 + Motion.RADIUS
	if kind in ["active_spikes", "scanner"]:
		var period: float = spec.get("period", 4.0)
		var phase: float = spec.get("phase", 0.0)
		var warning: float = spec.get("warning", 1.0)
		var active: float = spec.get("active", 1.5)
		for cycle in range(int(floor((start + phase) / period)), int(floor((end + phase) / period)) + 1):
			for offset in [0.0, warning, warning + 0.25, warning + active - 0.25, warning + active, period]:
				var boundary: float = cycle * period - phase + offset
				if boundary > start and boundary < end: cuts.append(boundary)
	elif kind.begins_with("fly_"):
		var trigger: float = spec.get("trigger", 0.0)
		for boundary in [trigger, trigger + float(spec.get("flight_duration", 1.0))]:
			if boundary > start and boundary < end: cuts.append(boundary)
	cuts.sort()
	for part in range(cuts.size() - 1):
		var left := cuts[part]
		var right := cuts[part + 1]
		if right <= left or not hazard_sample(index, (left + right) * 0.5).active: continue
		var first := hazard_sample(index, left)
		var last := hazard_sample(index, right)
		var t0 := (left - start) / (end - start)
		var t1 := (right - start) / (end - start)
		var p0 := from.lerp(to, t0)
		var p1 := from.lerp(to, t1)
		var z0 := lerpf(h0, h1, t0)
		var z1 := lerpf(h0, h1, t1)
		var r0: Rect2 = first.rect.grow(Motion.RADIUS)
		var r1: Rect2 = last.rect.grow(Motion.RADIUS)
		# 各距离 >= 0 时角色位于危险体内；线性不等式区间求交。
		var d0 := [p0.x - r0.position.x, r0.end.x - p0.x, p0.y - r0.position.y, r0.end.y - p0.y, z0 + BODY_HEIGHT - first.bottom, first.top - z0]
		var d1 := [p1.x - r1.position.x, r1.end.x - p1.x, p1.y - r1.position.y, r1.end.y - p1.y, z1 + BODY_HEIGHT - last.bottom, last.top - z1]
		var low := 0.0
		var high := 1.0
		for axis in range(6):
			var delta: float = d1[axis] - d0[axis]
			if delta == 0.0:
				if d0[axis] < 0: high = -1.0
			elif delta > 0:
				low = maxf(low, -float(d0[axis]) / delta)
			else:
				high = minf(high, -float(d0[axis]) / delta)
		if low <= high:
			if low == high and ((low == 0 and not first.active) or (low == 1 and not last.active)): continue
			return true
	return false

func ground_gaps(time: float = -1.0) -> Array[Rect2]:
	var gaps: Array[Rect2] = []
	for i in range(kinds.size()):
		if kinds[i] == "road_gap": gaps.append(obstacles[i])
		if kinds[i] == "collapse" and hazard_sample(i, elapsed if time < 0 else time).stage == "collapsed": gaps.append(obstacles[i])
	return gaps

# 独木窄桥桥面中线 x；不在桥上返回 NAN。桥两侧为同一 y 区间、长度为 NARROW_LENGTH 的一对缺口。
func plank_center(point: Vector2) -> float:
	var left := -INF
	var right := INF
	for i in range(kinds.size()):
		if kinds[i] != "road_gap": continue
		var gap: Rect2 = obstacles[i]
		if gap.size.y < Templates.NARROW_LENGTH - 0.01 or point.y < gap.position.y - Motion.RADIUS or point.y > gap.end.y + Motion.RADIUS: continue
		if gap.end.x <= point.x + 0.01: left = maxf(left, gap.end.x)
		elif gap.position.x >= point.x - 0.01: right = minf(right, gap.position.x)
	if left == -INF or right == INF or right - left > Templates.NARROW_PLANK * 2.0: return NAN
	return (left + right) * 0.5

# 桥上横向移动放慢，松开横向键时自动回正到桥中线，减少轻点方向键就滑下桥。
func plank_assist(point: Vector2, input: Vector2) -> Vector2:
	var center := plank_center(point)
	if is_nan(center): return input
	if absf(input.x) > 0.01:
		input.x *= PLANK_LATERAL
	else:
		input.x = clampf((center - point.x) / (LATERAL * FIXED_STEP), -PLANK_CENTERING, PLANK_CENTERING)
	return input

func has_ground_support(point: Vector2, time: float = -1.0) -> bool:
	return absf(point.x) <= EDGE + 0.00001 and Surfaces.supported(point, Motion.RADIUS, ground_gaps(time))

func ground_sweep_supported(from: Vector2, to: Vector2, time: float = -1.0) -> bool:
	# 圆形脚底与矩形缺口的精确胶囊相交；每条边和内部均参与检测。
	for gap in ground_gaps(time):
		if gap.has_point(from) or gap.has_point(to): return false
		var corners := [gap.position, Vector2(gap.end.x, gap.position.y), gap.end, Vector2(gap.position.x, gap.end.y)]
		for i in range(4):
			if Surfaces.segments_distance(from, to, corners[i], corners[(i + 1) % 4]) < Motion.RADIUS - 0.00001: return false
	return true

func sweeper_rope_hits(index: int, start: float, end: float, old_path: PackedVector2Array, old_z: PackedFloat32Array) -> bool:
	var center := obstacles[index].get_center()
	# 旧/新真实绕障绳段及高度，旋转期间的连续包络包括绳段移动余量。
	var current_z := rope.path_heights()
	var movement_margin := 0.0
	if old_path.size() == rope.path.size():
		for n in range(old_path.size()): movement_margin = maxf(movement_margin, old_path[n].distance_to(rope.path[n]))
	else:
		movement_margin = (speed() + LATERAL) * (end - start)
	for pass_index in range(2):
		var path: PackedVector2Array = old_path if pass_index == 0 else rope.path
		var z: PackedFloat32Array = old_z if pass_index == 0 else current_z
		# 高度变化的连续余量不能使低于当前绳高的结构漏判。
		var conservative_z := z.duplicate()
		if old_z.size() == current_z.size():
			for n in range(conservative_z.size()): conservative_z[n] = minf(old_z[n], current_z[n])
		if Surfaces.rope_hits(center, hazard_specs[index], start, end, path, conservative_z, movement_margin): return true
	return false

# floor 为该角色本子步允许的最低纵向位置；只有被巨岩挡在后边界之后的人才低于后边界。
func bounded(p: Vector2, floor: float = INF) -> Vector2:
	var rear := minf(rear_bound(), floor)
	return Vector2(clampf(p.x, -EDGE - FALL_REACH, EDGE + FALL_REACH), clampf(p.y, rear, distance + RELATIVE_RANGE))

func rear_bound() -> float:
	return distance - RELATIVE_RANGE if world_origin > 0 else maxf(0, distance - RELATIVE_RANGE)

# 巨岩实心阻挡：沿面滑行，挡死时原地不动，不伤人也不冻结道路。
func cargo_clear(from: Vector2, to: Vector2, h0: float, h1: float) -> bool:
	for index in range(kinds.size()):
		if kinds[index] == "cargo" and solid_sweep_hits(index, from, to, h0, h1): return false
	return true

func resolve_cargo(from: Vector2, to: Vector2, h0: float, h1: float) -> Vector2:
	if cargo_clear(from, to, h0, h1): return to
	for candidate in [Vector2(to.x, from.y), Vector2(from.x, to.y)]:
		if cargo_clear(from, candidate, h0, h1): return candidate
	return from

static func segment_hits(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	var low := 0.0
	var high := 1.0
	for axis in range(2):
		var d := to[axis] - from[axis]
		if absf(d) < 0.000001:
			if from[axis] < rect.position[axis] or from[axis] > rect.end[axis]:
				return false
		else:
			var first := (rect.position[axis] - from[axis]) / d
			var last := (rect.end[axis] - from[axis]) / d
			low = maxf(low, minf(first, last))
			high = minf(high, maxf(first, last))
			if low > high:
				return false
	return true
