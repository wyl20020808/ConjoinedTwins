extends "res://tests/industrial_relay_theme_online.gd"

var side_frames := [{}, {}]
var side_common := 0
var sides_equal := true
var observed := {}
var mapping_ok := true
var jump_sent := false
var jump_seen := false
var mapping_reported := false

func verify() -> void:
	# 固定全局随机源，使真实服务器生成的开局种子可重现；生产网络流程不变。
	seed(4242)
	await super.verify()

func record_frame(endpoint: int, frame_index: int, game) -> void:
	game.sync_charge_gate()
	var values := []
	for slot in range(game.run.charge_gates.size()):
		var gate: Dictionary = game.run.charge_gates[slot]
		var view = game.charge_gate_views[slot].get_node("RelayPower")
		var sides: Array = game.run.gate_side_feedback(gate)
		var conditions: Dictionary = gate.get("conditions", {})
		if endpoint == 0 and mid_resume_requested and game.run.state == "running" and gate.has("relay_index") and gate.get("kind", "charge") == "sync_plates" and gate.charge > 0.2 and not gate.open and not jump_sent:
			game.touch.jump_tapped = true
			jump_sent = true
		var entry := [gate.id, gate.get("conditions", {}), sides]
		for side in range(2):
			var name := "Left" if side == 0 else "Right"
			var status: Label3D = view.get_node(name + "Status")
			var guide: MeshInstance3D = view.get_node(name + "Guide")
			var expected := "missing"
			if gate.open: expected = "opened"
			elif gate.get("kind", "charge") == "sync_plates":
				if conditions.get("occupied", [false, false])[side]: expected = "holding" if conditions.get("ready", false) else "standing"
				elif conditions.get("airborne", [false, false])[side]: expected = "airborne"
			elif conditions.get("side_present", [false, false])[side]: expected = "positioned"
			var side_ok: bool = sides[side].state == expected
			if gate.has("relay_index"):
				side_ok = side_ok and status.text == sides[side].text and status.visible == not gate.open
			else:
				side_ok = side_ok and status.text.is_empty() and not status.visible
			if not side_ok and not mapping_reported:
				print("SIDE_MAPPING_MISMATCH id=", gate.id, " side=", side, " expected=", expected, " feedback=", sides[side], " visible=", status.visible, " text=", status.text)
				mapping_reported = true
			mapping_ok = mapping_ok and side_ok
			entry.append([status.text, status.visible, status.modulate, guide.material_override.albedo_color])
			observed[sides[side].state] = true
		values.append(entry)
	if endpoint == 0 and jump_sent and not jump_seen:
		jump_seen = game.run.heights[game.net.role] > 0
		if not jump_seen: game.touch.jump_fingers[999] = true
		else: game.touch.jump_fingers.erase(999)
	side_frames[endpoint][frame_index] = var_to_str(values)
	if side_frames[1-endpoint].has(frame_index):
		side_common += 1
		sides_equal = sides_equal and side_frames[endpoint][frame_index] == side_frames[1-endpoint][frame_index]
	super.record_frame(endpoint, frame_index, game)

func verify_extra() -> void:
	super.verify_extra()
	super.check("共同帧分侧事实文字材质一致", side_common > 100 and sides_equal)
	super.check("联网每帧显示对应生产分侧事实", mapping_ok)
	super.check("联网实际到位腾空落地与持续站稳", jump_sent and observed.has("positioned") and observed.has("holding") and observed.has("missing") and observed.has("opened") and observed.has("airborne") and observed.has("standing"))
	print("READABILITY_ONLINE common_frames=", side_common, " sides_equal=", sides_equal, " mapping_ok=", mapping_ok, " jump_sent=", jump_sent, " observed=", observed.keys())
