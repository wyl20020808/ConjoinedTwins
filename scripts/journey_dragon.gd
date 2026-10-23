extends RefCounted
# 第二章终点 Boss「烬翼魔龙」。与第一章相同，Boss 是 journey_events 中 kind=="boss" 的事件（species=="dragon"），
# 全部状态为可深拷贝的数据，按固定步与模拟时间推进：随存档恢复、联机两端一致。
# 入口与通用规则（站位上限、护甲、锁定）由 journey_boss.gd 分派；设计依据见 docs/BOSS_CH2_DESIGN.md。
# 坐标为道路单位（20 = 1 米），+y 为前进方向；龙落地时面朝两人（-y）。

const SPECIES := "dragon"
const CHAPTER := 1
const NAME := "烬翼魔龙"
const EPITHET := "盘踞河谷尽头的焚天之翼"
# 场地尺寸与第一章一致（journey_boss.gd 的 ARENA/TRIGGER/HOLD/FLOOR 按这些值计算站位与镜头）。
const ARENA := 1800.0
const TRIGGER := 300.0
const HOLD := 1380.0
const FLOOR := 120.0
# 龙的落点（脚下）与胸口：胸口熔岩核是瞄准点，在落点前方 120、离地约 10.2 米（模型放大 26 倍，v2 模型更直立）。
const PERCH := 1660.0
const CHEST_AHEAD := 120.0
const CHEST_HEIGHT := 205.0
const MAX_HP := 2400
const STAGES := [0.65, 0.30]
const PACE := [1.0, 0.88, 0.75]
const MOVES := [2, 3, 3]
# 每个阶段都会起飞：一阶段起就有悬空炎息（飞到场地上空追着人喷火），二阶段起加入横掠俯冲；
# 每轮都可能召唤火蝠。三阶段场地两侧燃起火墙。
const PATTERN := [["hover","breath","bats","tail","hover","meteors"],
	["strafe","hover","bats","breath","meteors","hover","tail","strafe","bats"],
	["hover","strafe","bats","breath","meteors","hover","tail","strafe","bats"]]

# —— 入场（电影式，约 14.4 秒）——
# 0–1.2 镜头抬向天空、远处龙吼 → 1.2–6.6 魔龙绕场地盘旋一整圈（从两人头顶掠过）→ 6.6–8.4 俯冲降落、8.4 秒着地震起尘浪
# → 9.1–11.5 落地咆哮、标题浮现 → 11.5–14.1 仰天喷出火焰 → 14.1–15.3 镜头交还。
const INTRO := 15.3
const INTRO_CIRCLE := 1.2
const INTRO_DIVE := 6.6
const INTRO_LAND := 8.4
const INTRO_ROAR := 9.1
const INTRO_FIRE := 11.5
const INTRO_FIRED := 14.1
const INTRO_SKIP_AFTER := 0.8
const RETURN_TIME := 1.2
# 盘旋：以场地中段为圆心、半径 40 米、高 22 米绕一圈，从远端出发，经右侧、两人头顶、左侧回到远端。
const CIRCLE_CENTER := 1100.0
const CIRCLE_RADIUS := 800.0
const CIRCLE_ALT := 440.0
# 降落动作 Land 长 1.6 秒，着地在 0.9 秒处。
const LAND_CLIP := 1.6
const LAND_TOUCH := 0.9

const ROAR := 2.4
const GAP := 0.9
const RECOVER := 0.8
const STAGGER := 7.0

# —— 烈焰吐息：龙头从正前方扫向一侧，烧过半个场地；二阶段起紧接着反向再扫另一半 ——
# 判定为从嘴部出发的一道火柱（角宽 ±BREATH_HALF），只有另一半场地安全；火不能跳过。
const BREATH_WINDUP := 1.5
const BREATH_SWEEP := 1.4
const BREATH_GAP := 0.8
const BREATH_FROM := 0.0
const BREATH_TO := 80.0
const BREATH_HALF := 7.0
const BREATH_DAMAGE := 30
const MOUTH_AHEAD := 240.0

# —— 甩尾震地：尾巴拍地掀起向外扩散的冲击环，跳起才能躲开；二阶段起连续两道 ——
const TAIL_WINDUP := 1.0
const TAIL_SPEED := 760.0
const TAIL_HALF := 26.0
const TAIL_TOP := 14.0
const TAIL_SECOND := 0.7
const TAIL_DAMAGE := 30

# —— 火雨：仰天喷火，火球从天而降砸在两人周围，落点留下熔岩池 ——
const METEOR_WINDUP := 1.2
const METEOR_FALL := 1.1
const METEOR_RADIUS := 72.0
const METEOR_DAMAGE := 22
const METEOR_OFFSETS := [Vector2.ZERO, Vector2.ZERO, Vector2(80,40), Vector2(-80,-40), Vector2(40,-90), Vector2(-50,90), Vector2(120,-20), Vector2(-120,20)]
const POOL_RADIUS := 56.0
const POOL_TIME := 4.0
const POOL_DAMAGE := 8

