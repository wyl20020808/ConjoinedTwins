extends Node
# 联机中转服务器：不运行游戏逻辑，只按固定 60 帧/秒把两人的输入和操作命令打包广播。
# 两台客户端按同一种子、同一帧序列各自模拟，因此画面与判定完全一致（帧同步）。
# 同时监听两种传输：ENet（UDP，原生客户端）和 WebSocket（TCP，网页版客户端），两种连接进同一个房间。

# 7：输入与逐帧广播改为紧凑二进制（见 encode_frame / encode_input），输入只在变化时上传。
const PROTOCOL := 7
const DEFAULT_PORT := 24680
const DEFAULT_WS_PORT := 24681
const TICK := 1.0 / 60.0
const ENET := 0
const WEBSOCKET := 1
# 高频消息用首字节标记的定长二进制；var_to_bytes 编码的数组首字节是类型号 28，不会与之混淆。
const INPUT_TAG := 0xC1
const FRAME_TAG := 0xF1
# UDP（ENet）玩家：每帧发一个“帧包”，内含最近 REDUNDANCY 帧，按不可靠有序方式发送——
# 丢一两个包时下一个包就补上，不必像 TCP 那样等重传、让后面的帧全部排队。
# 客户端发现缺帧过久时发 resend，服务器从最近 HISTORY 帧里可靠补发，保证两端帧序列完整一致。
const BUNDLE_TAG := 0xF2
const REDUNDANCY := 8
const HISTORY := 600
# UDP 玩家的输入每帧都发（不可靠），带 16 位序号，服务器只采用比上次更新的输入，旧包不会覆盖新输入。
const INPUT_SEQ_TAG := 0xC2

var links: Array = []    # [{"api": SceneMultiplayer, "peer": MultiplayerPeer, "name": String}]，下标即传输类型
var roles := {}          # Vector2i(传输类型, peer_id) -> 0 / 1；两种传输各自分配 peer_id，可能重复
var inputs := [[0, 0, false], [0, 0, false]]
var jump_latch := [false, false]
var commands: Array = []
var frame := 0
var in_match := false
var hashes := {}         # frame -> [hash0, hash1]
var clock := 0.0
var history := {}        # 帧号 -> 编码后的帧，供 UDP 冗余与补发
var input_seq := [-1, -1]
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
	send_raw(key, var_to_bytes(message), mode)

func send_raw(key: Vector2i, bytes: PackedByteArray, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE) -> void:
	if not links[key.x].api.get_peers().has(key.y):return
	if links[key.x].peer is WebSocketMultiplayerPeer and links[key.x].peer.get_peer(key.y).get_ready_state()!=WebSocketPeer.STATE_OPEN:return
	links[key.x].api.send_bytes(bytes, key.y, mode, 0)

