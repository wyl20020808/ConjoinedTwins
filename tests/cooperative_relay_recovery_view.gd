extends "res://tests/cooperative_relay_view.gd"

func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.generation_enabled = false
	game.run.charge_tutorial = false
	game.run.retry()
	game.run.install_block(Templates.make_block("charge_sync_relay", 1, 0), 0, "view")
	game.sync_view()
	game.update_ui()
	check("HUD显示当前首门要求", game.hud.text.contains("接力 1/2") and game.hud.text.contains("张紧"))
	check("预加载踏板不显示充能要求", not game.charge_gate_views[1].get_node("Status").text.contains("张紧"))
	var first: Dictionary = game.run.charge_gates[0]
	RunCharge(first)
	game.run.select_charge_gate()
	game.sync_view()
	game.update_ui()
	check("已开门锁存反馈且HUD切换次门", game.charge_gate_views[0].get_node("Status").text.contains("已开启") and game.hud.text.contains("接力 2/2") and not game.hud.text.contains("张紧"))
	game.run.retry()
	game.sync_view()
	game.update_ui()
	check("重试清空HUD与展示旧提示", not game.hud.text.contains("接力") and game.charge_gate_views.all(func(v): return not v.visible))
	game.run.install_block(Templates.make_block("charge_sync_relay", 1, 0), 0, "new")
	game.sync_view()
	game.update_ui()
	check("槽重用提示恢复未开状态", game.hud.text.contains("接力 1/2") and not game.hud.text.contains("已开启") and not game.gate_announced.has("view:gate:0"))
	for player in game.sfx.players:
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	print("RECOVERY_VIEW failures=", failures)
	quit(1 if failures else 0)

# 独立节点绑定夹具：通过真实充能计算开门，不用它证明生产路线。
func RunCharge(gate: Dictionary) -> void:
	var charge = preload("res://scripts/road_charge_gate.gd")
	charge.advance(gate, PackedVector2Array([Vector2(-65, gate.receiver.y), Vector2(65, gate.receiver.y)]), PackedFloat32Array([28, 28]), 0.9, true, 0.8)
