extends "res://tests/industrial_relay_theme.gd"

# 若分侧事实错用角色编号、忽略腾空或槽重绑不刷新，本专项应失败。
func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.generation_enabled = false
	game.run.charge_tutorial = false
	game.run.retry()
	var block := Templates.make_block("charge_sync_relay", 1, 0)
	game.run.install_block(block, 0, "sides")
	game.run.install_block(block, 840, "preload")
	game.sync_view()
	var first: Dictionary = game.run.charge_gates[0]
	var second: Dictionary = game.run.charge_gates[1]
	Charge.advance(first, PackedVector2Array([Vector2(-65, first.receiver.y), Vector2(0, first.receiver.y)]), PackedFloat32Array([28, 28]), 0.9, true, 0.1)
	check("充能生产分侧事实存在且仅右侧缺失", first.conditions.get("side_present", []) == [true, false] and not first.conditions.ready and first.charge == 0)
	check("统一分侧反馈入口存在", game.run.has_method("gate_side_feedback"))
	if game.run.has_method("gate_side_feedback"):
		var left: Vector2 = second.left.get_center()
		var right: Vector2 = second.right.get_center()
		verify_sides(game, first, ["positioned", "missing"], ["已到位", "未到位"])
		Charge.advance(first, PackedVector2Array([Vector2(0, first.receiver.y), Vector2(65, first.receiver.y)]), PackedFloat32Array([28, 28]), 0.9, true, 0.1)
		verify_sides(game, first, ["missing", "positioned"], ["未到位", "已到位"])
		Charge.advance(first, PackedVector2Array([Vector2(65, first.receiver.y), Vector2(-65, first.receiver.y)]), PackedFloat32Array([28, 28]), 0.9, true, 0.1)
		verify_sides(game, first, ["positioned", "positioned"], ["已到位", "已到位"])
		check("交换充能角色计时且不提前开启", first.conditions.ready and first.charge > 0 and not first.open)
		Charge.advance(first, PackedVector2Array(), PackedFloat32Array(), 0.9, true, 0.1)
		verify_sides(game, first, ["missing", "missing"], ["未到位", "未到位"])
		check("无绳路归零且无遗留站位", first.charge == 0 and first.conditions.side_present == [false, false])
		Plates.advance(second, left, left, true, true, 0.1)
		verify_sides(game, second, ["standing", "missing"], ["已落地", "未占板"])
		check("同板不得计时", not second.conditions.ready and second.charge == 0)
		Plates.advance(second, left, right, false, true, 0.1)
		verify_sides(game, second, ["airborne", "standing"], ["腾空", "已落地"])
		check("腾空位置和落地占用分别登记", second.conditions.side_present == [true, true] and second.conditions.airborne == [true, false] and second.conditions.occupied == [false, true])
		Plates.advance(second, right, left, false, true, 0.1)
		verify_sides(game, second, ["standing", "airborne"], ["已落地", "腾空"])
		Plates.advance(second, right, left, true, true, 0.1)
		verify_sides(game, second, ["holding", "holding"], ["持续站稳", "持续站稳"])
		check("落地计时但关闭门不亮出口", second.charge > 0 and not second.open and power(game.charge_gate_views[1]).get_node("ExitLight").light_energy == 0)
		var frozen: String = var_to_str(game.run.gate_side_feedback(second))
		game.run.pause()
		var state: int = game.run.sync_hash()
		for tick in range(10):
			game.run.step(1.0 / 60.0, Vector2.LEFT, Vector2.RIGHT, true, true)
			game.sync_charge_gate()
		check("暂停分侧与物理冻结", game.run.sync_hash() == state and var_to_str(game.run.gate_side_feedback(second)) == frozen)
		game.run.pause()
		Plates.advance(second, right, left, true, false, 0.1)
		verify_sides(game, second, ["airborne", "standing"], ["腾空", "已落地"])
		check("腾空中断持续站稳计时", second.charge == 0 and not second.open)
		var sound: int = game.sfx.next_player
		game.sync_charge_gate()
		check("分侧状态变化无新音效", game.sfx.next_player == sound)
		# 两个主题实例不能互相借用事实或共享可变材质。
		var untouched = power(game.charge_gate_views[3])
		check("预加载次实例两侧仍未占板", untouched.get_node("LeftStatus").text.contains("未占板") and untouched.get_node("RightStatus").text.contains("未占板"))
		game.run.charge_gates.remove_at(0)
		game.sync_charge_gate()
		check("槽移位重绑实际侧别", power(game.charge_gate_views[0]).get_node("LeftStatus").text.contains("腾空") and power(game.charge_gate_views[0]).get_node("RightStatus").text.contains("已落地"))
		open_gate(second)
		game.sync_charge_gate()
		check("开门侧提示隐藏且出口开启", not power(game.charge_gate_views[0]).get_node("LeftStatus").visible and not power(game.charge_gate_views[0]).get_node("RightStatus").visible and power(game.charge_gate_views[0]).get_node("ExitLight").light_energy > 0)
		game.run.fail_threat("分侧恢复夹具")
		game.run.retry(true)
		game.run.install_block(block, 0, "retry")
		game.sync_charge_gate()
		check("失败重试清除旧侧别与照明", power(game.charge_gate_views[0]).get_node("LeftStatus").text.contains("未到位") and power(game.charge_gate_views[1]).get_node("RightStatus").text.contains("未占板") and power(game.charge_gate_views[0]).get_node("ExitLight").light_energy == 0)
		var repeat: String = power(game.charge_gate_views[1]).get_node("LeftStatus").text
		game.run.retry(true)
		game.run.install_block(block, 0, "repeat")
		game.sync_charge_gate()
		check("同布局分侧反馈可复现", power(game.charge_gate_views[1]).get_node("LeftStatus").text == repeat)
		game.run.retry()
		game.run.install_block(Templates.make_block("sync_cargo", 1, 0), 0, "plain")
		game.sync_charge_gate()
		check("普通门槽重用清空文字", not power(game.charge_gate_views[0]).visible and power(game.charge_gate_views[0]).get_node("LeftStatus").text.is_empty() and power(game.charge_gate_views[0]).get_node("RightStatus").text.is_empty())
	for player in game.sfx.players:
		player.stop()
		player.stream = null
	game.queue_free()
	await process_frame
	print("READABILITY failures=", failures)
	await super.verify()

func verify_sides(game, gate: Dictionary, states: Array, words: Array) -> void:
	var feedback: Array = game.run.gate_side_feedback(gate)
	check("生产侧反馈 " + str(states), feedback.size() == 2 and feedback[0].state == states[0] and feedback[1].state == states[1])
	game.sync_charge_gate()
	var slot: int = game.run.charge_gates.find(gate)
	var view = power(game.charge_gate_views[slot])
	var hud: String = game.run.gate_hint(gate)
	check("左右主题与HUD反映实际条件 " + str(states), view.get_node("LeftStatus").text.contains(words[0]) and view.get_node("RightStatus").text.contains(words[1]) and hud.contains(feedback[0].text) and hud.contains(feedback[1].text))
	check("关闭门不误示已开或亮出口", not view.get_node("Sign").text.contains("已供电") and view.get_node("ExitLight").light_energy == 0 and not view.get_node("ForwardGuide").visible)
	if states[0] != states[1]:
		check("两侧不同状态有独立材质", color(view.get_node("LeftGuide")) != color(view.get_node("RightGuide")))
