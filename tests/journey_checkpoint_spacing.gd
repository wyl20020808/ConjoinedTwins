extends SceneTree
# 连续旅程补充存档：区域入口之外，在安全地面上按间距顺延保存，失败后回到离死亡点更近的位置。
# 每个存档都复核：贴地有支撑、不压机关或危险地形、远离未开机关、窄路、敌人出生点与近身敌人，周围没有逼近的移动危险。
const Journey=preload("res://scripts/journey_run.gd")
const Buddy=preload("res://scripts/journey_buddy.gd")
const Route=preload("res://tests/fixtures/journey_route.gd")
const FORCED_FAILURE_STEP := 800.0
var errors:Array[String]=[]
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok: errors.append(message);printerr("FAIL ",message)

func _initialize()->void:call_deferred("validate")

func drive(run,ai)->void:
	var human:Dictionary=Route.input(run)
	var weapon:Dictionary=run.combat.weapons[0]
	if weapon.is_empty() and run.a.position.y<180:human.move=Vector2.DOWN
	run.set_combat_input(not weapon.is_empty() and not run.Combat.select_target(run,0,weapon.target).is_empty())
	var choice:Dictionary=ai.think(run,1.0/60,human.move,human.jump)
	run.step(1.0/60,human.move,choice.move,human.jump,choice.jump)

func validate()->void:
	guards()
	var deaths:Array=[]
	var mid:=0
	# 实战：测试驾驶与玩家一样失败后从存档继续；战斗清空：模拟打倒每群敌人后前进，每 40 米再强制失败一次。
	# 同一存档连续失败 3 次视为测试驾驶无法通过该段，结束本轮。
	for cleared in [false,true]:
		for chapter in range(3):
			var r:Dictionary=await campaign(chapter,cleared)
			mid+=r.mid;deaths.append_array(r.deaths)
	var setback:=average(deaths,"setback");var zone_setback:=average(deaths,"zone_setback")
	print("CHECKPOINT SPACING TOTAL ",JSON.stringify({"mid":mid,"deaths":deaths.size(),"average_setback":setback,"zone_only_setback":zone_setback}))
	check(mid>=6,"区域内产生补充存档 %d"%mid)
	check(deaths.size()>=12,"失败恢复样本 %d"%deaths.size())
	check(setback<zone_setback*0.6,"平均回退 %.0f 明显短于仅区域入口存档 %.0f"%[setback,zone_setback])
	print("JOURNEY CHECKPOINT SPACING checks=%d failures=%d"%[checks,errors.size()])
	quit(0 if errors.is_empty() else 1)

func average(items:Array,key:String)->float:
	if items.is_empty(): return INF
	return items.reduce(func(s,d):return s+d[key],0.0)/items.size()

