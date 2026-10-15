extends Node
# 联机客户端：上传本机玩家输入，接收服务器按帧打包的双人输入与命令，交给游戏逐帧模拟。

signal status_changed(text: String)
signal match_started(seed: int)
signal match_stopped(reason: String)

const Relay = preload("res://scripts/net_relay.gd")
const HASH_INTERVAL := 60

var peer: MultiplayerPeer = null
var api := SceneMultiplayer.new()
var role := -1
var in_match := false
var frames: Array = []
var next_frame := 0
var desynced := false
var connected := false

func _ready() -> void:
	get_tree().set_multiplayer(api, get_path())
	api.connected_to_server.connect(func(): connected = true; status_changed.emit("已连上服务器，等待分配位置…"))
	api.connection_failed.connect(func(): stop("连接失败：检查服务器地址、端口和组网是否在线。"))
	api.server_disconnected.connect(func(): stop("与服务器断开。"))
	api.peer_packet.connect(_on_packet)

# 地址可写 “主机”、“主机:端口”、“[IPv6]:端口”，或 ws:// / wss:// 开头的完整地址。
# 原生客户端默认走 ENet（UDP）；网页版浏览器不能收发 UDP，一律走 WebSocket。
func connect_to(address: String) -> void:
	disconnect_from()
	var target := parse_address(address, OS.has_feature("web"), page_is_secure())
	if target.has("error"):
		status_changed.emit(target.error)
		return
	var error: int
	if target.kind == "ws":
		var ws := WebSocketMultiplayerPeer.new()
		error = ws.create_client(target.url)
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
static func page_default_address() -> String:
	if not OS.has_feature("web"): return ""
	var server = JavaScriptBridge.eval("new URLSearchParams(location.search).get('server') || ''", true)
	if server is String and not server.is_empty(): return server
	var host = JavaScriptBridge.eval("location.host", true)
	if not host is String or host.is_empty(): return ""
	return ("wss://" if page_is_secure() else "ws://") + host + "/ws"

func disconnect_from() -> void:
	if peer != null:
		peer.close()
	api.multiplayer_peer = null
	peer = null
	connected = false
	role = -1
	in_match = false
	frames.clear()

func stop(reason: String) -> void:
	var was_in_match := in_match
	disconnect_from()
	status_changed.emit(reason)
	if was_in_match: match_stopped.emit(reason)

func active() -> bool:
	return peer != null

func send(message: Array, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE) -> void:
	if connected: api.send_bytes(var_to_bytes(message), 1, mode, 0)

func send_input(move: Vector2, jump: bool) -> void:
	send(["in", roundi(clampf(move.x, -1, 1) * 100), roundi(clampf(move.y, -1, 1) * 100), jump])

func send_command(name: String, arg := "") -> void:
	send(["cmd", name, arg])

# 每模拟一帧后调用；定期上报状态指纹，由服务器比对两端是否一致。
func report(frame: int, state_hash: int) -> void:
	if frame % HASH_INTERVAL == 0: send(["hash", frame, state_hash])

func _on_packet(_id: int, bytes: PackedByteArray) -> void:
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
		"desync":
			desynced = true
			status_changed.emit("两端画面不同步（第 %d 帧），请回到开始页重新联机。" % int(message[1]))
		"f":
			if in_match and int(message[1]) == next_frame + frames.size():
				frames.append({"a": Vector2(message[2], message[3]) / 100.0, "ja": bool(message[4]),
					"b": Vector2(message[5], message[6]) / 100.0, "jb": bool(message[7]), "cmds": message[8]})

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
