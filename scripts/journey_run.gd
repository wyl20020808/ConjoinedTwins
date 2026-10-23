extends "res://scripts/road_run.gd"

# 主动前进的连续旅程。位置是固定世界坐标；镜头进度不驱动物理。
const CHAPTERS := [
	{"name":"穿林入村", "length":49800.0, "zones":["原野石板路","森林深处","坍塌林道","林缘与村口","村庄街道","村口防御"], "themes":["ridge","forest","broken","edge","village","village"]},
	{"name":"水车河道", "length":37200.0, "zones":["村外田野","农田小路","河岸渡口","水车栈道","旧桥防线","河谷出口"], "themes":["farm","farm","river","river","village","river"]},
	{"name":"矿道归航", "length":37200.0, "zones":["河谷山路","矿场入口","矿道深处","遗迹回廊","设施防线","归航出口"], "themes":["river","mine","mine","ruins","facility","facility"]}
]
const WALK_SPEED := 320.0
# 镜头只前进；允许在可见后沿前后调整，不把玩家夹回上一帧位置。
const RETREAT_DISTANCE := 200.0
const COLOR_GATE_LEASH := 10.0
const Combat = preload("res://scripts/journey_combat.gd")
const Monsters = preload("res://scripts/journey_monsters.gd")
const Encounters = preload("res://scripts/journey_encounters.gd")
const Boss = preload("res://scripts/journey_boss.gd")
const ZONE_WEAPONS := ["smg","shotgun","flamer","launcher"]
const TRIAL_ZONES := ["拾取与射击","单只冲锋兽","换弹与补给","交替应敌","护盾与医疗","共同抵达"]
var combat: Dictionary = {}
# 模拟默认兼容既有双输入夹具；新生产界面仅向单人入口提供输入。
var solo_control := false
var external_companion := false
var combat_trial := false
const EVENT_NAMES := {"monster":"怪物蓄力：射击打倒或离开落点", "tree":"树木即将倒下：一起离开标记区", "boar":"野猪冲锋：共同避开直线路径", "stone":"村民投掷：离开落点", "cart":"推车横穿：观察轨迹再前进", "swing":"水车摆臂：等待或从侧面通过"}
var terrain_index_signature:=0
var terrain_index_epoch:=-INF
var terrain_index_revision:=-1
var terrain_index_count:=-1
var terrain_indices:Array[int]=[]
# 只在父模拟的一次固定步内使用；结束后立即丢弃，外部直接改布局的查询仍读实时几何。
var terrain_step_bins: Dictionary = {}
var terrain_step_active := false
var terrain_bins:={}
var moving_terrain:Array[int]=[]
var obstacle_bins:={}
var obstacle_envelopes:Array[Rect2]=[]
var unbounded_obstacles:Array[int]=[]
var obstacle_bin_epoch:=-INF
var obstacle_bin_revision:=-1
var obstacle_bin_count:=-1
var obstacle_layout_signature := -1
var dynamic_obstacles: Array[int] = []
var dynamic_obstacle_bins := {}
var terrain_layout_signature := -1
var spatial_rebuilds := 0
var gap_layout_signature := -1
var gap_layout_count := -1
var gap_indices: Array[int] = []
var collapsing_indices: Array[int] = []
var collapsed_indices: Array[int] = []
var ground_gap_cache_time:=-INF
var ground_gap_cache_revision:=-1
var ground_gap_cache:Array[Rect2]=[]
var ground_gap_cache_epoch:=-INF
var ground_gap_queries:={}
var ground_gap_bins:={}
var ground_gap_layout:Array[Rect2]=[]
var ground_gap_layout_bins:={}
var solid_query_epoch:=-INF
var solid_query_revision:=-1
var solid_query_count:=-1
var encounter_markers:Array=[]
# 第一章 Boss 在 journey_events 中的下标（-1 表示没有）；随存档一起恢复。
var boss_index := -1
# 开场运镜：从 Boss 巢穴的浓烟绕一圈，沿路掠过机关与敌人回到两人身后。只在章节从头开始时播放，
# 期间两人不能操作、不受伤害，任一人按跳跃可跳过（剩 OPENING_RETURN 秒的镜头交还）。
# 按模拟时间推进，联机两端一致；opening_enabled 由生产入口打开，测试默认关闭。
const OPENING := 19.0
const OPENING_SKIP_AFTER := 0.6
const OPENING_RETURN := 1.2
var opening_enabled := false
# 开场开始的模拟时刻；跳过时会前移到负值，所以“没有开场”另用 NO_OPENING 表示。
const NO_OPENING := -1.0e6
var opening_at := NO_OPENING
var opening_skipped_age := -1.0
# 怪物潮专区区间与机关段零星小队的出生锚点，由布局生成，供怪物填充使用。
var arenas:Array=[]
var pack_slots:Array=[]
var journey_events: Array[Dictionary] = []
var visited_zones: Array[int] = []
var region_checkpoint := -1
# 区域入口之外的补充存档：距上一存档至少 40 米（约 2.5 秒步行）且满足全部安全条件时顺延保存。
const MID_CHECKPOINT_SPACING := 800.0
const MID_CHECKPOINT_POLL := 12
const MID_CHECKPOINT_HEALTH := 50
const MID_CHECKPOINT_GATE_CLOSED := 800.0
const MID_CHECKPOINT_GATE_OPEN := 300.0
const MID_CHECKPOINT_SPAWN_CLEAR := 80.0
const MID_CHECKPOINT_ENEMY_CLEAR := 360.0
const MID_CHECKPOINT_HAZARD_MARGIN := 36.0
const MID_CHECKPOINT_MOVING_BEHIND := 300.0
const MID_CHECKPOINT_MOVING_AHEAD := 2.0
const MID_CHECKPOINT_MOVING_LANE := 160.0
const MID_CHECKPOINT_EVENT_TRIGGERED := 240.0
var event_serial := 0
var last_floor := [0.0,0.0]

