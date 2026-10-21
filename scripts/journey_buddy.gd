extends RefCounted

# 只产生普通方向和跳跃输入。没有瞬移、无敌、额外速度或故意漏跳。
const REPLAN := 0.08
const HORIZON := 0.38
var feedback := "跟随"
var clock := 0.0
var pulse := 0.0
var confirmation := 0.0
var cached_move := Vector2.ZERO
var side := 1.0
var narrow_route:Dictionary={}
var narrow_leading:=false

func reset() -> void:
	feedback="跟随"
	clock=0
	pulse=0
	confirmation=0
	cached_move=Vector2.ZERO
	side=1
	narrow_route={}
	narrow_leading=false

func think(run,delta:float,human_move:Vector2=Vector2.ZERO,human_jump:bool=false) -> Dictionary:
	if run.state=="rescue":
		pulse+=delta
		feedback="拉住你了" if run.rescue.get("role",-1)==0 else "正在攀爬"
		return {"move":Vector2.ZERO,"jump":fmod(pulse,0.12)<0.06}
	if run.state=="settlement":
		confirmation+=delta
		return {"move":Vector2.ZERO,"jump":fmod(confirmation,1.2)>0.8}
	if run.state!="running":return {"move":Vector2.ZERO,"jump":false}
	confirmation=0
	clock-=delta
	if clock>0 and not human_jump:return {"move":cached_move,"jump":false}
	# 跑速提升后保持原来的空间预判距离，并更快响应真人换向。
	# 否则搭档会提前跑出近一条绳长，在密集换侧时被拉进下一处缺口。
	var pace:float=160.0/run.WALK_SPEED
	clock=REPLAN*pace
	var me:Vector2=run.b.position
	var human:Vector2=run.a.position
	var spacing:=56.0
	if human.x+56>run.EDGE-run.Motion.RADIUS:
		side=-1;spacing=32
	else:side=1
	var target:=human+Vector2(side*spacing,0)
	# 预测真人的短期前进，让并肩奔跑的队友不会每次落后才启动。
	var human_speed:float=run.WALK_SPEED*(run.Combat.MOVE_SCALE if not run.combat.weapons[0].is_empty() else 1.0)
	if human_move.y!=0:target.y+=human_move.limit_length().y*human_speed*HORIZON*pace
	var gate:Dictionary=run.charge_gate
	if human_move.y>=0 and gate.get("active",false) and not gate.open and gate.receiver.y-minf(human.y,me.y)<620:
		if gate.get("kind","")=="relay":
			# 离门前踏板更近的一方守板；搭档守板时真人过门，否则搭档过门去门后踏板。
			var near:Vector2=gate.near.get_center();var far:Vector2=gate.far.get_center()
			if human.distance_to(near)<=me.distance_to(near):
				target=far if gate.get("ajar",false) or me.y>gate.door.end.y else Vector2(far.x,gate.door.position.y-30)
				feedback="穿过闸门，踩住门后踏板"
			else:
				target=near
				feedback="我守住门前踏板，你先过"
		else:
			var plates:bool=gate.get("kind","")=="sync_plates"
			var human_left:bool=human.x<=0
			var zone:Rect2=gate.right if human_left else gate.left
			target=Vector2(zone.get_center().x,gate.receiver.y+(46.0 if plates else 0.0))
			feedback="站到另一侧踏板" if plates else "配合连接供能"
	else:
		feedback="跟随" if human_move!=Vector2.ZERO else "等待你前进"
		# 没有合作机关时，顺路去捡枪、吃血包、补弹药；只选绳长够得着、不用回头的拾取物。
		var pickup:=wanted_pickup(run,me,human)
		if not pickup.is_empty():
			target=pickup.position
			feedback={"gun":"去捡"+run.Combat.WEAPONS[pickup.get("weapon_type","smg")].name,"medkit":"去吃血包","ammo":"补充弹药"}[pickup.kind]
	# 专属颜色门：前方 12 米内有门时，搭档（02）对准自己的橙门通过。
	for index in run.indexed_kinds(["color_gate"]):
		if int(run.hazard_specs[index].get("role",-1))!=1:continue
		var door:Rect2=run.obstacles[index]
		# 提前 18 米开始对准门洞中线；未对准前停在门前横移，对准后直线穿过。
		if door.position.y-me.y<360 and door.end.y>me.y-20:
			var center:float=door.get_center().x
			var aligned:bool=absf(me.x-center)<door.size.x*0.5-run.Motion.RADIUS-4
			target=Vector2(center,maxf(target.y,door.end.y+40) if aligned else minf(maxf(me.y,target.y),door.position.y-run.Motion.RADIUS-6))
			feedback="走橙色门"
	if not narrow_route.is_empty() and (minf(me.y,human.y)>narrow_route.narrow_end+65 or maxf(me.y,human.y)<narrow_route.narrow_start-320):narrow_route={}
	if narrow_route.is_empty():
		narrow_route=run.Encounters.narrow_at(run,minf(me.y,human.y),maxf(me.y,human.y))
		# 已经在前方的搭档保持领队，不在窄路入口掉头穿过玩家身体。
		narrow_leading=me.y>human.y+12
	var narrow:Dictionary=narrow_route
	if not narrow.is_empty():
		var lane:float=narrow.lanes[0]
		for x:float in narrow.lanes:
			if absf(x-human.x)<absf(lane-human.x):lane=x
		var follow_lane:float=lane
		for x:float in narrow.lanes:
			if x>lane and x-lane<run.LINK_LIMIT-24:follow_lane=x;break
		target=Vector2(follow_lane,human.y+((56.0 if narrow_leading else -56.0) if follow_lane==lane else 0.0))
		if human_move.y!=0:target.y+=human_move.y*human_speed*HORIZON*pace
		feedback="前后通过窄路" if follow_lane==lane else "沿相邻窄路配合"
	else:target=dodge_target(run,me,human,target)
	target.x=clampf(target.x,-run.EDGE+run.Motion.RADIUS,run.EDGE-run.Motion.RADIUS)
	if me.distance_to(target)<30:clock=0
	var desired:=axis(target-me)
	# 仅在真人后撤时跟随后撤，避免向前绕过断口后又退回危险边缘。
	if human_move.y>=0 and (narrow.is_empty() or target.y>=human.y-20):desired.y=maxf(0,desired.y)
	var candidates:Array[Vector2]=[desired,Vector2(desired.x,0),Vector2(0,desired.y),Vector2.ZERO,Vector2(-1,1),Vector2(1,1),Vector2.LEFT,Vector2.RIGHT]
	var best:=Vector2.ZERO
	var best_score:=INF
	var best_jump:=false
	var near_hazards:Array=[]
	var near_events:Array=[]
	var attack_jump:=false
	for i in range(run.kinds.size()):
		var rect:Rect2=run.obstacles[i]
		if run.hazard_specs[i].get("front",false) or run.kinds[i]=="drone":rect=run.hazard_sample(i,run.elapsed).rect
		if rect.end.y>=me.y-150 and rect.position.y<=me.y+500:
			var samples:Array=[]
			for n in range(4):
				var offset:float=HORIZON*pace*n/3.0
				var spec:Dictionary=run.hazard_sample(i,run.elapsed+offset)
				if run.hazard_specs[i].get("front",false):spec.rect.position+=run.hazard_specs[i].velocity*offset
				samples.append(spec)
			near_hazards.append({"index":i,"samples":samples})
	for event in run.journey_events:
		if event.has("hp") and event.hp<=0:continue
		if event.y>=me.y-900 and event.y<=me.y+700:
			attack_jump=attack_jump or jump_for_attack(run,event,me)
			var samples:Array=[]
			for n in range(4):samples.append(predict_event(run,event,HORIZON*pace*n/3.0))
			near_events.append({"event":event,"samples":samples})
	for direction:Vector2 in candidates:
		# 没有推进意图时不主动超越真人；门前允许走到相邻操作位。
		if direction.y>0 and desired.y==0:continue
		for jump in [false,true]:
			if jump and (run.heights[1]>0 or run.vertical_speed[1]!=0):continue
			var cost:=path_cost(run,me,human,direction,human_move,jump,near_hazards,near_events,target)
			if is_inf(cost):continue
			var future:Vector2=project(me,direction,run.WALK_SPEED*HORIZON*pace,target)
			var score:float=future.distance_squared_to(target)+cost+(120.0 if jump else 0.0)
			if direction!=desired:score+=80
			if human_jump and jump:score-=140
			if attack_jump and jump:score-=1800
			if score<best_score:best_score=score;best=direction;best_jump=jump
	cached_move=best
	if is_inf(best_score):feedback="前方危险，等待安全时机"
	elif best!=desired:feedback="正在避险"
	return {"move":best,"jump":best_jump}

