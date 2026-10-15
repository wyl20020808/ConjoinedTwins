extends SceneTree

const Journey=preload("res://scripts/journey_run.gd")

func _initialize() -> void:
	var run=Journey.new()
	run.combat_trial=true
	run.solo_control=true
	run.retry()
	run.clear_input=false
	var invariant_error := ""
	var peak_pickups := 0
	for frame in range(6500):
		if run.state!="running": break
		# 只在看见有效目标时按住射击，模拟玩家控制开火，不替玩家移动或瞄准。
		var fire: bool=not run.Combat.select_target(run,0,-1).is_empty()
		run.set_combat_input(fire)
		var previous := [run.a.position,run.b.position]
		run.step(1.0/60.0,Vector2(0,1))
		if run.a.position.distance_to(run.b.position)>run.LINK_LIMIT+0.03:
			invariant_error="rope length exceeded";break
		if run.a.position.y<previous[0].y-0.001 or run.b.position.y<previous[1].y-0.001:
			invariant_error="unexpected backward movement";break
		peak_pickups=maxi(peak_pickups,run.combat.pickups.size())
	var passed: bool=run.state=="complete" and run.combat.kills==6 and run.combat.health==[100,100] and invariant_error.is_empty()
	print("COMBAT TRIAL REPLAY ",JSON.stringify({"passed":passed,"state":run.state,"seconds":run.elapsed,"progress":run.progress(),"kills":run.combat.kills,"health":run.combat.health,"peak_pickups":peak_pickups,"invariant_error":invariant_error,"reason":run.reason}))
	run.dispose()
	quit(0 if passed else 1)
