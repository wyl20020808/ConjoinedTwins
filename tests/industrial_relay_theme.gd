extends "res://tests/cooperative_relay_view.gd"

const Charge = preload("res://scripts/road_charge_gate.gd")
const Plates = preload("res://scripts/road_sync_plates.gd")

func power(view):
	return view.get_node_or_null("RelayPower")

func open_gate(gate: Dictionary) -> void:
	if gate.get("kind", "charge") == "sync_plates":
		Plates.advance(gate, gate.left.get_center(), gate.right.get_center(), true, true, 0.4)
	else:
		Charge.advance(gate, PackedVector2Array([Vector2(-65, gate.receiver.y), Vector2(65, gate.receiver.y)]), PackedFloat32Array([28, 28]), 0.9, true, 0.8)

func color(node: MeshInstance3D) -> Color:
	return node.material_override.albedo_color

func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run.generation_enabled = false
	game.run.charge_tutorial = false
	game.run.retry()
	var block := Templates.make_block("charge_sync_relay", 1, 0)
	game.run.install_block(block, 0, "first")
	game.run.install_block(block, 840, "second")
	var physics: int = game.run.sync_hash()
	var camera: Transform3D = game.camera.transform
	game.sync_view()
	check("四门主题绑定", game.charge_gate_views.size() == 4 and game.charge_gate_views.all(func(v): return power(v) != null))
	if power(game.charge_gate_views[0]) == null:
		await cleanup(game)
		return
	var first = power(game.charge_gate_views[0])
	var second = power(game.charge_gate_views[1])
	check("首门标明接线供能", first.get_node("Sign").text.contains("01 接线供能"))
	check("次门标明双板接力", second.get_node("Sign").text.contains("02 双板接力"))
	check("预加载未供电出口不亮", second.get_node("ExitLight").light_energy == 0 and second.get_node("Sign").text.contains("等待"))
	check("地面双侧导向先显示站位", first.get_node("LeftGuide").visible and first.get_node("RightGuide").visible and not first.get_node("ForwardGuide").visible)
	check("主题不改变生产状态及镜头", game.run.sync_hash() == physics and game.camera.transform == camera)
	var initial: Color = color(second.get_node("PowerLamp"))
	game.run.charge_gates[0].charge = 0.2
	game.sync_view()
	check("部分供能有独立反馈", first.get_node("Sign").text.contains("供能中") and color(first.get_node("PowerLamp")) != initial and color(second.get_node("PowerLamp")) == initial)
	var charging_color: Color = color(first.get_node("PowerLamp"))
	var charging_sound: int = game.sfx.next_player
	game.run.pause()
	physics = game.run.sync_hash()
	for tick in range(20):
		game.run.step(1.0 / 60.0, Vector2.LEFT, Vector2.RIGHT, true, true)
		game.sync_charge_gate()
	check("部分供能暂停保持计时与颜色", game.run.sync_hash() == physics and first.get_node("Sign").text.contains("供能中") and color(first.get_node("PowerLamp")) == charging_color and color(second.get_node("PowerLamp")) == initial)
	game.run.pause()
	Charge.advance(game.run.charge_gates[0], PackedVector2Array([Vector2(-65, 120), Vector2(65, 120)]), PackedFloat32Array([28, 28]), 0.1, true, 0.01)
	game.sync_charge_gate()
	check("恢复后条件失效清零回待供电", game.run.charge_gates[0].charge == 0 and first.get_node("Sign").text.contains("等待") and color(first.get_node("PowerLamp")) == initial)
	check("部分计时暂停恢复无开门音效", game.sfx.next_player == charging_sound)
	open_gate(game.run.charge_gates[0])
	var sound_before: int = game.sfx.next_player
	game.sync_charge_gate()
	check("首门单次开门音效", game.sfx.next_player == (sound_before + 1) % game.sfx.players.size())
	check("首门开启引向次门", first.get_node("Sign").text.contains("前往 02") and first.get_node("ForwardGuide").visible and not first.get_node("LeftGuide").visible)
	check("首门不点亮次门及其他实例", color(second.get_node("PowerLamp")) == initial and second.get_node("ExitLight").light_energy == 0 and color(power(game.charge_gate_views[2]).get_node("PowerLamp")) == initial)
	game.run.charge_gates[1].charge = 0.1
	game.sync_charge_gate()
	check("踏板计时不提前亮出口", second.get_node("Sign").text.contains("供能中") and second.get_node("ExitLight").light_energy == 0)
	open_gate(game.run.charge_gates[1])
	game.sync_charge_gate()
	check("次门开启才亮出口", second.get_node("ExitLight").light_energy > 0 and second.get_node("ExitRail").visible and second.get_node("Sign").text.contains("出口"))
	check("开门后两门各一次音效", game.sfx.next_player == (sound_before + 2) % game.sfx.players.size())
	var quiet: int = game.sfx.next_player
	for tick in range(20): game.sync_charge_gate()
	check("重复显示不重复音效", game.sfx.next_player == quiet)
	game.run.pause()
	physics = game.run.sync_hash()
	var sign: String = second.get_node("Sign").text
	for tick in range(20):
		game.run.step(1.0 / 60.0, Vector2.LEFT, Vector2.RIGHT, true, true)
		game.sync_charge_gate()
	check("暂停保持供电照明及物理", game.run.sync_hash() == physics and second.get_node("Sign").text == sign and game.sfx.next_player == quiet)
	game.run.charge_gates.remove_at(0)
	game.sync_charge_gate()
	check("回收槽移位重绑次门", first.get_node("Sign").text.contains("02 双板接力") and first.get_node("ExitLight").light_energy > 0 and not power(game.charge_gate_views[3]).is_visible_in_tree())
	check("已开实例移槽不再响", game.sfx.next_player == quiet)
	game.run.retry()
	game.sync_charge_gate()
	check("重试所有主题隐藏", game.charge_gate_views.all(func(v): return not v.visible) and game.gate_announced.is_empty())
	game.run.install_block(block, 0, "new")
	game.sync_charge_gate()
	check("槽重用清除旧亮灯和指向", first.get_node("Sign").text.contains("01 接线供能") and first.get_node("ExitLight").light_energy == 0 and color(first.get_node("PowerLamp")) == initial and not first.get_node("ForwardGuide").visible)
	check("相同模板主题可复现", color(power(game.charge_gate_views[1]).get_node("PowerLamp")) == initial and power(game.charge_gate_views[1]).get_node("Sign").text.contains("02 双板接力"))
	game.run.retry()
	game.run.install_block(Templates.make_block("sync_cargo", 1, 0), 0, "ordinary")
	game.sync_charge_gate()
	check("普通门复用槽不残留主题", not first.visible and first.get_node("ExitLight").light_energy == 0 and first.get_node("Sign").text.is_empty())
	check("全程固定相机", game.camera.transform == camera)
	await cleanup(game)

func cleanup(game) -> void:
	for player in game.sfx.players:
		player.stop()
		player.stream = null
	game.queue_free()
	await process_frame
	print("INDUSTRIAL_THEME failures=", failures)
	quit(1 if failures else 0)
