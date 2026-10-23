extends SceneTree
# 第二章 Boss「烬翼魔龙」：场地布局、开战存档、入场锁操作与跳过、护甲与锁定、
# 吐息（半场 / 二阶段换边）、甩尾冲击环、火雨与熔岩池、起飞横掠、绞盘锁链破甲与炎爆、阶段、火墙、重打与通关。
const Journey=preload("res://scripts/journey_run.gd")
const Boss=preload("res://scripts/journey_boss.gd")
const Dragon=preload("res://scripts/journey_dragon.gd")
var failures:Array=[]
var checks:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures.append(label);printerr("FAIL ",label)

func place(run,y:float,ax:float=-42.0,bx:float=42.0)->void:
	run.a.position=Vector2(ax,y);run.b.position=Vector2(bx,y)
	run.distance=y
	run.rope.reset(run.a.position,run.b.position)

func fresh(run)->void:
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
	Dragon.enter(run,boss,state)

# 在冲击环到达两人之前 lead 秒起跳。
func jump_before(run,boss:Dictionary,ring:int,lead:float)->void:
	var d:float=run.a.position.distance_to(boss.perch)
	for n in range(1200):
		var r:=Dragon.tail_radius(boss,run.elapsed+n*run.FIXED_STEP,ring) if boss.state=="tail" else Dragon.nova_radius(boss,run.elapsed+n*run.FIXED_STEP)
		if r>=d-Dragon.TAIL_HALF-12.0:
			ticks(run,maxi(0,roundi(n-lead/run.FIXED_STEP)))
			ticks(run,1,true)
			return

func _initialize()->void:call_deferred("verify")