# —— 起飞俯冲（二阶段起）：起飞绕到场地一侧，锁定两人所在的一条横带，低空横掠喷火，再飞回落点降落 ——
# 时间轴：0–1.2 起飞 → 1.2–2.6 飞到侧面并锁定横带 → 2.6–4.2 横掠 → 4.2–6.0 绕回 → 6.0–7.6 降落。
const STRAFE_TAKEOFF := 1.2
const STRAFE_LOCK := 2.6
const STRAFE_PASS := 1.6
const STRAFE_RETURN := 6.0
const STRAFE_END := 7.6
const STRAFE_HALF := 70.0
const STRAFE_REACH := 90.0
const STRAFE_ALT := 180.0
const STRAFE_DAMAGE := 30

# —— 悬空炎息：起飞到场地上空悬停，朝地面喷出一道火柱，火柱落点追着一人移动并沿途留下熔岩；之后飞回落点降落 ——
# 时间轴：0–1.2 起飞 → 1.2–2.2 飞到悬停点 → 2.2–2.8 落点圆圈亮起（不伤人）→ 2.8 起喷火 BEAM_TIME 秒 → 飞回 1.0 秒 → 降落 1.6 秒。
# 火柱落点追人速度低于两人跑速（180），一直移动就能甩开；二阶段起喷到一半改追另一人。
const HOVER_TAKEOFF := 1.2
const HOVER_ARRIVE := 2.2
const HOVER_AIM := 2.8
const HOVER_BACK := 1.0
const HOVER_POINT := 1530.0
const HOVER_ALT := 230.0
const BEAM_TIME := [3.0, 3.6, 4.2]
const BEAM_SPEED := [115.0, 130.0, 145.0]
const BEAM_RADIUS := 46.0
const BEAM_DAMAGE := 18
const BEAM_LEAD := 200.0
const BEAM_POOL_EVERY := 0.22
const BEAM_POOL_TIME := [1.8, 2.0, 2.6]
const BEAM_POOL_RADIUS := 40.0

# —— 召唤火蝠：仰头长啸，火蝠从龙巢两侧飞出扑向两人；场上火蝠太多时跳过 ——
const BATS_WINDUP := 1.1
const BATS_RECOVER := 0.6
const BATS_COUNT := [2, 3, 4]
const BATS_X := [-200.0, 200.0, -90.0, 90.0, 0.0]
const BATS_CAP := 5

# —— 蓄焰 / 锁龙链（破甲机会）——
# 龙伏地蓄焰，场地中段两块绞盘踏板亮起（间距小于绳长，两人可同时站上）；两人同时站稳累计 HOLD_TIME 秒，
# 两侧绞盘射出锁链把龙拽倒（硬直 7 秒、胸口熔岩核暴露，满伤害）。蓄焰期间龙每隔一段时间朝一块踏板吐火球，
# 站在上面会被烧，需要先让开再回来；不在踏板上时进度缓慢回落。CHARGE_LIMIT 秒内未完成则炎爆：全场冲击环，跳起躲避。
const PLATES := [Vector2(-60,1080), Vector2(60,1080)]
const PLATE_HALF := 34.0
const HOLD_TIME := 2.6
const HOLD_DECAY := 0.4
const CHARGE_WINDUP := 1.0
const CHARGE_LIMIT := 13.0
const SPIT_EVERY := 3.2
const SPIT_FLIGHT := 1.1
const SPIT_DAMAGE := 18
const NOVA_SPEED := 820.0
const NOVA_HALF := 30.0
const NOVA_TOP := 14.0
const NOVA_DAMAGE := 32
# 绞盘立在场地两侧、龙身旁，锁链从这里射向龙颈。
const WINCH_X := 360.0
const WINCH_Y := 1500.0

# 三阶段两侧火墙。
const WALL_WIDTH := 60.0
const WALL_DAMAGE := 10

const SUPPLY := 1200.0
const AMMO_EVERY := 7.0
const AMMO_CAP := 3

static func enabled(run) -> bool:
	return not run.combat_trial and run.level_index == CHAPTER

