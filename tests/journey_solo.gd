extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
const Buddy=preload("res://scripts/journey_buddy.gd")
var failures:Array=[]
var checks:=0
func check(ok:bool,name:String)->void:
	checks+=1
	if not ok:failures.append(name);printerr("FAIL ",name)
func _initialize()->void:
	var run=Journey.new();var ai=Buddy.new()
	run.state="running"
	for n in range(180):
		var choice:Dictionary=ai.think(run,run.FIXED_STEP)
		run.step(run.FIXED_STEP,Vector2.ZERO,choice.move,false,choice.jump)
	check(run.a.position.y==0 and run.b.position.y==0,"idle player does not start automatic running")
	for n in range(360):
		var choice:Dictionary=ai.think(run,run.FIXED_STEP,Vector2(0,1))
		check(choice.move.y>=0,"AI never asks to walk backwards")
		run.step(run.FIXED_STEP,Vector2(0,1),choice.move,false,choice.jump)
	check(run.b.position.y>350,"AI follows manual forward movement")
	check(run.a.position.distance_to(run.b.position)<=run.LINK_LIMIT+0.01,"same rope bound")
	run.pause()
	var point:Vector2=run.b.position
	var time:float=ai.clock
	for n in range(40):
		var choice:Dictionary=ai.think(run,run.FIXED_STEP,Vector2(0,1))
		run.step(run.FIXED_STEP,Vector2(0,1),choice.move,false,choice.jump)
	check(run.b.position==point and ai.clock==time,"pause freezes AI")
	run.pause()
	# 合作站位：人类在任意一侧，AI 到另一侧，不依赖角色固定分配。
	for exchange in [false,true]:
		run.retry();ai.reset()
		var gate:Dictionary=run.charge_gates[0]
		run.a.position=Vector2(65 if exchange else -65,gate.receiver.y)
		run.b.position=Vector2(-30 if exchange else 30,gate.receiver.y)
		run.rope.reset(run.a.position,run.b.position)
		for n in range(400):
			var choice:Dictionary=ai.think(run,run.FIXED_STEP)
			run.step(run.FIXED_STEP,Vector2.ZERO,choice.move,false,choice.jump)
		check(gate.open,"AI cooperates with charge gate, exchanged=%s"%exchange)
		var plates:Dictionary=run.charge_gates[1]
		run.a.position=(plates.right if exchange else plates.left).get_center()
		run.b.position=Vector2(-15 if exchange else 15,run.a.position.y)
		run.rope.reset(run.a.position,run.b.position);ai.reset()
		for n in range(300):
			var choice:Dictionary=ai.think(run,run.FIXED_STEP)
			run.step(run.FIXED_STEP,Vector2.ZERO,choice.move,false,choice.jump)
		check(plates.open,"AI cooperates with plates, exchanged=%s"%exchange)
	# 实际低栏跳跃：双方使用相同跳跃物理，AI 不穿越低栏。
	run.retry();ai.reset()
	run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear();run.journey_events.clear();run.charge_gates.clear();run.select_charge_gate()
	run.a.position=Vector2(-56,0);run.b.position=Vector2(0,0)
	run.rope.reset(run.a.position,run.b.position)
	run.add_hazard("rail",Rect2(-100,60,200,12))
	run.step(run.FIXED_STEP)
	var jumped:=false
	for n in range(100):
		var choice:Dictionary=ai.think(run,run.FIXED_STEP,Vector2(0,1),n==0)
		run.step(run.FIXED_STEP,Vector2(0,1),choice.move,n==0,choice.jump)
		jumped=jumped or run.heights[1]>0
	check(jumped and run.state=="running" and run.b.position.y>96,"AI jumps over actual low rail")
	# 真人踩空后，AI 用普通跳跃键节奏救援，不修改救援进度。
	run.retry();ai.reset()
	run.a.position=Vector2(-100,0);run.b.position=Vector2(-44,0)
	run.add_hazard("road_gap",Rect2(-130,-20,50,200))
	run.rope.reset(run.a.position,run.b.position)
	run.begin_fall(0,run.a.position)
	check(run.state=="rescue","single fall enters real rescue")
	for n in range(360):
		var choice:Dictionary=ai.think(run,run.FIXED_STEP)
		run.step(run.FIXED_STEP,Vector2.ZERO,choice.move,false,choice.jump)
		if run.state!="rescue":break
	check(run.state=="running","AI rescues fallen human with normal key presses")
	# AI 自动确认不替代真人确认。
	run.state="settlement";run.confirmations=[false,false];run.confirmation_held=[false,false]
	for n in range(150):
		var choice:Dictionary=ai.think(run,run.FIXED_STEP)
		run.step(run.FIXED_STEP,Vector2.ZERO,choice.move,false,choice.jump)
	check(run.confirmations[1] and not run.confirmations[0],"AI confirms only own role")
	run.dispose()
	print("JOURNEY SOLO CHECKS ",checks," FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)
