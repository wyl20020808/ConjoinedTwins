extends SceneTree

const Journey=preload("res://scripts/journey_run.gd")
var errors:Array[String]=[]
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok: errors.append(message);printerr("FAIL ",message)

func _initialize()->void:
	var run=Journey.new()
	check(run.state=="start","start state")
	run.state="running"
	for n in range(120):run.step(run.FIXED_STEP)
	check(run.a.position==Vector2(-42,0) and run.b.position==Vector2(42,0),"no automatic movement")
	check(run.distance==0,"no automatic camera progress")
	for n in range(120):run.step(run.FIXED_STEP,Vector2(0,-1),Vector2(0,-1))
	check(run.a.position.y==0 and run.b.position.y==0,"backward input rejected")
	for n in range(240):run.step(run.FIXED_STEP,Vector2(0,1),Vector2(0,1))
	check(run.a.position.y>300 and run.b.position.y>300,"manual forward movement")
	var before:Vector2=run.a.position
	var time:float=run.elapsed
	run.pause()
	for n in range(30):run.step(run.FIXED_STEP,Vector2(0,1),Vector2(0,1),true,true)
	check(run.a.position==before and run.elapsed==time,"pause freezes state")
	run.pause()
	for n in range(50):run.step(run.FIXED_STEP,Vector2.ZERO,Vector2.ZERO)
	check(run.a.position.distance_to(before)<0.01,"release stops movement")
	var heights_before:float=run.heights[0]
	run.step(run.FIXED_STEP,Vector2.ZERO,Vector2.ZERO,true,false)
	check(run.heights[0]>heights_before and run.heights[1]==0,"independent jump")
	for n in range(100):run.step(run.FIXED_STEP)
	check(not run.checkpoint.is_empty(),"region checkpoint exists")
	var cp:Dictionary=run.checkpoint.duplicate(true)
	run.fail_threat("test failure")
	check(run.restore_checkpoint(),"restore checkpoint")
	check(run.a.position==cp.a and run.b.position==cp.b,"restored positions")
	check(run.journey_events==cp.run.journey_events,"restored deterministic events")
	for chapter in range(3):
		run.level_index=chapter;run.retry()
		check(run.charge_gates.size()==2,"two-stage exit chapter %d"%chapter)
		check(run.journey_events.size()>5,"authored events chapter %d"%chapter)
		for zone in range(6):
			check(not run.CHAPTERS[chapter].zones[zone].is_empty(),"six named regions")
		check(run.rewards.size()<=run.Levels.MAX_REWARDS,"bounded rewards")
	# 任意前进输入在连线拉满时不能把静止的另一人往后拉。
	run.level_index=0;run.retry()
	var previous:=[run.a.position,run.b.position]
	for n in range(600):
		run.step(run.FIXED_STEP,Vector2(0,1) if n<400 else Vector2.RIGHT,Vector2.ZERO)
		check(run.a.position.y>=previous[0].y-0.001 and run.b.position.y>=previous[1].y-0.001,"no physical backward displacement")
		check(run.a.position.distance_to(run.b.position)<=run.LINK_LIMIT+0.02,"rope bound")
		previous=[run.a.position,run.b.position]
	# 门前站位可侧移，前进被挡住后不会错过无法回撤的机关。
	run.retry()
	var gate:Dictionary=run.charge_gates[0]
	var hold:float=gate.receiver.y+15
	run.a.position=Vector2(-65,hold-1);run.b.position=Vector2(65,hold-1)
	run.rope.reset(run.a.position,run.b.position)
	for n in range(240):run.step(run.FIXED_STEP,Vector2(0,1),Vector2(0,1))
	check(gate.open,"charge opens from forward-only hold line")
	var plates:Dictionary=run.charge_gates[1]
	run.a.position=plates.left.get_center();run.b.position=plates.right.get_center()
	run.rope.reset(run.a.position,run.b.position)
	for n in range(90):run.step(run.FIXED_STEP)
	check(plates.open,"plates open")
	var bridge_index:int=run.kinds.find("drawbridge")
	var bridge:Rect2=run.obstacles[bridge_index]
	run.elapsed+=1.0
	var gap_y:float=bridge.position.y+26
	run.a.position=Vector2(-28,gap_y-50);run.b.position=Vector2(28,gap_y-50)
	run.rope.reset(run.a.position,run.b.position)
	for n in range(250):run.step(run.FIXED_STEP,Vector2(0,1),Vector2(0,1))
	check(run.state=="running" and run.a.position.y>bridge.end.y,"bridge bank transitions remain supported")
	# 一次性结算和双方确认。
	run.a.position.y=run.finish_distance()+1;run.b.position.y=run.finish_distance()+1
	run.check_finish()
	check(run.state=="settlement" and run.results.size()==1,"shared finish")
	run.step(0,Vector2.ZERO,Vector2.ZERO,false,false)
	run.step(0,Vector2.ZERO,Vector2.ZERO,true,false)
	check(run.state=="settlement","requires both confirmations")
	run.step(0,Vector2.ZERO,Vector2.ZERO,true,true)
	check(run.level_index==1 and run.state=="running","next chapter")
	run.dispose()
	print("JOURNEY CHECKS ",checks," FAILURES ",errors.size())
	quit(0 if errors.is_empty() else 1)
