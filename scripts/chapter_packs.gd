extends Node
# 章节数据包（自动加载 ChapterPacks）。
# 网页版主包只含脚本、主界面与封面；章节资源由 build-tools/split_web_pack.py 拆成若干数据包，
# 选中章节时才下载并挂载，多个章节共用的包只下载一次。浏览器缓存由网页外壳的 Service Worker
# 负责（web/sw.js）：下载过的包刷新页面后直接从本地缓存读取，不再走网络。
# 原生、无头和未拆包的网页没有清单，一律视为全部就绪，行为与拆包前完全相同。
#
# 传输：每个包另有一份 brotli 压缩文件（清单里的 transfer，扩展名 .pckz），服务器原样发送、
# 不带 Content-Encoding，下载后在这里解压。不能让服务器对 .pck 做 Content-Encoding 压缩：
# 浏览器交给引擎的是解压后的数据，HTTPRequest 却按响应头里压缩后的长度停止读取，文件会被截断。
# 解压失败（例如引擎不支持 brotli）时改为下载未压缩的原包。
signal changed

const CloudUpdate = preload("res://scripts/cloud_update.gd")
const MANIFEST := "packs.json"
# 下载块：HTTPRequest 每帧只读一块，块太小会把缓存命中时的读取速度限制在每帧 64KB。
const CHUNK := 4 << 20
const RETRIES := 2
var enabled := false
# idle / loading / ready / none（未拆包）/ stale（网页已更新）/ error
var manifest_state := "idle"
var manifest := {}
var base_url := ""
var store := ""
var mounted := {}
var queue: Array[String] = []
var active := ""
var attempts := {}
var failure := ""
var http: HTTPRequest
var cached := {}
var speed := 0.0
var speed_bytes := 0
var speed_clock := 0.0
var cache_clock := 0.0
var cache_polls := 20
var raw_fallback := {}

func _ready() -> void:
	# 桌面版云更新后的进程：该版本的数据包已全部下载到本机，启动时一次挂载，之后与整包相同。
	if CloudUpdate.mount_installed_packs():
		manifest_state = "none"
		return
	var url := packs_url()
	if url.is_empty():
		manifest_state = "none"
		return
	base_url = url if url.ends_with("/") else url + "/"
	store = "/tmp/ct-packs/" if OS.has_feature("web") else "user://ct-packs/"
	DirAccess.make_dir_recursive_absolute(store)
	http = HTTPRequest.new()
	http.use_threads = false
	http.download_chunk_size = CHUNK
	# 压缩由 .pckz 自行处理，不让引擎再按 Content-Encoding 解 gzip。
	http.accept_gzip = false
	add_child(http)
	http.request_completed.connect(_on_completed)
	manifest_state = "loading"
	# 清单每次向服务器确认，保证与当前主包同一次构建。
	if http.request(base_url + MANIFEST, ["Cache-Control: no-cache"]) != OK:
		fail_manifest("无法请求章节清单")

# 网页版从页面地址推出包目录；原生只在测试或本机验证时用 --packs-url= 打开。
static func packs_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--packs-url="): return arg.get_slice("=", 1)
	if not OS.has_feature("web"): return ""
	var href = JavaScriptBridge.eval("location.href.split('#')[0].split('?')[0].replace(/[^/]*$/, '')", true)
	return href if href is String else ""

func fail_manifest(message: String) -> void:
	manifest_state = "error"
	failure = message
	changed.emit()

func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if manifest_state == "loading":
		_on_manifest(result, code, body)
		return
	var name := active
	active = ""
	if name.is_empty(): return
	var info: Dictionary = manifest.packs[name]
	var plan := transfer(name)
	var data := PackedByteArray()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() == int(plan.size):
		data = body.decompress(int(info.size), FileAccess.COMPRESSION_BROTLI) if plan.compressed else body
		if plan.compressed and data.size() != int(info.size):
			push_warning("章节包 %s 解压失败，改为下载未压缩版本" % name)
			raw_fallback[name] = true
			data = PackedByteArray()
	body = PackedByteArray()
	var path := store + str(info.file).get_file()
	if data.size() == int(info.size):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(data)
			file.close()
	data = PackedByteArray()
	var size := FileAccess.open(path, FileAccess.READ).get_length() if FileAccess.file_exists(path) else -1
	if size != int(info.size):
		attempts[name] = int(attempts.get(name, 0)) + 1
		if attempts[name] <= RETRIES:
			queue.push_front(name)
		else:
			failure = "下载失败（%s，状态 %d，结果 %d，收到 %d / %d 字节），请检查网络后重试。" % [name, code, result, http.get_downloaded_bytes(), int(plan.size)]
			queue.clear()
	elif not ProjectSettings.load_resource_pack(path):
		failure = "章节数据无法读取（%s），请刷新页面重试。" % name
		queue.clear()
	else:
		mounted[name] = true
		cached[name] = true
	changed.emit()
	_pump()

# 本次下载用的文件：优先 brotli 压缩版（.pckz），解压失败过则用原包。
func transfer(name: String) -> Dictionary:
	var info: Dictionary = manifest.packs[name]
	if info.has("transfer") and not raw_fallback.has(name):
		return {"url": str(info.transfer), "size": int(info.transfer_size), "hash": str(info.get("transfer_hash", "")), "compressed": true}
	return {"url": str(info.file), "size": int(info.size), "hash": str(info.get("hash", "")), "compressed": false}

