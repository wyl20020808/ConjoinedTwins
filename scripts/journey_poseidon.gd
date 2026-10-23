extends RefCounted
# 第三章终点 Boss「海神波塞冬」。与前两章相同，Boss 是 journey_events 中 kind=="boss" 的事件（species=="poseidon"），
# 全部状态为可深拷贝的数据，按固定步与模拟时间推进：随存档恢复、联机两端一致。
# 入口与通用规则（站位上限、护甲、锁定）由 journey_boss.gd 分派；设计依据见 docs/BOSS_CH3_DESIGN.md。
# 坐标为道路单位（20 = 1 米），+y 为前进方向；海神悬浮在场地尽头的深潭上方，面朝两人（-y）。

const SPECIES := "poseidon"
const CHAPTER := 2
const NAME := "海神波塞冬"
const EPITHET := "自遗迹深潭升起的怒涛之主"
# 场地尺寸与前两章一致（journey_boss.gd 的 ARENA/TRIGGER/HOLD/FLOOR 按这些值计算站位与镜头）。
const ARENA := 1800.0
const TRIGGER := 300.0
const HOLD := 1380.0
const FLOOR := 120.0
# 深潭从 S+POOL_NEAR 开始；海神悬浮在落点上方 HOVER（约 3.5 米），在 ±DRIFT 之间缓慢左右漂移。
# 瞄准点是胸口海神之心（模型放大 16 倍，胸口离身体底部约 11 米）。
const POOL_NEAR := 1440.0
const PERCH := 1600.0
const HOVER := 70.0
const DRIFT := 110.0
const DRIFT_RATE := 0.33
const CHEST_HEIGHT := 220.0
const MAX_HP := 2000
const STAGES := [0.65, 0.30]
const PACE := [1.0, 0.88, 0.75]
const MOVES := [2, 3, 3]
# 二阶段起加入怒涛震环；三阶段道路两侧海水漫上来。每轮都可能召唤潮汐水母。
const PATTERN := [["lance","geysers","wave","summon","lance","geysers"],
	["wave","lance","summon","geysers","ring","wave","lance","summon","geysers"],
	["wave","ring","lance","summon","geysers","wave","lance","ring","summon"]]

# —— 入场（电影式，约 13 秒）——
# 0–1.2 镜头转向深潭 → 1.2–4.5 潭水翻涌、旋涡扩大 → 4.5–7.0 海神破水升起（4.6 秒水柱冲天）→ 7.6–10.0 高举三叉神矛、雷光、
# 标题浮现 → 10.0–11.8 神矛顿向水面掀起浪圈 → 11.8–13.0 镜头交还。
const INTRO := 13.0
const INTRO_STIR := 1.2
const INTRO_RISE := 4.5
const INTRO_RISEN := 7.0
const INTRO_RAISE := 7.6
const INTRO_SLAM := 10.0
const INTRO_SKIP_AFTER := 0.8
const RETURN_TIME := 1.2
const DEPTH := 300.0

const ROAR := 2.2
const GAP := 0.9
const RECOVER := 0.8
const STAGGER := 7.0

# —— 三叉激流：神矛指向一人，水柱沿锁定直线激射；二阶段起同时射向两人，三阶段再加一道射向两人中点 ——
# 前摇期间直线一直跟着目标，出手瞬间锁定，0.5 秒后水柱射出（够横跑约 90）；水柱齐腰高，跳不过去，只能横向让开。
const LANCE_WINDUP := 1.3
const LANCE_DELAY := 0.5
const LANCE_FIRE := 0.7
const LANCE_HALF := 30.0
const LANCE_LENGTH := 1700.0
const LANCE_DAMAGE := 28

# —— 巨浪：整面水墙从海神脚下朝镜头推过来，只在一处留出缺口（亮起的安全通道），两人一起钻进缺口；二阶段起连续两道，缺口换边 ——
const WAVE_WINDUP := 1.4
const WAVE_SPEED := 520.0
const WAVE_HALF := 30.0
const WAVE_GAP := 72.0
const WAVE_SECOND := 1.6
const WAVE_START := 140.0
const WAVE_DAMAGE := 30

