@tool
extends EditorScenePostImport
# Tripo 模型把 1K 基础色、法线和金属粗糙度贴图以 Basis Universal 嵌入 .scn，每件约 3MB，
# 网页版 PCK 因此膨胀到近 200MB。导入时把嵌入贴图缩到下列边长并重新编码为 Basis Universal：
# 仍是显存压缩格式（浏览器按 GPU 转成 BPTC/S3TC/ETC2/ASTC），下载体积约为原来的四分之一。
# 2.5D 固定镜头下这些路边布景和机关只占屏幕一小块，512 基础色与 256 细节贴图足够。
const ALBEDO_SIZE := 512
const DETAIL_SIZE := 256

func _post_import(scene:Node)->Object:
	var done:={}
	for node in scene.find_children("*","MeshInstance3D",true,false):
		var mesh:Mesh=node.mesh
		if mesh==null:continue
		for surface in range(mesh.get_surface_count()):
			var mat:=mesh.surface_get_material(surface) as BaseMaterial3D
			if mat==null:continue
			for channel in ["albedo_texture","normal_texture","roughness_texture","metallic_texture","ao_texture","emission_texture"]:
				var texture:Texture2D=mat.get(channel)
				if texture==null:continue
				if not done.has(texture):done[texture]=shrink(texture,ALBEDO_SIZE if channel=="albedo_texture" else DETAIL_SIZE,channel=="normal_texture")
				mat.set(channel,done[texture])
	return scene

func shrink(texture:Texture2D,size:int,normal_map:bool)->Texture2D:
	var image:=texture.get_image()
	if image==null or maxi(image.get_width(),image.get_height())<=size:return texture
	if image.is_compressed():image.decompress()
	image.clear_mipmaps()
	var scale:=float(size)/maxi(image.get_width(),image.get_height())
	image.resize(maxi(1,roundi(image.get_width()*scale)),maxi(1,roundi(image.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps(normal_map)
	var result:=PortableCompressedTexture2D.new()
	result.create_from_image(image,PortableCompressedTexture2D.COMPRESSION_MODE_BASIS_UNIVERSAL,normal_map)
	result.resource_name=texture.resource_name
	return result
