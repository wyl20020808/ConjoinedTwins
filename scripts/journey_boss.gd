extends RefCounted
# 第一章终点 Boss「枯根巨像」。Boss 是 journey_events 中 kind=="boss" 的事件，
# 全部状态为可深拷贝的数据，按固定步与模拟时间推进：随存档恢复、联机两端一致。
# 设计依据见 docs/BOSS_CH1_DESIGN.md。坐标为道路单位（20 = 1 米），+y 为前进方向。

const CHAPTERS := [0]
# 场地长度、树心与玩家前进上限都相对场地入口（章节终点之前 ARENA）。
const ARENA := 1800.0
const TRIGGER := 300.0
const HOLD := 1380.0
# 开战后场地内可以自由前后走：最远退到入口根墙前（场地起点 + FLOOR），不受旅程“最多后退 10 米”的限制。
const FLOOR := 120.0
# 打 Boss 时各种枪的射程额外 +25 米，不必贴脸输出。
const RANGE_BONUS := 500.0
const CORE := 1540.0
const NAME := "枯根巨像"
const MAX_HP := 3000
# 护甲状态只吃 25% 伤害；硬直（树心暴露）满伤害。本地键盘 02 号没有射击键，血量按单人输出也能约两分钟打完来定。
const ARMOR := 0.25
const STAGES := [0.65, 0.30]
# 各阶段前摇倍率与每轮攻击数；轮末必定扎根汲取，给出破甲窗口。
const PACE := [1.0, 0.9, 0.75]
const MOVES := [2, 3, 3]
# 每个阶段都有召唤，每轮约出现两次。
const PATTERN := [["spikes","summon","sweep","seeds","sweep","spikes","summon","seeds"],
	["summon","sweep","spikes","seeds","summon","sweep","seeds","spikes"],
	["summon","sweep","spikes","seeds","summon","seeds","sweep","spikes"]]
# 入场动画（电影式）：拉高拉远 → 破土泼土、蜷成一团钻出并在上升中逐渐舒展绽放 → 烟散 → 左右挥爪抓人 → 仰天咆哮 → 镜头交还。
# 期间两人不能操作、不受伤害，Boss 不能被锁定；任一人按跳跃可跳过（剩 RETURN_TIME 秒的镜头交还）。
# 各节点为距开战的秒数，画面与音效按同一时间轴取样。
const INTRO := 13.2
const INTRO_CRANE := 2.0
const INTRO_RISE := 2.3
const INTRO_RISEN := 5.6
const INTRO_REVEAL := 6.4
const INTRO_ROAR := 9.2
const INTRO_ROARED := 11.8
const INTRO_SKIP_AFTER := 0.8
const RETURN_TIME := 1.4
const ROAR := 2.2
const GAP := 0.9
const RECOVER := 0.8
const STAGGER := 6.0
# 根刺：沿锁定直线从 Boss 脚下冲向镜头，钻出后停留 0.5 秒。
const SPIKE_WINDUP := 1.2
const SPIKE_SPEED := 900.0
const SPIKE_HALF := 28.0
const SPIKE_LINGER := 0.5
const SPIKE_DAMAGE := 25
# 横扫：根臂贴地一挥，掀起一道沿道路纵向铺满整个场地的根浪横扫全宽，跳起高于 SWEEP_TOP 才能躲开。
# 二阶段起双臂连扫。根浪 1.1 秒滚过全宽（原 0.6 秒），玩家看得清来向再起跳；第二臂等第一臂扫完再出手。
# 根浪变慢后在人身上停留更久，判定宽度同步收窄到贴地根浪本身的厚度，起跳窗口约 0.35 秒。
const SWEEP_WINDUP := 1.4
const SWEEP_TIME := 1.1
const SWEEP_SECOND := 1.4
const SWEEP_HALF := 22.0
const SWEEP_TOP := 16.0
const SWEEP_DAMAGE := 35
const SWEEP_DEPTH := HOLD-FLOOR
# 孢果：前摇期间落点一直跟着两人走，出手瞬间锁定；前两颗砸在两人脚下，其余落在身边 3 米内。
const SEED_WINDUP := 1.3
const SEED_FLIGHT := 1.0
const SEED_RADIUS := 70.0
const SEED_DAMAGE := 20
const SEED_OFFSETS := [Vector2.ZERO, Vector2.ZERO, Vector2(60,35), Vector2(-60,-30), Vector2(35,-65), Vector2(-40,70)]
const SUMMON_WINDUP := 1.0
# 召唤：前两阶段每次 3 只、三阶段 4 只根须蛛（原每次 2 只）；场上活着的超过 SUMMON_CAP 只时跳过。
const SUMMON_X := [-240.0,240.0,-120.0,120.0]
const SUMMON_CAP := 4
# 缠柱（破甲机会）：场地左侧立着一根石柱（偏离中线，两人并排前后走时绳子不会被它挂住）。扎根汲取时一人绕柱转一圈，用能量绳把它缠住即可让 Boss 萎靡。
# 进度按两人绕柱心的相对转角累计（柱子比绳高，绕过去绳子必然缠上），完成时绳子须挂在柱上。
# 缠紧后石柱崩碎、绳子松开，两人立即可以走开输出；下一次扎根汲取时石柱在原地重新升起。
const PILLAR := Vector2(-170,950)
const PILLAR_HALF := 12.0
const WRAP_TURN := 0.85
const ROOT_WINDUP := 1.0
const ROOT_LIMIT := 14.0
const RIP_DAMAGE := 30
const RIP_TOP := 12.0
# 三阶段道路两侧长出荆棘，贴边扣血（每秒最多一次）。
const THORN_WIDTH := 60.0
const THORN_DAMAGE := 10
# 场内补给放在射击站位附近：旅程只允许后退 10 米，放在场地前段的补给开战后就拿不到了。
const SUPPLY := 1200.0
# 战斗中每 AMMO_EVERY 秒在两人附近随机掉一盒弹药（每第三次改掉医疗包，抵消更多小怪的压力），
# 场上最多 AMMO_CAP 份；位置由 Boss 序号与掉落序号决定，联机两端一致。
const AMMO_EVERY := 7.0
const AMMO_CAP := 3