static func add(run) -> void:
	var arena: float=run.finish_distance()-ARENA
	var perch:=Vector2(0,arena+PERCH)
	var chest:=perch-Vector2(0,CHEST_AHEAD)
	var body:=Rect2(-200,chest.y-40,400,260)
	run.boss_index=run.journey_events.size()
	run.journey_events.append({"id":run.event_serial,"kind":"boss","species":SPECIES,"arena":arena,"y":perch.y,"origin":chest,"spawn":chest,
		"perch":perch,"aim_height":CHEST_HEIGHT,"airborne":false,
		"rect":body,"sample":body,"previous":body,"bottom":0.0,"top":0.0,"side":0.0,"locked_x":0.0,"combined":false,"obstacle":-1,
		"trigger":-1.0,"phase":"dormant","hp":MAX_HP,"max_hp":MAX_HP,"stage":0,
		"state":"idle","state_at":0.0,"skill":"","skill_seq":0,"cycle_moves":0,"pattern_index":0,
		"breath_side":1.0,"targets":[],"pools":[],"lane_y":0.0,"lane_side":1.0,
		"hold":0.0,"pinned":false,"spit_seq":0,"spit_target":Vector2.ZERO,"stagger_count":0,"stage_at":0.0,"ammo_at":0.0,"ammo_drops":0,
		"beam":Vector2.ZERO,"beam_target":0,"beam_drops":0,"hover_count":0,"adds":[]})
	run.event_serial+=1
	# 入口两侧各一把枪（间距小于绳长，两人可同时拾取），另有弹药与医疗包；硬直结束与换阶段时再刷新。
	run.Combat.add_pickup(run,"gun",Vector2(-60,arena+160),{},"smg")
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
	if event.hp<=0: return
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
				event.pinned=false
				resupply(run,event)
				enter(run,event,"recover")
		"breath": breath(run,event)
		"tail": tail(run,event)
		"meteors": meteors(run,event)
		"strafe": strafe(run,event)
		"hover": hover(run,event)
		"bats": bats(run,event)
		"charge": charge(run,event)
		"nova": nova(run,event)
	update_body(run,event)
	pools(run,event)
	if event.stage==2: walls(run,event)
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
		# 与第一章相同：换阶段时存档，失败从本阶段继续。
		run.capture_checkpoint()
		return
	event.skill_seq+=1
	if event.cycle_moves>=MOVES[event.stage]:
		event.cycle_moves=0
		start_charge(run,event)
		return
	var pattern:Array=PATTERN[event.stage]
	var skill:String=pattern[event.pattern_index%pattern.size()]
	event.pattern_index+=1
	# 场上火蝠太多时跳过召唤。
	if skill=="bats" and living_adds(run,event)>BATS_CAP-BATS_COUNT[event.stage]:
		skill=pattern[event.pattern_index%pattern.size()]
		event.pattern_index+=1
	event.cycle_moves+=1
	event.skill=skill
	match skill:
		"breath":
			# 先烧离两人中点更近的那一半，逼两人换边。
			var middle:float=(run.a.position.x+run.b.position.x)*0.5
			event.breath_side=1.0 if middle>=0.0 else -1.0
			enter(run,event,"breath")
		"tail": enter(run,event,"tail")
		"meteors":
			aim_meteors(run,event)
			enter(run,event,"meteors")
		"strafe":
			event.lane_side=-event.lane_side
			event.lane_y=lane_target(run,event)
			enter(run,event,"strafe")
		"hover": start_hover(run,event)
		"bats": enter(run,event,"bats")

# —— 龙身位置：落地时在落点；起飞俯冲时按时间轴飞行。瞄准点（origin）跟随胸口 ——

# 返回 {"pos":道路坐标, "alt":离地高度（单位）, "heading":机头朝向（道路坐标单位向量）}。纯函数，画面同样调用。
static func body_pose(run, event: Dictionary, time: float) -> Dictionary:
	var perch: Vector2=event.perch
	var grounded:={"pos":perch,"alt":0.0,"heading":Vector2(0,-1)}
	if event.get("phase","")=="intro": return intro_pose(event,time-event.state_at)
	if event.state=="hover" and event.hp>0: return hover_pose(run,event,time)
	if event.state!="strafe" or event.hp<=0: return grounded
	var t: float=time-event.state_at
	var side: float=event.lane_side
	var edge: float=run.EDGE+520.0
	var lane: float=event.lane_y
	var start_pass:=Vector2(side*edge,lane)
	var end_pass:=Vector2(-side*edge,lane)
	if t<STRAFE_TAKEOFF:
		var k:=smoothstep(0.0,1.0,t/STRAFE_TAKEOFF)
		return {"pos":perch+Vector2(0,40*k),"alt":lerpf(0.0,160.0,k*k),"heading":Vector2(0,-1)}
	if t<STRAFE_LOCK:
		var k:=(t-STRAFE_TAKEOFF)/(STRAFE_LOCK-STRAFE_TAKEOFF)
		return hermite(perch+Vector2(0,40),Vector2(side*900,900),start_pass,Vector2(-side*1400,0),k,160.0,STRAFE_ALT+60,STRAFE_LOCK-STRAFE_TAKEOFF)
	if t<STRAFE_LOCK+STRAFE_PASS:
		var k:=(t-STRAFE_LOCK)/STRAFE_PASS
		var pos:=start_pass.lerp(end_pass,k)
		return {"pos":pos,"alt":STRAFE_ALT+60*(1.0-sin(k*PI)),"heading":Vector2(-side,0)}
	if t<STRAFE_RETURN:
		var k:=(t-STRAFE_LOCK-STRAFE_PASS)/(STRAFE_RETURN-STRAFE_LOCK-STRAFE_PASS)
		return hermite(end_pass,Vector2(-side*1400,0),perch+Vector2(0,260),Vector2(0,-500),k,STRAFE_ALT+60,200.0,STRAFE_RETURN-STRAFE_LOCK-STRAFE_PASS)
	var k:=clampf((t-STRAFE_RETURN)/LAND_TOUCH,0.0,1.0)
	return {"pos":(perch+Vector2(0,260)).lerp(perch,smoothstep(0.0,1.0,k)),"alt":200.0*(1.0-smoothstep(0.0,1.0,k)),"heading":Vector2(0,-1)}

