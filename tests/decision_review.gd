extends SceneTree

# Isolated headless checks; synthetic events never use desktop input devices.
var game
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
	print("PASS: " if condition else "FAIL: ", message)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	game._unhandled_input(event)

func button(text: String) -> Button:
	for child in game.menu.get_child(0).get_children():
		if child is Button and child.text == text:
			return child
	return null

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.manual_tick = true
	await process_frame
	key(KEY_Q)
	check(game.ai.mode == "wait", "Q handler enters wait")
	key(KEY_Q)
	check(game.ai.mode == "follow", "Q handler resumes follow")
	game.command_target(Vector2(280, 390))
	key(KEY_E)
	check(game.ai.mode == "follow" and not game.ai.has_target, "E handler clears target and recalls")
	key(KEY_ESCAPE)
	check(game.paused and game.menu.visible, "Esc handler opens pause menu")
	game.command_target(Vector2(280, 390))
	key(KEY_Q)
	check(not game.ai.has_target and game.ai.mode == "follow", "Paused world rejects target and Q commands")
	var before: Vector2 = game.a.position
	var clock: float = game.clock
	game.simulate(1.0 / 60.0, Vector2.RIGHT)
	check(game.a.position == before and game.clock == clock, "Pause freezes production movement and clock")
	game.mode_button.pressed.emit()
	check(game.local_two and game.paused, "Mode menu callback selects local two while paused")
	button("继续").pressed.emit()
	check(not game.paused and not game.menu.visible, "Continue callback closes pause menu")
	game.command_target(Vector2(280, 390))
	check(not game.ai.has_target, "Local two rejects AI target commands")
	game.set_mode(false)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_D
	event.keycode = KEY_D
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	check(game.keyboard([KEY_A, KEY_D, KEY_W, KEY_S]) == Vector2.RIGHT, "Synthetic D reaches physical-key polling")
	game.manual_tick = false
	game._physics_process(1.0 / 60.0)
	check(game.a.position == before, "Mode switch clears one frame of movement input")
	game._physics_process(1.0 / 60.0)
	check(game.a.position.x > before.x, "Production physics handler moves player from keyboard state")
	var release := event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	game.manual_tick = true
	check(game.keyboard([KEY_A, KEY_D, KEY_W, KEY_S]) == Vector2.ZERO, "Synthetic key release clears keyboard state")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(280, 390)
	motion.global_position = motion.position
	root.push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = motion.position
	click.global_position = motion.position
	root.push_input(click, true)
	if not game.ai.has_target or game.ai.target.distance_to(motion.position) >= 1:
		print("Input state: viewport_mouse=", root.get_mouse_position(), " global_mouse=", game.get_global_mouse_position(), " target=", game.ai.target, " has_target=", game.ai.has_target)
	check(game.ai.has_target and game.ai.target.distance_to(motion.position) < 1, "Viewport right-click targets actual ground coordinate")
	game.position = Vector2(25, 30)
	game.scale = Vector2(0.8, 0.8)
	var ground := Vector2(300, 410)
	var transformed_click := InputEventMouseButton.new()
	transformed_click.button_index = MOUSE_BUTTON_RIGHT
	transformed_click.pressed = true
	transformed_click.position = game.get_global_transform_with_canvas() * ground
	transformed_click.global_position = transformed_click.position
	root.push_input(transformed_click, true)
	check(game.ai.has_target and game.ai.target.distance_to(ground) < 1, "Right-click coordinate respects scene translation and scale")
	game.position = Vector2.ZERO
	game.scale = Vector2.ONE
	key(KEY_R)
	check(game.a.position == game.checkpoint[0] and game.b.position == game.checkpoint[1] and not game.ai.has_target, "R handler restores both characters and clears commands")
	game.command_target(Vector2(280, 390))
	game.paused = true
	game.refresh_ui()
	button("检查点重开").pressed.emit()
	check(not game.paused and not game.ai.has_target and game.a.position == game.checkpoint[0] and game.b.position == game.checkpoint[1], "Checkpoint restart callback clears commands and resumes play")
	game.load_level(2)
	game.paused = true
	button("返回第一关 / 重新游玩").pressed.emit()
	check(game.level_index == 0 and not game.paused and not game.won, "Return-to-start callback rebuilds playable first level")
	game.load_level(2)
	game.won = true
	game.paused = true
	game.refresh_ui()
	check(game.menu.visible and game.menu_title.text.contains("三关完成"), "Completion state shows restart menu")
	button("返回第一关 / 重新游玩").pressed.emit()
	game.simulate(1.0 / 60.0, Vector2.RIGHT)
	check(game.level_index == 0 and not game.won and not game.paused and game.a.position.x > game.checkpoint[0].x, "Completion restart restores production movement")
	var report := {"checks": checks, "failures": failures, "status": "PASS" if failures.is_empty() else "FAIL", "scope": "真正 headless 的生产输入处理、合成视口事件和菜单回调；不使用桌面输入，不代表视觉验收"}
	var output := FileAccess.open("res://tests/decision_review_result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("RESULT ", JSON.stringify(report))
	game.queue_free()
	quit(0 if failures.is_empty() else 1)
