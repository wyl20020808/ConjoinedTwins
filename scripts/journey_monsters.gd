extends RefCounted

# 固定步追击、绕障和落点攻击。导航路径也保存在事件中，存档与联机完整复现。
const WINDUP := 0.75
const FLIGHT := 0.5
const CYCLE := 2.8
const ATTACK_RANGE := 300.0
const NOTICE_RANGE := 900.0
const BODY_RADIUS := 16.0
const GRID := 40.0
const SPEEDS := {"briar":210.0,"raider":240.0,"sentinel":170.0,"archer":185.0,"dasher":260.0,"wolf":270.0}
const NAMES := {"briar":"树皮小怪", "raider":"村庄掠袭者", "sentinel":"矿道石卫", "archer":"林地弓手", "dasher":"破阵冲锋者", "wolf":"灰鬃狼"}
const PROFILES := {
	"archer":{"windup":0.65,"active":1.15,"cycle":2.1,"range":740.0,"damage":34,"speed":720.0},
	"dasher":{"windup":0.65,"active":0.65,"cycle":2.8,"range":420.0,"damage":45,"speed":680.0},
	"wolf":{"windup":0.45,"active":0.45,"cycle":1.8,"range":230.0,"damage":28,"speed":430.0}}
const MELEE := {"windup":WINDUP,"active":FLIGHT,"cycle":CYCLE,"range":ATTACK_RANGE,"damage":32,"speed":0.0}

static func profile(event:Dictionary)->Dictionary:
	return PROFILES.get(event.archetype,MELEE)

static func safe_spawn(run, point: Vector2) -> bool:
	if absf(point.x)>run.EDGE-50 or not run.has_ground_support(point): return false
	for gate in run.charge_gates:
		if absf(point.y-gate.receiver.y)<800: return false
	for rect in run.obstacles:
		if rect.grow(48).has_point(point): return false
	for event in run.journey_events:
		if event.kind!="monster" and event.rect.grow(55).has_point(point): return false
	return true

static func safe_supply(run,point:Vector2)->bool:
	# 拾取物按玩家脚底检查；不能套用怪物出生区的 48 单位留白，
	# 否则窄通道虽然可走，弹药仍会全部被拒绝生成。
	if absf(point.x)>run.EDGE-run.Motion.RADIUS or not run.ground_sweep_supported(point,point,run.elapsed):return false
	for gate in run.charge_gates:
		if absf(point.y-gate.receiver.y)<800:return false
	# 地图仍在构造时不建立运行期索引；重试完成后由第一步按最终布局建表。
	for i in range(run.obstacles.size()):
		if run.kinds[i] in ["cargo","pillar","rail","sweeper"] and run.obstacles[i].grow(run.Motion.RADIUS).has_point(point):return false
	return true

static func populate(run) -> void:
	var pack := 0
	for base in range(900,int(run.finish_distance())-1200,900):
		var points: Array[Vector2]=[]
		for member in range(4):
			var found := false
			for offset in [0,100,-100,200]:
				for x in ([-250,-120,120,250] if member%2==0 else [250,120,-120,-250]):
					var point := Vector2(x,base+member*100+offset)
					if points.any(func(p):return p.distance_to(point)<90) or not safe_spawn(run,point): continue
					var variant:String=["archer","dasher","wolf",""][(pack+member)%4]
					add(run,point,run.theme_at(point.y),variant)
					points.append(point);found=true;break
				if found: break
		if points.is_empty(): continue
		pack+=1
		# 每两群附近补给一次，避开实体、缺口与门；不凭空补满玩家弹药。
		if pack%2==0:
			var supply_y:float=base+260
			var center:=0.0
			for marker in run.encounter_markers:
				if marker.y+110<supply_y:continue
				center=-marker.blocked*245;break
			for offset in [0,-60,60,-120,120]:
				var point:=Vector2(center-28,supply_y+offset)
				if safe_supply(run,point):
					run.Combat.add_pickup(run,"ammo",point)
					# 密集战斗后的有限恢复点，两侧角色都必须实际走近拾取。
					for x in [center-28,center+28]:
						var recovery:=Vector2(x,point.y+35)
						if safe_supply(run,recovery):run.Combat.add_pickup(run,"medkit",recovery)
					break

static func add(run, position: Vector2, theme: String, variant:String="") -> Dictionary:
	var archetype := variant if not variant.is_empty() else ("briar" if theme in ["forest","broken","edge","meadow","river","ridge"] else ("sentinel" if theme in ["mine","ruins","facility"] else "raider"))
	var hp: int={"briar":30,"raider":40,"sentinel":50,"archer":40,"dasher":60,"wolf":40}[archetype]
	var rect := Rect2(position-Vector2(28,28),Vector2(56,56))
	var event := {"id":run.event_serial,"kind":"monster","archetype":archetype,"origin":position,
		"y":position.y,"side":signf(position.x),"rect":rect,"sample":rect,"previous":rect,
		"bottom":0.0,"top":18.0,"trigger":-1.0,"phase":"ready","locked_x":position.x,
		"landing":position,"hp":hp,"max_hp":hp,"attack_seq":0,"combined":false,"obstacle":-1,
		"spawn":position,"alert":false,"velocity":Vector2.ZERO,"stride":0.0,
		"launch":position,"attack_direction":Vector2(0,-1),"attack_blocked":false,"ground_height":0.0,
		"route":PackedVector2Array(),"repath_at":run.elapsed+float(run.event_serial%17)*run.FIXED_STEP,"facing":Vector2(0,-1)}
	run.event_serial+=1
	event.ground_height=run.surface_at(position,run.elapsed).height
	run.journey_events.append(event)
	return event