static func wanted_pickup(run,me:Vector2,human:Vector2)->Dictionary:
	var weapon:Dictionary=run.combat.weapons[1]
	var health:int=run.combat.health[1]
	var best:Dictionary={}
	var best_distance:=INF
	for pickup:Dictionary in run.combat.pickups:
		var point:Vector2=pickup.position
		if point.y<me.y-10 or point.y>me.y+260 or point.distance_to(human)>run.LINK_LIMIT-30:continue
		if pickup.blocked_role==1 and run.elapsed<pickup.blocked_until:continue
		match pickup.kind:
			"gun":if not weapon.is_empty():continue
			"ammo":if weapon.is_empty() or weapon.reserve*2>=int(run.Combat.spec(weapon).max_reserve):continue
			# 血包让给更需要的人：自己少于 100 且不比真人健康太多。
			"medkit":if health>=100 or health>run.combat.health[0]+10:continue
		var distance:=me.distance_to(point)
		if distance<best_distance:best=pickup;best_distance=distance
	return best

static func axis(error:Vector2)->Vector2:
	return Vector2(signf(error.x) if absf(error.x)>3 else 0.0,signf(error.y) if absf(error.y)>2 else 0.0)

func path_cost(run,me:Vector2,human:Vector2,direction:Vector2,human_move:Vector2,jump:bool,hazards:Array,events:Array,target:Vector2)->float:
	if jump and not run.has_ground_support(me+direction.limit_length()*run.WALK_SPEED*0.6,run.elapsed+0.6):return INF
	var previous:=me
	var cost:=0.0
	var previous_height:float=run.foot_height(1)
	for sample in range(1,4):
		var time:float=HORIZON*(160.0/run.WALK_SPEED)*sample/3.0
		var point:Vector2=project(me,direction,run.WALK_SPEED*time,target)
		if absf(point.x)>run.EDGE-run.Motion.RADIUS:return INF
		var human_speed:float=run.WALK_SPEED*(run.Combat.MOVE_SCALE if not run.combat.weapons[0].is_empty() else 1.0)
		var other:Vector2=human+human_move.limit_length()*human_speed*time
		# 自己和队友的预期相对运动受同一条绳约束，超长时选择停步等候。
		if point.distance_to(other)>run.LINK_LIMIT-1:cost+=6000
		var height:float=run.foot_height(1)
		if jump:height=run.floor_heights[1]+maxf(0,run.JUMP_SPEED*time-run.GRAVITY*time*time*0.5)
		elif run.heights[1]>0:height=run.floor_heights[1]+maxf(0,run.heights[1]+run.vertical_speed[1]*time-run.GRAVITY*time*time*0.5)
		if height<=run.floor_heights[1]+0.01 and not run.has_ground_support(point,run.elapsed+time):return INF
		if not jump and run.heights[1]==0 and not run.ground_sweep_supported(previous,point,run.elapsed+time):return INF
		for forecast:Dictionary in hazards:
			var i:int=forecast.index
			var kind:String=run.kinds[i]
			if kind in run.Terrain.KINDS or kind in ["road_gap","collapse"]:continue
			# 自己颜色的门洞是通路，不是危险体；只有对方的门会挡住搭档。
			if kind=="color_gate" and int(run.hazard_specs[i].get("role",-1))==1:continue
			var spec:Dictionary=forecast.samples[sample]
			if not spec.active:continue
			var old:Rect2=forecast.samples[sample-1].rect
			if run.swept_body_hits(previous,point-(spec.rect.position-old.position),previous_height,height,old.grow(run.Motion.RADIUS),spec.bottom,spec.top):return INF
		for forecast:Dictionary in events:
			var event:Dictionary=forecast.event
			var spec:Dictionary=forecast.samples[sample]
			if spec.phase not in ["active","falling","fallen"]:continue
			var old:Rect2=forecast.samples[sample-1].rect
			if run.swept_body_hits(previous,point-(spec.rect.position-old.position),previous_height,height,old.grow(run.Motion.RADIUS+3),spec.bottom,spec.top):return INF
			if event.kind in ["tree","cart","swing"] and run.segment_hits(other,point,spec.rect.grow(3)) and spec.bottom<=run.ROPE_HEIGHT:return INF
		previous=point
		previous_height=height
	return cost

