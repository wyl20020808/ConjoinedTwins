extends RefCounted

const SEGMENT := 840.0
# 一段预加载已覆盖最高关速的共同预警；避免每次同步重演四段造成长停顿。
const AHEAD := 840.0
const BEHIND := 240.0
const MAX_HAZARDS := 32
const MAX_SCENE_NODES := 6000
const START_DISTANCE := 500.0
const NEW_KINDS := ["sweeper", "road_gap", "drone", "forklift", "press", "hammer", "collapse", "steam"]
const COMBINATIONS := {"pillar_press": ["pillar", "press"], "low_steam": ["fly_low", "steam"]}
# 横排巨岩：每段在主障碍所在位置把路面横向封死，只留下 open 里的区间（按 side=+1 书写，另一侧镜像）。
# 留空的是主障碍自身占的位置和合法通道；迎面物用 depth 较长的岩墙夹出一条峡谷，不能提前或推后侧身躲开。
# 通道左右随段落随机，跳跃段只留中间，所以一直贴着某一侧路边走必然撞墙。
# 路面半宽（20 单位/米），road_run.EDGE 直接引用此值。加宽后开口仍按原 10.5 米路面的合法通道书写，
# 原本通到路边的开口改为通到新路边；新增宽度只在开口外由巨岩补齐，不改变已验证主障碍的通过方式。
const ROAD_HALF_WIDTH := 320.0
# 窄桥：桥面宽 2 米，扣除碰撞半径后中心只有 ±0.4 米可站，两人身体互不穿透，只能前后单列。
# 桥长 22 米，超过最高关速下“前后调节 10 米 + 0.6 秒腾空”的最大跳程，不能并排跳过两侧断崖。
const NARROW_PLANK := 40.0
const NARROW_START := 150.0
const NARROW_LENGTH := 440.0
const NARROW_SPACING := 40.0
const ROWS := {
	"left": {"y": 290, "depth": 65, "open": [[-45, 180]]}, "right": {"y": 290, "depth": 65, "open": [[-45, 180]]},
	"stagger": {"y": 290, "depth": 65, "open": [[-45, 180]]},
	"pillar": {"y": 280, "depth": 50, "open": [[-180, 180]]},
	"low_jump": {"y": 250, "depth": 350, "open": [[-70, 70]]},
	"stone_ball": {"y": 250, "depth": 370, "open": [[-52, 180]]}, "ball": {"y": 250, "depth": 370, "open": [[-52, 180]]},
	"body": {"y": 250, "depth": 370, "open": [[-52, 180]]}, "rocket": {"y": 250, "depth": 370, "open": [[-52, 180]]},
	"double": {"y": 250, "depth": 370, "open": [[-52, 180]]},
	"sweep_bypass": {"y": 290, "depth": 50, "open": [[-40, 180]]}, "sweep_single": {"y": 290, "depth": 50, "open": [[-40, 120]]},
	"sweep_double": {"y": 290, "depth": 50, "open": [[-55, 55]]},
	"gap_bypass": {"y": 290, "depth": 50, "open": [[-80, 200]]}, "gap_single": {"y": 290, "depth": 50, "open": [[-80, 80]]},
	"gap_double": {"y": 290, "depth": 50, "open": [[-80, 80]]}, "gap_long": {"y": 300, "depth": 60, "open": [[-80, ROAD_HALF_WIDTH]]},
	"collapse": {"y": 525, "depth": 50, "open": [[-80, ROAD_HALF_WIDTH]]}, "steam": {"y": 555, "depth": 50, "open": [[-60, ROAD_HALF_WIDTH]]},
	"drone": {"y": 250, "depth": 350, "open": [[-62, ROAD_HALF_WIDTH]]}, "press": {"y": 560, "depth": 50, "open": [[-100, ROAD_HALF_WIDTH]]},
	# 摆锤与矿车原先靠路边封住外侧；加宽后用巨岩补上，不能从新增路面绕过整个摆幅或矿车起点。
	"hammer": {"y": 420, "depth": 56, "open": [[-215, 240]]}, "forklift": {"y": 570, "depth": 68, "open": [[-215, ROAD_HALF_WIDTH]]}}
const DIFFICULTIES := {
	"简单": {"speed": 250.0, "cap": 250.0, "density": 1, "density_cap": 2, "fly_frequency": 0.15, "fly_cap": 0.25, "warning": 1.5, "front_warning": 1.9, "complexity": 1},
	"普通": {"speed": 295.0, "cap": 295.0, "density": 2, "density_cap": 3, "fly_frequency": 0.3, "fly_cap": 0.4, "warning": 1.25, "front_warning": 1.6, "complexity": 2},
	"困难": {"speed": 330.0, "cap": 330.0, "density": 3, "density_cap": 3, "fly_frequency": 0.45, "fly_cap": 0.55, "warning": 1.0, "front_warning": 1.4, "complexity": 3}}

const Threats = preload("res://scripts/dynamic_threats.gd")
const Surfaces = preload("res://scripts/road_surfaces.gd")
const ChargeGate = preload("res://scripts/road_charge_gate.gd")
const SyncPlates = preload("res://scripts/road_sync_plates.gd")
# 保留历史测试的常量接口；当前生成不再按此间隔调度。
const PILLAR_EVERY := 4
const ROUTES := ["left", "right", "jump", "pillar", "ball", "low_jump", "stagger", "double"]
# 独立身体高度教学和两种球先在第二关出现，双威胁只在第三关出现。
const LEVEL_ROUTES := [
	["stone_ball", "rocket", "hammer", "body", "collapse", "steam", "drone", "forklift", "press", "ball", "sweep_bypass", "gap_bypass", "double", "sweep_single", "gap_single", "stagger", "sweep_double", "gap_double", "rocket", "gap_long", "pillar", "low_jump", "jump", "ball", "left", "right", "body", "double", "narrow", "narrow"],
	["stone_ball", "ball", "rocket", "body", "hammer", "collapse", "steam", "drone", "forklift", "press", "sweep_bypass", "gap_bypass", "pillar", "low_jump", "jump", "stagger", "sweep_single", "gap_single", "sweep_double", "gap_double", "gap_long", "left", "right", "narrow", "narrow"],
	["stone_ball", "ball", "rocket", "body", "hammer", "collapse", "steam", "drone", "forklift", "press", "sweep_bypass", "gap_bypass", "pillar", "low_jump", "jump", "stagger", "double", "sweep_single", "gap_single", "sweep_double", "gap_double", "gap_long", "left", "right", "narrow", "narrow"]]
