extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
const Buddy=preload("res://scripts/journey_buddy.gd")
const Route=preload("res://tests/fixtures/journey_route.gd")
var failures:Array=[]
var reports:Array=[]
func _initialize()->void:call_deferred("validate")
func validate()->void:
	for chapter in range(3):
		var run=Journey.new();run.level_index=chapter;run.retry();run.state="running"
		var ai=Buddy.new();var frames:=0;var lowest:=0.0;var max_rope:=0.0
		while frames<60000 and run.state=="running":
			var human:Dictionary=Route.input(run)
			var choice:Dictionary=ai.think(run,1.0/60,human.move,human.jump)
			var a:Vector2=run.a.position;var b:Vector2=run.b.position
			run.step(1.0/60,human.move,choice.move,human.jump,choice.jump)
			lowest=minf(lowest,minf(run.a.position.y-a.y,run.b.position.y-b.y));max_rope=maxf(max_rope,run.rope.length)
			frames+=1
			if frames%1000==0:print("DENSITY PROGRESS ",chapter," ",frames," ",run.progress()," ",run.state);await process_frame
		var r:={"chapter":chapter,"frames":frames,"state":run.state,"reason":run.reason,"progress":run.progress(),"gates":run.charge_gates.size(),"opened":run.charge_gates.filter(func(g):return g.open).size(),"encounters":run.encounter_markers.size(),"rewards":run.rewards.size(),"lowest_forward_delta":lowest,"max_rope":max_rope,"health":run.combat.health,"ai":ai.feedback}
		print("DENSITY CAMPAIGN ",JSON.stringify(r));reports.append(r)
		if run.state!="settlement" or lowest<-.001 or max_rope>run.LINK_LIMIT+.02:failures.append(r)
		run.dispose()
	var f:=FileAccess.open("res://build-tools/journey/evidence/environment/density-campaign.json",FileAccess.WRITE);f.store_string(JSON.stringify({"runs":reports,"failures":failures},"\t"))
	print("DENSITY CAMPAIGN FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