# 三次 Hermite：p0/m0 → p1/m1，k∈[0,1]；duration 用于把切线换算成每秒速度。
static func hermite(p0: Vector2, m0: Vector2, p1: Vector2, m1: Vector2, k: float, alt0: float, alt1: float, duration: float) -> Dictionary:
	var k2:=k*k
	var k3:=k2*k
	var pos:=p0*(2*k3-3*k2+1)+m0*(k3-2*k2+k)*duration+p1*(-2*k3+3*k2)+m1*(k3-k2)*duration
	var vel:=p0*(6*k2-6*k)+m0*(3*k2-4*k+1)*duration+p1*(-6*k2+6*k)+m1*(3*k2-2*k)*duration
	return {"pos":pos,"alt":lerpf(alt0,alt1,smoothstep(0.0,1.0,k)),"heading":vel.normalized() if vel.length()>0.001 else Vector2(0,-1)}

# 悬停时身体半直立（pitch 小于平飞），朝两人方向，略微上下起伏并把头转向火柱落点。
static func hover_pose(run, event: Dictionary, time: float) -> Dictionary:
	var perch: Vector2=event.perch
	var t: float=time-event.state_at
	var spot:=Vector2(0,event.arena+HOVER_POINT)
	var beam_end:=hover_beam_end(event)
	if t<HOVER_TAKEOFF:
		var k:=smoothstep(0.0,1.0,t/HOVER_TAKEOFF)
		return {"pos":perch+Vector2(0,40*k),"alt":lerpf(0.0,160.0,k*k),"heading":Vector2(0,-1)}
	if t<HOVER_ARRIVE:
		var k:=(t-HOVER_TAKEOFF)/(HOVER_ARRIVE-HOVER_TAKEOFF)
		var pose:=hermite(perch+Vector2(0,40),Vector2(0,-200),spot,Vector2(0,-60),k,160.0,HOVER_ALT,HOVER_ARRIVE-HOVER_TAKEOFF)
		pose.heading=Vector2(0,-1)
		pose.pitch=lerpf(0.85,0.35,smoothstep(0.0,1.0,k))
		return pose
	if t<beam_end:
		var bob:=sin((t-HOVER_ARRIVE)*2.6)*14.0
		var look:Vector2=(event.beam as Vector2)-spot
		var heading:=Vector2(0,-1) if look.length()<1.0 else Vector2(0,-1).lerp(look.normalized(),0.35).normalized()
		return {"pos":spot,"alt":HOVER_ALT+bob,"heading":heading,"pitch":0.35}
	if t<beam_end+HOVER_BACK:
		var k:=(t-beam_end)/HOVER_BACK
		var pose:=hermite(spot,Vector2(0,100),perch+Vector2(0,260),Vector2(0,200),k,HOVER_ALT,200.0,HOVER_BACK)
		pose.heading=Vector2(0,-1)
		pose.pitch=0.35
		return pose
	var k:=clampf((t-beam_end-HOVER_BACK)/LAND_TOUCH,0.0,1.0)
	return {"pos":(perch+Vector2(0,260)).lerp(perch,smoothstep(0.0,1.0,k)),"alt":200.0*(1.0-smoothstep(0.0,1.0,k)),"heading":Vector2(0,-1)}

