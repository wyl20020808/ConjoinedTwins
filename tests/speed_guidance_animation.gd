extends SceneTree
const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
func _initialize() -> void:
	call_deferred("verify")
func check(name: String, ok: bool) -> void:
	checks.append({"name": name, "passed": ok})
	print("PASS " if ok else "FAIL ", name)
func verify() -> void:
	for direction in [Vector2.RIGHT, Vector2.DOWN, Vector2(1, 1)]:
		var r = Run.new(false)
		r.streaming = false
		r.retry()
		r.step(0)
		var a: Vector2 = r.a.position
		var b: Vector2 = r.b.position
		r.step(Run.FIXED_STEP, direction, direction)
		var automatic := Vector2(0, Run.FORWARD * Run.FIXED_STEP)
		var da: Vector2 = r.a.position - a - automatic
		var db: Vector2 = r.b.position - b - automatic
		check("双人实际8米每秒及归一化 %s" % direction, da.is_equal_approx(db) and absf(da.length() - 160 * Run.FIXED_STEP) < 0.001)
		r.dispose()
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.capture_mode = true
	var r = game.run
	r.generation_enabled = false
	check("真实双角色动画播放器", game.animation_players.size() == 2)
	for difficulty in Run.Templates.DIFFICULTIES:
		for level in range(3):
			r.difficulty = difficulty
			r.level_index = level
			r.retry()
			game.sync_view()
			for i in range(2):
				var p: AnimationPlayer = game.animation_players[i]
				p.seek(0, true)
				p.advance(0.1)
				check("实际Run播放 %s/%d/%d" % [difficulty, level, i], p.current_animation.ends_with("Run") and p.speed_scale > 1 and p.current_animation_position > 0.12)
	r.pause()
	game.sync_view()
	for p in game.animation_players:
		var pos: float = p.current_animation_position
		p.advance(0.1)
		check("暂停冻结Run播放", p.speed_scale == 0 and is_equal_approx(pos, p.current_animation_position))
	r.pause()
	game.sync_view()
	for p in game.animation_players: check("恢复Run加速", p.speed_scale > 1)
	r.heights = [30.0, 30.0]
	r.vertical_speed = [120.0, -120.0]
	game.sync_view()
	for i in range(2):
		var p: AnimationPlayer = game.animation_players[i]
		var phase: float = (Run.JUMP_SPEED - r.vertical_speed[i]) / (2 * Run.JUMP_SPEED)
		check("Jump原速及物理相位 %d" % i, p.current_animation.ends_with("Jump") and p.speed_scale == 1 and absf(p.current_animation_position - phase * p.current_animation_length) < 0.001)
	r.heights = [0.0, 0.0]
	r.state = "start"
	game.sync_view()
	for p in game.animation_players: check("Idle原速", p.current_animation.ends_with("Idle") and p.speed_scale == 1)
	r.state = "failed"
	game.sync_view()
	for p in game.animation_players:
		check("受击原速", p.current_animation.ends_with("HitRecieve_1") and p.speed_scale == 1)
		p.advance(p.current_animation_length + 0.2)
		check("死亡原速", p.current_animation.ends_with("Death") and p.speed_scale == 1)
	r.retry()
	game.sync_view()
	for p in game.animation_players: check("重试恢复Run", p.current_animation.ends_with("Run") and p.speed_scale > 1)
	game.queue_free()
	await process_frame
	var failed: int = checks.filter(func(c): return not c.passed).size()
	FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/speed-guidance/animation-result.json", FileAccess.WRITE).store_string(JSON.stringify({"passed": failed == 0, "checks": checks}, "\t"))
	quit(1 if failed else 0)
