extends "res://tests/cooperative_relay_online.gd"
# 比较相同 UDP 帧的提示来源及最终文案，而非比较不同渲染时刻。
var hint_frames := [{}, {}]
var hint_common := 0
var hints_equal := true

func record_frame(endpoint: int, frame_index: int, game) -> void:
	var values := []
	for gate in game.run.charge_gates:
		values.append([gate.id, gate.get("conditions", {}), game.run.gate_hint(gate)])
	hint_frames[endpoint][frame_index] = var_to_str(values)
	if hint_frames[1-endpoint].has(frame_index):
		hint_common += 1
		hints_equal = hints_equal and hint_frames[endpoint][frame_index] == hint_frames[1-endpoint][frame_index]
	super.record_frame(endpoint, frame_index, game)

func verify_extra() -> void:
	super.verify_extra()
	super.check("共同帧提示条件及文案一致", hint_common > 100 and hints_equal)
	print("RECOVERY_ONLINE common_frames=", hint_common, " hints_equal=", hints_equal)
