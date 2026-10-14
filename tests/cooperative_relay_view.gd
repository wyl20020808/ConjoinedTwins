extends SceneTree
const Templates = preload("res://scripts/road_templates.gd")
var failures := 0

func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.generation_enabled = false
	game.run.charge_tutorial = false
	game.run.retry()
	game.run.install_block(Templates.make_block("charge_sync_relay", 1, 0), 0, "first")
	game.sync_view()
	check("两门保持独立位置", game.charge_gate_views.size() == 2 and is_equal_approx(game.charge_gate_views[1].position.z - game.charge_gate_views[0].position.z, -18.0))
	check("顺序及机关类型反馈", game.charge_gate_views[0].get_node("Status").text.contains("接力 1/2 · 充能") and game.charge_gate_views[1].get_node("Status").text.contains("接力 2/2 · 踏板"))
	game.run.charge_gates[0].open = true
	game.run.select_charge_gate()
	game.sync_view()
	check("首门锁存不误开次门", not game.charge_gate_views[0].get_node("Door").visible and game.charge_gate_views[1].get_node("Door").visible and game.gate_announced.get("first:gate:0", false))
	game.run.charge_gates.remove_at(0)
	game.sync_view()
	check("回收清理身份", not game.charge_gate_views[1].visible and not game.gate_announced.has("first:gate:0"))
	for player in game.sfx.players:
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	print("RELAY_VIEW failures=", failures)
	quit(1 if failures else 0)