# 冲锋的物理位置只由固定步推进；这里仅预测已锁定方向，不改敌人状态。
# 一次思考生成四个采样点，所有候选输入复用，避免重复计算攻击轨迹。
static func predict_event(run,event:Dictionary,offset:float)->Dictionary:
	var spec:Dictionary=run.event_sample(event,run.elapsed+offset)
	if event.kind=="monster" and run.Monsters.charges(event) and event.trigger>=0 and not event.attack_blocked:
		var data:Dictionary=run.Monsters.profile(event)
		var start:float=maxf(run.elapsed,event.trigger+data.windup)
		var finish:float=minf(run.elapsed+offset,event.trigger+data.windup+data.active)
		spec.rect.position+=event.attack_direction*maxf(0,finish-start)*data.speed
	return spec

static func jump_for_attack(run,event:Dictionary,point:Vector2)->bool:
	if event.kind!="monster" or event.phase not in ["warning","active"]:return false
	# 冲锋者的身体高于跳跃最高点，必须横向绕开。
	if event.archetype=="dasher":return false
	var data:Dictionary=run.Monsters.profile(event)
	var age:float=run.elapsed-event.trigger
	var impact:float=data.windup-age+.28
	if run.Monsters.ranged(event) or run.Monsters.charges(event):
		var origin:Vector2=event.launch if run.Monsters.ranged(event) else event.origin
		var delta:Vector2=point-origin
		if absf(delta.cross(event.attack_direction))>70 or delta.dot(event.attack_direction)<-40:return false
		impact=maxf(0,data.windup-age)+maxf(0,delta.dot(event.attack_direction)-42)/data.speed
		if run.Monsters.ranged(event):impact=data.windup-age+maxf(0,delta.dot(event.attack_direction)-20)/data.speed
	elif point.distance_to(event.landing)>80:return false
	return impact>.25 and impact<.40

