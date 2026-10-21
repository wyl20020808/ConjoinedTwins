extends RefCounted
# 连续世界空间地貌。相邻区块共用同一高度函数、材质和实例网格。
const HALF := 16.0
const EXTENT := 140.0
const WIDTH := 80.0
const SHADER = preload("res://scripts/journey_ground.gdshader")
# Tripo 文生 3D 村民（静态，约 5.7k 三角面、1024 贴图），原生高 1、朝 +X；按 3 米身高摆放。
const VILLAGERS := ["villager_farmer","villager_elder","villager_blacksmith","villager_merchant"]
const VILLAGER_HEIGHT := 3.0
const TRIPO_HOUSES := ["tripo_cottage","tripo_workshop","tripo_roadside_inn","tripo_corner_townhouse","tripo_stone_cottage","tripo_riverside_house","tripo_thatched_farmhouse","tripo_storage_barn","tripo_forester_cabin"]
const SURFACE_KINDS := ["tripo_cobble_road_panel","tripo_flagstone_road_panel","tripo_muddy_wheel_ruts","tripo_grass_soil_border","tripo_leaf_litter_patch","tripo_stone_road_curb","tripo_crumbled_pit_rim","tripo_layered_cliff_face"]
var game
var terrain: ShaderMaterial
var cut_material:StandardMaterial3D
var parts := {}
var road_materials := {}
var palette := {}
var leaf_material:ShaderMaterial
var mobile:=false

static func profile(meters:float,chapter:int=0)->Vector3:
	if chapter==0:
		var land:=smoothstep(220.0,420.0,meters)
		var village:=smoothstep(1020.0,1250.0,meters)
		return Vector3(1.0-land,land*(1.0-village),village)
	if chapter==1:return Vector3(0,0.3,0.7)
	return Vector3(0.75,0.2,0.05)

static func height_at(x:float,meters:float,chapter:int)->float:
	var p:=profile(meters,chapter)
	var shoulder:=maxf(0,absf(x)-HALF)
	var cliff:=-minf(46.0,pow(shoulder,0.72)*4.2)
	var hill:=(sin(x*.12+meters*.023)*1.4+sin(x*.051-meters*.045)*1.8+2.2)*smoothstep(0.0,35.0,shoulder)
	return lerpf(hill,cliff,p.x)

func _init(owner_game)->void:
	game=owner_game
	mobile=OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	terrain=ShaderMaterial.new();terrain.shader=SHADER
	terrain.set_shader_parameter("road_macro",load("res://assets/landscape/ground/road_macro.png"))
	terrain.set_shader_parameter("stone",load("res://assets/env/monastery_stone_floor_diff.jpg"))
	terrain.set_shader_parameter("soil",load("res://assets/journey/forest_leaves_02_diff.jpg"))
	terrain.set_shader_parameter("rock",load("res://assets/env/rock_face_03_diff.jpg"))
	terrain.set_shader_parameter("soil_normal",load("res://assets/journey/forest_leaves_02_nor.jpg"))
	terrain.set_shader_parameter("stone_normal",load("res://assets/env/monastery_stone_floor_nor.jpg"))
	for entry in [["paving","flagstone_road_panel"],["cobbles","cobble_road_panel"],["mud","muddy_wheel_ruts"]]:
		terrain.set_shader_parameter(entry[0]+"_color",load("res://assets/landscape/ground/%s_color.png"%entry[1]))
		terrain.set_shader_parameter(entry[0]+"_detail",load("res://assets/landscape/ground/%s_normal_rough.png"%entry[1]))
	palette.Bark=game.tex_material("landscape_bark","rock_face_03",0.7,Color("776856"))
	palette.Bark.albedo_texture=load("res://assets/decor/Pine_Bark_NormalTree.png")
	palette.Bark.normal_texture=load("res://assets/decor/Pine_Bark_NormalTree_Normal.png")
	leaf_material=ShaderMaterial.new();leaf_material.shader=preload("res://scripts/journey_foliage.gdshader")
	palette.Leaf=leaf_material
	var natural:=ShaderMaterial.new();natural.shader=preload("res://scripts/journey_natural_leaf.gdshader")
	palette.NaturalLeaf=natural
	palette.Stone=game.tex_material("landscape_stone","rock_boulder_dry",0.4,Color("aaa895"))
	cut_material=palette.Stone.duplicate()
	cut_material.vertex_color_use_as_albedo=true
	palette.Wood=game.material("landscape_wood",Color("79634b"))
	palette.Wood.albedo_texture=load("res://assets/journey/wood_planks_diff.jpg")
	palette.Wood.uv1_triplanar=true;palette.Wood.uv1_scale=Vector3.ONE*.5
	palette.Cloth=game.material("landscape_cloth",Color("b9a883"));palette.Cloth.cull_mode=BaseMaterial3D.CULL_DISABLED
	palette.Plaster=ShaderMaterial.new();palette.Plaster.shader=preload("res://scripts/journey_plaster.gdshader")
	palette.Roof=game.material("landscape_roof",Color("865346"))
	palette.Window=game.material("landscape_window",Color("393a2c"),.08)
	palette.Iron=game.material("landscape_iron",Color("434a45"))
	for entry in [["Moss","435a2c"],["Endgrain","b69a6e"],["ClothRed","9c5343"],["ClothCream","c9b685"],["Clay","aa7154"],["Produce","cc963f"],["Soil","483b2a"]]:
		palette[entry[0]]=game.material("dressing_"+entry[0],Color(entry[1]))
		palette[entry[0]].roughness=.92
	for cloth in ["ClothRed","ClothCream"]:palette[cloth].cull_mode=BaseMaterial3D.CULL_DISABLED
	palette.Glow=game.material("dressing_glow",Color("ffd79b"),.8)
	palette.GroundShade=ShaderMaterial.new();palette.GroundShade.shader=preload("res://scripts/journey_contact.gdshader")

