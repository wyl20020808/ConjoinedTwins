extends SceneTree
# 第一章 Boss「枯根巨像」：场地布局、开战存档、站位上限、护甲与硬直、五种技能的命中与躲避、
# 绳索灼断缚根、阶段切换、击败后通关与失败后从场地入口重打。
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
	for index in [1,2]:
		var other=chapter(index)
		check(Boss.boss(other).is_empty(),"第 %d 章没有 Boss"%(index+1))
		other.dispose()
	var run=chapter(0)
	var boss:Dictionary=Boss.boss(run)
	check(not boss.is_empty() and boss.arena==run.finish_distance()-Boss.ARENA,"第一章末尾登记 Boss 场地")
	for i in range(run.kinds.size()):
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
	var saved_progress:float=run.checkpoint.progress
	check(run.bounded(Vector2(0,boss.arena+1700)).y==boss.arena+Boss.HOLD,"Boss 存活时前进被限制在树心前")
	check(not run.mid_checkpoint_clear() and not run.checkpoint_ground_clear(),"战斗中不补充存档")
	check(run.active_hint().contains(Boss.NAME),"苏醒提示")
	until(run,boss,"idle")
	check(boss.phase=="fight","苏醒结束进入战斗")
	# —— 护甲与锁定 ——
	run.combat.weapons[0]=run.Combat.gun();place(run,boss.arena+1250);fresh(run);ticks(run,1)
	check(run.combat.weapons[0].target==boss.id,"自动锁定 Boss 树心")
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
	place(run,boss.arena+600)
	until(run,boss,"recover")
	check(run.combat.health==[100,100],"离开落点躲过孢果")
	# —— 扎根汲取：同侧不灼烧，超时冲击；分站两侧灼断后硬直 ——
	place(run,boss.arena+900,-120,-40);fresh(run)
	boss.skill_seq+=1;Boss.start_root(run,boss)
	ticks(run,roundi((Boss.ROOT_WINDUP+1.0)/run.FIXED_STEP))
	check(boss.burn==0.0,"两人同侧时缚根不灼烧")
	until(run,boss,"recover")
	check(run.combat.health==[100-Boss.RIP_DAMAGE,100-Boss.RIP_DAMAGE],"超时根臂拔出冲击地面上的人")
	place(run,boss.arena+900);fresh(run)
	boss.skill_seq+=1;Boss.start_root(run,boss)
	place(run,boss.binding.y,-60,60)
	ticks(run,roundi((Boss.ROOT_WINDUP+Boss.BURN_TIME+0.2)/run.FIXED_STEP))
	check(boss.state=="stagger" and boss.burned,"分站两侧让绳索穿过缚根，灼断后硬直")
	hp=boss.hp
	run.Combat.damage(run,boss,10)
	check(boss.hp==hp-10,"硬直时满伤害")
	check(run.active_hint().contains("树心暴露"),"硬直提示")
	var ammo_before:int=run.combat.pickups.filter(func(p):return p.kind=="ammo").size()
	until(run,boss,"idle")
	check(run.combat.pickups.filter(func(p):return p.kind=="ammo").size()>ammo_before,"硬直结束刷新弹药")
	# —— 阶段切换与召唤 ——
	boss.hp=int(boss.max_hp*0.6);Boss.enter(run,boss,"idle")
	until(run,boss,"roar")
	check(boss.stage==1,"血量 65% 以下进入第二阶段")
	until(run,boss,"idle")
	boss.cycle_moves=0;boss.pattern_index=0
	until(run,boss,"summon");until(run,boss,"recover")
	check(Boss.living_adds(run,boss)==2,"第二阶段召唤两只根须蛛")
	boss.skill_seq+=1;Boss.enter(run,boss,"sweep")
	check(Boss.sweep_arms(boss)==2,"第二阶段双臂连扫")
	boss.hp=int(boss.max_hp*0.25);Boss.enter(run,boss,"idle")
	until(run,boss,"roar")
	check(boss.stage==2,"血量 30% 以下进入第三阶段")
	place(run,boss.arena+900,-run.EDGE+20,-run.EDGE+110);fresh(run);ticks(run,2)
	check(run.combat.health[0]==100-Boss.THORN_DAMAGE,"第三阶段贴边被荆棘扣血")
	# —— 失败后从场地入口重打 ——
	fresh(run);run.fail_threat("测试失败")
	run.state="failed";check(run.restore_checkpoint(),"失败后恢复存档")
	boss=Boss.boss(run)
	check(boss.phase=="dormant" and boss.hp==boss.max_hp and absf(run.checkpoint.progress-saved_progress)<1.0,"恢复到场地入口，Boss 满血沉睡")
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
