extends Node
# 联机中转服务器：不运行游戏逻辑，只按固定 60 帧/秒把两人的输入和操作命令打包广播。
# 两台客户端按同一种子、同一帧序列各自模拟，因此画面与判定完全一致（帧同步）。
# 同时监听两种传输：ENet（UDP，原生客户端）和 WebSocket（TCP，网页版客户端），两种连接进同一个房间。

const PROTOCOL := 3
const DEFAULT_PORT := 24680
const DEFAULT_WS_PORT := 24681
const TICK := 1.0 / 60.0
const ENET := 0
const WEBSOCKET := 1

var links: Array = []    # [{"api": SceneMultiplayer, "peer": MultiplayerPeer, "name": String}]，下标即传输类型
var roles := {}          # Vector2i(传输类型, peer_id) -> 0 / 1；两种传输各自分配 peer_id，可能重复
var inputs := [[0, 0, false], [0, 0, false]]
var jump_latch := [false, false]
var commands: Array = []
var frame := 0
var in_match := false
var hashes := {}         # frame -> [hash0, hash1]
var clock := 0.0
var port := DEFAULT_PORT
var ws_port := DEFAULT_WS_PORT   # 0 表示不开 WebSocket

func _ready() -> void:
	Engine.max_fps = 120
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="): port = int(arg.get_slice("=", 1))
		if arg.begins_with("--ws-port="): ws_port = int(arg.get_slice("=", 1))
	var enet := ENetMultiplayerPeer.new()
	var error := enet.create_server(port, 4)
	if error != OK:
		log_line("无法监听 UDP 端口 %d（错误 %d），可能已被占用。" % [port, error])
		get_tree().quit(1)
		return
	add_link(enet, "UDP")
	# ENet 交给场景树轮询；WebSocket 在 _process 里手动轮询。
	get_tree().set_multiplayer(links[ENET].api, get_path())
	if ws_port > 0:
		var ws := WebSocketMultiplayerPeer.new()
		error = ws.create_server(ws_port)
		if error != OK:
			log_line("无法监听 WebSocket 端口 %d（错误 %d），可能已被占用。" % [ws_port, error])
			get_tree().quit(1)
			return
		add_link(ws, "WebSocket")
		log_line("联机服务器已启动，UDP 端口 %d，WebSocket 端口 %d。关闭此窗口即停止。" % [port, ws_port])
	else:
		log_line("联机服务器已启动，UDP 端口 %d。关闭此窗口即停止。" % port)

func add_link(peer: MultiplayerPeer, label: String) -> void:
	var kind := links.size()
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	api.server_relay = false
	api.root_path = get_path()  # 手动轮询的 SceneMultiplayer 也必须有根路径，否则丢包
	api.peer_connected.connect(func(id): _on_connected(Vector2i(kind, id)))
	api.peer_disconnected.connect(func(id): _on_disconnected(Vector2i(kind, id)))
	api.peer_packet.connect(func(id, bytes): _on_packet(Vector2i(kind, id), bytes))
	links.append({"api": api, "peer": peer, "name": label})

func _process(_delta: float) -> void:
	for kind in range(1, links.size()): links[kind].api.poll()

func _exit_tree() -> void:
	for link in links: link.peer.close()

func log_line(text: String) -> void:
	print("[%s] %s" % [Time.get_time_string_from_system(), text])

func send(key: Vector2i, message: Array, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE) -> void:
	if not links[key.x].api.get_peers().has(key.y):return
	if links[key.x].peer is WebSocketMultiplayerPeer and links[key.x].peer.get_peer(key.y).get_ready_state()!=WebSocketPeer.STATE_OPEN:return
	links[key.x].api.send_bytes(var_to_bytes(message), key.y, mode, 0)

func _on_connected(key: Vector2i) -> void:
	var free := [0, 1].filter(func(r): return not roles.values().has(r))
	if free.is_empty():
		send(key, ["full"])
		log_line("第三人（%s %d）被拒绝：房间已满。" % [links[key.x].name, key.y])
		links[key.x].peer.disconnect_peer.call_deferred(key.y)
		return
	roles[key] = free[0]
	log_line("玩家 %02d 已连接（%s %d）。" % [free[0] + 1, links[key.x].name, key.y])
	send(key, ["welcome", free[0], PROTOCOL])
	broadcast_lobby()
	if roles.size() == 2: start_match()

func _on_disconnected(key: Vector2i) -> void:
	if not roles.has(key): return
	log_line("玩家 %02d 已断开。" % (roles[key] + 1))
	roles.erase(key)
	if in_match:
		in_match = false
		for other in roles: send(other, ["peer_left"])
	broadcast_lobby()

func broadcast_lobby() -> void:
	for key in roles: send(key, ["lobby", roles.size()])

func start_match() -> void:
	frame = 0
	clock = 0.0
	commands.clear()
	hashes.clear()
	inputs = [[0, 0, false], [0, 0, false]]
	jump_latch = [false, false]
	in_match = true
	var seed := randi() & 0x7fffffff
	for key in roles: send(key, ["match", seed])
	log_line("两人到齐，开始对局，种子 %d。" % seed)

func _on_packet(key: Vector2i, bytes: PackedByteArray) -> void:
	if not roles.has(key): return
	var message = bytes_to_var(bytes)
	if not message is Array or message.is_empty(): return
	var role: int = roles[key]
	match message[0]:
		"in":
			if message.size() < 4: return
			inputs[role] = [clampi(int(message[1]), -100, 100), clampi(int(message[2]), -100, 100), bool(message[3])]
			if message[3]: jump_latch[role] = true
		"cmd":
			if in_match and message.size() >= 3:
				commands.append([role, str(message[1]), str(message[2])])
		"hash":
			if message.size() >= 3: check_hash(role, int(message[1]), int(message[2]))

func check_hash(role: int, at: int, value: int) -> void:
	if hashes.size() > 64: hashes.clear()
	var pair: Array = hashes.get(at, [null, null])
	pair[role] = value
	hashes[at] = pair
	if pair[0] == null or pair[1] == null: return
	hashes.erase(at)
	if pair[0] != pair[1]:
		log_line("第 %d 帧两端状态不一致。" % at)
		for key in roles: send(key, ["desync", at])

func _physics_process(delta: float) -> void:
	if not in_match: return
	clock += delta
	# 物理帧本身固定 60 帧/秒；累加只为在卡顿后补齐，不多发也不少发。
	while clock >= TICK - 0.0001:
		clock -= TICK
		var a: Array = inputs[0]
		var b: Array = inputs[1]
		var packet := ["f", frame, a[0], a[1], a[2] or jump_latch[0], b[0], b[1], b[2] or jump_latch[1], commands.duplicate()]
		jump_latch = [false, false]
		commands.clear()
		for key in roles: send(key, packet)
		frame += 1
