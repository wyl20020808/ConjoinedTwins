extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
const Landscape=preload("res://scripts/journey_landscape.gd")
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize()->void:
	for chapter in range(3):
		var run=Journey.new();run.level_index=chapter;run.retry()
		var all_kinds:={}
		for marker in run.encounter_markers:all_kinds[marker.kind]=true
		check(run.encounter_markers.size()>=45,"at least 45 road encounters")
		check(all_kinds.size()>=13,"at least 13 mechanism/enemy types")
		check(run.charge_gates.size()>2,"cooperation gates distributed through route")
		check(run.rewards.size()<=run.Levels.MAX_REWARDS,"finite bounded reward pool")
		var missing:=0
		# 跑速翻倍后，门前完整机关包络退至 48 米外，门后留 42 米离桥空间。
		# 按与机关相同的 10 米采样余量覆盖合作区域边界，其余区域继续要求相邻机关覆盖。
		for y in range(400,int(run.finish_distance()-400),100):
			var near:bool=run.encounter_markers.any(func(m):return absf(m.y-y)<=200)
			near=near or run.charge_gates.any(func(g):return y>=g.receiver.y-1160 and y<=g.receiver.y+1040)
			if not near:missing+=1
		check(missing==0,"no unaccounted encounter gaps")
		# 缓存只减少重复查询，与父类完整几何求值逐项一致。
		for seconds in [0.0,3.0,17.0]:
			var expected:Array[Rect2]=[]
			for i in range(run.kinds.size()):
				if run.kinds[i]=="road_gap" or (run.kinds[i]=="collapse" and run.hazard_sample(i,seconds).stage=="collapsed"):expected.append(run.obstacles[i])
			check(run.ground_gaps(seconds)==expected,"all ground gaps preserved")
		for seconds in [0.0,1.4,3.5]:
			for i in range(run.kinds.size()):
				if run.kinds[i] not in run.Terrain.KINDS:continue
				for point in [run.obstacles[i].get_center(),run.obstacles[i].position-Vector2(5,5)]:
					var expected:={"supported":absf(point.x)<=run.EDGE,"height":0.0,"normal":Vector3.UP,"friction":0.8,"velocity":Vector3.ZERO}
					for gap in run.ground_gaps(seconds):
						if gap.has_point(point):expected.supported=false
					for j in range(run.kinds.size()):
						if run.kinds[j] not in run.Terrain.KINDS:continue
						var sample:Dictionary=run.terrain_sample(j,seconds,point)
						if sample.supported and sample.rect.has_point(point):expected=sample
					check(run.surface_at(point,seconds)==expected,"indexed surface identical to complete scan")
		print("DENSITY LAYOUT chapter=",chapter," encounters=",run.encounter_markers.size()," types=",all_kinds.keys()," gates=",run.charge_gates.size())
		run.dispose()
	check(Landscape.profile(0).x==1 and Landscape.profile(500).y==1 and Landscape.profile(1400).z==1,"original ridge then forest then village")
	for meter in [220.0,320.0,420.0,1020.0,1150.0,1250.0]:
		check(Landscape.profile(meter-.01).distance_to(Landscape.profile(meter+.01))<.001,"smooth biome weights")
		for x in [-140.0,-16.0,16.0,140.0]:check(absf(Landscape.height_at(x,meter-.001,0)-Landscape.height_at(x,meter+.001,0))<.01,"continuous surrounding terrain")
	print("DENSITY CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
