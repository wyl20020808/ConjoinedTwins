extends Control
# 触屏操作：左半屏按下即生成浮动摇杆，滑动方向即移动方向（吸附 8 方向，与键盘手感一致）；
# 旧道路入口右半屏按下跳跃；旅程入口启用独立战斗按钮。

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
var combat_buttons := false
var action_fingers := {}
var fire_tapped := false
var reload_tapped := false
var drop_tapped := false
var swap_tapped := false

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
	action_fingers.clear()
	fire_tapped=false
	reload_tapped=false
	drop_tapped=false
	swap_tapped=false
	queue_redraw()

# 跳跃按住期间持续为真；极短的一次轻点也至少上报一帧，不会被漏掉。
func take_jump() -> bool:
	var pressed := jump_tapped or not jump_fingers.is_empty()
	jump_tapped = false
	return pressed

func take_combat() -> Dictionary:
	var result := {"fire":fire_tapped or "fire" in action_fingers.values(),"reload":reload_tapped,"drop":drop_tapped,"swap":swap_tapped}
	fire_tapped=false
	reload_tapped=false
	drop_tapped=false
	swap_tapped=false
	return result

func action_circles() -> Dictionary:
	var viewport := get_viewport_rect().size
	var scale := minf(1.0,minf(viewport.x*0.45/350.0,viewport.y*0.46/290.0))
	var origin := viewport-Vector2(22,30)*scale
	return {"jump":Vector3(origin.x-72*scale,origin.y-72*scale,64*scale),
		"fire":Vector3(origin.x-235*scale,origin.y-80*scale,74*scale),
		"reload":Vector3(origin.x-65*scale,origin.y-212*scale,36*scale),
		"drop":Vector3(origin.x-175*scale,origin.y-225*scale,36*scale),
		"swap":Vector3(origin.x-285*scale,origin.y-195*scale,36*scale)}

func action_at(point: Vector2) -> String:
	for action in action_circles():
		var circle: Vector3=action_circles()[action]
		if point.distance_to(Vector2(circle.x,circle.y))<=circle.z: return action
	return ""

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT: reset()

func blocked(point: Vector2) -> bool:
	for control in blockers:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point): return true
	return false

func _input(event: InputEvent) -> void:
	if not enabled: return
	if event is InputEventScreenTouch:
		var point: Vector2 = event.position
		if event.pressed and not event.canceled:
			if blocked(point): return
			if point.x < get_viewport_rect().size.x * 0.5:
				if stick_finger < 0:
					stick_finger = event.index
					stick_origin = point
					stick_point = point
					update_move()
			else:
				var action := action_at(point) if combat_buttons else "jump"
				if action=="jump":
					jump_fingers[event.index] = true
					jump_tapped = true
				elif not action.is_empty():
					action_fingers[event.index]=action
					if action=="fire": fire_tapped=true
					elif action=="reload": reload_tapped=true
					elif action=="drop": drop_tapped=true
					elif action=="swap": swap_tapped=true
		else:
			if event.index == stick_finger:
				stick_finger = -1
				move = Vector2.ZERO
			jump_fingers.erase(event.index)
			action_fingers.erase(event.index)
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
	if not enabled: return
	if combat_buttons:
		var font := ThemeDB.fallback_font
		var titles := {"fire":"射击","jump":"跳跃","reload":"换弹","drop":"丢弃","swap":"换枪"}
		for action in action_circles():
			var circle: Vector3=action_circles()[action]
			var center := Vector2(circle.x,circle.y)
			var held: bool=not jump_fingers.is_empty() if action=="jump" else action in action_fingers.values()
			var color := Color(0.1,0.38,0.4,0.68) if action!="jump" else Color(0.5,0.32,0.13,0.72)
			if held: color=color.lightened(0.3)
			draw_circle(center,circle.z,color)
			draw_arc(center,circle.z,0,TAU,48,Color(0.85,0.95,0.95,0.8),2.0)
			var font_size := int(circle.z*0.42)
			var text: String=titles[action]
			var text_width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
			draw_string(font,center+Vector2(-text_width/2,font_size*0.35),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.WHITE)
	if stick_finger<0: return
	draw_circle(stick_origin, RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(stick_origin, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	var knob := stick_origin + (stick_point - stick_origin).limit_length(RADIUS)
	draw_circle(knob, RADIUS * 0.42, Color(0.39, 0.86, 0.9, 0.55))
