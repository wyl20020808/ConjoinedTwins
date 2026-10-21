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
	# Godot 4.7.1 Dummy RID 容器不支持资源线程与主线程并发分配/释放。
	# 无界面验证按原队列在主线程加载；真实窗口和 Web 仍使用后台 IO。
	# 上游问题：https://github.com/godotengine/godot/issues/124139
	if DisplayServer.get_name()=="headless":
		while error.is_empty() and not pending.is_empty():
			if deadline_usec>0 and Time.get_ticks_usec()>=deadline_usec:break
			var path:String=pending.pop_front()
			var resource:=ResourceLoader.load(path)
			if resource==null:error=path;return false
			resources[path]=resource
		return error.is_empty() and pending.is_empty()
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
# 只释放队列持有的引用；仍被场景使用的网格/贴图由场景继续持有。
func retain(paths:Array)->void:
	for path in resources.keys():
		if not paths.has(path):resources.erase(path)

func dispose() -> void:
	# 退出场景时回收已提交的 IO；运行帧从不通过 get 等待未完成资源。
	pending.clear()
	for path in active:
		if ResourceLoader.load_threaded_get_status(path) in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]: ResourceLoader.load_threaded_get(path)
	active.clear()
	resources.clear()
# web 参数供章节拆包巡检取得网页分支的首屏路径；运行时按当前平台判断。
static func startup_paths(web: bool = OS.has_feature("web")) -> Array:
	var paths: Array = ["res://scenes/journey.tscn", "res://assets/env/belfast_sunset_puresky_2k.hdr"]
	if web:
		# 连续旅程首屏用地貌材质，不预读旧白盒的整套装饰模型。
		paths.append_array(["res://assets/env/rock_face_03_diff.jpg","res://assets/env/rock_face_03_nor.jpg","res://assets/decor/Pine_Bark_NormalTree.png","res://assets/decor/Pine_Bark_NormalTree_Normal.png","res://assets/journey/wood_planks_diff.jpg"])
	for prefix in ["res://assets/env/monastery_stone_floor", "res://assets/env/rock_boulder_dry", "res://assets/journey/forest_leaves_02"]:
		for suffix in ["diff", "nor", "rough"]:
			var path: String = prefix+"_"+suffix+".jpg"
			if ResourceLoader.exists(path): paths.append(path)
	if not web:
		for name in ["Pine", "Bush", "TallGrass", "Column"]: paths.append("res://assets/decor/%s.glb" % name)
	# Adventurer_A 只作动画来源；主角模型为 Tripo 生成的 hero_01/02。
	for name in ["hero_01", "hero_02", "Adventurer_A", "rescue_climb", "rescue_ropepull"]: paths.append("res://assets/humans/%s.glb" % name)
	for name in ["sign", "gate"]: paths.append("res://assets/journey/%s.glb" % name)
	return paths
static func hazard_paths(kinds: Array) -> Array:
	var paths: Array=[]
	if "drone" in kinds: paths.append("res://assets/props/Eagle_Flying.glb")
	if "forklift" in kinds or "shuttle" in kinds: paths.append("res://assets/props/Minecart_HunterParamore.glb")
	return paths