static func sample(event: Dictionary, time: float) -> Dictionary:
	var data:=profile(event)
	var age: float=time-event.trigger
	var phase := "ready"
	var bottom := 0.0
	if event.trigger>=0:
		phase="warning" if age<data.windup else ("active" if age<data.windup+data.active else "recovery")
	var center:Vector2=event.landing
	var size:=Vector2(56,56)
	var height:=18.0
	if event.archetype=="archer":
		center=event.launch+event.attack_direction*maxf(0,age-data.windup)*data.speed
		bottom=event.get("launch_height",0.0)+24.0;size=Vector2(12,12);height=8.0
	elif event.archetype in ["dasher","wolf"]:
		center=event.origin;bottom=event.get("ground_height",0.0);height=42.0 if event.archetype=="dasher" else 26.0
	elif phase=="active": bottom=event.get("ground_height",0.0)+maxf(0,70-(age-WINDUP)*180)
	if event.get("attack_blocked",false) and phase=="active":phase="recovery"
	return {"rect":Rect2(center-size/2,size),"phase":phase,"bottom":bottom,"top":bottom+height}

static func advance(run, event: Dictionary) -> void:
	# 只更新附近敌人；远处保持出生数据，不把全地图寻路塞进每个固定步。
	event.velocity=Vector2.ZERO
	if absf(event.y-run.distance)>NOTICE_RANGE+200: return
	var target:Vector2=run.a.position if event.id%2==0 else run.b.position
	if event.origin.distance_to(target)<NOTICE_RANGE: event.alert=true
	# 门的站位区保留合作空间，附近追兵仍会在外围行走。
	var protected:bool=run.charge_gates.any(func(g):return absf(target.y-g.receiver.y)<180)
	var data:=profile(event)
	var age:float=run.elapsed-event.trigger if event.trigger>=0 else -1.0
	if not event.alert or protected:
		target=event.spawn+Vector2(sin(run.elapsed*.8+event.id)*60,cos(run.elapsed*.8+event.id)*40)
	elif event.origin.distance_to(target)>200:
		target.x=clampf(target.x+(-90 if event.id%2==0 else 90),-run.EDGE+40,run.EDGE-40)
	if event.archetype in ["dasher","wolf"] and age>=0 and age<data.windup+data.active:
		if age>=data.windup and not event.attack_blocked:
			var destination:Vector2=event.origin+event.attack_direction*data.speed*run.FIXED_STEP
			if clear_path(run,event.origin,destination,blockers(run,event.origin,destination)):
				place(run,event,destination)
			else:event.attack_blocked=true
	elif event.archetype!="archer" or age<0 or age>=data.windup+data.active:
		move(run,event,target)
	if event.trigger>=0 and age>=data.cycle: event.trigger=-1.0
	if event.trigger<0 and not protected and absf(event.y-run.distance)<NOTICE_RANGE:
		var nearest := -1
		var distance:float=data.range
		for role in range(2):
			var point: Vector2=run.a.position if role==0 else run.b.position
			var d: float=point.distance_to(event.origin)
			if d<distance and run.Combat.line_of_sight(run,event.origin,point,run.Combat.enemy_height(event),run.foot_height(role)+24):
				nearest=role;distance=d
		if nearest>=0:
			event.trigger=run.elapsed
			event.attack_seq+=1
			event.landing=run.a.position if nearest==0 else run.b.position
			event.locked_x=event.landing.x
			event.launch=event.origin
			event.launch_height=run.surface_at(event.origin,run.elapsed).height
			event.attack_direction=(event.landing-event.origin).normalized()
			event.facing=event.attack_direction
			event.attack_blocked=false
			for role in range(2): run.combat.hits.erase("monster:%d:%d"%[event.id,role])
	var next := sample(event,run.elapsed+run.FIXED_STEP)
	if event.archetype=="archer" and next.phase=="active":
		# 箭矢沿锁定方向飞行，实体挡住后本轮停止，不在墙后重新出现。
		if not run.Combat.line_of_sight(run,event.launch,next.rect.get_center(),next.bottom+4,next.bottom+4):
			event.attack_blocked=true;next.phase="recovery"
	if event.phase!="active" and next.phase=="active":event.sample=next.rect
	event.previous=event.sample
	event.sample=next.rect
	event.phase=next.phase
	event.bottom=next.bottom
	event.top=next.top

