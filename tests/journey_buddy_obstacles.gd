extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
const Buddy=preload("res://scripts/journey_buddy.gd")
var failures:Array=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func _initialize()->void:call_deferred("verify")
func isolated():
	var run=Journey.new()
	run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear()
	run.journey_events.clear();run.charge_gates.clear();run.select_charge_gate();run.combat=run.Combat.fresh()
	run.a.position=Vector2(-56,130);run.b.position=Vector2.ZERO
	run.rope.reset(run.a.position,run.b.position)
	run.external_companion=true;run.clear_input=false;run.state="running"
	return run
func verify()->void:
	# 真人已经通过撞石，在绳长内等候；搭档应观察空隙通过，不能把轨道当墙。
	for phase in range(12):
		var run=isolated();var ai=Buddy.new()
		var index:int=run.add_hazard("shuttle",Rect2(-56,50,112,56))
		run.hazard_specs[index].reach=run.EDGE-56
		run.hazard_specs[index].period=3.6
		run.hazard_specs[index].phase=phase*.3
		for frame in range(1200):
			var choice:Dictionary=ai.think(run,run.FIXED_STEP)
			run.step(run.FIXED_STEP,Vector2.ZERO,choice.move,false,choice.jump)
			if run.b.position.y>123 or run.state!="running":break
		check(run.b.position.y>123 and run.state=="running","横跨道路撞石通过，相位 %d，位置 %s"%[phase,run.b.position])
		run.dispose()
	# 空中分部的轨道或梁不能误判为落地实体；地面的锤头仍须拦截。
	for kind in ["hammer","press","piston","shuttle"]:
		var run=isolated();var ai=Buddy.new()
		var index:int=run.add_hazard(kind,Rect2(-26,50,52,44))
		var safe:={"rect":Rect2(-100,30,200,100),"bottom":0.0,"top":136.0,"active":true,"parts":[{"rect":Rect2(-100,30,200,100),"bottom":-3.0,"top":0.0,"active":false},{"rect":Rect2(-100,30,200,100),"bottom":110.0,"top":136.0,"active":true}]}
		var hazard:={"index":index,"samples":[safe,safe,safe,safe,safe,safe,safe,safe,safe]}
		check(not is_inf(ai.path_cost(run,run.b.position,run.a.position,Vector2.DOWN,Vector2.ZERO,false,[hazard],[],Vector2(0,130))),kind+" 不把轨道和高处横梁当墙")
		safe.parts[1].bottom=0.0
		check(is_inf(ai.path_cost(run,run.b.position,run.a.position,Vector2.DOWN,Vector2.ZERO,false,[hazard],[],Vector2(0,130))),kind+" 仍避开地面实体")
		run.dispose()
	var run=isolated();var ai=Buddy.new()
	run.a.position=Vector2(0,110);run.b.position=Vector2(56,0);run.rope.reset(run.a.position,run.b.position)
	run.add_hazard("cargo",Rect2(38,45,36,36))
	for frame in range(1200):
		var choice:Dictionary=ai.think(run,run.FIXED_STEP)
		run.step(run.FIXED_STEP,Vector2.ZERO,choice.move,false,choice.jump)
		if run.b.position.y>100:break
	check(run.b.position.y>100,"高障碍主动横向绕行，位置 %s"%run.b.position)
	run.dispose()
	var industrial=Journey.Industrial
	var reach:float=industrial.HAMMER_LENGTH*sin(industrial.HAMMER_ANGLE)+industrial.HAMMER_HEAD.x*.5
	check(reach>=Journey.EDGE,"摆锤横向摆幅覆盖完整道路")
	check(is_equal_approx(industrial.HAMMER_PIVOT-industrial.HAMMER_LENGTH-industrial.HAMMER_HEAD.z*.5,7.0),"扩大摆幅保留最低点离地高度")
	print("BUDDY OBSTACLES failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