static func enabled(run) -> bool:
	return not run.combat_trial and run.level_index in CHAPTERS

static func start_y(run) -> float:
	return run.finish_distance()-ARENA

# 站位约束每个子步都要查 Boss；按登记时记下的下标直接取，失配时再整表查找。
static func boss(run) -> Dictionary:
	var index:int=run.boss_index
	if index>=0 and index<run.journey_events.size() and run.journey_events[index].kind=="boss": return run.journey_events[index]
	# 非 Boss 章节及训练场没有 Boss；避免每次边界、射程与镜头查询扫描整张事件表。
	if index<0 and not enabled(run): return {}
	for event in run.journey_events:
		if event.kind=="boss": return event
	return {}

# 开战后的后退下限；未开战或已击败时不限制（INF）。
static func floor_y(run) -> float:
	var event:=boss(run)
	if not alive(event) or event.phase=="dormant": return INF
	return event.arena+FLOOR

static func alive(event: Dictionary) -> bool:
	return not event.is_empty() and event.hp>0

# Boss 存活时两人最多前进到树心前方 8 米。
static func hold_y(run) -> float:
	var event:=boss(run)
	if not alive(event): return INF
	return event.arena+HOLD

static func add(run) -> void:
	if not enabled(run): return
	var arena:=start_y(run)
	var core:=Vector2(0,arena+CORE)
	var body:=Rect2(-180,core.y-40,360,220)
	run.boss_index=run.journey_events.size()
	run.journey_events.append({"id":run.event_serial,"kind":"boss","arena":arena,"y":core.y,"origin":core,"spawn":core,
		"rect":body,"sample":body,"previous":body,"bottom":0.0,"top":0.0,"side":0.0,"locked_x":0.0,"combined":false,"obstacle":-1,
		"trigger":-1.0,"phase":"dormant","hp":MAX_HP,"max_hp":MAX_HP,"stage":0,
		"state":"idle","state_at":0.0,"skill":"","skill_seq":0,"cycle_moves":0,"pattern_index":0,
		"lanes":[],"sweep_side":1.0,"targets":[],"binding":Vector2.ZERO,"burn":0.0,"burned":false,
		"radius":120.0,"stagger_count":0,"adds":[],"stage_at":0.0,"pillar":-1,"wrap_prev":0.0,"ammo_at":0.0,"ammo_drops":0})
	run.event_serial+=1
	var boss_event:Dictionary=run.journey_events[-1]
	boss_event.binding=pillar_center(boss_event)
	var pillar:int=run.add_hazard("pillar",Rect2(boss_event.binding-Vector2.ONE*PILLAR_HALF,Vector2.ONE*PILLAR_HALF*2))
	boss_event.pillar=run.obstacle_ids[pillar]
	# 入口两侧各一把枪（间距小于绳长，两人可同时拾取），场地内不放其他补给，硬直结束与换阶段时再刷新。
	run.Combat.add_pickup(run,"gun",Vector2(-60,arena+160),{},"smg")
	run.Combat.add_pickup(run,"gun",Vector2(60,arena+160),{},"shotgun")
	for x in [-150.0,150.0]: run.Combat.add_pickup(run,"ammo",Vector2(x,arena+220))
	for x in [-50.0,50.0]: run.Combat.add_pickup(run,"medkit",Vector2(x,arena+220))

