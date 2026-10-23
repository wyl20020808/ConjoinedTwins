extends SceneTree

const Journey = preload("res://scripts/journey_run.gd")
var checks := 0
var failures: Array[String] = []

# 对照沿用优化前的全列表窄相检测、扫杆原算法和地形查询。
class OracleRun extends Journey:
	func damage_candidates(_pa: Vector2, _ca: Vector2, _pb: Vector2, _cb: Vector2, _path: PackedVector2Array) -> Array[int]:
		var result: Array[int] = []
		for index in range(obstacles.size()): result.append(index)
		return result
	func timed_hazard_hits(index: int, start: float, end: float, from: Vector2, to: Vector2, h0: float, h1: float) -> bool:
		if kinds[index] == "sweeper":
			return Surfaces.body_hits(obstacles[index].get_center(), hazard_specs[index], start, end, from, to, h0, h1, Motion.RADIUS)
		return super(index, start, end, from, to, h0, h1)
	func prepare_terrain_lookup() -> void:
		pass

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		if failures.size() <= 10: printerr("FAIL ", message)

func _initialize() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 418209
	var precise_hits := 0
	var rejected := 0
	var running_steps := 0
	for chapter in range(3):
		var run = Journey.new(); run.random_seed = false; run.seed_value = 8123; run.level_index = chapter; run.retry()
		run.elapsed = 13.25
		for index in range(run.kinds.size()):
			for sample in range(8):
				var center: Vector2 = run.hazard_sample(index, run.elapsed).rect.get_center()
				var pa := center + Vector2(rng.randf_range(-350,350),rng.randf_range(-350,350))
				var pb := pa + Vector2(56,0)
				var ca := pa + Vector2(rng.randf_range(-100,100),rng.randf_range(-160,160))
				var cb := ca + Vector2(56,0)
				var h0 := rng.randf_range(0,90); var h1 := rng.randf_range(0,90)
				run.a.position = ca; run.b.position = cb
				run.heights = [h1,h1]
				run.rope.physical = run.RopePhysics.create(Vector3(ca.x,h1+28,ca.y),Vector3(cb.x,h1+28,cb.y),run.LINK_LIMIT)
				var old_path := PackedVector2Array([pa,pb])
				var old_z := PackedFloat32Array([h0+28,h0+28])
				var candidates: Array = run.damage_candidates(pa,ca,pb,cb,old_path)
				var ordered := true
				for n in range(1,candidates.size()):
					if candidates[n] <= candidates[n-1]: ordered = false
				check(ordered, "候选索引保持原顺序且不重复")
				var dt: float = run.FIXED_STEP/3 if sample%2 == 0 else 0.1
				var kind: String = run.kinds[index]
				if kind == "sweeper":
					var expected: bool = run.Surfaces.body_hits(run.obstacles[index].get_center(),run.hazard_specs[index],run.elapsed,run.elapsed+dt,pa,ca,h0,h1,run.Motion.RADIUS)
					check(run.timed_hazard_hits(index,run.elapsed,run.elapsed+dt,pa,ca,h0,h1) == expected, "扫杆完整旋转盘裁剪与原分片结果一致")
				if candidates.has(index): continue
				rejected += 1
				if kind in run.Industrial.KINDS:
					var hit: Dictionary = run.industrial_hits(index,run.elapsed,run.elapsed+dt,pa,ca,pb,cb,[h0,h0],old_path,old_z)
					if not hit.is_empty(): precise_hits += 1
					check(hit.is_empty(), "被排除的工业机关不能命中")
				elif kind not in ["cargo","road_gap"] and kind not in run.Terrain.KINDS:
					var hit: bool = run.timed_hazard_hits(index,run.elapsed,run.elapsed+dt,pa,ca,h0,h1) or run.timed_hazard_hits(index,run.elapsed,run.elapsed+dt,pb,cb,h0,h1)
					if hit: precise_hits += 1
					check(not hit, "被排除的普通机关不能命中")
		# 同一布局，在台阶、渡船、升降平台及边界附近逐值比较分桶与完整地形查询。
		for index in run.indexed_terrain():
			var rect: Rect2 = run.obstacles[index]
			for point in [rect.position,rect.end,rect.get_center(),rect.get_center()+Vector2(30,0),rect.position-Vector2.ONE]:
				for radius in [0.0,12.0]:
					run.terrain_step_active = false
					var expected: Dictionary = run.surface_at(point,run.elapsed,radius)
					run.prepare_terrain_lookup()
					check(run.surface_at(point,run.elapsed,radius) == expected, "地形分桶保留完整解析表面结果")
					run.terrain_step_active = false
		run.dispose()
	# 两个种子、三章，包含移动、跳跃、开火、暂停与存档恢复的逐步状态对照。
	for seed_value in [8123,3917]:
		for chapter in range(3):
			var run = Journey.new(); var oracle = OracleRun.new()
			for model in [run,oracle]:
				model.random_seed = false; model.seed_value = seed_value; model.level_index = chapter; model.retry()
				model.state = "running"; model.clear_input = false; model.elapsed = 10.0
				model.a.position = Vector2(80,9600); model.b.position = Vector2(136,9600); model.distance = 9600
				for gate in model.charge_gates:
					gate.open = gate.receiver.y < model.distance-180; gate.opened_at = 0 if gate.open else -1
				model.select_charge_gate(); model.rope.reset(model.a.position,model.b.position)
				model.combat.weapons = [model.Combat.gun(),model.Combat.gun()]
				model.capture_checkpoint()
			for frame in range(180):
				var direction: Vector2 = [Vector2.UP,Vector2.RIGHT,Vector2.ZERO,Vector2.DOWN,Vector2.LEFT,Vector2.UP][frame/30]
				if run.state == "running": running_steps += 1
				for model in [run,oracle]:
					if model.state in ["failed","rescue"]: model.restore_checkpoint()
					if frame in [35,40]: model.pause()
					if frame == 110: model.restore_checkpoint()
					model.set_combat_input(frame<100,frame==101,frame==150)
					model.step(model.FIXED_STEP,direction,direction,frame%47==0,frame%43==0)
				check(run.sync_hash() == oracle.sync_hash(), "全列表与裁剪版本逐步同步指纹一致")
				check(not run.terrain_step_active, "所有父模拟返回路径释放地形索引")
			run.dispose(); oracle.dispose()
	check(running_steps > 500, "逐步对照必须实际推进足量运行态物理")
	print("PORTABLE COLLISION checks=",checks," failures=",failures.size()," rejected=",rejected," missed=",precise_hits," running_steps=",running_steps)
	quit(0 if failures.is_empty() else 1)
