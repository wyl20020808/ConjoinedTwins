extends SceneTree
var failures:Array=[]
var paths:={}
func _initialize()->void:
	for name in ["house_0","house_1","house_2","gate","drawbridge","cart","fence","falling_tree","waterwheel"]:
		var path:="res://assets/journey/%s.glb"%name
		var scene=load(path).instantiate();inspect(scene);scene.free()
	print("SHARED MATERIAL TEXTURES ",JSON.stringify(paths.keys()))
	print("SHARED MATERIAL FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
func inspect(node:Node)->void:
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			var material=node.mesh.surface_get_material(i)
			if not material is StandardMaterial3D:continue
			for key in ["albedo_texture","normal_texture","roughness_texture","metallic_texture","ao_texture"]:
				var texture:Texture2D=material.get(key)
				if texture==null:continue
				var path:=texture.resource_path;paths[path]=true
				if "/journey/" in path and not path.get_file().begins_with("wood_planks"):
					failures.append(path);printerr("FAIL duplicated texture ",path)
	for child in node.get_children():inspect(child)
