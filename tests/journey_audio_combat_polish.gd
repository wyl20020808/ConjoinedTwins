extends SceneTree
# 本轮试玩反馈的逻辑回归：弹药箱补全部枪、倒树靠近才倒、吊桥快速采样与父类一致、怪物潮整体压上。
const Journey=preload("res://scripts/journey_run.gd")
const Terrain=preload("res://scripts/road_terrain.gd")
var failures:Array=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func _initialize()->void:call_deferred("verify")
func verify()->void:
	ammo_refills_both_guns()
	tree_waits_for_players()
	drawbridge_sample_matches_parent()
	horde_wakes_together()
	print("JOURNEY AUDIO COMBAT POLISH failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func isolated():
	var run=Journey.new()
	run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear();run.journey_events.clear();run.charge_gates.clear();run.select_charge_gate()
	run.combat=run.Combat.fresh()
	run.a.position=Vector2(-30,300);run.b.position=Vector2(30,300)
	run.rope.reset(run.a.position,run.b.position)
	run.clear_input=false;run.state="running"
	return run

func ammo_refills_both_guns()->void:
	var run=isolated()
	var held:Dictionary=run.Combat.gun("smg");held.reserve=0
	var spare:Dictionary=run.Combat.gun("shotgun");spare.reserve=0
	run.combat.weapons[0]=held;run.combat.backups[0]=spare
	run.Combat.add_pickup(run,"ammo",run.a.position)
	run.Combat.collect(run,[run.a.position,run.b.position])
	check(held.reserve==run.Combat.WEAPONS.smg.ammo_pickup,"弹药箱补手上的枪")
	check(spare.reserve==run.Combat.WEAPONS.shotgun.ammo_pickup,"弹药箱同时补背上的枪")
	# 手上的枪满了、背上的没满，仍可拾取。
	held.reserve=run.Combat.WEAPONS.smg.max_reserve;spare.reserve=0
	run.Combat.add_pickup(run,"ammo",run.a.position)
	run.Combat.collect(run,[run.a.position,run.b.position])
	check(run.combat.pickups.is_empty() and spare.reserve>0,"只有背上的枪缺弹也能拾取")
	run.dispose()

func tree_waits_for_players()->void:
	var run=isolated()
	run.add_event("tree",1200,1)
	var event:Dictionary=run.journey_events[0]
	run.advance_events(run.FIXED_STEP)
	check(event.trigger<0,"倒树在 45 米外不提前触发")
	run.a.position.y=1200-run.TREE_TRIGGER+5;run.b.position.y=run.a.position.y
	run.advance_events(run.FIXED_STEP)
	check(event.trigger>=0 and event.phase=="warning","玩家走近后才开始预警")
	run.elapsed=event.trigger+run.TREE_WARNING+0.1
	run.advance_events(run.FIXED_STEP)
	check(event.phase=="falling","预警结束后倒下")
	run.dispose()

func drawbridge_sample_matches_parent()->void:
	var run=isolated()
	run.add_gate(1000,true,"bridge_test")
	run.Encounters.bridge(run,run.charge_gates[-1])
	var gate:Dictionary=run.charge_gates[-1]
	var index:int=run.kinds.find("drawbridge")
	var rect:Rect2=run.obstacles[index]
	for opened in [false,true]:
		gate.open=opened;gate.opened_at=2.0 if opened else -1.0
		for time in [1.0,2.1,2.3,2.59,2.61,5.0]:
			for point in [rect.get_center(),rect.position-Vector2(5,5),rect.end-Vector2(1,1)]:
				var fast:Dictionary=run.terrain_sample(index,time,point)
				var spec:Dictionary=run.hazard_specs[index].duplicate()
				spec.opening=clampf((time-2.0)/0.6,0,1) if opened else 0.0
				var slow:Dictionary=Terrain.sample("drawbridge",rect,spec,time,point)
				check(fast.supported==slow.supported and is_equal_approx(fast.height,slow.height) and fast.rect==slow.rect,"吊桥快速采样一致 open=%s t=%s"%[opened,time])
	run.dispose()

func horde_wakes_together()->void:
	var run=Journey.new();run.level_index=0;run.retry();run.state="running"
	var arena:Dictionary=run.arenas[0]
	var members:Array=run.journey_events.filter(func(e):return e.kind=="monster" and e.has("horde") and e.horde==arena.start)
	check(members.size()>=27,"怪物潮专区三波共 %d 只"%members.size())
	var ammo:Array=run.combat.pickups.filter(func(p):return p.kind=="ammo" and p.position.y>=arena.start and p.position.y<arena.end)
	check(ammo.size()>=7,"专区弹药补给 %d 箱"%ammo.size())
	var y:float=arena.start+run.Monsters.HORDE_ENTRY+20
	run.a.position=Vector2(-30,y);run.b.position=Vector2(30,y);run.distance=y
	var rear:Dictionary=members.reduce(func(best,e):return e if e.y>best.y else best,members[0])
	var start:Vector2=rear.origin
	for frame in range(120):run.advance_events(run.FIXED_STEP);run.elapsed+=run.FIXED_STEP
	check(rear.alert and rear.origin.y<start.y-20,"最后一波也一起压上来 %s -> %s"%[start,rear.origin])
	run.dispose()
