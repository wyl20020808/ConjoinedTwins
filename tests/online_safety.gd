extends SceneTree
# 不等待真实网络时钟，验证超时边界、控制恢复和不同步终止语义。
const Relay = preload("res://scripts/net_relay.gd")
const Client = preload("res://scripts/net_client.gd")
class RecordingRelay extends Relay:
	var sent: Array = []
	func send_raw(key: Vector2i, bytes: PackedByteArray, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE) -> void:
		sent.append([key, bytes, mode])
class RecordingClient extends Client:
	var sent: Array = []
	func send_raw(bytes: PackedByteArray, _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE) -> void:
		sent.append(bytes_to_var(bytes))
var failures := 0
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _initialize() -> void:
	var relay = RecordingRelay.new()
	var udp := Vector2i(Relay.ENET, 123)
	var ws := Vector2i(Relay.WEBSOCKET, 456)
	relay.roles = {udp: 0, ws: 1}; relay.verified = {udp: true, ws: true}
	relay.in_match = true
	relay.inputs = [[100, 0, true], [0, 100, true]]
	relay.last_input_msec = [1000, 1000]
	relay.pending_jumps[0] = 2; relay.jump_latch[0] = true; relay.jump_output[0] = true
	relay.commands = [[0, "combat", "1,1,0,0"], [1, "pause", ""]]
	relay.expire_inputs(1499)
	check(not relay.input_stale[0] and relay.inputs[0][0] == 100, "UDP 宽限期内保持合法长按")
	relay.expire_inputs(1500)
	check(relay.input_stale[0] and relay.inputs[0] == [0, 0, false] and not relay.next_jump(0), "500 ms 后释放移动、跳跃与待重放边沿")
	check(relay.commands == [[1, "pause", ""], [0, "combat", "0,0,0,0"]], "射击释放进入共同帧且不改队友命令")
	relay.expire_inputs(1600)
	check(relay.commands.size() == 2 and not relay.input_stale[1], "重复巡检不重复释放，WS 一秒保活不会被误判")
	relay._on_packet(udp, var_to_bytes(["cmd", "combat", "1,0,0,0"]))
	check(relay.commands.size() == 2, "失联期间迟到的射击命令不能重新按住")
	relay.jump_seq[0] = 1
	relay._on_packet(udp, Relay.encode_input_seq(0, -100, 0, false, 5))
	check(not relay.input_stale[0] and relay.inputs[0][0] == -100 and not relay.next_jump(0), "恢复采用最新方向，不重放过期的短按")
	relay._on_packet(udp, Relay.encode_input_seq(1, 0, 0, true, 6))
	check(relay.next_jump(0), "恢复后的新跳跃仍有效")
	relay.last_input_msec[0] = Time.get_ticks_msec() - Relay.INPUT_TIMEOUT_MSEC
	relay._on_packet(udp, Relay.encode_input_seq(0, 100, 0, true, 5))
	relay.expire_inputs(Time.get_ticks_msec())
	check(relay.input_stale[0], "迟到旧序号不能续期并绕过超时保护")
	relay.last_input_msec[0] = 100000
	relay.expire_inputs(2500)
	check(relay.input_stale[1] and relay.inputs[1] == [0, 0, false], "WS 超过 1500 ms 同样释放输入")
	relay._on_packet(ws, Relay.encode_input(0, 100, true))
	check(not relay.input_stale[1] and relay.next_jump(1), "WS 恢复保活后长按正常")
	# MAX_LEAD 暂停时仍应安排中和帧，恢复广播会带上它。
	relay.frame = Relay.MAX_LEAD; relay.acked = [0, 0]
	relay.last_input_msec = [-10000, -10000]; relay.input_stale = [false, false]
	relay.broadcast_due_frames()
	check(relay.frame == Relay.MAX_LEAD and relay.input_stale == [true, true], "慢端上限暂停出帧时仍执行超时保护")
	relay.check_hash(0, 60, 11); relay.check_hash(1, 60, 12)
	var emitted: int = relay.sent.size()
	relay.acked = [Relay.MAX_LEAD, Relay.MAX_LEAD]
	relay.broadcast_due_frames(); relay.resend(udp, 0)
	relay._on_packet(udp, var_to_bytes(["cmd", "retry", ""]))
	check(relay.desynced and relay.frame == Relay.MAX_LEAD and relay.sent.size() == emitted and relay.commands.is_empty(), "不同步后不再出帧、补帧或接受操作")
	relay.start_match()
	check(not relay.desynced and relay.frame == 0 and relay.input_stale == [false, false], "新对局重置终止状态和输入租期")
	relay.free()
	var client = RecordingClient.new(); client.connected = true; client.in_match = true
	client.send_combat(true, true, true, true)
	client.send_combat(true, false, false, false)
	check(client.sent.size() == 1, "持续射击保活限频")
	client.last_combat_msec -= Client.COMBAT_REFRESH_MSEC
	client.send_combat(true, false, false, false)
	check(client.sent.size() == 2 and client.sent[-1] == ["cmd", "combat", "1,0,0,0"], "保活只重发持续射击，不重发换弹、丢枪和切枪")
	client.send_combat(false, false, false, false)
	check(client.sent[-1] == ["cmd", "combat", "0,0,0,0"], "松开射击立即发送")
	var stopped: Array = []; client.match_stopped.connect(func(reason): stopped.append(reason))
	client.frames = [{"a": Vector2.ZERO}]; client.next_frame = 5; client.resend_wanted = true
	client._on_packet(1, var_to_bytes(["desync", 0]))
	client._on_packet(1, var_to_bytes(["desync", 0]))
	client.receive_bundle([{"index": 5}])
	var before: int = client.sent.size()
	client.send_input(Vector2.ONE, true); client.send_command("retry"); client.send_combat(true, false, false, false)
	check(client.desynced and client.frames.is_empty() and client.take_frames().is_empty() and client.next_frame == 5, "不同步后丢弃缓存与迟到帧，不再消费模拟帧")
	check(stopped.size() == 1 and not client.resend_wanted and client.sent.size() == before, "只通知停局一次并停止上传操作和补帧")
	client.free()
	print("ONLINE SAFETY failures=", failures)
	quit(0 if failures == 0 else 1)