static func cinematic(run) -> bool:
	var event:=boss(run)
	return alive(event) and event.phase=="intro"

# 跳过入场：直接进入最后的镜头交还段，模拟时间轴整体前移，各端结果一致。
static func skip_intro(run) -> void:
	var event:=boss(run)
	if not cinematic(run) or run.elapsed-event.state_at<INTRO_SKIP_AFTER or run.elapsed-event.state_at>=INTRO-RETURN_TIME: return
	event.state_at=run.elapsed-(INTRO-RETURN_TIME)
	event.intro_skipped=true

static func pace(event: Dictionary) -> float:
	return PACE[event.stage]

static func age(run, event: Dictionary) -> float:
	return run.elapsed-event.state_at

static func enter(run, event: Dictionary, state: String) -> void:
	event.state=state
	event.state_at=run.elapsed

# 受到的伤害：护甲与硬直倍率。由 Combat.damage 调用，结果保持整数且至少 1。
static func incoming(event: Dictionary, amount: int) -> int:
	if event.get("state","")=="stagger": return amount
	return maxi(1,roundi(amount*ARMOR))

static func exposed(event: Dictionary) -> bool:
	return event.get("state","")=="stagger"

static func advance(run, event: Dictionary) -> void:
	if event.hp<=0: return
	if event.phase=="dormant":
		if minf(run.a.position.y,run.b.position.y)<event.arena+TRIGGER: return
		# 开战前存档：失败后从场地入口重打，Boss 回到满血沉睡。
		run.capture_checkpoint()
		event.phase="intro"
		event.trigger=run.elapsed
		enter(run,event,"intro")
		return
	match event.state:
		"intro":
			if age(run,event)>=INTRO:
				event.phase="fight"
				event.ammo_at=run.elapsed+AMMO_EVERY*0.5
				enter(run,event,"idle")
		"roar":
			if age(run,event)>=ROAR: enter(run,event,"idle")
		"idle":
			if age(run,event)>=GAP*pace(event): choose(run,event)
		"recover":
			if age(run,event)>=RECOVER*pace(event): enter(run,event,"idle")
		"stagger":
			if age(run,event)>=STAGGER:
				resupply(run,event)
				enter(run,event,"idle")
		"spikes": spikes(run,event)
		"sweep": sweep(run,event)
		"seeds": seeds(run,event)
		"summon": summon(run,event)
		"root": root(run,event)
	if event.stage==2: thorns(run,event)
	if event.phase=="fight": drop_ammo(run,event)

static func choose(run, event: Dictionary) -> void:
	# 阶段转换优先：血量越过门槛后的下一个空档怒吼并换招。
	var ratio:float=float(event.hp)/event.max_hp
	if event.stage<STAGES.size() and ratio<=STAGES[event.stage]:
		event.stage+=1
		event.stage_at=run.elapsed
		event.cycle_moves=0
		event.pattern_index=0
		run.Combat.add_pickup(run,"medkit",Vector2(0,event.arena+SUPPLY-60))
		run.combat.notice="%s进入第 %d 阶段"%[NAME,event.stage+1]
		enter(run,event,"roar")
		# 保存换阶段时的双方位置、血量、弹药、Boss 与场内状态，失败从本阶段继续。
		run.capture_checkpoint()
		return
	event.skill_seq+=1
	if event.cycle_moves>=MOVES[event.stage]:
		event.cycle_moves=0
		start_root(run,event)
		return
	var pattern:Array=PATTERN[event.stage]
	var skill:String=pattern[event.pattern_index%pattern.size()]
	event.pattern_index+=1
	# 场上召唤物太多时跳过召唤。
	if skill=="summon" and living_adds(run,event)>SUMMON_CAP-summon_count(event):
		skill=pattern[event.pattern_index%pattern.size()]
		event.pattern_index+=1
	event.cycle_moves+=1
	event.skill=skill
	match skill:
		"spikes": start_spikes(run,event)
		"sweep":
			event.sweep_side=-event.sweep_side
			enter(run,event,"sweep")
		"seeds": start_seeds(run,event)
		"summon": enter(run,event,"summon")

