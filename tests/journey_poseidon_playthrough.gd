extends SceneTree
# 第三章海神实打：两名脚本玩家从场地入口出发，只通过移动、跳跃和射击输入（与本地双人相同：只有 01 号开火）
# 拾枪、横向让开激流、钻进巨浪缺口、躲涌泉与水洼、跳过震环与海啸、分站水球两侧让能量绳横穿潮汐之心破甲（水弹来时侧身）、
# 输出海神之心，直到击败海神并走到终点结算。不修改血量、坐标或 Boss 状态；入口之前的路程由其他旅程测试覆盖。
const Journey=preload("res://scripts/journey_run.gd")
const Boss=preload("res://scripts/journey_boss.gd")
const Poseidon=preload("res://scripts/journey_poseidon.gd")
const LIMIT := 120*420
const STAND := 1250.0
var failures:Array=[]

func check(ok:bool,label:String)->void:
	if not ok: failures.append(label);printerr("FAIL ",label)

func toward(point:Vector2,target:Vector2)->Vector2:
	var delta:=target-point
	return Vector2(clampf(delta.x/12.0,-1,1) if absf(delta.x)>2 else 0.0,clampf(delta.y/12.0,-1,1) if absf(delta.y)>2 else 0.0)

func dodge_puddles(boss:Dictionary,point:Vector2)->Vector2:
	for puddle in boss.puddles:
		if point.distance_to(puddle.position)<Poseidon.PUDDLE_RADIUS+24:
			point.y+=140.0 if point.y<boss.arena+800 else -140.0
	return point

# 水环 0.2 秒后到达任一人脚下就起跳。
func ring_jump(run,boss:Dictionary)->bool:
	if run.heights[0]!=0.0 or run.heights[1]!=0.0:return false
	var radii:Array=[]
	var center:Vector2=Poseidon.ring_center(boss)
	if boss.state=="ring":
		for n in range(Poseidon.ring_count(boss)):radii.append(Poseidon.ring_radius(boss,run.elapsed+0.2,n))
	elif boss.state=="tsunami":
		radii.append(Poseidon.tsunami_radius(boss,run.elapsed+0.2));center=Poseidon.source(run,boss)
	for r in radii:
		if r<0.0:continue
		for point in [run.a.position,run.b.position]:
			if absf(point.distance_to(center)-r)<Poseidon.RING_HALF+run.Motion.RADIUS+16:return true
	return false

func _initialize()->void:call_deferred("verify")

