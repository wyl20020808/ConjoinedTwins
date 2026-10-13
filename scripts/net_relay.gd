extends Node
# 联机中转服务器：不运行游戏逻辑，只按固定 60 帧/秒把两人的输入和操作命令打包广播。
# 两台客户端按同一种子、同一帧序列各自模拟，因此画面与判定完全一致（帧同步）。

const PROTOCOL := 1
const DEFAULT_PORT := 24680
const TICK := 1.0 / 60.0

var peer := ENetMultiplayerPeer.new()
var api := SceneMultiplayer.new()
var roles := {}          # peer_id -> 0 / 1
var inputs := [[0, 0, false], [0, 0, false]]
var jump_latch := [false, false]
var commands: Array = []
var frame := 0
var in_match := false
var hashes := {}         # frame -> [hash0, hash1]
var clock := 0.0
var port := DEFAULT_PORT

func _ready() -> void:
	Engine.max_fps = 120
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="): port = int(arg.get_slice("=", 1))
	var error := peer.create_server(port, 4)
	if error != OK:
		log_line("无法监听 UDP 端口 %d（错误 %d），可能已被占用。" % [port, error])
		get_tree().quit(1)
		return
	api.multiplayer_peer = peer
	api.server_relay = false
	get_tree().set_multiplayer(api, get_path())
	api.peer_connected.connect(_on_connected)
	api.peer_disconnected.connect(_on_disconnected)
	api.peer_packet.connect(_on_packet)
	log_line("联机服务器已启动，UDP 端口 %d。关闭此窗口即停止。" % port)

func log_line(text: String) -> void:
	print("[%s] %s" % [Time.get_time_string_from_system(), text])

func send(id: int, message: Array, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE) -> void:
	api.send_bytes(var_to_bytes(message), id, mode, 0)

func _on_connected(id: int) -> void:
	var free := [0, 1].filter(func(r): return not roles.values().has(r))
	if free.is_empty():
		send(id, ["full"])
		log_line("第三人 %d 被拒绝：房间已满。" % id)
		peer.disconnect_peer.call_deferred(id)
		return
	roles[id] = free[0]
	log_line("玩家 %02d 已连接（%d）。" % [free[0] + 1, id])
	send(id, ["welcome", free[0], PROTOCOL])
	broadcast_lobby()
	if roles.size() == 2: start_match()

func _on_disconnected(id: int) -> void:
	if not roles.has(id): return
	log_line("玩家 %02d 已断开。" % (roles[id] + 1))
	roles.erase(id)
	if in_match:
		in_match = false
		for other in roles: send(other, ["peer_left"])
	broadcast_lobby()

func broadcast_lobby() -> void:
	for id in roles: send(id, ["lobby", roles.size()])

func start_match() -> void:
	frame = 0
	clock = 0.0
	commands.clear()
	hashes.clear()
	inputs = [[0, 0, false], [0, 0, false]]
	jump_latch = [false, false]
	in_match = true
	var seed := randi() & 0x7fffffff
	for id in roles: send(id, ["match", seed])
	log_line("两人到齐，开始对局，种子 %d。" % seed)

func _on_packet(id: int, bytes: PackedByteArray) -> void:
	if not roles.has(id): return
	var message = bytes_to_var(bytes)
	if not message is Array or message.is_empty(): return
	var role: int = roles[id]
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
		for id in roles: send(id, ["desync", at])

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
		for id in roles: send(id, packet)
		frame += 1