# 一帧双人输入：标记 1 + 帧号 4 + 四个轴各 1（-100..100）+ 跳跃位 1 = 11 字节；
# 本帧有操作命令时才在末尾追加 var_to_bytes(命令数组)。旧格式每帧约 100 字节。
static func encode_frame(index: int, a: Array, b: Array, ja: bool, jb: bool, cmds: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(11)
	bytes[0] = FRAME_TAG
	bytes.encode_u32(1, index)
	bytes.encode_s8(5, a[0])
	bytes.encode_s8(6, a[1])
	bytes.encode_s8(7, b[0])
	bytes.encode_s8(8, b[1])
	bytes[9] = int(ja) | (int(jb) << 1)
	bytes[10] = 1 if not cmds.is_empty() else 0
	if not cmds.is_empty(): bytes.append_array(var_to_bytes(cmds))
	return bytes

static func decode_frame(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 11 or bytes[0] != FRAME_TAG: return {}
	var cmds: Array = []
	if bytes[10] == 1:
		var decoded = bytes_to_var(bytes.slice(11))
		if decoded is Array: cmds = decoded
	return {"index": bytes.decode_u32(1), "a": Vector2(bytes.decode_s8(5), bytes.decode_s8(6)) / 100.0,
		"ja": bytes[9] & 1 != 0, "b": Vector2(bytes.decode_s8(7), bytes.decode_s8(8)) / 100.0, "jb": bytes[9] & 2 != 0, "cmds": cmds}

# 帧包：标记 1 + 帧数 1，之后每帧为 长度 2 + 帧内容（encode_frame 的结果），从旧到新排列。
static func encode_bundle(packets: Array) -> PackedByteArray:
	var bytes := PackedByteArray([BUNDLE_TAG, packets.size()])
	for packet: PackedByteArray in packets:
		var length := PackedByteArray([0, 0])
		length.encode_u16(0, packet.size())
		bytes.append_array(length)
		bytes.append_array(packet)
	return bytes

static func decode_bundle(bytes: PackedByteArray) -> Array:
	var result: Array = []
	if bytes.size() < 2 or bytes[0] != BUNDLE_TAG: return result
	var cursor := 2
	for n in range(bytes[1]):
		if cursor + 2 > bytes.size(): break
		var length := bytes.decode_u16(cursor)
		cursor += 2
		if cursor + length > bytes.size(): break
		result.append(decode_frame(bytes.slice(cursor, cursor + length)))
		cursor += length
	return result

# 带序号的输入：标记 1 + 序号 2 + 两个轴各 1 + 跳跃 1 = 6 字节。
static func encode_input_seq(seq: int, x: int, y: int, jump: bool) -> PackedByteArray:
	var bytes := PackedByteArray([INPUT_SEQ_TAG, 0, 0, 0, 0, int(jump)])
	bytes.encode_u16(1, seq & 0xFFFF)
	bytes.encode_s8(3, clampi(x, -100, 100))
	bytes.encode_s8(4, clampi(y, -100, 100))
	return bytes

# 16 位序号回绕比较：value 是否比 last 新。
static func seq_newer(value: int, last: int) -> bool:
	if last < 0: return true
	var delta := (value - last) & 0xFFFF
	return delta > 0 and delta < 0x8000

# 输入：标记 1 + 两个轴各 1 + 跳跃 1 = 4 字节。
static func encode_input(x: int, y: int, jump: bool) -> PackedByteArray:
	var bytes := PackedByteArray([INPUT_TAG, 0, 0, int(jump)])
	bytes.encode_s8(1, clampi(x, -100, 100))
	bytes.encode_s8(2, clampi(y, -100, 100))
	return bytes

func _on_connected(key: Vector2i) -> void:
	var free := [0, 1].filter(func(r): return not roles.values().has(r))
	if free.is_empty():
		send(key, ["full"])
		log_line("第三人（%s %d）被拒绝：房间已满。" % [links[key.x].name, key.y])
		# 稍后再断开，让“房间已满”先送到对方，否则对方只会看到“连接失败”。
		get_tree().create_timer(0.5).timeout.connect(func():
			if links[key.x].api.get_peers().has(key.y): links[key.x].peer.disconnect_peer(key.y))
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
	history.clear()
	input_seq = [-1, -1]
	in_match = true
	var seed := randi() & 0x7fffffff
	for key in roles: send(key, ["match", seed])
	log_line("两人到齐，开始对局，种子 %d。" % seed)

func _on_packet(key: Vector2i, bytes: PackedByteArray) -> void:
	if not roles.has(key): return
	var role: int = roles[key]
	if bytes.size() == 4 and bytes[0] == INPUT_TAG:
		var jump := bytes[3] != 0
		inputs[role] = [bytes.decode_s8(1), bytes.decode_s8(2), jump]
		if jump: jump_latch[role] = true
		return
	if bytes.size() == 6 and bytes[0] == INPUT_SEQ_TAG:
		var seq := bytes.decode_u16(1)
		if not seq_newer(seq, input_seq[role]): return
		input_seq[role] = seq
		var pressed := bytes[5] != 0
		inputs[role] = [bytes.decode_s8(3), bytes.decode_s8(4), pressed]
		if pressed: jump_latch[role] = true
		return
	var message = bytes_to_var(bytes)
	if not message is Array or message.is_empty(): return
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
		"resend":
			if message.size() >= 2: resend(key, int(message[1]))
		"ping":
			# 原样回给发送者，客户端据此测往返延迟；不进入对局帧，不影响同步。
			if message.size() >= 2: send(key, ["pong", message[1]])
		"stat":
			# 客户端每 10 秒上报一次网络质量，记在主机的中继日志里，不用让对方截图就能看出卡在哪。
			if message.size() >= 6:
				log_line("玩家 %02d 网络：延迟 %d ms，抖动 %d ms，缓冲 %d 帧，近 10 秒卡顿 %d 次，帧率 %d" % [role + 1, int(message[1]), int(message[2]), int(message[3]), int(message[4]), int(message[5])])

# 可靠补发：从客户端缺的那一帧起，按每包 40 帧发到当前帧。
func resend(key: Vector2i, from: int) -> void:
	var batch: Array = []
	for index in range(maxi(from, frame - HISTORY), frame):
		if not history.has(index): continue
		batch.append(history[index])
		if batch.size() == 40:
			send_raw(key, encode_bundle(batch))
			batch = []
	if not batch.is_empty(): send_raw(key, encode_bundle(batch))

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
		var packet := encode_frame(frame, a, b, a[2] or jump_latch[0], b[2] or jump_latch[1], commands)
		jump_latch = [false, false]
		commands.clear()
		history[frame] = packet
		history.erase(frame - HISTORY)
		var recent: Array = []
		for index in range(maxi(0, frame - REDUNDANCY + 1), frame + 1): recent.append(history[index])
		var bundle := encode_bundle(recent)
		for key in roles:
			if key.x == ENET: send_raw(key, bundle, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
			else: send_raw(key, packet)
		frame += 1
