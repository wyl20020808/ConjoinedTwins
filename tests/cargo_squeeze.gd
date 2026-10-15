extends SceneTree

# 巨岩新规则：碰到巨岩不致死，只会被挡住；被巨岩卡住并被推出画面后方才失败。
const Run = preload("res://scripts/road_run.gd")
var checks: Array = []

func _initialize() -> void:
	call_deferred("verify")

func check(label: String, passed: bool) -> void:
	checks.append({"name": label, "passed": passed})
	print("PASS " if passed else "FAIL ", label)

func fixture(rect: Rect2):
	var r = Run.new(false)
	r.retry()
	r.step(1.0 / 60)
	r.obstacles.assign([rect])
	r.kinds.assign(["cargo"])
	r.obstacle_heights.assign([Run.HAZARD_TOPS.cargo])
	# 回收逻辑按下标同步删除并行数组，夹具需保持长度一致。
	r.obstacle_ids.assign([900001])
	r.hazard_specs.assign([{}])
	return r

func ticks(r, count: int, first := Vector2.ZERO, second := Vector2.ZERO) -> void:
	for i in range(count):
		if r.state != "running": return
		r.step(1.0 / 60, first, second)

func verify() -> void:
	# 01 在 x=-42 处，巨岩横挡在其前方；02 在 x=42 处不受阻挡。
	var r = fixture(Rect2(-80, 40, 60, 60))
	ticks(r, 12)
	check("碰到巨岩不立即失败", r.state == "running")
	check("巨岩挡住 01 而不穿越", r.a.position.y < 40 - Run.Motion.RADIUS + 0.5)
	check("道路推进不被巨岩冻结", r.distance > 40)
	check("02 不受影响继续前进", r.b.position.y > r.a.position.y)
	ticks(r, 14)
	var lag: float = r.rear_bound() - r.a.position.y
	print("lag=%.1f distance=%.1f a=%s state=%s" % [lag, r.distance, r.a.position, r.state])
	check("01 被巨岩压在后方界线之后但仍存活", lag > 0 and r.state == "running")
	# 持续卡住：道路推进把 01 推出画面后失败。
	var safety := 0
	while r.state == "running" and safety < 1200:
		r.step(1.0 / 60)
		safety += 1
	check("持续被巨岩卡住挤出画面后失败", r.state == "failed")
	check("失败原因为巨岩挤出", str(r.reason).contains("巨岩"))
	r.dispose()

	# 卡住一段时间后横移脱困，能回到正常范围。
	r = fixture(Rect2(-80, 40, 60, 60))
	ticks(r, 26)
	var before: float = r.rear_bound() - r.a.position.y
	ticks(r, 8, Vector2.RIGHT, Vector2.ZERO)
	ticks(r, 90, Vector2(0, 1), Vector2.ZERO)
	ticks(r, 90)
	var after: float = r.rear_bound() - r.a.position.y
	print("before=%.1f after=%.1f a=%s state=%s reason=%s" % [before, after, r.a.position, r.state, r.reason])
	check("横移脱困后仍在运行", r.state == "running")
	check("脱困后不再落后于后方界线", before > 0 and after <= 0.5)
	r.dispose()

	var failed := checks.filter(func(c): return not c.passed).size()
	print("CARGO_SQUEEZE failures=%d" % failed)
	quit(1 if failed else 0)
