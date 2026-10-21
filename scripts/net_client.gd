extends Node
# 联机客户端：上传本机玩家输入，接收服务器按帧打包的双人输入与命令，交给游戏逐帧模拟。

signal status_changed(text: String)
signal match_started(seed: int)
signal match_stopped(reason: String)

const Relay = preload("res://scripts/net_relay.gd")
const HASH_INTERVAL := 60
# 桌面版（发给朋友的 Windows 程序）默认连接的服务器：经 SakuraFrp TCP 隧道（自动 HTTPS）到主机电脑上的
# deploy/windows/serve_web.py，再由 /ws 转给联机中继。可用启动参数 -- --server=地址 覆盖；
# 玩家改过并成功连接的地址保存在 user://online.cfg，下次启动沿用。
const DEFAULT_SERVER := "wss://www.u4139693.nyat.app:57412/ws"
const ADDRESS_FILE := "user://online.cfg"
# 输入只在变化时上传（服务器沿用上一份），另每秒补发一次以防万一；静止或按住方向时几乎没有上行流量。
const INPUT_REFRESH_MSEC := 1000

var peer: MultiplayerPeer = null
var api := SceneMultiplayer.new()
var role := -1
var in_match := false
var frames: Array = []
var next_frame := 0
var desynced := false
var connected := false
var last_address := ""
# 桌面版 wss 证书校验失败时（安全软件、校园网或公司网截获 HTTPS 很常见），改用不校验证书的加密连接重试一次。
var tls_relaxed := false
var last_input := PackedByteArray()
var last_input_msec := 0
# 联机流量统计（字节，含本层负载，不含传输层头部），供测试与网页验证读取。
var bytes_sent := 0
var bytes_received := 0
# 联机质量：往返延迟（ping/pong）、服务器帧到达间隔的抖动、缓冲见底的卡顿次数。
# 只用于显示、日志和自适应缓冲，不进入模拟，两端同步不受影响。
const DIAG_FILE := "user://online_diag.log"
const FRAME_MS := 1000.0 / 60.0
var rtt_ms := -1.0
var gaps: Array[float] = []
var last_arrival_usec := 0
var starved := false
var stalls := 0
var stalls_window := 0
var ping_clock := 0.0
var stat_clock := 0.0

func _ready() -> void:
	get_tree().set_multiplayer(api, get_path())
	api.connected_to_server.connect(func():
		connected = true
		remember_address(last_address)
		status_changed.emit("已连上服务器，等待分配位置…"))
	api.connection_failed.connect(_on_connection_failed)
	api.server_disconnected.connect(func(): stop("与服务器断开。"))
	api.peer_packet.connect(_on_packet)

# 地址可写 “主机”、“主机:端口”、“[IPv6]:端口”，或 ws:// / wss:// 开头的完整地址。
# 原生客户端默认走 ENet（UDP）；网页版浏览器不能收发 UDP，一律走 WebSocket。
func connect_to(address: String, relaxed: bool = false) -> void:
	disconnect_from()
	last_address = address
	tls_relaxed = relaxed
	var target := parse_address(address, OS.has_feature("web"), page_is_secure())
	if target.has("error"):
		status_changed.emit(target.error)
		return
	var error: int
	if target.kind == "ws":
		var ws := WebSocketMultiplayerPeer.new()
		error = ws.create_client(target.url, TLSOptions.client_unsafe() if relaxed else TLSOptions.client())
		peer = ws
	else:
		var enet := ENetMultiplayerPeer.new()
		error = enet.create_client(target.host, target.port)
		peer = enet
	if error != OK:
		peer = null
		status_changed.emit("无法创建连接（错误 %d）。" % error)
		return
	api.multiplayer_peer = peer
	status_changed.emit("正在连接 %s …" % target.label)

# 纯函数，便于测试。返回 {kind: "enet"/"ws", host, port, url, label} 或 {error}。
static func parse_address(address: String, web: bool, secure_page: bool) -> Dictionary:
	var text := address.strip_edges()
	if text.is_empty():
		return {"error": "请先填写服务器地址。"}
	var lower := text.to_lower()
	if lower.begins_with("ws://") or lower.begins_with("wss://"):
		if secure_page and lower.begins_with("ws://"):
			return {"error": "网页是 https 打开的，只能连接 wss:// 开头的地址。"}
		return {"kind": "ws", "url": text, "label": text}
	if text.contains("://"):
		return {"error": "地址格式不对：只支持 主机:端口、ws:// 或 wss:// 开头的地址。"}
	var host := text
	var port := -1
	if text.begins_with("["):
		var close := text.find("]")
		if close < 0: return {"error": "IPv6 地址缺少右方括号 ]。"}
		host = text.substr(1, close - 1)
		var rest := text.substr(close + 1)
		if rest.begins_with(":"):
			port = rest.substr(1).to_int() if rest.substr(1).is_valid_int() else 0
		elif not rest.is_empty():
			return {"error": "地址格式不对。"}
	elif text.count(":") == 1:
		host = text.get_slice(":", 0)
		var tail := text.get_slice(":", 1)
		port = tail.to_int() if tail.is_valid_int() else 0
	if host.is_empty() or port == 0 or port > 65535:
		return {"error": "地址格式不对：端口应为 1～65535 的数字。"}
	if web:
		var scheme := "wss" if secure_page else "ws"
		var url := "%s://%s" % [scheme, "[%s]" % host if host.contains(":") else host]
		# https 网页不写端口时走 443；http 网页不写端口时直连中继的 WebSocket 端口。
		if port < 0 and not secure_page: port = Relay.DEFAULT_WS_PORT
		if port > 0: url += ":%d" % port
		return {"kind": "ws", "url": url, "label": url}
	if port < 0: port = Relay.DEFAULT_PORT
	return {"kind": "enet", "host": host, "port": port, "label": "%s:%d" % [host, port]}

