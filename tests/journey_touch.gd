extends SceneTree
class TestNet extends "res://scripts/net_client.gd":
	var last_jump:=false
	var active_flag:=true
	func active()->bool:return active_flag
	func send_input(_move:Vector2,jump:bool)->void:last_jump=jump
var failures:=0
func _initialize()->void:call_deferred("validate")
func check(ok:bool,name:String)->void:
	print("PASS " if ok else "FAIL ",name)
	if not ok:failures+=1
func validate()->void:
	var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game);game.set_physics_process(false)
	await process_frame
	game.net.disconnect_from();game.net.queue_free()
	game.net=TestNet.new();game.add_child(game.net);game.net.in_match=true
	game.play_mode="online";game.touch_device=true;game.run.state="running"
	game.touch.set_enabled(true);game.touch.jump_tapped=true
	game._physics_process(1.0/60)
	check(game.net.last_jump,"short mobile tap sent to remote role")
	game._physics_process(1.0/60)
	check(not game.net.last_jump,"tap consumed once, no held synthetic jump")
	game.net.active_flag=false;game.play_mode="solo"
	game.touch.move=Vector2(0,-1)
	var input:Dictionary=game.sample_local_input()
	check(input.a.y==0,"touch cannot request backward movement")
	game.touch.move=Vector2(1,1)
	input=game.sample_local_input()
	check(input.a==Vector2(1,1),"touch movement feeds normal raw axes")
	game.run.state="paused";game._physics_process(1.0/60)
	check(not game.touch.enabled,"paused touch controls disabled")
	game.queue_free();await process_frame
	print("JOURNEY TOUCH FAILURES ",failures)
	quit(0 if failures==0 else 1)