# —— 涌泉：落点圆圈跟着两人走，出手时锁定，片刻后水柱从地下喷出；落点留下旋涡水洼 ——
const GEYSER_WINDUP := 1.1
const GEYSER_DELAY := 0.9
const GEYSER_RADIUS := 66.0
const GEYSER_DAMAGE := 22
const GEYSER_OFFSETS := [Vector2.ZERO, Vector2.ZERO, Vector2(85,45), Vector2(-85,-40), Vector2(40,-95), Vector2(-55,95), Vector2(125,-15)]
const PUDDLE_RADIUS := 52.0
const PUDDLE_TIME := 3.0
const PUDDLE_DAMAGE := 8

# —— 召唤：潮汐水母（远程水弹）从深潭浮起，2/3/4 只；场上召唤物太多时跳过。
# 曾在三阶段加一只河岸钳甲兵（135 血、近战 32），与海神招式叠加压力过大，已去掉，保留接口。
const SUMMON_WINDUP := 1.2
const SUMMON_RECOVER := 0.5
const SUMMON_JELLY := [3, 4, 5]
const SUMMON_CRAB := [0, 0, 0]
const SUMMON_X := [-180.0, 180.0, 0.0, -90.0, 90.0]
const SUMMON_CAP := 5

# —— 怒涛震环（二阶段起）：神矛顿向水面，水环向外扩散，跳起躲开；三阶段连续两道 ——
const RING_WINDUP := 1.1
const RING_SPEED := 700.0
const RING_HALF := 26.0
const RING_TOP := 14.0
const RING_SECOND := 0.7
const RING_DAMAGE := 28

# —— 潮汐之心（破甲机会）：海神双手高举凝聚水球，水球落到场地中段（S+ORB_Y）左右缓慢摆动；
# 两人分站水球两侧，让能量绳横穿水球（绳与球心距离小于 ORB_RADIUS），站稳累计 HOLD_TIME 秒，能量顺着绳子灌进水球，
# 水球炸开、海神被震落到水面（硬直 7 秒，海神之心暴露，满伤害）。期间海神朝两人轮流掷水弹，圆圈内会被打中，侧身让开；
# 绳子不穿过水球时进度缓慢回落；CHANNEL_LIMIT 秒内未完成则海啸：全场水环，跳起躲避。
const ORB_Y := 1000.0
const ORB_SWAY := 90.0
const ORB_RATE := 0.8
const ORB_RADIUS := 36.0
const ORB_DROP := 1.2
const HOLD_TIME := 2.8
const HOLD_DECAY := 0.4
const CHANNEL_WINDUP := 1.0
const CHANNEL_LIMIT := 14.0
const BOLT_EVERY := 3.0
const BOLT_FLIGHT := 1.0
const BOLT_RADIUS := 50.0
const BOLT_DAMAGE := 16
const TSUNAMI_SPEED := 820.0
const TSUNAMI_HALF := 30.0
const TSUNAMI_TOP := 14.0
const TSUNAMI_DAMAGE := 32

# 三阶段两侧海水漫上道路。
const FLOOD_WIDTH := 60.0
const FLOOD_DAMAGE := 10

const SUPPLY := 1200.0
const AMMO_EVERY := 7.0
const AMMO_CAP := 3

static func enabled(run) -> bool:
	return not run.combat_trial and run.level_index == CHAPTER

