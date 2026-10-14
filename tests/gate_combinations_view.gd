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
	game.run.install_block(Templates.make_block("charge_cargo", 1, 0), 0, "first")
	game.run.install_block(Templates.make_block("charge_cargo", -1, 0), 840, "second")
	game.sync_view()
	var exists := false
	for property in game.get_property_list():
		if property.name == "charge_gate_views": exists = true
	check("两门同时保留独立展示", exists)
	if exists:
		check("预加载门位置映射", game.charge_gate_views.size() == 2 and is_equal_approx(game.charge_gate_views[1].position.z-game.charge_gate_views[0].position.z, -42.0))
		game.run.charge_gates[0].open = true
		game.run.select_charge_gate()
		game.sync_view()
		check("前门开启后门框仍在且独立反馈", game.charge_gate_views[0].visible and not game.charge_gate_views[0].get_node("Door").visible and game.charge_gate_views[1].get_node("Door").visible and game.gate_announced.get("first:gate", false))
		game.run.charge_gates.remove_at(0)
		game.sync_view()
		check("回收复用节点且清除旧身份", not game.charge_gate_views[1].visible and not game.gate_announced.has("first:gate"))
	game.queue_free()
	await process_frame
	print("GATE_VIEW failures=", failures)
	quit(1 if failures else 0)
