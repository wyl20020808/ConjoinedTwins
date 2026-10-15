extends RefCounted

# 战斗仅保存可深拷贝的数据，随旅程存档恢复。全部计时由生产固定步驱动。
const MAGAZINE := 24
const RESERVE := 72
const MAX_RESERVE := 144
const RELOAD_STEPS := 168
const FIRE_STEPS := 20
const RANGE := 400.0
const PICKUP_RADIUS := 20.0
const MOVE_SCALE := 0.85

static func fresh() -> Dictionary:
	return {"health":[100,100], "weapons":[{},{}], "pickups":[], "serial":0,
		"fire":[false,false], "reload":[false,false], "drop":[false,false],
		"invulnerable":[0.0,0.0], "hits":{}, "shots":[{},{}], "shot_serial":0,
		"kills":0, "notice":"靠近枪械自动拾取；鼠标左键开火，R 换弹，G 丢枪"}

static func clear_input(run) -> void:
	if run.combat.is_empty(): return
	for action in ["fire","reload","drop"]: run.combat[action]=[false,false]

static func add_pickup(run, kind: String, position: Vector2, weapon: Dictionary = {}) -> void:
	run.combat.serial+=1
	run.combat.pickups.append({"id":run.combat.serial,"kind":kind,"position":position,
		"weapon":weapon.duplicate(true),"blocked_role":-1,"blocked_until":0.0})

static func gun() -> Dictionary:
	return {"ammo":MAGAZINE,"reserve":RESERVE,"reload":0,"cooldown":0,"target":-1}

static func start_reload(run, role: int) -> void:
	var weapon: Dictionary=run.combat.weapons[role]
	if weapon.is_empty() or weapon.reload>0 or weapon.ammo>=MAGAZINE or weapon.reserve<=0: return
	weapon.reload=RELOAD_STEPS
	run.combat.notice="%02d 正在换弹，可继续移动和跳跃"%[role+1]

static func drop_weapon(run, role: int) -> void:
	var weapon: Dictionary=run.combat.weapons[role]
	if weapon.is_empty(): return
	var point: Vector2=run.a.position if role==0 else run.b.position
	weapon.reload=0
	weapon.target=-1
	if run.has_ground_support(point):
		add_pickup(run,"gun",point,weapon)
		var pickup: Dictionary=run.combat.pickups[-1]
		pickup.blocked_role=role
		pickup.blocked_until=run.elapsed+1.0
	run.combat.weapons[role]={}
	run.combat.notice="武器已丢下，移动速度恢复" if run.has_ground_support(point) else "武器落入缺口，移动速度恢复"

static func collect(run, previous: Array) -> void:
	for pickup in run.combat.pickups.duplicate():
		var nearest := -1
		var nearest_distance := INF
		for role in range(2):
			if run.solo_control and role==1 and pickup.kind in ["gun","ammo"]: continue
			if run.heights[role]>4 or not run.ground_support[role]: continue
			if pickup.blocked_role==role and run.elapsed<pickup.blocked_until: continue
			var weapon: Dictionary=run.combat.weapons[role]
			if pickup.kind=="gun" and not weapon.is_empty(): continue
			if pickup.kind=="ammo" and (weapon.is_empty() or weapon.reserve>=MAX_RESERVE): continue
			if pickup.kind=="medkit" and run.combat.health[role]>=100: continue
			var point: Vector2=run.a.position if role==0 else run.b.position
			var distance: float=run.Rope.segment_distance(previous[role],point,pickup.position)
			if distance<=PICKUP_RADIUS+run.Motion.RADIUS and not run.solid_sweep_clear(point,pickup.position,run.foot_height(role),0): continue
			if distance<=PICKUP_RADIUS+run.Motion.RADIUS and distance<nearest_distance:
				nearest=role
				nearest_distance=distance
		if nearest<0: continue
		match pickup.kind:
			"gun":
				run.combat.weapons[nearest]=gun() if pickup.weapon.is_empty() else pickup.weapon.duplicate(true)
				run.combat.notice="%02d 拾取冲锋枪 · 移动速度 85%%"%[nearest+1]
			"ammo":
				run.combat.weapons[nearest].reserve=mini(MAX_RESERVE,run.combat.weapons[nearest].reserve+48)
				run.combat.notice="%02d 备用弹药 +48"%[nearest+1]
			"medkit":
				run.combat.health[nearest]=mini(100,run.combat.health[nearest]+30)
				run.combat.notice="%02d 血量 +30"%[nearest+1]
		run.combat.pickups.erase(pickup)

static func enemy_position(event: Dictionary) -> Vector2:
	return Vector2(event.side*360.0,event.y) if event.kind=="stone" else event.sample.get_center()

static func enemy_height(event: Dictionary) -> float:
	return 38.0 if event.kind=="stone" else 17.0

# 线段进入实体的区间与同区间枪线高度相交才挡弹，低栏不会挡住头顶枪线。
static func box_blocks(from: Vector2, to: Vector2, from_height: float, to_height: float, rect: Rect2, top: float) -> bool:
	var enter := 0.0
	var leave := 1.0
	var delta := to-from
	for axis in range(2):
		if absf(delta[axis])<0.00001:
			if from[axis]<rect.position[axis] or from[axis]>rect.end[axis]: return false
		else:
			var first: float=(rect.position[axis]-from[axis])/delta[axis]
			var second: float=(rect.end[axis]-from[axis])/delta[axis]
			enter=maxf(enter,minf(first,second))
			leave=minf(leave,maxf(first,second))
			if enter>leave: return false
	return minf(lerpf(from_height,to_height,enter),lerpf(from_height,to_height,leave))<=top

