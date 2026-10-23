extends SceneTree
# 验证二批真实模型、分区使用、地表切片与坍塌刷新，不替代原生 GPU 验收。
const Plans=preload("res://scripts/journey_chunk_plan.gd")
const Landscape=preload("res://scripts/journey_landscape.gd")
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
		for number in range(ceili(game.run.CHAPTERS[chapter].length/1600.0)):
			var plan:Array=Plans.make(number,chapter,game.run.CHAPTERS[chapter],game.run.EDGE)
			var paths:Array=Plans.paths(plan)
			for item in plan:
				if item[0]=="landscape_batch":used[item[1]]=true
			var theme:String=game.run.CHAPTERS[chapter].themes[clampi(int(number*1600.0/game.run.CHAPTERS[chapter].length*6),0,5)] if chapter>0 else ""
			var pieces:Array=[Rect2(-320,number*1600,640,1600)]
			var hole:=Rect2(-180,number*1600+700,360,180)
			pieces=game.subtract_floor(pieces,hole)
			var details:Dictionary=Landscape.surface_plan(pieces,number,chapter,theme,[hole])
			check(details==Landscape.surface_plan(pieces,number,chapter,theme,[hole]),"地表规划确定且不依赖玩法随机源")
			for kind:String in details:
				used[kind]=true
				check(paths.has("res://assets/landscape/%s.glb"%kind),"地表模型进入原有异步预读和保留窗口："+kind)
				var parts:Array=game.landscape.load_parts("res://assets/landscape/%s.glb"%kind)
				for transform:Transform3D in details[kind]:
					var bounds:AABB=(transform*parts[0].transform)*parts[0].mesh.get_aabb()
					var foot:=Rect2(Vector2(bounds.position.x,-bounds.end.z)*20,Vector2(bounds.size.x,bounds.size.z)*20).grow(-.02)
					if kind in ["tripo_grass_soil_border","tripo_stone_road_curb","tripo_layered_cliff_face"]:
						check(bounds.position.x>=16 or bounds.end.x<=-16,"路肩与岩壁不得侵入道路："+kind)
					elif kind=="tripo_crumbled_pit_rim":check(bounds.end.y<0,"破损坑沿全部低于站立平面，不会把缺口伪装成可走地面")
					else:check(Landscape.contained(pieces,foot),"实际网格完整位于安全切片，不能桥接缺口："+kind)
	# 三种完整路面直接覆盖安全切片，使用从对应 GLB 烘焙的完整材质，而非零散模型贴块。
	for pair in [["paving","flagstone_road_panel"],["cobbles","cobble_road_panel"],["mud","muddy_wheel_ruts"]]:
		for suffix in ["color","detail"]:
			var texture:Texture2D=game.landscape.terrain.get_shader_parameter(pair[0]+"_"+suffix)
			check(texture!=null and texture.get_width()==1024 and texture.get_height()==2048,"完整路面绑定对应模型的顶视烘焙纹理："+pair[1]+suffix)
			check(pair[1] in texture.resource_path,"纹理来源与三种路面模型一致")
		used["tripo_"+pair[1]]=true
	var surface_holder:=Node3D.new();game.road.add_child(surface_holder)
	var safe:Array=game.subtract_floor([Rect2(-320,0,640,1600)],Rect2(-180,700,360,180))
	game.landscape.ground(surface_holder,safe,0)
	var surface:MeshInstance3D=surface_holder.get_node("RoadSurface")
	check(surface.material_override==game.landscape.terrain,"生产地面使用连续铺装材质")
	var vertices:PackedVector3Array=surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var area:=0.0
	for i in range(0,vertices.size(),3):area+=(vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).length()*.5
	var expected:=0.0
	for piece:Rect2 in safe:expected+=piece.get_area()/400.0
	check(absf(area-expected)<.01,"连续新路面覆盖全部安全面积，并精确扣除缺口")
	check(game.landscape.road_material(1,"farm",false).get_shader_parameter("road_region")==1,"农田使用完整泥路")
	check(game.landscape.road_material(1,"village",false).get_shader_parameter("road_region")==2,"村庄使用完整卵石路")
	check(game.landscape.road_material(2,"mine",false).get_shader_parameter("road_region")==0,"矿道使用完整石板路")
	var entries:Array=JSON.parse_string(FileAccess.get_file_as_string("res://build-tools/journey/tripo-village-expansion-assets.json")).assets
	check(entries.size()==20,"二批清单恰好二十件")
	for entry in entries:
		var kind:String="tripo_"+entry.key
		check(used.has(kind),"二十件素材全部进入实际章节规划："+kind)
		var parts:Array=game.landscape.load_parts("res://"+entry.path)
		check(parts.size()==1 and parts[0].mesh.get_surface_count()==1,"每件只有一个网格材质批次："+kind)
		var mat:StandardMaterial3D=parts[0].mesh.surface_get_material(0)
		check(mat.albedo_texture!=null and mat.normal_enabled and mat.normal_texture!=null and mat.roughness_texture!=null,"保留颜色、法线与金属粗糙度贴图："+kind)
		var bounds:AABB=parts[0].transform*parts[0].mesh.get_aabb()
		check(bounds.size.is_equal_approx(Vector3(entry.prepared_size_m[0],entry.prepared_size_m[1],entry.prepared_size_m[2])) or bounds.size.distance_to(Vector3(entry.prepared_size_m[0],entry.prepared_size_m[1],entry.prepared_size_m[2]))<.002,"米制尺度未重复缩放："+kind)
		check(absf(bounds.position.y-entry.prepared_bottom_m)<.002,"地表与岩壁的负高度基准正确："+kind)
		check(parts==game.landscape.load_parts("res://"+entry.path),"实例继续复用网格："+kind)
	# 生产 rebuild_floor 必须对改变后的缺口重建，并保留完整玩法状态。
	game.run.state="running"
	var chunk:=Node3D.new();game.road.add_child(chunk)
	var before:int=game.run.sync_hash()
	game.rebuild_floor(chunk,0)
	var original:Node=chunk.get_node("Floor")
	check(before==game.run.sync_hash(),"真实地表构建不修改物理、机关和同步状态")
	check(original.get_child_count()>2,"生产切片实际安装新地表模型")
	game.rebuild_floor(chunk,0)
	check(original==chunk.get_node("Floor"),"未变化的地面不重复构建")
	game.run.add_hazard("road_gap",Rect2(-180,200,360,140))
	before=game.run.sync_hash();game.rebuild_floor(chunk,0)
	check(original!=chunk.get_node("Floor"),"新增实际缺口立即使旧地表失效")
	check(before==game.run.sync_hash(),"缺口刷新仍不修改玩法状态")
	for player in game.sfx.players:player.stop()
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("TRIPO_EXPANSION checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