static func add(run) -> void:
	var arena: float=run.finish_distance()-ARENA
	var perch:=Vector2(0,arena+PERCH)
	var body:=Rect2(-160,perch.y-60,320,200)
	run.boss_index=run.journey_events.size()
	run.journey_events.append({"id":run.event_serial,"kind":"boss","species":SPECIES,"arena":arena,"y":perch.y,"origin":perch,"spawn":perch,
		"perch":perch,"aim_height":CHEST_HEIGHT+HOVER,"airborne":true,
		"rect":body,"sample":body,"previous":body,"bottom":0.0,"top":0.0,"side":0.0,"locked_x":0.0,"combined":false,"obstacle":-1,
		"trigger":-1.0,"phase":"dormant","hp":MAX_HP,"max_hp":MAX_HP,"stage":0,
		"state":"idle","state_at":0.0,"skill":"","skill_seq":0,"cycle_moves":0,"pattern_index":0,
		"targets":[],"lances":[],"lance_from":Vector2.ZERO,"puddles":[],"gaps":[],
		"hold":0.0,"orb_on":false,"bolt_seq":0,"bolt_target":Vector2.ZERO,"stagger_count":0,"stage_at":0.0,"ammo_at":0.0,"ammo_drops":0,"adds":[]})
	run.event_serial+=1
	# 入口两侧各一把枪（间距小于绳长，两人可同时拾取），另有弹药与医疗包；硬直结束与换阶段时再刷新。
	run.Combat.add_pickup(run,"gun",Vector2(-60,arena+160),{},"smg")
	# 海神悬浮在 20 米开外，霰弹枪弹丸散得太开；与魔龙一样给榴弹发射器。
	run.Combat.add_pickup(run,"gun",Vector2(60,arena+160),{},"launcher")
	for x in [-150.0,150.0]: run.Combat.add_pickup(run,"ammo",Vector2(x,arena+220))
	for x in [-50.0,50.0]: run.Combat.add_pickup(run,"medkit",Vector2(x,arena+220))

static func pace(event: Dictionary) -> float:
	return PACE[event.stage]

static func age(run, event: Dictionary) -> float:
	return run.elapsed-event.state_at

static func enter(run, event: Dictionary, state: String) -> void:
	event.state=state
	event.state_at=run.elapsed

static func players(run) -> Array:
	return [run.a.position,run.b.position]

static func hit(run, event: Dictionary, role: int, skill: String, amount: int) -> void:
	run.Combat.hit(run,role,"boss:%s:%d"%[skill,event.skill_seq],amount)

static func skip_intro(run, event: Dictionary) -> void:
	if run.elapsed-event.state_at<INTRO_SKIP_AFTER or run.elapsed-event.state_at>=INTRO-RETURN_TIME: return
	event.state_at=run.elapsed-(INTRO-RETURN_TIME)
	event.intro_skipped=true

static func advance(run, event: Dictionary) -> void:
	if event.hp<=0:
		if not event.has("death_pos"): event.death_pos=event.origin
		update_body(run,event)
		return
	if event.phase=="dormant":
		if minf(run.a.position.y,run.b.position.y)<event.arena+TRIGGER: return
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
				enter(run,event,"recover")
		"lance": lance(run,event)
		"wave": wave(run,event)
		"geysers": geysers(run,event)
		"summon": summon(run,event)
		"ring": ring(run,event)
		"channel": channel(run,event)
		"tsunami": tsunami(run,event)
	update_body(run,event)
	puddles(run,event)
	if event.stage==2: flood(run,event)
	if event.phase=="fight": drop_ammo(run,event)

static func choose(run, event: Dictionary) -> void:
	var ratio:float=float(event.hp)/event.max_hp
	if event.stage<STAGES.size() and ratio<=STAGES[event.stage]:
		event.stage+=1
		event.stage_at=run.elapsed
		event.cycle_moves=0
		event.pattern_index=0
		run.Combat.add_pickup(run,"medkit",Vector2(0,event.arena+SUPPLY-60))
		run.combat.notice="%s进入第 %d 阶段"%[NAME,event.stage+1]
		enter(run,event,"roar")
		# 与前两章相同：换阶段时存档，失败从本阶段继续。
		run.capture_checkpoint()
		return
	event.skill_seq+=1
	if event.cycle_moves>=MOVES[event.stage]:
		event.cycle_moves=0
		start_channel(run,event)
		return
	var pattern:Array=PATTERN[event.stage]
	var skill:String=pattern[event.pattern_index%pattern.size()]
	event.pattern_index+=1
	if skill=="summon" and living_adds(run,event)>SUMMON_CAP-summon_count(event):
		skill=pattern[event.pattern_index%pattern.size()]
		event.pattern_index+=1
	event.cycle_moves+=1
	event.skill=skill
	match skill:
		"lance":
			aim_lances(run,event)
			enter(run,event,"lance")
		"wave":
			plan_gaps(run,event)
			enter(run,event,"wave")
		"geysers":
			aim_geysers(run,event)
			enter(run,event,"geysers")
		"summon": enter(run,event,"summon")
		"ring": enter(run,event,"ring")

