@tool
extends EditorScenePostImport
# Blender 原有道具各自嵌入相同贴图。导入时统一为项目纹理，避免浏览器重复上传。
func _post_import(scene:Node)->Object:
	share(scene)
	return scene
func share(node:Node)->void:
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var mat=node.mesh.surface_get_material(surface)
			if not mat is StandardMaterial3D:continue
			for channel in ["albedo_texture","normal_texture","roughness_texture","metallic_texture","ao_texture"]:
				var texture:Texture2D=mat.get(channel)
				if texture==null:continue
				var path:=texture.resource_path
				if channel in ["metallic_texture","ao_texture"] and any_shared(path):
					mat.set(channel,null)
					continue
				var suffix:="diff" if channel=="albedo_texture" else ("nor" if channel=="normal_texture" else "rough")
				for family in ["rock_face_03","rock_boulder_dry","wood_planks"]:
					if family in path:
						var prefix:="res://assets/journey/" if family=="wood_planks" else "res://assets/env/"
						mat.set(channel,load(prefix+family+"_"+suffix+".jpg"))
				if "Pine_Bark_NormalTree" in path:
					mat.set(channel,load("res://assets/decor/Pine_Bark_NormalTree"+("_Normal" if channel=="normal_texture" else "")+".png"))
	for child in node.get_children():share(child)

func any_shared(path:String)->bool:
	return "wood_planks" in path or "rock_face_03" in path or "rock_boulder_dry" in path or "Pine_Bark_NormalTree" in path
