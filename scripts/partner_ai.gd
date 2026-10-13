extends RefCounted

const Motion = preload("res://scripts/link_motion.gd")
const CELL := 20.0
var mode := "follow"
var target := Vector2.ZERO
var has_target := false
var feedback := "跟随"
var route: Array[Vector2] = []
var timer := 0.0
var last_goal := Vector2.INF

func reset() -> void:
	mode = "follow"
	has_target = false
	route.clear()
	timer = 0.0
	last_goal = Vector2.INF
	feedback = "跟随"

func wait() -> void:
	mode = "wait"
	has_target = false
	route.clear()
	feedback = "原地等待"

func command(point: Vector2, position: Vector2, walls: Array) -> void:
	target = point
	has_target = true
	mode = "goto"
	route = path(position, point, walls)
	last_goal = point
	timer = 0.0
	feedback = "前往目标" if not route.is_empty() else "不可达目标；右键重选 / E 召回"

static func cell(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / CELL), roundi(p.y / CELL))

static func point(c: Vector2i) -> Vector2:
	return Vector2(c) * CELL

static func path(start: Vector2, goal: Vector2, walls: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not Motion.free_at(goal, walls):
		return result
	var from := cell(start)
	var to := cell(goal)
	if not Motion.free_at(point(from), walls) or not Motion.free_at(point(to), walls):
		return result
	var frontier: Array[Vector2i] = [from]
	var previous := {from: from}
	var cursor := 0
	while cursor < frontier.size() and cursor < 2200:
		var current := frontier[cursor]
		cursor += 1
		if current == to:
			var trace := to
			while trace != from:
				result.push_front(point(trace))
				trace = previous[trace]
			result.append(goal)
			return result
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + offset
			if next.x < 3 or next.x > 52 or next.y < 8 or next.y > 32 or previous.has(next):
				continue
			if Motion.free_at(point(next), walls):
				previous[next] = current
				frontier.append(next)
	return result

func direction(position: Vector2, human: Vector2, walls: Array, hazards: Array, time: float, delta: float) -> Vector2:
	if mode == "wait":
		return Vector2.ZERO
	var goal := target if has_target else human
	if mode == "follow" and position.distance_to(human) <= 88.0:
		feedback = "跟随 · 保持间距"
		return Vector2.ZERO
	if has_target and position.distance_to(target) < 5.0:
		mode = "wait"
		feedback = "到达 · 等待（E 召回）"
		return Vector2.ZERO
	timer -= delta
	if timer <= 0.0 or goal.distance_to(last_goal) > 35.0:
		route = path(position, goal, walls)
		last_goal = goal
		timer = 0.6
	if route.is_empty():
		feedback = "不可达目标；右键重选 / E 召回"
		return Vector2.ZERO
	while route.size() > 1 and position.distance_to(route[0]) < 5.0:
		route.pop_front()
	var move := position.direction_to(route[0])
	var probe := position + move * 20.0
	for hazard: Dictionary in hazards:
		if preload("res://scripts/mechanisms.gd").hazard_phase(time, hazard.offset) != 0 and hazard.rect.grow(14).has_point(probe):
			feedback = "避险 · 等待激光关闭"
			return Vector2.ZERO
	if position.distance_to(human) > 218.5 and move.dot((position - human).normalized()) > 0.02:
		feedback = "连接限制 · 请玩家靠近"
		return Vector2.ZERO
	feedback = "前往目标" if has_target else "跟随 · 绕墙寻路"
	return move