# —— 身体：悬浮在深潭上方，左右缓慢漂移、上下起伏；入场时从水下升起，硬直时跌到水面，倒下后沉入水中 ——

# 返回 {"pos":道路坐标, "alt":离地高度（单位，水面为 0）}。纯函数，画面同样调用。
static func body_pose(run, event: Dictionary, time: float) -> Dictionary:
	var perch: Vector2=event.perch
	var drift:=sin(time*DRIFT_RATE)*DRIFT
	var bob:=sin(time*1.7)*8.0
	var pos:=perch+Vector2(drift,0)
	if event.get("phase","")=="dormant": return {"pos":perch,"alt":-DEPTH}
	if event.get("phase","")=="intro":
		var t: float=time-event.state_at
		var k:=smoothstep(INTRO_RISE,INTRO_RISEN,t)
		# 入场时停在潭心正中，升起后才开始漂移。
		return {"pos":perch,"alt":lerpf(-DEPTH,HOVER,k)+bob*k}
	if event.hp<=0:
		var dead: float=time-float(event.get("defeated_at",time))
		return {"pos":event.get("death_pos",pos),"alt":HOVER-smoothstep(1.0,4.0,dead)*(HOVER+DEPTH)}
	if event.state=="stagger":
		var t: float=time-event.state_at
		var fall:=smoothstep(0.0,0.5,t)*(1.0-smoothstep(STAGGER-0.8,STAGGER,t))
		return {"pos":event.get("stagger_pos",pos),"alt":lerpf(HOVER,12.0,fall)+bob*(1.0-fall)}
	return {"pos":pos,"alt":HOVER+bob}

static func update_body(run, event: Dictionary) -> void:
	var pose:=body_pose(run,event,run.elapsed)
	event.origin=pose.pos
	event.aim_height=CHEST_HEIGHT+maxf(float(pose.alt),-CHEST_HEIGHT+20.0)

static func source(run, event: Dictionary) -> Vector2:
	# 水柱与浪从海神脚下的水面出发（落点前方一点）。
	return (event.origin as Vector2)-Vector2(0,60)

# —— 三叉激流 ——

static func lance_count(event: Dictionary) -> int:
	return event.stage+1

static func aim_lances(run, event: Dictionary) -> void:
	var from:=source(run,event)
	var aims:Array=[players(run)[event.skill_seq%2]]
	if event.stage>=1: aims=[players(run)[0],players(run)[1]]
	if event.stage>=2: aims.append((players(run)[0]+players(run)[1])*0.5)
	var dirs:Array=[]
	for aim:Vector2 in aims:
		var d:=aim-from
		dirs.append(d.normalized() if d.length()>1.0 else Vector2(0,-1))
	event.lance_from=from
	event.lances=dirs

static func lance_live(event: Dictionary, time: float) -> bool:
	var t: float=time-event.state_at
	var start: float=LANCE_WINDUP*PACE[event.stage]+LANCE_DELAY
	return event.state=="lance" and t>=start and t<start+LANCE_FIRE

static func lance_distance(event: Dictionary, point: Vector2, index: int) -> float:
	var from: Vector2=event.lance_from
	var dir: Vector2=event.lances[index]
	var along:=clampf((point-from).dot(dir),0.0,LANCE_LENGTH)
	return point.distance_to(from+dir*along)

