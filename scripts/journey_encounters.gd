extends RefCounted
# 平均 12 米主节拍搭配前置地形组合；共享安全走廊，门前后保留操作空间。
const RandomLayout=preload("res://scripts/journey_random.gd")
const Boss=preload("res://scripts/journey_boss.gd")
const STEP:=240.0
const REUSED:=["sweeper","hammer","press","steam","shuttle","piston","lift","slope","steps","tilt"]
# 主节拍只放会动的机关：原矮木栏、立柱、巨岩等静态占位改为往复撞石、摆锤、扫杆、活塞等动态机关。
const RIDGE:=["shuttle","hammer","sweeper","road_gap","active_spikes","shuttle","collapse","piston"]
const FOREST:=["shuttle","hammer","tree","road_gap","collapse","boar","shuttle","swing","sweeper","tree","active_spikes","boar"]
const VILLAGE:=["sweeper","stone","shuttle","cart","hammer","active_spikes","road_gap","swing","collapse","stone","shuttle","piston"]
# 飞行波次：组首拍（工业机关拍）额外加一波空中来袭，与中拍迎面波次错开。
const AIR:=["drone","fly_body","fly_low","rocket"]
const MID_GATES:=[
	[4800.0,false,"ridge_lock","石门供能 · 分侧拉紧连线",false],
	[12000.0,true,"forest_bridge","林间木桥 · 双板放桥",true],
	[18400.0,false,"forest_relay","古树接力门 · 一人守板一人过门",false],
	[24000.0,false,"village_supply","村口闸门 · 连线供能",false],
	[31200.0,true,"village_yard","院落防线 · 双板开门",false]
]
# 怪物潮专区：在组边界插入 120 米无机关空地，机关段只保留零星小队。
# 机关按原节奏在"基准坐标"中生成，再把切口之后的全部实体整体后移，机关数量不变。
const ARENA:=2400.0
const ARENA_GROUPS:=[[13,21,31,40],[11,24,33],[11,24,33]]
static func cuts(run)->Array:
	var result:Array=[]
	for group in ARENA_GROUPS[mini(run.level_index,ARENA_GROUPS.size()-1)]:result.append(group*720.0)
	return result
static func shift_at(cut_list:Array,y:float)->float:
	var shift:=0.0
	for cut in cut_list:
		if y>=cut:shift+=ARENA
	return shift

