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

func reset() -> void:
	feedback="跟随"
	clock=0
	pulse=0
	confirmation=0
	cached_move=Vector2.ZERO
	side=1

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
	clock=REPLAN
	var me:Vector2=run.b.position
	var human:Vector2=run.a.position
	var spacing:=56.0
	if human.x+56>run.EDGE-run.Motion.RADIUS:
		side=-1;spacing=32
	else:side=1
	var target:=human+Vector2(side*spacing,0)
	# 预测真人的短期前进，让并肩奔跑的队友不会每次落后才启动。
	if human_move.y>0:target.y+=human_move.limit_length().y*run.WALK_SPEED*HORIZON
	var gate:Dictionary=run.charge_gate
	if gate.get("active",false) and not gate.open and gate.receiver.y-minf(human.y,me.y)<620:
		var plates:bool=gate.get("kind","")=="sync_plates"
		var human_left:bool=human.x<=0
		var zone:Rect2=gate.right if human_left else gate.left
		target=Vector2(zone.get_center().x,gate.receiver.y+(46.0 if plates else 0.0))
		feedback="站到另一侧踏板" if plates else "配合连接供能"
	else:feedback="跟随" if human_move!=Vector2.ZERO else "等待你前进"
	target.x=clampf(target.x,-run.EDGE+run.Motion.RADIUS,run.EDGE-run.Motion.RADIUS)
	if me.distance_to(target)<30:clock=0
	var desired:=axis(target-me)
	var candidates:Array[Vector2]=[desired,Vector2(desired.x,0),Vector2(0,desired.y),Vector2.ZERO,Vector2(-1,1),Vector2(1,1),Vector2.LEFT,Vector2.RIGHT]
	var best:=Vector2.ZERO
	var best_score:=INF
	var best_jump:=false
	var near_hazards:Array=[]
	var near_events:Array=[]
	for i in range(run.kinds.size()):
		var rect:Rect2=run.obstacles[i]
		if rect.end.y>=me.y-150 and rect.position.y<=me.y+500:near_hazards.append(i)
	for event in run.journey_events:
		if event.y>=me.y-900 and event.y<=me.y+700:near_events.append(event)
	for direction:Vector2 in candidates:
		# 没有推进意图时不主动超越真人；门前允许走到相邻操作位。
		if direction.y>0 and desired.y==0:continue
		for jump in [false,true]:
			if jump and (run.heights[1]>0 or run.vertical_speed[1]!=0):continue
			var cost:=path_cost(run,me,human,direction,human_move,jump,near_hazards,near_events,target)
			if is_inf(cost):continue
			var future:Vector2=project(me,direction,run.WALK_SPEED*HORIZON,target)
			var score:float=future.distance_squared_to(target)+cost+(120.0 if jump else 0.0)
			if direction!=desired:score+=80
			if human_jump and jump:score-=140
			if score<best_score:best_score=score;best=direction;best_jump=jump
	cached_move=best
	if is_inf(best_score):feedback="前方危险，等待安全时机"
	elif best!=desired:feedback="正在避险"
	return {"move":best,"jump":best_jump}

static func axis(error:Vector2)->Vector2:
	return Vector2(signf(error.x) if absf(error.x)>3 else 0.0,1.0 if error.y>2 else 0.0)

func path_cost(run,me:Vector2,human:Vector2,direction:Vector2,human_move:Vector2,jump:bool,hazards:Array,events:Array,target:Vector2)->float:
	if jump and not run.has_ground_support(me+direction.limit_length()*run.WALK_SPEED*0.6,run.elapsed+0.6):return INF
	var previous:=me
	var cost:=0.0
	var previous_height:float=run.foot_height(1)
	for sample in range(1,4):
		var time:float=HORIZON*sample/3.0
		var point:Vector2=project(me,direction,run.WALK_SPEED*time,target)
		if absf(point.x)>run.EDGE-run.Motion.RADIUS:return INF
		var other:Vector2=human+human_move.limit_length()*run.WALK_SPEED*time
		# 自己和队友的预期相对运动受同一条绳约束，超长时选择停步等候。
		if point.distance_to(other)>run.LINK_LIMIT-1:cost+=6000
		var height:float=run.foot_height(1)
		if jump:height=run.floor_heights[1]+maxf(0,run.JUMP_SPEED*time-run.GRAVITY*time*time*0.5)
		elif run.heights[1]>0:height=run.floor_heights[1]+maxf(0,run.heights[1]+run.vertical_speed[1]*time-run.GRAVITY*time*time*0.5)
		if height<=run.floor_heights[1]+0.01 and not run.has_ground_support(point,run.elapsed+time):return INF
		if not jump and run.heights[1]==0 and not run.ground_sweep_supported(previous,point,run.elapsed+time):return INF
		for i:int in hazards:
			var kind:String=run.kinds[i]
			if kind in run.Terrain.KINDS or kind in ["road_gap","collapse"]:continue
			var spec:Dictionary=run.hazard_sample(i,run.elapsed+time)
			if not spec.active:continue
			if run.swept_body_hits(previous,point,previous_height,height,spec.rect.grow(run.Motion.RADIUS),spec.bottom,spec.top):return INF
		for event:Dictionary in events:
			var spec:Dictionary=run.event_sample(event,run.elapsed+time)
			if spec.phase not in ["active","falling","fallen"]:continue
			if run.swept_body_hits(previous,point,previous_height,height,spec.rect.grow(run.Motion.RADIUS+3),spec.bottom,spec.top):return INF
			if event.kind in ["boar","tree","cart","swing"] and run.segment_hits(other,point,spec.rect.grow(3)) and spec.bottom<=run.ROPE_HEIGHT:return INF
		previous=point
		previous_height=height
	return cost

func project(point:Vector2,direction:Vector2,distance:float,target:Vector2)->Vector2:
	var result:=point+direction.limit_length()*distance
	if direction.x>0 and target.x>point.x:result.x=minf(result.x,target.x)
	elif direction.x<0 and target.x<point.x:result.x=maxf(result.x,target.x)
	if direction.y>0 and target.y>point.y:result.y=minf(result.y,target.y)
	return result