static func intro_pose(event: Dictionary, t: float) -> Dictionary:
	var perch: Vector2=event.perch
	var center:=Vector2(0,event.arena+CIRCLE_CENTER)
	if t<INTRO_DIVE:
		# 盘旋前段从远处高空飞入圆周（入场开头在画面外），然后整圈盘旋。
		var k:=clampf((t-INTRO_CIRCLE)/(INTRO_DIVE-INTRO_CIRCLE),0.0,1.0) if t>=INTRO_CIRCLE else 0.0
		var a:=k*TAU
		var pos:=center+Vector2(sin(a),cos(a))*CIRCLE_RADIUS
		var alt:=CIRCLE_ALT+sin(a*2.0)*40.0
		if t<INTRO_CIRCLE:
			var come:=1.0-t/INTRO_CIRCLE
			pos+=Vector2(-600,900)*come
			alt+=300.0*come
		return {"pos":pos,"alt":alt,"heading":Vector2(cos(a),-sin(a))}
	if t<INTRO_LAND:
		var k:=(t-INTRO_DIVE)/(INTRO_LAND-INTRO_DIVE)
		var far:=center+Vector2(0,CIRCLE_RADIUS)
		var pose:=hermite(far,Vector2(1000,0),perch,Vector2(0,-200),k,CIRCLE_ALT,0.0,INTRO_LAND-INTRO_DIVE)
		# 最后 0.6 秒转身面朝两人。
		var turn:=smoothstep(0.55,1.0,k)
		pose.heading=(pose.heading as Vector2).lerp(Vector2(0,-1),turn).normalized()
		pose.alt=CIRCLE_ALT*(1.0-smoothstep(0.0,1.0,k))*(1.0-k*0.3)
		return pose
	return {"pos":perch,"alt":0.0,"heading":Vector2(0,-1)}

static func update_body(run, event: Dictionary) -> void:
	var pose:=body_pose(run,event,run.elapsed)
	var heading: Vector2=pose.heading
	event.origin=(pose.pos as Vector2)+heading*CHEST_AHEAD
	event.aim_height=CHEST_HEIGHT+float(pose.alt)
	event.airborne=float(pose.alt)>20.0

# —— 烈焰吐息 ——

static func mouth(event: Dictionary) -> Vector2:
	return (event.perch as Vector2)-Vector2(0,MOUTH_AHEAD)

static func breath_sweeps(event: Dictionary) -> int:
	return 2 if event.stage>=1 else 1

# 第 n 道扫射的火柱角度（度，0 = 正对两人，正值偏 +x）；未开始或已结束返回 INF。
static func breath_angle(event: Dictionary, time: float, sweep: int) -> float:
	var start: float=event.state_at+BREATH_WINDUP*PACE[event.stage]+sweep*(BREATH_SWEEP+BREATH_GAP)
	var k:=(time-start)/BREATH_SWEEP
	if k<0.0 or k>1.0: return INF
	var side: float=event.breath_side*(1.0 if sweep==0 else -1.0)
	return side*lerpf(BREATH_FROM,BREATH_TO,k)

static func player_angle(event: Dictionary, point: Vector2) -> float:
	var d:=point-mouth(event)
	return rad_to_deg(atan2(d.x,-d.y))

static func breath(run, event: Dictionary) -> void:
	for sweep in range(breath_sweeps(event)):
		var now:=breath_angle(event,run.elapsed,sweep)
		if now==INF: continue
		var before:=breath_angle(event,run.elapsed-run.FIXED_STEP,sweep)
		if before==INF: before=now
		for role in range(2):
			var angle:=player_angle(event,players(run)[role])
			if angle>=minf(before,now)-BREATH_HALF and angle<=maxf(before,now)+BREATH_HALF:
				hit(run,event,role,"breath%d"%sweep,BREATH_DAMAGE)
	var done: float=BREATH_WINDUP*pace(event)+breath_sweeps(event)*BREATH_SWEEP+(breath_sweeps(event)-1)*BREATH_GAP
	if age(run,event)>=done: enter(run,event,"recover")

# —— 甩尾震地 ——

static func tail_rings(event: Dictionary) -> int:
	return 2 if event.stage>=1 else 1

static func tail_radius(event: Dictionary, time: float, ring: int) -> float:
	var start: float=event.state_at+TAIL_WINDUP*PACE[event.stage]+ring*TAIL_SECOND
	if time<start: return -1.0
	return (time-start)*TAIL_SPEED

static func tail_reach(run, event: Dictionary) -> float:
	return (event.perch as Vector2).distance_to(Vector2(run.EDGE,event.arena+FLOOR))+60.0

static func tail(run, event: Dictionary) -> void:
	for ring in range(tail_rings(event)):
		var radius:=tail_radius(event,run.elapsed,ring)
		if radius<0.0: continue
		var before:=maxf(0.0,radius-TAIL_SPEED*run.FIXED_STEP)
		for role in range(2):
			var d: float=players(run)[role].distance_to(event.perch)
			if d>=before-TAIL_HALF-run.Motion.RADIUS and d<=radius+TAIL_HALF+run.Motion.RADIUS and run.foot_height(role)<TAIL_TOP:
				hit(run,event,role,"tail%d"%ring,TAIL_DAMAGE)
	var done: float=TAIL_WINDUP*pace(event)+(tail_rings(event)-1)*TAIL_SECOND+tail_reach(run,event)/TAIL_SPEED
	if age(run,event)>=done: enter(run,event,"recover")

