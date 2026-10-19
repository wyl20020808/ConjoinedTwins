extends RefCounted
# 平均 12 米主节拍搭配前置地形组合；共享安全走廊，门前后保留操作空间。
const RandomLayout=preload("res://scripts/journey_random.gd")
const STEP:=240.0
const REUSED:=["sweeper","hammer","press","steam","shuttle","piston","lift","slope","steps","tilt"]
const RIDGE:=["rail","pillar","cargo","road_gap","active_spikes","rail","collapse","pillar"]
const FOREST:=["rail","pillar","tree","road_gap","collapse","boar","rail","swing","pillar","tree","active_spikes","boar"]
const VILLAGE:=["cargo","stone","rail","cart","pillar","active_spikes","road_gap","swing","collapse","stone","rail","pillar"]
const MID_GATES:=[
	[4800.0,false,"ridge_lock","石门供能 · 分侧拉紧连线",false],
	[12000.0,true,"forest_bridge","林间木桥 · 双板放桥",true],
	[18400.0,false,"forest_relay","古树接力门 · 一人守板一人过门",false],
	[24000.0,false,"village_supply","村口闸门 · 连线供能",false],
	[31200.0,true,"village_yard","院落防线 · 双板开门",false]
]
static func build(run)->void:
	var layout=RandomLayout.new(run.seed_value,run.level_index,1)
	var finish:float=run.finish_distance()
	if run.level_index==0:
		for entry in MID_GATES:
			if entry[2].ends_with("relay"):
				run.add_relay(entry[0],layout.draw("relay_side",[-1.0,1.0]),entry[2]);run.charge_gates[-1].title=entry[3]
				continue
			run.add_gate(entry[0],entry[1],entry[2]);run.charge_gates[-1].title=entry[3]
			if entry[4]:bridge(run,run.charge_gates[-1])
	# 后续章节保留地域，但同样增加途中合作站，不把机关都堆到终点。
	else:
		for ratio in [.22,.48,.73]:
			if ratio==.73:
				run.add_relay(finish*ratio,layout.draw("relay_side",[-1.0,1.0]),"route_relay")
				continue
			run.add_gate(finish*ratio,ratio==.48,"route_%d"%int(ratio*100))
	run.add_gate(finish-1900,false,"waterwheel")
	run.add_gate(finish-1000,true,"drawbridge")
	bridge(run,run.charge_gates[-1])
	var routes:={}
	var small_beats:Array=[]
	var route_number:=0
	for group in range(2,int(finish/720)-1):
		if group%5!=2:continue
		var start:float=group*720+160
		if run.charge_gates.any(func(g):return start-200<=g.receiver.y+840 and start+700>=g.receiver.y-960):continue
		var shape:int=layout.draw("narrow",[0,1,2,3])
		var lanes:Array=[0.0] if shape==0 else ([layout.draw("edge",[-245.0,245.0])] if shape==1 else ([-55.0,55.0] if shape==2 else [-66.0,0.0,66.0]))
		routes[group]={"lanes":lanes,"start":start,"end":start+440,"shape":["center_path","edge_path","twin_paths","triple_paths"][shape]}
		route_number+=1
	var group_sides:={}
	# 双人机关按每 10 组的节奏"到期"（第 4 组跳绳杆、第 6 组木桶、第 9 组颜色门），
	# 落在之后第一个可用的第三拍；遇到合作门留空区或窄路组时顺延，不因节奏撞车而整章缺失。
	var due:Array=[]
	for n in range(1,int(finish/STEP)):
		if n%3==0:
			match int(n/3)%10:
				4:due.append("jump_bar")
				6:due.append("barrel")
				9:due.append("color_gate")
		# 同侧三拍成组加密，组间留 20 米换侧；平均节拍仍为 12 米。
		# 400 / 80 / 240 单位的节奏允许两人和完整短绳先退出旧侧机关。
		var y:=n*STEP+(160.0 if n%3==0 else 0.0)
		# 只扰动组内中拍；组间换侧空地与窄路入口保持原有安全包络。
		if n%3==1:y+=float(layout.draw("spacing",[-18.0,-9.0,0.0,9.0,18.0]))
		# 前后留站位与退出空间；这些路段的交互目标是合作门及其桥面。
		# 按整组地形的前后包络留出到达、横移和离桥空间，不能只检查机关中心。
		if run.charge_gates.any(func(g):return y>=g.receiver.y-960 and y<=g.receiver.y+840):continue
		var theme:String=run.theme_at(y)
		var kinds:Array=FOREST if theme in ["forest","broken","edge","meadow","river"] else (RIDGE if theme in ["ridge","ruins","mine"] else VILLAGE)
		# 三个节拍共用同侧安全走廊，组间允许换侧，避免密集机关强迫瞬间横穿整条路。
		var group:=int(n/3)
		if not group_sides.has(group):group_sides[group]=layout.draw("side",[-1.0,-1.0,1.0,1.0])
		var blocked:float=group_sides[group]
		if routes.has(int(n/3)):
			var route:Dictionary=routes[int(n/3)]
			run.encounter_markers.append({"y":y,"kind":route.shape,"blocked":blocked,"formation":true,"lanes":route.lanes,"narrow_start":route.start,"narrow_end":route.end})
			if n%3==0:narrow_terrain(run,route)
			continue
		# 双人机关占用组内第三拍（原双滚球拍），迎面一波所在的中拍保持原样，各类迎面物频率不变。
		# 跳绳杆与颜色门独占该拍，不叠加阵型、滚球与小型陷阱；木桶只替换该拍的双滚球。
		var special:String=due[0] if n%3==2 and n>3 and not due.is_empty() else ""
		if special in ["jump_bar","color_gate"]:
			due.pop_front()
			if special=="jump_bar":jump_bar(run,y,layout)
			else:color_gate(run,y,layout)
			run.encounter_markers.append({"y":y,"kind":special,"blocked":blocked,"formation":false})
			continue
		# 窄路替换的拍子不消费机关配额，完整章节仍覆盖所有共享机关。
		var kind:String=layout.draw("reused",REUSED) if n%3==0 else layout.draw("theme:"+theme,kinds)
		run.encounter_markers.append({"y":y,"kind":kind,"blocked":blocked,"formation":n>2})
		if n>2: formation(run,n,y,blocked,layout.draw("formation",[0,1,2,3]))
		if n%3!=0 and n>3:small_beats.append([n,y,blocked])
		if n%3==1 and n>3: moving_wave(run,n,y,blocked,layout.draw("wave",["drone","fly_body","stone_ball","fly_low","iron_ball","rocket"]))
		if n%3==2 and n>3:
			if special=="barrel":
				due.pop_front()
				moving_wave(run,n,y,blocked,"barrel")
			else:rolling_pair(run,n,y,blocked,layout.draw("pair",["stone_ball","iron_ball"]))
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
			# 长缓坡、低石阶、侧倾石脊按配比洗牌，保留相同的实体支撑采样。
			run.hazard_specs[index].amplitude=layout.draw("amplitude",[16.0,24.0,28.0])
			run.hazard_specs[index].period=3.2
		if kind=="collapse":run.hazard_specs[index].grace=2.8
		if kind=="active_spikes":run.hazard_specs[index].phase=float(layout.draw("spike_phase",[0,.7,1.4,2.1]))
		# 换侧首拍先整理站位，金币放在同侧后续节拍，密集地图仍遵守奖励池上限。
		if n%3!=0:
			run.rewards.append({"id":"beat:%d:0"%n,"kind":"coin","position":Vector2(-blocked*220,y-65),"radius":22.0,"claimed":false})
	ground_mechanisms(run)
	for beat in small_beats:small_hazards(run,beat[0],beat[1],beat[2],layout)
	for zone in range(6):
		var y:=zone*finish/6+400
		run.rewards.append({"id":"shield:%d"%zone,"kind":"shield","position":Vector2(0,y),"radius":28.0,"claimed":false})
	# 旅程有限，奖励集合也有明确上界，不沿用旧随机路段的小型池截断地图。
	run.select_charge_gate();run.revision+=1