func verify()->void:
	var run=Journey.new();run.level_index=2;run.retry();run.state="running";run.clear_input=false
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
	var waves:=0
	var x:=-60.0
	var dealt:={}
	var last_boss_hp:int=boss.hp
	while frames<LIMIT and run.state=="running":
		var targets:=[Vector2(x-35,arena+STAND),Vector2(x+35,arena+STAND)]
		var jump:=false
		if run.combat.weapons[0].is_empty():targets=[Vector2(-60,arena+160),Vector2(60,arena+160)]
		# 硬直是输出窗口：只有血量很低时才去捡补给，否则留在射击站位。
		var low:bool=run.combat.health[0]<40 or run.combat.health[1]<40
		if boss.state in ["idle","recover","roar","intro","summon"] or boss.phase!="fight" or (boss.state=="stagger" and low):
			var weapon:Dictionary=run.combat.weapons[0]
			for pickup in run.combat.pickups:
				if pickup.position.y<arena+Poseidon.FLOOR:continue
				if pickup.kind=="ammo" and not weapon.is_empty() and weapon.reserve+weapon.ammo<40 and boss.state!="stagger":
					targets=[pickup.position,pickup.position+Vector2(110 if pickup.position.x<0 else -110,0)];break
				if pickup.kind=="medkit" and (run.combat.health[0]<75 or run.combat.health[1]<75):
					var role:=0 if run.combat.health[0]<=run.combat.health[1] else 1
					targets[role]=pickup.position;targets[1-role]=pickup.position+Vector2(100 if pickup.position.x<0 else -100,0);break
		var age:float=run.elapsed-float(boss.state_at)
		var pace:float=Poseidon.PACE[boss.stage]
		if boss.hp>0 and boss.phase=="fight":
			match boss.state:
				"lance":
					# 出手锁定后两人一起横向让开 150：离开最近一道水柱（在两人中点高度上的横坐标）。
					targets=[run.a.position,run.b.position]
					if age>=Poseidon.LANCE_WINDUP*pace-0.05:
						var mid:Vector2=(run.a.position+run.b.position)*0.5
						var from:Vector2=boss.lance_from
						var nearest:=INF
						var line_x:=0.0
						for dir:Vector2 in boss.lances:
							var lx:float=from.x+dir.x*(mid.y-from.y)/minf(dir.y,-0.05)
							if absf(lx-mid.x)<nearest:nearest=absf(lx-mid.x);line_x=lx
						var shift:=150.0 if mid.x>=line_x else -150.0
						if absf(mid.x+shift)>run.EDGE-80.0:shift=-shift
						if not boss.has("bot_shift") or boss.bot_shift_seq!=boss.skill_seq:
							boss.bot_shift=shift;boss.bot_shift_seq=boss.skill_seq
						targets=[run.a.position+Vector2(boss.bot_shift,0),run.b.position+Vector2(boss.bot_shift,0)]
						for role in range(2):targets[role].x=clampf(targets[role].x,-run.EDGE+40,run.EDGE-40)
				"wave":
					var front:float=Poseidon.wave_y(boss,run.elapsed,0)
					var which:=0 if front==INF or (front!=-INF and front>run.a.position.y-Poseidon.WAVE_HALF-20.0) else 1
					which=mini(which,boss.gaps.size()-1)
					var g:float=boss.gaps[which]
					targets=[Vector2(g-24,run.a.position.y),Vector2(g+24,run.b.position.y)]
				"geysers":
					if age>=Poseidon.GEYSER_WINDUP*pace:
						var spots:Array=boss.targets
						var done:=false
						for dy in [0.0,-100.0,100.0,-170.0]:
							for dx in [0.0,-100.0,100.0,-160.0,160.0]:
								var moved:=[run.a.position+Vector2(dx,dy),run.b.position+Vector2(dx,dy)]
								if moved.any(func(p):return absf(p.x)>230.0 or p.y>arena+Poseidon.HOLD or p.y<arena+400):continue
								if moved.all(func(p):return spots.all(func(s):return s.distance_to(p)>Poseidon.GEYSER_RADIUS+run.Motion.RADIUS+10)):
									targets=moved;done=true;break
							if done:break
					else:targets=[run.a.position,run.b.position]
				"channel":
					# 分站水球两侧，绳子横穿球心；水弹飞向谁，谁沿绳子方向（横向）往外让一步再回来。
					if Poseidon.orb_ready(boss,run.elapsed):
						var c:=Poseidon.orb_center(boss,run.elapsed)
						targets=[Vector2(c.x-55,c.y),Vector2(c.x+55,c.y)]
						var bolt_age:float=run.elapsed-float(boss.get("bolt_at",-10.0))
						if bolt_age>=0.0 and bolt_age<Poseidon.BOLT_FLIGHT+0.05:
							for role in range(2):
								if [run.a.position,run.b.position][role].distance_to(boss.bolt_target)<Poseidon.BOLT_RADIUS+30:
									targets[role]+=Vector2(0,90)
					else:
						var c0:=Vector2(0,arena+Poseidon.ORB_Y)
						targets=[c0+Vector2(-60,0),c0+Vector2(60,0)]
					if Poseidon.tsunami_warning(run,boss):targets=[run.a.position,run.b.position]
		if boss.state in ["ring","tsunami"]:jump=ring_jump(run,boss)
		if boss.hp>0 and boss.state not in ["channel","wave"]:
			for role in range(2):targets[role]=dodge_puddles(boss,targets[role])
		# 已经站在水洼里时先横向走出来（离开水洼中心），再去目标。
		if boss.hp>0 and boss.state not in ["wave","lance"]:
			var mid:Vector2=(run.a.position+run.b.position)*0.5
			for puddle in boss.puddles:
				for point in [run.a.position,run.b.position]:
					if point.distance_to(puddle.position)<Poseidon.PUDDLE_RADIUS+run.Motion.RADIUS+6:
						var away:=Vector2(signf(mid.x-puddle.position.x+0.01)*90.0,0)
						targets=[run.a.position+away,run.b.position+away]
		# 小怪近战预警（落点亮起）时离开落点。
		for e in run.journey_events:
			if e.kind!="monster" or e.hp<=0 or e.get("phase","")!="warning" or run.Monsters.ranged(e) or run.Monsters.charges(e):continue
			var land:Vector2=e.get("landing",e.origin)
			for role in range(2):
				var point:Vector2=[run.a.position,run.b.position][role]
				if point.distance_to(land)<110.0:
					var away:Vector2=(point-land).normalized() if point.distance_to(land)>1.0 else Vector2(1,0)
					targets=[run.a.position+away*130.0,run.b.position+away*130.0]
		if boss.stage==2:
			for role in range(2):targets[role].x=clampf(targets[role].x,-run.EDGE+Poseidon.FLOOD_WIDTH+30,run.EDGE-Poseidon.FLOOD_WIDTH-30)
		if boss.hp<=0:targets=[Vector2(-42,run.finish_distance()+80),Vector2(42,run.finish_distance()+80)]
		run.combat.fire[0]=not run.combat.weapons[0].is_empty()
		run.step(run.FIXED_STEP,toward(run.a.position,targets[0]),toward(run.b.position,targets[1]),jump,jump)
		for role in range(2):
			if run.combat.health[role]<last_health[role]:
				hits+=1
				print("HIT role=",role," -",last_health[role]-run.combat.health[role]," state=",boss.state," stage=",boss.stage," age=",snappedf(run.elapsed-float(boss.state_at),0.01)," a=",run.a.position," b=",run.b.position)
		last_health=run.combat.health.duplicate()
		if boss.hp!=last_boss_hp:
			dealt[boss.state]=dealt.get(boss.state,0)+last_boss_hp-boss.hp
			last_boss_hp=boss.hp
		if boss.state=="stagger" and run.elapsed-boss.state_at<run.FIXED_STEP*1.5:staggers+=1
		if boss.state=="wave" and run.elapsed-boss.state_at<run.FIXED_STEP*1.5:waves+=1
		frames+=1
	var seconds:float=frames*run.FIXED_STEP
	var by_skill:={}
	for key in run.combat.hits.keys():
		if str(key).begins_with("boss:"):by_skill[str(key).split(":")[1]]=by_skill.get(str(key).split(":")[1],0)+1
	print("HITS BY SKILL ",by_skill)
	print("BOSS DAMAGE BY STATE ",dealt," kills=",run.combat.kills)
	print("POSEIDON PLAYTHROUGH state=",run.state," reason=",run.reason," boss_hp=",boss.hp," stage=",boss.stage," seconds=",snappedf(seconds,0.1)," staggers=",staggers," waves=",waves," hits_taken=",hits," health=",run.combat.health)
	check(boss.hp==0,"只用输入击败海神")
	check(run.state=="settlement","击败后走到终点结算")
	check(staggers>=2,"至少两次让能量绳横穿潮汐之心破甲")
	check(waves>=1,"经历过巨浪")
	check(seconds>60.0 and seconds<330.0,"战斗时长在 1–5.5 分钟")
	run.dispose()
	print("POSEIDON PLAYTHROUGH FAILURES ",failures.size())
	quit(1 if not failures.is_empty() else 0)
