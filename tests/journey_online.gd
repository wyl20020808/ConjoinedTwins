extends SceneTree
const Relay=preload("res://scripts/net_relay.gd")
var failures:Array=[]
var records:=[{},{}]
var common:=0
var equal:=true
var last:=[-1,-1]
func check(ok:bool,name:String)->void:
	print("PASS " if ok else "FAIL ",name)
	if not ok:failures.append(name)
func _initialize()->void:call_deferred("validate")
func until(predicate:Callable,seconds:float=15.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call():return true
		await process_frame
	return predicate.call()
func record(endpoint:int,index:int,game)->void:
	equal=equal and index==last[endpoint]+1
	last[endpoint]=index
	records[endpoint][index]=game.run.sync_hash()
	if records[1-endpoint].has(index):
		equal=equal and records[endpoint][index]==records[1-endpoint][index]
		common+=1
		records[0].erase(index);records[1].erase(index)
func validate()->void:
	var relay=Relay.new();relay.port=24831;relay.ws_port=24832;root.add_child(relay)
	var games:Array=[]
	for endpoint in range(2):
		var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
		game.play_mode="online"
		game.input_override={"a":Vector2.ZERO,"b":Vector2.ZERO,"ja":false,"jb":false}
		game.online_frame_applied.connect(func(index):record(endpoint,index,game))
		games.append(game)
		game.net.connect_to("ws://127.0.0.1:24832" if endpoint==1 or OS.get_environment("ONLINE_TRANSPORT")!="mixed" else "127.0.0.1:24831")
	check(await until(func():return games.all(func(g):return g.net.in_match)),"two production journey clients connect")
	if not games.all(func(g):return g.net.in_match):quit(1);return
	games[0].command("primary")
	check(await until(func():return common>=90 and games.all(func(g):return g.run.state=="running")),"shared start")
	games[0].input_override.a=Vector2(0,1);games[1].input_override.a=Vector2(0,1)
	check(await until(func():return games.all(func(g):return g.run.a.position.y>100 and g.run.b.position.y>100)),"both remote roles receive forward input")
	games[0].input_override.a=Vector2.ZERO;games[1].input_override.a=Vector2.ZERO
	games[0].command("pause")
	check(await until(func():return games.all(func(g):return g.run.state=="paused")),"shared pause")
	games[1].command("pause")
	check(await until(func():return games.all(func(g):return g.run.state=="running")),"either player can resume")
	var before_seed:int=games[0].run.seed_value
	games[0].command("retry")
	check(await until(func():return games.all(func(g):return g.run.seed_value!=before_seed and g.run.state=="running")),"shared retry")
	check(await until(func():return common>=420),"420 common network frames")
	check(equal and games.all(func(g):return not g.net.desynced),"all hashes equal and frame numbers contiguous")
	check(games.all(func(g):return g.play_mode=="online" and g.buddy.clock==0),"online disables AI")
	var hash_before:int=games[0].run.sync_hash()
	games[0].run.journey_events[0].trigger=1.25
	check(games[0].run.sync_hash()!=hash_before,"event phases included in network fingerprint")
	# 联机流量（本层负载字节，不含 WebSocket/TCP 头）：每帧下行与整局上行，供带宽评估。
	for game in games:print("JOURNEY ONLINE traffic role=",game.net.role," frames=",game.net.next_frame," down_bytes=",game.net.bytes_received," up_bytes=",game.net.bytes_sent," down_per_frame=",snappedf(float(game.net.bytes_received)/maxi(game.net.next_frame,1),0.01)," jitter_ms=",snappedf(game.net.jitter_ms(),0.1)," stalls=",game.net.stalls)
	for game in games:game.net.disconnect_from();game.queue_free()
	relay.queue_free();await process_frame
	print("JOURNEY ONLINE common=",common," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
