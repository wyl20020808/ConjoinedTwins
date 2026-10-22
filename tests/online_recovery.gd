extends SceneTree
# 真实本机 UDP 中继：停在 MAX_LEAD 的断流恢复、短按上行全丢、输入去重与版本拒绝。
const Relay = preload("res://scripts/net_relay.gd")
const Client = preload("res://scripts/net_client.gd")
class LossClient extends Client:
	var lose_down := false
	var lose_input := false
	var identity_override := ""
	var forge_hello := false
	func compatibility_fingerprint() -> String:
		return identity_override if not identity_override.is_empty() else super.compatibility_fingerprint()
	func _on_packet(id: int, bytes: PackedByteArray) -> void:
		if lose_down and not bytes.is_empty():
			if bytes[0] in [Relay.BUNDLE_TAG, Relay.FRAME_TAG]: return
			var message = bytes_to_var(bytes)
			if message is Array and not message.is_empty() and message[0] == "progress": return
		super._on_packet(id, bytes)
	func send(message: Array, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE) -> void:
		if forge_hello and message[0] == "hello": message = ["hello", Relay.PROTOCOL, "wrong-build"]
		super.send(message, mode)
	func send_raw(bytes: PackedByteArray, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE) -> void:
		if lose_input and not bytes.is_empty() and bytes[0] == Relay.INPUT_SEQ_TAG: return
		super.send_raw(bytes, mode)

var failures: Array = []
var relay
var clients: Array = []
var received := [{}, {}]
var last := [-1, -1]
var contiguous := true
var jump_edges := [0, 0]
var held := [false, false]
var equal := true
var next_input_msec := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func _initialize() -> void: call_deferred("validate")

func pump() -> void:
	# 与生产客户端一样刷新当前输入，避免把夹具长期不发输入误当成普通短按丢包。
	if Time.get_ticks_msec() >= next_input_msec:
		next_input_msec = Time.get_ticks_msec() + 16
		for c in clients: c.send_input(Vector2.ZERO, c.jump_was_down)
	for endpoint in range(clients.size()):
		var c = clients[endpoint]
		for frame in c.take_frames(1):
			var index: int = c.next_frame - 1
			contiguous = contiguous and index == last[endpoint] + 1
			last[endpoint] = index
			received[endpoint][index] = var_to_str(frame)
			if received[1-endpoint].has(index):
				equal = equal and received[endpoint][index] == received[1-endpoint][index]
				received[0].erase(index); received[1].erase(index)
			var down: bool = frame.ja if clients[0].role == 0 else frame.jb
			if down and not held[endpoint]: jump_edges[endpoint] += 1
			held[endpoint] = down
			c.acknowledge(c.next_frame)

func until(condition: Callable, seconds := 4.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		pump()
		if condition.call(): return true
		await process_frame
	return condition.call()

func wait_ms(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	await until(func(): return Time.get_ticks_msec() >= end, ms/1000.0 + 1.0)

func validate() -> void:
	relay = Relay.new(); relay.port = 24971; relay.ws_port = 24972; root.add_child(relay)
	var bad = LossClient.new(); bad.identity_override = "different-script-build"; root.add_child(bad)
	var statuses: Array = []
	bad.status_changed.connect(func(message): statuses.append(message))
	bad.connect_to("127.0.0.1:24971")
	check(await until(func(): return not statuses.is_empty() and statuses[-1].contains("版本不一致")), "不同脚本指纹在入房时拒绝")
	check(not bad.in_match and not relay.in_match, "拒绝的客户端不会启动对局")
	bad.queue_free(); await process_frame
	await until(func(): return relay.roles.is_empty())
	var liar = LossClient.new(); liar.forge_hello = true; root.add_child(liar)
	var rejected: Array = []
	liar.status_changed.connect(func(message): rejected.append(message))
	liar.connect_to("127.0.0.1:24971")
	check(await until(func(): return not rejected.is_empty() and rejected[-1].contains("版本不一致")), "中继独立拒绝伪造的客户端握手")
	check(not relay.in_match, "未经双向确认不会出帧")
	liar.queue_free(); await process_frame
	await until(func(): return relay.roles.is_empty())
	for i in range(2):
		var c = LossClient.new(); root.add_child(c); clients.append(c)
		c.connect_to("127.0.0.1:24971")
	check(await until(func(): return clients.all(func(c): return c.in_match)), "两个 UDP 客户端通过双向版本握手")
	if not clients.all(func(c): return c.in_match): cleanup(); return
	check(await until(func(): return last[0] >= 60 and last[1] >= 60), "中继正常持续出帧")
	# 整段下行（包括补发和进度）不可达，但 ENet 连接保持；不能靠收到未来帧才能恢复。
	clients[0].lose_down = true
	await wait_ms(2200)
	var stalled: int = relay.frame
	check(stalled - int(relay.acked[clients[0].role]) == Relay.MAX_LEAD, "断流使服务器停在慢端领先上限")
	clients[0].lose_down = false
	check(await until(func(): return clients[0].next_frame >= stalled + 30, 3.0), "网络恢复后无须新输入即可补齐并继续出帧")
	check(clients[0].resends > 0 and clients[0].resends < 20, "补发有超时触发并且请求限频")
	# 包含短按的所有上行包丢弃，只送达松开后的包。
	clients[0].lose_input = true
	clients[0].send_input(Vector2.ZERO, true)
	clients[0].lose_input = false
	for i in range(8): clients[0].send_input(Vector2.ZERO, false)
	check(await until(func(): return jump_edges == [1, 1]), "短按包丢失后两端各恢复一次跳跃")
	await wait_ms(250)
	check(jump_edges == [1, 1], "重复携带累计跳跃次数不会多跳")
	# 两次按下及中间松开均丢失，后续累计计数仍恢复两个独立边沿。
	clients[0].lose_input = true
	for down in [true, false, true]: clients[0].send_input(Vector2.ZERO, down)
	clients[0].lose_input = false
	clients[0].send_input(Vector2.ZERO, false)
	check(await until(func(): return jump_edges == [3, 3]), "多个丢失短按恢复为各自独立边沿")
	check(equal and contiguous, "断流与跳跃恢复期间两端输入帧逐帧相同且不跳不重")
	check(clients[0].diagnostics().missing_frames == 0, "恢复后诊断没有缺失帧")
	print("RECOVERY resends=", clients[0].resends, " frames=", last, " jump_edges=", jump_edges)
	cleanup()

func cleanup() -> void:
	for c in clients: c.disconnect_from(); c.queue_free()
	relay.queue_free()
	await process_frame
	print("ONLINE RECOVERY failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
