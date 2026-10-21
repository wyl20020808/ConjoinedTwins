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
# 双枪：手上一把，背上最多一把。换枪 0.3 秒内不能开火，收起的枪中断换弹。
const SWAP_STEPS := 36
# 四种枪。步数按 120 Hz 固定步计；冲锋枪数值与旧版完全一致。
# 霰弹枪：7 颗弹丸扇形散开，按弹丸实际覆盖敌人身体的角宽计数，近距离一发 63。
# 喷火器：每 0.05 秒对锥形范围内所有可见敌人各烧 3 点，射程短、持续压制。
# 榴弹发射器：命中点 95 单位半径内所有敌人各受 45，适合打成群的怪。
const WEAPONS := {
	"smg":{"name":"冲锋枪","magazine":24,"reserve":72,"max_reserve":144,"reload":168,"fire":20,"damage":10,"range":400.0,"ammo_pickup":48},
	"shotgun":{"name":"霰弹枪","magazine":6,"reserve":18,"max_reserve":36,"reload":192,"fire":66,"damage":9,"pellets":7,"spread":0.32,"range":280.0,"ammo_pickup":12},
	"flamer":{"name":"喷火器","magazine":100,"reserve":100,"max_reserve":200,"reload":216,"fire":6,"damage":3,"cone":0.6,"range":190.0,"ammo_pickup":60},
	"launcher":{"name":"榴弹发射器","magazine":4,"reserve":8,"max_reserve":16,"reload":240,"fire":96,"damage":45,"splash":95.0,"range":480.0,"ammo_pickup":4}}
const ENEMY_RADIUS := 28.0
# 接触伤害按机关类型区分；持续接触每秒最多结算一次。
const CONTACT_INTERVAL := 1.0
const HAZARD_DAMAGE := {
	"steam":15, "scanner":15, "spikes":20, "active_spikes":25,
	"rail":15, "pillar":20, "sweeper":25, "shuttle":35, "piston":45,
	"drone":35, "fly_low":25, "fly_body":35, "fly_tall":45, "rocket":40,
	"stone_ball":70, "iron_ball":100, "forklift":65, "press":80, "hammer":80,
	"tree":60, "cart":50, "swing":65, "boar":20, "stone":20, "monster":15
}

static func fresh() -> Dictionary:
	return {"health":[100,100], "weapons":[{},{}], "backups":[{},{}], "pickups":[], "serial":0,
		"fire":[false,false], "reload":[false,false], "drop":[false,false], "swap":[false,false],
		"invulnerable":[0.0,0.0], "hits":{}, "shots":[{},{}], "shot_serial":0,
		"kills":0, "notice":"靠近枪械自动拾取，最多带两把；鼠标左键开火，R 换弹，Q 换枪，G 丢枪"}

# 旧存档与测试夹具没有背枪槽，按需补齐；两端在同一固定步补，联机一致。
static func ensure_slots(run) -> void:
	if not run.combat.has("backups"): run.combat.backups=[{},{}]
	if not run.combat.has("swap"): run.combat.swap=[false,false]

static func backup(run, role: int) -> Dictionary:
	ensure_slots(run)
	return run.combat.backups[role]

static func clear_input(run) -> void:
	if run.combat.is_empty(): return
	for action in ["fire","reload","drop","swap"]: run.combat[action]=[false,false]

static func add_pickup(run, kind: String, position: Vector2, weapon: Dictionary = {}, weapon_type: String = "smg") -> void:
	run.combat.serial+=1
	run.combat.pickups.append({"id":run.combat.serial,"kind":kind,"position":position,
		"weapon":weapon.duplicate(true),"weapon_type":weapon.get("type",weapon_type),"blocked_role":-1,"blocked_until":0.0})

static func gun(type: String="smg") -> Dictionary:
	var data: Dictionary=WEAPONS[type]
	return {"type":type,"ammo":data.magazine,"reserve":data.reserve,"reload":0,"cooldown":0,"target":-1}

# 旧存档与测试夹具里的枪没有 type 字段，一律视为冲锋枪。
static func spec(weapon: Dictionary) -> Dictionary:
	return WEAPONS[weapon.get("type","smg")]

static func weapon_name(weapon: Dictionary) -> String:
	return spec(weapon).name

