extends SceneTree
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.run.journey_events.clear();game.run.kinds.clear();game.run.obstacles.clear();game.run.obstacle_ids.clear();game.run.obstacle_heights.clear();game.run.hazard_specs.clear()
	game.reset_journey_views();game.built_chapter=-1;game.sync_world();game.run.state="running";game.run.elapsed=1.0
	var indices:Array=[]
	for kind in ["fly_low","fly_body","rocket","stone_ball","iron_ball","drone"]:
		var size:Vector2=Vector2(64,40) if kind=="drone" else game.run.Threats.CONFIG[kind].size
		var index:int=game.run.add_hazard(kind,Rect2(Vector2(100,400),size));indices.append(index)
		if kind=="drone":game.run.hazard_specs[index].trigger=0.0;game.run.hazard_specs[index].warning=.7
	game.sync_static_hazards()
	for index:int in indices:
		check(game.static_views.has(index),"moving threat has visible production node "+game.run.kinds[index])
		var view:Node3D=game.static_views[index]
		var sample:Dictionary=game.run.hazard_sample(index,game.run.elapsed)
		check(view.position.is_equal_approx(Vector3(sample.rect.get_center().x/20,0,-sample.rect.get_center().y/20)),"visual follows actual moving collision "+game.run.kinds[index])
	var lift:int=game.run.add_hazard("lift",Rect2(-150,700,130,160));game.run.hazard_specs[lift].amplitude=28.0;game.run.hazard_specs[lift].period=3.2
	game.sync_static_hazards()
	var lift_view:Node3D=game.static_views[lift]
	var support:Node3D=lift_view.get_child(1)
	var old_support:=support.global_position
	game.run.elapsed+=.8;game.sync_static_hazards()
	check(support.global_position.is_equal_approx(old_support),"lift support stays on ground")
	check(is_equal_approx(lift_view.get_node("TerrainDeck").position.y,game.run.terrain_sample(lift,game.run.elapsed,game.run.obstacles[lift].get_center()).height/20-.12),"lift deck follows collision height")
	for variant in ["archer","dasher","wolf"]:
		var first:Node3D=game.CombatView.EnemyView.make_monster(game,game.road,variant)
		var second:Node3D=game.CombatView.EnemyView.make_monster(game,game.road,variant)
		check(first.get_node("LeftLeg").get_child(0).mesh==second.get_node("LeftLeg").get_child(0).mesh,variant+" instances share geometry")
		check(first.has_node("LeftArm") and first.has_node("RightArm"),variant+" animated attack limbs exist")
	for path in ["natural_oak_7","natural_oak_17","natural_birch"]:
		for suffix in ["","_lod"]:
			var parts:Array=game.landscape.load_parts("res://assets/landscape/%s%s.glb"%[path,suffix])
			check(parts.size()==1 and parts[0].mesh.get_surface_count()==2,"tree stays in two material batches "+path+suffix)
			check(parts[0].mesh.surface_get_material(1)==game.landscape.palette.NaturalLeaf,"tree uses actual leaf material "+path+suffix)
	for player in game.sfx.players:player.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("WORLD_VIEW CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
