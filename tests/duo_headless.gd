extends SceneTree

const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
var game

func _initialize() -> void:
	call_deferred("verify")

func check(label: String, passed: bool) -> void:
	checks.append({"name": label, "passed": passed})
	print("PASS " if passed else "FAIL ", label)

func fresh():
	game.run.retry()
	game.run.step(1.0 / 60)
	return game.run

func ticks(r, count: int, first := Vector2.ZERO, second := Vector2.ZERO, ja := false, jb := false) -> void:
	for i in range(count):
		r.step(1.0 / 60, first, second, ja, jb)

func key_event(key: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	return event

func verify() -> void:
	game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	check("生产场景初始为开始页，无模式按钮", game.run.state == "start" and game.get("mode_button") == null)
	check("道路实际可玩宽度扩大 1.5 倍", Run.EDGE / 156.0 >= 1.4)
	check("George / Leela 均有 AnimationPlayer", game.animation_players.size() == 2)
	for i in range(game.animation_players.size()):
		var player: AnimationPlayer = game.animation_players[i]
		for action in ["Idle", "Run", "Jump", "HitRecieve_1", "Death"]:
			var found := false
			for name in player.get_animation_list():
				if name.ends_with(action):
					found = player.get_animation(name).get_track_count() > 0
					player.play(name)
					player.advance(0.1)
			check("角色 %d 骨骼动画 %s 可播放" % [i + 1, action], found)
	var r = fresh()
	var before: Vector2 = r.b.position
	ticks(r, 10, Vector2.RIGHT)
	check("玩家一独立横移，无 AI 接管玩家二", r.a.position.x > -42 and r.b.position.x == before.x)
	r = fresh()
	ticks(r, 10, Vector2.ZERO, Vector2.LEFT)
	check("玩家二独立横移", r.a.position.x == -42 and r.b.position.x < 42)
	r = fresh()
	ticks(r, 10, Vector2.UP, Vector2.DOWN)
	check("两人独立前后调节", r.a.position.y < r.distance and r.b.position.y > r.distance)
	r = fresh()
	var pa: Vector2 = r.a.position
	var d: float = r.distance
	ticks(r, 8, Vector2.ONE, Vector2.ONE)
	var diagonal: float = (r.a.position - pa - Vector2(0, r.distance - d)).length()
	r = fresh()
	pa = r.a.position
	ticks(r, 8, Vector2.RIGHT, Vector2.RIGHT)
	var straight: float = (r.a.position - pa - Vector2(0, Run.FORWARD * 8.0 / 60)).length()
	check("斜向输入归一化，不额外加速", absf(diagonal - straight) < 0.01)
	r = fresh()
	ticks(r, 100, Vector2.ONE, Vector2.ONE)
	check("道路边界和前后活动范围合法", absf(r.a.position.x) <= Run.EDGE and absf(r.a.position.y - r.distance) <= Run.RELATIVE_RANGE + 0.001)
	r = fresh()
	ticks(r, 100, Vector2(-1, -1), Vector2(1, 1))
	check("地面连接包含前后差并限制长度", r.a.position.distance_to(r.b.position) <= Run.Motion.LIMIT + 0.001 and absf(r.a.position.y - r.b.position.y) > 20)
	r = fresh()
	ticks(r, 12, Vector2.ZERO, Vector2.ZERO, true)
	check("仅玩家一起跳，队友不强制起跳", r.heights[0] > 0 and r.heights[1] == 0)
	game.sync_view()
	check("连线随跳跃抬高且阴影仍在地面", game.robots[0].position.y > 0 and game.shadows[0].position.y < 0.02 and absf(game.cable.quaternion.z) > 0.01)
	var velocity: float = r.vertical_speed[0]
	ticks(r, 1, Vector2.ZERO, Vector2.ZERO, false)
	ticks(r, 1, Vector2.ZERO, Vector2.ZERO, true)
	check("空中再次按下无二段跳", r.vertical_speed[0] < velocity)
	ticks(r, 100, Vector2.ZERO, Vector2.ZERO, true)
	check("长按跳跃不会落地连跳", r.heights[0] == 0)
	ticks(r, 1)
	ticks(r, 1, Vector2.ZERO, Vector2.ZERO, false, true)
	check("玩家二可独立跳跃", r.heights[1] > 0 and r.heights[0] == 0)
	r.retry()
	ticks(r, 12, Vector2.ZERO, Vector2.ZERO, true, true)
	check("启动或重试按住跳跃无附带起跳", r.heights == [0.0, 0.0])
	ticks(r, 1)
	ticks(r, 10, Vector2.ZERO, Vector2.ZERO, true)
	var positions := [r.a.position, r.b.position]
	var heights: Array = r.heights.duplicate()
	var elapsed: float = r.elapsed
	r.pause()
	ticks(r, 60, Vector2.ONE, Vector2.ONE, true, true)
	check("暂停冻结位置、高度及计时", positions == [r.a.position, r.b.position] and heights == r.heights and elapsed == r.elapsed)
	r.pause()
	var prior_velocity: float = r.vertical_speed[0]
	ticks(r, 1, Vector2.ZERO, Vector2.ZERO, true, true)
	check("恢复清理跳跃残留，不新增起跳", r.heights[1] == 0 and r.vertical_speed[0] < prior_velocity)
	r = fresh()
	var original_obstacles: Array = r.obstacles.duplicate()
	var original_kinds: Array = r.kinds.duplicate()
	var original_heights: Array = r.obstacle_heights.duplicate()
	# 明确夹具：与生产相同的碰撞代码；低障碍并非本任务新增关卡内容。
	r.obstacles.assign([Rect2(-55, 45, 26, 4)])
	r.kinds.assign(["cargo"])
	r.obstacle_heights.assign([8.0])
	ticks(r, 35, Vector2.ZERO, Vector2.ZERO, true)
	check("跳跃高度允许跨越低障碍", r.state == "running" and r.a.position.y > 49)
	r = fresh()
	ticks(r, 35)
	check("同一低障碍地面接触共同失败", r.state == "failed")
	r = fresh()
	r.obstacle_heights[0] = 34.0
	ticks(r, 35, Vector2.ZERO, Vector2.ZERO, true)
	check("跳跃不能穿越高货箱", r.state == "failed")
	check("连续线段检查捕获高速穿越", Run.segment_hits(Vector2(-100, 0), Vector2(100, 0), Rect2(-1, -1, 2, 2)))
	r.obstacles.assign(original_obstacles)
	r.kinds.assign(original_kinds)
	r.obstacle_heights.assign(original_heights)
	r = fresh()
	# 双人预先向右侧宽走廊移动，随后自然自动推进；不改生产障碍或角色位置。
	ticks(r, 100, Vector2.RIGHT, Vector2.RIGHT)
	ticks(r, 4600)
	check("真实生产双人路线完成 450 米", r.state == "finished" and r.a.position.y == Run.FINISH and r.b.position.y == Run.FINISH)
	r.retry()
	check("共同重试恢复双方合法地面状态", r.a.position == Vector2(-42, 0) and r.b.position == Vector2(42, 0) and r.heights == [0.0, 0.0] and r.distance == 0)
	# 合成键盘事件仅验证生产映射，不代表设备多键并按能力。
	game.clear_controls()
	game._physics_process(1.0 / 60)
	key_event(KEY_W, true)
	key_event(KEY_DOWN, true)
	for i in range(10): game._physics_process(1.0 / 60)
	check("生产 WASD / 方向键前后映射，无 W/上跳跃", r.a.position.y > r.distance and r.b.position.y < r.distance and r.heights == [0.0, 0.0])
	key_event(KEY_W, false)
	key_event(KEY_DOWN, false)
	key_event(KEY_SPACE, true)
	game._physics_process(1.0 / 60)
	check("生产空格只跳玩家一", r.heights[0] > 0 and r.heights[1] == 0)
	key_event(KEY_ENTER, true)
	game._physics_process(1.0 / 60)
	check("生产回车跳玩家二", r.heights[1] > 0)
	game._unhandled_key_input(key_event(KEY_ESCAPE, true))
	game._unhandled_key_input(key_event(KEY_ESCAPE, true))
	for i in range(90): game._physics_process(1.0 / 60)
	check("生产恢复后按住旧跳跃键不连跳", r.heights == [0.0, 0.0])
	game._unhandled_key_input(key_event(KEY_R, true))
	for i in range(10): game._physics_process(1.0 / 60)
	check("生产重试清理空格回车残留", r.heights == [0.0, 0.0])
	key_event(KEY_SPACE, false)
	key_event(KEY_ENTER, false)
	key_event(KEY_ESCAPE, false)
	key_event(KEY_R, false)
	r.state = "start"
	game._unhandled_key_input(key_event(KEY_ENTER, true))
	for i in range(10): game._physics_process(1.0 / 60)
	check("回车启动不会同时跳跃", r.state == "running" and r.heights == [0.0, 0.0])
	key_event(KEY_ENTER, false)
	r.state = "start"
	game._unhandled_key_input(key_event(KEY_SPACE, true))
	for i in range(10): game._physics_process(1.0 / 60)
	check("空格启动不会同时跳跃", r.state == "running" and r.heights == [0.0, 0.0])
	key_event(KEY_SPACE, false)
	game.sync_view()
	var bad := 0
	for item in checks:
		if not item.passed: bad += 1
	var output := FileAccess.open("res://tests/duo-result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed": bad == 0, "checks": checks, "failures": bad, "scope": "执行者生产场景 headless 自测，非真实键盘及 GUI 验收"}, "\t"))
	print("DUO RESULT ", checks.size(), " checks, ", bad, " failures")
	game.queue_free()
	await process_frame
	quit(0 if bad == 0 else 1)
