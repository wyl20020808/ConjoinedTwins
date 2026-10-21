extends SceneTree
# 自适应联机缓冲：模拟隧道抖动（帧每 100 毫秒一阵、偶有 150 毫秒长停），对比旧的“来一帧用一帧”
# 与新的自适应缓冲在 20 秒内的卡顿次数；同时核对帧按原顺序全部应用、不跳不重。
# 用法：Godot --headless --path . --script res://tests/online_jitter_buffer.gd
const NetClient = preload("res://scripts/net_client.gd")
var failures: Array = []

func check(ok: bool, name: String) -> void:
	print("PASS " if ok else "FAIL ", name)
	if not ok: failures.append(name)

func _initialize() -> void:
	call_deferred("validate")

# 返回 [卡顿次数, 应用的帧序号]；adaptive=false 时用旧规则。
func simulate(adaptive: bool) -> Array:
	var net = NetClient.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261021
	var produced := 0
	var applied: Array = []
	var stalls := 0
	var empty_before := false
	var next_burst := 0.0
	for tick in range(1200):
		var now := tick * NetClient.FRAME_MS
		# 服务器每 16.7 毫秒产生一帧，但经隧道按一阵一阵到达（约 100 毫秒一阵，偶尔再晚 50 毫秒）。
		if now >= next_burst:
			var due := int(now / NetClient.FRAME_MS) + 1
			while produced < due:
				net.frames.append({"index": produced})
				if net.last_arrival_usec > 0: net.gaps.append(0.5)
				produced += 1
			net.gaps.append(100.0 + (50.0 if rng.randf() < 0.2 else 0.0))
			if net.gaps.size() > 180: net.gaps.pop_front()
			net.last_arrival_usec = 1
			next_burst = now + 100.0 + (50.0 if rng.randf() < 0.2 else 0.0)
		var limit := 0
		if adaptive:
			limit = net.playout_limit(8)
		else:
			var queued: int = net.frames.size()
			limit = 1 if queued <= 2 else (2 if queued <= 8 else mini(8, queued - 2))
			if queued == 0 and not empty_before: stalls += 1
			empty_before = queued == 0
		for n in range(mini(limit, net.frames.size())):
			applied.append(net.frames.pop_front().index)
	var result := [net.stalls if adaptive else stalls, applied]
	net.free()
	return result

func validate() -> void:
	var old_run := simulate(false)
	var new_run := simulate(true)
	print("JITTER old stalls=", old_run[0], " new stalls=", new_run[0], " new applied=", new_run[1].size())
	check(new_run[1] == range(new_run[1].size()), "自适应缓冲按原顺序应用全部帧，不跳不重")
	check(new_run[1].size() > 1100, "20 秒内正常推进（不会一直等待）")
	check(new_run[0] * 4 <= old_run[0], "抖动下卡顿次数降到旧规则的四分之一以下")
	print("ONLINE JITTER failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
