extends Node
# 桌面版云更新。启动时按玩家填写的更新链接读取 manifest.json（由 build-tools/publish_update.py 生成），
# 把新版本的主包与章节数据包下载到 user://ct-update/files/，文件名带内容哈希，未变化的包不重复下载；
# 逐个校验 SHA-256 后用 --main-pack 重新启动自身进入新版本。exe 本身不更新，引擎版本变化时提示下载完整安装包。
# 清单同时带联机服务器地址与备用更新链接：换隧道或节点只需改清单，玩家下次检查更新时自动换用。
# 更新服务器连不上时不阻塞游戏：有已下载的新版本就进入它，否则用安装包自带的版本。
signal progress(text: String, ratio: float)
# outcome：relaunch（已启动新版本，本进程即将退出）/ current（已是最新）/ offline（连不上，继续当前版本）/ failed
signal finished(outcome: String, message: String)

const STORE := "user://ct-update/"
const FILES := STORE + "files/"
const CONFIG := STORE + "update.cfg"
const CURRENT := STORE + "current.json"
const MANIFEST := "manifest.json"
const FORMAT := 1
const RELEASE_FILE := "res://ct_release.txt"
# 玩家没填链接时使用；主机换了隧道后，玩家在“检查更新”里粘贴新链接即可，不必重新安装。
const DEFAULT_URLS: Array[String] = ["https://www.u4139693.nyat.app:57412/update/"]
const MANIFEST_TIMEOUT := 8.0

var http: HTTPRequest
var busy := false
var manifest := {}
var base_url := ""

# 只在导出的桌面程序里启用；源码运行可用 --ct-update-test 测试，--ct-no-update 关闭。
static func supported() -> bool:
	if OS.has_feature("web") or has_arg("--ct-no-update"): return false
	if has_arg("--ct-update-test"): return true
	return OS.has_feature("template") and DisplayServer.get_name() != "headless"

static func has_arg(name: String) -> bool:
	return OS.get_cmdline_user_args().has(name)

static func arg_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix + "="): return arg.substr(prefix.length() + 1)
	return ""

# 当前运行的版本：更新后启动时由启动参数带入，否则取安装包导出时写入的版本号。
static func current_release() -> String:
	var value := arg_value("--ct-release")
	if not value.is_empty(): return value
	if FileAccess.file_exists(RELEASE_FILE): return FileAccess.get_file_as_string(RELEASE_FILE).strip_edges()
	return ""

static func running_update() -> bool:
	return not arg_value("--ct-release").is_empty()

static func load_config() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(CONFIG)
	return config

static func normalize(url: String) -> String:
	var text := url.strip_edges()
	if text.is_empty(): return ""
	if not text.contains("://"): text = "http://" + text
	if text.ends_with(MANIFEST): text = text.substr(0, text.length() - MANIFEST.length())
	return text if text.ends_with("/") else text + "/"

# 玩家自己填的链接（界面里显示与编辑的内容）。
static func user_urls() -> Array[String]:
	var result: Array[String] = []
	for url in load_config().get_value("update", "urls", PackedStringArray()):
		var text := normalize(str(url))
		if not text.is_empty() and not result.has(text): result.append(text)
	return result

static func save_user_urls(list: Array) -> void:
	var config := load_config()
	var clean := PackedStringArray()
	for url in list:
		var text := normalize(str(url))
		if not text.is_empty() and not clean.has(text): clean.append(text)
	config.set_value("update", "urls", clean)
	DirAccess.make_dir_recursive_absolute(STORE)
	config.save(CONFIG)

# 尝试顺序：玩家填的 → 上次清单里给的备用链接 → 内置默认。
static func urls() -> Array[String]:
	var result := user_urls()
	var extra: Array = Array(load_config().get_value("update", "learned", PackedStringArray()))
	extra.append_array(DEFAULT_URLS)
	for url in extra:
		var text := normalize(str(url))
		if not text.is_empty() and not result.has(text): result.append(text)
	return result

