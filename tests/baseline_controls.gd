extends SceneTree

# 使用生产场景和合成触屏事件核对状态切换；不触碰桌面输入。
var failures := 0

func check(label: String, passed: bool) -> void:
	print("PASS " if passed else "FAIL ", label)
	if not passed: failures += 1

func _initialize() -> void:
	call_deferred("verify")

func held_touch(game) -> void:
	game.touch.set_enabled(true)
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = Vector2(100, 500)
	press.pressed = true
	game.touch._input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(180, 500)
	game.touch._input(drag)
	press = InputEventScreenTouch.new()
	press.index = 1
	press.position = Vector2(1000, 500)
	press.pressed = true
	game.touch._input(press)
	check("触屏夹具确实产生移动和跳跃", game.touch.move != Vector2.ZERO and game.touch.take_jump())

func cleared(game, label: String) -> void:
	check(label, game.touch.move == Vector2.ZERO and game.touch.stick_finger == -1 and not game.touch.take_jump())
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(200, 500)
	game.touch._input(drag)
	check(label + "：旧手指拖动不恢复移动", game.touch.move == Vector2.ZERO)

func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.streaming = false
	game.run.cancel_generation()
	game.run.random_seed = false
	held_touch(game)
	game.clear_controls()
	cleared(game, "清除控制同时清除触屏")
	game.run.state = "running"
	held_touch(game)
	game.apply_command("retry")
	cleared(game, "运行中重试清除触屏")
	held_touch(game)
	game.apply_command("pause")
	cleared(game, "暂停清除触屏")
	game.apply_command("pause")
	check("恢复后无旧移动或旧跳跃", game.run.state == "running" and game.touch.move == Vector2.ZERO and not game.touch.take_jump())
	held_touch(game)
	game.run.state = "failed"
	game.primary_action()
	cleared(game, "失败后共同出发清除触屏")
	# 键盘与触屏同时输入时，触屏快速点按必须在当帧消费。
	game.blocked_keys.clear()
	var keyboard := InputEventKey.new()
	keyboard.physical_keycode = KEY_SPACE
	keyboard.pressed = true
	Input.parse_input_event(keyboard)
	Input.flush_buffered_events()
	check("联机夹具确实按住键盘跳跃", game.key_down(KEY_SPACE))
	var tap := InputEventScreenTouch.new()
	tap.index = 2
	tap.position = Vector2(1000, 500)
	tap.pressed = true
	game.touch._input(tap)
	tap.pressed = false
	game.touch._input(tap)
	game.net.in_match = true
	game.online_process(1.0 / 60.0)
	check("联机键盘跳跃不延迟消费触屏点按", not game.touch.jump_tapped and not game.touch.take_jump())
	game.net.in_match = false
	keyboard.pressed = false
	Input.parse_input_event(keyboard)
	Input.flush_buffered_events()
	game.queue_free()
	await process_frame
	print("BASELINE_CONTROLS failures=", failures)
	quit(1 if failures else 0)