static func visible_target(run, role: int, event: Dictionary) -> bool:
	if event.get("hp",0)<=0 or event.phase=="spent": return false
	var from: Vector2=run.a.position if role==0 else run.b.position
	var to := enemy_position(event)
	var delta := to-from
	if delta.length()>RANGE or delta.y<0 or (delta.length()>0.01 and delta.y/delta.length()<0.5): return false
	var gun_height: float=run.foot_height(role)+36.0
	var target_height := enemy_height(event)
	for i in range(run.kinds.size()):
		if run.kinds[i] in ["cargo","pillar","rail"] and box_blocks(from,to,gun_height,target_height,run.obstacles[i],run.obstacle_heights[i]): return false
	for gate in run.charge_gates:
		if not gate.open and box_blocks(from,to,gun_height,target_height,gate.door,INF): return false
	return true

static func select_target(run, role: int, current: int) -> Dictionary:
	for event in run.journey_events:
		if event.id==current and visible_target(run,role,event): return event
	var best: Dictionary={}
	var best_score := INF
	var from: Vector2=run.a.position if role==0 else run.b.position
	for event in run.journey_events:
		if not visible_target(run,role,event): continue
		var score: float=from.distance_to(enemy_position(event))+(0.0 if event.phase in ["active","warning"] else RANGE)
		if score<best_score:
			best=event
			best_score=score
	return best

static func blind_shot_end(run, from: Vector2, to: Vector2, height: float) -> Vector2:
	var blockers: Array[Rect2]=[]
	for i in range(run.kinds.size()):
		if run.kinds[i] in ["cargo","pillar","rail"] and box_blocks(from,to,height,height,run.obstacles[i],run.obstacle_heights[i]): blockers.append(run.obstacles[i])
	for gate in run.charge_gates:
		if not gate.open: blockers.append(gate.door)
	var end := to
	for rect in blockers:
		if rect.has_point(from): return from
		var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
		for n in range(4):
			var hit = Geometry2D.segment_intersects_segment(from,to,corners[n],corners[(n+1)%4])
			if hit is Vector2 and from.distance_squared_to(hit)<from.distance_squared_to(end): end=hit
	return end

static func tick(run, previous: Array) -> void:
	collect(run,previous)
	for role in range(2):
		if run.combat.drop[role]:
			drop_weapon(run,role)
			run.combat.drop[role]=false
		var weapon: Dictionary=run.combat.weapons[role]
		if weapon.is_empty():
			run.combat.reload[role]=false
			continue
		weapon.cooldown=maxi(0,weapon.cooldown-1)
		if weapon.reload>0:
			weapon.reload-=1
			if weapon.reload==0:
				var amount: int=mini(MAGAZINE-weapon.ammo,weapon.reserve)
				weapon.ammo+=amount
				weapon.reserve-=amount
		if run.combat.reload[role]: start_reload(run,role)
		run.combat.reload[role]=false
		var target := select_target(run,role,weapon.target)
		weapon.target=target.get("id",-1)
		if not run.combat.fire[role] or weapon.reload>0 or weapon.cooldown>0: continue
		if weapon.ammo==0:
			start_reload(run,role)
			continue
		weapon.ammo-=1
		weapon.cooldown=FIRE_STEPS
		var from: Vector2=run.a.position if role==0 else run.b.position
		var to: Vector2=enemy_position(target) if not target.is_empty() else from+Vector2(0,RANGE)
		if target.is_empty(): to=blind_shot_end(run,from,to,run.foot_height(role)+36.0)
		run.combat.shot_serial+=1
		run.combat.shots[role]={"id":run.combat.shot_serial,"from":from,"to":to,"height":run.foot_height(role)+36.0,"target_height":enemy_height(target) if not target.is_empty() else run.foot_height(role)+36.0,"time":run.elapsed}
		if not target.is_empty():
			target.hp=maxi(0,target.hp-10)
			target.hit_at=run.elapsed
			if target.hp==0:
				target.phase="spent"
				run.combat.kills+=1
				run.combat.notice="敌人已击退"
		if weapon.ammo==0: start_reload(run,role)

static func hit(run, role: int, event_id: String, amount: int=20) -> void:
	var key := "%s:%d"%[event_id,role]
	if run.combat.hits.has(key): return
	run.combat.hits[key]=true
	if run.elapsed<run.invulnerable_until or run.elapsed<run.combat.invulnerable[role]: return
	if run.shield:
		run.shield=false
		run.shield_uses+=1
		run.absorbed_events[event_id]=true
		run.invulnerable_until=run.elapsed+run.Levels.INVULNERABILITY
		run.combat.notice="团队护盾抵挡了攻击"
		return
	run.combat.health[role]=maxi(0,run.combat.health[role]-amount)
	run.combat.invulnerable[role]=run.elapsed+0.8
	run.combat.notice="%02d 受到攻击，血量 -%d"%[role+1,amount]
	if run.combat.health[role]==0: run.fail_threat("%02d 血量耗尽，从安全存档继续"%[role+1])
