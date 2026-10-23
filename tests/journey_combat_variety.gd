extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
const Buddy=preload("res://scripts/journey_buddy.gd")
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func isolated():
	var run=Journey.new()
	run.journey_events.clear();run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear()
	run.charge_gates.clear();run.select_charge_gate();run.rewards.clear();run.combat=run.Combat.fresh()
	run.state="running";run.clear_input=false
	return run
func ticks(run,count:int)->void:
	for n in range(count):run.step(run.FIXED_STEP,Vector2.ZERO,Vector2.ZERO)
func _initialize()->void:call_deferred("verify")
func verify()->void:
	for entry in [["briar",32],["archer",34],["dasher",45],["wolf",28]]:
		check(Journey.Monsters.profile({"archetype":entry[0]}).damage==entry[1],entry[0]+" increased damage contract")
	for chapter in range(3):
		var run=Journey.new();run.level_index=chapter;run.retry()
		# 全部种类每章都可能出现（不按关卡限制），各至少 4 只。
		for variant in run.Monsters.ROSTER:
			check(run.journey_events.filter(func(e):return e.get("archetype","")==variant).size()>=4,"chapter %d contains %s"%[chapter,variant])
		for kind in ["drone","fly_low","fly_body","rocket","stone_ball","iron_ball","shuttle","piston"]:
			check(run.kinds.count(kind)>=2,"chapter %d has repeated %s"%[chapter,kind])
		var early_ammo:int=run.combat.pickups.filter(func(p):return p.kind=="ammo" and p.position.y>900 and p.position.y<10000 and absf(p.position.x)>180).size()
		check(early_ammo>=3,"chapter %d supplies survive narrow safe corridors"%chapter)
		run.dispose()
	for variant in ["archer","dasher","wolf"]:
		var run=isolated()
		var event:Dictionary=run.Monsters.add(run,Vector2(-42,200),"forest",variant)
		ticks(run,1)
		var data:Dictionary=run.Monsters.profile(event)
		check(event.phase=="warning" and run.combat.health==[100,100],variant+" harmless windup")
		var frozen:Dictionary=event.duplicate(true);run.pause();ticks(run,120)
		check(event==frozen,variant+" pause freezes attack")
		run.pause();ticks(run,int((data.windup+data.active)*120)+2)
		check(run.combat.health==[100-data.damage,100],variant+" live attack deals configured damage exactly once")
		check(run.combat.hits.size()<=2,variant+" bounded hit keys")
		run.capture_checkpoint();var saved:Dictionary=event.duplicate(true)
		ticks(run,30);run.fail_threat("test restore");run.restore_checkpoint()
		check(run.journey_events[0]==saved,variant+" exact saved trajectory")
		run.dispose()
		# 预警后插入实体，验证箭和冲锋中途确实被挡；不是只测试索敌。
		run=isolated();event=run.Monsters.add(run,Vector2(-42,200),"forest",variant);ticks(run,1)
		run.add_hazard("cargo",Rect2(-100,100,120,35));ticks(run,int((data.windup+data.active)*120)+2)
		check(run.combat.health==[100,100] and event.attack_blocked,variant+" cover stops in-flight attack")
		if variant!="archer":check(event.origin.y>=135+run.Monsters.BODY_RADIUS,variant+" cannot dash through wall")
		run.dispose()
		# 预警后的真实横向输入可躲避，攻击方向不随玩家转弯。
		run=isolated();event=run.Monsters.add(run,Vector2(-42,200),"forest",variant);ticks(run,1)
		var direction:Vector2=event.attack_direction
		for n in range(int((data.windup+data.active)*120)):
			run.step(run.FIXED_STEP,Vector2.RIGHT,Vector2.RIGHT)
		check(event.attack_direction==direction and run.combat.health==[100,100],variant+" locked attack can be dodged")
		run.dispose()
		# 搭档用正常方向/跳跃输入规避新攻击，不能靠血量注入或碰撞豁免。
		run=isolated();run.solo_control=false
		event=run.Monsters.add(run,Vector2(42,200),"forest",variant)
		var buddy=Buddy.new()
		for n in range(int((data.windup+data.active)*120)+10):
			var input:Dictionary=buddy.think(run,run.FIXED_STEP)
			run.step(run.FIXED_STEP,Vector2.ZERO,input.move,false,input.jump)
		check(run.combat.health[1]==100 and event.attack_seq==1,variant+" companion survives actual attack using legal inputs")
		run.dispose()
	var left=isolated();var right=isolated()
	for run in [left,right]:
		for entry in [["archer",Vector2(-200,600)],["dasher",Vector2(100,400)],["wolf",Vector2(-42,200)]]:
			run.Monsters.add(run,entry[1],"forest",entry[0])
	var same:=true
	for n in range(480):
		for run in [left,right]:run.step(run.FIXED_STEP,Vector2.RIGHT if n<60 else Vector2.DOWN,Vector2.RIGHT if n<60 else Vector2.DOWN)
		same=same and left.sync_hash()==right.sync_hash()
	check(same,"480 mixed attack steps deterministic")
	left.dispose();right.dispose()
	print("VARIETY CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
