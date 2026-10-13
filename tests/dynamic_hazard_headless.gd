extends SceneTree
const Run = preload("res://scripts/road_run.gd")
var checks: Array = []

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)

func verify() -> void:
	for player in range(2):
		var r = Run.new()
		var index: int = r.kinds.find("active_spikes")
		var spec: Dictionary = r.hazard_specs[index].duplicate(true)
		r.obstacles.assign([Rect2(-55 if player == 0 else 29, 149.333333333333, 26, 8)])
		r.kinds.assign(["active_spikes"])
		r.obstacle_heights.assign([16.0])
		r.hazard_specs.assign([spec])
		r.retry()
		r.step(0)
		for frame in range(120):
			r.step(1.0 / 60, Vector2.ZERO, Vector2.ZERO, frame >= 63 and player == 0, frame >= 63 and player == 1)
		check("双方正常输入通过决策者伸出净空夹具 P" + str(player + 1), r.state == "running")
		var x: float = -42 if player == 0 else 42
		var inside := Vector2(x, 150)
		# 扩张后危险上边界为 169.333；离开/进入时间必须在刺高交叉点之外。
		var outside := Vector2(x, 400)
		check("伸出时未来高度不提前致命 P" + str(player + 1), not r.timed_hazard_hits(0, 1.1, 1.2, inside, outside, 7, 7))
		check("伸出中真正超过角色才命中 P" + str(player + 1), r.timed_hazard_hits(0, 1.1, 1.2, inside, inside, 7, 7))
		check("回落后接触不使用旧最高高度 P" + str(player + 1), not r.timed_hazard_hits(0, 2.3, 2.4, outside, inside, 10, 10))
		check("回落初期真实接触仍命中 P" + str(player + 1), r.timed_hazard_hits(0, 2.3, 2.4, inside, outside, 10, 10))
		check("跨激活边界接触发生于预警期不致命 P" + str(player + 1), not r.timed_hazard_hits(0, 0.9, 1.1, inside, Vector2(x, 200), 0, 0))
		check("跨失活边界仅安全期进入不致命 P" + str(player + 1), not r.timed_hazard_hits(0, 2.4, 2.6, Vector2(x, 200), inside, 0, 0))
		check("跨整段激活期首尾安全仍捕获 P" + str(player + 1), r.timed_hazard_hits(0, 0.9, 2.6, inside, inside, 0, 0))
		r.dispose()
	var failures := 0
	for item in checks:
		if not item.passed: failures += 1
	var output := FileAccess.open("res://tests/dynamic-hazard-result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed": failures == 0, "checks": checks, "failures": failures}, "\t"))
	quit(0 if failures == 0 else 1)