# 后一节拍的缺口可能向前侵入上一机关。生成完成后按全部实体底座切分缺口，
# 给底座保留贯通两岸的实心路基，而不是给悬空机关补一块孤立空气地板。
# 此时还未建立空间索引、运行碰撞或视图；同步更新所有障碍数组。
static func ground_mechanisms(run)->void:
	var supports:Array[Rect2]=[]
	for i in range(run.kinds.size()):
		if run.kinds[i] in ["road_gap","drawbridge","ferry","drone"] or run.hazard_specs[i].get("front",false):continue
		supports.append(run.obstacles[i].grow(8))
	var additions:Array[Rect2]=[]
	for i in range(run.kinds.size()-1,-1,-1):
		if run.kinds[i]!="road_gap":continue
		var pieces:Array[Rect2]=[run.obstacles[i]]
		for support:Rect2 in supports:
			var next:Array[Rect2]=[]
			for piece:Rect2 in pieces:
				if not piece.intersects(support):next.append(piece);continue
				if support.position.y>piece.position.y:
					next.append(Rect2(piece.position,Vector2(piece.size.x,support.position.y-piece.position.y)))
				if support.end.y<piece.end.y:
					next.append(Rect2(Vector2(piece.position.x,support.end.y),Vector2(piece.size.x,piece.end.y-support.end.y)))
			pieces=next
		if pieces.is_empty():
			for array in [run.obstacles,run.kinds,run.obstacle_heights,run.obstacle_ids,run.hazard_specs]:array.remove_at(i)
		else:
			run.obstacles[i]=pieces[0]
			for part in range(1,pieces.size()):additions.append(pieces[part])
	for rect:Rect2 in additions:run.add_hazard("road_gap",rect)

