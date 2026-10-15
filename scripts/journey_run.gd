extends "res://scripts/road_run.gd"

# 主动前进的连续旅程。位置是固定世界坐标；镜头进度不驱动物理。
const CHAPTERS := [
	{"name":"穿林入村", "length":38400.0, "zones":["原野石板路","森林深处","坍塌林道","林缘与村口","村庄街道","村口防御"], "themes":["ridge","forest","broken","edge","village","village"]},
	{"name":"水车河道", "length":30000.0, "zones":["村外田野","农田小路","河岸渡口","水车栈道","旧桥防线","河谷出口"], "themes":["farm","farm","river","river","village","river"]},
	{"name":"矿道归航", "length":30000.0, "zones":["河谷山路","矿场入口","矿道深处","遗迹回廊","设施防线","归航出口"], "themes":["river","mine","mine","ruins","facility","facility"]}
]
const WALK_SPEED := 160.0
const Combat = preload("res://scripts/journey_combat.gd")
const TRIAL_ZONES := ["拾取与射击","单只冲锋兽","换弹与补给","交替应敌","护盾与医疗","共同抵达"]
var combat: Dictionary = {}
# 模拟默认兼容既有双输入夹具；新生产界面仅向单人入口提供输入。
var solo_control := false
var external_companion := false
var combat_trial := false
const EVENT_NAMES := {"tree":"树木即将倒下：一起离开标记区", "boar":"野猪冲锋：共同避开直线路径", "stone":"村民投掷：离开落点", "cart":"推车横穿：观察轨迹再前进", "swing":"水车摆臂：等待或从侧面通过"}
var terrain_index_signature:=0
var terrain_indices:Array[int]=[]
var ground_gap_cache_time:=-INF
var ground_gap_cache_revision:=-1
var ground_gap_cache:Array[Rect2]=[]
var ground_gap_cache_epoch:=-INF
var ground_gap_queries:={}
var encounter_markers:Array=[]
var journey_events: Array[Dictionary] = []
var visited_zones: Array[int] = []
var region_checkpoint := -1
var event_serial := 0
var last_floor := [0.0,0.0]

func _init() -> void:
	super(false, false)

func speed() -> float:
	return 0.0

func level_speed() -> float:
	return WALK_SPEED

func finish_distance() -> float:
	if combat_trial: return 12240.0
	return CHAPTERS[level_index].length

func update_stream() -> void:
	# 仅跟随落后者的实际前进；无输入时世界和镜头都不推进。
	distance = maxf(distance, minf(a.position.y,b.position.y))
	select_charge_gate()

func bounded(point: Vector2, floor: float = INF) -> Vector2:
	var forward := maxf(point.y,0.0 if is_inf(floor) else floor)
	if charge_gate.get("active",false) and not charge_gate.open:
		var hold: float=charge_gate.receiver.y+(46.0 if charge_gate.get("kind","")=="sync_plates" else 15.0)
		forward=minf(forward,hold)
	return Vector2(clampf(point.x,-EDGE+Motion.RADIUS,EDGE-Motion.RADIUS),forward)

func retry(count_failure: bool = false) -> void:
	ground_gap_cache_time=-INF
	generation_enabled = false
	async_enabled = false
	charge_tutorial = false
	streaming = true
	super(count_failure)
	journey_events.clear()
	encounter_markers.clear()
	visited_zones.clear()
	region_checkpoint = -1
	event_serial = 0
	combat=Combat.fresh()
	if combat_trial: build_combat_trial()
	else:
		build_journey()
		for zone in range(6):
			var start: float=zone*finish_distance()/6.0
			Combat.add_pickup(self,"gun",Vector2(-42,start+200))
			Combat.add_pickup(self,"ammo",Vector2(-42,start+550))
			Combat.add_pickup(self,"medkit",Vector2(0,start+720))
	checkpoint = {}
	update_checkpoint()

func zone_index() -> int:
	return clampi(int(progress()/finish_distance()*6.0),0,5)

func zone_name() -> String:
	if combat_trial: return TRIAL_ZONES[zone_index()]
	return CHAPTERS[level_index].zones[zone_index()]

func theme_at(y: float) -> String:
	if combat_trial: return "forest" if y<finish_distance()*0.6 else "village"
	return CHAPTERS[level_index].themes[clampi(int(y/finish_distance()*6.0),0,5)]

