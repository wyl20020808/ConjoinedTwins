extends MeshInstance3D

# 麻绳网格只读取生产物理质点。没有独立的显示层绳长、重力或空气地板。
const SEGMENTS := 32
const RADIUS := 0.045
const SIDES := 12
const GRAVITY := Vector3(0, -14.0, 0)
const ITERATIONS := 18
# 道路在跑，空气迎面吹来：给绳子一点向后（朝镜头）的风。
const WIND := Vector3(0, 0, 2.2)
var points := PackedVector3Array()
var previous := PackedVector3Array()
var surface := ArrayMesh.new()
var vertex_data := PackedByteArray()
var attribute_data := PackedByteArray()
var vertex_count := 0
var vertex_stride := 0
var normal_stride := 0
var normal_offset := 0
var tangent_offset := 0
var uv_stride := 0
var uv_offset := 0
var rope_material := StandardMaterial3D.new()
var length := 7.33

func _ready() -> void:
	mesh = surface
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	rope_material.albedo_texture = braid_texture()
	rope_material.albedo_color = Color("d8b07a")
	rope_material.roughness = 0.98
	rope_material.normal_enabled = true
	rope_material.normal_texture = fiber_normal()
	rope_material.normal_scale = 0.55
	rope_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rope_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = rope_material

# 三股捻绳和细纤维由确定性纹理生成，无外部素材依赖。
static func braid_texture() -> ImageTexture:
	var image := Image.create(128, 128, true, Image.FORMAT_RGB8)
	for x in range(128):
		for y in range(128):
			var strand := 0.72 + 0.20 * cos(TAU * (3.0*x/128.0 + y/64.0))
			var fiber := 0.05 * sin(x*2.1+y*0.7) + 0.03 * sin(x*4.3-y*0.27)
			var shade := strand + fiber
			image.set_pixel(x, y, Color(shade, shade*0.87, shade*0.65))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func reset(start: Vector3, finish: Vector3) -> void:
	points.resize(SEGMENTS + 1)
	previous.resize(SEGMENTS + 1)
	for n in range(SEGMENTS + 1):
		points[n] = start.lerp(finish, float(n) / SEGMENTS)
		previous[n] = points[n]

# 兼容旧调用入口；物理推进由 road_run 完成，画面不再使用 delta 改变绳形。
func simulate(path: Array[Vector3], _delta: float, _tint: Color, _glow: float) -> void:
	points = PackedVector3Array(path)
	rope_material.albedo_color = Color("d8b583")
	rope_material.emission_enabled = false
	draw()

static func along(path: Array[Vector3], distance: float) -> Vector3:
	for n in range(1, path.size()):
		var piece := path[n - 1].distance_to(path[n])
		if distance <= piece or n == path.size() - 1:
			return path[n - 1].lerp(path[n], clampf(distance / maxf(piece, 0.00001), 0.0, 1.0))
		distance -= piece
	return path[path.size() - 1]

