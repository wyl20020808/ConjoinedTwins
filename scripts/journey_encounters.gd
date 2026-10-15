extends RefCounted
# 15 米主节拍搭配前置地形组合；共享安全走廊，门前后保留操作空间。
const STEP:=300.0
const REUSED:=["sweeper","hammer","press","steam","shuttle","piston","lift","slope","steps","tilt"]
const RIDGE:=["rail","pillar","cargo","road_gap","active_spikes","rail","collapse","pillar"]
const FOREST:=["rail","pillar","tree","road_gap","collapse","boar","rail","swing","pillar","tree","active_spikes","boar"]
const VILLAGE:=["cargo","stone","rail","cart","pillar","active_spikes","road_gap","swing","collapse","stone","rail","pillar"]
const MID_GATES:=[
	[4800.0,false,"ridge_lock","石门供能 · 分侧拉紧连线",false],
	[12000.0,true,"forest_bridge","林间木桥 · 双板放桥",true],
	[18400.0,false,"forest_lock","古树林门 · 连接解锁",false],
	[24000.0,false,"village_supply","村口闸门 · 连线供能",false],
	[31200.0,true,"village_yard","院落防线 · 双板开门",false]
]
static func build(run)->void:
	var finish:float=run.finish_distance()
	if run.level_index==0:
		for entry in MID_GATES:
			run.add_gate(entry[0],entry[1],entry[2]);run.charge_gates[-1].title=entry[3]
			if entry[4]:bridge(run,run.charge_gates[-1])
	# 后续章节保留地域，但同样增加途中合作站，不把机关都堆到终点。
	else:
		for ratio in [.22,.48,.73]:
			run.add_gate(finish*ratio,ratio==.48,"route_%d"%int(ratio*100))
	run.add_gate(finish-1900,false,"waterwheel")
	run.add_gate(finish-1000,true,"drawbridge")
	bridge(run,run.charge_gates[-1])
	for n in range(1,int(finish/STEP)):
		var y:=n*STEP
		# 前后留站位与退出空间；这些路段的交互目标是合作门及其桥面。
		if run.charge_gates.any(func(g):return y>g.receiver.y-680 and y<g.receiver.y+720):continue
		var theme:String=run.theme_at(y)
		var kinds:Array=FOREST if theme in ["forest","broken","edge","meadow","river"] else (RIDGE if theme in ["ridge","ruins","mine"] else VILLAGE)
		var kind:String=kinds[n%kinds.size()]
		if n%3==0:kind=REUSED[int(n/3)%REUSED.size()]
		if run.level_index==0 and n==72:kind="sweeper"
		if theme in ["village","farm","facility"] and n%12==5:kind="cart"
		# 三个节拍共用同侧安全走廊，组间再换侧，避免密集机关强迫瞬间横穿整条路。
		var blocked:float=-1.0 if int(n/3)%2==0 else 1.0
		run.encounter_markers.append({"y":y,"kind":kind,"blocked":blocked,"formation":n>2})
		if n>2: formation(run,n,y,blocked)
		if kind in ["tree","boar","stone","cart","swing"]:
			run.add_event(kind,y,blocked)
			continue
		var rect:=Rect2(Vector2(blocked*120-100,y),Vector2(200,24))
		match kind:
			"sweeper":rect=Rect2(blocked*120-5,y,10,10)
			"hammer":rect=Rect2(blocked*75-26,y,52,44)
			"press","steam","piston":rect=Rect2(blocked*120-70,y,140,60)
			"shuttle":rect=Rect2(blocked*130-35,y,70,45)
			"lift","slope","steps","tilt":rect=Rect2(blocked*140-65,y,130,160)
			"pillar":rect=Rect2(blocked*95-12,y,24,24)
			"cargo":rect=Rect2(blocked*130-55,y,110,70)
			"road_gap":rect=Rect2(blocked*220-70,y,140,95)
			"collapse":rect=Rect2(blocked*120-120,y,240,70)
			"rail":rect.size.y=12
			"active_spikes":rect.size.y=30
		var index:int=run.add_hazard(kind,rect)
		if kind in run.Industrial.KINDS:
			run.hazard_specs[index].start_distance=y-620
			run.hazard_specs[index].side=blocked
		if kind in run.Terrain.KINDS:
			run.hazard_specs[index].amplitude=28.0
			run.hazard_specs[index].period=3.2
		if kind=="collapse":run.hazard_specs[index].grace=2.8
		if kind=="active_spikes":run.hazard_specs[index].phase=float(n%4)*.7
		for k in range(1):
			run.rewards.append({"id":"beat:%d:%d"%[n,k],"kind":"coin","position":Vector2(-blocked*220,y-65+k*45),"radius":22.0,"claimed":false})
	for zone in range(6):
		var y:=zone*finish/6+400
		run.rewards.append({"id":"shield:%d"%zone,"kind":"shield","position":Vector2(0,y),"radius":28.0,"claimed":false})
	# 旅程有限，奖励集合也有明确上界，不沿用旧随机路段的小型池截断地图。
	run.select_charge_gate();run.revision+=1

static func bridge(run,gate:Dictionary)->void:
	var y:float=gate.door.position.y+60
	run.add_hazard("road_gap",Rect2(-run.EDGE,y,run.EDGE*2,160))
	var index:int=run.add_hazard("drawbridge",Rect2(-70,y-26,140,212))
	run.hazard_specs[index].gate_id=gate.id

# 每组三个节拍换侧前留出横移空地；组首组合紧邻主机关。
# 其余组合位于主机关前方 7 米，危险边界与真实缺口一致。
# 对侧至少保留 8 米宽的道路，两名角色及短绳能够并肩通过。
static func formation(run,n:int,y:float,blocked:float)->void:
	var start:=y-10.0 if n%3==0 else y-140.0
	match n%4:
		0,1:
			var left:float=-run.EDGE if blocked<0 else -70.0
			run.add_hazard("road_gap",Rect2(left,start,run.EDGE+70.0,80))
			# 同侧崖沿再向前错开一块缺口，形成阶梯状断面；安全侧保持连续。
			var edge:float=-run.EDGE if blocked<0 else run.EDGE-70
			run.add_hazard("road_gap",Rect2(edge,start-35,70,55))
		2:
			run.add_hazard("cargo",Rect2(blocked*145-38,start,76,55))
			run.add_hazard("pillar",Rect2(blocked*265-16,start+30,32,32))
		3:
			var index:int=run.add_hazard("steps",Rect2(blocked*155-65,start,130,85))
			run.hazard_specs[index].amplitude=24.0
			run.add_hazard("rail",Rect2(blocked*170-110,start+95,220,12))
