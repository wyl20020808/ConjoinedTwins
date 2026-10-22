extends SceneTree
# 联机缓冲：模拟隧道抖动（帧每 100 毫秒一阵、偶有 150 毫秒长停），对比三种消化规则 20 秒内的画面停顿：
#  - 最早的“来一帧用一帧”；
#  - 上一版“见底后停住，攒满目标帧数再继续”（日志里队友每 10 秒卡十几次的来源）；
#  - 现在的“见底只等下一帧 + 轻微变速”。
# 体感卡顿按“连续 3 个物理帧以上没有推进”（≥50 毫秒）计；同时核对帧按原顺序全部应用、不跳不重。
# 用法：Godot --headless --path . --script res://tests/online_jitter_buffer.gd
const NetClient = preload("res://scripts/net_client.gd")
var failures: Array = []

func check(ok: bool, name: String) -> void:
	print("PASS " if ok else "FAIL ", name)
	if not ok: failures.append(name)

func _initialize() -> void:
	call_deferred("validate")

# 上一版规则（只用于对照）。
func previous_limit(net, state: Dictionary) -> int:
	var queued: int = net.frames.size()
	var target: int = net.playout_target()
	if queued == 0:
		state.starved = true
		return 0
	if state.starved:
		if queued < target: return 0
		state.starved = false
	if queued <= target: return 1
	if queued <= target + 6: return 2
	return mini(8, queued - target)

# 返回 {hitches: ≥3 帧的停顿次数, frozen: 停住的物理帧总数, applied: 应用的帧序号}。
func simulate(mode: String) -> Dictionary:
	var net = NetClient.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261021
	var produced := 0
	var applied: Array = []
	var next_burst := 0.0
	var state := {"starved": false}
	var run := 0
	var hitches := 0
	var frozen := 0
	for tick in range(1200):
		var now := tick * NetClient.FRAME_MS
		# 服务器每 16.7 毫秒产生一帧，但经隧道按一阵一阵到达（约 100 毫秒一阵，偶尔再晚 50 毫秒）。
		if now >= next_burst:
			var due := int(now / NetClient.FRAME_MS) + 1
			while produced < due:
				net.frames.append({"index": produced})
				produced += 1
			net.gaps.append(100.0 + (50.0 if rng.randf() < 0.2 else 0.0))
			if net.gaps.size() > 180: net.gaps.pop_front()
			next_burst = now + 100.0 + (50.0 if rng.randf() < 0.2 else 0.0)
		var limit := 0
		match mode:
			"current": limit = net.playout_limit(8)
			"previous": limit = previous_limit(net, state)
			_:
				var queued: int = net.frames.size()
				limit = 1 if queued <= 2 else (2 if queued <= 8 else mini(8, queued - 2))
		var took := mini(limit, net.frames.size())
		for n in range(took): applied.append(net.frames.pop_front().index)
		if tick < 30: continue
		if took == 0:
			run += 1
			frozen += 1
		else:
			if run >= 3: hitches += 1
			run = 0
	net.free()
	return {"hitches": hitches, "frozen": frozen, "applied": applied}

func validate() -> void:
	var naive := simulate("naive")
	var previous := simulate("previous")
	var current := simulate("current")
	for entry in [["来一帧用一帧", naive], ["上一版", previous], ["现在", current]]:
		print("JITTER %s: 停顿≥50ms %d 次，停住物理帧 %d，应用 %d 帧" % [entry[0], entry[1].hitches, entry[1].frozen, entry[1].applied.size()])
	check(current.applied == range(current.applied.size()), "按原顺序应用全部帧，不跳不重")
	check(current.applied.size() > 1100, "20 秒内正常推进")
	check(current.hitches * 4 <= previous.hitches, "≥50 毫秒的停顿降到上一版的四分之一以下")
	check(current.hitches <= naive.hitches, "不比来一帧用一帧更卡")
	print("ONLINE JITTER failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
