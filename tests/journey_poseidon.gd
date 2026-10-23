extends SceneTree
# 第三章 Boss「海神波塞冬」：场地布局、开战存档、入场锁操作与跳过、悬浮与瞄准、护甲与锁定、
# 三叉激流（锁定直线 / 二阶段两道）、巨浪缺口、涌泉与水洼、召唤水族、怒涛震环、潮汐之心（能量绳横穿水球）破甲与海啸、阶段、两侧海水、重打与通关。
const Journey=preload("res://scripts/journey_run.gd")
const Boss=preload("res://scripts/journey_boss.gd")
const Poseidon=preload("res://scripts/journey_poseidon.gd")
var failures:Array=[]
var checks:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures.append(label);printerr("FAIL ",label)

func place(run,y:float,ax:float=-42.0,bx:float=42.0)->void:
	run.a.position=Vector2(ax,y);run.b.position=Vector2(bx,y)
	run.distance=y
	run.rope.reset(run.a.position,run.b.position)

# 清掉场上的召唤物，避免它们干扰后面单独验证的招式。
func fresh(run)->void:
	for e in run.journey_events:
		if e.kind=="monster" and e.get("boss_add",false):run.Combat.damage(run,e,e.hp)
	run.combat.health=[100,100];run.combat.invulnerable=[0.0,0.0];run.combat.hits.clear()
	run.invulnerable_until=0.0;run.shield=false

func ticks(run,count:int,jump:=false)->void:
	for n in range(count):run.step(run.FIXED_STEP,Vector2.ZERO,Vector2.ZERO,jump,jump)

func until(run,boss:Dictionary,state:String,limit:int=3000)->void:
	for n in range(limit):
		if boss.state==state:return
		ticks(run,1)

func chapter(index:int):
	var run=Journey.new();run.level_index=index;run.retry()
	run.state="running";run.clear_input=false
	for gate in run.charge_gates:gate.open=true;gate.opened_at=-10.0
	run.select_charge_gate()
	return run

func start(run,boss:Dictionary,state:String)->void:
	boss.skill_seq+=1
	Poseidon.enter(run,boss,state)

# 在水环到达两人之前 lead 秒起跳。
func jump_before(run,boss:Dictionary,ring:int,lead:float)->void:
	for n in range(1200):
		var time:float=run.elapsed+n*run.FIXED_STEP
		var r:float=Poseidon.ring_radius(boss,time,ring) if boss.state=="ring" else Poseidon.tsunami_radius(boss,time)
		var center:Vector2=Poseidon.ring_center(boss) if boss.state=="ring" else Poseidon.source(run,boss)
		var d:float=run.a.position.distance_to(center)
		if r>=d-Poseidon.RING_HALF-12.0:
			ticks(run,maxi(0,roundi(n-lead/run.FIXED_STEP)))
			ticks(run,1,true)
			return

func _initialize()->void:call_deferred("verify")

