extends SceneTree
# 从实际 Tripo 网格顶视烘焙连续路面的颜色及世界法线/粗糙度；保留源 GLB。
const BAKE=preload("res://build-tools/journey/tripo_ground_bake.gdshader")
func _initialize()->void:call_deferred("bake")
func bake()->void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(1024,2048)
	viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	viewport.add_child(env)
	var eye:=Camera3D.new();viewport.add_child(eye)
	eye.projection=Camera3D.PROJECTION_ORTHOGONAL;eye.size=4.0;eye.near=.1;eye.far=30
	eye.position=Vector3(0,10,0);eye.look_at(Vector3.ZERO,Vector3.FORWARD);eye.current=true
	for kind in ["flagstone_road_panel","cobble_road_panel","muddy_wheel_ruts"]:
		var scene:Node3D=load("res://assets/landscape/tripo_%s.glb"%kind).instantiate()
		viewport.add_child(scene)
		# 卵石模型两侧有宽泥边；顶视烘焙取内部铺装，避免把整块轮廓一起重复。
		scene.scale.x=2.2 if kind=="cobble_road_panel" else 1.0
		eye.size=3.55 if kind=="cobble_road_panel" else (3.5 if kind=="flagstone_road_panel" else 2.6)
		var meshes:Array=[];collect(scene,meshes)
		for packed:bool in [false,true]:
			env.environment.background_color=Color(.23,.17,.105) if not packed else Color(.5,.5,.92)
			for entry in meshes:
				var source:StandardMaterial3D=entry.source
				var mat:=ShaderMaterial.new();mat.shader=BAKE
				mat.set_shader_parameter("base_texture",source.albedo_texture)
				mat.set_shader_parameter("normal_texture",source.normal_texture)
				mat.set_shader_parameter("rough_texture",source.roughness_texture)
				mat.set_shader_parameter("roughness_factor",source.roughness)
				mat.set_shader_parameter("packed_normal",packed)
				entry.node.material_override=mat
			for frame in range(8):await process_frame
			await RenderingServer.frame_post_draw
			var picture:=viewport.get_texture().get_image()
			var path:="res://assets/landscape/ground/%s_%s.png"%[kind,"normal_rough" if packed else "color"]
			if picture.save_png(path)!=OK:push_error("烘焙保存失败："+path);quit(1);return
			print("BAKED ",path)
		viewport.remove_child(scene);scene.free()
	viewport.queue_free();await process_frame;await create_timer(.2).timeout
	quit(0)
func collect(node:Node,meshes:Array)->void:
	if node is MeshInstance3D:meshes.append({"node":node,"source":node.mesh.surface_get_material(0)})
	for child in node.get_children():collect(child,meshes)