func _on_manifest(result: int, code: int, body: PackedByteArray) -> void:
	# 没有清单说明网页未拆包（整包导出或旧部署），全部资源已在主包内。
	if result != HTTPRequest.RESULT_SUCCESS or code == 404:
		manifest_state = "none"
		changed.emit()
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
	if not parsed is Dictionary or not parsed.has("packs") or not parsed.has("chapters"):
		fail_manifest("章节清单格式不对（状态 %d）" % code)
		return
	manifest = parsed
	var build := FileAccess.get_file_as_string("res://ct_build.txt").strip_edges()
	if build != str(manifest.get("build", "")):
		# 主包来自浏览器缓存的旧版本、清单已是新版本：两者混用会读坏资源，必须刷新。
		manifest_state = "stale"
		failure = "游戏已更新，请刷新页面载入新版本。"
		changed.emit()
		return
	enabled = true
	manifest_state = "ready"
	query_browser_cache()
	changed.emit()
	_pump()

# 当前设备需要的包：通用部分加上本机 GPU 支持的贴图压缩格式（桌面 s3tc、手机 etc2）。
func needed(chapter: int) -> Array[String]:
	var result: Array[String] = []
	if not enabled: return result
	for name in manifest.chapters.get(str(chapter), []):
		var feature: String = manifest.packs[name].get("feature", "")
		if feature.is_empty() or OS.has_feature(feature): result.append(name)
	return result

func missing(chapter: int) -> Array[String]:
	return needed(chapter).filter(func(name): return not mounted.has(name))

func is_ready(chapter: int) -> bool:
	if manifest_state in ["loading", "idle"]: return false
	return missing(chapter).is_empty()

func blocked() -> bool:
	return manifest_state in ["stale", "error"] or not failure.is_empty()

# urgent：玩家正在等待的章节排在最前；否则排在队尾（预取下一章）。
func request(chapter: int, urgent: bool = true) -> void:
	if urgent:
		failure = ""
		attempts.clear()
	var names := missing(chapter)
	if urgent: names.reverse()
	for name in names:
		if name == active: continue
		queue.erase(name)
		if urgent: queue.push_front(name)
		else: queue.append(name)
	_pump()

func _pump() -> void:
	if not enabled or not active.is_empty() or queue.is_empty() or not failure.is_empty(): return
	active = queue.pop_front()
	if mounted.has(active):
		active = ""
		_pump()
		return
	# 下载到内存再写入虚拟文件系统：压缩包要先解压，原包也一并按大小校验后再挂载。
	if http.request(base_url + str(transfer(active).url)) != OK:
		failure = "无法开始下载 %s。" % active
		active = ""
	changed.emit()

# 进度、剩余量都按实际传输的字节数（压缩版大小）计算。
func pack_size(name: String) -> int:
	return int(transfer(name).size) if enabled else 0

func bytes_total(chapter: int) -> int:
	var total := 0
	for name in needed(chapter): total += pack_size(name)
	return total

func bytes_done(chapter: int) -> int:
	var done := 0
	for name in needed(chapter):
		if mounted.has(name): done += pack_size(name)
		elif name == active: done += mini(http.get_downloaded_bytes(), pack_size(name))
	return done

# 本次还需要从网络或浏览器缓存读取的字节数（主界面显示“需下载 xx MB”）。
func bytes_missing(chapter: int) -> int:
	var total := 0
	for name in missing(chapter):
		if not cached.has(name): total += pack_size(name)
	return total

func progress(chapter: int) -> float:
	var total := bytes_total(chapter)
	return 1.0 if total == 0 else clampf(float(bytes_done(chapter)) / total, 0.0, 1.0)

func downloading(chapter: int) -> bool:
	return not active.is_empty() and needed(chapter).has(active)

func _process(delta: float) -> void:
	# 浏览器缓存查询是异步的，清单就绪后的头几秒轮询结果，供主界面标注“已缓存”。
	cache_clock += delta
	if cache_clock >= 0.5 and cache_polls < 20:
		cache_clock = 0.0
		cache_polls += 1
		poll_browser_cache()
	# 下载速度取约 1 秒的滑动平均，载入画面据此估算剩余时间。
	if active.is_empty():
		speed_bytes = 0
		return
	speed_clock += delta
	if speed_clock >= 0.5:
		var now := http.get_downloaded_bytes()
		var rate := maxf(0.0, (now - speed_bytes) / speed_clock)
		speed = rate if speed <= 0.0 else lerpf(speed, rate, 0.5)
		speed_bytes = now
		speed_clock = 0.0

# 询问网页外壳哪些包已在浏览器缓存里（异步，结果写回 window.ctCached）。
func query_browser_cache() -> void:
	if not OS.has_feature("web"): return
	cache_polls = 0
	var files := []
	for name in manifest.packs:
		var plan := transfer(name)
		files.append({"name": name, "file": plan.url, "hash": plan.hash})
	JavaScriptBridge.eval("window.ctQueryCache && window.ctQueryCache(%s)" % JSON.stringify(files), true)

func poll_browser_cache() -> void:
	if not OS.has_feature("web") or not enabled: return
	var text = JavaScriptBridge.eval("JSON.stringify(window.ctCached || {})", true)
	if not text is String: return
	var known = JSON.parse_string(text)
	if not known is Dictionary: return
	var before := cached.size()
	for name in known:
		if known[name]: cached[name] = true
	if cached.size() != before: changed.emit()

static func megabytes(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1048576.0)