# 一个生产固定步的最大轴向手动位移；段尾只允许正常按键步距残差。
const MANUAL_SPEED := 300.0
const FIXED_STEP := 1.0 / 120.0
const KEYBOARD_STEP := MANUAL_SPEED * FIXED_STEP
const EXIT_TOLERANCE := KEYBOARD_STEP + 0.01
var rng := RandomNumberGenerator.new()
var rejected := 0
var fallbacks := 0
var last_evidence := {}
var rejection_evidence: Array = []
var verified := {}
var source_override := ""
var cancellation = null
# 段落抽签袋：每关的段落种类洗牌后依次抽出，抽完再洗；相邻两段不重复同一种。
var bag: Array = []
var bag_level := -1
var last_kind := ""
static var binding_stamp := ""
static var binding_value := ""

# 线程唯一共享对象只负责取消，所有访问均在 Mutex 内。
class Cancellation extends RefCounted:
	var mutex := Mutex.new()
	var canceled := false
	func cancel() -> void:
		mutex.lock()
		canceled = true
		mutex.unlock()
	func is_canceled() -> bool:
		mutex.lock()
		var value := canceled
		mutex.unlock()
		return value

func binding() -> String:
	return source_override if not source_override.is_empty() else source_binding()

func canceled() -> bool:
	return cancellation != null and cancellation.is_canceled()

func reset(seed_value: int) -> void:
	rng.seed = seed_value
	rejected = 0
	fallbacks = 0
	last_evidence = {}
	rejection_evidence.clear()
	bag.clear()
	bag_level = -1
	last_kind = ""