static func start_reload(run, role: int) -> void:
	var weapon: Dictionary=run.combat.weapons[role]
	if weapon.is_empty() or weapon.reload>0 or weapon.ammo>=spec(weapon).magazine or weapon.reserve<=0: return
	weapon.reload=spec(weapon).reload
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
	# 背上还有枪时自动拿到手上。
	var spare: Dictionary=backup(run,role)
	if not spare.is_empty():
		spare.cooldown=SWAP_STEPS
		run.combat.weapons[role]=spare
		run.combat.backups[role]={}
		run.combat.notice="%02d 丢下武器，换上背后的%s"%[role+1,weapon_name(spare)]

# 手上与背上的枪互换；背上没有枪时不动作。
static func swap_weapon(run, role: int) -> void:
	var spare: Dictionary=backup(run,role)
	if spare.is_empty(): return
	var held: Dictionary=run.combat.weapons[role]
	if not held.is_empty():
		held.reload=0
		held.target=-1
	spare.cooldown=maxi(int(spare.get("cooldown",0)),SWAP_STEPS)
	run.combat.weapons[role]=spare
	run.combat.backups[role]=held
	run.combat.notice="%02d 换上%s"%[role+1,weapon_name(spare)]

static func collect(run, previous: Array) -> void:
	for pickup in run.combat.pickups.duplicate():
		var nearest := -1
		var nearest_distance := INF
		for role in range(2):
			if run.heights[role]>4 or not run.ground_support[role]: continue
			if pickup.blocked_role==role and run.elapsed<pickup.blocked_until: continue
			var weapon: Dictionary=run.combat.weapons[role]
			if pickup.kind=="gun" and not weapon.is_empty() and not backup(run,role).is_empty(): continue
			if pickup.kind=="ammo" and not needs_ammo(run,role): continue
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
				var picked: Dictionary=gun(pickup.get("weapon_type","smg")) if pickup.weapon.is_empty() else pickup.weapon.duplicate(true)
				if run.combat.weapons[nearest].is_empty():
					run.combat.weapons[nearest]=picked
					run.combat.notice="%02d 拾取%s · 移动速度 85%%"%[nearest+1,weapon_name(picked)]
				else:
					# 手上有枪：新枪背到背上，按换枪键取用。
					picked.reload=0
					picked.target=-1
					run.combat.backups[nearest]=picked
					run.combat.notice="%02d 拾取%s，背在背上 · Q 换枪"%[nearest+1,weapon_name(picked)]
			"ammo":
				# 弹药箱同时补满手上与背上的枪，各按自身枪种的补给量。
				var parts: Array=[]
				for held: Dictionary in [run.combat.weapons[nearest],backup(run,nearest)]:
					if held.is_empty(): continue
					var data: Dictionary=spec(held)
					var added: int=mini(data.max_reserve,held.reserve+data.ammo_pickup)-held.reserve
					held.reserve+=added
					if added>0: parts.append("%s +%d"%[data.name,added])
				run.combat.notice="%02d 备用弹药 %s"%[nearest+1," · ".join(parts)]
			"medkit":
				run.combat.health[nearest]=mini(100,run.combat.health[nearest]+30)
				run.combat.notice="%02d 血量 +30"%[nearest+1]
		run.combat.pickups.erase(pickup)

# 手上或背上任一把枪的备用弹药未满即可拾取弹药箱。
static func needs_ammo(run, role: int) -> bool:
	for held: Dictionary in [run.combat.weapons[role],backup(run,role)]:
		if not held.is_empty() and held.reserve<spec(held).max_reserve: return true
	return false

static func enemy_position(event: Dictionary) -> Vector2:
	if event.kind in ["monster","boss"]: return event.origin
	return Vector2(event.side*360.0,event.y) if event.kind=="stone" else event.sample.get_center()

static func enemy_height(event: Dictionary) -> float:
	# Boss 的瞄准点是胸口树心，约 5.5 米高。
	if event.kind=="boss": return 110.0
	if event.kind=="monster": return event.get("ground_height",0.0)+({"wolf":24.0,"root_spider":20.0,"goblin_bomber":30.0,"river_crab_knight":44.0}.get(event.archetype,38.0))
	return 38.0 if event.kind in ["stone","monster"] else 17.0

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

