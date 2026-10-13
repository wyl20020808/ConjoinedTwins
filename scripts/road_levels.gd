extends RefCounted

# 基础推进约 100 秒；绕柱停滞及真人回撤会延长实际时间。
const LEVELS := [
	{"name": "同侧归航", "seconds": 100.0, "speed_scale": 1.0, "kinds": ["rail", "fly_low", "pillar", "stone_ball"]},
	{"name": "迎面协作", "seconds": 100.0, "speed_scale": 1.08, "kinds": ["fly_body", "rocket", "stone_ball", "iron_ball", "cargo", "fly_low", "pillar"]},
	{"name": "连线接力", "seconds": 100.0, "speed_scale": 1.16, "kinds": ["iron_ball", "fly_body", "rocket", "pillar", "stone_ball", "rail", "cargo"]}
]
const MAX_REWARDS := 96
const INVULNERABILITY := 1.0
const PRIZE_SOCKET_MAX_RADIUS := 29.0

static func safe_side(seed_value: int, level: int) -> float:
	return -1.0 if (seed_value + level) % 2 == 0 else 1.0

# 本轮使用保守同侧段落，左右由种子及关卡决定，不依赖旧 11 米右侧证书。
# 双人中心在 side*154±25，间距 2.5 米；危险集中在另一侧，中央柱也不侵入该路径。
static func hazards(number: int, level: int, side: float) -> Array:
	var config: Dictionary = LEVELS[level]
	var kind: String = config.kinds[number % config.kinds.size()]
	var size := Vector2(80, 65 if kind == "cargo" else 12)
	var threats = preload("res://scripts/dynamic_threats.gd")
	if threats.CONFIG.has(kind): size = threats.CONFIG[kind].size
	if kind == "pillar": size = Vector2(24, 24)
	var x := 0.0 if kind == "pillar" else -side * 95.0
	var result := [{"kind": kind, "rect": Rect2(Vector2(x, 240) - size * 0.5, size), "velocity": threats.CONFIG[kind].velocity if threats.CONFIG.has(kind) else Vector2.ZERO}]
	if level == 2 and number % 3 == 2:
		result.append({"kind": "fly_low", "rect": Rect2(Vector2(-side * 95 - 28, 430), Vector2(56, 24)), "velocity": Vector2(0, -180)})
	return result

static func rewards(number: int, level: int, side: float) -> Array:
	var center := Vector2(side * 154, 420)
	var result := [{"kind": "coin", "position": center + Vector2(-25, -100), "radius": 20.0}, {"kind": "coin", "position": center + Vector2(25, 0), "radius": 20.0}]
	if number % 4 == 0:
		result.append({"kind": "shield", "position": center + Vector2(-25, 100), "radius": 20.0})
	if number % 5 == 2:
		result.append({"kind": "prize", "position": center, "radius": 44.0 if level < 2 else 26.0, "staggered": level == 2})
	return result
