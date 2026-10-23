extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
var failed:Array=[]
var checked:=0
func check(ok:bool,name:String)->void:
	checked+=1
	if not ok:failed.append(name);printerr("FAIL ",name)
func isolated(kind:String):
	var run=Journey.new()
	run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear();run.journey_events.clear();run.charge_gates.clear();run.select_charge_gate()
	# 倒树等人走近才起裂，放在触发距离之内。
	run.add_event(kind,700 if kind=="tree" else 800,1)
	run.a.position=Vector2(100,300);run.b.position=Vector2(150,300)
	run.rope.reset(run.a.position,run.b.position)
	run.clear_input=false;run.state="running"
	return run
func _initialize()->void:
	for kind in ["tree","boar","stone","cart","swing"]:
		var run=isolated(kind)
		run.fixed_step(Vector2.ZERO,Vector2.ZERO)
		var event:Dictionary=run.journey_events[0]
		check(event.phase=="warning",kind+" warns before attack")
		var trigger:float=event.trigger
		var locked:float=event.locked_x
		run.a.position.x=-240;run.b.position.x=-190
		run.advance_events(run.FIXED_STEP)
		check(event.locked_x==locked and event.trigger==trigger,kind+" lock does not track")
		run.elapsed=trigger+(run.TREE_WARNING+run.TREE_FALL*0.8 if kind=="tree" else 3.1)
		run.advance_events(run.FIXED_STEP)
		check(event.phase in ["active","falling"],kind+" activates")
		var phase_before:String=event.phase
		var sample_before:Rect2=event.sample
		run.pause();run.step(0.2,Vector2.ZERO,Vector2.ZERO)
		check(event.phase==phase_before and event.sample==sample_before,kind+" pauses")
		run.pause()
		var rect:Rect2=event.sample
		var x:float=clampf(rect.get_center().x,-220,220)
		if kind=="cart":x=rect.get_center().x
		run.a.position=Vector2(x-15,rect.get_center().y)
		run.b.position=Vector2(x+15,rect.get_center().y)
		run.rope.reset(run.a.position,run.b.position)
		run.check_event_hits([run.a.position,run.b.position])
		check(run.state=="failed",kind+" actual body collision")
		run.dispose()
	# 倒树落地后成为实体，不允许角色穿过。
	var tree=isolated("tree")
	tree.elapsed=10
	var event:Dictionary=tree.journey_events[0]
	event.trigger=0
	tree.advance_events(tree.FIXED_STEP)
	var segments:Array=tree.tree_segments(event)
	check(event.phase=="fallen" and range(tree.TREE_SEGMENTS).all(func(n):return tree.obstacles[event.trunk[n]]==segments[n]),"fallen tree retains collision")
	# 倒向锁定在两人所在方向：两人站在树的左前方，树干朝左前方倒。
	var aimed=isolated("tree")
	aimed.a.position=Vector2(-100,420);aimed.b.position=Vector2(-50,420)
	aimed.advance_events(aimed.FIXED_STEP)
	var lean:Dictionary=aimed.journey_events[0]
	check(lean.trigger>=0 and lean.direction.x<-0.3 and lean.direction.y<0,"tree falls toward players")
	aimed.dispose()
	tree.dispose()
	print("JOURNEY EVENT CHECKS ",checked," FAILURES ",failed.size())
	quit(0 if failed.is_empty() else 1)