static func players(run) -> Array:
	return [run.a.position,run.b.position]

static func hit(run, event: Dictionary, role: int, skill: String, amount: int) -> void:
	run.Combat.hit(run,role,"boss:%s:%d"%[skill,event.skill_seq],amount)

# —— 根刺突袭 ——

static func start_spikes(run, event: Dictionary) -> void:
	# 两条直线锁定两人当前横向位置，其余直线放在离两人最远的空当上；三阶段 5 道。
	var lanes:Array=[]
	for point in players(run): lanes.append(clampf(point.x,-run.EDGE+SPIKE_HALF,run.EDGE-SPIKE_HALF))
	var extra:=3 if event.stage==2 else 1
	var candidates:=[-240.0,240.0,0.0,-120.0,120.0]
	for x in candidates:
		if lanes.size()>=2+extra: break
		if lanes.all(func(l):return absf(l-x)>=100.0): lanes.append(x)
	event.lanes=lanes
	enter(run,event,"spikes")

static func spike_front(run, event: Dictionary, time: float) -> float:
	var travel:=maxf(0.0,time-event.state_at-SPIKE_WINDUP*pace(event))
	return event.origin.y-100.0-travel*SPIKE_SPEED

static func spikes(run, event: Dictionary) -> void:
	var windup:float=SPIKE_WINDUP*pace(event)
	var front:=spike_front(run,event,run.elapsed)
	if age(run,event)>=windup:
		for role in range(2):
			var point:Vector2=players(run)[role]
			if run.foot_height(role)>=60.0: continue
			for x in event.lanes:
				if absf(point.x-x)<SPIKE_HALF+run.Motion.RADIUS and point.y>=front and point.y<=front+SPIKE_SPEED*SPIKE_LINGER:
					hit(run,event,role,"spikes",SPIKE_DAMAGE)
	if front+SPIKE_SPEED*SPIKE_LINGER<event.arena: enter(run,event,"recover")

# —— 巨臂横扫 ——

# 扫臂当前横向位置；返回 INF 表示该臂尚未出手或已经扫完。
static func sweep_x(run, event: Dictionary, time: float, arm: int) -> float:
	var start:float=event.state_at+SWEEP_WINDUP*pace(event)+arm*SWEEP_SECOND
	var t:=(time-start)/SWEEP_TIME
	if t<0.0 or t>1.0: return INF
	var side:float=event.sweep_side*(1.0 if arm==0 else -1.0)
	var reach:float=run.EDGE+60.0
	return lerpf(side*reach,-side*reach,t)

static func sweep_arms(event: Dictionary) -> int:
	return 2 if event.stage>=1 else 1

static func sweep(run, event: Dictionary) -> void:
	for arm in range(sweep_arms(event)):
		var now:=sweep_x(run,event,run.elapsed,arm)
		if now==INF: continue
		var before:=sweep_x(run,event,run.elapsed-run.FIXED_STEP,arm)
		if before==INF: before=now
		var low:float=minf(before,now)-SWEEP_HALF-run.Motion.RADIUS
		var high:float=maxf(before,now)+SWEEP_HALF+run.Motion.RADIUS
		for role in range(2):
			var point:Vector2=players(run)[role]
			if point.x>=low and point.x<=high and point.y>=event.arena+HOLD-SWEEP_DEPTH and run.foot_height(role)<SWEEP_TOP:
				hit(run,event,role,"sweep%d"%arm,SWEEP_DAMAGE)
	var done:float=SWEEP_WINDUP*pace(event)+(sweep_arms(event)-1)*SWEEP_SECOND+SWEEP_TIME
	if age(run,event)>=done: enter(run,event,"recover")

# —— 孢果投掷 ——

static func start_seeds(run, event: Dictionary) -> void:
	aim_seeds(run,event)
	enter(run,event,"seeds")

static func aim_seeds(run, event: Dictionary) -> void:
	var count:=6 if event.stage==2 else 4
	var targets:Array=[]
	for n in range(count):
		var point:Vector2=players(run)[n%2]+SEED_OFFSETS[n]
		point.x=clampf(point.x,-run.EDGE+30,run.EDGE-30)
		point.y=clampf(point.y,event.arena+120,event.arena+HOLD)
		targets.append(point)
	event.targets=targets