func set_chapter(chapter:int)->void:terrain.set_shader_parameter("chapter",chapter)

func road_material(chapter:int,theme:String,continuous:bool)->ShaderMaterial:
	if continuous:return terrain
	var key:="%d:%s"%[chapter,theme]
	if not road_materials.has(key):
		var mat:ShaderMaterial=terrain.duplicate()
		mat.set_shader_parameter("chapter",chapter)
		mat.set_shader_parameter("road_region",2 if theme=="village" else (1 if theme in ["forest","farm","meadow"] else 0))
		mat.set_shader_parameter("night",1 if chapter==2 and theme in ["mine","ruins","facility"] else 0)
		road_materials[key]=mat
	return road_materials[key]

func ground(parent:Node3D,pieces:Array,chapter:int,top_material:Material=null)->void:
	set_chapter(chapter)
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls:=SurfaceTool.new();walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect:Rect2 in pieces:
		var x0:float=rect.position.x/20.0;var x1:float=rect.end.x/20.0
		var z0:float=rect.position.y/20.0;var z1:float=rect.end.y/20.0
		var rim:=[Vector3(x0,0,-z0),Vector3(x1,0,-z0),Vector3(x1,0,-z1),Vector3(x0,0,-z1)]
		quad(tool,rim[0],rim[1],rim[2],rim[3])
		# 缺口来自同一批地面切片，垂直岩壁与可站立边界严格吻合。
		# 每区块合并为一个网格，不为每块破损路面添加节点或碰撞体。
		for edge in range(4):
			var a:Vector3=rim[edge];var b:Vector3=rim[(edge+1)%4]
			var down:=Vector3(0,-4.5,0)
			var normal:Vector3=(a-b).cross(down).normalized()
			for v in [a,b,b+down,a,b+down,a+down]:
				walls.set_color(Color(.72,.67,.58) if v.y>-.1 else Color(.16,.18,.18))
				walls.set_normal(normal);walls.add_vertex(v)
	var view:=MeshInstance3D.new();view.name="RoadSurface";view.mesh=tool.commit();view.material_override=terrain if top_material==null else top_material
	view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(view)
	var cliff:=MeshInstance3D.new();cliff.name="BrokenRoadWalls"
	cliff.mesh=walls.commit();cliff.material_override=cut_material
	cliff.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(cliff)