# —— 火雨 ——

static func meteor_count(event: Dictionary) -> int:
	return 8 if event.stage==2 else 5

static func aim_meteors(run, event: Dictionary) -> void:
	var targets:Array=[]
	for n in range(meteor_count(event)):
		var point:Vector2=players(run)[n%2]+METEOR_OFFSETS[n]
		point.x=clampf(point.x,-run.EDGE+30,run.EDGE-30)
		point.y=clampf(point.y,event.arena+FLOOR+40,event.arena+HOLD)
		targets.append(point)
	event.targets=targets

static func meteor_land_age(event: Dictionary) -> float:
	return METEOR_WINDUP*PACE[event.stage]+METEOR_FALL

static func meteors(run, event: Dictionary) -> void:
	# 前摇期间落点跟着两人走，仰头喷火的瞬间锁定。
	if age(run,event)<METEOR_WINDUP*pace(event): aim_meteors(run,event)
	var land:=meteor_land_age(event)
	if age(run,event)>=land and age(run,event)-run.FIXED_STEP<land:
		for target:Vector2 in event.targets:
			for role in range(2):
				if players(run)[role].distance_to(target)<METEOR_RADIUS+run.Motion.RADIUS and run.foot_height(role)<40.0:
					hit(run,event,role,"meteors",METEOR_DAMAGE)
			event.pools.append({"position":target,"until":run.elapsed+POOL_TIME*(1.3 if event.stage==2 else 1.0)})
	if age(run,event)>=land+0.4: enter(run,event,"recover")

# 熔岩池：踩在上面每秒受一次灼烧（跳起时不算）；到时自动熄灭。
static func pools(run, event: Dictionary) -> void:
	var live:Array=[]
	for pool in event.pools:
		if run.elapsed<float(pool.until): live.append(pool)
	if live.size()!=event.pools.size(): event.pools=live
	for pool in live:
		for role in range(2):
			if players(run)[role].distance_to(pool.position)<float(pool.get("radius",POOL_RADIUS))+run.Motion.RADIUS*0.5 and run.foot_height(role)<10.0:
				run.Combat.hit(run,role,"boss:pool",POOL_DAMAGE,true)

# —— 起飞俯冲 ——

# 锁定横带：两人中点所在的纵向位置，限制在场地射击区内。
static func lane_target(run, event: Dictionary) -> float:
	var middle:float=(run.a.position.y+run.b.position.y)*0.5
	return clampf(middle,event.arena+FLOOR+STRAFE_HALF,event.arena+HOLD-STRAFE_HALF)

static func strafe_locked(run, event: Dictionary) -> bool:
	return event.state=="strafe" and age(run,event)>=STRAFE_LOCK

static func strafe(run, event: Dictionary) -> void:
	var t:=age(run,event)
	# 锁定前横带一直跟着两人（画面上的预警带随之移动），锁定后不再改道。
	if t<STRAFE_LOCK: event.lane_y=lane_target(run,event)
	if t>=STRAFE_LOCK and t<STRAFE_LOCK+STRAFE_PASS:
		var pose:=body_pose(run,event,run.elapsed)
		var x: float=(pose.pos as Vector2).x
		for role in range(2):
			var point:Vector2=players(run)[role]
			if absf(point.y-event.lane_y)<STRAFE_HALF+run.Motion.RADIUS and absf(point.x-x)<STRAFE_REACH:
				hit(run,event,role,"strafe",STRAFE_DAMAGE)
		# 三阶段横掠后沿横带留下几处熔岩。
		if event.stage==2:
			var serial:=int((t-STRAFE_LOCK)/0.25)
			if int((t-STRAFE_LOCK-run.FIXED_STEP)/0.25)!=serial and absf(x)<run.EDGE-40:
				event.pools.append({"position":Vector2(x,event.lane_y),"until":run.elapsed+2.5})
	if t>=STRAFE_END: enter(run,event,"recover")

# —— 悬空炎息 ——

static func beam_time(event: Dictionary) -> float:
	return BEAM_TIME[event.stage]

static func hover_beam_end(event: Dictionary) -> float:
	return HOVER_AIM+beam_time(event)

static func hover_done(event: Dictionary) -> float:
	return hover_beam_end(event)+HOVER_BACK+LAND_CLIP

static func start_hover(run, event: Dictionary) -> void:
	event.hover_count=int(event.get("hover_count",0))+1
	# 轮流追两人；起点在目标前方（朝龙的一侧），留出反应距离。
	event.beam_target=int(event.hover_count)%2
	event.beam=beam_start(run,event)
	event.beam_drops=0
	enter(run,event,"hover")

