extends SceneTree
# 第一章 Boss 实打：两名脚本玩家从 Boss 场地入口出发，只通过移动、跳跃和射击输入
# （与本地双人相同：只有 01 号开火，02 号键盘没有射击键）拾枪、躲招、绕缠柱一圈用绳缠住破甲、
# 输出树心，直到击败 Boss 并走到终点结算。不修改血量、坐标或 Boss 状态。
# 入口之前的路程由其他旅程测试覆盖；这里把两人放在场地入口前（取景式起点），之后全部走真实输入。
const Journey=preload("res://scripts/journey_run.gd")
const Boss=preload("res://scripts/journey_boss.gd")
const LIMIT := 120*360
var failures:Array=[]

func check(ok:bool,label:String)->void:
	if not ok: failures.append(label);printerr("FAIL ",label)

func toward(point:Vector2,target:Vector2)->Vector2:
	var delta:=target-point
	return Vector2(clampf(delta.x/12.0,-1,1) if absf(delta.x)>2 else 0.0,clampf(delta.y/12.0,-1,1) if absf(delta.y)>2 else 0.0)

# 远离所有锁定直线 / 落点的横向站位。
func safe_x(preferred:float,blocked:Array,clear:float)->float:
	var best:=preferred
	var best_cost:=INF
	for candidate in range(-230,231,10):
		var x:=float(candidate)
		if blocked.any(func(b):return absf(b-x)<clear):continue
		var cost:=absf(x-preferred)
		if cost<best_cost:best=x;best_cost=cost
	return best

func _initialize()->void:call_deferred("verify")