# 地表模块与玩法共用安全切片；整块放不下就省略，绝不跨越真实缺口。
static func surface_plan(pieces:Array,number:int,chapter:int,theme:String,gaps:Array=[])->Dictionary:
	var batches:={}
	var start:=number*WIDTH
	var p:=profile(start+40,chapter)
	for row in range(20):
		var meters:=start+row*4+2
		for side:float in [-1.0,1.0]:
			var border:="tripo_grass_soil_border" if p.x<.5 else "tripo_stone_road_curb"
			var x:=side*16.6
			add_instance(batches,border,Vector3(x,height_at(x,meters,chapter) if chapter==0 else 0.0,-meters),1,PI/2 if border=="tripo_stone_road_curb" else 0.0)
			# 路缘草簇：打碎 16 米的几何直边，也遮住铺装与泥土的硬接缝。
			if border=="tripo_grass_soil_border":
				var edge_seed:=meters*3.7+side*9.1
				var edge_roll:=fposmod(sin(edge_seed)*17343.21,1.0)
				if edge_roll>0.42:
					var gx:=side*(14.55+edge_roll*0.45)
					var gy:=meters+(fposmod(sin(edge_seed*1.7)*9871.3,1.0)-0.5)*2.4
					var grass_foot:=Rect2(Vector2(gx-0.85,gy-0.85)*20,Vector2(1.7,1.7)*20)
					if contained(pieces,grass_foot):
						add_instance(batches,"grass",Vector3(gx,.02,-gy),0.55+edge_roll*0.5,fposmod(sin(edge_seed*2.1)*3571.7,1.0)*TAU)
			if row%2==0 and p.y>.25:
				var litter_x:=side*12.5
				# 同一模型原本每 8 米完全复制一次；用坐标散列打散间距、朝向和大小，
				# 降低“环形落叶堆等距排队”的重复感，不改变道路、碰撞和缺口。
				var litter_seed:=meters*7.31+side*13.7
				var roll:=fposmod(sin(litter_seed)*43758.5453,1.0)
				var yaw:=(roll-0.5)*0.7
				var litter_scale:=0.78+roll*0.22
				var offset_x:=side*(roll-0.5)*0.4
				var offset_z:=(fposmod(sin(litter_seed*2.3)*56445.234,1.0)-0.5)*1.0
				# 安全切片按实际网格外接盒判断：4 米见方的检查框覆盖旋转、缩放与偏移后的最大范围。
				var litter_foot:=Rect2(Vector2(litter_x+offset_x-2.4,meters-offset_z-2.4)*20,Vector2(4.8,4.8)*20)
				if roll>0.22 and contained(pieces,litter_foot):
					add_instance(batches,"tripo_leaf_litter_patch",Vector3(litter_x+offset_x,.025,-meters+offset_z),litter_scale,yaw)
			if row%2==0 and p.x>.5:
				add_instance(batches,"tripo_layered_cliff_face",Vector3(side*17.5,-.08,-meters),1,side*PI/2)
	# 坑沿最高点低于站立平面，仅在缺口两端下方露出破损侧壁。
	for gap:Rect2 in gaps:
		for side:float in [-1.0,1.0]:
			var edge:float=gap.position.y/20 if side<0 else gap.end.y/20
			var x:=gap.get_center().x/20
			var foot:=Rect2(Vector2(x-.9,edge+side*.85-.05)*20,Vector2(1.8,.1)*20)
			if contained(pieces,foot):add_instance(batches,"tripo_crumbled_pit_rim",Vector3(x,-.04,-edge),.45,0)
	return batches

static func contained(pieces:Array,foot:Rect2)->bool:
	for piece:Rect2 in pieces:
		if piece.encloses(foot):return true
	return false

func surface_details(parent:Node3D,pieces:Array,number:int,chapter:int,theme:String,gaps:Array)->void:
	var batches:=surface_plan(pieces,number,chapter,theme,gaps)
	for kind:String in batches:
		batch(parent,"res://assets/landscape/%s.glb"%kind,batches[kind],85 if mobile or OS.has_feature("web") else 120)
	# 贴地模块没有独立碰撞体，也不向路面投射大批细碎阴影。
	for child in parent.get_children():
		if child is MultiMeshInstance3D:child.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pit_depths(parent,number,gaps)

