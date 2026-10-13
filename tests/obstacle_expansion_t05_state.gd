extends SceneTree
const Templates = preload("res://scripts/road_templates.gd")
const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
func _initialize() -> void:
	call_deferred("verify")
func check(name: String, valid: bool) -> void:
	checks.append({"name": name, "passed": valid})
	print("PASS " if valid else "FAIL ", name)
func verify() -> void:
	var generator = Templates.new()
	check("具备完整状态克隆与入口绑定接口", generator.has_method("capture_state") and generator.has_method("certificate_key"))
	if generator.has_method("capture_state"):
		var run = Run.new(false)
		run.step(0)
		run.a.position = Vector2(-70, 42)
		run.b.position = Vector2(40, -42)
		run.rope.reset(run.a.position, run.b.position)
		run.heights = [12.0, 0.0]
		run.vertical_speed = [150.0, 0.0]
		run.jump_buffer = [3, 0]
		run.jump_held = [true, false]
		run.ground_support = [false, true]
		run.rope.contacts = [{"id": 17, "center": Vector2(0, 10), "radius": 12.0, "side": 1}]
		run.rope_bound = true
		run.rope_block_substeps = 39
		run.elapsed = 1.25
		run.install_block(Templates.make_block("steam", 1, 0), 1200, "prior")
		run.hazard_specs[0].trigger = 0.25
		var state: Dictionary = generator.capture_state(run)
		var clone = generator.clone_state(state)
		check("完整克隆不中心重置且保留空中状态与相位", clone.a.position == run.a.position and clone.b.position == run.b.position and clone.heights == run.heights and clone.vertical_speed == run.vertical_speed and clone.jump_buffer == run.jump_buffer and clone.hazard_specs == run.hazard_specs)
		check("克隆保留绳接触支撑与受阻累积", clone.rope.contacts == run.rope.contacts and clone.ground_support == run.ground_support and clone.rope_bound and clone.rope_block_substeps == 39)
		clone.hazard_specs[0].trigger = 9.0
		check("危险规格深拷贝不污染源入口", run.hazard_specs[0].trigger == 0.25)
		var block: Dictionary = Templates.make_block("safe", 0, 0)
		var first: String = generator.certificate_key(block, "普通", 0, state, 0)
		run.jump_buffer[0] = 4
		check("缓存绑定输入缓冲状态", first != generator.certificate_key(block, "普通", 0, generator.capture_state(run), 0))
		check("缓存绑定布局与速度源码", not generator.source_binding().is_empty() and first != generator.certificate_key(Templates.make_block("left", -1, 0), "普通", 0, state, 0))
		clone.dispose()
		run.dispose()
		var fresh = Run.new(false)
		fresh.retry()
		fresh.step(0)
		var initial: Dictionary = generator.capture_state(fresh)
		check("真实双人出生入口复放安全段", generator.call("validate_block", block, "普通", 0, initial, 600))
		check("验证不修改生产入口", generator.capture_state(fresh) == initial)
		var impossible: Dictionary = Templates.make_block("safe", 0, 0)
		impossible.hazards.append({"kind": "cargo", "rect": Rect2(-246, 180, 492, 65)})
		check("同入口拒绝无解段", not generator.call("validate_block", impossible, "普通", 0, initial, 600))
		var rejected_hash: String = generator.last_evidence.source_entry_hash
		check("安全回退复用原入口", generator.call("validate_block", block, "普通", 0, initial, 600) and generator.last_evidence.source_entry_hash == rejected_hash)
		fresh.dispose()
		var production = Run.new()
		production.retry()
		production.step(0)
		check("生产预加载首轮教学不被安全回退吞掉", production.state == "running" and production.generator.rejected == 0)
		var continuous := true
		var boundaries: Array = []
		for tick in range(3000):
			var input: Array = Templates.existing_route_input(production)
			production.step(Run.FIXED_STEP, input[0], input[1], input[2], input[3])
			continuous = continuous and production.rope.required <= Run.LINK_LIMIT + 0.01 and production.shield_uses == 0
			if production.total_distance() >= 600 + boundaries.size() * Templates.SEGMENT:
				boundaries.append(Templates.snapshot(production, tick))
			if production.state != "running" or boundaries.size() == 4: break
		check("生产连续三段无入口重置且支撑连接合法", continuous and boundaries.size() == 4 and production.state == "running")
		var record := FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t05/state-continuous-boundaries.json", FileAccess.WRITE)
		record.store_string(JSON.stringify({"boundaries": boundaries, "rejections": production.generator.rejection_evidence}, "\t"))
		record.close()
		production.dispose()
	var failed := 0
	for item in checks:
		if not item.passed: failed += 1
	var file := FileAccess.open("res://build-tools/obstacle-expansion-6377e8b8/t05/state-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failed": failed, "passed": failed == 0, "executor_self_test": true}, "\t"))
	file.close()
	quit(1 if failed else 0)