static func lance(run, event: Dictionary) -> void:
	var t:=age(run,event)
	if t<LANCE_WINDUP*pace(event): aim_lances(run,event)
	if lance_live(event,run.elapsed):
		for index in range(event.lances.size()):
			for role in range(2):
				if lance_distance(event,players(run)[role],index)<LANCE_HALF+run.Motion.RADIUS and run.foot_height(role)<40.0:
					hit(run,event,role,"lance%d"%index,LANCE_DAMAGE)
	if t>=LANCE_WINDUP*pace(event)+LANCE_DELAY+LANCE_FIRE+0.2: enter(run,event,"recover")

# —— 巨浪 ——

static func wave_count(event: Dictionary) -> int:
	return 2 if event.stage>=1 else 1

# 第一道缺口开在两人中点的另一侧（逼两人横穿）；第二道从第一道再横移 150–210，换到另一侧——
# 两道浪相隔 1.6 秒，两人跑 1 秒多就能赶到。位置限制在路面内。
static func plan_gaps(run, event: Dictionary) -> void:
	var middle:float=(run.a.position.x+run.b.position.x)*0.5
	var side:=-1.0 if middle>=0.0 else 1.0
	var rng:=RandomNumberGenerator.new()
	rng.seed=int(event.id)*7331+int(event.skill_seq)*101+3
	var limit:float=run.EDGE-WAVE_GAP-20.0
	var first:=clampf(side*rng.randf_range(90.0,200.0),-limit,limit)
	var gaps:Array=[first]
	if wave_count(event)==2:
		var second:=first-side*rng.randf_range(150.0,210.0)
		if absf(second)>limit: second=first+side*rng.randf_range(150.0,210.0)
		gaps.append(clampf(second,-limit,limit))
	event.gaps=gaps

# 第 n 道浪的纵向位置；未出发返回 INF，已经推过场地返回 -INF。
static func wave_y(event: Dictionary, time: float, n: int) -> float:
	var start: float=event.state_at+WAVE_WINDUP*PACE[event.stage]+n*WAVE_SECOND
	if time<start: return INF
	var y: float=float(event.perch.y)-WAVE_START-(time-start)*WAVE_SPEED
	return y if y>float(event.arena)+FLOOR-80.0 else -INF

static func in_gap(event: Dictionary, n: int, x: float, margin: float) -> bool:
	return absf(x-float(event.gaps[n]))<=WAVE_GAP-margin

static func wave(run, event: Dictionary) -> void:
	for n in range(wave_count(event)):
		var y:=wave_y(event,run.elapsed,n)
		if y==INF or y==-INF: continue
		var before: float=y+WAVE_SPEED*run.FIXED_STEP
		for role in range(2):
			var point:Vector2=players(run)[role]
			if point.y>=y-WAVE_HALF-run.Motion.RADIUS and point.y<=before+WAVE_HALF+run.Motion.RADIUS and not in_gap(event,n,point.x,run.Motion.RADIUS):
				hit(run,event,role,"wave%d"%n,WAVE_DAMAGE)
	if wave_y(event,run.elapsed,wave_count(event)-1)==-INF: enter(run,event,"recover")

# —— 涌泉 ——

static func geyser_count(event: Dictionary) -> int:
	return [4,5,7][event.stage]

static func aim_geysers(run, event: Dictionary) -> void:
	var targets:Array=[]
	for n in range(geyser_count(event)):
		var point:Vector2=players(run)[n%2]+GEYSER_OFFSETS[n]
		point.x=clampf(point.x,-run.EDGE+30,run.EDGE-30)
		point.y=clampf(point.y,event.arena+FLOOR+40,event.arena+HOLD)
		targets.append(point)
	event.targets=targets

static func geyser_age(event: Dictionary) -> float:
	return GEYSER_WINDUP*PACE[event.stage]+GEYSER_DELAY

