extends RefCounted
# 队列只在主线程访问；后台读取完成前不调用 load_threaded_get。
const MAX_REQUESTS := 2
var pending: Array[String] = []
var active: Array[String] = []
var resources := {}
var error := ""
var total := 0
func request(paths: Array) -> void:
	for path in paths:
		if resources.has(path) or pending.has(path) or active.has(path): continue
		pending.append(path)
		total += 1
func poll(deadline_usec: int = 0) -> bool:
	for path in active.duplicate():
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec: break
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			resources[path] = ResourceLoader.load_threaded_get(path)
			active.erase(path)
		elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			error = path
			return false
	while error.is_empty() and active.size() < MAX_REQUESTS and not pending.is_empty():
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec: break
		var path: String = pending.pop_front()
		if ResourceLoader.load_threaded_request(path) != OK:
			error = path
			return false
		active.append(path)
	return error.is_empty() and active.is_empty() and pending.is_empty()
func ready(paths: Array) -> bool:
	return paths.all(func(path): return resources.has(path))
func progress() -> float:
	return float(resources.size()) / maxi(total, 1)
func dispose() -> void:
	# 退出场景时回收已提交的 IO；运行帧从不通过 get 等待未完成资源。
	pending.clear()
	for path in active:
		if ResourceLoader.load_threaded_get_status(path) in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]: ResourceLoader.load_threaded_get(path)
	active.clear()
	resources.clear()
static func startup_paths() -> Array:
	var paths: Array = ["res://scenes/journey.tscn", "res://assets/env/belfast_sunset_puresky_2k.hdr"]
	for prefix in ["res://assets/env/monastery_stone_floor", "res://assets/env/rock_boulder_dry", "res://assets/journey/forest_leaves_02"]:
		for suffix in ["diff", "nor", "rough"]:
			var path: String = prefix+"_"+suffix+".jpg"
			if ResourceLoader.exists(path): paths.append(path)
	for name in ["Pine", "Bush", "TallGrass", "Column"]: paths.append("res://assets/decor/%s.glb" % name)
	for name in ["Adventurer_A", "Adventurer_B", "rescue_climb", "rescue_ropepull"]: paths.append("res://assets/humans/%s.glb" % name)
	for name in ["sign", "gate", "falling_tree"]: paths.append("res://assets/journey/%s.glb" % name)
	return paths
static func hazard_paths(kinds: Array) -> Array:
	var paths: Array=[]
	if "drone" in kinds: paths.append("res://assets/props/Eagle_Flying.glb")
	if "forklift" in kinds or "shuttle" in kinds: paths.append("res://assets/props/Minecart_HunterParamore.glb")
	return paths
