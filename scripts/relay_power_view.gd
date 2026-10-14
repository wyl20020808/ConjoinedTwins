extends RefCounted

# 工业接力的程序显示层。只消费门的既有状态，不改变碰撞、计时或随机生成。
static func build(game, view: Node3D) -> void:
	var power := Node3D.new()
	power.name = "RelayPower"
	power.visible = false
	view.add_child(power)
	var steel = game.material("relay_steel", Color("385360"))
	for side in [-1, 1]:
		game.box(power, Vector3(side * 10.9, 1.4, -7.8), Vector3(0.45, 2.8, 0.5), steel)
	var lamp = game.box(power, Vector3(0, 5.45, -7.8), Vector3(4.2, 0.22, 0.25), steel)
	lamp.name = "PowerLamp"
	for side in [-1, 1]:
		var guide = game.box(power, Vector3(side * 2.475, 0.04, -0.8), Vector3(0.12, 0.02, 1.4), steel)
		guide.name = "LeftGuide" if side < 0 else "RightGuide"
		# 箭头朝道路远方；无碰撞，保留原站位区边界可见。
		for direction in [-1, 1]:
			var tip = game.box(guide, Vector3(direction * 0.2, 0, -0.55), Vector3(0.1, 0.02, 0.55), steel)
			tip.rotation.y = direction * PI / 4.0
		var status := Label3D.new()
		status.name = "LeftStatus" if side < 0 else "RightStatus"
		status.position = Vector3(side * 2.475, 0.65, -0.8)
		status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		status.font_size = 32
		status.pixel_size = 0.008
		power.add_child(status)
	var forward := Node3D.new()
	forward.name = "ForwardGuide"
	power.add_child(forward)
	for n in range(3):
		for side in [-1, 1]:
			var arrow = game.box(forward, Vector3(side * 0.3, 0.04, -9.5 - n * 1.8), Vector3(0.12, 0.02, 0.85), steel)
			arrow.rotation.y = side * PI / 4.0
	var rail = game.box(power, Vector3(0, 0.05, -14), Vector3(8, 0.03, 0.16), steel)
	rail.name = "ExitRail"
	var light := OmniLight3D.new()
	light.name = "ExitLight"
	light.position = Vector3(0, 2, -14)
	light.omni_range = 6.0
	light.light_energy = 0
	light.shadow_enabled = false
	power.add_child(light)
	var sign := Label3D.new()
	sign.name = "Sign"
	sign.position = Vector3(0, 6, -7.8)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 40
	sign.pixel_size = 0.008
	power.add_child(sign)

static func sync(game, view: Node3D, gate: Dictionary) -> void:
	var power: Node3D = view.get_node("RelayPower")
	var themed := gate.has("relay_index")
	power.visible = themed
	var sign: Label3D = power.get_node("Sign")
	var light: OmniLight3D = power.get_node("ExitLight")
	# 每次完整覆盖，包括普通门复用接力槽，不能继承旧出口照明。
	light.light_energy = 0
	if not themed:
		sign.text = ""
		for name in ["LeftStatus", "RightStatus"]:
			power.get_node(name).text = ""
			power.get_node(name).visible = false
		return
	var last: bool = int(gate.relay_index) == int(gate.relay_count) - 1
	var opened: bool = gate.open
	var charging: bool = gate.charge > 0 and not opened
	var state := "on" if opened else ("charging" if charging else "off")
	var tint := Color("68dce3") if opened else (Color("ffc06b") if charging else Color("687782"))
	# 缓存按固定状态键取材质；不修改共享材质，避免多门串色。
	var surface = game.material("relay_power_" + state, tint, 0.65 if opened else (0.3 if charging else 0.0))
	power.get_node("PowerLamp").material_override = surface
	var sides: Array = game.run.gate_side_feedback(gate)
	for side in range(2):
		var guide: MeshInstance3D = power.get_node("LeftGuide" if side == 0 else "RightGuide")
		var status: Label3D = power.get_node("LeftStatus" if side == 0 else "RightStatus")
		var side_state: String = sides[side].state
		var side_tint := Color("687782")
		if side_state == "airborne": side_tint = Color("ef956b")
		elif side_state == "holding": side_tint = Color("ffc06b")
		elif side_state in ["standing", "positioned", "opened"]: side_tint = Color("68dce3")
		var side_surface = game.material("relay_side_" + side_state, side_tint, 0.0 if side_state == "missing" else 0.3)
		guide.visible = not opened
		guide.material_override = side_surface
		for tip in guide.get_children(): tip.material_override = side_surface
		status.visible = not opened
		status.text = sides[side].text
		status.modulate = side_tint
	var forward: Node3D = power.get_node("ForwardGuide")
	forward.visible = opened
	for arrow in forward.get_children(): arrow.material_override = surface
	var rail: MeshInstance3D = power.get_node("ExitRail")
	rail.visible = last and opened
	rail.material_override = surface
	light.light_color = tint
	light.light_energy = 0.8 if last and opened else 0.0
	var stage := "02 双板接力" if last else "01 接线供能"
	var feedback := "等待供能" if not charging else "供能中"
	if opened: feedback = "已供电 · 出口已照明" if last else "已供电 · 前往 02"
	sign.text = stage + " · " + feedback
	sign.modulate = tint
