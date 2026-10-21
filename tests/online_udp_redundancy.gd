extends SceneTree
# UDP 冗余帧：服务器每包带最近 8 帧，模拟 20% 随机丢包、偶尔连丢 15 包（约 250 毫秒）。
# 核对：客户端按原顺序拿到全部帧、不跳不重；短丢包靠冗余补齐不需补发；长断流触发补发后补齐。
# 另核对带序号输入：旧包不会覆盖新输入，序号回绕仍判断正确。
# 用法：Godot --headless --path . --script res://tests/online_udp_redundancy.gd
const Relay = preload("res://scripts/net_relay.gd")
const NetClient = preload("res://scripts/net_client.gd")
var failures: Array = []

func check(ok: bool, name: String) -> void:
	print("PASS " if ok else "FAIL ", name)
	if not ok: failures.append(name)

func _initialize() -> void:
	call_deferred("validate")

func validate() -> void:
	var history := {}
	var client = NetClient.new()
	client.in_match = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var outage := 0
	var resend_requests := 0
	var consumed: Array = []
	for frame in range(3600):
		history[frame] = Relay.encode_frame(frame, [frame % 100, 0, false], [0, -(frame % 100), false], frame % 7 == 0, false, [[0, "combat", "1,0,0,0"]] if frame % 50 == 0 else [])
		var recent: Array = []
		for index in range(maxi(0, frame - Relay.REDUNDANCY + 1), frame + 1): recent.append(history[index])
		if outage == 0 and rng.randf() < 0.01: outage = 15
		var dropped := outage > 0 or rng.randf() < 0.2
		if outage > 0: outage -= 1
		if not dropped: client.receive_bundle(Relay.decode_bundle(Relay.encode_bundle(recent)))
		# 客户端提出补发时，服务器从缺的那一帧可靠补到当前帧（与 net_relay.gd resend 相同的分批方式）。
		if client.resend_wanted:
			client.resend_wanted = false
			resend_requests += 1
			var batch: Array = []
			for index in range(client.next_frame + client.frames.size(), frame + 1):
				batch.append(history[index])
				if batch.size() == 40:
					client.receive_bundle(Relay.decode_bundle(Relay.encode_bundle(batch)))
					batch = []
			if not batch.is_empty(): client.receive_bundle(Relay.decode_bundle(Relay.encode_bundle(batch)))
		for taken in client.take_frames(): consumed.append(taken)
	for taken in client.take_frames(): consumed.append(taken)
	var ordered := true
	for i in range(consumed.size()):
		var expect := Vector2(i % 100, 0) / 100.0
		if consumed[i].a != expect or consumed[i].ja != (i % 7 == 0) or (i % 50 == 0) != (consumed[i].cmds.size() == 1):
			ordered = false
			break
	print("UDP frames=", consumed.size() + client.frames.size(), " resend_requests=", resend_requests)
	check(ordered and consumed.size() + client.frames.size() >= 3590, "20% 丢包加偶发长断流下帧按原顺序完整到达，命令不丢")
	check(resend_requests > 0 and resend_requests < 60, "只有长断流才请求补发，短丢包靠冗余补齐")
	client.free()
	check(Relay.seq_newer(5, 4) and not Relay.seq_newer(4, 5) and Relay.seq_newer(2, 65530) and not Relay.seq_newer(65530, 2) and Relay.seq_newer(0, -1), "输入序号回绕比较正确")
	var input := Relay.encode_input_seq(65535, -100, 37, true)
	check(input.size() == 6 and input.decode_u16(1) == 65535 and input.decode_s8(3) == -100 and input.decode_s8(4) == 37 and input[5] == 1, "带序号输入编码 6 字节")
	print("ONLINE UDP failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
