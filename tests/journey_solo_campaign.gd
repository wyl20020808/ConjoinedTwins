extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
const Buddy=preload("res://scripts/journey_buddy.gd")
var evidence:Array=[]
var failures:Array=[]
func direction(point:Vector2,target:Vector2)->Vector2:
	return Vector2(signf(target.x-point.x) if absf(target.x-point.x)>1.2 else 0.0,1.0 if target.y-point.y>1.2 else 0.0)
func _initialize()->void:
	call_deferred("validate")
func validate()->void:
	for chapter in range(3):
		var run=Journey.new()
		var ai=Buddy.new()
		run.level_index=chapter;run.retry();run.state="running"
		var frames:=0
		var lowest_delta:=0.0
		var max_rope:=0.0
		while frames<65000 and run.state=="running":
			var y:float=minf(run.a.position.y,run.b.position.y)
			var center:=0.0
			var wait:=false
			var target_y:=y+600
			var half:=28.0
			var static_order:Array=range(run.kinds.size())
			static_order.sort_custom(func(i,j):return run.obstacles[i].position.y<run.obstacles[j].position.y)
			for i in static_order:
				var rect:Rect2=run.obstacles[i]
				if rect.end.y<y-30 or rect.position.y>y+800:continue
				if run.kinds[i]=="collapse" or (run.kinds[i]=="road_gap" and rect.size.x<200):center=245 if rect.get_center().x<=0 else -245
				if run.kinds[i]=="rail":center=245
				if center!=0:break
			for event in run.journey_events:
				if event.y<y-100 or event.y>y+800:continue
				if event.kind in ["tree","boar"]:center=-event.side*245
				elif event.kind=="swing":center=270
				elif event.kind in ["stone","cart"]:
					if event.phase!="spent" and y>event.y-480:wait=true
			for i in range(run.kinds.size()):
				if run.kinds[i]=="road_gap" and run.obstacles[i].size.x>200:
					var bridge_rect:Rect2=run.obstacles[i]
					if y>=bridge_rect.position.y-400 and y<=bridge_rect.end.y+30:center=0
			if run.charge_gate.active and not run.charge_gate.open and run.charge_gate.receiver.y-y<700:
				var gate:Dictionary=run.charge_gate
				center=0;wait=false
				half=45 if gate.get("kind","")=="sync_plates" else 65
				target_y=gate.receiver.y+(46 if gate.get("kind","")=="sync_plates" else 0)
			if wait:target_y=y
			var target_a:=Vector2(center-half,target_y)
			var target_b:=Vector2(center+half,target_y)
			var ia:=direction(run.a.position,target_a)
			var ib:=direction(run.b.position,target_b)
			# 先横移至共同安全走廊，再进入危险段，完全使用原始键盘轴值。
			if absf(target_a.x-run.a.position.x)>8:
				ia.y=0;ib.y=0
			var pa:Vector2=run.a.position
			var pb:Vector2=run.b.position
			var choice:Dictionary=ai.think(run,run.FIXED_STEP,ia)
			run.step(run.FIXED_STEP,ia,choice.move,false,choice.jump)
			lowest_delta=minf(lowest_delta,minf(run.a.position.y-pa.y,run.b.position.y-pb.y))
			max_rope=maxf(max_rope,run.rope.length)
			frames+=1
			if frames%10000==0:print("PROGRESS chapter=",chapter," y=",y," state=",run.state," gate=",run.charge_gate.get("id","none"));await process_frame
		var result:={"chapter":chapter+1,"frames":frames,"state":run.state,"reason":run.reason,"a":str(run.a.position),"b":str(run.b.position),"ai":ai.feedback,"progress":run.progress(),"zones":run.visited_zones.duplicate(),"max_rope":max_rope,"lowest_delta":lowest_delta,"gate_events":run.gate_events.duplicate(true)}
		evidence.append(result)
		if run.state!="settlement" or lowest_delta<-.001 or max_rope>run.LINK_LIMIT+.02 or run.visited_zones.size()!=6:failures.append(result)
		print("CAMPAIGN ",JSON.stringify(result))
		run.dispose()
	DirAccess.make_dir_recursive_absolute("res://build-tools/journey/evidence")
	var file:=FileAccess.open("res://build-tools/journey/evidence/web-update/solo-campaign.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"executor_self_test":failures.is_empty(),"controller_tests":[],"runs":evidence},"\t"))
	print("JOURNEY SOLO CAMPAIGN FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)
