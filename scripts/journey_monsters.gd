extends RefCounted

# 固定步中的轻量远程怪物。只保存数据，不增加寻路、刚体或逐怪物节点更新。
const WINDUP := 1.25
const FLIGHT := 0.5
const CYCLE := 4.0
const ATTACK_RANGE := 300.0
const NAMES := {"briar":"树皮小怪", "raider":"村庄掠袭者", "sentinel":"矿道石卫"}

static func safe_spawn(run, point: Vector2) -> bool:
	if absf(point.x)>run.EDGE-50 or not run.has_ground_support(point): return false
	for gate in run.charge_gates:
		if absf(point.y-gate.receiver.y)<800: return false
	for rect in run.obstacles:
		if rect.grow(48).has_point(point): return false
	for event in run.journey_events:
		if event.kind!="monster" and event.rect.grow(55).has_point(point): return false
	return true

static func populate(run) -> void:
	var pack := 0
	for base in range(900,int(run.finish_distance())-1200,900):
		var points: Array[Vector2]=[]
		for member in range(2):
			var found := false
			for offset in [0,100,-100,200]:
				for x in ([-120,120,-210,210] if member==0 else [120,-120,210,-210]):
					var point := Vector2(x,base+member*100+offset)
					if points.any(func(p):return p.distance_to(point)<90) or not safe_spawn(run,point): continue
					add(run,point,run.theme_at(point.y))
					points.append(point);found=true;break
				if found: break
		if points.is_empty(): continue
		pack+=1
		# 每两群附近补给一次，避开实体、缺口与门；不凭空补满玩家弹药。
		if pack%2==0:
			for x in [-42,42,-120,120]:
				var point:=Vector2(x,base+260)
				if safe_spawn(run,point):
					run.Combat.add_pickup(run,"ammo",point)
					break

static func add(run, position: Vector2, theme: String) -> Dictionary:
	var archetype := "briar" if theme in ["forest","broken","edge","meadow","river","ridge"] else ("sentinel" if theme in ["mine","ruins","facility"] else "raider")
	var hp: int={"briar":30,"raider":40,"sentinel":50}[archetype]
	var rect := Rect2(position-Vector2(28,28),Vector2(56,56))
	var event := {"id":run.event_serial,"kind":"monster","archetype":archetype,"origin":position,
		"y":position.y,"side":signf(position.x),"rect":rect,"sample":rect,"previous":rect,
		"bottom":0.0,"top":18.0,"trigger":-1.0,"phase":"ready","locked_x":position.x,
		"landing":position,"hp":hp,"max_hp":hp,"attack_seq":0,"combined":false,"obstacle":-1}
	run.event_serial+=1
	run.journey_events.append(event)
	return event

static func sample(event: Dictionary, time: float) -> Dictionary:
	var age: float=time-event.trigger
	var phase := "ready"
	var bottom := 0.0
	if event.trigger>=0:
		phase="warning" if age<WINDUP else ("active" if age<WINDUP+FLIGHT else "recovery")
		if phase=="active": bottom=maxf(0,70-(age-WINDUP)*180)
	return {"rect":Rect2(event.landing-Vector2(28,28),Vector2(56,56)),"phase":phase,"bottom":bottom,"top":bottom+18}

static func advance(run, event: Dictionary) -> void:
	if event.trigger>=0 and run.elapsed-event.trigger>=CYCLE: event.trigger=-1.0
	if event.trigger<0 and absf(event.y-run.distance)<600:
		var nearest := -1
		var distance := ATTACK_RANGE
		for role in range(2):
			var point: Vector2=run.a.position if role==0 else run.b.position
			var d: float=point.distance_to(event.origin)
			if d<distance and run.Combat.line_of_sight(run,event.origin,point,38.0,run.foot_height(role)+24):
				nearest=role;distance=d
		if nearest>=0:
			event.trigger=run.elapsed
			event.attack_seq+=1
			event.landing=run.a.position if nearest==0 else run.b.position
			event.locked_x=event.landing.x
			for role in range(2): run.combat.hits.erase("monster:%d:%d"%[event.id,role])
	var next := sample(event,run.elapsed+run.FIXED_STEP)
	event.previous=event.sample
	event.sample=next.rect
	event.phase=next.phase
	event.bottom=next.bottom
	event.top=next.top