func verify()->void:
	# —— 布局 ——
	var run=chapter(2)
	var boss:Dictionary=Boss.boss(run)
	check(Boss.poseidon(boss) and boss.arena==run.finish_distance()-Poseidon.ARENA,"第三章末尾登记海神场地")
	check(Boss.title(boss)==Poseidon.NAME,"Boss 名称")
	for i in range(run.kinds.size()):
		check(run.obstacles[i].end.y<boss.arena or run.obstacles[i].position.x>run.EDGE,"机关不进入海神场地：%s"%run.kinds[i])
	for gate in run.charge_gates: check(gate.receiver.y<boss.arena,"合作门在场地之前")
	for event in run.journey_events:
		if event.kind=="monster": check(event.y<boss.arena,"场地内没有预置怪物")
	check(run.combat.pickups.filter(func(p):return p.kind=="gun" and p.position.y>boss.arena).size()==2,"场地入口两把枪")
	check(Poseidon.body_pose(run,boss,run.elapsed).alt<0.0,"开战前海神沉在潭底")
	# —— 开战与站位上限 ——
	place(run,boss.arena+200);fresh(run);ticks(run,2)
	check(boss.phase=="dormant","入口前海神不出现")
	place(run,boss.arena+320);ticks(run,1)
	check(boss.phase=="intro" and not run.checkpoint.is_empty(),"越过开战线进入入场并存档")
	var saved_progress:float=run.checkpoint.progress
	check(run.bounded(Vector2(0,boss.arena+1700)).y==boss.arena+Poseidon.HOLD,"海神存活时前进受限")
	# —— 入场：破水升起，不能移动、开火、受伤；0.8 秒后可跳过 ——
	check(Boss.cinematic(run) and Boss.hint(run).is_empty(),"入场期间不显示招式提示")
	ticks(run,roundi(3.0/run.FIXED_STEP))
	check(Poseidon.body_pose(run,boss,run.elapsed).alt<0.0,"入场前段仍在水下")
	var risen:=Poseidon.body_pose(run,boss,boss.state_at+Poseidon.INTRO_RISEN+0.01)
	check(risen.alt>Poseidon.HOVER-12.0 and risen.pos.distance_to(boss.perch)<1.0,"升出水面悬浮在潭心")
	run.combat.weapons[0]=run.Combat.gun()
	var held:Vector2=run.a.position
	for n in range(60):
		run.set_combat_input(true)
		run.step(run.FIXED_STEP,Vector2(1,1),Vector2(-1,1))
	check(run.a.position.distance_to(held)<0.01,"入场期间输入不移动角色")
	check(run.combat.weapons[0].target==-1,"入场期间不锁定海神")
	run.Combat.hit(run,0,"test:intro",50)
	check(run.combat.health[0]==100,"入场期间不受伤害")
	run.step(run.FIXED_STEP,Vector2.ZERO,Vector2.ZERO,false,true)
	check(boss.get("intro_skipped",false) and run.elapsed-boss.state_at>=Poseidon.INTRO-Poseidon.RETURN_TIME-0.01,"按跳跃跳到镜头交还段")
	run.set_combat_input(false)
	run.combat.weapons[0]={}
	until(run,boss,"idle")
	check(boss.phase=="fight" and not Boss.cinematic(run),"入场结束进入战斗")
	# —— 悬浮、漂移、护甲与锁定 ——
	var p0:=Poseidon.body_pose(run,boss,run.elapsed)
	var p1:=Poseidon.body_pose(run,boss,run.elapsed+3.0)
	check(p0.alt>Poseidon.HOVER-12.0 and absf(p0.pos.x-p1.pos.x)>10.0 and absf(p1.pos.x)<=Poseidon.DRIFT+0.1,"战斗中悬浮并左右漂移")
	run.combat.weapons[0]=run.Combat.gun();place(run,boss.arena+1250);fresh(run);ticks(run,1)
	check(run.combat.weapons[0].target==boss.id,"自动锁定海神")
	check(boss.aim_height>Poseidon.CHEST_HEIGHT+Poseidon.HOVER-15.0,"瞄准点在悬浮的胸口")
	var hp:int=boss.hp
	run.Combat.damage(run,boss,10)
	check(boss.hp>=hp-3,"神铠减伤")
	run.combat.weapons[0]={}
	# —— 三叉激流：站着不动被打中，锁定后横向让开 ——
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"lance");Poseidon.aim_lances(run,boss)
	until(run,boss,"recover")
	var lanced:int=[0,1].filter(func(r):return run.combat.health[r]<100).size()
	check(lanced>=1,"站在激流直线上被打中")
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"lance");Poseidon.aim_lances(run,boss)
	ticks(run,roundi(Poseidon.LANCE_WINDUP*Poseidon.PACE[boss.stage]/run.FIXED_STEP)+1)
	var dirs:Array=boss.lances.duplicate()
	place(run,boss.arena+900,-180,-110);ticks(run,1)
	check(boss.lances==dirs,"出手后激流方向锁定")
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"锁定后横向让开躲过激流")
	# —— 巨浪：不在缺口被冲到，钻进缺口躲开 ——
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"wave");Poseidon.plan_gaps(run,boss)
	check(boss.gaps.size()==1 and absf(boss.gaps[0])>=90.0,"一阶段一道浪、缺口偏离两人")
	until(run,boss,"recover")
	check(run.combat.health==[100-Poseidon.WAVE_DAMAGE,100-Poseidon.WAVE_DAMAGE],"不在缺口被巨浪冲到")
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"wave");Poseidon.plan_gaps(run,boss)
	var gap:float=boss.gaps[0]
	place(run,boss.arena+900,gap-28,gap+28)
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"两人钻进缺口躲过巨浪")
	# 巨浪不能跳过。
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"wave");Poseidon.plan_gaps(run,boss)
	for n in range(roundi(5.0/run.FIXED_STEP)):
		if boss.state!="wave":break
		var y:=Poseidon.wave_y(boss,run.elapsed+0.15,0)
		ticks(run,1,y!=INF and y!=-INF and absf(y-run.a.position.y)<60.0)
	check(run.combat.health[0]<100,"巨浪跳不过去")
	# —— 涌泉与水洼 ——
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"geysers");Poseidon.aim_geysers(run,boss)
	check(boss.targets.size()==4,"一阶段四处涌泉")
	until(run,boss,"recover")
	check(run.combat.health==[100-Poseidon.GEYSER_DAMAGE,100-Poseidon.GEYSER_DAMAGE],"站在圆圈里被涌泉冲到")
	check(boss.puddles.size()==4,"落点留下旋涡水洼")
	ticks(run,roundi(1.2/run.FIXED_STEP))
	check(run.combat.health[0]<100-Poseidon.GEYSER_DAMAGE,"站在水洼里持续受损")
	place(run,boss.arena+900);fresh(run);boss.puddles=[]
	start(run,boss,"geysers");Poseidon.aim_geysers(run,boss)
	ticks(run,roundi(Poseidon.GEYSER_WINDUP*Poseidon.PACE[boss.stage]/run.FIXED_STEP)+1)
	place(run,boss.arena+560);ticks(run,1)
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"出手后离开圆圈躲过涌泉")
	ticks(run,roundi(Poseidon.PUDDLE_TIME/run.FIXED_STEP)+2)
	check(boss.puddles.is_empty(),"水洼到时消散")
	# —— 召唤水族 ——
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"summon")
	until(run,boss,"recover")
	var adds:Array=run.journey_events.filter(func(e):return e.kind=="monster" and e.get("boss_add",false) and e.hp>0)
	check(adds.size()==Poseidon.summon_count(boss) and adds.all(func(e):return e.archetype=="tide_jelly" and e.alert),"一阶段召唤两只潮汐水母")
	check(Poseidon.living_adds(run,boss)==2 and run.Monsters.ranged(adds[0]) and run.Monsters.hover_height(adds[0])>0.0,"水母会飞、远程攻击")
	fresh(run)
	# —— 潮汐之心：分站两侧让绳子横穿水球，站稳足够时间海神被震落；硬直满伤害 ——
	boss.skill_seq+=1;Poseidon.start_channel(run,boss)
	place(run,boss.arena+900);fresh(run)
	ticks(run,roundi((Poseidon.CHANNEL_WINDUP+Poseidon.ORB_DROP+0.4)/run.FIXED_STEP))
	check(Poseidon.orb_ready(boss,run.elapsed) and Poseidon.hold_ratio(boss)==0.0,"水球落到场地中段；两人站在一侧不计进度")
	# 跟着水球左右摆动，两人分站水球两侧（绳子穿过球心）。
	for n in range(roundi(6.0/run.FIXED_STEP)):
		if boss.state!="channel":break
		var c:=Poseidon.orb_center(boss,run.elapsed)
		var ta:=Vector2(c.x-55,c.y);var tb:=Vector2(c.x+55,c.y)
		var dir_a:Vector2=(ta-run.a.position)/12.0;var dir_b:Vector2=(tb-run.b.position)/12.0
		run.step(run.FIXED_STEP,dir_a.limit_length(1.0),dir_b.limit_length(1.0))
	check(boss.state=="stagger","能量绳横穿水球站稳足够时间，海神被震落")
	ticks(run,roundi(0.6/run.FIXED_STEP))
	check(boss.aim_height<Poseidon.CHEST_HEIGHT+Poseidon.HOVER*0.5,"硬直时跌到水面")
	hp=boss.hp
	run.Combat.damage(run,boss,10)
	check(boss.hp==hp-10,"硬直时满伤害")
	check(run.active_hint().contains("海神之心"),"硬直提示")
	var ammo_before:int=run.combat.pickups.filter(func(p):return p.kind=="ammo").size()
	until(run,boss,"recover")
	check(run.combat.pickups.filter(func(p):return p.kind=="ammo").size()>ammo_before,"硬直结束刷新弹药")
	# 水弹：站着不动会被打中。
	place(run,boss.arena+900,-100,-30);fresh(run)
	boss.skill_seq+=1;Poseidon.start_channel(run,boss)
	ticks(run,roundi((Poseidon.bolt_time(boss,0)+Poseidon.BOLT_FLIGHT+0.1)/run.FIXED_STEP))
	check(run.combat.health[0]<100,"站着不动被水弹打中")
	# 超时海啸：跳起躲开；不跳被打中。
	place(run,boss.arena+900,-100,-30);fresh(run)
	until(run,boss,"tsunami")
	place(run,boss.arena+900,-100,-30);fresh(run)
	jump_before(run,boss,0,0.2)
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"海啸水环到脚下时跳起躲开")
	place(run,boss.arena+900);fresh(run)
	boss.skill_seq+=1;Poseidon.start_channel(run,boss)
	until(run,boss,"tsunami",roundi(30.0/run.FIXED_STEP));fresh(run);until(run,boss,"recover")
	check(run.combat.health==[100-Poseidon.TSUNAMI_DAMAGE,100-Poseidon.TSUNAMI_DAMAGE],"不跳被海啸击中")
	# —— 阶段二：两道激流、两道浪、怒涛震环 ——
	boss.hp=int(boss.max_hp*0.6);Poseidon.enter(run,boss,"idle")
	until(run,boss,"roar")
	check(boss.stage==1,"血量 65% 以下进入第二阶段")
	until(run,boss,"idle")
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"lance");Poseidon.aim_lances(run,boss)
	check(boss.lances.size()==2,"二阶段两道激流分别瞄准两人")
	until(run,boss,"recover")
	check(run.combat.health[0]<100 and run.combat.health[1]<100,"二阶段两人都被瞄准")
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"wave");Poseidon.plan_gaps(run,boss)
	check(boss.gaps.size()==2 and absf(boss.gaps[0]-boss.gaps[1])>=140.0,"二阶段两道浪缺口换位")
	# 跟着缺口走：每道浪到来前站进对应缺口。
	for n in range(roundi(8.0/run.FIXED_STEP)):
		if boss.state!="wave":break
		# 第一道浪越过两人后立刻转向第二道缺口。
		var front:=Poseidon.wave_y(boss,run.elapsed,0)
		var which:=0 if front==INF or (front!=-INF and front>run.a.position.y-Poseidon.WAVE_HALF-20.0) else 1
		var g:float=boss.gaps[which]
		var dir_a:Vector2=(Vector2(g-26,run.a.position.y)-run.a.position)/12.0;var dir_b:Vector2=(Vector2(g+26,run.b.position.y)-run.b.position)/12.0
		run.step(run.FIXED_STEP,dir_a.limit_length(1.0),dir_b.limit_length(1.0))
	check(run.combat.health==[100,100],"跟着换边的缺口躲过两道浪")
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"ring")
	ticks(run,2)
	jump_before(run,boss,0,0.2)
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"怒涛震环到脚下时跳起躲开")
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"ring")
	until(run,boss,"recover")
	check(run.combat.health==[100-Poseidon.RING_DAMAGE,100-Poseidon.RING_DAMAGE],"不跳被震环击中")
	# —— 阶段三：三道激流、两道震环、两侧海水 ——
	boss.hp=int(boss.max_hp*0.25);Poseidon.enter(run,boss,"idle")
	until(run,boss,"roar")
	check(boss.stage==2,"血量 30% 以下进入第三阶段")
	check(Poseidon.ring_count(boss)==2 and Poseidon.geyser_count(boss)==7,"三阶段两道震环、七处涌泉")
	place(run,boss.arena+900,-run.EDGE+20,-run.EDGE+110);fresh(run);ticks(run,2)
	check(run.combat.health[0]==100-Poseidon.FLOOD_DAMAGE,"三阶段贴边被海水冲刷")
	# —— 招式循环：每轮若干招后必定凝聚潮汐之心 ——
	boss.cycle_moves=Poseidon.MOVES[boss.stage];Poseidon.enter(run,boss,"idle")
	place(run,boss.arena+900);fresh(run)
	until(run,boss,"channel",roundi(3.0/run.FIXED_STEP))
	check(boss.state=="channel","每轮招式后凝聚潮汐之心（破甲机会）")
	# —— 失败后从场地入口重打 ——
	fresh(run);run.fail_threat("测试失败")
	run.state="failed";check(run.restore_checkpoint(),"失败后恢复存档")
	boss=Boss.boss(run)
	check(boss.phase=="dormant" and boss.hp==boss.max_hp and absf(run.checkpoint.progress-saved_progress)<1.0,"恢复到场地入口，海神满血沉睡")
	# —— 击败后通关 ——
	run.state="running";place(run,boss.arena+320);fresh(run);ticks(run,1)
	Poseidon.enter(run,boss,"stagger")
	run.Combat.damage(run,boss,boss.max_hp)
	check(boss.hp==0 and Boss.hold_y(run)==INF,"击败后道路放开")
	ticks(run,roundi(4.5/run.FIXED_STEP))
	check(Poseidon.body_pose(run,boss,run.elapsed).alt<0.0,"倒下后沉入深潭")
	place(run,run.finish_distance()+10);ticks(run,2)
	check(run.state=="settlement","走到终点结算")
	run.dispose()
	print("POSEIDON CHECKS ",checks," FAILURES ",failures.size())
	quit(1 if not failures.is_empty() else 0)
