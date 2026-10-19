extends SceneTree
# 验证真实区块中的布景边界、共享 PBR 网格与运动机关的同源尺寸。
const Plans=preload("res://scripts/journey_chunk_plan.gd")
var checks:=0
var failures:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	var used:={}
	for chapter in range(3):
		for number in range(-1,ceili(game.run.CHAPTERS[chapter].length/1600.0)+1):
			var plan:Array=Plans.make(number,chapter,game.run.CHAPTERS[chapter],game.run.EDGE)
			check(plan==Plans.make(number,chapter,game.run.CHAPTERS[chapter],game.run.EDGE),"相同区块的美术规划保持确定性")
			for item in plan:
				if item[0]!="landscape_batch" or not item[1].begins_with("tripo_"):continue
				used[item[1]]=true
				var parts:Array=game.landscape.load_parts("res://assets/landscape/%s.glb"%item[1])
				for transform:Transform3D in item[2]:
					for part in parts:
						var bounds:AABB=(transform*part.transform)*part.mesh.get_aabb()
						check(bounds.position.x>16 or bounds.end.x< -16,"新布景完整位于可行走道路外："+item[1])
	check(used.size()==6,"六件环境资产均进入实际三章区块规划")
	var entries:Array=JSON.parse_string(FileAccess.get_file_as_string("res://build-tools/journey/tripo-village-assets.json")).assets
	for entry in entries:
		var parts:Array=game.landscape.load_parts("res://"+entry.path)
		check(parts.size()==1 and parts[0].mesh.get_surface_count()==1,"每件资产保持一个材质批次："+entry.name)
		var mat:StandardMaterial3D=parts[0].mesh.surface_get_material(0)
		check(mat!=null and mat.albedo_texture!=null and mat.normal_enabled and mat.normal_texture!=null and mat.roughness_texture!=null,"导入后保留完整 PBR："+entry.name)
		check(parts==game.landscape.load_parts("res://"+entry.path),"重复实例复用缓存网格："+entry.name)
		if entry.height_m!=null:
			var bounds:AABB=parts[0].transform*parts[0].mesh.get_aabb()
			check(absf(bounds.size.y-entry.height_m)<.02,"导入高度与世界米制一致："+entry.name)
	# 真实生产同步创建机关，检查美术变换没有写入玩法状态。
	for array in [game.run.journey_events,game.run.kinds,game.run.obstacles,game.run.obstacle_ids,game.run.obstacle_heights,game.run.hazard_specs]:array.clear()
	game.reset_journey_views();game.run.state="running"
	var indices:Array=[]
	for kind in ["stone_ball","rail"]:
		var size:Vector2=game.run.Threats.CONFIG[kind].size if kind=="stone_ball" else Vector2(200,12)
		indices.append(game.run.add_hazard(kind,Rect2(Vector2(100,400),size)))
	var before:int=game.run.sync_hash()
	game.sync_static_hazards()
	check(before==game.run.sync_hash(),"新模型创建不会改变碰撞、随机种子或同步状态")
	for index:int in indices:
		var view:Node3D=game.static_views[index]
		var ball:bool=game.run.kinds[index]=="stone_ball"
		var parent:Node3D=view.get_node("BallBody") if ball else view
		var figure:Node3D=parent.get_node("TripoModel")
		var bounds:AABB=figure.transform*game.model_bounds(figure,figure)
		var rect:Rect2=game.run.obstacles[index]
		var diameter:float=rect.size.x/20
		var wanted:=Vector3.ONE*diameter if ball else Vector3(rect.size.x/20,.6,rect.size.y/20)
		check(bounds.size.is_equal_approx(wanted),"模型包围盒精确适配已有危险体："+game.run.kinds[index])
		check(bounds.get_center().is_equal_approx(Vector3.ZERO if ball else Vector3(0,.3,0)),"模型旋转轴与高度中心正确："+game.run.kinds[index])
		check(not game.hazard_asset_paths(index).is_empty(),"机关模型进入分帧预读路径："+game.run.kinds[index])
	for player in game.sfx.players:player.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("TRIPO_VILLAGE checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
