extends SceneTree
# 双人机关专项：接力踏板、同步跳绳杆、分侧拉绳绊桶、专属颜色门与滚球瞄准。
# 全部通过生产模拟的 step 输入驱动，不改写位置以外的状态、不关闭碰撞或伤害。
const Journey=preload("res://scripts/journey_run.gd")
const DT:=1.0/60.0
var failures:=0
var checks:=0

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",message)

# 只保留被测机关：其余危险与事件移到路外，并按真实流程打开之前的合作门。
func isolate(run,keep:Array,y:float)->void:
	run.journey_events.clear()
	for i in run.kinds.size():
		if i in keep:continue
		run.obstacles[i].position.x=run.EDGE*20
		if run.hazard_specs[i].get("front",false):run.hazard_specs[i].start_distance=INF
	for g in run.charge_gates:
		if g.receiver.y<y-200:g.open=true
	run.obstacle_bin_epoch=-INF;run.ground_gap_cache_time=-INF;run.terrain_index_epoch=-INF;run.solid_query_epoch=-INF
	run.revision+=1

func place(run,a:Vector2,b:Vector2)->void:
	run.state="running"
	run.a.position=a;run.b.position=b
	run.distance=minf(a.y,b.y)
	run.heights=[0.0,0.0];run.vertical_speed=[0.0,0.0]
	run.rope.reset(a,b)
	run.combat.health=[100,100]
	run.invulnerable_until=0.0
	run.select_charge_gate()

func toward(from:Vector2,to:Vector2)->Vector2:
	var d:=to-from
	return Vector2.ZERO if d.length()<4.0 else d.normalized()

