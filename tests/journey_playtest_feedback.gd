extends SceneTree

# 2026-10-20 试玩反馈回归：滚球一次性重击不卡人、颜色门不卡死、怪物巡逻。
const Journey=preload("res://scripts/journey_run.gd")
const Buddy=preload("res://scripts/journey_buddy.gd")
var failures: Array[String]=[]
var checks := 0

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		printerr("FAIL ",message)

func isolated():
	var run=Journey.new()
	run.journey_events.clear()
	run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear()
	run.charge_gates.clear();run.select_charge_gate();run.rewards.clear()
	run.combat=run.Combat.fresh()
	run.state="running";run.clear_input=false
	return run

func _initialize() -> void:
	call_deferred("validate")

func validate() -> void:
	ball_hits_once()
	for teal_left in [true,false]:
		for swapped in [false,true]:
			color_gate_passes(teal_left,swapped)
	monsters_patrol()
	weapon_variety()
	buddy_pickups()
	pause_checkpoint()
	print("playtest feedback checks=%d failures=%d"%[checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)

# 滚球迎面撞上不再被绳索拦停：每人只扣一次重伤，球继续滚走，不持续扣血。
func ball_hits_once() -> void:
	for kind in ["stone_ball","iron_ball"]:
		var run=isolated()
		run.a.position=Vector2(-20,100);run.b.position=Vector2(20,100)
		run.rope.reset(run.a.position,run.b.position)
		var index:int=run.add_hazard(kind,Rect2(Vector2(-45,700),run.Threats.CONFIG[kind].size))
		run.hazard_specs[index].velocity=Vector2(0,-620)
		var started:=Time.get_ticks_usec()
		for n in range(240):
			run.step(run.FIXED_STEP)
			if run.state!="running":break
		var cost:=Time.get_ticks_usec()-started
		var spec:Dictionary=run.hazard_specs[index]
		var center:Vector2=run.obstacles[index].get_center()+spec.offset
		if kind=="iron_ball":
			check(run.state=="failed","%s: iron ball is lethal on contact"%kind)
		else:
			check(run.state=="running","%s: stone ball leaves the team alive"%kind)
			check(run.combat.health[0]==30 and run.combat.health[1]==30,"%s: each player takes a single 70 hit, got %s"%[kind,str(run.combat.health)])
			check(center.y<run.a.position.y-200,"%s: ball keeps rolling past the players (y=%.0f)"%[kind,center.y])
			check(not spec.blocked and not run.rope.touches(run.obstacle_ids[index]),"%s: rope never snags the ball"%kind)
		check(cost<1500000,"%s: 4 seconds of ball contact simulate quickly (%d usec)"%[kind,cost])

# 颜色门：01 走青门、02 由搭档 AI 走橙门；站错边也能换位通过，不会两人一起卡住。
func color_gate_passes(teal_left:bool,swapped:bool) -> void:
	var run=isolated()
	var layout:=FixedLayout.new(teal_left)
	run.Encounters.color_gate(run,600.0,layout)
	run.solo_control=true;run.external_companion=true
	# 未换位时 01 本来就在青门一侧；换位时两人站错边，必须交叉。
	var teal_side:=-1.0 if teal_left else 1.0
	var a_side:=-teal_side if swapped else teal_side
	run.a.position=Vector2(a_side*30,200);run.b.position=Vector2(-a_side*30,200)
	run.rope.reset(run.a.position,run.b.position)
	var buddy:=Buddy.new()
	var teal_x:=-60.0 if teal_left else 60.0
	var still:=0
	var worst:=0
	for n in range(900):
		var me:Vector2=run.a.position
		var human:=Vector2.UP*-1
		if me.y<600:
			human=Vector2(clampf((teal_x-me.x)/20.0,-1,1),1.0 if absf(teal_x-me.x)<8 or me.y<540 else 0.0)
		var choice:Dictionary=buddy.think(run,run.FIXED_STEP,human,false)
		var before:=[run.a.position,run.b.position]
		run.step(run.FIXED_STEP,human,choice.move,false,choice.jump)
		if run.state!="running":break
		if before[0].distance_to(run.a.position)<0.01 and before[1].distance_to(run.b.position)<0.01 and human!=Vector2.ZERO:still+=1
		else:still=0
		worst=maxi(worst,still)
		if run.a.position.y>700 and run.b.position.y>700:break
	var label:="teal_left=%s swapped=%s"%[teal_left,swapped]
	check(run.state=="running","%s: still running"%label)
	check(run.a.position.y>640 and run.b.position.y>640,"%s: both pass the colour gate (a=%s b=%s)"%[label,run.a.position,run.b.position])
	check(worst<60,"%s: nobody frozen for a second (%d steps)"%[label,worst])

# 远处未警觉的怪物在出生点附近巡逻，不再原地站桩，也不离出生点太远。
func monsters_patrol() -> void:
	var run=isolated()
	run.a.position=Vector2(-20,0);run.b.position=Vector2(20,0)
	run.rope.reset(run.a.position,run.b.position)
	var event:Dictionary=run.Monsters.add(run,Vector2(120,2200),"forest","")
	var start:Vector2=event.origin
	var farthest:=0.0
	var moved_steps:=0
	for n in range(600):
		run.step(run.FIXED_STEP)
		if event.velocity.length()>1:moved_steps+=1
		farthest=maxf(farthest,event.origin.distance_to(start))
	check(moved_steps>60,"far monster walks while patrolling (%d steps)"%moved_steps)
	check(farthest>20 and farthest<run.Monsters.PATROL_SPAN.length()+5,"patrol stays near spawn (%.1f)"%farthest)
	check(not event.alert,"patrol does not alert the monster")

func enemy(run,position:Vector2)->Dictionary:
	var event:Dictionary=run.Monsters.add(run,position,"forest","")
	event.hp=200;event.max_hp=200
	return event

# 三种新枪：霰弹枪近距离多颗弹丸命中，喷火器一次烧到锥形内所有敌人，榴弹溅射伤到成群敌人。
func weapon_variety() -> void:
	var run=isolated()
	run.a.position=Vector2(0,0);run.b.position=Vector2(-60,0);run.rope.reset(run.a.position,run.b.position)
	run.combat.weapons[0]=run.Combat.gun("shotgun")
	var close:=enemy(run,Vector2(0,90))
	run.set_combat_input(true);run.step(run.FIXED_STEP)
	check(close.hp<=200-45,"shotgun lands most pellets at close range (hp %d)"%close.hp)
	check(run.combat.weapons[0].ammo==5 and run.combat.shots[0].pellets.size()==7,"shotgun spends one shell for seven pellets")
	run=isolated()
	run.a.position=Vector2(0,0);run.b.position=Vector2(-60,0);run.rope.reset(run.a.position,run.b.position)
	run.combat.weapons[0]=run.Combat.gun("flamer")
	var left:=enemy(run,Vector2(-30,120));var right:=enemy(run,Vector2(30,120));var far:=enemy(run,Vector2(0,330))
	run.set_combat_input(true)
	for n in range(60):run.step(run.FIXED_STEP)
	check(left.hp<200 and right.hp<200,"flamer burns every enemy in the cone (%d,%d)"%[left.hp,right.hp])
	check(far.hp==200,"flamer has short range")
	run=isolated()
	run.a.position=Vector2(0,0);run.b.position=Vector2(-60,0);run.rope.reset(run.a.position,run.b.position)
	run.combat.weapons[0]=run.Combat.gun("launcher")
	var pack:=[enemy(run,Vector2(0,300)),enemy(run,Vector2(50,320)),enemy(run,Vector2(-200,300))]
	run.set_combat_input(true);run.step(run.FIXED_STEP)
	check(pack[0].hp==155 and pack[1].hp==155,"grenade splash hits the whole group")
	check(pack[2].hp==200,"grenade splash has a limited radius")
	run=isolated()
	run.Combat.add_pickup(run,"gun",run.a.position,{},"shotgun")
	run.step(run.FIXED_STEP)
	check(run.combat.weapons[0].get("type","")=="shotgun","gun pickup gives its own weapon type")

# 单人模式：搭档会去捡枪、吃血包，拿到枪后看见敌人自己开火。
func buddy_pickups() -> void:
	var run=isolated()
	run.solo_control=true;run.external_companion=true
	run.a.position=Vector2(-30,0);run.b.position=Vector2(30,0);run.rope.reset(run.a.position,run.b.position)
	run.Combat.add_pickup(run,"gun",Vector2(80,120),{},"flamer")
	run.combat.health[1]=50
	run.Combat.add_pickup(run,"medkit",Vector2(60,220))
	var buddy:=Buddy.new()
	for n in range(360):
		var choice:Dictionary=buddy.think(run,run.FIXED_STEP,Vector2(0,0.3),false)
		run.step(run.FIXED_STEP,Vector2(0,0.3),choice.move,false,choice.jump)
	check(run.combat.weapons[1].get("type","")=="flamer","buddy walks over and picks up a gun")
	check(run.combat.health[1]==80,"buddy eats the medkit when hurt (%d)"%run.combat.health[1])
	var target:=enemy(run,run.b.position+Vector2(0,120))
	for n in range(30):
		var choice:Dictionary=buddy.think(run,run.FIXED_STEP,Vector2.ZERO,false)
		run.step(run.FIXED_STEP,Vector2.ZERO,choice.move,false,choice.jump)
	check(target.hp<200,"buddy fires its own weapon at a visible enemy")

# 暂停菜单「回到存档点继续」走失败恢复路径；无存档时从本关开头重来。
func pause_checkpoint() -> void:
	var run=Journey.new()
	run.state="running";run.clear_input=false
	for n in range(240):run.step(run.FIXED_STEP,Vector2(0,1),Vector2(0,1))
	run.capture_checkpoint()
	var saved:Vector2=run.a.position
	for n in range(120):run.step(run.FIXED_STEP,Vector2(0,1),Vector2(0,1))
	run.pause()
	run.resume_from_checkpoint()
	check(run.state=="running" and run.a.position==saved,"pause menu returns to the checkpoint")

class FixedLayout:
	var teal_left:bool
	func _init(value:bool)->void:teal_left=value
	func draw(_name:String,options:Array):return teal_left if options==[true,false] else options[0]