# 每段从中央进入并返回中央。段落种类按种子洗牌抽取，每局顺序都不同；左右、机关相位和奖励也随机。
func candidate_block(number: int, level: int) -> Dictionary:
	if bag.is_empty() or bag_level != level:
		bag = LEVEL_ROUTES[level].duplicate()
		bag.append("charge_cargo")
		bag.append("sync_cargo")
		bag.append("charge_sync_relay")
		bag_level = level
		# 用自己的随机数洗牌，同一种子可复现；Array.shuffle 用全局随机数，不可复现。
		for i in range(bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var held = bag[i]
			bag[i] = bag[j]
			bag[j] = held
		if bag.size() > 1 and bag.back() == last_kind:
			var held = bag[0]
			bag[0] = bag.back()
			bag[bag.size() - 1] = held
		# 有限关卡未必抽完整袋；教学之后的前八段内必有一次踏板合作。
		var plates_index := bag.find("sync_cargo")
		if plates_index < bag.size() - 8:
			var early_index := rng.randi_range(bag.size() - 8, bag.size() - (2 if last_kind == "sync_cargo" else 1))
			bag[plates_index] = bag[early_index]
			bag[early_index] = "sync_cargo"
		# 接力也须在有限关卡内出现；不能挤走前八段的踏板或造成连抽。
		var relay_index := bag.find("charge_sync_relay")
		if relay_index < bag.size() - 12:
			var slots: Array = []
			for slot in range(bag.size() - 12, bag.size()):
				if bag[slot] != "sync_cargo" and not (slot == bag.size() - 1 and last_kind == "charge_sync_relay"):
					slots.append(slot)
			var early_index: int = slots[rng.randi_range(0, slots.size() - 1)]
			bag[relay_index] = bag[early_index]
			bag[early_index] = "charge_sync_relay"
	var kind: String = bag.pop_back()
	last_kind = kind
	return candidate_of(kind, level)

# 同一种段落的一个随机变体；后台证明失败时换另一变体重试，不直接让出空段。
func candidate_of(kind: String, level: int) -> Dictionary:
	var side := -1.0 if rng.randi_range(0, 1) == 0 else 1.0
	if kind == "left": side = -1.0
	if kind == "right": side = 1.0
	var block := decorate(make_block(kind, side, level), kind, side)
	for hazard in block.hazards:
		if hazard.kind in ["hammer", "sweeper"]: hazard.phase = rng.randf_range(0.0, TAU)
	# 护盾和合作奖品不再每段都有；前后站位段的奖品就是该段玩法本身，保留。
	block.rewards = block.rewards.filter(func(reward):
		if reward.kind == "shield": return rng.randf() < 0.3
		if reward.kind == "prize": return reward.staggered or rng.randf() < 0.45
		return true)
	block.extra_seed = rng.randi()
	return block

# 随机散布陷阱：只放在本段已验证双人路线（含两人之间的连线）之外，不碰主障碍、奖励和迎面物轨迹。
# 放好后调用方会带着这些陷阱把整段再验证一遍，验证不过就不加。
const EXTRA_WEIGHTS := [
	{"cargo": 3, "spikes": 3, "active_spikes": 2, "steam": 2, "sweeper": 1},
	{"cargo": 3, "spikes": 2, "active_spikes": 3, "steam": 2, "sweeper": 2, "pillar": 1},
	{"cargo": 2, "spikes": 2, "active_spikes": 3, "steam": 3, "sweeper": 2, "pillar": 1}]
const EXTRA_CLEARANCE := 22.0

static func extra_size(kind: String, picker: RandomNumberGenerator) -> Vector2:
	match kind:
		"cargo": return Vector2(picker.randf_range(40, 90), picker.randf_range(30, 60))
		"spikes", "active_spikes": return Vector2(80, 12)
		"steam": return Vector2(30, 40)
		"sweeper": return Vector2(52, 52)
	return Vector2(24, 24)

static func extra_hazards(block: Dictionary, corridor: Array, picker: RandomNumberGenerator, difficulty: String, level: int) -> Array:
	# 接力两处等待、换位和完整出口全宽安全，不叠加散布危险。
	if block.route == "charge_sync_relay": return []
	var weights: Dictionary = EXTRA_WEIGHTS[clampi(level, 0, EXTRA_WEIGHTS.size() - 1)]
	var total := 0
	for kind in weights: total += weights[kind]
	# 加宽路面多放一个，避免宽阔路面显得空旷；仍须通过带陷阱复证。
	var wanted: int = 3 + DIFFICULTIES[difficulty].complexity + level + picker.randi_range(0, 2)
	var placed: Array = []
	var others: Array = block.hazards.duplicate()
	for attempt in range(wanted * 14):
		if placed.size() >= wanted: break
		var roll := picker.randi_range(1, total)
		var kind := ""
		for name in weights:
			roll -= weights[name]
			if roll <= 0:
				kind = name
				break
		var size := extra_size(kind, picker)
		var position := Vector2(picker.randf_range(-ROAD_HALF_WIDTH + 8, ROAD_HALF_WIDTH - 8 - size.x), picker.randf_range(60, 790 - size.y))
		var rect := Rect2(position, size)
		# 全宽保护到达、观察、操作和门后归队空间。
		if block.has("gate") and rect.grow(EXTRA_CLEARANCE).intersects(Rect2(-ROAD_HALF_WIDTH - 40, 0, ROAD_HALF_WIDTH * 2 + 80, 350)): continue
		if not extra_fits(rect, others, block.rewards, corridor): continue
		var hazard := {"kind": kind, "rect": rect, "extra": true}
		if kind == "cargo": hazard.filler = true
		if kind in ["active_spikes", "sweeper"]: hazard.phase = picker.randf_range(0.0, 4.0 if kind == "active_spikes" else TAU)
		if kind == "steam":
			hazard.side = 1.0
			hazard.phase = picker.randf_range(0.0, 4.0)
		placed.append(hazard)
		others.append(hazard)
	return placed

static func extra_fits(rect: Rect2, others: Array, rewards: Array, corridor: Array) -> bool:
	for hazard in others:
		var other: Rect2 = hazard.rect
		# 迎面滚来、飞来的东西会扫过整条纵向通道；横穿的矿车、来回摆的锤扫过整条横带。
		if hazard.kind in ["stone_ball", "iron_ball", "fly_low", "fly_body", "rocket", "drone"]:
			if rect.position.x < other.end.x + 30 and rect.end.x > other.position.x - 30: return false
		elif hazard.kind in ["forklift", "hammer"]:
			if rect.position.y < other.end.y + 60 and rect.end.y > other.position.y - 60: return false
		elif rect.grow(30).intersects(other): return false
	for reward in rewards:
		if rect.grow(reward.radius + 12).has_point(reward.position): return false
	# 两人身位和两人之间的连线都要离开陷阱一个身位以上。
	var keep := rect.grow(EXTRA_CLEARANCE + 12.0)
	for pair in corridor:
		for n in range(5):
			if keep.has_point(pair[0].lerp(pair[1], n / 4.0)): return false
	return true

# 后台证明入口：先证明主段落并记录路线，再撒随机陷阱、带陷阱复证；任何一步失败都不让玩家判负。
func prove(candidate: Dictionary, difficulty: String, level: int) -> Dictionary:
	var block: Dictionary = candidate.duplicate(true)
	if not combination_allowed(block) or not validate_block(block, difficulty, level, {}, 0.0, true): return {}
	var corridor: Array = last_evidence.get("corridor", [])
	var picker := RandomNumberGenerator.new()
	picker.seed = block.get("extra_seed", 1)
	var extras := extra_hazards(block, corridor, picker, difficulty, level)
	while not extras.is_empty():
		if canceled(): return {}
		var dressed: Dictionary = block.duplicate(true)
		dressed.hazards.append_array(extras)
		if validate_block(dressed, difficulty, level, {}, 0.0, false): return dressed
		extras.resize(extras.size() / 2)
	return block

# 白名单组合：高柱配侧边压机、低空物配侧边蒸汽。
static func decorate(block: Dictionary, kind: String, side: float) -> Dictionary:
	if kind == "pillar":
		block.hazards.append({"kind": "press", "rect": Rect2(-side * 140 - 40, 560, 80, 50), "side": side})
		block.combination = "pillar_press"
	# 低空飞石段两侧已是岩墙，原先放在路边的蒸汽喷口会埋进墙里，不再附加。
	if ROWS.has(kind):
		var row: Dictionary = ROWS[kind]
		var cursor := -ROAD_HALF_WIDTH
		var spans: Array = row.open.duplicate()
		spans.append([ROAD_HALF_WIDTH, ROAD_HALF_WIDTH])
		for span in spans:
			# 不足 1 米的碎条不生成，免得出现看不清的细石片。
			if span[0] - cursor >= 20.0:
				var left: float = cursor if side > 0 else -float(span[0])
				block.hazards.append({"kind": "cargo", "rect": Rect2(left, row.y, span[0] - cursor, row.depth), "filler": true})
			cursor = maxf(cursor, span[1])
	return block

static func combination_allowed(block: Dictionary) -> bool:
	var kinds: Array = []
	var has_new := false
	for hazard in block.hazards:
		# 封路巨岩和随机散布陷阱不算一种组合机制。
		if hazard.get("filler", false) or hazard.get("extra", false): continue
		if hazard.kind not in kinds: kinds.append(hazard.kind)
		has_new = has_new or hazard.kind in NEW_KINDS
	if not has_new or kinds.size() <= 1: return true
	var allowed: Array = COMBINATIONS.get(block.get("combination", ""), [])
	if kinds.size() != allowed.size(): return false
	for kind in kinds:
		if kind not in allowed: return false
	return true

static func make_block(kind: String, side: float, level: int) -> Dictionary:
	if kind == "charge_sync_relay":
		var charge := ChargeGate.make_tutorial()
		ChargeGate.relocate(charge, 60.0)
		var plates := SyncPlates.make_tutorial()
		ChargeGate.relocate(plates, 190.0)
		charge.relay_index = 0
		plates.relay_index = 1
		charge.relay_count = 2
		plates.relay_count = 2
		return {"route": kind, "lane": 0.0, "gates": [charge, plates], "hazards": [],
			"rewards": [{"kind": "coin", "position": Vector2(-25, 660), "radius": 20.0},
				{"kind": "coin", "position": Vector2(-25, 710), "radius": 20.0},
				{"kind": "coin", "position": Vector2(-25, 760), "radius": 20.0}]}
	if kind in ["charge_cargo", "sync_cargo"]:
		var gate := SyncPlates.make_tutorial() if kind == "sync_cargo" else ChargeGate.make_tutorial()
		# 踏板开门后须从分站位置共同换侧，不能沿用教学纵坐标挤压绕箱距离。
		ChargeGate.relocate(gate, -170.0 if kind == "sync_cargo" else 60.0)
		return {"route": kind, "lane": side * 110.0, "gate": gate,
			"hazards": [{"kind": "cargo", "rect": Rect2(-45, 430, 90, 65)}],
			"rewards": [{"kind": "coin", "position": Vector2(side * 110.0 - 25, 380), "radius": 20.0},
				{"kind": "coin", "position": Vector2(side * 110.0 + 25, 520), "radius": 20.0}]}
	if kind == "narrow":
		# 两侧断崖一直延伸到路外，桥面偏向随机一侧；只放桥上金币，不放需两人并排到位的奖品。
		var plank := side * 40.0
		var outer := ROAD_HALF_WIDTH + 40.0
		return {"route": kind, "lane": plank, "hazards": [
			{"kind": "road_gap", "rect": Rect2(-outer, NARROW_START, plank - NARROW_PLANK * 0.5 + outer, NARROW_LENGTH), "narrow": true},
			{"kind": "road_gap", "rect": Rect2(plank + NARROW_PLANK * 0.5, NARROW_START, outer - plank - NARROW_PLANK * 0.5, NARROW_LENGTH), "narrow": true}],
			"rewards": [{"kind": "coin", "position": Vector2(plank, NARROW_START + 120), "radius": 20.0},
				{"kind": "coin", "position": Vector2(plank, NARROW_START + 300), "radius": 20.0}]}
	var lane := side * 110.0 if kind not in ["jump", "low_jump", "safe"] else 0.0
	if kind in ["gap_bypass", "gap_long", "drone", "forklift", "press"]: lane = side * 130.0
	if kind in ["sweep_double", "gap_double", "gap_single"]: lane = 0.0
	if kind == "sweep_single": lane = side * 50.0
	var hazards: Array = []
	if kind in ["drone", "forklift", "press", "hammer", "collapse", "steam"]:
		lane = (-side if kind == "hammer" else side) * 140.0
		# 摆锤吊在路面上方的龙门架上，在横跨道路的竖直平面里来回摆；支点偏向 side 一侧。
		# 摆到 -side 一侧最高处时锤头高过头顶，那一侧路边留一条窄安全带，其余位置要掐时机穿过。
		if kind == "hammer": hazards.append({"kind": kind, "rect": Rect2(side * 60 - 6, 442, 12, 12), "side": side})
		if kind == "collapse": hazards.append({"kind": kind, "rect": Rect2(-80, 520, 160, 60), "side": side})
		if kind == "steam":
			for n in range(2): hazards.append({"kind": kind, "rect": Rect2(-45 + n * 55, 560, 30, 40), "side": side, "phase": n * 3.0})
		if kind == "drone": hazards.append({"kind": kind, "rect": Rect2(-side * 40 - 18, 640, 36, 36), "side": side})
		if kind == "forklift": hazards.append({"kind": kind, "rect": Rect2(-side * 180 - 30, 580, 60, 48), "side": side})
		if kind == "press": hazards.append({"kind": kind, "rect": Rect2(-80, 560, 160, 50), "side": side})
	if kind.begins_with("sweep_"):
		hazards.append({"kind": "sweeper", "rect": Rect2(-26, 288, 52, 52), "phase": 0.0})
	if kind.begins_with("gap_"):
		var gap := Rect2(-80, 300, 160, Surfaces.LONG_GAP if kind == "gap_long" else Surfaces.SHORT_GAP)
		if kind == "gap_single": gap = Rect2(-65, 300, 60, Surfaces.SHORT_GAP) if side > 0 else Rect2(5, 300, 60, Surfaces.SHORT_GAP)
		hazards.append({"kind": "road_gap", "rect": gap})
	if kind in ["left", "right", "stagger"]:
		hazards.append({"kind": "cargo", "rect": Rect2(-45, 290, 90, 65)})
	if kind == "pillar": hazards.append({"kind": "pillar", "rect": Rect2(-12, 300, 24, 24)})
	if kind == "jump": hazards.append({"kind": "rail", "rect": Rect2(-ROAD_HALF_WIDTH - 36, 294, ROAD_HALF_WIDTH * 2 + 72, 12)})
	if kind == "low_jump": hazards.append({"kind": "fly_low", "rect": Rect2(-70, 760, 140, 24)})
	if kind == "ball": hazards.append({"kind": "stone_ball" if level == 0 else "iron_ball", "rect": Rect2(-45, 550, 90, 90) if level == 0 else Rect2(-40, 550, 80, 80)})
	if kind == "stone_ball": hazards.append({"kind": "stone_ball", "rect": Rect2(-45, 550, 90, 90)})
	if kind == "body": hazards.append({"kind": "fly_body", "rect": Rect2(-28, 900, 56, 24)})
	if kind == "rocket": hazards.append({"kind": "rocket", "rect": Rect2(-20, 900, 40, 64)})
	if kind == "double":
		hazards.append({"kind": "fly_body", "rect": Rect2(-28, 900, 56, 24)})
		hazards.append({"kind": "iron_ball", "rect": Rect2(-40, 550, 80, 80)})
	for hazard in hazards:
		if hazard.kind in ["stone_ball", "iron_ball", "fly_low", "fly_body", "rocket"]: hazard.timed_launch = true
	var staggered := kind == "stagger"
	var rewards: Array = [
		{"kind": "coin", "position": Vector2(lane - 25, 260), "radius": 20.0},
		{"kind": "coin", "position": Vector2(lane + 25, 410), "radius": 20.0},
		{"kind": "prize", "position": Vector2(lane, 370), "radius": 26.0 if staggered else 44.0, "staggered": staggered},
		{"kind": "shield", "position": Vector2(lane - 25, 440), "radius": 20.0}]
	if kind == "gap_long":
		# 奖励不放在失去支撑范围；先保持同侧，再在缺口完全通过后归队。
		rewards[1].position.y = 600.0
		rewards[2].position.y = 590.0
		rewards[3].position.y = 630.0
	return {"route": kind, "lane": lane, "hazards": hazards, "rewards": rewards}

# 输出普通双人按键方向和跳跃按下状态，生产运动、碰撞、绳索不做特殊处理。
# 路线控制器只供生成验证与回放；生产玩家仍由真实键盘输入控制。
static func route_input(run, block: Dictionary, base: float) -> Array:
	if run.charge_gate.active and not run.charge_gate.open and run.distance >= run.charge_gate.receiver.y - 100:
		if run.charge_gate.get("kind", "charge") == "sync_plates": return SyncPlates.route_input(run, run.charge_gate)
		return ChargeGate.route_input(run, run.charge_gate)
	var d: float = run.distance - base
	var lane: float = block.lane
	# 提速后仍按真实横移速度预留返回中央所需时间，不能依赖旧 150 单位出口。
	var return_at := minf(450.0, SEGMENT - run.speed() * (absf(lane) / run.LATERAL + 0.10))
	if block.route == "gap_long": return_at = 660.0
	if block.route in ["drone", "forklift", "press", "collapse", "steam"]: return_at = 650.0
	if block.route == "hammer": return_at = 650.0
	if block.route in ["charge_cargo", "sync_cargo"]: return_at = 570.0
	# 后方角色完全离开桥尾断崖后才回中。
	if block.route == "narrow": return_at = NARROW_START + NARROW_LENGTH + NARROW_SPACING + 30.0
	# 分部危险的最后端必须落在双方及绳段后方才可回中。
	for i in range(run.kinds.size()):
		if not run.hazard_specs[i].get("industrial", false) or run.hazard_specs[i].get("extra", false): continue
		if absf(run.hazard_specs[i].start_distance - base) > 0.1: continue
		var sample: Dictionary = run.hazard_sample(i, run.elapsed)
		var end_y: float = sample.envelope.end.y if run.kinds[i] == "hammer" else sample.rect.end.y
		if end_y >= minf(run.a.position.y, run.b.position.y) - run.Motion.RADIUS - 2.0:
			return_at = maxf(return_at, d + run.speed() * run.FIXED_STEP)
	# 迎面物随关速重定位；不能沿用固定距离回中而切入尚未通过的球体。
	for i in range(run.kinds.size()):
		if not run.hazard_specs[i].get("front", false) or run.hazard_specs[i].get("extra", false): continue
		if absf(run.hazard_specs[i].get("start_distance", 0.0) - base) > 0.1: continue
		var rect: Rect2 = run.hazard_sample(i, run.elapsed).rect
		if rect.end.y >= minf(run.a.position.y, run.b.position.y) - run.Motion.RADIUS:
			return_at = maxf(return_at, d + run.speed() * run.FIXED_STEP)
	var center := lane if d < return_at else 0.0
	if d < 0: center = 0.0
	var stagger: bool = block.route == "stagger" and d >= 230 and d < 410
	var jump_stagger: bool = block.route in ["sweep_double", "gap_double"] and d >= 100 and d < 410
	# 窄桥：01 在前、02 在后排成单列，沿桥面中线通过。
	var single_file: bool = block.route == "narrow" and d >= 0 and d < return_at
	var width := 0.0 if stagger or single_file else 25.0
	var offset := 30.0 if stagger else (NARROW_SPACING if single_file else (18.0 if jump_stagger else 0.0))
	var first_error := Vector2(center - width - run.a.position.x, run.distance + offset - run.a.position.y)
	var second_error := Vector2(center + width - run.b.position.x, run.distance - offset - run.b.position.y)
	# 普通段危险接近时只共同横移，避免为半步残差突然前进改变 TTC。
	# 前后合作段正常使用纵向按键；其余段在危险已通过的出口区修正残差。
	if block.route not in ["stagger", "narrow"] and not jump_stagger and d < 450:
		first_error.y = 0
		second_error.y = 0
	# 出口先完成横移再修正前后残差，避免对角归一化吃掉回中余量。
	if d >= return_at:
		if absf(first_error.x) > KEYBOARD_STEP * 0.5: first_error.y = 0
		if absf(second_error.x) > KEYBOARD_STEP * 0.5: second_error.y = 0
	var first := keyboard_direction(first_error)
	var second := keyboard_direction(second_error)
	var jump := false
	if block.route == "jump": jump = d >= 300 - run.speed() * 0.30 and d < 310 - run.speed() * 0.30
	if block.route == "low_jump":
		for i in range(run.kinds.size()):
			if run.kinds[i] != "fly_low": continue
			var rect: Rect2 = run.hazard_sample(i, run.elapsed).rect
			var ttc: float = (rect.get_center().y - maxf(run.a.position.y, run.b.position.y)) / (run.speed() - Threats.CONFIG.fly_low.velocity.y)
			if ttc <= 0.30 and ttc > 0.25: jump = true
	if block.route in ["sweep_single", "gap_single", "sweep_double", "gap_double"]:
		var jumps := [false, false]
		for i in range(2):
			var point: Vector2 = run.a.position if i == 0 else run.b.position
			var needed: bool = block.route in ["sweep_double", "gap_double"] or (absf(point.x) < 50 if block.route == "sweep_single" else (point.x < 0 if block.hazards[0].rect.position.x < 0 else point.x > 0))
			var takeoff: float = base + 314.0 - run.speed() * 0.30
			jumps[i] = needed and point.y >= takeoff and point.y < takeoff + run.speed() * 0.05
		return [first, second, jumps[0], jumps[1]]
	return [first, second, jump, jump]

# 每轴只输出 -1、0、1，等价于现有四方向键；对角归一化由生产 step 执行。
# 半步死区防止过目标后的无意义按键抖动，不吸附位置，也不减小运动步长。
static func keyboard_direction(error: Vector2) -> Vector2:
	return Vector2(signf(error.x) if absf(error.x) > KEYBOARD_STEP * 0.5 else 0.0, signf(error.y) if absf(error.y) > KEYBOARD_STEP * 0.5 else 0.0)

static func keyboard_legal(direction: Vector2) -> bool:
	return direction.x in [-1.0, 0.0, 1.0] and direction.y in [-1.0, 0.0, 1.0]

static func object_state(object, excluded: Array = []) -> Dictionary:
	var captured := {}
	for property in object.get_property_list():
		if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or property.name in excluded: continue
		var value = object.get(property.name)
		captured[property.name] = value.duplicate(true) if value is Array or value is Dictionary else value
	return captured

# 包括输入边沿、跳跃缓冲、绳接触、活动危险及全部相位；禁止只保存角色坐标。
static func capture_state(run) -> Dictionary:
	var excluded: Array = ["a", "b", "rope", "generator"]
	# 调度句柄不属于物理入口，不跨线程分享 Thread、取消对象或主线程日志。
	for property in run.get_property_list():
		if str(property.name).begins_with("async_"): excluded.append(property.name)
	return {"run": object_state(run, excluded), "a": run.a.position,
		"b": run.b.position, "rope": object_state(run.rope)}

static func clone_state(captured: Dictionary):
	var clone = load("res://scripts/road_run.gd").new(false)
	for name in captured.run:
		var value = captured.run[name]
		clone.set(name, value.duplicate(true) if value is Array or value is Dictionary else value)
	clone.a.position = captured.a
	clone.b.position = captured.b
	for name in captured.rope:
		var value = captured.rope[name]
		clone.rope.set(name, value.duplicate(true) if value is Array or value is Dictionary else value)
	# 仅关闭递归生成，不改变固定步、回收、重定位、支撑和已加载危险。
	clone.generation_enabled = false
	# 快照按属性深拷贝后重新选中队列内字典，充能不能写入游离副本。
	clone.select_charge_gate()
	return clone

static func source_binding(force: bool = true) -> String:
	var sources: Array[String] = []
	var directory := DirAccess.open("res://scripts")
	for name in directory.get_files():
		if name.ends_with(".gd"): sources.append(name)
	sources.sort()
	var paths: Array[String] = []
	for name in sources: paths.append("res://scripts/" + name)
	# 动画资源与场景也绑定，不能仅靠物理参数使旧播放证据命中缓存。
	paths.append_array(["res://scenes/road_demo.tscn", "res://project.godot", "res://assets/mechs/George.gltf", "res://assets/mechs/Leela.gltf"])
	var stamp := ""
	for name in paths: stamp += name + ":" + str(FileAccess.get_modified_time(name)) + ";"
	if not force and stamp == binding_stamp and not binding_value.is_empty(): return binding_value
	var binding := ""
	for name in paths: binding += name + ":" + FileAccess.get_sha256(name) + "\n"
	binding_stamp = stamp
	binding_value = binding.sha256_text()
	return binding_value

static func certificate_key(block: Dictionary, difficulty: String, level: int, entrance: Dictionary, base: float) -> String:
	return var_to_str([source_binding(), difficulty, level, DIFFICULTIES[difficulty], MANUAL_SPEED,
		FIXED_STEP, block, entrance, base]).sha256_text()

static func existing_route_input(run) -> Array:
	if run.charge_gate.active and not run.charge_gate.open and run.distance >= run.charge_gate.receiver.y - 100:
		if run.charge_gate.get("kind", "charge") == "sync_plates": return SyncPlates.route_input(run, run.charge_gate)
		return ChargeGate.route_input(run, run.charge_gate)
	for segment in run.route_segments:
		if run.total_distance() >= segment.base and run.total_distance() < segment.base + SEGMENT:
			return route_input(run, segment.block, segment.base - run.world_origin)
	return route_input(run, make_block("safe", 0, run.level_index), run.distance)

func remember_certificate(key: String) -> void:
	verified[key] = last_evidence.duplicate(true)
	# 完整入口不同即不同证书；限制缓存数量，不能以删状态换取复用。
	while verified.size() > 32: verified.erase(verified.keys()[0])

func validate_block(block: Dictionary, difficulty: String, level: int, entrance: Dictionary = {}, base: float = 0.0, build_chain: bool = false) -> bool:
	# 使用实际 road_run；仅关闭递归生成，仍执行生产流式回收、固定步、奖励与连续碰撞。
	var run
	if entrance.is_empty():
		run = load("res://scripts/road_run.gd").new(false)
		run.difficulty = difficulty
		run.level_index = level
		run.retry()
		run.a.position = Vector2(-25, 0)
		run.b.position = Vector2(25, 0)
		run.rope.reset(run.a.position, run.b.position)
		run.step(0)
	else: run = clone_state(entrance)
	var source_state := capture_state(run)
	var absolute_base: float = base + run.world_origin
	if not combination_allowed(block):
		last_evidence = {"accepted": false, "reason": "禁区组合", "exit": snapshot(run, 0), "source_entry": source_state, "source_entry_hash": var_to_str(source_state).sha256_text(), "source_binding": binding(), "layout_hash": var_to_str(block).sha256_text(), "base": absolute_base}
		run.dispose()
		return false
	var source_shield_uses: int = run.shield_uses
	var shield_collision := {}
	var reward_prefix := "certificate:%d" % run.next_obstacle_id
	if build_chain:
		block.rewards = block.rewards.filter(func(reward): return reward.kind != "coin")
		block.coin_chain = "生产安全足点在线建链；实际领取；金币仅计分，不改变物理或路线输入"
	run.install_block(block, base, reward_prefix)
	var expected_coins := 0
	var expected_prizes := 0
	for reward in block.rewards:
		if reward.kind == "coin": expected_coins += 1
		if reward.kind == "prize": expected_prizes += 1
	var entry_sample := {}
	var inputs: Array = []
	var samples: Array = []
	var warnings := {}
	var jump_events: Array = []
	var valid := true
	var illegal_inputs := 0
	var next_coin_y := 90.0
	var coin_role := 0
	# 本段实际走过的双人位置（段内局部坐标），供之后在路线外散布陷阱。
	var corridor: Array = []
	var duration: float = maxf(0.0, absolute_base + SEGMENT - run.total_distance())
	# 预算包含每个预加载机关的充能及调整；不改变生产固定步。
	for tick in range(int(ceil(duration / run.speed() / run.FIXED_STEP)) + 180 + 240 * run.charge_gates.size()):
		if canceled():
			last_evidence = {"accepted": false, "reason": "后台验证已取消", "exit": snapshot(run, tick), "source_entry_hash": var_to_str(source_state).sha256_text()}
			run.dispose()
			return false
		var in_block: bool = run.total_distance() >= absolute_base
		if in_block and entry_sample.is_empty(): entry_sample = snapshot(run, tick)
		var input := route_input(run, block, absolute_base - run.world_origin) if in_block else existing_route_input(run)
		if not keyboard_legal(input[0]) or not keyboard_legal(input[1]): illegal_inputs += 1
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
			shield_collision = {"tick": tick, "local_y": local_y, "events": run.absorbed_events.duplicate(true), "state": snapshot(run, tick)}
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
		if tick % 30 == 0: samples.append(snapshot(run, tick))
		if run.state != "running" or run.total_distance() >= absolute_base + SEGMENT: break
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
			warning_ok = warning_ok and evidence.ttc >= evidence.joint_change_time + 0.35 - 0.025 and evidence.ttc >= DIFFICULTIES[difficulty].front_warning - 0.025
	var exit_ok: bool = absf(run.a.position.x + 25) <= EXIT_TOLERANCE and absf(run.b.position.x - 25) <= EXIT_TOLERANCE and absf(run.a.position.y - run.distance) <= EXIT_TOLERANCE and absf(run.b.position.y - run.distance) <= EXIT_TOLERANCE and run.rope.contacts.is_empty() and run.heights == [0.0, 0.0]
	valid = valid and illegal_inputs == 0 and run.state == "running" and run.total_distance() >= absolute_base + SEGMENT and all_rewards and exit_ok and warning_ok
	last_evidence = {"accepted": valid, "reason": run.reason if run.state != "running" else ("奖励未全部可达" if not all_rewards else ("段尾状态不兼容" if not exit_ok else ("预警不足" if not warning_ok else "生产回放"))), "route": block.route, "difficulty": difficulty, "level": level, "inputs": inputs, "samples": samples, "warnings": warnings, "exit": snapshot(run, inputs.size()), "coins": run.coins, "prizes": run.prizes, "shield_uses": run.shield_uses}
	last_evidence.input_encoding = "原始键盘轴值：01横/纵、02横/纵各为-1/0/1；空格、回车按下状态"
	last_evidence.illegal_inputs = illegal_inputs
	last_evidence.exit_tolerance = EXIT_TOLERANCE
	last_evidence.jump_events = jump_events
	last_evidence.source_entry_hash = var_to_str(source_state).sha256_text()
	last_evidence.source_entry = source_state
	last_evidence.predicted_entry = entry_sample
	last_evidence.source_binding = binding()
	last_evidence.base = absolute_base
	last_evidence.entry_mode = "生产预加载状态连续预测" if not entrance.is_empty() else "历史中心夹具"
	last_evidence.expected_rewards = [expected_coins, expected_prizes]
	last_evidence.claimed_block_rewards = [claimed_coins, claimed_prizes]
	last_evidence.speed = run.speed()
	last_evidence.layout_hash = var_to_str(block).sha256_text()
	last_evidence.support_rule = "实际固定步角色地面支撑；绳索不承重；连续扫掠"
	last_evidence.shield_uses_before = source_shield_uses
	last_evidence.shield_uses_after = run.shield_uses
	last_evidence.shield_collision = shield_collision
	last_evidence.corridor = corridor
	if illegal_inputs > 0: last_evidence.reason = "非生产键盘输入"
	run.dispose()
	return valid

static func snapshot(run, tick: int) -> Dictionary:
	var threats: Array = []
	for i in range(run.kinds.size()):
		var sample: Dictionary = run.hazard_sample(i, run.elapsed)
		var entry := {"id": run.obstacle_ids[i], "kind": run.kinds[i], "rect": [sample.rect.position.x, sample.rect.position.y, sample.rect.size.x, sample.rect.size.y], "warning": sample.warning, "ttc": sample.get("ttc", -1)}
		if sample.has("parts"):
			entry.stage = sample.stage
			entry.parts = sample.parts.duplicate(true)
		threats.append(entry)
	return {"tick": tick, "a": [run.a.position.x, run.a.position.y], "b": [run.b.position.x, run.b.position.y], "jump": run.heights.duplicate(), "support": run.ground_support.duplicate(), "rope_heights": Array(run.rope.path_heights()), "rope": run.rope.required, "contacts": run.rope.contacts.duplicate(true), "threats": threats, "distance": run.distance, "origin": run.world_origin, "state": run.state, "coins": run.coins, "prizes": run.prizes,
		"elapsed": run.elapsed, "vertical_speed": run.vertical_speed.duplicate(), "jump_buffer": run.jump_buffer.duplicate(), "jump_held": run.jump_held.duplicate(), "accumulator": run.accumulator,
		"rope_bound": run.rope_bound, "rope_resume": run.rope_resume, "hazard_specs": run.hazard_specs.duplicate(true), "shield_uses": run.shield_uses,
		"rope_path": Array(run.rope.path), "charge_gate": run.charge_gate.duplicate(true), "charge_gates": run.charge_gates.duplicate(true), "gate_events": run.gate_events.duplicate(true)}

func generate_block(number: int, difficulty: String, level: int, source_run = null, base: float = 0.0) -> Dictionary:
	var previous_binding := source_override
	source_override = source_binding(true)
	var block := candidate_block(number, level)
	var entrance: Dictionary = capture_state(source_run) if source_run != null else {}
	var result := generate_candidate(block, number, difficulty, level, entrance, base, source_run != null)
	source_override = previous_binding
	return result

# 候选和随机数由主线程确定；后台只验证自己的入口副本与固定布局。
func generate_candidate(block: Dictionary, number: int, difficulty: String, level: int, entrance: Dictionary, base: float, build_chain: bool) -> Dictionary:
	var key := var_to_str([binding(), difficulty, level, DIFFICULTIES[difficulty], MANUAL_SPEED, FIXED_STEP, block, entrance, base]).sha256_text()
	var accepted: bool = verified.has(key) and not block.get("injected", false)
	if accepted: last_evidence = verified[key].duplicate(true)
	if not accepted:
		accepted = validate_block(block, difficulty, level, entrance, base, build_chain)
		if canceled(): return {}
		if accepted:
			last_evidence.generated_block = block.duplicate(true)
			remember_certificate(key)
			remember_certificate(var_to_str([binding(), difficulty, level, DIFFICULTIES[difficulty], MANUAL_SPEED, FIXED_STEP, block, entrance, base]).sha256_text())
	elif accepted and build_chain: block = last_evidence.generated_block.duplicate(true)
	if accepted: return block
	rejected += 1
	var reason: String = last_evidence.reason
	var rejected_exit: Dictionary = last_evidence.exit.duplicate(true)
	var rejected_source: String = last_evidence.source_entry_hash
	# 首轮教学必须实际出现；拒绝时保留证据并停生，不能用安全空段吞掉教学。
	if number < LEVEL_ROUTES[level].size() and not block.get("injected", false):
		rejection_evidence.append({"segment": number, "route": block.route, "reason": reason,
			"source_entry_hash": rejected_source, "exit": rejected_exit, "fallback": "teaching_rejected_generation_stopped"})
		return {}
	fallbacks += 1
	var fallback := make_block("safe", 0, level)
	var fallback_key := var_to_str([binding(), difficulty, level, DIFFICULTIES[difficulty], MANUAL_SPEED, FIXED_STEP, fallback, entrance, base]).sha256_text()
	if not verified.has(fallback_key):
		# release 构建可能省略 assert，验证必须显式执行；失败时关闭生成。
		if not validate_block(fallback, difficulty, level, entrance, base, build_chain):
			if canceled(): return {}
			rejection_evidence.append({"segment": number, "route": block.route, "reason": reason,
				"source_entry_hash": rejected_source, "exit": rejected_exit, "fallback": "failed_generation_stopped",
				"fallback_reason": last_evidence.reason, "fallback_exit": last_evidence.exit.duplicate(true), "fallback_key": fallback_key})
			return {}
		last_evidence.generated_block = fallback.duplicate(true)
		remember_certificate(fallback_key)
	else:
		last_evidence = verified[fallback_key].duplicate(true)
		fallback = last_evidence.generated_block.duplicate(true)
	rejection_evidence.append({"segment": number, "route": block.route, "candidate_hash": var_to_str(block).sha256_text(), "reason": reason, "exit": rejected_exit, "fallback": "verified_safe", "fallback_key": fallback_key,
		"source_entry_hash": rejected_source, "fallback_source_entry_hash": last_evidence.source_entry_hash, "source_binding": last_evidence.source_binding})
	if rejection_evidence.size() > 32: rejection_evidence.pop_front()
	return fallback

# 历史调用兼容；不再使用 11 米证书或固定右侧包络。
func generate(number: int, difficulty: String) -> Array:
	return generate_block(number, difficulty, 0).hazards

func validate_joint(template: Array) -> bool:
	var block := make_block("safe", 0, 0)
	block.hazards = template
	return validate_block(block, "普通", 0)
