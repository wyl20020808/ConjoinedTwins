extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
var checks:=0
var failures:Array=[]
class FullScan:
	extends "res://scripts/journey_run.gd"
	func ground_gaps(time:float=-1.0)->Array[Rect2]:
		var result:Array[Rect2]=[]
		for i in range(kinds.size()):
			if kinds[i]=="road_gap" or (kinds[i]=="collapse" and hazard_sample(i,elapsed if time<0 else time).stage=="collapsed"):
				result.append(obstacles[i])
		return result
	func obstacles_in_bounds(_bounds:Rect2)->Array[int]:
		var result:Array[int]=[]
		for i in range(kinds.size()):result.append(i)
		return result
	func surface_at(point:Vector2,time:float,radius:float=0.0)->Dictionary:
		var surface:={"supported":absf(point.x)<=EDGE,"height":0.0,"normal":Vector3.UP,"friction":0.8,"velocity":Vector3.ZERO}
		for gap in ground_gaps(time):
			if gap.grow(radius).has_point(point):surface.supported=false
		for i in range(kinds.size()):
			if kinds[i] not in Terrain.KINDS:continue
			var sample:=terrain_sample(i,time,point)
			if sample.supported and sample.rect.grow(-radius).has_point(point):surface=sample
		return surface
	func has_ground_support(point:Vector2,time:float=-1.0)->bool:
		return surface_at(point,elapsed if time<0 else time,Motion.RADIUS).supported
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func _initialize()->void:
	for chapter in range(3):
		var fast=Journey.new();var full=FullScan.new()
		for run in [fast,full]:run.level_index=chapter;run.retry()
		for time in [0.0,0.4,3.0]:
			for run in [fast,full]:
				run.elapsed=time
				for gate in run.charge_gates:gate.open=true;gate.opened_at=0.0
				for i in range(run.kinds.size()):
					if run.kinds[i]=="collapse":run.hazard_specs[i].trigger=0.0
			for rect:Rect2 in fast.obstacles:
				for point:Vector2 in [rect.position,rect.end,rect.get_center(),rect.position-Vector2.ONE*16,rect.end+Vector2.ONE*16]:
					check(fast.surface_at(point,time)==full.surface_at(point,time),"地形高度、摩擦、速度和支撑与全量查询一致")
					check(fast.has_ground_support(point,time)==full.has_ground_support(point,time),"脚底边缘和动态桥面支撑一致")
				var bounds:=rect.grow(100)
				var candidates:Array=fast.obstacles_in_bounds(bounds)
				for i in range(fast.kinds.size()):
					var envelope:Rect2=fast.obstacles[i]
					if fast.kinds[i] in fast.Industrial.KINDS:envelope=fast.Industrial.motion_envelope(fast.kinds[i],envelope,fast.hazard_specs[i])
					if bounds.intersects(envelope,true):check(candidates.has(i),"空间筛选保留所有相交包络")
		# 当前、将来和过去的地面查询交错，重用分桶不能污染其他时刻。
		for run in [fast,full]:run.elapsed=0.0
		for query_time in [0.0,3.0,0.4,0.0,3.0]:
			check(fast.ground_gaps(query_time)==full.ground_gaps(query_time),"混合预测时刻缺口与无缓存全量查询一致")
			for rect:Rect2 in full.obstacles:
				check(fast.surface_at(rect.get_center(),query_time)==full.surface_at(rect.get_center(),query_time),"复用分桶保留各时刻塌陷支撑")
		# 保持事件、输入、动作、绳索与存档语义；不是仅比较优化函数自身。
		for run in [fast,full]:run.retry();run.state="running";run.clear_input=false
		for frame in range(180):
			for run in [fast,full]:run.step(run.FIXED_STEP,Vector2(sin(frame*.13),1),Vector2(-sin(frame*.13),1),frame%45==0,frame%51==0)
			check(fast.sync_hash()==full.sync_hash(),"完整固定步状态与全量扫描相同")
		check(fast.state=="running","等价测试必须仍在运行")
		fast.capture_checkpoint();fast.state="failed";check(fast.restore_checkpoint(),"读档可恢复")
		check(fast.obstacle_bin_epoch==-INF and fast.terrain_index_epoch==-INF,"读档使派生空间缓存失效")
		fast.retry();check(fast.obstacle_bin_epoch==-INF,"重试使空间缓存失效")
		fast.dispose();full.dispose()
	print("JOURNEY_SPATIAL_REGRESSION checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