func add_hazard(kind: String, rect: Rect2) -> int:
	var index := kinds.size()
	install_block({"hazards":[{"kind":kind,"rect":rect}],"rewards":[]},0,"journey:%d"%index)
	return index

func add_event(kind: String, y: float, side: float, combined: bool = false) -> void:
	var x := side*125.0
	var width := 240.0 if kind=="tree" else (32.0 if kind=="boar" else (140.0 if kind=="cart" else (80.0 if kind=="swing" else 24.0)))
	var rect := Rect2(x-width/2,y-50 if kind=="tree" else y-35,width,100 if kind=="tree" else 70)
	var index := -1
	if kind=="tree":
		# 倒下之后成为实心树干。砸下阶段另做伤害扫掠。
		index = add_hazard("cargo",Rect2(x-width/2,y-50 if kind=="tree" else y-35,width,100 if kind=="tree" else 70))
		obstacles[index].position.x = EDGE+1000
		obstacle_heights[index] = 52.0
	journey_events.append({"id":event_serial,"kind":kind,"y":y,"side":side,"rect":rect,"trigger":-1.0,"phase":"ready","previous":rect,"sample":rect,"bottom":0.0,"top":60.0,"obstacle":index,"combined":combined,"locked_x":x})
	if kind in ["boar","stone"]:
		journey_events[-1].hp=30 if kind=="boar" else 40
		journey_events[-1].max_hp=journey_events[-1].hp
	event_serial += 1

func add_gate(y: float, plates: bool, suffix: String) -> void:
	var gate := SyncPlates.make_tutorial() if plates else ChargeGate.make_tutorial()
	# 所有站位区延伸至门前，越过中心后仍可侧向修正，无需后退。
	gate.receiver = Vector2(0,y)
	gate.left = Rect2(-71 if plates else -94,y-60,52 if plates else 42,160)
	gate.right = Rect2(19 if plates else 52,y-60,52 if plates else 42,160)
	gate.door = Rect2(-EDGE-20,y+120,EDGE*2+40,12)
	gate.id = suffix
	gate.title = "双人踏板 · 持续站稳" if plates else "连接供能 · 两侧站位拉紧绳索"
	gate.active = true
	gate.open = false
	gate.opened_at = -1.0
	# 同步踏板的两个圆心与供能区保留明确物理语义。
	if plates:
		gate.left = Rect2(-71,y+20,52,52)
		gate.right = Rect2(19,y+20,52,52)
	charge_gates.append(gate)

func build_journey() -> void:
	preload("res://scripts/journey_encounters.gd").build(self)

func fixed_step(input_a: Vector2,input_b: Vector2) -> void:
	input_a.y=maxf(0,input_a.y)
	input_b.y=maxf(0,input_b.y)
	if solo_control and not external_companion: input_b=companion_input(input_a)
	last_floor=[a.position.y,b.position.y]
	var previous := [a.position,b.position]
	advance_events(FIXED_STEP)
	if state!="running": return
	var scale_a: float=Combat.MOVE_SCALE if not combat.weapons[0].is_empty() else 1.0
	var scale_b: float=Combat.MOVE_SCALE if not combat.weapons[1].is_empty() else 1.0
	super(input_a*(WALK_SPEED/LATERAL)*scale_a,input_b*(WALK_SPEED/LATERAL)*scale_b)
	if state!="running": return
	# 任何物理修正也不得把玩家送往身后；父求解器已按本子步 floor 扫掠约束。
	for role in range(2):
		var pos: Vector2 = a.position if role==0 else b.position
		if pos.distance_to(previous[role])<0.001 and heights[role]==0.0: actions[role]="Idle"
	# 运动与实体求解之后开火，死亡敌人不会在同一步继续攻击。
	Combat.tick(self,previous)
	check_event_hits(previous)

func event_sample(event: Dictionary,time: float) -> Dictionary:
	var kind: String=event.kind
	var age: float=time-event.trigger
	var rect: Rect2=event.rect
	var phase := "ready"
	var bottom := 0.0
	var top := 60.0
	if event.trigger>=0:
		phase="warning" if age<2.8 else "active"
		var flight:=maxf(0,age-2.8)
		if kind=="tree":
			phase="warning" if age<2.8 else ("falling" if flight<0.65 else "fallen")
			top=26.0 if phase=="fallen" else 160.0
		elif kind=="boar":
			rect.position.y-=flight*240
			top=34.0
			if flight>4: phase="spent"
		elif kind=="cart":
			rect=Rect2(Vector2(-event.side*440+event.side*220*flight,event.y-25),Vector2(140,50))
			top=64.0
			if flight>4.5: phase="spent"
		elif kind=="stone":
			rect=Rect2(event.locked_x-12,event.y-12,24,24)
			bottom=maxf(0,160-flight*400)
			top=bottom+20
			if flight>0.65: phase="spent"
		elif kind=="swing":
			rect.position.x=sin(flight*2.0)*180-40
			top=80
	return {"rect":rect,"phase":phase,"bottom":bottom,"top":top}