# 局部实体集合：低栏、树干和缺口都不能被追兵穿过，开门后可正常追入下一段。
static func blockers(run, from:Vector2, to:Vector2) -> Array[Rect2]:
	var result:Array[Rect2]=[]
	var low:float=minf(from.y,to.y)-120
	var high:float=maxf(from.y,to.y)+120
	for i in run.obstacles_in_bounds(Rect2(Vector2(-run.EDGE,low),Vector2(run.EDGE*2,high-low))):
		var rect:Rect2=run.obstacles[i]
		if rect.end.y<low or rect.position.y>high: continue
		if run.kinds[i] in ["cargo","pillar","rail","sweeper"]:
			result.append(rect.grow(BODY_RADIUS))
	for gate in run.charge_gates:
		if not gate.open: result.append(gate.door.grow(BODY_RADIUS))
	return result

static func clear_path(run, from:Vector2, to:Vector2, solids:Array[Rect2]) -> bool:
	if absf(to.x)>run.EDGE-BODY_RADIUS: return false
	for rect in solids:
		if run.segment_hits(from,to,rect): return false
	# 间距小于身体半径，覆盖整条行走路径，避免跨过细缺口。
	var steps:=maxi(1,ceili(from.distance_to(to)/12.0))
	# 网格格心的起终点相同时，只检查一次同样的五个脚底采样。
	for n in range(1 if from==to else steps+1):
		var point:=from.lerp(to,float(n)/steps)
		for offset in [Vector2.ZERO,Vector2(BODY_RADIUS,0),Vector2(-BODY_RADIUS,0),Vector2(0,BODY_RADIUS),Vector2(0,-BODY_RADIUS)]:
			if not run.has_ground_support(point+offset): return false
	return true

static func route(run, from:Vector2, target:Vector2, solids:Array[Rect2]) -> PackedVector2Array:
	if clear_path(run,from,target,solids): return PackedVector2Array([target])
	# 有障碍才创建小型确定性网格；每只怪物最多每 0.6 秒重算，禁止穿角。
	var grid:=AStarGrid2D.new()
	var low:=floori((minf(from.y,target.y)-120)/GRID)
	var high:=ceili((maxf(from.y,target.y)+120)/GRID)
	var edge:=floori((run.EDGE-BODY_RADIUS)/GRID)
	grid.region=Rect2i(-edge,low,edge*2+1,high-low+1)
	grid.cell_size=Vector2.ONE*GRID
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in range(low,high+1):
		for x in range(-edge,edge+1):
			var point:=Vector2(x,y)*GRID
			grid.set_point_solid(Vector2i(x,y),not clear_path(run,point,point,solids))
	var start:=Vector2i((from/GRID).round())
	var end:=Vector2i((target/GRID).round())
	if not grid.is_in_boundsv(start) or not grid.is_in_boundsv(end): return PackedVector2Array()
	# 起终点取附近可走且能实际连接的位置，不强行清除实体格。
	start=nearest_cell(run,grid,start,from,solids)
	end=nearest_cell(run,grid,end,target,solids)
	if start==Vector2i(99999,99999) or end==Vector2i(99999,99999): return PackedVector2Array()
	return grid.get_point_path(start,end)

static func nearest_cell(run, grid:AStarGrid2D, cell:Vector2i, point:Vector2, solids:Array[Rect2]) -> Vector2i:
	var best:=Vector2i(99999,99999)
	var distance:=INF
	for y in range(cell.y-2,cell.y+3):
		for x in range(cell.x-2,cell.x+3):
			var candidate:=Vector2i(x,y)
			if not grid.is_in_boundsv(candidate) or grid.is_point_solid(candidate): continue
			var position:=Vector2(candidate)*GRID
			if point.distance_squared_to(position)<distance and clear_path(run,point,position,solids):
				best=candidate;distance=point.distance_squared_to(position)
	return best

static func move(run, event:Dictionary, target:Vector2) -> void:
	var from:Vector2=event.origin
	if from.distance_to(target)<36: return
	var solids:=blockers(run,from,target)
	if run.elapsed>=event.repath_at:
		event.route=route(run,from,target,solids)
		event.repath_at=run.elapsed+.6
	var path:PackedVector2Array=event.route
	while not path.is_empty() and from.distance_to(path[0])<4: path.remove_at(0)
	event.route=path
	if path.is_empty(): return
	var speed:float=SPEEDS[event.archetype] if event.alert else 80.0
	var next:=from.move_toward(path[0],speed*run.FIXED_STEP)
	if not clear_path(run,from,next,solids):
		event.repath_at=minf(event.repath_at,run.elapsed+.1)
		return
	place(run,event,next)

static func place(run,event:Dictionary,next:Vector2)->void:
	var from:Vector2=event.origin
	event.origin=next
	event.y=next.y
	event.ground_height=run.surface_at(next,run.elapsed).height
	event.velocity=(next-from)/run.FIXED_STEP
	event.facing=event.velocity.normalized()
	event.stride+=from.distance_to(next)/32.0