static func visible_target(run, role: int, event: Dictionary, reach: float = RANGE) -> bool:
	if event.get("hp",0)<=0 or event.phase=="spent": return false
	var from: Vector2=run.a.position if role==0 else run.b.position
	var to := enemy_position(event)
	var delta := to-from
	if delta.length()>reach: return false
	# 追击怪会绕到侧后方；这些敌人沿用射程和遮挡，但允许转身还击。
	if event.kind!="monster" and (delta.y<0 or (delta.length()>0.01 and delta.y/delta.length()<0.5)): return false
	var gun_height: float=run.foot_height(role)+36.0
	var target_height := enemy_height(event)
	return line_of_sight(run,from,to,gun_height,target_height)

static func line_of_sight(run, from: Vector2, to: Vector2, gun_height: float, target_height: float) -> bool:
	for i in run.obstacles_in_bounds(Rect2(from,Vector2.ZERO).expand(to).grow(.001)):
		if run.kinds[i] in ["cargo","pillar","rail"] and box_blocks(from,to,gun_height,target_height,run.obstacles[i],run.obstacle_heights[i]): return false
	for gate in run.charge_gates:
		if not gate.open and box_blocks(from,to,gun_height,target_height,gate.door,INF): return false
	return true

static func select_target(run, role: int, current: int, reach: float = RANGE) -> Dictionary:
	for event in run.journey_events:
		# 锁定 Boss 时不粘住：射程内出现其他敌人（召唤的小怪）就让给它们，否则小怪永远打不到。
		if event.id==current and visible_target(run,role,event,reach):
			if event.kind!="boss" or not run.journey_events.any(func(other): return other.kind!="boss" and visible_target(run,role,other,reach)): return event
	var best: Dictionary={}
	var best_score := INF
	var from: Vector2=run.a.position if role==0 else run.b.position
	for event in run.journey_events:
		if not visible_target(run,role,event,reach): continue
		var score: float=from.distance_to(enemy_position(event))+(0.0 if event.phase in ["active","warning"] else reach)+(reach*2.0 if event.kind=="boss" else 0.0)
		if score<best_score:
			best=event
			best_score=score
	return best

static func blind_shot_end(run, from: Vector2, to: Vector2, height: float) -> Vector2:
	var blockers: Array[Rect2]=[]
	var bounds:=Rect2(from,Vector2.ZERO).expand(to)
	for i in run.indices_for_types(["cargo","pillar","rail"]):
		if bounds.intersects(run.obstacles[i],true) and box_blocks(from,to,height,height,run.obstacles[i],run.obstacle_heights[i]): blockers.append(run.obstacles[i])
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
	ensure_slots(run)
	collect(run,previous)
	for role in range(2):
		if run.combat.drop[role]:
			drop_weapon(run,role)
			run.combat.drop[role]=false
		if run.combat.swap[role]:
			swap_weapon(run,role)
			run.combat.swap[role]=false
		var weapon: Dictionary=run.combat.weapons[role]
		if weapon.is_empty():
			run.combat.reload[role]=false
			continue
		var data: Dictionary=spec(weapon)
		weapon.cooldown=maxi(0,weapon.cooldown-1)
		if weapon.reload>0:
			weapon.reload-=1
			if weapon.reload==0:
				var amount: int=mini(data.magazine-weapon.ammo,weapon.reserve)
				weapon.ammo+=amount
				weapon.reserve-=amount
		if run.combat.reload[role]: start_reload(run,role)
		run.combat.reload[role]=false
		var target := select_target(run,role,weapon.target,data.range)
		weapon.target=target.get("id",-1)
		# 单人模式的搭档由模拟自己扣扳机：看得见敌人就开火，存档与重放结果一致。
		var firing: bool=run.combat.fire[role] or (run.solo_control and role==1 and not target.is_empty())
		if not firing or weapon.reload>0 or weapon.cooldown>0: continue
		if weapon.ammo==0:
			start_reload(run,role)
			continue
		weapon.ammo-=1
		weapon.cooldown=data.fire
		var from: Vector2=run.a.position if role==0 else run.b.position
		var height: float=run.foot_height(role)+36.0
		var aim:=Vector2(0,1)
		if not target.is_empty() and from.distance_to(enemy_position(target))>0.01: aim=from.direction_to(enemy_position(target))
		var to: Vector2=enemy_position(target) if not target.is_empty() else from+aim*data.range
		if target.is_empty(): to=blind_shot_end(run,from,to,height)
		var type: String=weapon.get("type","smg")
		run.combat.shot_serial+=1
		var shot:={"id":run.combat.shot_serial,"type":type,"from":from,"to":to,"height":height,"target_height":enemy_height(target) if not target.is_empty() else height,"time":run.elapsed,"hit":not target.is_empty()}
		match type:
			"shotgun": fire_shotgun(run,role,from,aim,data,shot)
			"flamer": fire_flamer(run,role,from,aim,data,shot)
			"launcher": fire_launcher(run,to,data,shot)
			_:
				if not target.is_empty(): damage(run,target,data.damage)
		run.combat.shots[role]=shot
		if weapon.ammo==0: start_reload(run,role)