static func seed_land_age(event: Dictionary) -> float:
	return SEED_WINDUP*PACE[event.stage]+SEED_FLIGHT

static func seeds(run, event: Dictionary) -> void:
	if age(run,event)<SEED_WINDUP*pace(event): aim_seeds(run,event)
	var land:=seed_land_age(event)
	if age(run,event)>=land and age(run,event)-run.FIXED_STEP<land:
		for target:Vector2 in event.targets:
			for role in range(2):
				if players(run)[role].distance_to(target)<SEED_RADIUS+run.Motion.RADIUS and run.foot_height(role)<40.0:
					hit(run,event,role,"seeds",SEED_DAMAGE)
	if age(run,event)>=land+0.4: enter(run,event,"recover")

# —— 召唤根须蛛 ——

static func summon(run, event: Dictionary) -> void:
	if age(run,event)<SUMMON_WINDUP*pace(event): return
	# 从 Boss 两侧的地面钻出，要先爬过来，给玩家转火的时间。
	for point in summon_points(event):
		var monster:Dictionary=run.Monsters.add(run,point,"forest","root_spider")
		monster.alert=true
		monster.boss_add=true
		event.adds.append(monster.id)
	enter(run,event,"recover")

static func summon_count(event: Dictionary) -> int:
	return 4 if event.stage==2 else 3

static func summon_points(event: Dictionary) -> Array:
	var result:Array=[]
	for n in range(summon_count(event)): result.append(Vector2(SUMMON_X[n],event.arena+HOLD+100))
	return result

static func living_adds(run, event: Dictionary) -> int:
	var count:=0
	for other in run.journey_events:
		if other.kind=="monster" and other.id in event.adds and other.hp>0: count+=1
	return count

# —— 扎根汲取 / 缠柱（破甲机会）——

static func start_root(run, event: Dictionary) -> void:
	event.binding=pillar_center(event)
	event.burn=0.0
	event.wrap_prev=relative_angle(run,event)
	event.burned=false
	event.skill="root"
	enter(run,event,"root")

static func pillar_center(event: Dictionary) -> Vector2:
	return Vector2(PILLAR.x,event.arena+PILLAR.y)

# 两人绕柱心的相对方位角；一人站定、另一人绕柱一圈时变化 2π。
static func relative_angle(run, event: Dictionary) -> float:
	var center:=pillar_center(event)
	return (run.b.position-center).angle()-(run.a.position-center).angle()

# 绳子此刻是否挂在缠柱上。
static func rope_on_pillar(run, event: Dictionary) -> bool:
	for contact in run.rope.contacts:
		if contact.id==event.get("pillar",-1) and contact.wrap>0.0: return true
	return false

static func pillar_index(run, event: Dictionary) -> int:
	return run.obstacle_ids.find(event.get("pillar",-1))

static func pillar_up(run, event: Dictionary) -> bool:
	var index:=pillar_index(run,event)
	return index>=0 and absf(run.obstacles[index].get_center().x-pillar_center(event).x)<1.0

# 升起或沉下缠柱：沉下时把碰撞体移出道路（与倒树相同的做法），画面跟随碰撞体。
static func set_pillar(run, event: Dictionary, up: bool) -> void:
	var index:=pillar_index(run,event)
	if index<0: return
	var center:=pillar_center(event)
	if not up: center.x=run.EDGE+1000.0
	run.obstacles[index].position=center-Vector2.ONE*PILLAR_HALF

# 原地没有人、绳子也不穿过柱位时才能升起，避免把人或绳子卡进柱子里。
static func pillar_clear(run, event: Dictionary) -> bool:
	var center:=pillar_center(event)
	for point in players(run):
		if point.distance_to(center)<PILLAR_HALF+run.Motion.RADIUS+4.0: return false
	var path:PackedVector2Array=run.rope.physical_path()
	for n in range(1,path.size()):
		if Geometry2D.get_closest_point_to_segment(center,path[n-1],path[n]).distance_to(center)<PILLAR_HALF+run.ROPE_CLEARANCE+4.0: return false
	return true

