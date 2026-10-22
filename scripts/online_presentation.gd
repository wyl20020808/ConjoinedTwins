extends RefCounted
# 仅保存显示位置。两个网络帧内追到目标，不外推；状态切换与大位移直接重置。
const BLEND_SECONDS := 1.0 / 30.0
const SNAP_DISTANCE := 2.0
var target: Array[Vector3] = []
var origin: Array[Vector3] = []
var displayed: Array[Vector3] = []
var age := 0.0

func reset() -> void:
	target.clear()
	origin.clear()
	displayed.clear()
	age = 0.0

func sample(points: Array[Vector3], delta: float) -> Array[Vector3]:
	var snap := points.size() != target.size() or target.is_empty()
	if not snap:
		for i in range(points.size()):
			if points[i].distance_to(target[i]) > SNAP_DISTANCE:
				snap = true
				break
	if snap:
		target = points.duplicate()
		origin = points.duplicate()
		displayed = points.duplicate()
		age = BLEND_SECONDS
	elif points != target:
		origin = displayed.duplicate()
		target = points.duplicate()
		age = 0.0
	age = minf(BLEND_SECONDS, age + maxf(0.0, delta))
	var weight := age / BLEND_SECONDS
	for i in range(target.size()): displayed[i] = origin[i].lerp(target[i], weight)
	return displayed