func advance_events(_dt: float) -> void:
	for event in journey_events:
		if event.has("hp") and event.hp<=0:
			event.phase="spent"
			continue
		# 以最快合法前进速度预留 >2.8 秒；锁定后不跟踪改道。
		if event.trigger<0 and maxf(a.position.y,b.position.y)>=event.y-620:
			event.trigger=elapsed
			if event.kind=="stone": event.locked_x=clampf((a.position.x+b.position.x)*0.5,-EDGE+30,EDGE-30)
			event.warning_positions=[a.position,b.position]
		var sample:=event_sample(event,elapsed+FIXED_STEP)
		event.previous=event.sample
		event.sample=sample.rect
		event.phase=sample.phase
		event.bottom=sample.bottom
		event.top=sample.top
		if event.kind=="tree" and event.phase=="fallen": obstacles[event.obstacle]=event.rect

func check_event_hits(previous: Array) -> void:
	for event in journey_events:
		if event.phase not in ["active","falling"]: continue
		var old: Rect2=event.previous
		var current: Rect2=event.sample
		if current.position.y>maxf(a.position.y,b.position.y)+700 or current.end.y<minf(a.position.y,b.position.y)-700: continue
		for role in range(2):
			var point: Vector2=a.position if role==0 else b.position
			var motion: Vector2=current.position-old.position
			if swept_body_hits(previous[role],point-motion,foot_height(role),foot_height(role),old.grow(Motion.RADIUS),event.bottom,event.top):
				if event.kind in ["boar","stone"]:
					Combat.hit(self,role,"journey:%d"%event.id)
					if state!="running": return
				elif damage("journey:%d"%event.id,"%02d %s，两人共同重试"%[role+1,EVENT_NAMES[event.kind]]): return
		# 推车、摆臂和倒树保留绳段危险；野猪与投掷攻击只造成角色战斗伤害。
		if event.kind in ["cart","swing","tree"]:
			var path:=rope.physical_path()
			var z:=rope.physical_heights()
			for n in range(1,path.size()):
				if minf(z[n-1],z[n])<=event.top and maxf(z[n-1],z[n])>=event.bottom and segment_hits(path[n-1],path[n],current):
					fail_threat("绳索被%s命中，两人共同重试"%EVENT_NAMES[event.kind].split("：")[0])
					return

func update_checkpoint() -> void:
	if journey_events.is_empty(): return
	var zone:=zone_index()
	if zone not in visited_zones: visited_zones.append(zone)
	if region_checkpoint==zone or progress()<zone*finish_distance()/6.0+60: return
	if heights[0]>0 or heights[1]>0 or not ground_support[0] or not ground_support[1] or rope.touching()>0: return
	# 入口 8 秒缓冲内存档，不把活跃攻击或塌陷危险保存到脚下。
	for event in journey_events:
		if event.trigger>=0 and event.phase not in ["spent","fallen"] and absf(event.y-progress())<800: return
	for i in range(kinds.size()):
		if obstacles[i].grow(80).has_point(a.position) or obstacles[i].grow(80).has_point(b.position): return
	region_checkpoint=zone
	capture_checkpoint()

func check_finish() -> void:
	if charge_gates.any(func(gate): return not gate.open): return
	super()
	if combat_trial and state=="settlement": state="complete"

