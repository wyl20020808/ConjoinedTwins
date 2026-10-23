extends SceneTree

const Journey=preload("res://scripts/journey_run.gd")
const Physics=preload("res://scripts/rope_physics.gd")
var checks:=0
var failures: Array[String]=[]

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=381733
	# 与保留的逐字典投影函数对照，覆盖混合顺序、边界、零方向和缺口。
	for variant in range(4):
		var floor_query:Callable=func(point: Vector2) -> float:return -INF if point.x>10 else point.y*.07
		var colliders: Array=[{"center":Vector2.ZERO,"radius":16.137,"bottom":-12.3,"top":89.7},{"low":Vector3(-20,-40,-30),"high":Vector3(26,11,48)},{"center":Vector2(20,17),"radius":9.773,"bottom":-40.0,"top":60.0}]
		if variant%2:colliders.reverse()
		if variant==3:colliders.clear()
		var prepared=Physics.ContactQuery.new(floor_query,colliders)
		for sample in range(2000):
			var point:=Vector3(rng.randf_range(-45,45),rng.randf_range(-45,110),rng.randf_range(-60,60))
			if sample<4:point=[Vector3.ZERO,Vector3(20,11,17),Vector3(26,11,48),Vector3(-20,-40,-30)][sample]
			var from:=point+Vector3(0,3,0)
			check(prepared.project(point,from)==Physics.project(point,from,floor_query,colliders),"预处理碰撞与原投影逐值一致")
	var run=Journey.new();run.random_seed=false;run.seed_value=8123;run.retry()
	for chapter in range(3):
		run.level_index=chapter;run.retry();run.elapsed=14.25
		for types in [["pillar","cargo"],run.ROPE_BLOCKERS,run.Terrain.KINDS]:
			var expected: Array=[]
			for i in range(run.kinds.size()):
				if run.kinds[i] in types:expected.append(i)
			check(run.indices_for_types(types)==expected,"类型索引保留源列表顺序")
		for sample in range(250):
			var from:=Vector2(rng.randf_range(-330,330),rng.randf_range(0,run.finish_distance()))
			var to:=from+Vector2(rng.randf_range(-150,150),rng.randf_range(-200,400))
			var expected:=true
			for i in range(run.kinds.size()):
				if run.kinds[i] in ["cargo","pillar","rail"] and run.Combat.box_blocks(from,to,36,38,run.obstacles[i],run.obstacle_heights[i]):expected=false
			for gate in run.charge_gates:
				if not gate.open and run.Combat.box_blocks(from,to,36,38,gate.door,INF):expected=false
			check(run.Combat.line_of_sight(run,from,to,36,38)==expected,"动物与射击视线裁剪不漏遮挡")
	var index: int=run.kinds.find("cargo")
	run.indices_for_types(["cargo"])
	run.kinds[index]="pillar"
	check(not run.indices_for_types(["cargo"]).has(index) and run.indices_for_types(["pillar"]).has(index),"同长度类型替换立即使索引失效")
	run.dispose()
	print("DENSE REGRESSION checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
