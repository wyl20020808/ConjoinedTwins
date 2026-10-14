extends "res://tests/cooperative_relay_recovery_online.gd"

# 在同一已应用 UDP 帧上同步并读取真实主题节点，避免比较不同渲染时刻。
var power_frames := [{}, {}]
var power_common := 0
var power_equal := true
var exit_seen := false

func record_frame(endpoint: int, frame_index: int, game) -> void:
	game.sync_charge_gate()
	var values := []
	for slot in range(game.run.charge_gates.size()):
		var gate: Dictionary = game.run.charge_gates[slot]
		var power = game.charge_gate_views[slot].get_node("RelayPower")
		var lamp: MeshInstance3D = power.get_node("PowerLamp")
		var light: OmniLight3D = power.get_node("ExitLight")
		values.append([gate.id, power.visible, lamp.material_override.albedo_color, power.get_node("Sign").text, light.light_energy])
		exit_seen = exit_seen or light.light_energy > 0
	power_frames[endpoint][frame_index] = var_to_str(values)
	if power_frames[1-endpoint].has(frame_index):
		power_common += 1
		power_equal = power_equal and power_frames[endpoint][frame_index] == power_frames[1-endpoint][frame_index]
	super.record_frame(endpoint, frame_index, game)

func verify_extra() -> void:
	super.verify_extra()
	super.check("共同帧主题颜色文案照明一致", power_common > 100 and power_equal and exit_seen)
	print("INDUSTRIAL_ONLINE common_frames=", power_common, " theme_equal=", power_equal, " exit_seen=", exit_seen)