# 缺口内部：底部一层近黑的深渊面，压住穿透到下方的远景；内壁脚下散落碎石，做出塌陷纵深。
# 只是表现，不参与支撑或碰撞；按区块裁剪，跨区块的长缺口不重复铺设。
const PIT_DEPTH := 4.4
func pit_depths(parent:Node3D,number:int,gaps:Array)->void:
	if gaps.is_empty():return
	var chunk:=Rect2(-HALF*20-40,number*WIDTH*20,HALF*40+80,WIDTH*20)
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rubble:Array=[]
	for gap:Rect2 in gaps:
		var clip:=gap.intersection(chunk)
		if clip.size.x<=0 or clip.size.y<=0:continue
		var x0:=clip.position.x/20;var x1:=clip.end.x/20;var z0:=-clip.position.y/20;var z1:=-clip.end.y/20
		quad(tool,Vector3(x0,-PIT_DEPTH,z0),Vector3(x1,-PIT_DEPTH,z0),Vector3(x1,-PIT_DEPTH,z1),Vector3(x0,-PIT_DEPTH,z1))
		var rng:=RandomNumberGenerator.new();rng.seed=int(clip.position.x*31+clip.position.y*17)
		for n in range(clampi(int(clip.size.x*clip.size.y/9000.0),2,8)):
			rubble.append(Vector3(rng.randf_range(x0+.4,x1-.4),-PIT_DEPTH+.15,rng.randf_range(z1+.4,z0-.4)))
	var floor:=MeshInstance3D.new();floor.name="PitAbyss";floor.mesh=tool.commit()
	var dark:=StandardMaterial3D.new();dark.albedo_color=Color(.035,.032,.03);dark.roughness=1.0
	floor.material_override=dark;floor.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(floor)
	if rubble.is_empty():return
	var rock:=SphereMesh.new();rock.radius=.5;rock.height=.7;rock.radial_segments=6;rock.rings=3
	var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=rock;multi.instance_count=rubble.size()
	for i in range(rubble.size()):
		var size:=.35+fmod(abs(rubble[i].x*7.3+rubble[i].z*3.1),.5)
		multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,rubble[i].x).scaled(Vector3(size,size*.7,size*1.2)),rubble[i]))
	var stones:=MultiMeshInstance3D.new();stones.name="PitRubble";stones.multimesh=multi
	stones.material_override=cut_material;stones.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(stones)

func quad(tool:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,d:Vector3)->void:
	for v in [a,c,b,a,d,c]:
		tool.set_normal(Vector3.UP);tool.add_vertex(v)

func sides(parent:Node3D,number:int,chapter:int,section:int)->void:
	set_chapter(chapter)
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var start:=number*WIDTH
	for side:float in [-1.0,1.0]:
		for row in range(section*2,section*2+2):
			for col in range(int((EXTENT-HALF)/4)):
				var x0:float=side*(HALF+col*4.0);var x1:float=side*(HALF+(col+1)*4.0)
				var y0:=start+row*4.0;var y1:=y0+4
				var a:=Vector3(x0,height_at(x0,y0,chapter),-y0)
				var b:=Vector3(x1,height_at(x1,y0,chapter),-y0)
				var c:=Vector3(x1,height_at(x1,y1,chapter),-y1)
				var d:=Vector3(x0,height_at(x0,y1,chapter),-y1)
				# 两侧绕序统一向上；接缝顶点使用全局坐标。
				for vertices in [[a,b,c],[a,c,d]] if side>0 else [[a,c,b],[a,d,c]]:
					var normal:Vector3=(vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).normalized()
					for v in vertices:tool.set_normal(normal);tool.add_vertex(v)
	var mesh:=tool.commit()
	var view:=MeshInstance3D.new();view.mesh=mesh;view.material_override=terrain
	view.name="SurroundingTerrain";view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(view)

func load_parts(path:String)->Array:
	if parts.has(path):return parts[path]
	var scene:Node3D=load(path).instantiate()
	var result:Array=[]
	collect(scene,Transform3D.IDENTITY,result,path)
	scene.free()
	if path.get_file().get_basename() in SURFACE_KINDS:
		for part in result:
			var mat:StandardMaterial3D=part.mesh.surface_get_material(0).duplicate()
			mat.roughness=.98;mat.normal_scale=.35
			if "muddy" in path:mat.albedo_color=Color(.58,.52,.43)
			elif "road_panel" in path:mat.albedo_color=Color(.72,.69,.61)
			part.mesh.surface_set_material(0,mat)
	parts[path]=result
	return result

