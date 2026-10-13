extends SceneTree
const Run = preload("res://scripts/road_run.gd")
const Templates = preload("res://scripts/road_templates.gd")
const Keyboard = preload("res://tests/keyboard_route_assertions.gd")
var checks: Array = []
var evidence: Array = []
func _initialize() -> void:
	call_deferred("verify")
func check(name: String, ok: bool) -> void:
	checks.append({"name": name, "passed": ok})
	print("PASS " if ok else "FAIL ", name)
func verify() -> void:
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var run = game.run
	run.generation_enabled = false
	run.retry()
	run.step(0)
	run.distance = 5940
	run.a.position = Vector2(-42, 5940)
	run.b.position = Vector2(42, 5940)
	run.rope.reset(run.a.position, run.b.position)
	var block := Templates.make_block("safe", 0, 0)
	block.hazards = [{"kind": "pillar", "rect": Rect2(-12, 38, 24, 24)}, {"kind": "iron_ball", "rect": Rect2(120, 700, 80, 80)}]
	block.rewards = [{"kind": "coin", "position": Vector2(-42, 75), "radius": 20.0}, {"kind": "prize", "position": Vector2(0, 80), "radius": 44.0, "staggered": false}, {"kind": "shield", "position": Vector2(42, 85), "radius": 20.0}]
	run.install_block(block, 5940, "state")
	var pillar_id: int = run.obstacle_ids[0]
	var shifted_contact := false
	var shifted_rewards := false
	var shifted_dynamic := false
	var had_contact := false
	for tick in range(100):
		var old_origin: float = run.world_origin
		var old_rewards: Array = run.rewards.duplicate(true)
		var old_contacts: Array = run.rope.contacts.duplicate(true)
		var old_start: float = run.hazard_specs[1].start_distance
		run.step(Run.FIXED_STEP)
		had_contact = had_contact or run.rope.has_contact(pillar_id)
		if run.world_origin != old_origin:
			shifted_contact = not old_contacts.is_empty() and run.rope.has_contact(pillar_id) and run.rope.contacts[0].id == old_contacts[0].id and run.rope.contacts[0].side == old_contacts[0].side and run.rope.contacts[0].center == run.obstacles[0].get_center() and run.rope.path[0] == run.a.position
			shifted_rewards = run.rewards.size() == old_rewards.size()
			for i in range(run.rewards.size()):
				shifted_rewards = shifted_rewards and run.rewards[i].id == old_rewards[i].id and run.rewards[i].position == old_rewards[i].position - Vector2(0, 4800)
			shifted_dynamic = run.hazard_specs[1].start_distance == old_start - 4800
			evidence.append(Templates.snapshot(run, tick))
			break
	check("真实接触及奖励共存时自动重定位", had_contact and shifted_contact and shifted_rewards and shifted_dynamic and run.rebases == 1)
	var claimed_before: Dictionary = run.claimed_rewards.duplicate()
	run.pause()
	var frozen := var_to_str([run.distance, run.rope.contacts, run.rewards, run.hazard_specs])
	run.step(0.25, Vector2.LEFT, Vector2.LEFT, true, true)
	check("接触/奖励/动态运动暂停一致", frozen == var_to_str([run.distance, run.rope.contacts, run.rewards, run.hazard_specs]))
	run.pause()
	run.step(0)
	var phase := 0
	var all_inputs_legal := true
	for tick in range(1200):
		# 复用已验证的回撤解围输入：先到柱前，再让 01 绕到 02 同侧。
		var first := Vector2.ZERO
		var second := Vector2.ZERO
		if run.rope_bound and phase == 0: phase = 1
		if phase == 1:
			var offset: Vector2 = Vector2(run.a.position.x, 1152) - run.a.position
			first = Vector2(signf(offset.x) if absf(offset.x) > Templates.KEYBOARD_STEP * 0.5 else 0, signf(offset.y) if absf(offset.y) > Templates.KEYBOARD_STEP * 0.5 else 0)
			if first == Vector2.ZERO: phase = 2
		if phase == 2:
			# 转向期间继续按后退，抵消自动推进，给柱前横移保留真实净空。
			first = Vector2(1, -1) if run.a.position.x < 70 else Vector2.ZERO
			if run.rope.contacts.is_empty(): second = Vector2.RIGHT if run.b.position.x < 90 else Vector2.ZERO
		all_inputs_legal = all_inputs_legal and Keyboard.legal([first.x, first.y, second.x, second.y, false, false])
		run.step(Run.FIXED_STEP, first, second)
		if tick % 30 == 0: evidence.append(Templates.snapshot(run, tick))
		if run.state != "running": break
	check("重定位后真实同侧解围与回收", run.state == "running" and not run.rope.has_contact(pillar_id) and not run.obstacle_ids.has(pillar_id) and run.recycled > 0)
	evidence.append({"final": Templates.snapshot(run, 1200), "reason": run.reason, "phase": phase})
	if run.state != "running": print("STATE DEBUG ", run.reason, " ", run.a.position, " ", run.b.position, " distance=", run.distance, " phase=", phase)
	check("重定位后回撤解围输入全部键盘合法", all_inputs_legal)
	var unique := true
	for id in claimed_before: unique = unique and run.claimed_rewards.has(id)
	check("回收重定位保留奖励领取去重", unique and run.coins <= 1 and run.prizes <= 1)
	run.retry()
	check("重试清空接触/奖励/动态/路段且保留种子", run.rope.contacts.is_empty() and run.rewards.is_empty() and run.hazard_specs.is_empty() and run.route_segments.is_empty() and run.claimed_rewards.is_empty() and run.world_origin == 0)
	var failed := 0
	for entry in checks:
		if not entry.passed: failed += 1
	var file := FileAccess.open("res://tests/short-rope-t05-state.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failed": failed, "checks": checks, "evidence": evidence}))
	file.close()
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