static func page_is_secure() -> bool:
	if not OS.has_feature("web"): return false
	return str(JavaScriptBridge.eval("location.protocol", true)) == "https:"

# 网页版的默认服务器地址：网址里的 ?server= 优先；否则用网页所在主机的 /ws（网页与中继由同一台机器提供时免填）。
# 原生客户端返回空字符串，沿用本地保存的地址。
# 开始页地址框的初始值：网页用页面所在主机；桌面版依次取启动参数、上次连接成功的地址、默认服务器。
static func default_address() -> String:
	var page := page_default_address()
	if not page.is_empty(): return page
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="): return arg.get_slice("=", 1)
	var config := ConfigFile.new()
	if config.load(ADDRESS_FILE) == OK:
		var saved := str(config.get_value("online", "address", ""))
		if not saved.is_empty(): return saved
	return DEFAULT_SERVER

static func remember_address(address: String) -> void:
	# 无界面自动化测试连本机测试端口，不能把测试地址写进玩家的默认地址。
	if OS.has_feature("web") or DisplayServer.get_name() == "headless": return
	var config := ConfigFile.new()
	config.set_value("online", "address", address.strip_edges())
	config.save(ADDRESS_FILE)

static func page_default_address() -> String:
	if not OS.has_feature("web"): return ""
	var server = JavaScriptBridge.eval("new URLSearchParams(location.search).get('server') || ''", true)
	if server is String and not server.is_empty(): return server
	var host = JavaScriptBridge.eval("location.host", true)
	if not host is String or host.is_empty(): return ""
	return ("wss://" if page_is_secure() else "ws://") + host + "/ws"

func _on_connection_failed() -> void:
	var secure := last_address.strip_edges().to_lower().begins_with("wss://")
	if secure and not tls_relaxed and not OS.has_feature("web"):
		status_changed.emit("加密校验未通过，正在改用兼容方式重连…")
		connect_to.call_deferred(last_address, true)
		return
	stop("连接失败：%s 连不上。请确认主机电脑的联机服务和 SakuraFrp 在线，并用浏览器打开 %s 看能否访问。" % [last_address, browser_url(last_address)])

# 服务器地址对应的网页地址，便于玩家用浏览器排查网络是否可达。
static func browser_url(address: String) -> String:
	var text := address.strip_edges()
	if text.to_lower().begins_with("wss://"): text = "https://" + text.substr(6)
	elif text.to_lower().begins_with("ws://"): text = "http://" + text.substr(5)
	return text.trim_suffix("/ws")

func disconnect_from() -> void:
	if peer != null:
		peer.close()
	api.multiplayer_peer = null
	peer = null
	connected = false
	role = -1
	in_match = false
	frames.clear()
	last_input = PackedByteArray()

func stop(reason: String) -> void:
	var was_in_match := in_match
	disconnect_from()
	status_changed.emit(reason)
	if was_in_match: match_stopped.emit(reason)

func active() -> bool:
	return peer != null

func send(message: Array, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE) -> void:
	send_raw(var_to_bytes(message), mode)

func send_raw(bytes: PackedByteArray, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE) -> void:
	if not connected: return
	api.send_bytes(bytes, 1, mode, 0)
	bytes_sent += bytes.size()

func send_input(move: Vector2, jump: bool) -> void:
	var bytes := Relay.encode_input(roundi(clampf(move.x, -1, 1) * 100), roundi(clampf(move.y, -1, 1) * 100), jump)
	var now := Time.get_ticks_msec()
	if bytes == last_input and now - last_input_msec < INPUT_REFRESH_MSEC: return
	last_input = bytes
	last_input_msec = now
	send_raw(bytes)

func send_command(name: String, arg := "") -> void:
	send(["cmd", name, arg])

# 每模拟一帧后调用；定期上报状态指纹，由服务器比对两端是否一致。
func report(frame: int, state_hash: int) -> void:
	if frame % HASH_INTERVAL == 0: send(["hash", frame, state_hash])