func _initialize()->void:
	relay()
	jump_bar()
	barrel()
	color_gate()
	ball_aim()
	print("COOP_MECHANISMS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func relay()->void:
	var run=Journey.new();run.retry()
	var gate:Dictionary={}
	for g in run.charge_gates:
		if g.get("kind","")=="relay":gate=g;break
	check(not gate.is_empty(),"chapter 0 has a relay gate")
	if gate.is_empty():return
	var near:Vector2=gate.near.get_center();var far:Vector2=gate.far.get_center()
	isolate(run,[],gate.receiver.y)
	place(run,Vector2(near.x-20,gate.receiver.y-40),Vector2(near.x+20,gate.receiver.y-40))
	check(run.charge_gate.id==gate.id,"relay selected as active gate")
	# 没人守板：两人一起前进被门挡住。
	for n in range(150):run.step(DT,Vector2(0,1),Vector2(0,1))
	check(maxf(run.a.position.y,run.b.position.y)<gate.door.position.y,"closed relay door blocks both")
	check(not gate.ajar and not gate.open,"door stays shut without a plate holder")
	# 01 守门前踏板，02 过门去门后踏板。
	var opened_at:=-1
	for n in range(600):
		var ia:=toward(run.a.position,near)
		var ib:=toward(run.b.position,far if gate.ajar or gate.open else Vector2(far.x,gate.door.position.y-30))
		run.step(DT,ia,ib)
		if gate.open and opened_at<0:opened_at=n
		if gate.open:break
	check(run.b.position.y>gate.door.end.y,"02 passed the door while 01 held the near plate")
	check(gate.open,"standing on the far plate opens the relay door")
	check(run.state=="running","relay sequence keeps the run alive")
	# 开门后 01 也能通过。
	for n in range(180):run.step(DT,toward(run.a.position,far+Vector2(-30,40)),Vector2.ZERO)
	check(run.a.position.y>gate.door.end.y,"01 passes after the door opens permanently")
	run.dispose()

func first(run,kind:String)->int:
	for i in run.kinds.size():
		if run.kinds[i]==kind:return i
	return -1

func jump_bar()->void:
	var run=Journey.new();run.retry()
	var index:=first(run,"jump_bar")
	check(index>=0,"chapter 0 has a jump bar")
	if index<0:return
	var spec:Dictionary=run.hazard_specs[index]
	var line:float=run.obstacles[index].get_center().y
	isolate(run,[index],line)
	# 找下一个贴地窗口中点。
	var period:float=spec.period;var bottom:float=spec.warning+spec.active*.5
	# 情况一：两人站在杆线上不跳，贴地时被扫中。
	place(run,Vector2(-40,line),Vector2(40,line))
	var hit:=false
	for n in range(int(period/DT)+10):
		run.step(DT)
		if run.combat.health[0]<100 or run.combat.health[1]<100:hit=true;break
	check(hit,"standing on the jump bar line gets hit when it sweeps the ground")
	# 情况二：贴地前约 0.3 秒两人同时起跳（跳跃最高点对准贴地中点），安全越过。
	place(run,Vector2(-40,line),Vector2(40,line))
	var cycle:=fposmod(run.elapsed+float(spec.phase),period)
	var wait:=fposmod(bottom-cycle-0.30,period)
	for n in range(int(wait/DT)):run.step(DT)
	run.step(DT,Vector2.ZERO,Vector2.ZERO,true,true)
	for n in range(int(.9/DT)):run.step(DT)
	check(run.combat.health==[100,100],"jumping together at the right time clears the bar health=%s"%[run.combat.health])
	# 情况三：只有 01 起跳，02 被扫中。
	place(run,Vector2(-40,line),Vector2(40,line))
	cycle=fposmod(run.elapsed+float(spec.phase),period)
	wait=fposmod(bottom-cycle-0.30,period)
	for n in range(int(wait/DT)):run.step(DT)
	run.step(DT,Vector2.ZERO,Vector2.ZERO,true,false)
	for n in range(int(.9/DT)):run.step(DT)
	check(run.combat.health[0]==100 and run.combat.health[1]<100,"only the jumper is safe health=%s"%[run.combat.health])
	run.dispose()

func barrel()->void:
	var run=Journey.new();run.retry()
	var index:=first(run,"barrel")
	check(index>=0,"chapter 0 has rolling barrels")
	if index<0:return
	var spec:Dictionary=run.hazard_specs[index]
	var center:Vector2=run.obstacles[index].get_center()
	isolate(run,[index],center.y)
	# 情况一：分站木桶中线两侧、把绳拉紧 → 绊倒。
	var y:float=spec.start_distance+10
	place(run,Vector2(-70,y),Vector2(70,y))
	var coins:int=run.coins
	for n in range(int(5.0/DT)):
		run.step(DT,Vector2(-1,0) if run.a.position.x>-72 else Vector2.ZERO,Vector2(1,0) if run.b.position.x<72 else Vector2.ZERO)
		if spec.get("tripped",false) or run.state!="running":break
	check(spec.get("tripped",false),"taut rope across the lane trips the barrel lane=%.0f"%[center.x+spec.offset.x])
	check(run.coins==coins+run.Threats.BARREL_TRIP_COINS,"tripping a barrel awards coins")
	check(run.combat.health==[100,100],"tripped barrel does not hurt anyone health=%s"%[run.combat.health])
	# 情况二：两人同侧并肩、绳子松弛 → 木桶撞人。
	run.retry()
	spec=run.hazard_specs[index]
	isolate(run,[index],center.y)
	place(run,Vector2(-15,y),Vector2(15,y))
	var hurt:=false
	for n in range(int(6.0/DT)):
		run.step(DT)
		if run.combat.health[0]<100 or run.combat.health[1]<100:hurt=true;break
	check(not spec.get("tripped",false) and hurt,"slack rope side by side gets hit by the barrel")
	run.dispose()

func color_gate()->void:
	var run=Journey.new();run.retry()
	var index:=first(run,"color_gate")
	check(index>=0,"chapter 0 has a color gate")
	if index<0:return
	var role:int=run.hazard_specs[index].role
	var door:Rect2=run.obstacles[index]
	var keep:=[]
	for i in run.kinds.size():
		if absf(run.obstacles[i].position.y-door.position.y)<1.0 and run.kinds[i] in ["cargo","color_gate"]:keep.append(i)
	isolate(run,keep,door.position.y)
	var x:float=door.get_center().x
	# 对应角色可穿过自己的门洞，另一人被挡在门前。
	var mine:=Vector2(x,door.position.y-40)
	var other:=Vector2(x+(30 if x<0 else -30),door.position.y-40)
	place(run,mine if role==0 else other,other if role==0 else mine)
	for n in range(int(1.2/DT)):
		run.step(DT,Vector2(0,1) if role==0 else Vector2.ZERO,Vector2(0,1) if role==1 else Vector2.ZERO)
	var passer:Vector2=run.a.position if role==0 else run.b.position
	check(passer.y>door.end.y,"%02d passes its own colored gate"%[role+1])
	run.retry()
	isolate(run,keep,door.position.y)
	place(run,mine if role==1 else other,other if role==1 else mine)
	for n in range(int(1.2/DT)):
		run.step(DT,Vector2(0,1) if role==1 else Vector2.ZERO,Vector2(0,1) if role==0 else Vector2.ZERO)
	var blocked:Vector2=run.a.position if role==1 else run.b.position
	check(blocked.y<door.position.y,"the other player is blocked by a gate of the wrong color")
	run.dispose()

func ball_aim()->void:
	var run=Journey.new();run.retry()
	var aimed:=0;var near:=0
	for i in run.kinds.size():
		if not run.Threats.is_ball(run.kinds[i]) or not run.hazard_specs[i].get("aim_players",false):continue
		var spec:Dictionary=run.hazard_specs[i]
		var y:float=run.obstacles[i].position.y-900
		# 两人站在与原定生成侧相反的一侧，瞄准后车道应转到他们这边。
		var side:float=-signf(run.obstacles[i].get_center().x)
		isolate(run,[i],run.obstacles[i].position.y)
		place(run,Vector2(side*200-20,y),Vector2(side*200+20,y))
		for n in range(int(4.0/DT)):
			run.step(DT)
			if spec.get("aimed",false):break
		if spec.get("aimed",false):
			aimed+=1
			var lane:float=run.obstacles[i].get_center().x+spec.offset.x
			if absf(lane-side*200)<60:near+=1
		run.retry()
		if aimed>=6:break
	check(aimed>=6,"rolling balls aim when they enter the warning window aimed=%d"%aimed)
	check(near==aimed,"aimed lane follows the players' side near=%d aimed=%d"%[near,aimed])
	run.dispose()