# 清单下发的联机地址（kind：udp / ws），没有时返回空字符串，由 net_client 退回内置地址。
static func server(kind: String) -> String:
	return str(load_config().get_value("servers", kind, ""))

static func load_installed() -> Dictionary:
	if not FileAccess.file_exists(CURRENT): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CURRENT))
	return parsed if parsed is Dictionary and parsed.has("release") and parsed.has("core") else {}

static func installed_ready(info: Dictionary) -> bool:
	if info.is_empty(): return false
	var files: Array = [info.core]
	files.append_array(info.get("packs", []))
	for path in files:
		if not FileAccess.file_exists(FILES + str(path)): return false
	return true

# 更新后的进程由 ChapterPacks 在加载任何章节资源前调用：挂载该版本的全部数据包。
static func mount_installed_packs() -> bool:
	if not running_update(): return false
	var info := load_installed()
	if info.is_empty() or str(info.release) != current_release(): return false
	for name in info.get("packs", []):
		if not ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(FILES + str(name))):
			push_error("更新数据包无法挂载：" + str(name))
			return false
	return true

static func engine_hash() -> String:
	return str(Engine.get_version_info().hash)

func _ready() -> void:
	http = HTTPRequest.new()
	http.use_threads = true
	http.download_chunk_size = 1 << 20
	add_child(http)

func run() -> void:
	if busy: return
	busy = true
	manifest = {}
	var errors: Array[String] = []
	for url in urls():
		progress.emit("正在检查更新：" + url, 0.0)
		var reply: Dictionary = await request(url + MANIFEST, "", MANIFEST_TIMEOUT)
		if not reply.ok:
			errors.append("%s（%s）" % [url, reply.error])
			continue
		var parsed = JSON.parse_string(reply.body)
		if not parsed is Dictionary or int(parsed.get("format", 0)) != FORMAT or not parsed.has("release") or not parsed.has("core"):
			errors.append(url + "（清单格式不对）")
			continue
		manifest = parsed
		base_url = url
		break
	if manifest.is_empty():
		fall_back("没连上更新服务器，继续使用当前版本。\n" + "\n".join(errors))
		return
	remember(manifest)
	# 清单记录发布时引擎版本的短哈希（godot --version 末段）。
	if not engine_hash().begins_with(str(manifest.get("engine", ""))):
		var installer: Dictionary = manifest.get("installer", {})
		var link: String = base_url + str(installer.get("file", "")) if installer.has("file") else base_url
		done("failed", "新版本换了引擎，需要重新下载完整安装包：\n" + link)
		return
	if str(manifest.release) == current_release():
		done("current", "已是最新版本（%s）。" % current_release())
		return
	var installed := load_installed()
	if str(installed.get("release", "")) == str(manifest.release) and installed_ready(installed):
		relaunch(installed)
		return
	await download_release()

func fall_back(message: String) -> void:
	var installed := load_installed()
	# 版本号以导出时间开头，按字符串比较即新旧；安装包比已下载的版本还新时不退回旧版。
	if not running_update() and installed_ready(installed) and str(installed.release) > current_release():
		relaunch(installed)
		return
	done("offline", message)

func remember(data: Dictionary) -> void:
	var config := load_config()
	var servers: Dictionary = data.get("servers", {})
	for kind in ["udp", "ws"]:
		config.set_value("servers", kind, str(servers.get(kind, "")))
	var learned := PackedStringArray()
	for url in data.get("update_urls", []): learned.append(normalize(str(url)))
	config.set_value("update", "learned", learned)
	DirAccess.make_dir_recursive_absolute(STORE)
	config.save(CONFIG)

# 本机需要的包：主包，加上通用与本机显卡支持的贴图格式（桌面 s3tc）。
func wanted() -> Array[Dictionary]:
	var result: Array[Dictionary] = [manifest.core]
	var packs: Dictionary = manifest.get("packs", {})
	var names := packs.keys()
	names.sort()
	for name in names:
		var info: Dictionary = packs[name]
		var feature := str(info.get("feature", ""))
		if feature.is_empty() or OS.has_feature(feature): result.append(info)
	return result