func _on_packet(_id: int, bytes: PackedByteArray) -> void:
	bytes_received += bytes.size()
	if not bytes.is_empty() and bytes[0] == Relay.FRAME_TAG:
		var frame := Relay.decode_frame(bytes)
		var now := Time.get_ticks_usec()
		if last_arrival_usec > 0:
			gaps.append((now - last_arrival_usec) / 1000.0)
			if gaps.size() > 180: gaps.pop_front()
		last_arrival_usec = now
		if in_match and not frame.is_empty() and int(frame.index) == next_frame + frames.size():
			frame.erase("index")
			frames.append(frame)
		return
	var message = bytes_to_var(bytes)
	if not message is Array or message.is_empty(): return
	match message[0]:
		"welcome":
			if int(message[2]) != Relay.PROTOCOL:
				stop("版本不一致：请两人都安装同一版游戏。")
				return
			role = int(message[1])
			status_changed.emit("你是 %02d 号，等待队友加入…" % (role + 1))
		"lobby":
			if not in_match and role >= 0:
				status_changed.emit("你是 %02d 号 · 房间 %d/2 人" % [role + 1, int(message[1])])
		"full":
			stop("房间已满（已有两人）。")
		"match":
			frames.clear()
			gaps.clear()
			starved = false
			stalls = 0
			last_input = PackedByteArray()
			next_frame = 0
			desynced = false
			in_match = true
			status_changed.emit("联机中 · 你是 %02d 号" % (role + 1))
			match_started.emit(int(message[1]))
		"peer_left":
			in_match = false
			frames.clear()
			status_changed.emit("队友已断开，等待重新加入…")
			match_stopped.emit("队友已断开")
		"pong":
			if message.size() >= 2:
				var sample := (Time.get_ticks_usec() - int(message[1])) / 1000.0
				rtt_ms = sample if rtt_ms < 0 else lerpf(rtt_ms, sample, 0.3)
		"desync":
			desynced = true
			status_changed.emit("两端画面不同步（第 %d 帧），请回到开始页重新联机。" % int(message[1]))

# 近 3 秒服务器帧到达间隔超出 1 帧的部分（取 95% 分位），即网络抖动。
func jitter_ms() -> float:
	if gaps.size() < 20: return 0.0
	var sorted := gaps.duplicate()
	sorted.sort()
	return maxf(0.0, sorted[int(sorted.size() * 0.95)] - FRAME_MS)

# 自适应缓冲目标：抖动越大多留几帧（2–6 帧），用几十毫秒延迟换平滑，不再停一下、快进一下。
func playout_target() -> int:
	return clampi(1 + ceili(jitter_ms() / FRAME_MS), 2, 6)

# 本物理帧最多消化几帧。缓冲见底即记一次卡顿，并等攒回目标帧数再继续；
# 只改变应用时机，不跳帧、不改帧内容，模拟结果与两端同步不变。
func playout_limit(catchup: int) -> int:
	var queued := frames.size()
	var target := playout_target()
	if queued == 0:
		if not starved:
			starved = true
			stalls += 1
			stalls_window += 1
		return 0
	if starved:
		if queued < target: return 0
		starved = false
	if queued <= target: return 1
	if queued <= target + 6: return 2
	return mini(catchup, queued - target)

func _process(delta: float) -> void:
	if not connected: return
	ping_clock += delta
	if ping_clock >= 1.0:
		ping_clock = 0.0
		send(["ping", Time.get_ticks_usec()])
	if not in_match: return
	stat_clock += delta
	if stat_clock >= 10.0:
		stat_clock = 0.0
		var line := [roundi(rtt_ms), roundi(jitter_ms()), frames.size(), stalls_window, roundi(Engine.get_frames_per_second())]
		send(["stat"] + line)
		var file := FileAccess.open(DIAG_FILE, FileAccess.READ_WRITE if FileAccess.file_exists(DIAG_FILE) else FileAccess.WRITE)
		if file != null:
			file.seek_end()
			file.store_line("%s 你是 %02d 号 延迟 %d ms 抖动 %d ms 缓冲 %d 帧 近10秒卡顿 %d 次 帧率 %d" % ([Time.get_datetime_string_from_system(), role + 1] + line))
			file.close()
		stalls_window = 0

func diagnostics_text() -> String:
	return "延迟 %s · 抖动 %d ms · 缓冲 %d 帧 · 卡顿 %d 次 · %d 帧/秒" % [("%d ms" % roundi(rtt_ms)) if rtt_ms >= 0 else "—", roundi(jitter_ms()), frames.size(), stalls, roundi(Engine.get_frames_per_second())]

# 取出本次物理帧要模拟的帧：通常一帧；积压时追帧，保留少量缓冲吸收网络抖动。
func take_frames(maximum: int = -1) -> Array:
	var count := 0
	if frames.size() > 8: count = frames.size() - 2
	elif frames.size() > 3: count = 2
	elif frames.size() > 0: count = 1
	if maximum >= 0: count = mini(count, maximum)
	var out := frames.slice(0, count)
	frames = frames.slice(count)
	next_frame += count
	return out