func _init(randomize_layout:bool=false) -> void:
	health_hazards=true
	balls_snag_rope=false
	random_seed=randomize_layout
	super(false, false)

func hazard_contact(index: int, role: int, _message: String) -> bool:
	# 身体只扣命中的角色；绳段命中将伤害传给两端，共用同一机关冷却。
	var amount: int=Combat.HAZARD_DAMAGE.get(kinds[index],25)
	# 滚球是一次性重击：每颗球对每人只结算一次，随后照常滚走，不再贴身反复扣血。
	var repeatable:=not Threats.is_ball(kinds[index])
	for target in ([0,1] if role<0 else [role]):
		Combat.hit(self,target,"trap:%d"%obstacle_ids[index],amount,repeatable)
		if state!="running": return true
	return false

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
	# Boss 战中场地内可以后退：进度跟随落后者而不是最远处，模型显示、怪物察觉和镜头都围着两人。
	var arena_floor:=Boss.floor_y(self)
	if arena_floor<INF: distance=maxf(minf(a.position.y,b.position.y),arena_floor)
	select_charge_gate()

func bounded(point: Vector2, _floor: float = INF) -> Vector2:
	# Boss 战中场地内可以退到入口根墙前，不受“最多后退 10 米”的限制。
	var forward := maxf(point.y,maxf(0.0,minf(distance-RETREAT_DISTANCE,Boss.floor_y(self))))
	if charge_gate.get("active",false) and not charge_gate.open:
		var hold: float=charge_gate.receiver.y+(46.0 if charge_gate.get("kind","")=="sync_plates" else 15.0)
		# 接力踏板：门后踏板也在可达范围内；门关着时仍由门板本身挡住。
		if charge_gate.get("kind","")=="relay":hold=charge_gate.far.end.y
		forward=minf(forward,hold)
	# 颜色门：后面的人还没进门洞时，先过门的人最多离开门 10 单位，绳子不会被拉满，
	# 后者始终能横移对准自己的门，不会被拽进中间能量帘的转角两人一起卡死。
	# Boss 存活时不能越过树心前的站位线。
	forward=minf(forward,Boss.hold_y(self))
	var trailing:=minf(a.position.y,b.position.y)
	for i in indexed_kinds(["color_gate"]):
		var door:Rect2=obstacles[i]
		if trailing<door.position.y and maxf(a.position.y,b.position.y)>door.position.y-Motion.RADIUS:
			# 已在更前方的人原地保持，不被拉回（无瞬移），只是不能继续前进。
			forward=minf(forward,maxf(door.end.y+COLOR_GATE_LEASH,maxf(a.position.y,b.position.y)))
	# 主动跑动也必须等桥板落平；父类只暂停自动推进，不能约束旅程的手动前进。
	for gate in charge_gates:
		if gate.get("bridge",false) and gate.open and elapsed-gate.opened_at<0.6:
			forward=minf(forward,gate.door.position.y+60-Motion.RADIUS-2)
	return Vector2(clampf(point.x,-EDGE+Motion.RADIUS,EDGE-Motion.RADIUS),forward)

func retry(count_failure: bool = false) -> void:
	obstacle_bin_epoch=-INF
	ground_gap_cache_time=-INF
	terrain_index_epoch=-INF
	solid_query_epoch=-INF
	generation_enabled = false
	async_enabled = false
	charge_tutorial = false
	streaming = true
	super(count_failure)
	journey_events.clear()
	encounter_markers.clear()
	arenas.clear()
	pack_slots.clear()
	visited_zones.clear()
	region_checkpoint = -1
	event_serial = 0
	combat=Combat.fresh()
	if combat_trial: build_combat_trial()
	else:
		boss_index=-1
		build_journey()
		Monsters.populate(self)
		# 第一章终点 Boss 场地（章节最后 90 米），在怪物与补给之后登记。
		Boss.add(self)
		# 合作站是战斗间歇；补给位于已留空的到达区域，仍须实际走近拾取。
		for gate in charge_gates:
			for x in [-65,65]:Combat.add_pickup(self,"medkit",Vector2(x,gate.receiver.y-100))
			Combat.add_pickup(self,"ammo",Vector2(-65,gate.receiver.y-60))
		for zone in range(6):
			var start: float=zone*finish_distance()/6.0
			# 怪物潮专区自带补给；区域补给落在专区内时顺延到专区出口之后。
			for arena in arenas:
				if start+720>=arena.start and start+200<arena.end:start=arena.end
			Combat.add_pickup(self,"gun",Vector2(-42,start+200),{},ZONE_WEAPONS[(zone+level_index)%ZONE_WEAPONS.size()])
			# 第二把枪放在右侧，种类与左侧不同；单人时搭档也会去捡。落点避开实体与缺口。
			var second: String=ZONE_WEAPONS[(zone+level_index+2)%ZONE_WEAPONS.size()]
			for offset in [0.0,40.0,-40.0,80.0]:
				var point:=Vector2(42,start+200+offset)
				if Monsters.safe_supply(self,point):
					Combat.add_pickup(self,"gun",point,{},second)
					break
			Combat.add_pickup(self,"ammo",Vector2(-42,start+550))
			Combat.add_pickup(self,"medkit",Vector2(0,start+720))
	checkpoint = {}
	opening_at = NO_OPENING
	if not count_failure: arm_opening()
	update_checkpoint()

# 章节从头开始时排上开场运镜（未开始奔跑前时间停在 0，按“出发”后开始播放）。
func arm_opening() -> void:
	opening_skipped_age = -1.0
	opening_at = 0.0 if opening_enabled and not combat_trial and Boss.enabled(self) else NO_OPENING

func opening_active() -> bool:
	return opening_at > NO_OPENING and elapsed-opening_at < OPENING

func opening_age() -> float:
	return elapsed-opening_at if opening_at > NO_OPENING else -1.0

