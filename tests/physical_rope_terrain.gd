extends SceneTree

const Run = preload("res://scripts/road_run.gd")
const Physics = preload("res://scripts/rope_physics.gd")
var failures := 0

func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var run = Run.new(false)
	run.retry()
	for tick in range(120): run.step(Run.FIXED_STEP)
	check("生产固定步建立三维绳索",run.rope.physical.get("points",[]).size()==Physics.COUNT+1)
	var first: Vector3=run.rope.physical.points[0]
	var last: Vector3=run.rope.physical.points[-1]
	check("两端绑定真实角色挂点",first.distance_to(Vector3(run.a.position.x,Run.ROPE_HEIGHT,run.a.position.y))<0.01 and last.distance_to(Vector3(run.b.position.x,Run.ROPE_HEIGHT,run.b.position.y))<0.01)
	check("麻绳真实下垂",run.rope.physical.points[Physics.COUNT/2].y<Run.ROPE_HEIGHT-4.0)
	print("ROPE_METRICS stretch=",run.rope.physical.stretch," length=",run.rope.physical.actual_length)
	check("松绳总长误差小于百分之一",run.rope.physical.stretch<0.01)
	var floor_ok := true
	for point: Vector3 in run.rope.physical.points: floor_ok = floor_ok and point.y>=Physics.RADIUS-0.1
	check("地面接触没有穿入路面",floor_ok)
	var captured: Dictionary=Run.Templates.capture_state(run)
	var clone=Run.Templates.clone_state(captured)
	for tick in range(12):
		run.step(Run.FIXED_STEP,Vector2.RIGHT)
		clone.step(Run.FIXED_STEP,Vector2.RIGHT)
	check("状态克隆后物理链确定性复放",run.sync_hash()==clone.sync_hash())
	clone.dispose()
	run.pause()
	var before: PackedVector3Array=run.rope.physical.points.duplicate()
	run.step(0.1)
	check("暂停冻结质点",before==run.rope.physical.points)
	run.retry()
	check("重试清理物理与死亡状态",run.rope.physical.is_empty() and run.death_positions.is_empty())
	# 精确拉满：质点应位于端点直线上。
	var a := Vector3(-Run.LINK_LIMIT/2,60,0)
	var b := Vector3(Run.LINK_LIMIT/2,60,0)
	var chain := Physics.create(a,b,Run.LINK_LIMIT)
	Physics.advance(chain,a,b,Run.FIXED_STEP,func(_p): return -INF,[],PackedVector3Array([a,b]))
	var straight := true
	for p: Vector3 in chain.points: straight=straight and absf(p.y-60)<0.001 and absf(p.z)<0.001
	check("完全拉紧绳索收敛为直线",straight)
	# 自由端保留速度并坠落，缺口处没有全局地板。
	Physics.release(chain,0)
	for tick in range(120): Physics.advance(chain,a,b,Run.FIXED_STEP,func(_p): return -INF,[],PackedVector3Array([a,b]))
	check("脱扣端自然下落",chain.points[0].y<20 and chain.points[-1].distance_to(b)<0.001)
	run.install_block({"hazards":[{"kind":"road_gap","rect":Rect2(-360,-100,720,3000)}],"rewards":[]},0,"death_gap")
	run.fallen=[true,true]
	run.fail_threat("坠落测试")
	for tick in range(120): run.step(Run.FIXED_STEP)
	check("失败状态继续推进绳索与身体",run.death_time>0.99 and run.rope.physical.points[0].y<0)
	check("坠落绳端随身体移动",run.rope.physical.points[0].distance_to(run.death_positions[0]+Vector3(0,Run.ROPE_HEIGHT,0))<0.01)
	run.retry()
	run.fail_threat("撞击脱扣")
	for tick in range(120): run.step(Run.FIXED_STEP)
	check("撞击死亡后腰扣释放自由绳端",not run.rope.physical.bound[0] and not run.rope.physical.bound[1])
	check("脱落麻绳自然落向地面",run.rope.physical.points[0].y<Run.ROPE_HEIGHT-10)
	run.dispose()
	var traction=Run.new(false)
	traction.retry()
	traction.a.position=Vector2(-72,0)
	traction.b.position=Vector2(72,0)
	traction.rope.reset(traction.a.position,traction.b.position)
	traction.reset_input()
	for tick in range(60): traction.step(Run.FIXED_STEP,Vector2.LEFT)
	check("张紧绳索会牵引未横移的队友",traction.b.position.x<70)
	check("牵引仍保持三维绳长约束",traction.rope.required<=Run.LINK_LIMIT+0.01)
	traction.dispose()
	# 新地形查询同时决定脚底、绳索地面和平台。
	for route in ["slope_path","steps_path","tilt_path","ferry_crossing","lift_crossing"]:
		var terrain_run=Run.new(false)
		terrain_run.retry()
		terrain_run.install_block(Run.Templates.make_block(route,1,0),0,route)
		var point := Vector2(0,370)
		var surface: Dictionary=terrain_run.surface_at(point,0)
		check("地形真实支撑 "+route,surface.supported)
		if route in ["slope_path","steps_path","tilt_path","lift_crossing"]: check("路面真实高度 "+route,surface.height>0)
		terrain_run.dispose()
	var rescue_run=Run.new(false)
	rescue_run.retry()
	rescue_run.a.position=Vector2(Run.EDGE+2,100)
	rescue_run.b.position=Vector2(Run.EDGE-80,100)
	rescue_run.last_support=[Vector2(Run.EDGE-14,100),rescue_run.b.position]
	rescue_run.ground_support=[false,true]
	rescue_run.begin_fall(0,rescue_run.a.position)
	for tick in range(90): rescue_run.step(Run.FIXED_STEP)
	check("救援吊挂由重力推进身体",rescue_run.state=="rescue" and rescue_run.rescue_body_position(0).y<0)
	var hanging:Vector3=rescue_run.rescue_body_position(0)+Vector3(0,Run.ROPE_HEIGHT,0)
	check("吊挂身体与麻绳端点同源",rescue_run.rope.physical.points[0].distance_to(hanging)<0.01)
	rescue_run.dispose()
	print("PHYSICAL_ROPE_TERRAIN failures=",failures)
	quit(1 if failures else 0)
