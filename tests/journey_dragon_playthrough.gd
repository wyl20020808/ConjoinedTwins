extends SceneTree
# 第二章魔龙实打：两名脚本玩家从场地入口出发，只通过移动、跳跃和射击输入
# （与本地双人相同：只有 01 号开火）拾枪、躲吐息并换边、跳冲击环、躲火雨与熔岩池、离开俯冲横带、
# 两人各站一块绞盘踏板拉锁链破甲（火球来时让开）、输出熔岩核，直到击败魔龙并走到终点结算。
# 不修改血量、坐标或 Boss 状态；入口之前的路程由其他旅程测试覆盖。
const Journey=preload("res://scripts/journey_run.gd")
const Boss=preload("res://scripts/journey_boss.gd")
const Dragon=preload("res://scripts/journey_dragon.gd")
const LIMIT := 120*420
const STAND := 1250.0
var failures:Array=[]

func check(ok:bool,label:String)->void:
	if not ok: failures.append(label);printerr("FAIL ",label)

func toward(point:Vector2,target:Vector2)->Vector2:
	var delta:=target-point
	return Vector2(clampf(delta.x/12.0,-1,1) if absf(delta.x)>2 else 0.0,clampf(delta.y/12.0,-1,1) if absf(delta.y)>2 else 0.0)

# 熔岩池里的站位挪开。
func dodge_pools(boss:Dictionary,point:Vector2)->Vector2:
	for pool in boss.pools:
		if point.distance_to(pool.position)<Dragon.POOL_RADIUS+24:
			point.y+=140.0 if point.y<boss.arena+900 else -140.0
	return point

# 冲击环 0.2 秒后到达任一人脚下就起跳。
func ring_jump(run,boss:Dictionary)->bool:
	if run.heights[0]!=0.0 or run.heights[1]!=0.0:return false
	var radii:Array=[]
	if boss.state=="tail":
		for ring in range(Dragon.tail_rings(boss)):radii.append(Dragon.tail_radius(boss,run.elapsed+0.2,ring))
	elif boss.state=="nova":radii.append(Dragon.nova_radius(boss,run.elapsed+0.2))
	for r in radii:
		if r<0.0:continue
		for point in [run.a.position,run.b.position]:
			var d:float=point.distance_to(boss.perch)
			if absf(d-r)<Dragon.TAIL_HALF+run.Motion.RADIUS+16:return true
	return false

func _initialize()->void:call_deferred("verify")

