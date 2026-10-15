extends RefCounted
# 只给真人角色产生离散键盘输入。测试不会改位置、机关状态、速度、生命或碰撞。
static func input(run)->Dictionary:
	var y:float=minf(run.a.position.y,run.b.position.y)
	var center:=0.0
	var target_y:=y+600
	var half:=28.0
	for marker in run.encounter_markers:
		if marker.y+110<y or marker.y>y+800:continue
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
	var axis:=Vector2(signf(target.x-run.a.position.x) if absf(target.x-run.a.position.x)>1.2 else 0,1 if target.y-run.a.position.y>1.2 else 0)
	if absf(target.x-run.a.position.x)>8:axis.y=0
	# 密集换侧段先等搭档并肩通过，避免领跑者在绳长另一端先踏入下一处断口。
	if axis.y>0 and run.a.position.y>run.b.position.y+12:axis.y=0
	return {"move":axis,"jump":false}
