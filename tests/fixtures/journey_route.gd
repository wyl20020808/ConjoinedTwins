extends RefCounted
# 只给真人角色产生离散键盘输入。测试不会改位置、机关状态、速度、生命或碰撞。
static func input(run)->Dictionary:
	var y:float=minf(run.a.position.y,run.b.position.y)
	var center:=0.0
	var target_y:=y+600
	var half:=28.0
	for marker in run.encounter_markers:
		if marker.y+110<y or marker.y>y+800:continue
		if marker.has("lanes"):
			center=marker.lanes[0];half=0;break
		if marker.kind in ["stone","cart","boar"]:
			var event:Dictionary={}
			for e in run.journey_events:
				if e.y==marker.y:event=e;break
			# 敌人消失后，新组合中的断路/石块仍存在，不能把整段当作空路。
			if event.get("phase","")=="spent" and not marker.get("formation",false):continue
		center=-marker.blocked*(270 if marker.kind=="swing" else 245)
		if marker.kind in ["stone","cart"] and y>marker.y-450:
			for event in run.journey_events:
				if event.y==marker.y and event.phase!="spent":target_y=y
		break
	for i in range(run.kinds.size()):
		if run.kinds[i]!="drawbridge":continue
		var rect:Rect2=run.obstacles[i]
		if y>=rect.position.y-350 and y<=rect.end.y+40:center=0
	if run.charge_gate.active and not run.charge_gate.open and run.charge_gate.receiver.y-y<700:
		var gate:Dictionary=run.charge_gate;center=0
		half=45 if gate.get("kind","")=="sync_plates" else 65
		target_y=gate.receiver.y+(46 if gate.get("kind","")=="sync_plates" else 0)
	var target:=Vector2(center-half,target_y)
	var narrow:Dictionary=run.Encounters.narrow_at(run,y,maxf(run.a.position.y,run.b.position.y))
	if not narrow.is_empty():target.x=narrow.lanes[0]
	var axis:=Vector2(signf(target.x-run.a.position.x) if absf(target.x-run.a.position.x)>1.2 else 0,1 if target.y-run.a.position.y>1.2 else 0)
	if absf(target.x-run.a.position.x)>8:axis.y=0
	# 密集换侧段先等搭档并肩通过，避免领跑者在绳长另一端先踏入下一处断口。
	if axis.y>0 and run.a.position.y>run.b.position.y+(80 if not narrow.is_empty() and narrow.lanes.size()==1 else 12):axis.y=0
	# 新敌人的明确预警用普通跳跃输入应对，不修改生命、位置或敌人状态。
	var jump:=false
	for event in run.journey_events:
		if event.kind!="monster" or event.get("hp",0)<=0 or event.phase not in ["warning","active"]:continue
		var data:Dictionary=run.Monsters.profile(event)
		var age:float=run.elapsed-event.trigger
		var origin:Vector2=event.launch if event.archetype=="archer" else event.origin
		var delta:Vector2=run.a.position-origin
		var impact:float=data.windup-age+.28
		if event.archetype in ["archer","dasher","wolf"]:
			if absf(delta.cross(event.attack_direction))>65 or delta.dot(event.attack_direction)<-40:continue
			impact=maxf(0,data.windup-age)+maxf(0,delta.dot(event.attack_direction)-42)/data.speed
			if event.archetype=="archer":impact=data.windup-age+maxf(0,delta.dot(event.attack_direction)-20)/data.speed
		elif run.a.position.distance_to(event.landing)>75:continue
		if impact>.25 and impact<.38:jump=true
	return {"move":axis,"jump":jump}