func verify()->void:
	var run=Journey.new();run.level_index=0;run.retry();run.state="running";run.clear_input=false
	for gate in run.charge_gates:gate.open=true;gate.opened_at=-10.0
	run.select_charge_gate()
	var boss:Dictionary=Boss.boss(run)
	var arena:float=boss.arena
	run.a.position=Vector2(-60,arena+40);run.b.position=Vector2(60,arena+40)
	run.distance=arena+40;run.rope.reset(run.a.position,run.b.position)
	var frames:=0
	var hits:=0
	var last_health:=[100,100]
	var staggers:=0
	var jumped_at:=-INF
	while frames<LIMIT and run.state=="running":
		var targets:=[Vector2(-60,arena+1250),Vector2(60,arena+1250)]
		var jump:=false
		# 先拾枪：01 拿左侧冲锋枪，02 拿右侧霰弹枪（02 不开火，只是带着）。
		if run.combat.weapons[0].is_empty():targets=[Vector2(-60,arena+160),Vector2(60,arena+160)]
		# 空闲、硬直或恢复时去拾取补给：01 弹药不足时拿弹药，任一人血量低时拿医疗包。
		if boss.state in ["idle","recover","stagger","roar","intro"] or boss.phase!="fight":
			var weapon:Dictionary=run.combat.weapons[0]
			for pickup in run.combat.pickups:
				if pickup.position.y<maxf(arena,run.distance-run.RETREAT_DISTANCE+20):continue
				if pickup.kind=="ammo" and not weapon.is_empty() and weapon.reserve+weapon.ammo<40 and boss.state!="stagger":
					targets=[pickup.position+Vector2(0,0),pickup.position+Vector2(110,0)];break
				if pickup.kind=="medkit" and (run.combat.health[0]<60 or run.combat.health[1]<60):
					var role:=0 if run.combat.health[0]<=run.combat.health[1] else 1
					targets[role]=pickup.position;targets[1-role]=pickup.position+Vector2(100 if role==0 else -100,0);break
		var age:float=run.elapsed-float(boss.state_at)
		var pace:float=Boss.PACE[boss.stage]
		if boss.hp>0 and boss.phase=="fight":
			match boss.state:
				"spikes":
					for role in range(2):
						var x:=safe_x(targets[role].x,boss.lanes,Boss.SPIKE_HALF+run.Motion.RADIUS+16)
						targets[role]=Vector2(x,arena+1250)
					if absf(targets[0].x-targets[1].x)<50:targets[1].x=safe_x(targets[0].x+90,boss.lanes,Boss.SPIKE_HALF+run.Motion.RADIUS+16)
				"seeds":
					# 前摇期间落点跟着人走，出手锁定后两人保持间距一起平移出圈。
					if age>=Boss.SEED_WINDUP*pace:
						var spots:Array=boss.targets
						var done:=false
						for dy in [0.0,-120.0,120.0,-220.0]:
							for dx in [0.0,-130.0,130.0,-200.0,200.0]:
								var moved:=[run.a.position+Vector2(dx,dy),run.b.position+Vector2(dx,dy)]
								if moved.any(func(p):return absf(p.x)>230.0 or p.y>arena+Boss.HOLD or p.y<arena+400):continue
								if moved.all(func(p):return spots.all(func(s):return s.distance_to(p)>Boss.SEED_RADIUS+run.Motion.RADIUS+10)):
									targets=moved;done=true;break
							if done:break
				"sweep":
					# 预测根浪 0.25 秒后是否扫到任意一人，提前起跳。
					for arm in range(Boss.sweep_arms(boss)):
						var later:float=Boss.sweep_x(run,boss,run.elapsed+0.2,arm)
						if later!=INF:
							for point in [run.a.position,run.b.position]:
								if absf(later-point.x)<Boss.SWEEP_HALF+run.Motion.RADIUS+14 and run.heights[0]==0.0 and run.heights[1]==0.0:jump=true
				"root":
					# 01 贴着缠柱外侧站定，02 先到起点再绕柱外圈转一圈。
					var pillar:Vector2=Boss.pillar_center(boss)
					targets[0]=pillar+Vector2(-28,0)
					var start:=pillar+Vector2.from_angle(PI+0.7)*55.0
					if run.a.position.distance_to(targets[0])>6.0 or (absf(boss.burn)<0.05 and run.b.position.distance_to(start)>10.0):targets[1]=start
					else:targets[1]=pillar+Vector2.from_angle((run.b.position-pillar).angle()+0.45)*55.0
					var limit:float=Boss.ROOT_WINDUP*pace+Boss.ROOT_LIMIT
					if absf(age-(limit-0.15))<0.01 and not boss.burned:jump=true
		if boss.stage==2:
			for role in range(2):targets[role].x=clampf(targets[role].x,-run.EDGE+Boss.THORN_WIDTH+30,run.EDGE-Boss.THORN_WIDTH-30)
		# Boss 倒下后走向终点。
		if boss.hp<=0:targets=[Vector2(-42,run.finish_distance()+80),Vector2(42,run.finish_distance()+80)]
		if jump:jumped_at=run.elapsed
		run.combat.fire[0]=not run.combat.weapons[0].is_empty()
		run.step(run.FIXED_STEP,toward(run.a.position,targets[0]),toward(run.b.position,targets[1]),jump,jump)
		for role in range(2):
			if run.combat.health[role]<last_health[role]:
				hits+=1
				print("HIT role=",role," -",last_health[role]-run.combat.health[role]," state=",boss.state," stage=",boss.stage," age=",snappedf(run.elapsed-float(boss.state_at),0.01)," a=",run.a.position," b=",run.b.position," h=",run.heights)
		last_health=run.combat.health.duplicate()
		if boss.state=="stagger" and run.elapsed-boss.state_at<run.FIXED_STEP*1.5:staggers+=1
		frames+=1
	var seconds:float=frames*run.FIXED_STEP
	var by_skill:={}
	for key in run.combat.hits.keys():
		if str(key).begins_with("boss:"):by_skill[str(key).split(":")[1]]=by_skill.get(str(key).split(":")[1],0)+1
	print("HITS BY SKILL ",by_skill)
	print("BOSS PLAYTHROUGH state=",run.state," reason=",run.reason," boss_hp=",boss.hp," stage=",boss.stage," seconds=",snappedf(seconds,0.1)," staggers=",staggers," hits_taken=",hits," health=",run.combat.health," kills=",run.combat.kills)
	check(boss.hp==0,"只用输入击败 Boss")
	check(run.state=="settlement","击败后走到终点结算")
	check(staggers>=2,"至少两次绕柱缠绳破甲")
	check(seconds>60.0 and seconds<300.0,"战斗时长在 1–5 分钟")
	run.dispose()
	print("BOSS PLAYTHROUGH FAILURES ",failures.size())
	quit(1 if not failures.is_empty() else 0)