func campaign(chapter:int,cleared:bool)->Dictionary:
	var run=Journey.new();run.level_index=chapter;run.retry();run.state="running"
	if cleared:
		for event in run.journey_events:
			if event.kind=="monster": event.hp=0
	var ai=Buddy.new()
	var zone_length:float=run.finish_distance()/6.0
	var limit:float=zone_length*2.0
	var saved:Array[float]=[]
	var mid:Array=[]
	var deaths:Array=[]
	var last:=-INF
	var zone_entry:=-INF
	var region:=-1
	var repeats:={}
	var forced:=FORCED_FAILURE_STEP
	var frames:=0
	var furthest:=-INF
	var stalled:=0
	while frames<40000 and run.progress()<limit:
		drive(run,ai);frames+=1
		if run.progress()>furthest+1: furthest=run.progress();stalled=0
		else: stalled+=1
		if stalled>=1800: print("CHECKPOINT SPACING STALLED ",chapter," ",run.progress()," ",run.state);break
		if run.state not in ["running","failed"]: break
		if run.state=="running" and not run.checkpoint.is_empty() and run.checkpoint.progress!=last:
			last=run.checkpoint.progress;saved.append(last)
			if run.region_checkpoint!=region: region=run.region_checkpoint;zone_entry=last
			# 固定步内保存，渲染步结束时角色可能已再走一子步；检查使用快照里的真实站位。
			var p:Vector2=run.checkpoint.a;var q:Vector2=run.checkpoint.b
			check(run.checkpoint.run.heights==[0.0,0.0] and run.checkpoint.run.ground_support==[true,true],"存档时两人贴地有支撑 %.0f"%last)
			# 区域入口按原规则留 80，入口规则不满足时改用补充规则；两者都至少留出补充规则的身体余量。
			var margin:float=run.Motion.RADIUS+run.MID_CHECKPOINT_HAZARD_MARGIN
			for i in range(run.kinds.size()):
				if run.hazard_specs[i].get("front",false) or run.kinds[i].begins_with("fly_") or run.kinds[i] in ["drone","forklift"] or run.Threats.is_ball(run.kinds[i]): continue
				check(not run.obstacles[i].grow(margin).has_point(p) and not run.obstacles[i].grow(margin).has_point(q),"存档不压机关或危险地形 %.0f %s"%[last,run.kinds[i]])
			if zone_entry!=last:
				mid.append(last)
				check(last-saved[-2]>=run.MID_CHECKPOINT_SPACING-1,"补充存档间距不低于下限 %.0f"%last)
				check(run.checkpoint.run.combat.health.min()>=run.MID_CHECKPOINT_HEALTH,"补充存档血量足够 %.0f"%last)
				for gate in run.charge_gates:
					check(absf(p.y-gate.receiver.y)>=run.MID_CHECKPOINT_GATE_OPEN,"补充存档不在合作机关上 %.0f"%last)
				check(run.Encounters.narrow_at(run,minf(p.y,q.y),maxf(p.y,q.y)).is_empty(),"补充存档不在窄路 %.0f"%last)
				for event in run.journey_events:
					if event.kind!="monster": continue
					check(event.spawn.distance_to(p)>=run.MID_CHECKPOINT_SPAWN_CLEAR and event.spawn.distance_to(q)>=run.MID_CHECKPOINT_SPAWN_CLEAR,"补充存档不在敌人出生点 %.0f"%last)
		if cleared and run.state=="running" and run.progress()>=forced and not run.checkpoint.is_empty():
			forced+=FORCED_FAILURE_STEP
			run.fail_threat("强制失败采样")
		if run.state=="failed":
			var death:float=run.progress()
			var cp:Dictionary=run.checkpoint.duplicate(true)
			deaths.append({"death":death,"setback":death-cp.progress,"zone_setback":death-zone_entry,"reason":run.reason})
			repeats[cp.progress]=repeats.get(cp.progress,0)+1
			check(run.restore_checkpoint(),"失败后从最近存档恢复 %.0f"%death)
			check(run.a.position==cp.a and run.b.position==cp.b and run.state=="running","恢复到最近存档站位 %.0f"%cp.progress)
			check(run.elapsed<run.invulnerable_until,"恢复后有短暂保护")
			# 恢复瞬间的局面与保存时完全一致，补充存档的全部安全条件在此复核。
			if cp.progress in mid:
				check(run.mid_checkpoint_clear(),"补充存档恢复时远离机关、窄路与敌人 %.0f"%cp.progress)
				check(run.mid_checkpoint_hazards_clear(),"补充存档恢复时周围没有危险包络或逼近的移动危险 %.0f"%cp.progress)
			elif cp.progress in saved:
				check(run.checkpoint_ground_clear() or (run.mid_checkpoint_clear() and run.mid_checkpoint_hazards_clear()),"区域入口存档恢复时满足入口或补充规则 %.0f"%cp.progress)
			if repeats[cp.progress]>=3: break
		if frames%1000==0: print("CHECKPOINT SPACING PROGRESS ",chapter," ",frames," ",roundi(run.progress()));await process_frame
	print("CHECKPOINT SPACING ",JSON.stringify({"chapter":chapter,"cleared":cleared,"frames":frames,"progress":run.progress(),"saved":saved,"mid":mid,"deaths":deaths.map(func(d):return [roundi(d.death),roundi(d.setback),roundi(d.zone_setback)])}))
	if not run.checkpoint.is_empty(): restore(run)
	run.dispose()
	return {"mid":mid.size(),"deaths":deaths,"zone_length":zone_length}

# 重复恢复同一存档得到相同局面，联机两端按同一快照复现。
func restore(run)->void:
	run.fail_threat("补充存档恢复测试")
	check(run.restore_checkpoint(),"从补充存档恢复")
	var first:=var_to_str([run.a.position,run.b.position,run.journey_events,run.combat,run.obstacles,run.hazard_specs])
	for n in range(60): run.step(1.0/60)
	run.fail_threat("再次恢复测试");run.restore_checkpoint()
	check(var_to_str([run.a.position,run.b.position,run.journey_events,run.combat,run.obstacles,run.hazard_specs])==first,"重复恢复得到相同局面")

# 单项拒绝条件：低血量、未开机关附近、近身敌人、敌人出生点、窄路。
func guards()->void:
	var run=Journey.new();run.level_index=0;run.retry();run.state="running"
	var gate:Dictionary=run.charge_gates[0]
	place(run,gate.receiver.y-200)
	check(not run.mid_checkpoint_clear(),"未开机关前不补充存档")
	var monster:Dictionary={}
	for event in run.journey_events:
		if event.kind=="monster" and absf(event.spawn.y-gate.receiver.y)>2000: monster=event;break
	place(run,monster.origin.y-250,monster.origin.x)
	check(not run.mid_checkpoint_clear(),"近身存活敌人时不补充存档")
	monster.hp=0
	place(run,monster.spawn.y,monster.spawn.x)
	check(not run.mid_checkpoint_clear(),"已倒下敌人的出生点也不作为存档点")
	for marker in run.encounter_markers:
		if marker.has("lanes"):
			place(run,(marker.narrow_start+marker.narrow_end)/2.0)
			check(not run.mid_checkpoint_clear(),"窄路上不补充存档");break
	run.combat.health=[40,100]
	check(not run.mid_checkpoint_clear(),"低血量不补充存档")
	run.dispose()

func place(run,y:float,x:float=0.0)->void:
	run.a.position=Vector2(x-42,y);run.b.position=Vector2(x+42,y)
	run.rope.reset(run.a.position,run.b.position)