static func build(run)->void:
	var layout=RandomLayout.new(run.seed_value,run.level_index,1)
	var cut_list:=cuts(run)
	# 基准长度不含专区；地域主题、终点与护盾按真实坐标计算。
	# 有 Boss 的章节末尾留出 Boss 场地，机关、合作门与怪物都在场地之前结束。
	# 额外 400 单位让最后一拍的地形组合（最长 160）与入口留白都落在场地之外。
	var boss_arena:float=Boss.ARENA+400.0 if Boss.enabled(run) else 0.0
	var finish:float=run.finish_distance()-cut_list.size()*ARENA-boss_arena
	var real:=func(y:float)->float:return y+shift_at(cut_list,y)
	var anchors:Array=[]
	var tag:=func(y:float)->void:
		while anchors.size()<run.kinds.size():anchors.append(y)
	run.arenas.clear();run.pack_slots.clear()
	if run.level_index==0:
		for entry in MID_GATES:
			if entry[2].ends_with("relay"):
				run.add_relay(entry[0],layout.draw("relay_side",[-1.0,1.0]),entry[2]);run.charge_gates[-1].title=entry[3]
				continue
			run.add_gate(entry[0],entry[1],entry[2]);run.charge_gates[-1].title=entry[3]
			if entry[4]:bridge(run,run.charge_gates[-1])
			tag.call(entry[0])
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
	tag.call(finish-1000)
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
	var pending:=0.0
	for n in range(1,int(finish/STEP)):
		# 上一拍生成的实体全部记到该拍的锚点，后移时整拍一起移动，不会被切口拆开。
		tag.call(pending)
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
		pending=y
		var theme:String=run.theme_at(real.call(y))
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
		# 往复撞石横扫整条路，扫掠线上不再摆立柱、巨岩等阵型件，免得撞石穿模。
		if n>2 and kind!="shuttle": formation(run,n,y,blocked,layout.draw("formation",[0,1,2,3]))
		if n%3!=0 and n>3:small_beats.append([n,y,blocked])
		if n%3==1 and n>3: moving_wave(run,n,y,blocked,layout.draw("wave",["drone","fly_body","stone_ball","fly_low","iron_ball","rocket"]))
		# 横贯全路的往复撞石已经占满整条路，不再叠加空中波次。
		if n%3==0 and n>3 and kind!="shuttle": moving_wave(run,n,y,blocked,layout.draw("air",AIR))
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
			"shuttle":rect=Rect2(-SHUTTLE_WIDTH/2,y,SHUTTLE_WIDTH,45)
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
		if kind=="shuttle":
			# 往复撞石从路中出发，横扫覆盖整条路面，两人需要看准撞石离开再通过。
			run.hazard_specs[index].reach=run.EDGE-SHUTTLE_WIDTH/2
			run.hazard_specs[index].period=SHUTTLE_PERIOD
			run.hazard_specs[index].phase=float(layout.draw("shuttle_phase",[0.0,.9,1.8,2.7]))
		if kind=="active_spikes":run.hazard_specs[index].phase=float(layout.draw("spike_phase",[0,.7,1.4,2.1]))
		# 换侧首拍先整理站位，金币放在同侧后续节拍，密集地图仍遵守奖励池上限。
		if n%3!=0:
			run.rewards.append({"id":"beat:%d:0"%n,"kind":"coin","position":Vector2(-blocked*220,y-65),"radius":22.0,"claimed":false})
	tag.call(pending)
	# 机关段之间的零星小队：每隔一组放在组间换侧空地，靠近合作门或专区的组跳过。
	for group in range(2,int(finish/720)):
		if group%2!=0 or group*720.0 in cut_list:continue
		var slot:=group*720.0-50
		if run.charge_gates.any(func(g):return absf(slot-g.receiver.y)<900):continue
		run.pack_slots.append(real.call(slot))
	shift_layout(run,cut_list,anchors)
	for index in range(cut_list.size()):
		var start:float=cut_list[index]+index*ARENA
		run.arenas.append({"start":start,"end":start+ARENA})
		# 专区中线标记：保持遭遇覆盖与换侧留白，危险侧为 0，两人走中路。
		for y in range(int(start)+160,int(start+ARENA),400):
			run.encounter_markers.append({"y":float(y),"kind":"arena","blocked":0.0,"formation":false})
	# Boss 场地（含入口前留白）本身就是本段遭遇：同样按 400 单位登记中线标记。
	if boss_arena>0.0:
		for y in range(int(run.finish_distance()-boss_arena)+160,int(run.finish_distance()),400):
			run.encounter_markers.append({"y":float(y),"kind":"boss","blocked":0.0,"formation":false})
	run.encounter_markers.sort_custom(func(p,q):return p.y<q.y)
	ground_mechanisms(run)
	for beat in small_beats:small_hazards(run,beat[0],real.call(beat[1]),beat[2],layout)
	for zone in range(6):
		var y:float=zone*run.finish_distance()/6+400
		run.rewards.append({"id":"shield:%d"%zone,"kind":"shield","position":Vector2(0,y),"radius":28.0,"claimed":false})
	# 旅程有限，奖励集合也有明确上界，不沿用旧随机路段的小型池截断地图。
	run.select_charge_gate();run.revision+=1