func active_hint() -> String:
	if combat_trial: return combat.get("notice","")
	if charge_gate.active and not charge_gate.open and charge_gate.receiver.y-progress()<800:
		var conditions:Dictionary=charge_gate.get("conditions",{})
		var plates:bool=charge_gate.get("kind","")=="sync_plates"
		var duration:float=SyncPlates.HOLD_TIME if plates else ChargeGate.CHARGE_TIME
		var hint:="两人各站一块踏板，落地保持" if plates else "两人分别站左右标记，可交换站位"
		if not plates and conditions.get("positioned",false):
			if not conditions.get("clear",true):hint="一起横移，让绳索离开障碍物"
			elif not conditions.get("taut",false):hint="向两侧拉紧绳索，保持供能"
			else:hint="两人落地站稳，保持连线穿过接收器"
		return "%s · %d%%\n%s"%[charge_gate.title,int(charge_gate.charge/duration*100),hint]
	for event in journey_events:
		if event.phase=="warning": return EVENT_NAMES[event.kind]
	for marker in encounter_markers:
		if marker.y>=progress()-40 and marker.y<=progress()+450 and not marker.kind in EVENT_NAMES:
			return {"slope":"起伏坡道：观察前方高低，保持同侧", "steps":"石阶：留意高低差，依次通过", "tilt":"倾斜桥面：保持靠近，留意两侧高度", "lift":"升降平台：等平台接近地面再上桥"}.get(marker.kind,hazard_name(marker.kind))
	return ["主动前进，松开按键即可停下；两人保持同侧","注意树干与草丛的预警","裂纹地面会塌陷，提前选择落脚点","看见村庄了，整理站位后前进","观察村民抬手和推车轨迹","前方供能装置与双人踏板需要合作"][zone_index()]

func build_combat_trial() -> void:
	# 无机关与缺口的独立训练路，持枪步行约 90 秒；可以停下观察。
	Combat.add_pickup(self,"gun",Vector2(-42,200))
	var waves := [1500.0,3000.0,5100.0,7200.0,9000.0,10400.0]
	for index in range(waves.size()):
		add_event("boar",waves[index],-1 if index%2==0 else 1)
	for y in [2700.0,6500.0,9500.0]: Combat.add_pickup(self,"ammo",Vector2(-42,y))
	for y in [3900.0,8400.0]: Combat.add_pickup(self,"medkit",Vector2(-42,y))
	rewards.append({"id":"trial:shield","kind":"shield","position":Vector2(-42,4600),"radius":28.0,"claimed":false})
	select_charge_gate()
	revision+=1

func reset_input() -> void:
	super()
	Combat.clear_input(self)

func set_combat_input(fire: bool, reload_pressed: bool=false, drop_pressed: bool=false) -> void:
	if state!="running" or combat.is_empty(): return
	combat.fire[0]=fire
	combat.reload[0]=combat.reload[0] or reload_pressed
	combat.drop[0]=combat.drop[0] or drop_pressed

func step(delta: float, input_a: Vector2=Vector2.ZERO, input_b: Vector2=Vector2.ZERO, jump_a: bool=false, jump_b: bool=false) -> void:
	if solo_control and not external_companion: jump_b=jump_a
	super(delta,input_a,input_b,jump_a,jump_b)

func companion_input(leader: Vector2) -> Vector2:
	# 同侧跟随，机关处走向对侧站位区。只产生输入，交给现有碰撞和绳索求解。
	var target := a.position+Vector2(56,0)
	target.x=clampf(target.x,-EDGE+Motion.RADIUS,EDGE-Motion.RADIUS)
	# 不在跨越道路中线时交换左右，避免搭档迎面挡住玩家。
	# 右侧空间不足时改为前后站位；只向前调整，不把角色移向身后。
	if target.x-a.position.x<BODY_GAP+4: target.y+=BODY_GAP+8
	var gate_assist := false
	for gate in charge_gates:
		if gate.open or absf(a.position.y-gate.receiver.y)>180: continue
		var left: Rect2=gate.left
		var right: Rect2=gate.right
		if left.grow(12).has_point(a.position) or right.grow(12).has_point(a.position):
			var other: Rect2=right if left.grow(12).has_point(a.position) else left
			target=Vector2(other.get_center().x,maxf(other.position.y+12,a.position.y))
			gate_assist=true
			break
	var delta := target-b.position
	var input := Vector2(clampf(delta.x/30.0,-1,1),clampf(delta.y/30.0,0,1))
	if not gate_assist:
		var leader_scale: float=Combat.MOVE_SCALE if not combat.weapons[0].is_empty() else 1.0
		input.y=clampf(leader.y*leader_scale+delta.y/30.0,0,1)
	if absf(delta.x)<2: input.x=0
	if delta.y<2 and leader.y<=0: input.y=0
	return input.limit_length()

func sync_hash() -> int:
	return var_to_str([super(),journey_events,visited_zones,region_checkpoint,combat,solo_control,external_companion,combat_trial]).hash()