static func root(run, event: Dictionary) -> void:
	var windup:float=ROOT_WINDUP*pace(event)
	if not pillar_up(run,event) and pillar_clear(run,event): set_pillar(run,event,true)
	var now:=relative_angle(run,event)
	var turned:=wrapf(now-float(event.wrap_prev),-PI,PI)
	event.wrap_prev=now
	if age(run,event)<windup or not pillar_up(run,event): return
	# 正反方向都算，往回绕会抵消。
	event.burn=float(event.burn)+turned
	if burn_ratio(event)>=1.0 and rope_on_pillar(run,event):
		event.burned=true
		event.stagger_count+=1
		run.combat.notice="石柱缠紧！%s萎靡跪倒，树心暴露"%NAME
		set_pillar(run,event,false)
		run.rope.reset(run.a.position,run.b.position)
		enter(run,event,"stagger")
		return
	# 超时：根臂拔出，全场冲击，只有跳起的人躲得开。
	if age(run,event)>=windup+ROOT_LIMIT:
		for role in range(2):
			if run.foot_height(role)<RIP_TOP: hit(run,event,role,"rip",RIP_DAMAGE)
		enter(run,event,"recover")

static func burn_ratio(event: Dictionary) -> float:
	return clampf(absf(event.get("burn",0.0))/(TAU*WRAP_TURN),0.0,1.0)

# 根臂拔出前 1.5 秒为警示期（画面闪烁、提示跳起）。
static func rip_warning(run, event: Dictionary) -> bool:
	return event.state=="root" and age(run,event)>=ROOT_WINDUP*pace(event)+ROOT_LIMIT-1.5

# —— 三阶段：两侧荆棘 ——

static func thorns(run, event: Dictionary) -> void:
	for role in range(2):
		var point:Vector2=players(run)[role]
		if absf(point.x)>run.EDGE-THORN_WIDTH and point.y>=event.arena and run.foot_height(role)<20.0:
			run.Combat.hit(run,role,"boss:thorns",THORN_DAMAGE,true)

# —— 补给 ——

static func resupply(run, event: Dictionary) -> void:
	for x in [-200.0,200.0]:
		var point:=Vector2(x,event.arena+SUPPLY)
		if run.combat.pickups.any(func(p):return p.kind=="ammo" and p.position.distance_to(point)<10): continue
		run.Combat.add_pickup(run,"ammo",point)

# 战斗中定时在两人附近随机掉补给。
static func drop_ammo(run, event: Dictionary) -> void:
	if run.elapsed<float(event.get("ammo_at",0.0)): return
	event.ammo_at=run.elapsed+AMMO_EVERY
	var serial:int=event.get("ammo_drops",0)
	var kind:="medkit" if serial%3==2 else "ammo"
	if run.combat.pickups.filter(func(p):return p.kind==kind and p.position.y>event.arena).size()>=AMMO_CAP: return
	event.ammo_drops=serial+1
	var rng:=RandomNumberGenerator.new()
	rng.seed=int(event.id)*92821+serial*7919+17
	var middle:float=(run.a.position.y+run.b.position.y)*0.5
	var point:=Vector2(rng.randf_range(-run.EDGE+70,run.EDGE-70),clampf(middle+rng.randf_range(-220.0,220.0),event.arena+FLOOR+80,event.arena+HOLD-60))
	if point.distance_to(pillar_center(event))<70.0: point.x+=140.0 if point.x<=0.0 else -140.0
	run.Combat.add_pickup(run,kind,point)

# —— 提示 ——

static func hint(run) -> String:
	var event:=boss(run)
	if event.is_empty() or event.phase=="dormant": return ""
	if event.hp<=0: return "%s倒下了，继续前进"%NAME if run.elapsed-event.get("defeated_at",run.elapsed)<6.0 else ""
	match event.state:
		"intro": return ""
		"roar": return "%s怒吼：阶段 %d"%[NAME,event.stage+1]
		"spikes": return "根刺突袭：离开地面亮起的直线"
		"sweep": return "巨臂横扫：两人一起跳起躲过根臂" if sweep_arms(event)==1 else "双臂连扫：连跳两次"
		"seeds": return "孢果投掷：离开落点圆圈"
		"summon": return "召唤根须蛛：先清理小怪"
		"root":
			if rip_warning(run,event): return "根臂即将拔出：跳起躲避冲击！缚根 %d%%"%int(burn_ratio(event)*100)
			if not pillar_up(run,event): return "扎根汲取：石柱即将升起，先让开柱位"
			return "扎根汲取：绕发光石柱转一圈，用能量绳缠住它 · %d%%"%int(burn_ratio(event)*100)
		"stagger": return "树心暴露！全力输出"
	return ""