# 沿质点链生成一根细圆管；纹理 u 沿周向，v 沿长度，按实际长度重复，斜纹不会被拉伸。
func draw() -> void:
	if points.size() < 2:
		visible=false
		return
	for point in points:
		if not point.is_finite():
			visible=false
			return
	visible=true
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	# reset 的两端点与模拟的 25 个质点共用固定容量；多余环收在末端。
	# 保留原质点和原线段，不重采样或改变碰撞绳形。
	var ring_count:=maxi(maxi(SEGMENTS+1,points.size()),vertex_count/(SIDES+1))
	var count := ring_count*(SIDES+1)
	vertices.resize(count);normals.resize(count);tangents.resize(count*4);uvs.resize(count)
	var bounds := AABB(points[0],Vector3.ZERO)
	var travelled := 0.0
	var normal_hint := Vector3.UP
	for ring_index in range(ring_count):
		var n:=mini(ring_index,points.size()-1)
		var forward := (points[mini(n + 1, points.size()-1)] - points[maxi(n - 1, 0)]).normalized()
		if forward.length() < 0.5: forward = Vector3.RIGHT
		if absf(forward.dot(normal_hint)) > 0.95:
			normal_hint=Vector3.UP if absf(forward.y)<0.95 else Vector3.FORWARD
		var side := forward.cross(normal_hint).normalized()
		var up := side.cross(forward).normalized()
		if ring_index > 0 and ring_index < points.size(): travelled += points[n - 1].distance_to(points[n])
		bounds=bounds.expand(points[n])
		for k in range(SIDES + 1):
			var angle := TAU * k / SIDES
			var normal := side * cos(angle) + up * sin(angle)
			var braid := 1.0 + 0.09 * cos(3.0 * angle + travelled * TAU / 0.18)
			var index:=ring_index*(SIDES+1)+k
			var tangent:=-side*sin(angle)+up*cos(angle)
			vertices[index]=points[n]+normal*RADIUS*braid
			normals[index]=normal
			uvs[index]=Vector2(float(k)/SIDES,travelled/0.18)
			tangents[index*4]=tangent.x;tangents[index*4+1]=tangent.y
			tangents[index*4+2]=tangent.z;tangents[index*4+3]=1.0
	if count!=vertex_count:
		build_surface(vertices,normals,tangents,uvs)
	else:
		# 拓扑不变时只更新缓冲区，不销毁正在使用的渲染表面缓存。
		for index in range(count):
			var vertex:=vertices[index]
			vertex_data.encode_float(index*vertex_stride,vertex.x)
			vertex_data.encode_float(index*vertex_stride+4,vertex.y)
			vertex_data.encode_float(index*vertex_stride+8,vertex.z)
			encode_direction(normal_offset+index*normal_stride,normals[index].octahedron_encode())
			var tangent:=Vector3(tangents[index*4],tangents[index*4+1],tangents[index*4+2]).octahedron_encode()
			# 与 Godot 的正手性切线打包规则一致（UNORM16 八面体编码）。
			tangent.y=maxf(tangent.y,1.0/32767.0)*0.5+0.5
			if int(tangent.x*65535)==0 and int(tangent.y*65535)==65535:tangent.x=1.0
			encode_direction(tangent_offset+index*normal_stride,tangent)
			attribute_data.encode_float(uv_offset+index*uv_stride,uvs[index].x)
			attribute_data.encode_float(uv_offset+index*uv_stride+4,uvs[index].y)
		RenderingServer.mesh_surface_update_vertex_region(surface.get_rid(),0,0,vertex_data)
		RenderingServer.mesh_surface_update_attribute_region(surface.get_rid(),0,0,attribute_data)
	# 缓冲区更新不会自动重算包围盒，救援下坠和镜头切换都必须覆盖。
	custom_aabb=bounds.grow(RADIUS*1.1)

func encode_direction(offset:int,value:Vector2)->void:
	vertex_data.encode_u16(offset,clampi(int(value.x*65535),0,65535))
	vertex_data.encode_u16(offset+2,clampi(int(value.y*65535),0,65535))

func build_surface(vertices:PackedVector3Array,normals:PackedVector3Array,tangents:PackedFloat32Array,uvs:PackedVector2Array)->void:
	var indices:=PackedInt32Array()
	for n in range(vertices.size()/(SIDES+1)-1):
		for k in range(SIDES):
			var a:=n*(SIDES+1)+k
			var b:=a+SIDES+1
			indices.append_array(PackedInt32Array([a,b,b+1,a,b+1,a+1]))
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TANGENT]=tangents;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices
	# 点数变化才建立新网格；旧网格交由引擎管理引用释放，不清空活动网格。
	surface=ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	mesh=surface
	vertex_count=vertices.size()
	var format:=surface.surface_get_format(0)
	vertex_stride=RenderingServer.mesh_surface_get_format_vertex_stride(format,vertex_count)
	normal_stride=RenderingServer.mesh_surface_get_format_normal_tangent_stride(format,vertex_count)
	normal_offset=RenderingServer.mesh_surface_get_format_offset(format,vertex_count,Mesh.ARRAY_NORMAL)
	tangent_offset=RenderingServer.mesh_surface_get_format_offset(format,vertex_count,Mesh.ARRAY_TANGENT)
	uv_stride=RenderingServer.mesh_surface_get_format_attribute_stride(format,vertex_count)
	uv_offset=RenderingServer.mesh_surface_get_format_offset(format,vertex_count,Mesh.ARRAY_TEX_UV)
	vertex_data.resize(vertex_count*(vertex_stride+normal_stride))
	attribute_data.resize(vertex_count*uv_stride)

static func fiber_normal() -> ImageTexture:
	var image := Image.create(128, 128, true, Image.FORMAT_RGB8)
	for x in range(128):
		for y in range(128):
			var slope := sin(TAU * (3.0*x/128.0 + y/64.0)) * 0.35
			var normal := Vector3(slope, slope*0.5 + sin(x*2.1+y*0.7)*0.12, 1).normalized()
			image.set_pixel(x,y,Color(normal.x*0.5+0.5,normal.y*0.5+0.5,normal.z*0.5+0.5))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
