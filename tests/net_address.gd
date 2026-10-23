extends SceneTree
# 联机地址解析与 WebSocket 路径检查：原生默认 ENet、网页一律 WebSocket、https 网页只允许 wss；
# 另起一个中继，确认带 /ws 路径的 WebSocket 地址（反向代理转发时的形式）也能连上并分配角色。

const NetClient = preload("res://scripts/net_client.gd")
const Relay = preload("res://scripts/net_relay.gd")
const PORT := 24791
var checks: Array = []

func _initialize() -> void:
	call_deferred("verify")

func check(label: String, passed: bool) -> void:
	checks.append({"name": label, "passed": passed})
	print("PASS " if passed else "FAIL ", label)

func expect(address: String, web: bool, secure: bool, want: Dictionary) -> void:
	var got := NetClient.parse_address(address, web, secure)
	var passed := true
	for key in want: passed = passed and got.get(key) == want[key]
	check("%s（web=%s https=%s）解析为 %s" % [address, web, secure, want], passed)
	if not passed: print("  实际：", got)

func verify() -> void:
	expect("100.64.0.1", false, false, {"kind": "enet", "host": "100.64.0.1", "port": Relay.DEFAULT_PORT})
	expect(" frp.example.com:31000 ", false, false, {"kind": "enet", "host": "frp.example.com", "port": 31000})
	expect("[::1]:25000", false, false, {"kind": "enet", "host": "::1", "port": 25000})
	expect("::1", false, false, {"kind": "enet", "host": "::1", "port": Relay.DEFAULT_PORT})
	expect("ws://127.0.0.1:24681", false, false, {"kind": "ws", "url": "ws://127.0.0.1:24681"})
	expect("wss://abc.nyat.app:10086/ws", true, true, {"kind": "ws", "url": "wss://abc.nyat.app:10086/ws"})
	expect("192.168.1.5", true, false, {"kind": "ws", "url": "ws://192.168.1.5:%d" % Relay.DEFAULT_WS_PORT})
	expect("abc.nyat.app:10086", true, true, {"kind": "ws", "url": "wss://abc.nyat.app:10086"})
	expect("abc.nyat.app", true, true, {"kind": "ws", "url": "wss://abc.nyat.app"})
	check("https 网页拒绝 ws:// 地址", NetClient.parse_address("ws://1.2.3.4:24681", true, true).has("error"))
	check("空地址报错", NetClient.parse_address("  ", false, false).has("error"))
	check("非数字端口报错", NetClient.parse_address("host:abc", false, false).has("error"))
	check("越界端口报错", NetClient.parse_address("host:70000", false, false).has("error"))
	check("不支持的协议报错", NetClient.parse_address("http://host:1", false, false).has("error"))
	check("原生客户端没有网页默认地址", NetClient.page_default_address() == "")
	check("旧默认端口迁移到当前默认入口", NetClient.migrate_address("wss://www.u4139693.nyat.app:57412/ws") == NetClient.preferred_default())
	check("旧默认端口仍参与自动回退", NetClient.is_default("wss://www.u4139693.nyat.app:57412/ws"))
	check("自定义端口不被迁移", NetClient.migrate_address("wss://www.u4139693.nyat.app:12345/ws") == "wss://www.u4139693.nyat.app:12345/ws")
	var had_address := FileAccess.file_exists(NetClient.ADDRESS_FILE)
	var original_address := FileAccess.get_file_as_bytes(NetClient.ADDRESS_FILE) if had_address else PackedByteArray()
	var saved := ConfigFile.new()
	saved.set_value("online", "address", "wss://www.u4139693.nyat.app:57412/ws")
	saved.save(NetClient.ADDRESS_FILE)
	check("旧配置文件不会覆盖当前默认入口", NetClient.default_address() == NetClient.preferred_default())
	if had_address:
		var restore := FileAccess.open(NetClient.ADDRESS_FILE, FileAccess.WRITE)
		restore.store_buffer(original_address)
		restore.close()
	else:
		DirAccess.remove_absolute(NetClient.ADDRESS_FILE)

	var relay = Relay.new()
	relay.port = PORT
	relay.ws_port = PORT + 1
	root.add_child(relay)
	var client = NetClient.new()
	root.add_child(client)
	client.connect_to("ws://127.0.0.1:%d/ws" % (PORT + 1))
	var deadline := Time.get_ticks_msec() + 5000
	while client.role < 0 and Time.get_ticks_msec() < deadline: await process_frame
	check("带 /ws 路径的 WebSocket 地址连上中继并分配为 01", client.role == 0)
	client.disconnect_from()
	client.queue_free()
	await process_frame
	client = NetClient.new()
	root.add_child(client)
	# 接受 TCP 但不回应 WebSocket 握手，模拟隧道无响应，验证实际握手期限。
	var silent := TCPServer.new()
	check("无响应 WebSocket 测试端口可监听", silent.listen(PORT + 2, "127.0.0.1") == OK)
	var terminal := []
	client.status_changed.connect(func(message):
		if message.begins_with("连接失败"): terminal.append(message))
	client.connect_to("ws://127.0.0.1:%d/ws" % (PORT + 2))
	# 引擎默认三秒握手期限更短；本夹具延长它，以单独验证客户端的六秒门槛。
	client.peer.handshake_timeout = 30.0
	var held: Array[StreamPeerTCP] = []
	var handshake_started := Time.get_ticks_msec()
	deadline = Time.get_ticks_msec() + NetClient.CONNECT_TIMEOUT_MSEC + 1500
	while terminal.is_empty() and Time.get_ticks_msec() < deadline:
		if silent.is_connection_available(): held.append(silent.take_connection())
		await process_frame
	check("无响应握手确实等待到超时期限", Time.get_ticks_msec() - handshake_started >= NetClient.CONNECT_TIMEOUT_MSEC)
	check("WebSocket 超时返回可重试状态", client.peer == null and not terminal.is_empty())
	silent.stop()
	client.queue_free()
	relay.queue_free()
	await process_frame
	var failed := checks.filter(func(c): return not c.passed).size()
	print("RESULT %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