# 跳过开场：时间轴前移到最后的镜头交还段，记下跳过时刻，镜头从那一刻的位置收回。
func skip_opening() -> void:
	var age := opening_age()
	if not opening_active() or age < OPENING_SKIP_AFTER or age >= OPENING-OPENING_RETURN: return
	opening_skipped_age = age
	opening_at = elapsed-(OPENING-OPENING_RETURN)

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
	var x := side*(TREE_BASE if kind=="tree" else 125.0)
	var width := TREE_WIDTH if kind=="tree" else (32.0 if kind=="boar" else (140.0 if kind=="cart" else (80.0 if kind=="swing" else 24.0)))
	var rect := Rect2(x-width/2,y-width/2 if kind=="tree" else y-35,width,width if kind=="tree" else 70)
	var index := -1
	var trunk:Array=[]
	if kind=="tree":
		# 倒下之后树干分段成为实心障碍，贴合斜向倒伏的树干；砸下阶段另做伤害判定。
		for n in range(TREE_SEGMENTS):
			index = add_hazard("cargo",Rect2(EDGE+1000,y,TREE_WIDTH,TREE_WIDTH))
			obstacle_heights[index] = 52.0
			trunk.append(index)
		index = trunk[0]
	journey_events.append({"id":event_serial,"kind":kind,"y":y,"side":side,"rect":rect,"trigger":-1.0,"phase":"ready","previous":rect,"sample":rect,"bottom":0.0,"top":60.0,"obstacle":index,"combined":combined,"locked_x":x})
	if kind=="tree":
		journey_events[-1].trunk=trunk
		journey_events[-1].base=Vector2(x,y)
		journey_events[-1].direction=Vector2(0,-1)
		journey_events[-1].approach=Vector2.INF
	if kind in ["boar","stone"]:
		journey_events[-1].hp=30 if kind=="boar" else 40
		journey_events[-1].max_hp=journey_events[-1].hp
	event_serial += 1

func add_relay(y: float, side: float, suffix: String) -> void:
	var gate:Dictionary=RelayPlates.make(y,side,EDGE)
	gate.id=suffix
	gate.title="接力机关门 · 一人守板一人过门"
	charge_gates.append(gate)

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
	if preload("res://scripts/journey_boss_finale.gd").active(self):
		elapsed += FIXED_STEP
		Combat.clear_input(self)
		jump_buffer = [0, 0]
		move_directions = [Vector2.ZERO, Vector2.ZERO]
		invulnerable_until = maxf(invulnerable_until, elapsed+0.2)
		return
	if solo_control and not external_companion: input_b=companion_input(input_a)
	last_floor=[a.position.y,b.position.y]
	var previous := [a.position,b.position]
	advance_events(FIXED_STEP)
	if state!="running": return
	if Boss.cinematic(self) or opening_active():
		# 开战帧之后的同一步里也不再移动、开火或受伤。
		input_a=Vector2.ZERO;input_b=Vector2.ZERO
		combat.fire=[false,false]
		invulnerable_until=maxf(invulnerable_until,elapsed+0.2)
	var scale_a: float=Combat.MOVE_SCALE if not combat.weapons[0].is_empty() else 1.0
	var scale_b: float=Combat.MOVE_SCALE if not combat.weapons[1].is_empty() else 1.0
	prepare_terrain_lookup()
	super(input_a*(WALK_SPEED/LATERAL)*scale_a,input_b*(WALK_SPEED/LATERAL)*scale_b)
	terrain_step_active = false
	terrain_step_bins.clear()
	if state!="running": return
	# 前后移动共用父求解器的实体扫掠、地面支持与绳索约束。
	for role in range(2):
		var pos: Vector2 = a.position if role==0 else b.position
		if pos.distance_to(previous[role])<0.001 and heights[role]==0.0: actions[role]="Idle"
	# 运动与实体求解之后开火，死亡敌人不会在同一步继续攻击。
	Combat.tick(self,previous)
	check_event_hits(previous)

# 倒树等人走近约 23 米才起裂：按两人是否在前进预测到达位置，0.5 秒吱嘎后朝两人倒下，
# 0.6 秒砸地。树干 15 米长，分四段判定；看准倒向横移或停步即可躲开。
const TREE_TRIGGER := 460.0
const TREE_WARNING := 0.5
const TREE_FALL := 0.6
const TREE_LENGTH := 300.0
const TREE_WIDTH := 44.0
const TREE_BASE := 230.0
const TREE_SEGMENTS := 4
# 砸地前最后这段时间（倒伏进度 ≥ 60%）树干已低于头顶，才结算砸中。
const TREE_STRIKE := 0.6

