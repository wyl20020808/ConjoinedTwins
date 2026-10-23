extends SceneTree

# 救援动画接入检查：Blender 生成的收绳/攀爬动作已加入角色，救援时播放且两人面对面、绳端在手上。
const Run = preload("res://scripts/road_run.gd")
var checks: Array = []

func _initialize() -> void:
	call_deferred("verify")

func check(label: String, passed: bool) -> void:
	checks.append({"name": label, "passed": passed})
	print("PASS " if passed else "FAIL ", label)

func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var players: Array = game.animation_players
	check("两名角色都有动画播放器", players.size() >= 2)
	for i in range(mini(2, players.size())):
		var list: PackedStringArray = players[i].get_animation_list()
		check("%02d 含 RopePull 与 Climb" % (i + 1), list.has("RopePull") and list.has("Climb"))
	var r = game.run
	r.retry()
	r.state = "rescue"
	r.rescue = {"role": 1, "point": Vector2(200, 60), "hang": Vector2(330, 60), "progress": 0.3, "time": 0.5, "rate": 0.0, "gain": 0.0, "presses": [0, 0]}
	r.a.position = Vector2(120, 40)
	r.b.position = Vector2(330, 60)
	for n in range(6):
		game.sync_view()
		await process_frame
	check("救援者播放 RopePull", String(players[0].current_animation) == "RopePull")
	check("坠落者播放 Climb", String(players[1].current_animation) == "Climb")
	var holder: Node3D = game.robots[0]
	var hanging: Node3D = game.robots[1]
	var to_hanging: Vector3 = hanging.position - holder.position
	to_hanging.y = 0
	var holder_forward: Vector3 = -holder.global_transform.basis.z
	holder_forward.y = 0
	check("救援者面朝坠落者", holder_forward.normalized().dot(to_hanging.normalized()) > 0.9)
	var hand: Vector3 = game.hand_point(0)
	check("绳端位于救援者手部高度", hand.y > holder.position.y + 0.5 and hand.y < holder.position.y + 2.5 and hand.distance_to(holder.position) < 2.5)
	game.queue_free()
	await process_frame
	var failed := checks.filter(func(c): return not c.passed).size()
	print("RESCUE_ANIMATION failures=%d" % failed)
	quit(1 if failed else 0)