static func geysers(run, event: Dictionary) -> void:
	if age(run,event)<GEYSER_WINDUP*pace(event): aim_geysers(run,event)
	var erupt:=geyser_age(event)
	if age(run,event)>=erupt and age(run,event)-run.FIXED_STEP<erupt:
		for target:Vector2 in event.targets:
			for role in range(2):
				if players(run)[role].distance_to(target)<GEYSER_RADIUS+run.Motion.RADIUS:
					hit(run,event,role,"geysers",GEYSER_DAMAGE)
			event.puddles.append({"position":target,"until":run.elapsed+PUDDLE_TIME*(1.3 if event.stage==2 else 1.0)})
	if age(run,event)>=erupt+0.5: enter(run,event,"recover")

# 旋涡水洼：踩在上面每秒受一次冲刷（跳起时不算）；到时消散。
static func puddles(run, event: Dictionary) -> void:
	var live:Array=[]
	for puddle in event.puddles:
		if run.elapsed<float(puddle.until): live.append(puddle)
	if live.size()!=event.puddles.size(): event.puddles=live
	for puddle in live:
		for role in range(2):
			if players(run)[role].distance_to(puddle.position)<PUDDLE_RADIUS+run.Motion.RADIUS*0.5 and run.foot_height(role)<10.0:
				run.Combat.hit(run,role,"boss:puddle",PUDDLE_DAMAGE,true)

# —— 召唤 ——

static func summon_count(event: Dictionary) -> int:
	return SUMMON_JELLY[event.stage]+SUMMON_CRAB[event.stage]

static func summon(run, event: Dictionary) -> void:
	if age(run,event)<SUMMON_WINDUP*pace(event): return
	if int(event.get("summon_seq",-1))!=int(event.skill_seq):
		event.summon_seq=event.skill_seq
		# 从深潭边缘浮起（潭前沿），先过来再攻击，给玩家转火的时间。
		var n:=0
		for kind in ["tide_jelly","river_crab_knight"]:
			var count:int=SUMMON_JELLY[event.stage] if kind=="tide_jelly" else SUMMON_CRAB[event.stage]
			for k in range(count):
				var point:=Vector2(SUMMON_X[n%SUMMON_X.size()],event.arena+POOL_NEAR-40.0-(n%2)*30.0)
				var monster:Dictionary=run.Monsters.add(run,point,"river",kind)
				monster.alert=true
				monster.boss_add=true
				event.adds.append(monster.id)
				n+=1
	if age(run,event)>=SUMMON_WINDUP*pace(event)+SUMMON_RECOVER: enter(run,event,"recover")

static func living_adds(run, event: Dictionary) -> int:
	var count:=0
	for other in run.journey_events:
		if other.kind=="monster" and other.id in event.get("adds",[]) and other.hp>0: count+=1
	return count

# —— 怒涛震环 ——

static func ring_count(event: Dictionary) -> int:
	return 2 if event.stage>=2 else 1

static func ring_center(event: Dictionary) -> Vector2:
	return event.get("ring_at",event.perch)

static func ring_radius(event: Dictionary, time: float, n: int) -> float:
	var start: float=event.state_at+RING_WINDUP*PACE[event.stage]+n*RING_SECOND
	if time<start: return -1.0
	return (time-start)*RING_SPEED

static func ring_reach(run, event: Dictionary) -> float:
	return ring_center(event).distance_to(Vector2(run.EDGE,event.arena+FLOOR))+60.0

static func ring(run, event: Dictionary) -> void:
	# 震环中心在出手瞬间海神所在的水面位置。
	if age(run,event)<RING_WINDUP*pace(event): event.ring_at=source(run,event)
	for n in range(ring_count(event)):
		var radius:=ring_radius(event,run.elapsed,n)
		if radius<0.0: continue
		var before:=maxf(0.0,radius-RING_SPEED*run.FIXED_STEP)
		for role in range(2):
			var d: float=players(run)[role].distance_to(ring_center(event))
			if d>=before-RING_HALF-run.Motion.RADIUS and d<=radius+RING_HALF+run.Motion.RADIUS and run.foot_height(role)<RING_TOP:
				hit(run,event,role,"ring%d"%n,RING_DAMAGE)
	var done: float=RING_WINDUP*pace(event)+(ring_count(event)-1)*RING_SECOND+ring_reach(run,event)/RING_SPEED
	if age(run,event)>=done: enter(run,event,"recover")

