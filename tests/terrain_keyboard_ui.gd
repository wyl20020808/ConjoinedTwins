extends SceneTree

# 可见生产窗口中的原生键盘验收。此脚本只观察输入，不合成 InputEvent 或调用移动函数。
var game
var seconds:=0.0
var seen:Dictionary={"player1_move":false,"player2_move":false,"player1_jump":false,"player2_jump":false,"pause":false,"retry":false}
var last_axes:Array=[]
var done:=false
var last_distance:=0.0

func _initialize()->void:
	call_deferred("start")

func start()->void:
	game=load("res://scenes/road_demo.tscn").instantiate()
	game.run.generation_enabled=false
	game.run.async_enabled=false
	root.add_child(game)
	game.run.charge_tutorial=false
	game.run.retry()
	game.run.state="start"
	game.sync_view()
	print("NATIVE_INPUT_READY")

func _process(delta:float)->bool:
	if game==null or done: return false
	seconds+=delta
	var run=game.run
	var axes:Array=[run.move_directions[0],run.move_directions[1],run.heights[0]>0,run.heights[1]>0,run.state]
	if axes!=last_axes:
		print("NATIVE_INPUT ",axes)
		last_axes=axes
	seen.player1_move=seen.player1_move or (Input.is_physical_key_pressed(KEY_A) and absf(run.move_directions[0].x)>0)
	seen.player2_move=seen.player2_move or (Input.is_physical_key_pressed(KEY_RIGHT) and absf(run.move_directions[1].x)>0)
	seen.player1_jump=seen.player1_jump or (Input.is_physical_key_pressed(KEY_SPACE) and run.heights[0]>0)
	seen.player2_jump=seen.player2_jump or (Input.is_physical_key_pressed(KEY_ENTER) and run.heights[1]>0)
	seen.pause=seen.pause or run.state=="paused"
	seen.retry=seen.retry or (Input.is_physical_key_pressed(KEY_R) and run.distance<last_distance)
	last_distance=run.distance
	if seen.values().all(func(value): return value):
		done=true
		call_deferred("finish",true)
	elif seconds>120:
		done=true
		call_deferred("finish",false)
	return false

func finish(ok:bool)->void:
	await RenderingServer.frame_post_draw
	var path="res://build-tools/rope-terrain-evidence/"
	root.get_texture().get_image().save_png(path+"native-keyboard.png")
	var file:=FileAccess.open(path+"native-keyboard.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":ok,"seconds":seconds,"checks":seen,"source":"CUA 原生键盘；生产场景实时物理；未合成 InputEvent"},"\t"))
	print("NATIVE_INPUT_RESULT ",ok," ",seen)
	game.queue_free()
	await process_frame
	quit(0 if ok else 1)
