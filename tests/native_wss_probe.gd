extends SceneTree
# 桌面版经公网 wss 连接联机中继的探测：连上并分到玩家编号即通过（只读，连上后立即断开）。
# 用法：Godot --headless --path . --script res://tests/native_wss_probe.gd [-- --server=地址]
const NetClient = preload("res://scripts/net_client.gd")
func _initialize() -> void: call_deferred("probe")
func probe() -> void:
	var net = NetClient.new()
	root.add_child(net)
	var lines: Array = []
	net.status_changed.connect(func(text): lines.append(text); print("STATUS ", text))
	var address: String = NetClient.default_address()
	print("ADDRESS ", address)
	# -- --auto：按开始页“连接队友”的方式连接（默认地址时 UDP → wss 自动回退）。
	if "--auto" in OS.get_cmdline_user_args(): net.connect_auto(address)
	else: net.connect_to(address)
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and net.role < 0: await process_frame
	var ok: bool = net.role >= 0
	print("NATIVE_WSS ", "PASS" if ok else "FAIL", " role=", net.role)
	net.disconnect_from()
	await process_frame
	quit(0 if ok else 1)
