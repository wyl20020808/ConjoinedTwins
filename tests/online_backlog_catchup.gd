extends "res://tests/journey_online.gd"
# 联机积压追帧回归：一端停顿约 2 秒（模拟路段加载或浏览器卡顿）后，积压帧须在数秒内追回，
# 不能变成永久输入延迟；追帧期间两端逐帧指纹仍一致、帧号连续。

func validate()->void:
	var relay=Relay.new();relay.port=24841;relay.ws_port=24842;root.add_child(relay)
	var games:Array=[]
	for endpoint in range(2):
		var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
		game.play_mode="online"
		game.input_override={"a":Vector2.ZERO,"b":Vector2.ZERO,"ja":false,"jb":false}
		game.online_frame_applied.connect(func(index):record(endpoint,index,game))
		games.append(game)
		game.net.connect_to("ws://127.0.0.1:24842")
	check(await until(func():return games.all(func(g):return g.net.in_match)),"two production journey clients connect")
	if not games.all(func(g):return g.net.in_match):quit(1);return
	games[0].command("primary")
	check(await until(func():return common>=90 and games.all(func(g):return g.run.state=="running")),"shared start")
	games[0].input_override.a=Vector2(0,1);games[1].input_override.a=Vector2(0,1)
	# 第二端停顿：物理帧不跑，网络帧只进不出。
	games[1].set_physics_process(false)
	var stall_until:=Time.get_ticks_msec()+2000
	await until(func():return Time.get_ticks_msec()>=stall_until,3.0)
	var peak:int=games[1].net.frames.size()
	check(peak>=90,"stall builds a backlog (%d frames)"%peak)
	games[1].set_physics_process(true)
	var resumed:=Time.get_ticks_msec()
	check(await until(func():return games[1].net.frames.size()<=3,6.0),"backlog drains to at most 3 frames")
	var drain_ms:=Time.get_ticks_msec()-resumed
	print("backlog peak=",peak," drained_ms=",drain_ms)
	check(drain_ms<=4000,"backlog drains within 4 s (%d ms)"%drain_ms)
	# 追回后稳态缓冲保持很小，不再残留延迟。
	var worst:=0
	var steady_until:=Time.get_ticks_msec()+2000
	await until(func():
		worst=maxi(worst,games[1].net.frames.size())
		return Time.get_ticks_msec()>=steady_until,3.0)
	check(worst<=4,"steady buffer stays small after catch-up (max %d)"%worst)
	check(await until(func():return common>=420),"420 common network frames")
	check(equal and games.all(func(g):return not g.net.desynced),"all hashes equal and frame numbers contiguous")
	for game in games:game.net.disconnect_from();game.queue_free()
	relay.queue_free();await process_frame
	print("ONLINE BACKLOG common=",common," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
