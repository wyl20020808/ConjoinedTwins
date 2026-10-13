extends Node2D

const Motion = preload("res://scripts/link_motion.gd")
const Levels = preload("res://scripts/levels.gd")
const Mechanisms = preload("res://scripts/mechanisms.gd")
const Partner = preload("res://scripts/partner_ai.gd")
const Twin = preload("res://scripts/twin.gd")
var a: Node2D
var b: Node2D
var ai = Partner.new()
var mechanisms = Mechanisms.new()
var level: Dictionary
var level_index := 0
var clock := 0.0
var local_two := false
var paused := false
var won := false
var manual_tick := false
var checkpoint: Array = []
var deaths := 0
var hud: Label
var menu: PanelContainer
var menu_title: Label
var mode_button: Button
var notice := "右键指挥队友；Q 等待；E 召回"
var input_clear_frames := 0

func _ready() -> void:
	y_sort_enabled = true
	a = Twin.new()
	b = Twin.new()
	b.tint = Color(1, 0.65, 0.2)
	b.number = "2"
	add_child(a)
	add_child(b)
	build_ui()
	load_level(0)

func build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(28, 14)
	hud.size = Vector2(1044, 115)
	hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_theme_font_size_override("font_size", 16)
	canvas.add_child(hud)
	menu = PanelContainer.new()
	menu.position = Vector2(280, 160)
	menu.custom_minimum_size = Vector2(540, 390)
	canvas.add_child(menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	menu.add_child(column)
	menu_title = Label.new()
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_title.text = "暂停 / 操作说明"
	column.add_child(menu_title)
	var help := Label.new()
	help.text = "WASD 玩家一 / 方向键 玩家二\n右键：AI 前往并等待（目标为鼠标位置）\nQ：等待 / 跟随    E：召回\nR：检查点重开    Esc：暂停\n能量线可穿墙，角色不可穿墙；最大长度 220\n危险：虚线关闭 / 三角预警 / 斜纹开启\n两名角色都进入出口才会切关"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(help)
	add_button(column, "继续", func(): paused = false; refresh_ui())
	mode_button = add_button(column, "", func(): set_mode(not local_two))
	add_button(column, "检查点重开", func(): respawn(); paused = false; refresh_ui())
	add_button(column, "返回第一关 / 重新游玩", func(): load_level(0); paused = false; refresh_ui())
	menu.hide()

func add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func load_level(index: int) -> void:
	level_index = index
	level = Levels.create(index)
	checkpoint = level.spawn.duplicate()
	clock = 0.0
	won = false
	paused = false
	mechanisms.reset()
	respawn()
	notice = level.hint
	refresh_ui()

func walls() -> Array:
	var result: Array = level.walls.duplicate()
	for gate: Dictionary in level.gates:
		if not gate.open:
			result.append(gate.rect)
	return result

func respawn() -> void:
	a.position = checkpoint[0]
	b.position = checkpoint[1]
	ai.reset()
	mechanisms.charge = 0.0
	input_clear_frames = 1
	notice = "共同恢复至检查点"
	queue_redraw()

func set_mode(two: bool) -> void:
	local_two = two
	ai.reset()
	input_clear_frames = 1
	notice = "本地双人：方向键控制 2" if two else "单人 + 离线 AI：已恢复跟随"
	refresh_ui()

func command_target(target: Vector2) -> void:
	if not local_two and not paused and not won:
		ai.command(target, b.position, walls())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				paused = not paused
				input_clear_frames = 1
				refresh_ui()
			KEY_R:
				if not won:
					respawn()
			KEY_E:
				if not paused and not local_two:
					ai.reset()
			KEY_Q:
				if not paused and not local_two:
					if ai.mode == "wait":
						ai.reset()
					else:
						ai.wait()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Use this click's viewport coordinate, including canvas transforms, rather than a later cursor poll.
		command_target(get_global_transform_with_canvas().affine_inverse() * event.position)

func keyboard(keys: Array) -> Vector2:
	return Vector2(float(Input.is_physical_key_pressed(keys[1])) - float(Input.is_physical_key_pressed(keys[0])), float(Input.is_physical_key_pressed(keys[3])) - float(Input.is_physical_key_pressed(keys[2]))).limit_length()

func _physics_process(delta: float) -> void:
	if not manual_tick:
		var first := keyboard([KEY_A, KEY_D, KEY_W, KEY_S])
		var second := keyboard([KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN])
		if input_clear_frames > 0:
			first = Vector2.ZERO
			second = Vector2.ZERO
			input_clear_frames -= 1
		simulate(delta, first, second)

func simulate(delta: float, first: Vector2 = Vector2.ZERO, second: Vector2 = Vector2.ZERO) -> void:
	if paused or won:
		return
	clock += delta
	var obstacles := walls()
	var partner_input := second if local_two else ai.direction(b.position, a.position, obstacles, level.hazards, clock, delta)
	Motion.advance(a, b, first, partner_input, delta, obstacles)
	var event: String = mechanisms.update(level, a.position, b.position, delta, clock)
	if mechanisms.checkpoint_active:
		checkpoint = [Vector2(510, 370), Vector2(560, 420)]
	match event:
		"death":
			deaths += 1
			respawn()
			# Give both twins a safe new timing window without moving hazards' geometry.
			clock = 0.0
		"exit":
			if level_index < 2:
				load_level(level_index + 1)
			else:
				won = true
				paused = true
	refresh_ui()
	queue_redraw()

func refresh_ui() -> void:
	var length := a.position.distance_to(b.position)
	var tension := "张紧" if length >= 187 else "松弛"
	var state: String = "本地双人" if local_two else ai.feedback
	var target_text := " · 目标 (%d,%d)" % [ai.target.x, ai.target.y] if ai.has_target else ""
	hud.text = "%s    连线 %.1f / 220 · %s    %s%s\n%s\nWASD 移动  右键指令  Q 等待  E 召回  R 重开  Esc 菜单 | %s" % [level.title, length, tension, state, target_text, level.hint, notice]
	mode_button.text = "切换为单人 + AI" if local_two else "切换为本地双人"
	menu_title.text = "三关完成！重新游玩或继续观察" if won else "暂停 / 操作说明"
	menu.visible = paused or won

func text_at(p: Vector2, text: String, color := Color.WHITE, size := 16) -> void:
	draw_string(ThemeDB.fallback_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw() -> void:
	if level == null or level.is_empty():
		return
	draw_rect(Rect2(40, 140, 1020, 520), Color(0.10, 0.14, 0.19))
	for x in range(60, 1060, 40):
		draw_line(Vector2(x, 140), Vector2(x, 660), Color(0.15, 0.19, 0.24))
	for y in range(140, 660, 40):
		draw_line(Vector2(40, y), Vector2(1060, y), Color(0.15, 0.19, 0.24))
	for wall: Rect2 in level.walls:
		draw_rect(wall, Color(0.32, 0.38, 0.45))
		draw_line(wall.position, wall.position + Vector2(wall.size.x, 0), Color(0.6, 0.67, 0.72), 3)
	for i in range(level.plates.size()):
		var plate: Vector2 = level.plates[i]
		var active: bool = mechanisms.plate_occupied.size() > i and mechanisms.plate_occupied[i]
		draw_circle(plate, 24, Color(0.2, 0.8, 0.5) if active else Color(0.42, 0.35, 0.16))
		draw_arc(plate, 24, 0, TAU, 32, Color(1, 0.8, 0.3), 2)
		text_at(plate + Vector2(-25, -32), "合作板 %d" % (i + 1))
	for gate: Dictionary in level.gates:
		draw_rect(gate.rect, Color(0.1, 0.65, 0.35, 0.18) if gate.open else Color(0.95, 0.5, 0.2))
		text_at(gate.rect.position + Vector2(-25, 25), "已锁存" if gate.open else "门")
	for hazard: Dictionary in level.hazards:
		var phase: int = Mechanisms.hazard_phase(clock, hazard.offset)
		var rect: Rect2 = hazard.rect
		var colors := [Color(0.15, 0.55, 0.5, 0.22), Color(1, 0.75, 0.1, 0.5), Color(1, 0.18, 0.25, 0.65)]
		draw_rect(rect, colors[phase])
		for y in range(160, 640, 28):
			if phase == 0:
				draw_line(Vector2(rect.position.x + 24, y), Vector2(rect.position.x + 24, y + 12), Color.CYAN, 2)
			elif phase == 1:
				draw_colored_polygon(PackedVector2Array([Vector2(rect.position.x + 24, y), Vector2(rect.position.x + 12, y + 20), Vector2(rect.position.x + 36, y + 20)]), Color.YELLOW)
			else:
				draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y + 24), Color(1, 0.7, 0.7), 3)
		text_at(rect.position + Vector2(-5, 20), ["关闭", "预警", "危险"][phase])
	if level.checkpoint.size != Vector2.ZERO:
		draw_rect(level.checkpoint, Color(0.2, 0.7, 0.95, 0.12))
		text_at(level.checkpoint.position + Vector2(0, 20), "安全岛 · 检查点" if not mechanisms.checkpoint_active else "检查点已激活", Color.CYAN)
	var receiver: Vector2 = level.receiver
	if receiver != Vector2.ZERO:
		draw_circle(receiver, 18, Color(0.5, 0.3, 0.8))
		draw_arc(receiver, 24, -PI / 2, -PI / 2 + TAU * mechanisms.charge / 0.8, 40, Color.CYAN, 5)
		text_at(receiver + Vector2(-65, 45), "张紧穿过 · 充能 %.0f%%" % (mechanisms.charge / 0.8 * 100))
		for p in [Vector2(650, 285), Vector2(650, 495)]:
			draw_arc(p, 20, 0, TAU, 32, Color(0.7, 0.6, 1), 2)
	var exit: Rect2 = level.exit
	draw_rect(exit, Color(0.2, 0.8, 0.45, 0.23))
	draw_rect(exit, Color(0.3, 1, 0.6), false, 2)
	text_at(exit.position + Vector2(5, 40), "双人出口", Color(0.4, 1, 0.6), 14)
	text_at(exit.position + Vector2(-45, exit.size.y + 25), "右键指挥队友进入", Color(0.4, 1, 0.6), 14)
	var taut := a.position.distance_to(b.position) >= 187
	draw_line(a.position, b.position, Color(1, 0.75, 0.2) if taut else Color(0.3, 0.85, 1), 4 if taut else 2)
	if ai.has_target and not local_two:
		draw_arc(ai.target, 10, 0, TAU, 24, Color(1, 0.7, 0.2), 2)
		draw_line(ai.target - Vector2(15, 0), ai.target + Vector2(15, 0), Color.WHITE)
		draw_line(ai.target - Vector2(0, 15), ai.target + Vector2(0, 15), Color.WHITE)