# 真正挖空整幅路面，只留下 2.2 米宽的连续通道；单路必须前后通过。
# 双路间距 5.5 米，三路相邻间距 3.3 米，均可在原绳长内合作。
static func narrow_terrain(run,route:Dictionary)->void:
	var left:float=-run.EDGE
	for center:float in route.lanes:
		if center-22>left:run.add_hazard("road_gap",Rect2(left,route.start,center-22-left,route.end-route.start))
		left=center+22
	if left<run.EDGE:run.add_hazard("road_gap",Rect2(left,route.start,run.EDGE-left,route.end-route.start))

# 小型地刺、矮栏和碎石补充大机关；主通道外缘仍可走，窄桥内不塞障碍。
static func small_hazards(run,n:int,y:float,side:float,layout=null)->void:
	var kinds:Array=layout.shuffled(["active_spikes","rail","cargo"]) if layout!=null else ["active_spikes","rail","cargo"]
	for j in range(3):
		var kind:String=kinds[j]
		# 最后一个小机关的完整身体碰撞包络必须早于 marker.y+110，
		# 防止两人开始整理下一段站位时，仍横穿上一段的尾部危险。
		var center:=Vector2(side*190 if j!=1 else -side*135,y+20+j*25)
		var size:=Vector2(44,28) if kind=="active_spikes" else (Vector2(52,10) if kind=="rail" else Vector2(32,30))
		var rect:=Rect2(center-size/2,size)
		var supported:=true
		for i in range(run.kinds.size()):
			if run.kinds[i] in ["road_gap","collapse"] and run.obstacles[i].intersects(rect.grow(10),true):supported=false;break
		if not supported:continue
		var index:int=run.add_hazard(kind,rect)
		run.hazard_specs[index].small=true
		run.hazard_specs[index].beat_end=y+110
		if kind=="cargo":run.obstacle_heights[index]=14.0
		if kind=="active_spikes":
			run.hazard_specs[index].period=2.4
			run.hazard_specs[index].warning=.65
			run.hazard_specs[index].active=.95
			run.hazard_specs[index].phase=float(layout.draw("small_phase",[0,.6,1.2,1.8])) if layout!=null else float((n+j)%4)*.6

static func narrow_at(run,from_y:float,to_y:float)->Dictionary:
	for marker in run.encounter_markers:
		if marker.has("lanes") and to_y>=marker.narrow_start-200 and from_y<=marker.narrow_end+65:return marker
	return {}

# 每组三拍增加一条可预判的空中/滚动轨迹；沿危险侧进入，保留对侧通道。
static func moving_wave(run,n:int,y:float,side:float,variant:String="")->void:
	var kind:String=variant if not variant.is_empty() else ["drone","fly_body","stone_ball","fly_low","iron_ball","rocket"][int(n/3)%6]
	var size:Vector2=Vector2(64,40) if kind=="drone" else run.Threats.CONFIG[kind].size
	var speed:float=560.0 if kind=="drone" else absf(run.Threats.CONFIG[kind].velocity.y)
	if run.Threats.is_ball(kind):speed=620.0 if kind=="stone_ball" else 700.0
	var index:int=run.add_hazard(kind,Rect2(Vector2(side*210-size.x/2,y+speed+140),size))
	var spec:Dictionary=run.hazard_specs[index]
	spec.start_distance=y-160
	if run.Threats.is_ball(kind) or kind=="barrel":
		spec.velocity=Vector2(0,-speed)
		spec.aim_players=true
	if kind=="drone":
		spec.velocity=Vector2(-side*12,-560)
		spec.warning=.7
	# 迎面威胁继续使用引擎原有的共同换侧预警与连续扫掠判定。
	run.encounter_markers[-1].air_wave=kind

