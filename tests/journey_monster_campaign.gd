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
		var selected:=OS.get_environment("MONSTER_CHAPTER")
		if not selected.is_empty() and chapter!=int(selected):run.dispose();continue
		var ai=Buddy.new();var frames:=0;var lowest:=0.0;var camera_lowest:=0.0;var max_rope:=0.0
		while frames<60000 and run.state=="running":
			var human:Dictionary=Route.input(run)
			var weapon:Dictionary=run.combat.weapons[0]
			# 先用普通前进输入接近起点枪械，再开始绕障；不直接注入武器。
			if weapon.is_empty() and run.a.position.y<180:human.move=Vector2.DOWN
			run.set_combat_input(not weapon.is_empty() and not run.Combat.select_target(run,0,weapon.target).is_empty())
			var choice:Dictionary=ai.think(run,1.0/60,human.move,human.jump)
			var a:Vector2=run.a.position;var b:Vector2=run.b.position
			var camera_before:float=run.distance
			run.step(1.0/60,human.move,choice.move,human.jump,choice.jump)
			camera_lowest=minf(camera_lowest,run.distance-camera_before)
			lowest=minf(lowest,minf(run.a.position.y-a.y,run.b.position.y-b.y));max_rope=maxf(max_rope,run.rope.length)
			frames+=1
			if frames%1000==0:print("MONSTER PROGRESS ",chapter," ",frames," ",run.progress()," ",run.state);await process_frame
		var r:={"chapter":chapter,"frames":frames,"state":run.state,"reason":run.reason,"progress":run.progress(),"gates":run.charge_gates.size(),"opened":run.charge_gates.filter(func(g):return g.open).size(),"encounters":run.encounter_markers.size(),"rewards":run.rewards.size(),"lowest_forward_delta":lowest,"lowest_camera_delta":camera_lowest,"max_rope":max_rope,"health":run.combat.health,"ai":ai.feedback,"kills":run.combat.kills,"ammo":run.combat.weapons[0].duplicate()}
		print("MONSTER CAMPAIGN ",JSON.stringify(r));reports.append(r)
		# 当前需求允许角色后移，改为检查镜头永不后移；保留并加强真实通关要求。
		if run.state!="settlement" or camera_lowest<-.001 or max_rope>run.LINK_LIMIT+.02 or r.opened!=r.gates or run.combat.health.min()<=0:failures.append(r)
		run.dispose()
	var output:=OS.get_environment("MONSTER_REPORT")
	if output.is_empty():output="res://build-tools/journey/evidence/monsters/campaign.json"
	var f:=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify({"runs":reports,"failures":failures},"\t"))
	print("MONSTER CAMPAIGN FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
