extends SceneTree
const Presentation = preload("res://scripts/online_presentation.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	print("PASS " if ok else "FAIL ", text)
	if not ok: failures += 1
func _initialize() -> void:
	var visual = Presentation.new()
	var first: Array[Vector3] = [Vector3.ZERO, Vector3(0, 1.4, 0)]
	visual.sample(first, 1.0/60.0)
	var next: Array[Vector3] = [Vector3(0.4,0,0), Vector3(0.4,1.4,0)]
	var half: Array[Vector3] = visual.sample(next, 1.0/60.0).duplicate()
	check(half[0].x>0 and half[0].x<0.4, "双步推进在显示层平滑到中间位置")
	check(half[1]-half[0]==Vector3(0,1.4,0), "角色与绳端保持相同插值时刻")
	var idle: Array[Vector3] = visual.sample(next,1.0/120.0).duplicate()
	check(idle[0].x>half[0].x and idle[0].x<0.4, "没有新模拟帧时高刷新率显示仍连续推进")
	check(visual.sample(next,1.0/60.0)==next, "目标不变时两帧内到达，不外推")
	check(next[0]==Vector3(0.4,0,0), "不修改输入状态")
	var retry: Array[Vector3] = [Vector3(0,0,20),Vector3(0,1.4,20)]
	check(visual.sample(retry,1.0/120.0)==retry, "存档恢复或大位移直接重置")
	visual.reset()
	check(visual.sample(first,1.0/120.0)==first, "暂停、救援、失败或换章后无旧位置残留")
	check(visual.sample([Vector3.ZERO],1.0/120.0)==[Vector3.ZERO], "绳拓扑变化直接重置")
	print("ONLINE PRESENTATION failures=",failures)
	quit(1 if failures else 0)