# —— 潮汐之心 ——

static func start_channel(run, event: Dictionary) -> void:
	event.hold=0.0
	event.bolt_seq=0
	event.skill="channel"
	enter(run,event,"channel")

# 水球位置：前摇后从海神头顶落到场地中段，然后左右缓慢摆动。
static func orb_center(event: Dictionary, time: float) -> Vector2:
	var t: float=time-event.state_at
	var settle: float=CHANNEL_WINDUP*PACE[event.stage]+ORB_DROP
	return Vector2(sin(maxf(0.0,t-settle)*ORB_RATE)*ORB_SWAY,float(event.arena)+ORB_Y)

static func orb_ready(event: Dictionary, time: float) -> bool:
	return event.state=="channel" and time-event.state_at>=CHANNEL_WINDUP*PACE[event.stage]+ORB_DROP

static func hold_ratio(event: Dictionary) -> float:
	return clampf(float(event.get("hold",0.0))/HOLD_TIME,0.0,1.0)

# 能量绳（折线）离水球中心的最近距离。
static func rope_gap(run, center: Vector2) -> float:
	var path:PackedVector2Array=run.rope.physical_path()
	var best:=INF
	for n in range(path.size()-1):
		var a:Vector2=path[n]
		var b:Vector2=path[n+1]
		var ab:=b-a
		var k:=clampf((center-a).dot(ab)/maxf(ab.length_squared(),0.0001),0.0,1.0)
		best=minf(best,center.distance_to(a+ab*k))
	return best

# 绳子横穿水球：两人都落地、分在水球两侧（横向），且绳子穿过球体。
static func rope_through(run, event: Dictionary) -> bool:
	if not orb_ready(event,run.elapsed): return false
	if run.foot_height(0)>4.0 or run.foot_height(1)>4.0: return false
	var center:=orb_center(event,run.elapsed)
	if signf(run.a.position.x-center.x)==signf(run.b.position.x-center.x): return false
	return rope_gap(run,center)<ORB_RADIUS

# 第 n 发水弹的出手时刻（相对蓄力开始）。
static func bolt_time(event: Dictionary, n: int) -> float:
	return CHANNEL_WINDUP*PACE[event.stage]+ORB_DROP+0.8+n*BOLT_EVERY*PACE[event.stage]

static func channel(run, event: Dictionary) -> void:
	var t:=age(run,event)
	if not orb_ready(event,run.elapsed): return
	if rope_through(run,event): event.hold=float(event.hold)+run.FIXED_STEP
	else: event.hold=maxf(0.0,float(event.hold)-HOLD_DECAY*run.FIXED_STEP)
	# 水弹：瞄准一人当前位置，飞行 BOLT_FLIGHT 秒后落地；落点圆圈内被打中。
	var n:int=event.bolt_seq
	if t>=bolt_time(event,n):
		event.bolt_seq=n+1
		event.bolt_target=players(run)[n%2]
		event.bolt_at=run.elapsed
	if event.has("bolt_at") and run.elapsed-float(event.bolt_at)>=BOLT_FLIGHT and run.elapsed-float(event.bolt_at)-run.FIXED_STEP<BOLT_FLIGHT:
		for role in range(2):
			if players(run)[role].distance_to(event.bolt_target)<BOLT_RADIUS+run.Motion.RADIUS and run.foot_height(role)<30.0:
				run.Combat.hit(run,role,"boss:bolt:%d:%d"%[event.skill_seq,int(event.bolt_seq)],BOLT_DAMAGE)
	if hold_ratio(event)>=1.0:
		event.stagger_count+=1
		event.stagger_pos=event.origin
		event.burst_at=orb_center(event,run.elapsed)
		run.combat.notice="能量顺着绳子灌进潮汐之心！%s被震落水面，海神之心暴露"%NAME
		enter(run,event,"stagger")
		return
	if t>=CHANNEL_WINDUP*pace(event)+ORB_DROP+CHANNEL_LIMIT:
		event.skill="tsunami"
		enter(run,event,"tsunami")