static func damage(run, target: Dictionary, amount: int) -> void:
	if target.get("hp",0)<=0: return
	if target.kind=="boss": amount=run.Boss.incoming(target,amount)
	target.hp=maxi(0,target.hp-amount)
	target.hit_damage=(target.get("hit_damage",0) if target.get("hit_at",-1.0)==run.elapsed else 0)+amount
	target.hit_at=run.elapsed
	if target.hp==0:
		target.phase="spent"
		target.defeated_at=run.elapsed
		run.combat.kills+=1
		run.combat.notice="敌人已击退"

# 弹丸均匀铺满扇面；敌人身体按距离张成的角宽接住其中若干颗，射程后段伤害减半。
static func fire_shotgun(run, role: int, from: Vector2, aim: Vector2, data: Dictionary, shot: Dictionary) -> void:
	var count: int=data.pellets
	var ends: Array=[]
	var tally:={}
	for k in range(count):
		var direction:Vector2=aim.rotated(float(data.spread)*(float(k)/(count-1)-0.5))
		var end:Vector2=from+direction*float(data.range)
		var best_distance:float=data.range
		var best:Dictionary={}
		for event in run.journey_events:
			if not visible_target(run,role,event,data.range): continue
			var offset:=enemy_position(event)-from
			var along:=offset.dot(direction)
			if along<=0 or along>=best_distance or absf(offset.cross(direction))>event.get("radius",ENEMY_RADIUS): continue
			best_distance=along;best=event
		if not best.is_empty():
			end=from+direction*best_distance
			tally[best.id]=tally.get(best.id,0)+(data.damage if best_distance<data.range*0.6 else int(data.damage/2))
		else: end=blind_shot_end(run,from,end,shot.height)
		ends.append(end)
	for event in run.journey_events:
		if tally.has(event.id): damage(run,event,tally[event.id])
	shot.pellets=ends
	shot.hit=not tally.is_empty()

# 喷火器每次触发都对锥形范围内所有可见敌人结算，不局限于锁定目标。
static func fire_flamer(run, role: int, from: Vector2, aim: Vector2, data: Dictionary, shot: Dictionary) -> void:
	var burned:=0
	for event in run.journey_events:
		if not visible_target(run,role,event,data.range): continue
		var offset:=enemy_position(event)-from
		if offset.length()>0.01 and absf(aim.angle_to(offset))>data.cone: continue
		damage(run,event,data.damage)
		burned+=1
	shot.to=from+aim*data.range
	shot.hit=burned>0

# 榴弹在锁定点（或被实体挡住处）爆炸，半径内敌人全部受伤，不伤队友。
static func fire_launcher(run, at: Vector2, data: Dictionary, shot: Dictionary) -> void:
	var caught:=0
	for event in run.journey_events:
		if event.get("hp",0)<=0 or event.phase=="spent": continue
		if enemy_position(event).distance_to(at)<=data.splash+event.get("radius",0.0):
			damage(run,event,data.damage)
			caught+=1
	shot.splash=data.splash
	shot.hit=caught>0

static func hit(run, role: int, event_id: String, amount: int=20, repeatable: bool=false) -> void:
	var key := "%s:%d"%[event_id,role]
	if repeatable:
		if run.elapsed < float(run.combat.hits.get(key,-INF))+CONTACT_INTERVAL: return
	else:
		if run.combat.hits.has(key): return
		run.combat.hits[key]=true
	if run.elapsed<run.invulnerable_until or run.elapsed<run.combat.invulnerable[role]: return
	if repeatable: run.combat.hits[key]=run.elapsed
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