func verify()->void:
	var run=Journey.new();run.level_index=1;run.retry();run.state="running";run.clear_input=false
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
	var strafes:=0
	var side:=-1.0
	while frames<LIMIT and run.state=="running":
		var targets:=[Vector2(side*130-35,arena+STAND),Vector2(side*130+35,arena+STAND)]
		var jump:=false
		if run.combat.weapons[0].is_empty():targets=[Vector2(-60,arena+160),Vector2(60,arena+160)]
		if boss.state in ["idle","recover","stagger","roar","intro"] or boss.phase!="fight":
			var weapon:Dictionary=run.combat.weapons[0]
			for pickup in run.combat.pickups:
				if pickup.position.y<arena+Dragon.FLOOR:continue
				if pickup.kind=="ammo" and not weapon.is_empty() and weapon.reserve+weapon.ammo<40 and boss.state!="stagger":
					targets=[pickup.position,pickup.position+Vector2(110 if pickup.position.x<0 else -110,0)];break
				if pickup.kind=="medkit" and (run.combat.health[0]<60 or run.combat.health[1]<60):
					var role:=0 if run.combat.health[0]<=run.combat.health[1] else 1
					targets[role]=pickup.position;targets[1-role]=pickup.position+Vector2(100 if pickup.position.x<0 else -100,0);break
		var age:float=run.elapsed-float(boss.state_at)
		var pace:float=Dragon.PACE[boss.stage]
		if boss.hp>0 and boss.phase=="fight":
			match boss.state:
				"breath":
					# 站到当前（或下一道）扫射的另一半；第一道扫完立刻换边。
					var windup:float=Dragon.BREATH_WINDUP*pace
					var burning:float=boss.breath_side
					if Dragon.breath_sweeps(boss)==2 and age>windup+Dragon.BREATH_SWEEP+0.02:burning=-boss.breath_side
					side=-burning
					targets=[Vector2(side*200-35,arena+STAND),Vector2(side*200+35,arena+STAND)]
				"meteors":
					if age>=Dragon.METEOR_WINDUP*pace:
						var spots:Array=boss.targets
						var done:=false
						for dy in [0.0,-120.0,120.0,-220.0]:
							for dx in [0.0,-130.0,130.0,-200.0,200.0]:
								var moved:=[run.a.position+Vector2(dx,dy),run.b.position+Vector2(dx,dy)]
								if moved.any(func(p):return absf(p.x)>230.0 or p.y>arena+Dragon.HOLD or p.y<arena+400):continue
								if moved.all(func(p):return spots.all(func(s):return s.distance_to(p)>Dragon.METEOR_RADIUS+run.Motion.RADIUS+10)):
									targets=moved;done=true;break
							if done:break
					else:targets=[run.a.position,run.b.position]
				"strafe":
					# 锁定后离开横带（前后挪开），锁定前原地等它飞起来。
					targets=[run.a.position,run.b.position]
					if age>=Dragon.STRAFE_LOCK-0.9:
						var lane:float=boss.lane_y
						var away:=lane+170.0 if lane+170.0<arena+Dragon.HOLD else lane-170.0
						targets=[Vector2(run.a.position.x,away),Vector2(run.b.position.x,away)]
				"charge":
					# 两人各站一块踏板；火球飞向哪块，站在上面的人先往前让开，落地后回来。
					var p0:=Dragon.plate_center(boss,0)
					var p1:=Dragon.plate_center(boss,1)
					targets=[p0,p1]
					var spit_age:float=run.elapsed-float(boss.get("spit_at",-10.0))
					if spit_age>=0.0 and spit_age<Dragon.SPIT_FLIGHT+0.05:
						for role in range(2):
							if targets[role].distance_to(boss.spit_target)<1.0:targets[role]+=Vector2(0,110)
					if Dragon.nova_warning(run,boss):targets=[run.a.position,run.b.position]
		if boss.state in ["tail","nova"]:jump=ring_jump(run,boss)
		if boss.hp>0 and boss.state!="charge":
			for role in range(2):targets[role]=dodge_pools(boss,targets[role])
		if boss.stage==2:
			for role in range(2):targets[role].x=clampf(targets[role].x,-run.EDGE+Dragon.WALL_WIDTH+30,run.EDGE-Dragon.WALL_WIDTH-30)
		if boss.hp<=0:targets=[Vector2(-42,run.finish_distance()+80),Vector2(42,run.finish_distance()+80)]
		run.combat.fire[0]=not run.combat.weapons[0].is_empty()
		run.step(run.FIXED_STEP,toward(run.a.position,targets[0]),toward(run.b.position,targets[1]),jump,jump)
		for role in range(2):
			if run.combat.health[role]<last_health[role]:
				hits+=1
				print("HIT role=",role," -",last_health[role]-run.combat.health[role]," state=",boss.state," stage=",boss.stage," age=",snappedf(run.elapsed-float(boss.state_at),0.01)," a=",run.a.position," b=",run.b.position," h=",run.heights)
		last_health=run.combat.health.duplicate()
		if boss.state=="stagger" and run.elapsed-boss.state_at<run.FIXED_STEP*1.5:staggers+=1
		if boss.state=="strafe" and run.elapsed-boss.state_at<run.FIXED_STEP*1.5:strafes+=1
		frames+=1
	var seconds:float=frames*run.FIXED_STEP
	var by_skill:={}
	for key in run.combat.hits.keys():
		if str(key).begins_with("boss:"):by_skill[str(key).split(":")[1]]=by_skill.get(str(key).split(":")[1],0)+1
	print("HITS BY SKILL ",by_skill)
	print("DRAGON PLAYTHROUGH state=",run.state," reason=",run.reason," boss_hp=",boss.hp," stage=",boss.stage," seconds=",snappedf(seconds,0.1)," staggers=",staggers," strafes=",strafes," hits_taken=",hits," health=",run.combat.health)
	check(boss.hp==0,"只用输入击败魔龙")
	check(run.state=="settlement","击败后走到终点结算")
	check(staggers>=2,"至少两次站踏板拉锁链破甲")
	check(strafes>=1,"经历过起飞俯冲")
	check(seconds>60.0 and seconds<330.0,"战斗时长在 1–5.5 分钟")
	run.dispose()
	print("DRAGON PLAYTHROUGH FAILURES ",failures.size())
	quit(1 if not failures.is_empty() else 0)