# 同侧错时双滚球，约每 36 米一组；不穿越窄路或合作门，另一侧留完整走廊。
static func rolling_pair(run,n:int,y:float,side:float,variant:String="")->void:
	var kind:String=variant if not variant.is_empty() else ("stone_ball" if n%2==0 else "iron_ball")
	var speed:float=620.0 if kind=="stone_ball" else 700.0
	var size:Vector2=run.Threats.CONFIG[kind].size
	for ball in range(2):
		var rect:=Rect2(Vector2(side*225-size.x/2,y+speed*1.3+ball*180),size)
		var index:int=run.add_hazard(kind,rect)
		run.hazard_specs[index].velocity=Vector2(0,-speed)
		run.hazard_specs[index].start_distance=y-180
		run.hazard_specs[index].warning=1.0
		run.hazard_specs[index].rolling_pair=true
		# 双滚球各自在进入预警时瞄准玩家，后一颗会追向躲开第一颗后的新位置。
		run.hazard_specs[index].aim_players=true

# 专属颜色门：横贯全路的石墙上开两个 70 单位宽的门洞，中间隔 50 单位石墩。
# 青门（role 0）只放 01，橙门（role 1）只放 02；左右随机，站错边的两人需交叉换位。
const COLOR_DOOR_WIDTH:=70.0
const COLOR_DIVIDER:=50.0
static func color_gate(run,y:float,layout)->void:
	var teal_left:bool=layout.draw("color_side",[true,false])
	var depth:=24.0
	var inner:=COLOR_DIVIDER/2
	var outer:=inner+COLOR_DOOR_WIDTH
	for wall in [Rect2(-run.EDGE,y,run.EDGE-outer,depth),Rect2(-inner,y,COLOR_DIVIDER,depth),Rect2(outer,y,run.EDGE-outer,depth)]:
		var index:int=run.add_hazard("cargo",wall)
		run.hazard_specs[index].color_wall=true
	for side in [-1.0,1.0]:
		var role:int=0 if (side<0)==teal_left else 1
		var x0:float=-outer if side<0 else inner
		var index:int=run.add_hazard("color_gate",Rect2(x0,y,COLOR_DOOR_WIDTH,depth))
		run.hazard_specs[index].role=role

# 跳绳木杆：两侧石质转轴，木杆绕横轴旋转；每周期贴地 0.2 秒，之前 0.9 秒为下落预警。
# 伤害顶高 24 单位：起跳后约 0.11–0.49 秒脚下高于木杆，贴地窗口两侧各有约 0.09 秒容错。
static func jump_bar(run,y:float,layout)->void:
	var index:int=run.add_hazard("jump_bar",Rect2(-run.EDGE,y,run.EDGE*2,24))
	var spec:Dictionary=run.hazard_specs[index]
	spec.period=2.4
	spec.warning=0.9
	spec.active=0.2
	spec.phase=float(layout.draw("jump_phase",[0.0,0.6,1.2,1.8]))

static func bridge(run,gate:Dictionary)->void:
	gate.bridge=true
	var y:float=gate.door.position.y+60
	run.add_hazard("road_gap",Rect2(-run.EDGE,y,run.EDGE*2,160))
	var index:int=run.add_hazard("drawbridge",Rect2(-70,y-26,140,212))
	run.hazard_specs[index].gate_id=gate.id

# 每组三个节拍换侧前留出横移空地；组首组合紧邻主机关。
# 其余组合最多前置 7 米，且不得侵占组间横移区；危险边界与真实缺口一致。
# 对侧至少保留 8 米宽的道路，两名角色及短绳能够并肩通过。
static func formation(run,n:int,y:float,blocked:float,variant:int=-1)->void:
	# 次拍前置地形不能侵入组间横移区；含边缘缺口的最前端也保留绳长余量。
	var group_start:float=int(n/3)*3*STEP+150.0
	var start:=maxf(group_start,y-10.0 if n%3==0 else y-140.0)
	match n%4 if variant<0 else variant:
		0,1:
			# 组首没有足够的前置空间，不能把主机关所在的地面一起挖掉。
			if n%3==0:
				run.add_hazard("pillar",Rect2(blocked*265-12,y-8,24,24))
				return
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