# 树干各段的轴对齐包围盒：沿倒伏方向等分，每段外扩半个树干宽。
static func tree_segments(event: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var base: Vector2 = event.base
	var direction: Vector2 = event.direction
	for n in range(TREE_SEGMENTS):
		var p0: Vector2 = base+direction*TREE_LENGTH*n/TREE_SEGMENTS
		var p1: Vector2 = base+direction*TREE_LENGTH*(n+1)/TREE_SEGMENTS
		result.append(Rect2(Vector2(minf(p0.x,p1.x),minf(p0.y,p1.y)),(p1-p0).abs()).grow(TREE_WIDTH/2))
	return result

# 锁定倒向：两人中点；两人正在前进时按步行速度推算倒地时刻的位置。单步位移受绳索与碰撞修正影响，
# 只用来判断是否在前进，不直接外推。树总是朝镜头一侧（两人来的方向）倒，落点至少在树根前 5 米。
func aim_tree(event: Dictionary) -> void:
	var mid: Vector2 = (a.position+b.position)*0.5
	var advancing: bool = event.approach!=Vector2.INF and mid.y-event.approach.y>0.5
	var aim: Vector2 = mid+Vector2(0,WALK_SPEED*(TREE_WARNING+TREE_FALL) if advancing else 0.0)
	aim.x=clampf(aim.x,-EDGE+TREE_WIDTH,EDGE-TREE_WIDTH)
	aim.y=minf(aim.y,event.base.y-100.0)
	event.direction=(aim-event.base).normalized()

func event_sample(event: Dictionary,time: float) -> Dictionary:
	if event.kind=="monster": return Monsters.sample(event,time)
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
			flight=maxf(0,age-TREE_WARNING)
			phase="warning" if age<TREE_WARNING else ("falling" if flight<TREE_FALL else "fallen")
			top=26.0 if phase=="fallen" else 160.0
			if phase!="warning":
				var segments:=tree_segments(event)
				rect=segments[0]
				for segment in segments: rect=rect.merge(segment)
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
			# 摆臂横扫覆盖整条路面，两侧都无法贴边躲过，只能看准摆臂离开再通过。
			rect.position.x=sin(flight*2.0)*(EDGE-60)-40
			top=80
	return {"rect":rect,"phase":phase,"bottom":bottom,"top":top}

func advance_events(_dt: float) -> void:
	for event in journey_events:
		if event.has("hp") and event.hp<=0:
			event.phase="spent"
			if event.kind=="boss" and not event.get("victory_saved",false):
				event.victory_saved=true
				capture_checkpoint()
			continue
		if event.kind=="monster":
			Monsters.advance(self,event)
			continue
		if event.kind=="boss":
			Boss.advance(self,event)
			continue
		# 以最快合法前进速度预留 >2.8 秒；锁定后不跟踪改道。
		var reach:float=TREE_TRIGGER if event.kind=="tree" else maxf(620.0,WALK_SPEED*3.0)
		if event.trigger<0 and maxf(a.position.y,b.position.y)>=event.y-reach:
			event.trigger=elapsed
			if event.kind=="stone": event.locked_x=clampf((a.position.x+b.position.x)*0.5,-EDGE+30,EDGE-30)
			if event.kind=="tree": aim_tree(event)
			event.warning_positions=[a.position,b.position]
		if event.kind=="tree" and event.trigger<0: event.approach=(a.position+b.position)*0.5
		var sample:=event_sample(event,elapsed+FIXED_STEP)
		event.previous=event.sample
		event.sample=sample.rect
		event.phase=sample.phase
		event.bottom=sample.bottom
		event.top=sample.top
		if event.kind=="tree" and event.phase=="fallen" and obstacles[event.trunk[0]].position.x>EDGE:
			var segments:=tree_segments(event)
			for n in range(TREE_SEGMENTS): obstacles[event.trunk[n]]=segments[n]

func check_event_hits(previous: Array) -> void:
	for event in journey_events:
		if event.phase not in ["active","falling"]: continue
		var old: Rect2=event.previous
		var current: Rect2=event.sample
		if current.position.y>maxf(a.position.y,b.position.y)+700 or current.end.y<minf(a.position.y,b.position.y)-700: continue
		if event.kind=="tree" and event.phase=="falling":
			if tree_strikes(event,previous) and state!="running": return
			continue
		for role in range(2):
			var point: Vector2=a.position if role==0 else b.position
			var motion: Vector2=current.position-old.position
			if swept_body_hits(previous[role],point-motion,foot_height(role),foot_height(role),old.grow(Motion.RADIUS),event.bottom,event.top):
				if event.kind=="monster":
					if Combat.line_of_sight(self,event.origin,point,Combat.enemy_height(event),foot_height(role)+24):
						Combat.hit(self,role,"monster:%d"%event.id,Monsters.profile(event).damage)
					if state!="running": return
				elif event.kind in ["boar","stone"]:
					Combat.hit(self,role,"journey:%d"%event.id)
					if state!="running": return
				else:
					Combat.hit(self,role,"journey:%d"%event.id,Combat.HAZARD_DAMAGE[event.kind],true)
					if state!="running": return
		# 绳段接触同样扣血；与角色命中共用事件冷却，避免同帧重复伤害。
		if event.kind in ["cart","swing","tree"]:
			var path:=rope.physical_path()
			var z:=rope.physical_heights()
			for n in range(1,path.size()):
				if minf(z[n-1],z[n])<=event.top and maxf(z[n-1],z[n])>=event.bottom and segment_hits(path[n-1],path[n],current):
					for role in range(2):
						Combat.hit(self,role,"journey:%d"%event.id,Combat.HAZARD_DAMAGE[event.kind],true)
						if state!="running": return
					break

# 倒树砸地：树干放低到头顶以下后，按四段树干分别判定角色身体与绳段，共用事件冷却。
func tree_strikes(event: Dictionary,previous: Array) -> bool:
	if elapsed-event.trigger-TREE_WARNING<TREE_FALL*TREE_STRIKE: return false
	var segments:=tree_segments(event)
	var path:=rope.physical_path()
	var z:=rope.physical_heights()
	for segment in segments:
		var struck:=false
		for role in range(2):
			var point: Vector2=a.position if role==0 else b.position
			if swept_body_hits(previous[role],point,foot_height(role),foot_height(role),segment.grow(Motion.RADIUS),0.0,52.0):struck=true
		for n in range(1,path.size()):
			if minf(z[n-1],z[n])<=52.0 and segment_hits(path[n-1],path[n],segment):struck=true
		if not struck: continue
		for role in range(2):
			Combat.hit(self,role,"journey:%d"%event.id,Combat.HAZARD_DAMAGE.tree,true)
			if state!="running": return true
		return true
	return false

func update_checkpoint() -> void:
	if journey_events.is_empty(): return
	var zone:=zone_index()
	if zone not in visited_zones: visited_zones.append(zone)
	# 补充规则每 0.1 秒判定一次；判定只读同步状态，联机两端在同一固定步得出相同结果。
	var polled:=posmod(roundi(elapsed/FIXED_STEP),MID_CHECKPOINT_POLL)==0
	if region_checkpoint!=zone:
		if progress()<zone*finish_distance()/6.0+60: return
		# 入口规则迟迟不满足时（密集机关段），按补充存档规则保存本区域的第一个存档。
		if not checkpoint_ground_clear() and not (polled and mid_checkpoint_clear() and mid_checkpoint_hazards_clear()): return
		region_checkpoint=zone
		capture_checkpoint()
		return
	# 区域内补充存档：距上一存档足够远后，在战斗清空、远离机关与窄路的安全地面上顺延保存。
	if not polled or checkpoint.is_empty() or progress()<checkpoint.progress+MID_CHECKPOINT_SPACING: return
	if mid_checkpoint_clear() and mid_checkpoint_hazards_clear(): capture_checkpoint()

# 区域入口存档：两人贴地、绳未挂障碍，附近没有进行中的攻击，脚下不压机关。
func checkpoint_ground_clear() -> bool:
	if boss_fighting(): return false
	if heights[0]>0 or heights[1]>0 or not ground_support[0] or not ground_support[1] or rope.touching()>0: return false
	# 入口 8 秒缓冲内存档，不把活跃攻击或塌陷危险保存到脚下。
	for event in journey_events:
		# 新怪物只有预警与落弹期间阻止安全存档；冷却时恢复会重新给出完整预警。
		if event.kind=="monster" and event.phase not in ["warning","active"]: continue
		if event.trigger>=0 and event.phase not in ["spent","fallen"] and absf(event.y-progress())<800: return false
	for i in range(kinds.size()):
		if obstacles[i].grow(80).has_point(a.position) or obstacles[i].grow(80).has_point(b.position): return false
	return true

# 父类按 distance 判定“被挤出画面”；Boss 战中允许退回场地入口，后边界同步放宽。
func rear_bound() -> float:
	return minf(super(),Boss.floor_y(self)-RELATIVE_RANGE)

# Boss 开战时已在场地入口存档；战斗中不再顺延存档，失败从入口重打。
func boss_fighting() -> bool:
	var event:=Boss.boss(self)
	return Boss.alive(event) and event.phase!="dormant"

# 补充存档的额外条件：先查廉价的血量、机关、敌人与窄路，再由调用方做完整危险走廊检查。
func mid_checkpoint_clear() -> bool:
	if boss_fighting(): return false
	if heights[0]>0 or heights[1]>0 or not ground_support[0] or not ground_support[1] or rope.touching()>0: return false
	if combat.is_empty() or combat.health[0]<MID_CHECKPOINT_HEALTH or combat.health[1]<MID_CHECKPOINT_HEALTH: return false
	var low:=minf(a.position.y,b.position.y)
	var high:=maxf(a.position.y,b.position.y)
	for gate in charge_gates:
		var clear: float=MID_CHECKPOINT_GATE_OPEN if gate.open else MID_CHECKPOINT_GATE_CLOSED
		if high>=gate.receiver.y-clear and low<=gate.receiver.y+clear: return false
	if not Encounters.narrow_at(self,low,high).is_empty(): return false
	for event in journey_events:
		if event.kind=="monster":
			# 出生点即使敌人已倒下也不作为恢复位置；存活敌人须在近战距离之外，远程与冲锋仍有完整预警。
			for point in [a.position,b.position]:
				if event.spawn.distance_to(point)<MID_CHECKPOINT_SPAWN_CLEAR: return false
				if event.hp>0 and event.origin.distance_to(point)<MID_CHECKPOINT_ENEMY_CLEAR: return false
			# 正在预警或攻击的敌人仍按区域入口的 800 单位窗口回避。
			if event.hp>0 and event.phase in ["warning","active"] and absf(event.y-progress())<800: return false
		elif event.phase not in ["spent","fallen"]:
			# 倒树、推车、投掷与摆臂按自身作用区回避；已触发的再多留一段反应距离。
			var reach: float=MID_CHECKPOINT_EVENT_TRIGGERED if event.trigger>=0 else 80.0
			if event.rect.grow(reach).has_point(a.position) or event.rect.grow(reach).has_point(b.position): return false
	return true

# 旅程无输入时角色原地不动，不沿用自动推进道路的“恢复后直行 1 秒”走廊：
# 固定、周期与缺口危险按当前采样包络，不得进入两人及绳索周围的留白框；
# 移动危险在同一路线带内前后一段距离，或按相对速度即将到达时都不存档。
func mid_checkpoint_hazards_clear() -> bool:
	if rope_block_substeps>0 or rope_unwinding or rope_failed: return false
	var margin:=Motion.RADIUS+MID_CHECKPOINT_HAZARD_MARGIN
	var guard:=Rect2(a.position,Vector2.ZERO).expand(b.position).grow(margin)
	var low:=guard.position.y-MID_CHECKPOINT_MOVING_BEHIND
	var far:=guard.end.y+level_speed()*MID_CHECKPOINT_MOVING_AHEAD
	for i in range(kinds.size()):
		var moving: bool=hazard_specs[i].get("front",false) or kinds[i].begins_with("fly_") or kinds[i] in ["drone","forklift"] or Threats.is_ball(kinds[i])
		# 远处静止物只需粗筛；周期机关的运动包络不会离原位超过一屏。
		if not moving and (obstacles[i].end.y<guard.position.y-600 or obstacles[i].position.y>guard.end.y+600): continue
		var sample:=hazard_sample(i,elapsed)
		var rect: Rect2=sample.get("envelope",sample.rect)
		if rect.intersects(guard,true): return false
		var lane: bool=rect.end.x>=guard.position.x-MID_CHECKPOINT_MOVING_LANE and rect.position.x<=guard.end.x+MID_CHECKPOINT_MOVING_LANE
		if moving and lane and rect.end.y>=low and rect.position.y<=far: return false
		# 迎面物按纵向相对速度估算到达时间，只计同一路线带内的。
		if lane and sample.has("ttc") and rect.end.y>=low and sample.ttc<MID_CHECKPOINT_MOVING_AHEAD: return false
	return true

# 暂停菜单「回到存档点继续」：与失败后的恢复同一路径；还没有存档时从本关开头重来。
func resume_from_checkpoint() -> void:
	if state!="paused": return
	state="failed"
	if not restore_checkpoint():
		state="paused"
		retry(false)

func check_finish() -> void:
	if charge_gates.any(func(gate): return not gate.open): return
	super()
	if combat_trial and state=="settlement": state="complete"

# 进入专区前 15 米开始提示，离开专区即结束。
func arena_at(y: float) -> Dictionary:
	for arena in arenas:
		if y>=arena.start-300 and y<arena.end: return arena
	return {}

func active_hint() -> String:
	if combat_trial: return combat.get("notice","")
	var boss_hint:=Boss.hint(self)
	if not boss_hint.is_empty(): return boss_hint
	var narrow:Dictionary=Encounters.narrow_at(self,progress(),maxf(a.position.y,b.position.y))
	if not narrow.is_empty():return {"center_path":"中央独木道：对准中线，前后依次通过", "edge_path":"崖边单行道：提前靠边，前后依次通过", "twin_paths":"双线镂空桥：各走一条，保持同步", "triple_paths":"三线镂空桥：选择相邻通道，别把绳拉满"}[narrow.kind]
	if charge_gate.active and not charge_gate.open and charge_gate.receiver.y-progress()<800:
		var conditions:Dictionary=charge_gate.get("conditions",{})
		if charge_gate.get("kind","")=="relay":
			var step:="一人站上门前踏板，门会打开"
			if conditions.get("near",false):step="门已打开：另一人穿过去，站上门后踏板"
			if conditions.get("far",false):step="门后踏板已踩住，保持站稳"
			return "%s · %d%%\n%s"%[charge_gate.title,int(charge_gate.charge/RelayPlates.HOLD_TIME*100),step]
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
	var arena:=arena_at(progress())
	if not arena.is_empty():
		var left:=journey_events.filter(func(e):return e.kind=="monster" and e.hp>0 and e.y>=arena.start and e.y<arena.end).size()
		return "怪物潮：剩余 %d 只，边打边推进"%left if left>0 and progress()>=arena.start else "怪物潮专区：没有机关，专心清理敌群"
	for marker in encounter_markers:
		if marker.y>=progress()-40 and marker.y<=progress()+450 and not marker.kind in EVENT_NAMES and marker.kind!="boss":
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

func set_combat_input(fire: bool, reload_pressed: bool=false, drop_pressed: bool=false, swap_pressed: bool=false) -> void:
	if state!="running" or combat.is_empty(): return
	Combat.ensure_slots(self)
	combat.fire[0]=fire
	combat.reload[0]=combat.reload[0] or reload_pressed
	combat.drop[0]=combat.drop[0] or drop_pressed
	combat.swap[0]=combat.swap[0] or swap_pressed

func step(delta: float, input_a: Vector2=Vector2.ZERO, input_b: Vector2=Vector2.ZERO, jump_a: bool=false, jump_b: bool=false) -> void:
	if solo_control and not external_companion: jump_b=jump_a
	# Boss 入场动画期间两人原地观看：移动与跳跃输入清空，按跳跃改作“跳过动画”。
	if state=="running" and Boss.cinematic(self):
		if jump_a or jump_b: Boss.skip_intro(self)
		input_a=Vector2.ZERO;input_b=Vector2.ZERO;jump_a=false;jump_b=false
	elif state=="running" and opening_active():
		if jump_a or jump_b: skip_opening()
		input_a=Vector2.ZERO;input_b=Vector2.ZERO;jump_a=false;jump_b=false
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
		if leader.y<0 or gate.open or absf(a.position.y-gate.receiver.y)>180: continue
		var left: Rect2=gate.left
		var right: Rect2=gate.right
		if left.grow(12).has_point(a.position) or right.grow(12).has_point(a.position):
			var other: Rect2=right if left.grow(12).has_point(a.position) else left
			target=Vector2(other.get_center().x,maxf(other.position.y+12,a.position.y))
			gate_assist=true
			break
	var delta := target-b.position
	var input := Vector2(clampf(delta.x/30.0,-1,1),clampf(delta.y/30.0,-1,1))
	if not gate_assist:
		var leader_scale: float=Combat.MOVE_SCALE if not combat.weapons[0].is_empty() else 1.0
		input.y=clampf(leader.y*leader_scale+delta.y/30.0,-1,1)
	if absf(delta.x)<2: input.x=0
	if absf(delta.y)<2 and leader.y==0: input.y=0
	return input.limit_length()

func sync_hash() -> int:
	return var_to_str([super(),journey_events,visited_zones,region_checkpoint,combat,solo_control,external_companion,combat_trial]).hash()

# 一次物理时刻内地面支持会查询数十次；只缓存纯几何结果，不省略任何缺口。
func ground_gaps(time:float=-1.0)->Array[Rect2]:
	var sample_time:=elapsed if time<0 else time
	if ground_gap_cache_time==-INF or elapsed!=ground_gap_cache_epoch or revision!=ground_gap_cache_revision or gap_layout_count!=kinds.size():
		ground_gap_queries.clear()
		ground_gap_bins.clear()
		ground_gap_cache_epoch=elapsed;ground_gap_cache_revision=revision
		gap_layout_count=kinds.size()
		var signature:=hash([kinds,obstacles,revision])
		if signature!=gap_layout_signature:
			gap_layout_signature=signature;gap_indices.clear();collapsing_indices.clear()
			for i in range(kinds.size()):
				if kinds[i] in ["road_gap","collapse"]:gap_indices.append(i)
				if kinds[i]=="collapse":collapsing_indices.append(i)
			# 强制首次查询建立完整几何；之后只求值少数会塌陷的地面。
			collapsed_indices=[-1]
	if not ground_gap_queries.has(sample_time):
		# 固定步内混用当前、子步和预测时间，分别缓存，不互相覆盖。
		if ground_gap_queries.size()>=16:
			var oldest:float=ground_gap_queries.keys()[0]
			ground_gap_queries.erase(oldest);ground_gap_bins.erase(oldest)
		var active: Array[int]=[]
		for i in collapsing_indices:
			if hazard_sample(i,sample_time).stage=="collapsed":active.append(i)
		if active!=collapsed_indices:
			collapsed_indices=active
			# 新建数组，旧预测时刻的缓存仍指向原来的几何和分桶。
			ground_gap_layout=[];ground_gap_layout_bins={}
			for i in gap_indices:
				if kinds[i]=="road_gap" or i in active:ground_gap_layout.append(obstacles[i])
			for gap:Rect2 in ground_gap_layout:
				for cell in range(floori(gap.position.y/400.0),floori(gap.end.y/400.0)+1):
					if not ground_gap_layout_bins.has(cell):ground_gap_layout_bins[cell]=[]
					ground_gap_layout_bins[cell].append(gap)
		ground_gap_queries[sample_time]=ground_gap_layout
		ground_gap_bins[sample_time]=ground_gap_layout_bins
	ground_gap_cache_time=sample_time
	ground_gap_cache=ground_gap_queries[sample_time]
	return ground_gap_cache

func restore_checkpoint()->bool:
	var restored:=super()
	# 起点存档可能记在开场期间；从存档恢复不重播开场。
	if restored: opening_at=NO_OPENING
	obstacle_bin_epoch=-INF
	terrain_index_epoch=-INF
	solid_query_epoch=-INF
	ground_gap_cache_time=-INF
	return restored

# 已知静止物使用保守分桶；运动、旋转与未知类型不剔除。原索引顺序不变。
# 每个固定时刻重建一次，避免永久缓存随迭代、重试或行进增长。
func obstacles_in_bounds(bounds:Rect2)->Array[int]:
	if obstacle_bin_epoch!=elapsed or obstacle_bin_revision!=revision or obstacle_bin_count!=kinds.size():
		obstacle_bin_epoch=elapsed;obstacle_bin_revision=revision;obstacle_bin_count=kinds.size()
		# 静态布局只在真实几何变化时重建。类型/位置的原生哈希保留外部替换与倒树落地的失效路径。
		var signature := hash([kinds, obstacles, revision])
		if signature != obstacle_layout_signature:
			obstacle_layout_signature=signature;spatial_rebuilds+=1
			obstacle_bins.clear();unbounded_obstacles.clear();dynamic_obstacles.clear();obstacle_envelopes.clear()
			for i in range(kinds.size()):
				var envelope:Rect2=obstacles[i]
				if hazard_specs[i].get("front",false) or kinds[i] in ["drone","forklift"]:
					dynamic_obstacles.append(i);obstacle_envelopes.append(envelope);continue
				if kinds[i] in Industrial.KINDS:envelope=Industrial.motion_envelope(kinds[i],envelope,hazard_specs[i])
				elif kinds[i]=="sweeper":envelope=envelope.merge(Rect2(envelope.get_center()-Vector2.ONE*32,Vector2.ONE*64))
				obstacle_envelopes.append(envelope)
				if kinds[i] not in Industrial.KINDS and kinds[i] not in ["cargo","pillar","rail","spikes","active_spikes","scanner","road_gap","sweeper","slope","steps","tilt","lift","drawbridge"]:
					unbounded_obstacles.append(i);continue
				for cell in range(floori(envelope.position.y/400.0),floori(envelope.end.y/400.0)+1):
					if not obstacle_bins.has(cell):obstacle_bins[cell]=[]
					obstacle_bins[cell].append(i)
		refresh_moving_bins()
	var result:Array[int]=unbounded_obstacles.duplicate()
	if not rope.contacts.is_empty():
		for i in dynamic_obstacles:
			if rope.has_contact(obstacle_ids[i]):result.append(i)
	for bins:Dictionary in [obstacle_bins,dynamic_obstacle_bins]:
		for cell in range(floori(bounds.position.y/400.0),floori(bounds.end.y/400.0)+1):
			for index:int in bins.get(cell,[]):
				if bounds.intersects(obstacle_envelopes[index],true) and not result.has(index):result.append(index)
	result.sort()
	return result

func refresh_moving_bins() -> void:
	dynamic_obstacle_bins.clear()
	# 只对运动物体计算当前完整步包络；不更新远处模型，也不跳过已挂绳的滚球。
	for i in dynamic_obstacles:
		var spec: Dictionary=hazard_specs[i]
		var envelope: Rect2=obstacles[i]
		if spec.get("front",false):
			envelope.position+=spec.offset
			var travel:Vector2=spec.velocity*FIXED_STEP
			envelope=envelope.merge(Rect2(envelope.position-travel,envelope.size)).merge(Rect2(envelope.position+travel,envelope.size))
		else:envelope=Industrial.motion_envelope(kinds[i],envelope,spec)
		obstacle_envelopes[i]=envelope
		for cell in range(floori(envelope.position.y/400.0),floori(envelope.end.y/400.0)+1):
			if not dynamic_obstacle_bins.has(cell):dynamic_obstacle_bins[cell]=[]
			dynamic_obstacle_bins[cell].append(i)

# 地面/绳索每步多次采样，先索引地形类型，再使用原解析判定；不按距离删掉有效机关。
func indexed_terrain()->Array[int]:
	if terrain_index_epoch==elapsed and terrain_index_revision==revision and terrain_index_count==kinds.size():return terrain_indices
	terrain_index_epoch=elapsed;terrain_index_revision=revision;terrain_index_count=kinds.size()
	var signature:=kinds.hash()
	if signature!=terrain_index_signature:
		terrain_index_signature=signature;terrain_indices.clear()
		for i in range(kinds.size()):
			if kinds[i] in Terrain.KINDS:terrain_indices.append(i)
	var layout_signature := hash([kinds, obstacles, revision])
	if terrain_layout_signature == layout_signature: return terrain_indices
	terrain_layout_signature = layout_signature
	# 只缓存纵向范围；升降、开桥和横向渡船仍按真实查询时刻求值。
	terrain_bins.clear();moving_terrain.clear()
	for i in terrain_indices:
		if kinds[i]=="ferry":
			moving_terrain.append(i)
			continue
		for cell in range(floori(obstacles[i].position.y/400.0),floori(obstacles[i].end.y/400.0)+1):
			if not terrain_bins.has(cell):terrain_bins[cell]=[]
			terrain_bins[cell].append(i)
	return terrain_indices

func prepare_terrain_lookup() -> void:
	terrain_step_bins.clear()
	indexed_terrain()
	terrain_step_active = true

func terrain_candidates(y: float) -> Array:
	if terrain_step_active: return terrain_at(Vector2(0,y))
	return indexed_terrain()

func terrain_at(point:Vector2)->Array:
	indexed_terrain()
	var local:Array=terrain_bins.get(floori(point.y/400.0),[])
	if moving_terrain.is_empty():return local
	# 覆盖关系依赖原索引顺序；移动渡船仍按实际时间采样。
	var merged:=local+moving_terrain
	merged.sort()
	return merged

# 绳索质点在桥面上每次迭代都会采样吊桥；父类每次复制机关参数并用闭包查门，桥上明显掉帧。
# 这里按同一公式直接求值，结果与父类完全一致。
func terrain_sample(index:int,time:float,point:Vector2)->Dictionary:
	if kinds[index]!="drawbridge":return super(index,time,point)
	var gate_id:String=hazard_specs[index].get("gate_id","")
	var opening:=0.0
	for gate in charge_gates:
		if gate.id!=gate_id:continue
		var opened_at:float=gate.get("opened_at",-1.0)
		if gate.open and opened_at>=0:opening=clampf((time-opened_at)/0.6,0,1)
		break
	var rect:Rect2=obstacles[index]
	return {"rect":rect,"height":(1.0-opening)*100.0,"normal":Vector3.UP,"velocity":Vector3.ZERO,
		"friction":0.8,"opening":opening,"supported":rect.has_point(point) and opening>=0.999}

func surface_at(point:Vector2,time:float,radius:float=0.0)->Dictionary:
	var surface:={"supported":absf(point.x)<=EDGE,"height":0.0,"normal":Vector3.UP,"friction":0.8,"velocity":Vector3.ZERO}
	ground_gaps(time)
	var bins:Dictionary=ground_gap_bins[elapsed if time<0 else time]
	for cell in range(floori((point.y-radius)/400.0),floori((point.y+radius)/400.0)+1):
		for gap:Rect2 in bins.get(cell,[]):
			if gap.grow(radius).has_point(point):surface.supported=false
	for i in terrain_candidates(point.y):
		if kinds[i]!="ferry" and not obstacles[i].has_point(point):continue
		var sample:=terrain_sample(i,time,point)
		if sample.supported and sample.rect.grow(-radius).has_point(point):surface=sample
	return surface

func has_ground_support(point:Vector2,time:float=-1.0)->bool:
	var sample_time:=elapsed if time<0 else time
	# 普通路面无需为每个寻路采样分配完整表面字典；平台仍走原精确采样。
	for i in terrain_at(point):
		if kinds[i]=="ferry" or obstacles[i].has_point(point):
			return surface_at(point,sample_time,Motion.RADIUS).supported
	if absf(point.x)>EDGE:return false
	ground_gaps(sample_time)
	var bins:Dictionary=ground_gap_bins[sample_time]
	for cell in range(floori((point.y-Motion.RADIUS)/400.0),floori((point.y+Motion.RADIUS)/400.0)+1):
		for gap:Rect2 in bins.get(cell,[]):
			if gap.grow(Motion.RADIUS).has_point(point):return false
	return true

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
	for i in terrain_candidates(to.y):
		if kinds[i]!="ferry" and not obstacles[i].has_point(to):continue
		var sample:=terrain_sample(i,time,to)
		if sample.supported and sample.rect.grow(-Motion.RADIUS).has_point(from) and sample.rect.grow(-Motion.RADIUS).has_point(to):return true
	return false

func platform_motion(point:Vector2,start:float,end:float)->Vector2:
	for i in terrain_candidates(point.y):
		if kinds[i] not in Terrain.MOVING:continue
		var first:=terrain_sample(i,start,point)
		if first.rect.has_point(point):return terrain_sample(i,end,point).rect.position-first.rect.position
	return Vector2.ZERO

# 实体类型索引每个固定步最多刷新一次；几何位置仍由每次精确扫掠读取。
func indexed_solids()->Array[int]:
	if solid_query_epoch==elapsed and solid_query_revision==revision and solid_query_count==kinds.size():return solid_indices
	solid_query_epoch=elapsed;solid_query_revision=revision;solid_query_count=kinds.size()
	return super()

# 先排除整条新旧绳段都够不到的扫杆，再执行原有连续高度/旋转精确检测。
func sweeper_rope_hits(index:int,start:float,end:float,old_path:PackedVector2Array,old_z:PackedFloat32Array)->bool:
	var current:PackedVector2Array=rope.physical_path()
	if current.is_empty() or old_path.is_empty():return super(index,start,end,old_path,old_z)
	var bounds:=Rect2(old_path[0],Vector2.ZERO)
	for point in old_path:bounds=bounds.expand(point)
	for point in current:bounds=bounds.expand(point)
	var margin:=0.0
	if old_path.size()==current.size():
		for n in range(current.size()):margin=maxf(margin,old_path[n].distance_to(current[n]))
	else:margin=(speed()+LATERAL)*(end-start)
	# 原分片算法的圆弧包络至多 0.125；额外 1 为绳索半径，保守取 2。
	var reach:=maxf(Surfaces.POST_RADIUS,Surfaces.ARM_HALF+Surfaces.ARM_RADIUS)+margin+2.0
	if not bounds.grow(reach).has_point(obstacles[index].get_center()):return false
	return super(index,start,end,old_path,old_z)
