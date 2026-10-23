extends SceneTree
# 第一章 Boss「枯根巨像」：场地布局、开战存档、站位上限、护甲与硬直、五种技能的命中与躲避、
# 绳索灼断缚根、阶段切换、击败后通关与失败后恢复最近阶段。
const Journey=preload("res://scripts/journey_run.gd")
const Boss=preload("res://scripts/journey_boss.gd")
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

func until(run,boss:Dictionary,state:String,limit:int=2400)->void:
	for n in range(limit):
		if boss.state==state:return
		ticks(run,1)

func chapter(index:int):
	var run=Journey.new();run.level_index=index;run.retry()
	run.state="running";run.clear_input=false
	# 只验证 Boss 场地：途中合作门视为已开，避免关着的门把直接放置的角色夹回门前。
	for gate in run.charge_gates:gate.open=true;gate.opened_at=-10.0
	run.select_charge_gate()
	return run

func _initialize()->void:call_deferred("verify")

func verify()->void:
	# —— 布局 ——
	# 第二章是烬翼魔龙（tests/journey_dragon.gd），第三章暂无 Boss。
	var third=chapter(2)
	check(Boss.boss(third).is_empty(),"第 3 章没有 Boss")
	third.dispose()
	var second=chapter(1)
	check(Boss.dragon(Boss.boss(second)),"第 2 章的 Boss 是魔龙")
	second.dispose()
	var run=chapter(0)
	var boss:Dictionary=Boss.boss(run)
	check(not boss.is_empty() and boss.arena==run.finish_distance()-Boss.ARENA,"第一章末尾登记 Boss 场地")
	for i in range(run.kinds.size()):
		if run.obstacle_ids[i]==boss.pillar:
			check(run.kinds[i]=="pillar" and run.obstacles[i].get_center().distance_to(Boss.pillar_center(boss))<0.01,"场地左侧立着缠柱")
			continue
		if not (run.obstacles[i].end.y<boss.arena or run.obstacles[i].position.x>run.EDGE):print("IN ARENA ",run.kinds[i]," ",run.obstacles[i])
		check(run.obstacles[i].end.y<boss.arena or run.obstacles[i].position.x>run.EDGE,"机关不进入 Boss 场地：%s"%run.kinds[i])
	for gate in run.charge_gates: check(gate.receiver.y<boss.arena,"合作门在 Boss 场地之前")
	for event in run.journey_events:
		if event.kind=="monster": check(event.y<boss.arena,"场地内没有预置怪物")
	check(run.combat.pickups.filter(func(p):return p.kind=="gun" and p.position.y>boss.arena).size()==2,"场地入口两把枪")
	# —— 开战与站位上限 ——
	place(run,boss.arena+200);fresh(run);ticks(run,2)
	check(boss.phase=="dormant","入口前 Boss 沉睡")
	place(run,boss.arena+320);ticks(run,1)
	check(boss.phase=="intro" and not run.checkpoint.is_empty(),"越过开战线进入苏醒并存档")
	check(run.bounded(Vector2(0,boss.arena+1700)).y==boss.arena+Boss.HOLD,"Boss 存活时前进被限制在树心前")
	check(not run.mid_checkpoint_clear() and not run.checkpoint_ground_clear(),"战斗中不补充存档")
	# —— 入场动画：不能移动、开火、受伤，Boss 不能被锁定；开场 0.8 秒后按跳跃可跳过 ——
	check(Boss.cinematic(run) and Boss.hint(run).is_empty(),"入场动画期间不显示招式提示")
	run.combat.weapons[0]=run.Combat.gun()
	var held:Vector2=run.a.position
	for n in range(60):
		run.set_combat_input(true)
		run.step(run.FIXED_STEP,Vector2(1,1),Vector2(-1,1))
	check(run.a.position.distance_to(held)<0.01,"入场动画期间输入不移动角色")
	check(run.combat.weapons[0].ammo==run.Combat.WEAPONS.smg.magazine and run.combat.weapons[0].target==-1,"入场动画期间不开火、不锁定 Boss")
	run.Combat.hit(run,0,"test:intro",50)
	check(run.combat.health[0]==100,"入场动画期间不受伤害")
	run.step(run.FIXED_STEP,Vector2.ZERO,Vector2.ZERO,true,false)
	check(boss.phase=="intro" and run.elapsed-boss.state_at<Boss.INTRO_SKIP_AFTER,"开场 0.8 秒内按跳跃不跳过")
	for n in range(roundi(0.4/run.FIXED_STEP)):run.step(run.FIXED_STEP)
	run.step(run.FIXED_STEP,Vector2.ZERO,Vector2.ZERO,false,true)
	check(boss.get("intro_skipped",false) and run.elapsed-boss.state_at>=Boss.INTRO-Boss.RETURN_TIME-0.01,"任一人按跳跃跳到镜头交还段")
	check(run.a.position.distance_to(held)<0.01 and run.heights[1]==0.0,"跳过用的跳跃不让角色起跳")
	run.set_combat_input(false)
	run.combat.weapons[0]={}
	until(run,boss,"idle")
	check(boss.phase=="fight" and not Boss.cinematic(run),"入场结束进入战斗")
	# —— 护甲与锁定 ——
	run.combat.weapons[0]=run.Combat.gun();place(run,boss.arena+1250);fresh(run);ticks(run,1)
	check(run.combat.weapons[0].target==boss.id,"自动锁定 Boss 树心")
	# Boss 战中可以在场地内前后走：退到入口根墙前也不会被判“挤出画面”，射程加长后远处也能锁定。
	place(run,boss.arena+700);ticks(run,1)
	check(run.combat.weapons[0].target==boss.id,"射程加长：离树心 42 米仍能锁定")
	check(run.bounded(Vector2(0,boss.arena+40)).y==boss.arena+Boss.FLOOR,"场地内最远退到入口根墙前")
	run.distance=boss.arena+Boss.HOLD;place(run,boss.arena+1300)
	for n in range(600):run.step(run.FIXED_STEP,Vector2(0,-1),Vector2(0,-1))
	check(run.state=="running" and minf(run.a.position.y,run.b.position.y)<boss.arena+400,"真实输入可以一路后退到场地前段")
	check(absf(run.distance-maxf(minf(run.a.position.y,run.b.position.y),boss.arena+Boss.FLOOR))<0.01,"战斗中进度跟随落后者")
	var hp:int=boss.hp
	run.Combat.damage(run,boss,10)
	check(boss.hp==hp-maxi(1,roundi(10*Boss.ARMOR)),"护甲状态只受 25% 伤害")
	run.combat.weapons[0]={}
	# —— 根刺：站着被刺中，横移躲开 ——
	place(run,boss.arena+900);fresh(run)
	Boss.start_spikes(run,boss)
	check(boss.lanes.size()==3,"一阶段三道根刺")
	for n in range(400):
		if boss.state!="spikes":break
		ticks(run,1)
	check(run.combat.health==[100-Boss.SPIKE_DAMAGE,100-Boss.SPIKE_DAMAGE],"站在锁定直线上被根刺命中")
	place(run,boss.arena+900);fresh(run)
	Boss.start_spikes(run,boss)
	place(run,boss.arena+900,-200,-130)
	boss.lanes=[-42.0,42.0,240.0]
	for n in range(400):
		if boss.state!="spikes":break
		ticks(run,1)
	check(run.combat.health==[100,100],"离开直线躲过根刺")
	# —— 横扫：地面被扫中，同时起跳躲开 ——
	place(run,boss.arena+900);fresh(run)
	boss.skill_seq+=1;Boss.enter(run,boss,"sweep")
	until(run,boss,"recover")
	check(run.combat.health==[100-Boss.SWEEP_DAMAGE,100-Boss.SWEEP_DAMAGE],"不跳被横扫命中")
	place(run,boss.arena+900);fresh(run)
	boss.skill_seq+=1;Boss.enter(run,boss,"sweep")
	# 计算根臂扫到两人横向位置的时刻，提前 0.25 秒起跳。
	var arrive:=0.0
	for n in range(400):
		var x:=Boss.sweep_x(run,boss,run.elapsed+n*run.FIXED_STEP,0)
		if x!=INF and absf(x)<50:arrive=n*run.FIXED_STEP;break
	ticks(run,maxi(0,roundi((arrive-0.25)/run.FIXED_STEP)))
	ticks(run,1,true)
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"两人同时起跳躲过横扫")
	# —— 孢果 ——
	place(run,boss.arena+900);fresh(run)
	boss.skill_seq+=1;Boss.start_seeds(run,boss)
	check(boss.targets.size()==4,"一阶段四颗孢果")
	until(run,boss,"recover")
	check(run.combat.health==[100-Boss.SEED_DAMAGE,100-Boss.SEED_DAMAGE],"留在落点被孢果炸中")
	place(run,boss.arena+900);fresh(run)
	boss.skill_seq+=1;Boss.start_seeds(run,boss)
	# 前摇期间落点跟着人走；出手后锁定，再离开就躲得开。
	place(run,boss.arena+700,-150,-60);ticks(run,2)
	check(boss.targets[0].distance_to(run.a.position)<1.0 and boss.targets[1].distance_to(run.b.position)<1.0,"前摇期间孢果落点跟随两人")
	check(boss.targets.all(func(t):return minf(t.distance_to(run.a.position),t.distance_to(run.b.position))<=80.0),"孢果都落在两人身边")
	ticks(run,roundi(Boss.SEED_WINDUP*Boss.PACE[boss.stage]/run.FIXED_STEP))
	var locked:Array=boss.targets.duplicate()
	place(run,boss.arena+450,-150,-60);ticks(run,1)
	check(boss.targets==locked,"出手后落点锁定")
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"出手后离开落点躲过孢果")
	# —— 扎根汲取 / 缠柱：站着不动不计进度，超时冲击；一人站定、另一人绕柱一圈缠住后萎靡 ——
	var pillar:Vector2=Boss.pillar_center(boss)
	place(run,pillar.y,-120,-40);fresh(run)
	boss.skill_seq+=1;Boss.start_root(run,boss)
	ticks(run,roundi((Boss.ROOT_WINDUP+1.0)/run.FIXED_STEP))
	check(boss.burn==0.0,"不绕柱时没有缠绕进度")
	until(run,boss,"recover")
	check(run.combat.health==[100-Boss.RIP_DAMAGE,100-Boss.RIP_DAMAGE],"超时根臂拔出冲击地面上的人")
	run.a.position=pillar+Vector2(-28,0);run.b.position=pillar+Vector2.from_angle(PI+0.7)*55.0
	run.distance=minf(run.a.position.y,run.b.position.y);run.rope.reset(run.a.position,run.b.position);fresh(run)
	boss.skill_seq+=1;Boss.start_root(run,boss)
	ticks(run,roundi(Boss.ROOT_WINDUP/run.FIXED_STEP)+1)
	for n in range(roundi(Boss.ROOT_LIMIT/run.FIXED_STEP)):
		if boss.state!="root":break
		var angle:float=(run.b.position-pillar).angle()
		var goal:=pillar+Vector2.from_angle(angle+0.45)*55.0
		var hold:=pillar+Vector2(-28,0)
		var delta_b:Vector2=goal-run.b.position
		var delta_a:Vector2=hold-run.a.position
		run.step(run.FIXED_STEP,delta_a.limit_length(1.0) if delta_a.length()>2.0 else Vector2.ZERO,delta_b.normalized())
	check(boss.state=="stagger" and boss.burned,"一人站定、另一人绕柱一圈用绳缠住，Boss 萎靡")
	check(not Boss.pillar_up(run,boss) and not Boss.rope_on_pillar(run,boss),"缠紧后石柱崩碎、绳子松开")
	boss.skill_seq+=1;Boss.start_root(run,boss);ticks(run,1)
	check(Boss.pillar_up(run,boss),"下一次扎根汲取时石柱重新升起")
	Boss.enter(run,boss,"stagger");boss.state_at=run.elapsed
	hp=boss.hp
	run.Combat.damage(run,boss,10)
	check(boss.hp==hp-10,"硬直时满伤害")
	check(run.active_hint().contains("树心暴露"),"硬直提示")
	var ammo_before:int=run.combat.pickups.filter(func(p):return p.kind=="ammo").size()
	until(run,boss,"idle")
	check(run.combat.pickups.filter(func(p):return p.kind=="ammo").size()>ammo_before,"硬直结束刷新弹药")
	# —— 战斗中随机掉弹药 ——
	var before_drops:int=run.combat.pickups.filter(func(p):return p.kind=="ammo" and p.position.y>boss.arena).size()
	boss.ammo_at=run.elapsed
	Boss.drop_ammo(run,boss)
	var drops:Array=run.combat.pickups.filter(func(p):return p.kind=="ammo" and p.position.y>boss.arena)
	check(drops.size()==mini(before_drops+1,Boss.AMMO_CAP) or before_drops>=Boss.AMMO_CAP,"战斗中定时在场内掉弹药")
	check(boss.ammo_at>run.elapsed,"掉落后进入下一次冷却")
	# —— 阶段切换与召唤 ——
	boss.hp=int(boss.max_hp*0.6);Boss.enter(run,boss,"idle")
	until(run,boss,"roar")
	check(boss.stage==1,"血量 65% 以下进入第二阶段")
	check(Boss.boss(run).stage==1 and run.checkpoint.run.journey_events[run.boss_index].stage==1,"第二阶段自动存档")
	until(run,boss,"idle")
	boss.cycle_moves=0;boss.pattern_index=0
	until(run,boss,"summon");until(run,boss,"recover")
	check(Boss.living_adds(run,boss)==3,"第二阶段召唤三只根须蛛")
	boss.skill_seq+=1;Boss.enter(run,boss,"sweep")
	check(Boss.sweep_arms(boss)==2,"第二阶段双臂连扫")
	boss.hp=int(boss.max_hp*0.25);Boss.enter(run,boss,"idle")
	until(run,boss,"roar")
	check(boss.stage==2,"血量 30% 以下进入第三阶段")
	var saved_boss:Dictionary=run.checkpoint.run.journey_events[run.boss_index].duplicate(true)
	var saved_combat:Dictionary=run.checkpoint.run.combat.duplicate(true)
	var saved_positions:Array=[run.checkpoint.a,run.checkpoint.b]
	place(run,boss.arena+900,-run.EDGE+20,-run.EDGE+110);fresh(run);ticks(run,2)
	check(run.combat.health[0]==100-Boss.THORN_DAMAGE,"第三阶段贴边被荆棘扣血")
	# —— 失败后恢复最近阶段，保留双方当时的战斗资源与位置 ——
	fresh(run);run.fail_threat("测试失败")
	run.state="failed";check(run.restore_checkpoint(),"失败后恢复存档")
	boss=Boss.boss(run)
	check(boss==saved_boss and boss.stage==2,"恢复第三阶段及当时 Boss 血量，不重播入场")
	check(run.combat==saved_combat and [run.a.position,run.b.position]==saved_positions,"恢复双方血量、武器、弹药及位置")
	# —— 击败后通关 ——
	run.state="running";place(run,boss.arena+320);fresh(run);ticks(run,1)
	Boss.enter(run,boss,"stagger")
	run.Combat.damage(run,boss,boss.max_hp)
	check(boss.hp==0 and Boss.hold_y(run)==INF,"击败后道路放开")
	ticks(run,1)
	place(run,run.finish_distance()+10);ticks(run,2)
	check(run.state=="settlement","走到终点结算")
	run.dispose()
	print("BOSS CHECKS ",checks," FAILURES ",failures.size())
	quit(1 if not failures.is_empty() else 0)
