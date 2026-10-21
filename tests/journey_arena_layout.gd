extends SceneTree

# 2026-10-20 试玩反馈：怪物潮专区与机关段分开、小机关排列不重叠、回到主页停在模式选择。
const Journey=preload("res://scripts/journey_run.gd")
var failures: Array[String]=[]
var checks := 0

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		printerr("FAIL ",message)

func _initialize() -> void:
	call_deferred("validate")

func validate() -> void:
	for chapter in range(3):
		for seed_value in [1000,1001,1002]:
			layout(chapter,seed_value)
	await return_home()
	print("ARENA LAYOUT CHECKS ",checks," FAILURES ",failures.size())
	quit(1 if not failures.is_empty() else 0)

# 迎面滚球、飞行物与无人机在专区前触发并滚出，不算专区内的固定机关。
func moving(spec:Dictionary,kind:String="")->bool:
	return kind=="drone" or (spec.has("velocity") and not spec.get("industrial",false)) or spec.get("front",false)

func layout(chapter:int,seed_value:int)->void:
	var run=Journey.new();run.level_index=chapter;run.seed_value=seed_value;run.retry()
	var label:="chapter %d seed %d"%[chapter,seed_value]
	check(run.arenas.size()==run.Encounters.ARENA_GROUPS[chapter].size(),"%s: arena count"%label)
	for arena in run.arenas:
		# 专区内没有固定机关与缺口，只保留迎面物经过的空地。
		var inside:=0
		for i in range(run.kinds.size()):
			if moving(run.hazard_specs[i],run.kinds[i]):continue
			var rect:Rect2=run.obstacles[i]
			if rect.end.y>arena.start and rect.position.y<arena.end:inside+=1
		check(inside==0,"%s: arena %.0f has no fixed mechanisms (%d)"%[label,arena.start,inside])
		check(not run.journey_events.any(func(e):return e.kind!="monster" and e.y>arena.start and e.y<arena.end),"%s: arena has no road events"%label)
		var monsters:Array=run.journey_events.filter(func(e):return e.kind=="monster" and e.y>=arena.start and e.y<arena.end)
		check(monsters.size()>=15,"%s: arena wave has %d monsters"%[label,monsters.size()])
		check(not monsters.any(func(e):return e.y<arena.start+440),"%s: arena entrance stays clear for supplies"%label)
		check(run.combat.pickups.any(func(p):return p.kind=="ammo" and p.position.y>arena.start and p.position.y<arena.start+440),"%s: arena entrance ammo"%label)
	# 机关段每组（36 米）最多 3 只怪。
	var groups:={}
	for event in run.journey_events:
		if event.kind!="monster" or run.arenas.any(func(a):return event.y>=a.start and event.y<a.end):continue
		var group:=int(event.y/720)
		groups[group]=groups.get(group,0)+1
	check(groups.values().all(func(v):return v<=3),"%s: mechanism stretches keep packs small %s"%[label,groups.values()])
	# 小机关不与其它固定机关或路面事件重叠。
	var overlaps:=0
	for i in range(run.kinds.size()):
		if not run.hazard_specs[i].get("small",false):continue
		for j in range(run.kinds.size()):
			if i==j or moving(run.hazard_specs[j],run.kinds[j]) or run.kinds[j] in ["road_gap","collapse"]:continue
			if run.obstacles[i].intersects(run.obstacles[j]):overlaps+=1
		for event in run.journey_events:
			if event.kind!="monster" and run.obstacles[i].intersects(event.rect):overlaps+=1
	check(overlaps==0,"%s: small hazards never overlap other mechanisms (%d)"%[label,overlaps])
	run.dispose()

# 暂停菜单「回到主页」重新生成旅程后停在开始页，模式与难度按钮可见，不会直接开局。
func return_home() -> void:
	var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.run.state="running";game.run.pause()
	game.return_home();game.update_journey_ui()
	check(game.run.state=="start","return home stops on the start page (%s)"%game.run.state)
	check(not game.mode_buttons.is_empty() and game.mode_buttons.all(func(b):return b.visible),"return home shows play mode choices")
	check(game.difficulty_buttons.any(func(b):return b.visible),"return home shows difficulty choices")
	check(game.run.elapsed==0 and game.run.progress()==0,"return home does not start the new journey")
	game.run.combat_trial=false;game.update_journey_ui()
	game.training_button.pressed.emit();game.update_journey_ui()
	check(game.run.combat_trial and game.run.state=="start","training switch also waits on the start page")
	for player in game.sfx.players:player.stop()
	await create_timer(.15).timeout
	game.queue_free();await process_frame
	await create_timer(.2).timeout
