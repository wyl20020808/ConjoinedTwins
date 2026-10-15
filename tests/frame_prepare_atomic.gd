extends SceneTree
class HeldRun extends "res://tests/fixtures/no_threads_run.gd":
	var held := true
	func prepare_frame() -> bool:
		if held: return false
		return super.prepare_frame()
var checks := 0
var failures := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func _initialize() -> void: call_deferred("verify")
func frame(commands: Array) -> Dictionary:
	return {"a": Vector2.ZERO, "b": Vector2.ZERO, "ja": false, "jb": false, "cmds": commands}
func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.dispose()
	game.run = HeldRun.new(true, true)
	game.run.charge_tutorial = true
	game.run.lockstep = true
	game.run.seed_value = 42
	game.run.retry()
	game.run.state = "start"
	game.net.in_match = true
	game.net.next_frame = 0
	game.net.frames = [frame([[0,"retry",""]]), frame([[0,"pause",""]])]
	var applied: Array = []
	game.online_frame_applied.connect(func(index): applied.append(index))
	game.online_process(1.0/60)
	var seed_after_command: int = game.run.seed_value
	var hash_after_command: int = game.run.sync_hash()
	for poll in range(12): game.online_process(1.0/60)
	check("准备未完成时完整保留输入帧及编号", game.net.next_frame == 0 and game.net.frames.size() == 2 and applied.is_empty())
	check("重试命令在等待期间只执行一次", game.run.seed_value == seed_after_command and game.run.sync_hash() == hash_after_command)
	check("等待期间保持UI可刷新且没有整段补算", game.generation_waiting and game.run.async_deadline_steps == 0)
	game.run.held = false
	for poll in range(1000):
		game.online_process(1.0/60)
		if game.net.frames.is_empty(): break
	check("就绪后按原编号连续应用而非跳帧", applied == [0,1] and game.net.next_frame == 2 and game.net.frames.is_empty())
	check("随后暂停命令恰好生效一次", game.run.state == "paused" and game.run.seed_value == seed_after_command)
	# 快照不得保存可暂停任务句柄，否则恢复会重新挂上已取消的验证器。
	var pending = HeldRun.new(true, true)
	pending.capture_checkpoint()
	check("存档不保存合作验证任务句柄", not pending.checkpoint.run.has("cooperative_job"))
	pending.fail_threat("fixture")
	var restored: bool = pending.restore_checkpoint()
	pending.step(pending.FIXED_STEP)
	check("恢复重建调度而不引用已取消任务", restored and (pending.cooperative_job == null or pending.async_job.has("base")))
	pending.dispose()
	game.net.in_match = false
	for player in game.sfx.players:
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	print("RESULT %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
