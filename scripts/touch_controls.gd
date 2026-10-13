extends Control
# 触屏操作：左半屏按下即生成浮动摇杆，滑动方向即移动方向（吸附 8 方向，与键盘手感一致）；
# 右半屏任意位置按下即跳跃。只负责采集输入，不拦截界面按钮的点击。

const RADIUS := 90.0
const DEAD_ZONE := 0.28

var enabled := false
var blockers: Array[Control] = []
var move := Vector2.ZERO
var stick_finger := -1
var stick_origin := Vector2.ZERO
var stick_point := Vector2.ZERO
var jump_fingers := {}
var jump_tapped := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_enabled(value: bool) -> void:
	if enabled == value: return
	enabled = value
	reset()

func reset() -> void:
	move = Vector2.ZERO
	stick_finger = -1
	jump_fingers.clear()
	jump_tapped = false
	queue_redraw()

# 跳跃按住期间持续为真；极短的一次轻点也至少上报一帧，不会被漏掉。
func take_jump() -> bool:
	var pressed := jump_tapped or not jump_fingers.is_empty()
	jump_tapped = false
	return pressed

func blocked(point: Vector2) -> bool:
	for control in blockers:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point): return true
	return false

func _input(event: InputEvent) -> void:
	if not enabled: return
	if event is InputEventScreenTouch:
		var point: Vector2 = event.position
		if event.pressed:
			if blocked(point): return
			if point.x < get_viewport_rect().size.x * 0.5:
				if stick_finger < 0:
					stick_finger = event.index
					stick_origin = point
					stick_point = point
					update_move()
			else:
				jump_fingers[event.index] = true
				jump_tapped = true
		else:
			if event.index == stick_finger:
				stick_finger = -1
				move = Vector2.ZERO
			jump_fingers.erase(event.index)
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == stick_finger:
		stick_point = event.position
		update_move()
		queue_redraw()

func update_move() -> void:
	var offset := stick_point - stick_origin
	# 手指拖出半径时底座跟随，反向滑动不需要先拖回很远。
	if offset.length() > RADIUS:
		stick_origin = stick_point - offset.normalized() * RADIUS
		offset = stick_point - stick_origin
	if offset.length() < RADIUS * DEAD_ZONE:
		move = Vector2.ZERO
		return
	var angle := snappedf(offset.angle(), PI / 4.0)
	# 屏幕 y 向下；游戏里 +y 是向前（远方），与 W 键一致。
	move = Vector2(cos(angle), -sin(angle)).snapped(Vector2(0.001, 0.001))

func _draw() -> void:
	if not enabled or stick_finger < 0: return
	draw_circle(stick_origin, RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(stick_origin, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	var knob := stick_origin + (stick_point - stick_origin).limit_length(RADIUS)
	draw_circle(knob, RADIUS * 0.42, Color(0.39, 0.86, 0.9, 0.55))