static func beam_start(run, event: Dictionary) -> Vector2:
	var target:Vector2=players(run)[int(event.beam_target)]
	var point:=target+Vector2(0,BEAM_LEAD)
	point.x=clampf(point.x,-run.EDGE+30,run.EDGE-30)
	point.y=clampf(point.y,event.arena+FLOOR+40,event.arena+HOLD)
	return point

# 火柱正在喷射（落点会伤人、留熔岩）。
static func beam_on(event: Dictionary, time: float) -> bool:
	if event.state!="hover" or event.hp<=0: return false
	var t: float=time-event.state_at
	return t>=HOVER_AIM and t<hover_beam_end(event)

static func hover(run, event: Dictionary) -> void:
	var t:=age(run,event)
	# 瞄准期间落点跟着目标走；喷火后按限速追赶。
	if t<HOVER_AIM: event.beam=beam_start(run,event)
	elif t<hover_beam_end(event):
		var into:=t-HOVER_AIM
		if event.stage>=1 and into>=beam_time(event)*0.5 and into-run.FIXED_STEP<beam_time(event)*0.5:
			event.beam_target=1-int(event.beam_target)
		var target:Vector2=players(run)[int(event.beam_target)]
		var focus:Vector2=event.beam
		event.beam=focus.move_toward(target,BEAM_SPEED[event.stage]*run.FIXED_STEP)
		for role in range(2):
			if players(run)[role].distance_to(event.beam)<BEAM_RADIUS+run.Motion.RADIUS and run.foot_height(role)<30.0:
				run.Combat.hit(run,role,"boss:beam",BEAM_DAMAGE,true)
		var serial:=int(into/BEAM_POOL_EVERY)
		if serial>=int(event.beam_drops):
			event.beam_drops=serial+1
			event.pools.append({"position":event.beam,"until":run.elapsed+BEAM_POOL_TIME[event.stage],"radius":BEAM_POOL_RADIUS})
	if t>=hover_done(event): enter(run,event,"recover")

# —— 召唤火蝠 ——

static func bats(run, event: Dictionary) -> void:
	if age(run,event)<BATS_WINDUP*pace(event): return
	if once_spawned(event):
		# 从龙巢两侧飞出（龙身后方），先飞过来再扑人，给玩家转火的时间。
		for n in range(BATS_COUNT[event.stage]):
			var point:=Vector2(BATS_X[n],float(event.perch.y)+60.0+(n%2)*40.0)
			var monster:Dictionary=run.Monsters.add(run,point,"forest","ember_bat")
			monster.alert=true
			monster.boss_add=true
			event.adds.append(monster.id)
	if age(run,event)>=BATS_WINDUP*pace(event)+BATS_RECOVER: enter(run,event,"recover")

static func once_spawned(event: Dictionary) -> bool:
	if int(event.get("bats_seq",-1))==int(event.skill_seq): return false
	event.bats_seq=event.skill_seq
	return true

static func living_adds(run, event: Dictionary) -> int:
	var count:=0
	for other in run.journey_events:
		if other.kind=="monster" and other.id in event.get("adds",[]) and other.hp>0: count+=1
	return count

# —— 蓄焰 / 锁龙链 ——

static func start_charge(run, event: Dictionary) -> void:
	event.hold=0.0
	event.pinned=false
	event.spit_seq=0
	event.skill="charge"
	enter(run,event,"charge")

static func plate_center(event: Dictionary, index: int) -> Vector2:
	return Vector2(PLATES[index].x,event.arena+PLATES[index].y)

static func on_plate(run, event: Dictionary, role: int) -> int:
	var point:Vector2=players(run)[role]
	if run.foot_height(role)>4.0: return -1
	for n in range(PLATES.size()):
		var center:=plate_center(event,n)
		if absf(point.x-center.x)<=PLATE_HALF and absf(point.y-center.y)<=PLATE_HALF: return n
	return -1

# 两人各站一块（不论左右）才算站稳。
static func plates_held(run, event: Dictionary) -> bool:
	var a:=on_plate(run,event,0)
	var b:=on_plate(run,event,1)
	return a>=0 and b>=0 and a!=b

static func hold_ratio(event: Dictionary) -> float:
	return clampf(float(event.get("hold",0.0))/HOLD_TIME,0.0,1.0)

# 第 n 口火球的出手时刻（相对蓄焰开始）与目标踏板。
static func spit_time(event: Dictionary, n: int) -> float:
	return CHARGE_WINDUP*PACE[event.stage]+1.4+n*SPIT_EVERY*PACE[event.stage]