func download_release() -> void:
	DirAccess.make_dir_recursive_absolute(FILES)
	var items := wanted()
	var total := 0
	for info in items: total += int(info.size)
	var done_bytes := 0
	for info in items:
		var name := str(info.file).get_file()
		var path := FILES + name
		if not verified(path, info):
			var part := path + ".part"
			var reply: Dictionary = await request(base_url + str(info.file), part, 0.0, done_bytes, total)
			if not reply.ok:
				fall_back("下载 %s 失败（%s），继续使用当前版本。" % [name, reply.error])
				return
			if not verified(part, info):
				DirAccess.remove_absolute(part)
				fall_back("%s 校验失败，继续使用当前版本。" % name)
				return
			DirAccess.remove_absolute(path)
			DirAccess.rename_absolute(part, path)
		done_bytes += int(info.size)
	var packs: Array[String] = []
	for info in items.slice(1): packs.append(str(info.file).get_file())
	var record := {"release": str(manifest.release), "core": str(manifest.core.file).get_file(), "packs": packs}
	var file := FileAccess.open(CURRENT, FileAccess.WRITE)
	file.store_string(JSON.stringify(record, " "))
	file.close()
	prune(record)
	relaunch(record)

func verified(path: String, info: Dictionary) -> bool:
	if not FileAccess.file_exists(path): return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != int(info.size): return false
	file.close()
	return FileAccess.get_sha256(path) == str(info.sha256)

# 只保留当前版本用到的文件，旧版本的包删掉，避免越更新越占空间。
func prune(record: Dictionary) -> void:
	var keep: Array = [record.core]
	keep.append_array(record.packs)
	for name in DirAccess.get_files_at(FILES):
		if not keep.has(name): DirAccess.remove_absolute(FILES + name)

func relaunch(info: Dictionary) -> void:
	var args := PackedStringArray(["--main-pack", ProjectSettings.globalize_path(FILES + str(info.core)), "--", "--ct-release=" + str(info.release)])
	if DisplayServer.get_name() == "headless": args.insert(0, "--headless")
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--ct-release="): args.append(arg)
	progress.emit("正在启动新版本 %s …" % info.release, 1.0)
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		done("failed", "新版本已下载，但无法启动（%s）。" % OS.get_executable_path())
		return
	done("relaunch", "")
	get_tree().quit()

func done(outcome: String, message: String) -> void:
	busy = false
	finished.emit(outcome, message)

# timeout 为 0 表示不限总时长（大文件）；下载期间按已收字节汇报进度。
func request(url: String, target: String, timeout: float, offset: int = 0, total: int = 0) -> Dictionary:
	http.timeout = timeout
	http.download_file = target
	var result := []
	var callback := func(code: int, status: int, _headers: PackedStringArray, body: PackedByteArray): result.append([code, status, body])
	http.request_completed.connect(callback, CONNECT_ONE_SHOT)
	if http.request(url, ["Cache-Control: no-cache"]) != OK:
		http.request_completed.disconnect(callback)
		return {"ok": false, "error": "无法发起请求"}
	while result.is_empty():
		await get_tree().process_frame
		if total > 0:
			var got := offset + http.get_downloaded_bytes()
			progress.emit("正在下载新版本 %s / %s" % [megabytes(got), megabytes(total)], clampf(float(got) / total, 0.0, 1.0))
	var code: int = result[0][0]
	var status: int = result[0][1]
	if code != HTTPRequest.RESULT_SUCCESS: return {"ok": false, "error": "网络错误 %d" % code}
	if status != 200: return {"ok": false, "error": "HTTP %d" % status}
	return {"ok": true, "body": (result[0][2] as PackedByteArray).get_string_from_utf8()}

static func megabytes(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1048576.0)
