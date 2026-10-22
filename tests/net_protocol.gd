extends SceneTree
const Relay = preload("res://scripts/net_relay.gd")
const Client = preload("res://scripts/net_client.gd")
const Identity = preload("res://scripts/net_identity.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	print("PASS " if ok else "FAIL ", text)
	if not ok: failures += 1
func _initialize() -> void:
	check(Identity.fingerprint().begins_with(Identity.Manifest.FINGERPRINT+":"), "源码运行和打包清单指纹一致")
	var old = Client.new()
	var rejected := []
	old.status_changed.connect(func(text): rejected.append(text))
	old._on_packet(1, var_to_bytes(["welcome", 0, 7]))
	check(not rejected.is_empty() and rejected[-1].contains("版本不一致") and not old.in_match, "旧协议中继在开始前拒绝")
	old.free()
	var relay = Relay.new()
	var key := Vector2i(Relay.ENET, 123)
	relay.roles[key] = 0
	relay.verified[key] = true
	relay._on_packet(key, Relay.encode_input_seq(0, 0, 0, true, 1))
	check(relay.next_jump(0) and relay.next_jump(0), "长按保持按下状态，不因恢复机制反复跳跃")
	relay._on_packet(key, Relay.encode_input_seq(2, 0, 0, false, 1))
	check(not relay.next_jump(0), "松开后输出松开状态")
	relay._on_packet(key, Relay.encode_input_seq(1, 0, 0, true, 1))
	check(not relay.next_jump(0), "迟到旧包不能重新按下")
	relay.jump_seq[0] = 65535
	relay._on_packet(key, Relay.encode_input_seq(3, 0, 0, false, 0))
	check(relay.next_jump(0) and not relay.next_jump(0), "累计跳跃序号回绕后仍只执行一次")
	# 无重复事件时，不改变 WS 可靠输入原有的保持和短按锁存语义。
	relay._on_packet(key, Relay.encode_input(0, 0, true))
	relay._on_packet(key, Relay.encode_input(0, 0, false))
	check(relay.next_jump(0), "WebSocket 短按锁存保持兼容")
	relay.free()
	print("NET PROTOCOL failures=",failures)
	quit(1 if failures else 0)