func collect(node:Node3D,transform:Transform3D,result:Array,path:String="")->void:
	transform=transform*node.transform
	if node is MeshInstance3D:
		# 保留导入网格的索引和 LOD，不重新读取、上传整份顶点数组。
		var mesh:Mesh=node.mesh.duplicate()
		for surface in range(mesh.get_surface_count()):
			var source:Material=mesh.surface_get_material(surface)
			var mat:Material=palette.get(source.resource_name,source) if source else palette.Leaf
			if path.get_file().contains("villager_"):
				mat=villager_material(source)
			mesh.surface_set_material(surface,mat)
		result.append({"mesh":mesh,"transform":transform})
	for child in node.get_children():
		if child is Node3D:collect(child,transform,result,path)

func villager_material(source:Material) -> ShaderMaterial:
	var mat:=ShaderMaterial.new()
	mat.shader=preload("res://scripts/villager_sway.gdshader")
	if source is BaseMaterial3D:
		var base:=source as BaseMaterial3D
		mat.set_shader_parameter("albedo_color",base.albedo_color)
		if base.albedo_texture:
			mat.set_shader_parameter("albedo_tex",base.albedo_texture)
			mat.set_shader_parameter("has_albedo",true)
		if base.normal_enabled and base.normal_texture:
			mat.set_shader_parameter("normal_tex",base.normal_texture)
			mat.set_shader_parameter("has_normal",true)
	else:
		mat.set_shader_parameter("albedo_color",Color("cfc5b0"))
	return mat

# 带骨骼动作的村民（build-tools/journey/rig_npcs.py 生成）；不存在时退回 MultiMesh + 顶点摆动。
static func rigged_villager(path:String)->String:
	return path.replace("/landscape/","/landscape/rigged/") if path.get_file().begins_with("villager_") else ""

func batch(parent:Node3D,path:String,transforms:Array,end:float,begin:float=0.0)->void:
	var rigged:=rigged_villager(path)
	if not rigged.is_empty() and ResourceLoader.exists(rigged):
		spawn_villagers(parent,rigged,transforms,end)
		return
	if transforms.size()>8:
		# MultiMesh 整批剔除；世界坐标大批次既画满远处林地，也让距离 LOD 参考错误的原点。
		var cells:={}
		for transform:Transform3D in transforms:
			var cell:=Vector2i(floori(transform.origin.x/32.0),floori(transform.origin.z/32.0))
			if not cells.has(cell):cells[cell]=[]
			cells[cell].append(transform)
		for cell:Vector2i in cells:
			var center:=Vector3((cell.x+.5)*32,0,(cell.y+.5)*32)
			batch_cell(parent,path,cells[cell],end,begin,center)
		return
	batch_cell(parent,path,transforms,end,begin,Vector3.ZERO)

# 村民逐个实例化：每个区块只有几个人。按位置散列在待机、说话、张望中挑一个循环动作并错开起始帧，
# 避免整排同步；动作随时间自然播放，只是路边布景，不参与玩法。
const VILLAGER_CLIPS:=["Idle","Talk","Look","Idle","Talk"]
func spawn_villagers(parent:Node3D,path:String,transforms:Array,end:float)->void:
	var scene:PackedScene=load(path)
	for transform:Transform3D in transforms:
		var node:Node3D=scene.instantiate()
		node.name="Villager"
		parent.add_child(node)
		node.transform=transform
		for mesh:MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
			mesh.visibility_range_end=end
			mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if not mobile else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var players:=node.find_children("*","AnimationPlayer",true,false)
		if players.is_empty():continue
		var player:AnimationPlayer=players[0]
		var seed:=absi(int(transform.origin.x*7.31+transform.origin.z*3.17))
		var clip:String=VILLAGER_CLIPS[seed%VILLAGER_CLIPS.size()]
		for name in player.get_animation_list():
			player.get_animation(name).loop_mode=Animation.LOOP_LINEAR
		play_villager_clip(player,clip)
		player.seek(fposmod(seed*0.37,player.current_animation_length),true)
		if seed%2==0:stroll(node,player,transform,seed)

static func play_villager_clip(player:AnimationPlayer,clip:String)->void:
	for name in player.get_animation_list():
		if name.get_slice("|",name.get_slice_count("|")-1)==clip:
			player.play(name,0.25)
			return