static func dodge_target(run,me:Vector2,human:Vector2,target:Vector2)->Vector2:
	for event in run.journey_events:
		if event.kind!="monster" or event.get("hp",0)<=0 or not run.Monsters.charges(event) or event.phase not in ["warning","active"] or event.attack_blocked:continue
		var data:Dictionary=run.Monsters.profile(event)
		var direction:Vector2=event.attack_direction
		var delta:Vector2=me-event.origin
		var ahead:float=delta.dot(direction)
		var across:Vector2=Vector2(-direction.y,direction.x)
		var lane:float=delta.dot(across)
		var clearance:float=28+run.Motion.RADIUS+15
		var impact:float=maxf(0,event.trigger+data.windup-run.elapsed)+maxf(0,ahead-42)/data.speed
		if ahead< -42 or absf(lane)>clearance or impact>.65:continue
		var best:Vector2=target
		var score:=INF
		for sign_side in [-1.0,1.0]:
			var candidate:Vector2=me+across*(sign_side*clearance-lane)
			if absf(candidate.x)>run.EDGE-run.Motion.RADIUS or candidate.distance_to(human)>run.LINK_LIMIT-2:continue
			if not run.ground_sweep_supported(me,candidate,run.elapsed+.25):continue
			var distance:float=me.distance_squared_to(candidate)+candidate.distance_squared_to(target)*.2
			if distance<score:score=distance;best=candidate
		return best
	return target

func project(point:Vector2,direction:Vector2,distance:float,target:Vector2)->Vector2:
	var result:=point+direction.limit_length()*distance
	if direction.x>0 and target.x>point.x:result.x=minf(result.x,target.x)
	elif direction.x<0 and target.x<point.x:result.x=maxf(result.x,target.x)
	if direction.y>0 and target.y>point.y:result.y=minf(result.y,target.y)
	elif direction.y<0 and target.y<point.y:result.y=maxf(result.y,target.y)
	return result