func verify()->void:
	# —— 布局 ——
	var run=chapter(1)
	var boss:Dictionary=Boss.boss(run)
	check(Boss.dragon(boss) and boss.arena==run.finish_distance()-Dragon.ARENA,"第二章末尾登记魔龙场地")
	check(boss.perch.y==boss.arena+Dragon.PERCH and boss.origin.y<boss.perch.y,"瞄准点在落点前方的胸口")
	for i in range(run.kinds.size()):
		check(run.obstacles[i].end.y<boss.arena or run.obstacles[i].position.x>run.EDGE,"机关不进入魔龙场地：%s"%run.kinds[i])
	for gate in run.charge_gates: check(gate.receiver.y<boss.arena,"合作门在场地之前")
	for event in run.journey_events:
		if event.kind=="monster": check(event.y<boss.arena,"场地内没有预置怪物")
	check(run.combat.pickups.filter(func(p):return p.kind=="gun" and p.position.y>boss.arena).size()==2,"场地入口两把枪")
	check(Dragon.plate_center(boss,0).distance_to(Dragon.plate_center(boss,1))<run.LINK_LIMIT-10.0,"两块绞盘踏板间距小于绳长")
	# —— 开战与站位上限 ——
	place(run,boss.arena+200);fresh(run);ticks(run,2)
	check(boss.phase=="dormant","入口前魔龙不在场")
	place(run,boss.arena+320);ticks(run,1)
	check(boss.phase=="intro" and not run.checkpoint.is_empty(),"越过开战线进入入场并存档")
	var saved_progress:float=run.checkpoint.progress
	check(run.bounded(Vector2(0,boss.arena+1700)).y==boss.arena+Dragon.HOLD,"魔龙存活时前进受限")
	# —— 入场：盘旋 → 降落 → 咆哮 → 喷火；不能移动、开火、受伤；0.8 秒后可跳过 ——
	check(Boss.cinematic(run) and Boss.hint(run).is_empty(),"入场期间不显示招式提示")
	ticks(run,roundi(3.0/run.FIXED_STEP))
	var circling:=Dragon.body_pose(run,boss,run.elapsed)
	check(circling.alt>300.0 and circling.pos.distance_to(Vector2(0,boss.arena+Dragon.CIRCLE_CENTER))<Dragon.CIRCLE_RADIUS+20.0,"入场时在场地上空盘旋")
	var landing:=Dragon.body_pose(run,boss,boss.state_at+Dragon.INTRO_LAND+0.01)
	check(landing.alt==0.0 and landing.pos.distance_to(boss.perch)<1.0 and landing.heading.y<-0.99,"俯冲降落在落点并面朝两人")
	run.combat.weapons[0]=run.Combat.gun()
	var held:Vector2=run.a.position
	for n in range(60):
		run.set_combat_input(true)
		run.step(run.FIXED_STEP,Vector2(1,1),Vector2(-1,1))
	check(run.a.position.distance_to(held)<0.01,"入场期间输入不移动角色")
	check(run.combat.weapons[0].target==-1,"入场期间不锁定魔龙")
	run.Combat.hit(run,0,"test:intro",50)
	check(run.combat.health[0]==100,"入场期间不受伤害")
	run.step(run.FIXED_STEP,Vector2.ZERO,Vector2.ZERO,false,true)
	check(boss.get("intro_skipped",false) and run.elapsed-boss.state_at>=Dragon.INTRO-Dragon.RETURN_TIME-0.01,"按跳跃跳到镜头交还段")
	run.set_combat_input(false)
	run.combat.weapons[0]={}
	until(run,boss,"idle")
	check(boss.phase=="fight" and not Boss.cinematic(run),"入场结束进入战斗")
	# —— 护甲与锁定 ——
	run.combat.weapons[0]=run.Combat.gun();place(run,boss.arena+1250);fresh(run);ticks(run,1)
	check(run.combat.weapons[0].target==boss.id,"自动锁定魔龙胸口")
	var hp:int=boss.hp
	run.Combat.damage(run,boss,10)
	check(boss.hp==hp-maxi(1,roundi(10*Boss.ARMOR)),"龙鳞只受 25% 伤害")
	run.combat.weapons[0]={}
	# —— 吐息：亮起的半场被烧到，另一半安全 ——
	place(run,boss.arena+900,120,190);fresh(run)
	start(run,boss,"breath");boss.breath_side=1.0
	until(run,boss,"recover")
	check(run.combat.health==[100-Dragon.BREATH_DAMAGE,100-Dragon.BREATH_DAMAGE],"站在吐息半场被烧")
	place(run,boss.arena+900,-190,-120);fresh(run)
	start(run,boss,"breath");boss.breath_side=1.0
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"另一半场地躲过吐息")
	place(run,boss.arena+700,-30,30);fresh(run)
	start(run,boss,"breath");boss.breath_side=1.0
	until(run,boss,"recover")
	check(run.combat.health[0]<100 and run.combat.health[1]<100,"中线附近也会被烧到")
	# —— 甩尾：不跳被冲击环击中，算好时机跳起躲开 ——
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"tail")
	until(run,boss,"recover")
	check(run.combat.health==[100-Dragon.TAIL_DAMAGE,100-Dragon.TAIL_DAMAGE],"不跳被冲击环击中")
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"tail")
	jump_before(run,boss,0,0.2)
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"冲击环到脚下时跳起躲开")
	# —— 火雨：留在落点被砸，出手后离开躲开；熔岩池灼烧 ——
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"meteors");Dragon.aim_meteors(run,boss)
	check(boss.targets.size()==5,"一阶段五颗火球")
	until(run,boss,"recover")
	check(run.combat.health==[100-Dragon.METEOR_DAMAGE,100-Dragon.METEOR_DAMAGE],"留在落点被火球砸中")
	check(boss.pools.size()==5,"落点留下熔岩池")
	ticks(run,roundi(1.2/run.FIXED_STEP))
	check(run.combat.health[0]<100-Dragon.METEOR_DAMAGE,"站在熔岩池里持续灼烧")
	ticks(run,roundi(Dragon.POOL_TIME/run.FIXED_STEP))
	check(boss.pools.is_empty(),"熔岩池到时熄灭")
	place(run,boss.arena+900);fresh(run)
	start(run,boss,"meteors");Dragon.aim_meteors(run,boss)
	ticks(run,roundi(Dragon.METEOR_WINDUP*Dragon.PACE[boss.stage]/run.FIXED_STEP)+1)
	var locked:Array=boss.targets.duplicate()
	place(run,boss.arena+500);ticks(run,1)
	check(boss.targets==locked,"出手后火球落点锁定")
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"出手后离开落点躲过火雨")
	ticks(run,roundi(Dragon.POOL_TIME/run.FIXED_STEP)+2)
	# —— 绞盘锁链：两人各站一块踏板累计站稳，魔龙被拽倒；硬直满伤害 ——
	var p0:=Dragon.plate_center(boss,0)
	var p1:=Dragon.plate_center(boss,1)
	place(run,p0.y,p0.x,p1.x);fresh(run)
	boss.skill_seq+=1;Dragon.start_charge(run,boss)
	ticks(run,roundi((Dragon.CHARGE_WINDUP+0.5)/run.FIXED_STEP))
	check(Dragon.plates_held(run,boss) and Dragon.hold_ratio(boss)>0.1,"两人站上踏板，锁链进度增加")
	until(run,boss,"stagger",roundi(6.0/run.FIXED_STEP))
	check(boss.state=="stagger" and boss.pinned,"站稳足够时间，锁链把魔龙拽倒")
	check(run.combat.health[0]<100 or run.combat.health[1]<100,"蓄焰期间朝踏板吐火球（站着不动会被烧）")
	hp=boss.hp
	run.Combat.damage(run,boss,10)
	check(boss.hp==hp-10,"硬直时满伤害")
	check(run.active_hint().contains("熔岩核"),"硬直提示")
	var ammo_before:int=run.combat.pickups.filter(func(p):return p.kind=="ammo").size()
	until(run,boss,"recover")
	check(not boss.pinned and run.combat.pickups.filter(func(p):return p.kind=="ammo").size()>ammo_before,"硬直结束锁链松开并刷新弹药")
	# 只有一人站板：进度不涨，超时炎爆；跳起躲开冲击环。
	place(run,p0.y,p0.x,p0.x+70);fresh(run)
	boss.skill_seq+=1;Dragon.start_charge(run,boss)
	ticks(run,roundi((Dragon.CHARGE_WINDUP+1.0)/run.FIXED_STEP))
	check(Dragon.hold_ratio(boss)==0.0,"只有一人站板不计进度")
	place(run,boss.arena+900);fresh(run)
	until(run,boss,"nova")
	jump_before(run,boss,0,0.2)
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"炎爆冲击环到脚下时跳起躲开")
	place(run,boss.arena+900);fresh(run)
	boss.skill_seq+=1;Dragon.start_charge(run,boss)
	until(run,boss,"nova");until(run,boss,"recover")
	check(run.combat.health==[100-Dragon.NOVA_DAMAGE,100-Dragon.NOVA_DAMAGE],"不跳被炎爆击中")
	# —— 阶段二：双向吐息、双冲击环、起飞横掠 ——
	boss.hp=int(boss.max_hp*0.6);Dragon.enter(run,boss,"idle")
	until(run,boss,"roar")
	check(boss.stage==1,"血量 65% 以下进入第二阶段")
	until(run,boss,"idle")
	place(run,boss.arena+900,-190,-120);fresh(run)
	start(run,boss,"breath");boss.breath_side=1.0
	until(run,boss,"recover")
	check(run.combat.health[0]<100,"二阶段原地不动会被反向第二道吐息烧到")
	place(run,boss.arena+900,-190,-120);fresh(run)
	start(run,boss,"breath");boss.breath_side=1.0
	# 第一道扫完立刻换到另一半。
	for n in range(roundi(5.0/run.FIXED_STEP)):
		if boss.state!="breath":break
		var crossed:bool=run.elapsed-boss.state_at>Dragon.BREATH_WINDUP*Dragon.PACE[boss.stage]+Dragon.BREATH_SWEEP+0.05
		if crossed and run.a.position.x<0: place(run,boss.arena+900,120,190)
		ticks(run,1)
	check(run.combat.health==[100,100],"二阶段第一道扫过后换边躲过两道吐息")
	check(Dragon.tail_rings(boss)==2,"二阶段连续两道冲击环")
	place(run,boss.arena+700);fresh(run)
	boss.skill_seq+=1;boss.lane_y=Dragon.lane_target(run,boss);Dragon.enter(run,boss,"strafe")
	ticks(run,roundi(1.5/run.FIXED_STEP))
	check(boss.airborne and boss.aim_height>Dragon.CHEST_HEIGHT+100.0,"起飞后瞄准点随龙升空")
	until(run,boss,"recover")
	check(run.combat.health==[100-Dragon.STRAFE_DAMAGE,100-Dragon.STRAFE_DAMAGE],"留在横带被俯冲火线烧到")
	check(not boss.airborne and boss.origin.distance_to(boss.perch-Vector2(0,Dragon.CHEST_AHEAD))<1.0,"横掠后飞回落点降落")
	place(run,boss.arena+700);fresh(run)
	boss.skill_seq+=1;boss.lane_y=Dragon.lane_target(run,boss);Dragon.enter(run,boss,"strafe")
	ticks(run,roundi(Dragon.STRAFE_LOCK/run.FIXED_STEP)+1)
	var lane:float=boss.lane_y
	place(run,lane-200.0);ticks(run,1)
	check(boss.lane_y==lane,"锁定后横带不再跟随")
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"锁定后离开横带躲过俯冲")
	# —— 阶段三：火墙 ——
	boss.hp=int(boss.max_hp*0.25);Dragon.enter(run,boss,"idle")
	until(run,boss,"roar")
	check(boss.stage==2,"血量 30% 以下进入第三阶段")
	check(Dragon.meteor_count(boss)==8,"三阶段八颗火球")
	place(run,boss.arena+900,-run.EDGE+20,-run.EDGE+110);fresh(run);ticks(run,2)
	check(run.combat.health[0]==100-Dragon.WALL_DAMAGE,"三阶段贴边被火墙烧到")
	# —— 招式循环：每轮若干招后必定蓄焰 ——
	boss.cycle_moves=Dragon.MOVES[boss.stage];Dragon.enter(run,boss,"idle")
	place(run,boss.arena+900);fresh(run)
	until(run,boss,"charge",roundi(3.0/run.FIXED_STEP))
	check(boss.state=="charge","每轮招式后进入蓄焰（破甲机会）")
	# —— 失败后从场地入口重打 ——
	fresh(run);run.fail_threat("测试失败")
	run.state="failed";check(run.restore_checkpoint(),"失败后恢复存档")
	boss=Boss.boss(run)
	check(boss.phase=="dormant" and boss.hp==boss.max_hp and absf(run.checkpoint.progress-saved_progress)<1.0,"恢复到场地入口，魔龙满血不在场")
	# —— 击败后通关 ——
	run.state="running";place(run,boss.arena+320);fresh(run);ticks(run,1)
	Dragon.enter(run,boss,"stagger")
	run.Combat.damage(run,boss,boss.max_hp)
	check(boss.hp==0 and Boss.hold_y(run)==INF,"击败后道路放开")
	ticks(run,1)
	place(run,run.finish_distance()+10);ticks(run,2)
	check(run.state=="settlement","走到终点结算")
	run.dispose()
	print("DRAGON CHECKS ",checks," FAILURES ",failures.size())
	quit(1 if not failures.is_empty() else 0)
