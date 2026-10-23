extends RefCounted
# 单人模式的 02 人机：只读取 Run 状态，输出与真人相同的“方向 + 跳跃键”，不直接改模拟。
# 基础路线复用生成器验证过的 Templates.existing_route_input（能躲开所有障碍），
# 再叠加“不够聪明”的失误：断崖前按概率不跳（掉下去等待救援），平时偶尔晚跳一点。

const Templates = preload("res://scripts/road_templates.gd")
const GAP_LOOKAHEAD := 0.35  # 秒：起跳时检查前方这段时间内是否是断崖
const PRESS_PERIOD := 0.16   # 救援连按节奏（秒/次），比熟练玩家略慢

var role := 1
var miss_chance := 0.4       # 每次断崖起跳时的失误概率
var late_chance := 0.2       # 其他起跳偶尔迟疑的概率
var rng := RandomNumberGenerator.new()
var force_miss := false      # 测试用：下一处断崖必定失误
var route_jump_was := false
var suppress := 0.0          # 剩余“不跳”时间
var delay := 0.0             # 剩余迟疑时间
var hesitate := 0.0          # 失误时在崖边往后缩的剩余时间
var press_clock := 0.0
var press_down := false
var confirm_clock := 0.0
var misses := 0
var feedback := "跟随"

func reset(seed_value: int = 0) -> void:
	rng.seed = seed_value if seed_value != 0 else int(Time.get_ticks_usec())
	route_jump_was = false
	suppress = 0.0
	delay = 0.0
	hesitate = 0.0
	press_clock = 0.0
	press_down = false
	confirm_clock = 0.0
	feedback = "跟随"

# 返回 {"move": Vector2, "jump": bool}
func think(run, delta: float) -> Dictionary:
	match run.state:
		"rescue": return rescue_input(run, delta)
		"settlement": return confirm_input(run, delta)
		"running": return running_input(run, delta)
	press_down = false
	route_jump_was = false
	return {"move": Vector2.ZERO, "jump": false}

func self_point(run) -> Vector2:
	return run.b.position if role == 1 else run.a.position

func running_input(run, delta: float) -> Dictionary:
	var route: Array = Templates.existing_route_input(run)
	var move: Vector2 = route[role]
	var want_jump: bool = route[2 + role]
	var grounded: bool = run.heights[role] == 0.0 and run.vertical_speed[role] == 0.0
	# 路线刚要求起跳的那一刻决定这次是否失误。
	if want_jump and not route_jump_was and grounded and suppress <= 0.0 and delay <= 0.0:
		if gap_ahead(run):
			if force_miss or rng.randf() < miss_chance:
				# 失误＝在崖边犹豫一下没敢跳，随后被推进带进坑里；
				# 这时玩家通常已落地站稳，于是进入救援而不是直接双双坠落。
				suppress = 1.4
				hesitate = 0.45
				misses += 1
				feedback = "没跳过去！"
			force_miss = false
		elif rng.randf() < late_chance:
			delay = rng.randf_range(0.03, 0.07)
	route_jump_was = want_jump
	var jump := want_jump
	if suppress > 0.0:
		suppress -= delta
		jump = false
		hesitate -= delta
		# 犹豫期间，以及队友还在空中时，往后缩；等队友站稳再被推进带下去，才会触发救援。
		var partner := 1 - role
		if hesitate > 0.0 or run.heights[partner] > 0.0 or run.vertical_speed[partner] != 0.0:
			move = Vector2(move.x, -1.0)
	elif delay > 0.0:
		delay -= delta
		jump = false
	elif grounded and feedback != "跟随" and suppress <= 0.0:
		feedback = "跟随"
	return {"move": move, "jump": jump}

# 前方（按推进速度）是否会踩空。
func gap_ahead(run) -> bool:
	var me: Vector2 = self_point(run)
	for k in range(1, 5):
		if not run.has_ground_support(me + Vector2(0, run.speed() * GAP_LOOKAHEAD * k / 4.0)):
			return true
	return false

# 救援：不论拉人还是被拉，都以略慢的节奏连按，偶尔漏按一下。
func rescue_input(run, delta: float) -> Dictionary:
	feedback = "往上爬！" if run.rescue.get("role", -1) == role else "拉住你了！"
	press_clock += delta
	if press_clock >= PRESS_PERIOD * 0.5:
		press_clock = 0.0
		press_down = false if press_down or rng.randf() < 0.1 else true
	return {"move": Vector2.ZERO, "jump": press_down}

# 结算页：稍等后按一次确认。
func confirm_input(run, delta: float) -> Dictionary:
	confirm_clock += delta
	var pressed: bool = confirm_clock > 0.8 and confirm_clock < 1.0 and not run.confirmations[role]
	if confirm_clock > 1.2: confirm_clock = 0.0
	return {"move": Vector2.ZERO, "jump": pressed}
