extends "res://tests/online_lockstep.gd"
# 复用真实 UDP、共同帧、暂停重试及断线断言；仅选择专项生产模板。
var relay_charge_progress := false
var relay_charge_open := false
var independent := true
var mid_pause_requested := false
var mid_resume_requested := false
var mid_pause_frames := 0
var mid_frozen := ""
var mid_freeze_equal := true

func combination_kind() -> String:
	return "charge_sync_relay"

func record_frame(endpoint: int, frame_index: int, game) -> void:
	for gate in game.run.charge_gates:
		if gate.get("relay_index", -1) == 0:
			relay_charge_progress = relay_charge_progress or (gate.charge > 0 and not gate.open)
			relay_charge_open = relay_charge_open or gate.open
		if gate.get("relay_index", -1) == 1 and not relay_charge_open:
			independent = independent and gate.charge == 0 and not gate.open
		if gate.get("relay_index", -1) == 1 and gate.charge > 0.1 and not gate.open and not mid_pause_requested:
			mid_pause_requested = true
			network_games[0].command("pause")
	if endpoint == 0 and mid_pause_requested and not mid_resume_requested and game.run.state == "paused":
		var state := var_to_str([game.run.distance, game.run.a.position, game.run.b.position, game.run.heights, game.run.charge_gates, game.run.elapsed])
		if mid_frozen.is_empty(): mid_frozen = state
		mid_freeze_equal = mid_freeze_equal and state == mid_frozen
		mid_pause_frames += 1
		if mid_pause_frames >= 30:
			mid_resume_requested = true
			network_games[0].command("pause")
	super.record_frame(endpoint, frame_index, game)

func check(label: String, passed: bool) -> void:
	if label == "联机组合绕箱领奖安全退出":
		super.check("接力首门计时锁存且次门独立", relay_charge_progress and relay_charge_open and independent)
		super.check("次门计时中联机暂停恢复", mid_pause_requested and mid_resume_requested and mid_pause_frames >= 30 and mid_freeze_equal)
	label = label.replace("随机踏板组合", "随机接力踏板门").replace("联机组合绕箱领奖安全退出", "联机接力领奖安全退出")
	super.check(label, passed)
