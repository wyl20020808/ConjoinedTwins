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
	# 生产拾枪、开火、换弹与丢枪通过真实中继排进共同帧。
	games[0].input_override.a=Vector2(0,1);games[1].input_override.a=Vector2(0,1)
	check(await until(func():return games.all(func(g):return g.run.a.position.y>220 and not g.run.combat.weapons[0].is_empty())),"remote player automatically picks gun")
	games[0].input_override.a=Vector2.ZERO;games[1].input_override.a=Vector2.ZERO
	games[0].input_override.fire=true
	check(await until(func():return games.all(func(g):return g.run.combat.weapons[0].ammo<24)),"remote mouse fire changes both simulations")
	games[0].input_override.fire=false
	check(await until(func():return games.all(func(g):return not g.run.combat.fire[0])),"remote release stops fire")
	games[0].net.send_command("combat","0,1,0")
	check(await until(func():return games.all(func(g):return g.run.combat.weapons[0].reload>0)),"remote R starts reload on shared frame")
	check(await until(func():return games.all(func(g):return g.run.combat.weapons[0].ammo==24 and g.run.combat.weapons[0].reload==0)),"remote reload completes identically")
	games[0].net.send_command("combat","0,0,1")
	check(await until(func():return games.all(func(g):return g.run.combat.weapons[0].is_empty())),"remote G drops gun on both clients")
	var forward_progress:float=games[0].run.distance
	var before_retreat:float=games[0].run.a.position.y
	games[0].input_override.a=Vector2(0,-1);games[1].input_override.a=Vector2(0,-1)
	check(await until(func():return games.all(func(g):return g.run.a.position.y<before_retreat-30)),"remote roles can retreat")
	games[0].input_override.a=Vector2.ZERO;games[1].input_override.a=Vector2.ZERO
	check(games.all(func(g):return g.run.distance>=forward_progress),"remote retreat leaves camera progress unchanged")
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
	for game in games:game.net.disconnect_from();game.queue_free()
	relay.queue_free();await process_frame
	print("COMBAT ONLINE common=",common," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
