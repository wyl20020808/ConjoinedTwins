extends RefCounted
# 手柄读取：本地双人时第一个手柄控制 01、第二个控制 02；单人与联机时第一个手柄控制本机角色。
# 摇杆按阈值量化成与键盘相同的 -1/0/1 方向，两种输入走同一套固定步移动。

const AXIS_THRESHOLD := 0.45
const TRIGGER_THRESHOLD := 0.5
const IDLE := {"move":Vector2.ZERO,"jump":false,"fire":false}
const HELD_BUTTONS := [JOY_BUTTON_A,JOY_BUTTON_RIGHT_SHOULDER]

# 回归测试无法在 headless 下连接真实手柄，可在此填入模拟设备号。
static var simulated_devices: Array = []

static func devices() -> Array:
	var pads: Array = simulated_devices.duplicate() if not simulated_devices.is_empty() else Input.get_connected_joypads()
	pads.sort()
	return pads

# 设备对应的角色；-1 表示该手柄在当前模式下不控制角色。
static func role_for(device: int, local_pair: bool) -> int:
	var index := devices().find(device)
	if index == 0: return 0
	if index == 1 and local_pair: return 1
	return -1

static func device_for(role: int, local_pair: bool) -> int:
	var pads := devices()
	if role == 0 and pads.size() > 0: return pads[0]
	if role == 1 and local_pair and pads.size() > 1: return pads[1]
	return -1

static func axis_step(value: float) -> float:
	return signf(value) if absf(value) > AXIS_THRESHOLD else 0.0

static func read(device: int) -> Dictionary:
	if device < 0: return IDLE
	var x := axis_step(Input.get_joy_axis(device, JOY_AXIS_LEFT_X))
	var y := -axis_step(Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	# 十字键优先于摇杆，便于精确对准门洞。
	var dpad := Vector2(float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT))-float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT)),
		float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP))-float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN)))
	var move := dpad if dpad != Vector2.ZERO else Vector2(x, y)
	var fire := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_THRESHOLD or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
	return {"move":move,"jump":Input.is_joy_button_pressed(device, JOY_BUTTON_A),"fire":fire}

# 菜单确认后按键可能仍按着：等全部手柄的跳跃与射击键松开后再生效，与键盘的 blocked_keys 一致。
static func any_held() -> bool:
	for device in devices():
		for button in HELD_BUTTONS:
			if Input.is_joy_button_pressed(device, button): return true
		if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_THRESHOLD: return true
	return false

# Godot 4 默认的 ui_accept 只有回车与空格；补上手柄 A，菜单焦点按钮即可用 A 确认。
static func ensure_ui_accept() -> void:
	for event in InputMap.action_get_events("ui_accept"):
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A: return
	var accept := InputEventJoypadButton.new()
	accept.device = -1
	accept.button_index = JOY_BUTTON_A
	InputMap.action_add_event("ui_accept", accept)