# 一半村民沿路边来回散步：走 4 米、停下张望/说话、转身走回。纯布景，不参与玩法与同步。
# 模型正前方为本地 +X，朝 -Z 走取 yaw=PI/2，朝 +Z 走取 -PI/2。
const STROLL_DISTANCE:=4.0
const STROLL_SPEED:=1.1
func stroll(node:Node3D,player:AnimationPlayer,transform:Transform3D,seed:int)->void:
	var start:=transform.origin
	var away:=start+Vector3(0,0,-STROLL_DISTANCE if seed%4==0 else STROLL_DISTANCE)
	var face_away:=PI/2 if away.z<start.z else -PI/2
	var rest:String=VILLAGER_CLIPS[(seed/2)%VILLAGER_CLIPS.size()]
	var tween:=node.create_tween().set_loops()
	tween.tween_interval(0.5+float(seed%7)*0.4)
	tween.tween_callback(func():node.rotation.y=face_away;play_villager_clip(player,"Walk"))
	tween.tween_property(node,"position",away,STROLL_DISTANCE/STROLL_SPEED)
	tween.tween_callback(func():play_villager_clip(player,rest))
	tween.tween_interval(2.0+float(seed%5)*0.5)
	tween.tween_callback(func():node.rotation.y=face_away+PI;play_villager_clip(player,"Walk"))
	tween.tween_property(node,"position",start,STROLL_DISTANCE/STROLL_SPEED)
	tween.tween_callback(func():node.rotation.y=transform.basis.get_euler().y;play_villager_clip(player,rest))

func batch_cell(parent:Node3D,path:String,transforms:Array,end:float,begin:float,center:Vector3)->void:
	for part in load_parts(path):
		var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D
		var villagers:=path.get_file().contains("villager_")
		multi.use_custom_data=villagers
		multi.mesh=part.mesh;multi.instance_count=transforms.size()
		for i in range(transforms.size()):
			var local:Transform3D=transforms[i]*part.transform
			local.origin-=center
			multi.set_instance_transform(i,local)
			if villagers:multi.set_instance_custom_data(i,Color(fposmod(float(i)*0.371,1.0),0,0,1))
		var view:=MultiMeshInstance3D.new();view.multimesh=multi
		view.position=center
		view.visibility_range_begin=begin
		view.visibility_range_end=end
		view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if begin==0 and ("oak" in path or "birch" in path or (not mobile and "/tripo_" in path)) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(view)

static func plan(number:int,chapter:int)->Array:
	var items:Array=[]
	items.append(["landscape_surface",number,chapter,""])
	for section in range(10):items.append(["landscape_terrain",number,chapter,section])
	var rng:=RandomNumberGenerator.new();rng.seed=number*109+chapter*7919+42
	var batches:={}
	var start:=number*WIDTH
	for side:float in [-1.0,1.0]:
		# 近处有独立树干与林下层，深处林带封住地平线。密度逐米过渡。
		for n in range(85):
			var meters:=start+rng.randf()*WIDTH
			var p:=profile(meters,chapter)
			var forest_density:=p.y+p.z*.10
			if rng.randf()>forest_density:continue
			var x:=side*(lerpf(24.0,49.0,p.z)+pow(rng.randf(),1.65)*88)
			var kind:="natural_birch" if n%5==0 else ("natural_oak_7" if n%2==0 else "natural_oak_17")
			var scale:=rng.randf_range(.75,1.3)
			add_instance(batches,kind,Vector3(x,height_at(x,meters,chapter),-meters),scale,rng.randf()*TAU)
		for n in range(420):
			var meters:=start+rng.randf()*WIDTH;var p:=profile(meters,chapter)
			if rng.randf()>p.y+p.z*.12:continue
			var x:=side*rng.randf_range(16.2,55)
			var kind:="fern" if n%4==0 else ("shrub" if n%5==0 else "grass")
			add_instance(batches,kind,Vector3(x,height_at(x,meters,chapter),-meters),rng.randf_range(.7,1.6),rng.randf()*TAU)
		# 老山脊继续保留石壁、扶壁孤峰与半埋石块，逐渐被林地接住。
		for n in range(10):
			var meters:=start+n*8.0
			var p:=profile(meters,chapter)
			if p.x>.02:
				items.append(["landscape_rock",Vector3(side*17,-24*p.x,-meters),p.x,false,side*.13])
				if n%3==0:items.append(["landscape_rock",Vector3(side*rng.randf_range(45,105),-64*p.x,-meters),p.x,true,rng.randf()*TAU])
		for n in range(6):
			var meters:=start+n*13.2+6;var p:=profile(meters,chapter)
			var x:=side*rng.randf_range(17.2,29)
			if p.y>.2: add_instance(batches,"woodpile",Vector3(x,height_at(x,meters,chapter),-meters),.9,rng.randf()*TAU)
			if p.z<.05 or rng.randf()>p.z:continue
			# 两排住宅形成有纵深的院落；生活物件位于道路外，不影响物理。
			if n%2==0:
				add_instance(batches,house_kind(number+n),Vector3(side*28,height_at(side*28,meters,chapter),-meters),rng.randf_range(.8,1.0),-side*PI/2)
				add_instance(batches,"fence",Vector3(side*17.6,height_at(side*17.6,meters+5,chapter),-meters-5),.7,PI/2)
				add_instance(batches,"washing_line",Vector3(side*22,height_at(side*22,meters-5,chapter),-meters+5),1,0)
				add_instance(batches,"tripo_supplies",Vector3(side*20,height_at(side*20,meters+3,chapter),-meters-3),1,side*.3)
				add_villager(batches,number*3+(n>>1),side,Vector3(side*19.8,height_at(side*19.8,meters+8,chapter),-meters-8))
			else:add_instance(batches,house_kind(number+n+1),Vector3(side*48,height_at(side*48,meters,chapter),-meters),rng.randf_range(.8,1.0),-side*PI/2)
			if n==2:add_instance(batches,"tripo_covered_well",Vector3(side*20,height_at(side*20,meters+5,chapter),-meters-5),1,0)
			for k in range(4):
				var plantx:=side*(19+k*.7)
				add_instance(batches,"shrub",Vector3(plantx,height_at(plantx,meters+6,chapter),-meters-6),.8,0)
	decorate(batches,number,chapter)
	for kind in batches:items.append(["landscape_batch",kind,batches[kind]])
	return items