static func tsunami_warning(run, event: Dictionary) -> bool:
	return event.state=="channel" and age(run,event)>=CHANNEL_WINDUP*pace(event)+ORB_DROP+CHANNEL_LIMIT-1.6

static func tsunami_radius(event: Dictionary, time: float) -> float:
	if event.state!="tsunami": return -1.0
	return (time-event.state_at)*TSUNAMI_SPEED

static func tsunami(run, event: Dictionary) -> void:
	var radius:=tsunami_radius(event,run.elapsed)
	var before:=maxf(0.0,radius-TSUNAMI_SPEED*run.FIXED_STEP)
	var center:=source(run,event)
	for role in range(2):
		var d: float=players(run)[role].distance_to(center)
		if d>=before-TSUNAMI_HALF-run.Motion.RADIUS and d<=radius+TSUNAMI_HALF+run.Motion.RADIUS and run.foot_height(role)<TSUNAMI_TOP:
			hit(run,event,role,"tsunami",TSUNAMI_DAMAGE)
	if radius>center.distance_to(Vector2(run.EDGE,event.arena+FLOOR))+60.0: enter(run,event,"recover")

# —— 三阶段：两侧海水 ——

static func flood(run, event: Dictionary) -> void:
	for role in range(2):
		var point:Vector2=players(run)[role]
		if absf(point.x)>run.EDGE-FLOOD_WIDTH and point.y>=event.arena and run.foot_height(role)<20.0:
			run.Combat.hit(run,role,"boss:flood",FLOOD_DAMAGE,true)

# —— 补给（与前两章相同的节奏）——

static func resupply(run, event: Dictionary) -> void:
	for x in [-200.0,200.0]:
		var point:=Vector2(x,event.arena+SUPPLY)
		if run.combat.pickups.any(func(p):return p.kind=="ammo" and p.position.distance_to(point)<10): continue
		run.Combat.add_pickup(run,"ammo",point)

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
	run.Combat.add_pickup(run,kind,point)

# —— 提示 ——

static func hint(run, event: Dictionary) -> String:
	if event.hp<=0: return "%s沉入深潭，继续前进"%NAME if run.elapsed-event.get("defeated_at",run.elapsed)<6.0 else ""
	match event.state:
		"intro": return ""
		"roar": return "%s怒吼：阶段 %d"%[NAME,event.stage+1]
		"lance":
			if lance_count(event)==1: return "三叉激流：水柱沿亮起的直线射来，横向让开"
			return "三叉激流：%d 道水柱分别瞄准两人，各自横向让开"%lance_count(event)
		"wave":
			if wave_count(event)==2: return "巨浪：亮起区域是危险区，避开预警进入空白缺口；第二道浪会换边"
			return "巨浪：亮起区域是危险区，两人一起进入未标记的缺口"
		"geysers": return "涌泉：离开地上的圆圈，避开旋涡水洼"
		"summon": return "海神召唤潮汐水母：它们会吐水弹，先把它们打下来"
		"ring": return "怒涛震环：水环到脚下时跳起" if ring_count(event)==1 else "怒涛震环：连续两道水环，跳两次"
		"channel":
			if tsunami_warning(run,event): return "海啸将至：跳起躲避水环！潮汐之心 %d%%"%int(hold_ratio(event)*100)
			if not orb_ready(event,run.elapsed): return "海神凝聚潮汐之心：水球要落到场地中段"
			return "潮汐之心：两人分站水球两侧，让能量绳横穿水球；水弹来了侧身让开 · %d%%"%int(hold_ratio(event)*100)
		"tsunami": return "海啸：水环到脚下时跳起"
		"stagger": return "海神被震落水面！海神之心暴露，全力输出"
	return ""
