extends SceneTree
# Boss 试玩入口：打开真实游戏窗口，直接把两人放到第一章 Boss 场地入口前（途中合作门视为已开），
# 之后完全是正常游戏：01 用 WASD + 空格，02 用方向键 + 回车，鼠标左键射击。往前走就会触发入场动画。
# 用法：Godot --path <工程> --script res://build-tools/boss/preview_boss.gd
const Boss = preload("res://scripts/journey_boss.gd")

func _initialize() -> void:
	call_deferred("open")

func open() -> void:
	var game = load("res://scenes/journey.tscn").instantiate()
	game.start_chapter = 0
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	var run = game.run
	run.retry()
	for gate in run.charge_gates:
		gate.open = true
		gate.opened_at = -10.0
	run.select_charge_gate()
	var boss: Dictionary = Boss.boss(run)
	run.a.position = Vector2(-60, boss.arena - 200)
	run.b.position = Vector2(60, boss.arena - 200)
	run.distance = boss.arena - 200
	run.rope.reset(run.a.position, run.b.position)
	run.checkpoint = {}
	run.state = "running"