static func house_kind(index:int,theme:String="village")->String:
	if theme=="farm":return ["tripo_thatched_farmhouse","tripo_storage_barn","tripo_cottage"][posmod(index,3)]
	return TRIPO_HOUSES[posmod(index,6)]

# 村民面向道路并略转向镜头，便于看清正脸；不参与物理与碰撞。
static func add_villager(batches:Dictionary,index:int,side:float,point:Vector3)->void:
	# 左右两侧错开两种，相邻院落依次轮换。
	add_instance(batches,VILLAGERS[posmod(index+(2 if side>0 else 0),VILLAGERS.size())],point,VILLAGER_HEIGHT,PI+.6 if side>0 else -.6)

static func add_instance(batches:Dictionary,kind:String,point:Vector3,size:float,yaw:float)->void:
	if not batches.has(kind):batches[kind]=[]
	var basis:=Basis(Vector3.UP,yaw)
	if kind in ["natural_oak_7","natural_oak_17","natural_birch"]:
		basis=Basis(Vector3.BACK,signf(point.x)*0.12)*basis
	batches[kind].append(Transform3D(basis.scaled(Vector3.ONE*size),point))

# 布景与物理完全分离，最靠近道路的模型边缘也在道路外；独立随机源不改变关卡。
static func decorate(batches:Dictionary,number:int,chapter:int,village_only:bool=false)->void:
	var rng:=RandomNumberGenerator.new();rng.seed=number*197+chapter*1297+819
	var start:=number*WIDTH
	for side:float in [-1.0,1.0]:
		for n in range(8):
			var meters:=start+n*10+5
			var p:=profile(meters,chapter)
			if not village_only and p.y>.3:
				var x:=side*rng.randf_range(19.7,23.5)
				var kind:="tripo_road_edge" if n%3==0 else ("tripo_stump" if n%3==1 else "detail_fern_bed")
				add_instance(batches,kind,Vector3(x,height_at(x,meters,chapter),-meters),rng.randf_range(.85,1.15),rng.randf()*TAU)
				if n%2==0:add_instance(batches,"detail_fern_bed",Vector3(side*18.7,height_at(side*18.7,meters+3,chapter),-meters-3),.8,rng.randf()*TAU)
		for n in range(3):
			var meters:=start+19.2+n*26.4
			if not village_only and profile(meters,chapter).z<.45:continue
			var kind:String=["tripo_produce_stall","tripo_bread_oven","tripo_stone_fountain"][posmod(number+n,3)]
			var x:=side*20.5
			add_instance(batches,kind,Vector3(x,height_at(x,meters,chapter) if chapter==0 else 0.0,-meters),1.0,-side*PI/2)
			add_instance(batches,"detail_lantern",Vector3(side*18.4,0,-meters+4),1.0,-side*PI/2)
		# 林屋和磨坊放在第二排，避免与路边住宅、设施挤在同一个院落。
		var middle:=start+40
		var region:=profile(middle,chapter)
		if not village_only and region.y>.55 and posmod(number,3)==0:
			add_instance(batches,"tripo_forester_cabin",Vector3(side*31,height_at(side*31,middle,chapter),-middle),.9,-side*PI/2)
		if (village_only or region.z>.7) and posmod(number,3)==1 and side>0:
			add_instance(batches,"tripo_village_windmill",Vector3(65,height_at(65,middle,chapter) if not village_only else 0.0,-middle),1,-PI/2)
	# 路缘生活带：在 17–19.6 米空地填入木桶、倒木与苔石，遮住道路直边。
	for side:float in [-1.0,1.0]:
		for n in range(6):
			var meters:=start+n*6.6+3.3
			var seed_value:=meters*5.3+side*17.2
			var roll:=fposmod(sin(seed_value)*24634.6,1.0)
			if roll<0.24:continue
			var x:=side*(17.1+roll*1.7)
			var kind:String=["barrel","detail_deadwood","detail_moss_rocks"][posmod(n+int(side+1),3)]
			add_instance(batches,kind,Vector3(x,height_at(x,meters,chapter) if chapter==0 else 0.0,-meters),0.7+roll*0.45,fposmod(sin(seed_value*1.9)*7314.2,1.0)*TAU)
	# 新住宅自带门廊；院门和货物只跟随实际住宅，不在过渡带孤立生成。
	for kind in batches.keys():
		if kind in TRIPO_HOUSES:
			for house:Transform3D in batches[kind]:
				if absf(house.origin.x)>30:continue
				var side:=signf(house.origin.x)
				if village_only:add_instance(batches,"tripo_supplies",Vector3(side*20,0,house.origin.z+5),1,-side*PI/2)
				if posmod(number,2)==0:
					var meters:float=-house.origin.z+9
					add_instance(batches,"tripo_arch",Vector3(side*19.5,height_at(side*19.5,meters,chapter) if not village_only else 0.0,-meters),1,-side*PI/2)
			continue
		if not kind.begins_with("house_"):continue
		for house:Transform3D in batches[kind]:
			if absf(house.origin.x)>30:continue
			var size:=house.basis.get_scale().x
			var side:=signf(house.origin.x)
			add_instance(batches,"detail_porch",house.origin+Vector3(-side*3.6*size,0,0),.85*size,-side*PI/2)
	# 地标：每三到四个区块一座，放在第二排或路侧，远看有明确剪影；纯展示，不参与物理。
	var landmark_middle:=start+40
	var landmark_region:=profile(landmark_middle,chapter)
	if not village_only:
		if chapter==0 and landmark_region.z>.55 and posmod(number,3)==1:
			var tower_x:=38.0
			add_instance(batches,"landmark_watchtower",Vector3(tower_x,height_at(tower_x,landmark_middle,chapter),-landmark_middle),22.0,-PI/2)
		elif chapter==2 and posmod(number,3)==1:
			add_instance(batches,"landmark_headframe",Vector3(-36,0,-landmark_middle),16.0,PI/2)
		if posmod(number,4)==3:
			var shrine_x:=17.8
			add_instance(batches,"landmark_shrine",Vector3(shrine_x,height_at(shrine_x,landmark_middle,chapter) if chapter==0 else 0.0,-landmark_middle),3.0,-PI/2)
	# 接触暗部使用低成本透明网格，不恢复 Web 端整片树林的动态阴影。
	for kind in batches.keys():
		if kind not in ["natural_oak_7","natural_oak_17","natural_birch","house_0","house_1","house_2","detail_market","detail_moss_rocks","tripo_road_edge","tripo_stump"] and kind not in VILLAGERS and kind not in TRIPO_HOUSES:continue
		for transform:Transform3D in batches[kind]:
			if absf(transform.origin.x)>52:continue
			var point:=transform.origin+Vector3(0,.035,0)
			add_instance(batches,"detail_contact",point,3.8 if kind.begins_with("house") or kind in TRIPO_HOUSES else (0.9 if kind in VILLAGERS else 1.7),0)