# 把基准坐标中切口之后的实体整体后移一个专区长度。障碍按所属节拍的锚点判断，
# 迎面滚球、无人机等起点在前方的实体与其触发距离一起移动。
static func shift_layout(run,cut_list:Array,anchors:Array)->void:
	if cut_list.is_empty():return
	for i in range(run.obstacles.size()):
		var shift:=shift_at(cut_list,anchors[i])
		if shift==0.0:continue
		run.obstacles[i].position.y+=shift
		var spec:Dictionary=run.hazard_specs[i]
		# 地形默认触发距离为 0（始终有效）；只移动显式设定的触发点。
		if spec.get("start_distance",0.0)>0.0:spec.start_distance+=shift
	for gate in run.charge_gates:
		var shift:=shift_at(cut_list,gate.receiver.y)
		if shift==0.0:continue
		gate.receiver.y+=shift
		for key in ["left","right","door","near","far"]:
			if gate.has(key):gate[key].position.y+=shift
	for marker in run.encounter_markers:
		var shift:=shift_at(cut_list,marker.y)
		marker.y+=shift
		if marker.has("narrow_start"):
			marker.narrow_start+=shift;marker.narrow_end+=shift
	for event in run.journey_events:
		var shift:=shift_at(cut_list,event.y)
		if shift==0.0:continue
		event.y+=shift
		for key in ["rect","previous","sample"]:event[key].position.y+=shift
		if event.has("base"):event.base.y+=shift
	for reward in run.rewards:reward.position.y+=shift_at(cut_list,reward.position.y)

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

const SHUTTLE_WIDTH:=90.0
const SHUTTLE_PERIOD:=3.6
# 小型地刺补充大机关；主通道外缘仍可走，窄桥内不塞障碍。
# 小机关在危险侧排成一行（固定列），与主机关、倒树等事件重叠时换到下一列或后一排，
# 不再零散斜排；危险侧放不下时才退到对侧内缘，数量不因避让而减少。
const SMALL_COLUMNS:=[250.0,165.0,80.0,0.0,-135.0]
const SMALL_ROWS:=[40.0,70.0]
static func small_hazards(run,n:int,y:float,side:float,layout=null)->void:
	var kinds:Array=layout.shuffled(["active_spikes","rail","cargo"]) if layout!=null else ["active_spikes","rail","cargo"]
	var blockers:Array[Rect2]=[]
	var area:=Rect2(-run.EDGE,y-40,run.EDGE*2,170)
	for i in range(run.kinds.size()):
		# 迎面滚动/飞行物会离开原位，不占用固定列；工业机关的 velocity 是摆动参数，仍算占位。
		var spec:Dictionary=run.hazard_specs[i]
		if run.kinds[i]=="drone" or (spec.has("velocity") and not spec.get("industrial",false)) or spec.get("front",false):continue
		# 往复撞石按整条横扫轨迹占位，小地刺不放进撞石的扫掠线。
		var footprint:Rect2=run.obstacles[i].grow_individual(spec.reach,0,spec.reach,0) if run.kinds[i]=="shuttle" and spec.has("reach") else run.obstacles[i]
		if footprint.intersects(area):blockers.append(footprint.grow(8))
	for event in run.journey_events:
		if event.kind!="monster" and event.rect.intersects(area):blockers.append(event.rect.grow(8))
	for j in range(3):
		var kind:String=kinds[j]
		# 碎石块读起来像悬空的土块，试玩反馈要求去掉；原位改为贴地的活动地刺，
		# 保留洗牌次序与小机关密度。
		# 矮木栏同样是静态占位，试玩反馈要求只保留会动的机关。
		if kind in ["cargo","rail"]:kind="active_spikes"
		# 最后一个小机关的完整身体碰撞包络必须早于 marker.y+110，
		# 防止两人开始整理下一段站位时，仍横穿上一段的尾部危险。
		var size:=Vector2(44,28) if kind=="active_spikes" else Vector2(52,10)
		var rect:=Rect2()
		var found:=false
		for row in SMALL_ROWS:
			for column in SMALL_COLUMNS:
				rect=Rect2(Vector2(side*column,y+row)-size/2,size)
				if blockers.any(func(b):return b.intersects(rect)):continue
				var supported:=true
				for i in range(run.kinds.size()):
					if run.kinds[i] in ["road_gap","collapse"] and run.obstacles[i].intersects(rect.grow(10),true):supported=false;break
				if supported:found=true;break
			if found:break
		if not found:continue
		blockers.append(rect.grow(8))
		var index:int=run.add_hazard(kind,rect)
		run.hazard_specs[index].small=true
		run.hazard_specs[index].beat_end=y+110
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
		# 中间隔墩是矮石座加能量帘：挡身体，不挡绳索，两人各过一门时绳子从帘中穿过。
		if wall.position.x==-inner:run.hazard_specs[index].rope_passable=true
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