static func charge(run, event: Dictionary) -> void:
	var windup:float=CHARGE_WINDUP*pace(event)
	var t:=age(run,event)
	if t<windup: return
	if plates_held(run,event): event.hold=float(event.hold)+run.FIXED_STEP
	else: event.hold=maxf(0.0,float(event.hold)-HOLD_DECAY*run.FIXED_STEP)
	# 吐火球：瞄准一块踏板，飞行 SPIT_FLIGHT 秒后落地；站在那块踏板上的人被烧。
	var n:int=event.spit_seq
	if t>=spit_time(event,n):
		event.spit_seq=n+1
		event.spit_target=plate_center(event,n%2)
		event.spit_at=run.elapsed
	if event.has("spit_at") and run.elapsed-float(event.spit_at)>=SPIT_FLIGHT and run.elapsed-float(event.spit_at)-run.FIXED_STEP<SPIT_FLIGHT:
		for role in range(2):
			if players(run)[role].distance_to(event.spit_target)<PLATE_HALF+run.Motion.RADIUS+8.0 and run.foot_height(role)<30.0:
				run.Combat.hit(run,role,"boss:spit:%d:%d"%[event.skill_seq,int(event.spit_seq)],SPIT_DAMAGE)
	if hold_ratio(event)>=1.0:
		event.pinned=true
		event.stagger_count+=1
		run.combat.notice="锁链缠住了%s！它被拽倒在地，胸口熔岩核暴露"%NAME
		enter(run,event,"stagger")
		return
	if t>=windup+CHARGE_LIMIT:
		event.skill="nova"
		enter(run,event,"nova")

static func nova_warning(run, event: Dictionary) -> bool:
	return event.state=="charge" and age(run,event)>=CHARGE_WINDUP*pace(event)+CHARGE_LIMIT-1.6

static func nova_radius(event: Dictionary, time: float) -> float:
	if event.state!="nova": return -1.0
	return (time-event.state_at)*NOVA_SPEED

static func nova(run, event: Dictionary) -> void:
	var radius:=nova_radius(event,run.elapsed)
	var before:=maxf(0.0,radius-NOVA_SPEED*run.FIXED_STEP)
	for role in range(2):
		var d: float=players(run)[role].distance_to(event.perch)
		if d>=before-NOVA_HALF-run.Motion.RADIUS and d<=radius+NOVA_HALF+run.Motion.RADIUS and run.foot_height(role)<NOVA_TOP:
			hit(run,event,role,"nova",NOVA_DAMAGE)
	if radius>tail_reach(run,event): enter(run,event,"recover")

# —— 三阶段：两侧火墙 ——

static func walls(run, event: Dictionary) -> void:
	for role in range(2):
		var point:Vector2=players(run)[role]
		if absf(point.x)>run.EDGE-WALL_WIDTH and point.y>=event.arena and run.foot_height(role)<20.0:
			run.Combat.hit(run,role,"boss:walls",WALL_DAMAGE,true)

# —— 补给（与第一章相同的节奏）——

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
	# 不落在绞盘踏板上。
	for n in range(PLATES.size()):
		if point.distance_to(plate_center(event,n))<80.0: point.y+=160.0 if point.y<event.arena+HOLD-200 else -160.0
	run.Combat.add_pickup(run,kind,point)

# —— 提示 ——

static func hint(run, event: Dictionary) -> String:
	if event.hp<=0: return "%s倒下了，继续前进"%NAME if run.elapsed-event.get("defeated_at",run.elapsed)<6.0 else ""
	match event.state:
		"intro": return ""
		"roar": return "%s怒吼：阶段 %d"%[NAME,event.stage+1]
		"breath":
			if breath_sweeps(event)==2: return "烈焰吐息：先躲到另一半场地，火焰扫过后立刻换边！"
			return "烈焰吐息：躲到亮起区域的另一半场地"
		"tail": return "甩尾震地：冲击环到脚下时跳起" if tail_rings(event)==1 else "甩尾震地：连续两道冲击环，跳两次"
		"meteors": return "火雨：离开落点圆圈，避开熔岩池"
		"strafe":
			if age(run,event)<STRAFE_LOCK: return "魔龙起飞：它要横掠喷火，留意地上的火线横带"
			return "俯冲火线：前后离开横带！"
		"charge":
			if nova_warning(run,event): return "炎爆将至：跳起躲避冲击！锁链 %d%%"%int(hold_ratio(event)*100)
			return "魔龙蓄焰：两人各站一块绞盘踏板拉动锁链，火球来了先让开 · %d%%"%int(hold_ratio(event)*100)
		"nova": return "炎爆：冲击环到脚下时跳起"
		"hover":
			if age(run,event)<HOVER_AIM: return "魔龙飞上天空：火柱要追着 %02d 烧，准备跑动"%(int(event.beam_target)+1)
			if age(run,event)<hover_beam_end(event): return "悬空炎息：火柱追着 %02d 走，一直跑别停，绕开地上的熔岩"%(int(event.beam_target)+1)
			return "魔龙飞回巢穴"
		"bats": return "魔龙召唤火翼妖：它们会俯冲扑咬，先把它们打下来"
		"stagger": return "魔龙被锁链拽倒！熔岩核暴露，全力输出"
	return ""