# 一次物理时刻内地面支持会查询数十次；只缓存纯几何结果，不省略任何缺口。
func ground_gaps(time:float=-1.0)->Array[Rect2]:
	var sample_time:=elapsed if time<0 else time
	if ground_gap_cache_time==-INF or elapsed!=ground_gap_cache_epoch or revision!=ground_gap_cache_revision:
		ground_gap_queries.clear()
		ground_gap_cache_epoch=elapsed;ground_gap_cache_revision=revision
	if not ground_gap_queries.has(sample_time):
		# 固定步内混用当前、子步和预测时间，分别缓存，不互相覆盖。
		if ground_gap_queries.size()>=16:ground_gap_queries.erase(ground_gap_queries.keys()[0])
		ground_gap_queries[sample_time]=super(sample_time)
	ground_gap_cache_time=sample_time
	ground_gap_cache=ground_gap_queries[sample_time]
	return ground_gap_cache

func restore_checkpoint()->bool:
	var restored:=super()
	ground_gap_cache_time=-INF
	return restored

# 地面/绳索每步多次采样，先索引地形类型，再使用原解析判定；不按距离删掉有效机关。
func indexed_terrain()->Array[int]:
	var signature:=kinds.hash()
	if signature!=terrain_index_signature:
		terrain_index_signature=signature;terrain_indices.clear()
		for i in range(kinds.size()):
			if kinds[i] in Terrain.KINDS:terrain_indices.append(i)
	return terrain_indices

func surface_at(point:Vector2,time:float,radius:float=0.0)->Dictionary:
	var surface:={"supported":absf(point.x)<=EDGE,"height":0.0,"normal":Vector3.UP,"friction":0.8,"velocity":Vector3.ZERO}
	for gap in ground_gaps(time):
		if gap.grow(radius).has_point(point):surface.supported=false
	for i in indexed_terrain():
		if kinds[i]!="ferry" and not obstacles[i].has_point(point):continue
		var sample:=terrain_sample(i,time,point)
		if sample.supported and sample.rect.grow(-radius).has_point(point):surface=sample
	return surface

func surface_rope_length(p:Vector2,q:Vector2,h0:float,h1:float)->float:
	# 两端高于平地时，普通路面/缺口不会抬高绳段；仅局部平台可能改变原有十二点采样。
	if minf(h0,h1)<RopePhysics.RADIUS:return super(p,q,h0,h1)
	var distance:=Vector2(p.distance_to(q),h1-h0).length()
	var terrain_list:=indexed_terrain()
	if terrain_list.is_empty():return distance
	var bounds:=Rect2(p,Vector2.ZERO).expand(q)
	var candidates:Array[int]=[]
	for i in terrain_list:
		var rect:Rect2=terrain_sample(i,elapsed,obstacles[i].get_center()).rect if kinds[i]=="ferry" else obstacles[i]
		if bounds.intersects(rect,true):candidates.append(i)
	var previous:=Vector3(p.x,h0,p.y)
	var total:=0.0
	for i in range(1,13):
		var t:=float(i)/12
		var point:=p.lerp(q,t)
		var height:=lerpf(h0,h1,t)
		if i<12:
			var floor_height:=-INF
			for index in candidates:
				if kinds[index]!="ferry" and not obstacles[index].has_point(point):continue
				var sample:=terrain_sample(index,elapsed,point)
				if sample.supported and sample.rect.has_point(point):floor_height=sample.height
			height=maxf(height,floor_height+RopePhysics.RADIUS)
		var current:=Vector3(point.x,height,point.y)
		total+=previous.distance_to(current);previous=current
	return maxf(total,distance)

func terrain_supports_sweep(from:Vector2,to:Vector2,time:float)->bool:
	for i in indexed_terrain():
		if kinds[i]!="ferry" and not obstacles[i].has_point(to):continue
		var sample:=terrain_sample(i,time,to)
		if sample.supported and sample.rect.grow(-Motion.RADIUS).has_point(from) and sample.rect.grow(-Motion.RADIUS).has_point(to):return true
	return false

func platform_motion(point:Vector2,start:float,end:float)->Vector2:
	for i in indexed_terrain():
		if kinds[i] not in Terrain.MOVING:continue
		var first:=terrain_sample(i,start,point)
		if first.rect.has_point(point):return terrain_sample(i,end,point).rect.position-first.rect.position
	return Vector2.ZERO
