extends SceneTree

const Journey=preload("res://scripts/journey_run.gd")
const NetClient=preload("res://scripts/net_client.gd")
var checks:=0
var failures:=0

class ReferenceRun extends Journey:
	func ground_gaps_in_bounds(_bounds:Rect2,time:float=-1.0)->Array[Rect2]:
		return ground_gaps(time)

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)

func _initialize()->void:call_deferred("verify")

func verify()->void:
	for chapter in range(3):
		var fast=Journey.new();var full=ReferenceRun.new()
		for run in [fast,full]:
			run.random_seed=false;run.seed_value=8123;run.level_index=chapter;run.retry()
		for time in [0.0,0.4,3.0]:
			for run in [fast,full]:
				run.elapsed=time
				for i in range(run.kinds.size()):
					if run.kinds[i]=="collapse":run.hazard_specs[i].trigger=0.0
			for gap in full.ground_gaps(time):
				for point in [gap.position,gap.end,gap.get_center(),gap.position-Vector2.ONE*12]:
					for offset in [Vector2.ZERO,Vector2(30,0),Vector2(0,430)]:
						check(fast.ground_sweep_supported(point,point+offset,time)==full.ground_sweep_supported(point,point+offset,time),"缺口边缘、跨桶路径及塌陷与全量扫掠一致")
			for y in range(0,int(fast.finish_distance()),400):
				for x in [-240.0,0.0,240.0]:
					var point:=Vector2(x,y)
					for offset in [Vector2.ZERO,Vector2(20,120),Vector2(-40,430)]:
						var solids:Array[Rect2]=fast.Monsters.blockers(fast,point,point+offset)
						check(fast.Monsters.clear_path(fast,point,point+offset,solids)==reference_path(fast,point,point+offset,solids),"导航整段支撑快速路径与五点逐段采样一致")
		fast.dispose();full.dispose()
	var pickup_run=Journey.new()
	for y in [50000.0,1000000.0]:
		for extra in [0.0,0.25]:
			pickup_run.combat=pickup_run.Combat.fresh()
			pickup_run.combat.health=[50,50]
			pickup_run.a.position=Vector2(-40,y);pickup_run.b.position=Vector2(40,y)
			pickup_run.Combat.add_pickup(pickup_run,"medkit",Vector2(-40,y+pickup_run.Combat.PICKUP_RADIUS+pickup_run.Motion.RADIUS+extra))
			pickup_run.Combat.collect(pickup_run,[pickup_run.a.position,pickup_run.b.position])
			check(pickup_run.combat.health[0]==(80 if extra==0.0 else 50),"远处坐标拾取半径边界包含、边界外拒绝")
	pickup_run.dispose()
	verify_network_queue()
	print("STUTTER_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func verify_network_queue()->void:
	# 覆盖空队列、稳态和整段追帧：每帧只交付一次，剩余顺序和帧号必须一致。
	for size in [0,1,2,3,4,8,9,30,90]:
		for maximum in [-1,0,1,2,3,8]:
			var net=NetClient.new()
			net.next_frame=100
			for i in range(size):net.frames.append({"index":100+i})
			var taken:Array=net.take_frames(maximum)
			var combined:Array=taken+net.frames
			check(combined.size()==size,"消费前后帧总数守恒")
			for i in range(size):check(combined[i].index==100+i,"消费和剩余帧顺序连续、不丢不重")
			check(net.next_frame==100+taken.size(),"下一帧编号只按实际消费推进")
			if maximum>=0:check(taken.size()<=maximum,"单次消费遵守上限")
			if maximum==0:check(taken.is_empty() and net.frames.size()==size,"零预算不消费队列")
			net.desynced=true
			var remaining:int=net.frames.size()
			check(net.take_frames(8).is_empty() and net.frames.size()==remaining,"不同步时停止消费")
			net.free()

static func reference_path(run, from:Vector2, to:Vector2, solids:Array[Rect2]) -> bool:
	if absf(to.x)>run.EDGE-Journey.Monsters.BODY_RADIUS: return false
	# 寻路网格只查询静止格心。点与矩形按原线段判定的闭区间处理，省去逐轴裁线及插值。
	if from==to:
		for rect in solids:
			if from.x>=rect.position.x and from.x<=rect.end.x and from.y>=rect.position.y and from.y<=rect.end.y:return false
		for offset in Journey.Monsters.FOOT_OFFSETS:
			if not run.has_ground_support(from+offset):return false
		return true
	for rect in solids:
		if run.segment_hits(from,to,rect): return false
	# 间距小于身体半径，覆盖整条行走路径，避免跨过细缺口。
	var steps:=maxi(1,ceili(from.distance_to(to)/12.0))
	# 网格格心的起终点相同时，只检查一次同样的五个脚底采样。
	for n in range(steps+1):
		var point:=from.lerp(to,float(n)/steps)
		for offset in Journey.Monsters.FOOT_OFFSETS:
			if not run.has_ground_support(point+offset): return false
	return true
