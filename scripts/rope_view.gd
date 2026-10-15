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
var immediate := ImmediateMesh.new()
var rope_material := StandardMaterial3D.new()
var length := 7.33

func _ready() -> void:
	mesh = immediate
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
	if points.size() < 2: return
	immediate.clear_surfaces()
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var travelled := 0.0
	var normal_hint := Vector3.UP
	for n in range(points.size()):
		var forward := (points[mini(n + 1, points.size()-1)] - points[maxi(n - 1, 0)]).normalized()
		if forward.length() < 0.5: forward = Vector3.RIGHT
		if absf(forward.dot(normal_hint)) > 0.95: normal_hint = Vector3.FORWARD
		var side := forward.cross(normal_hint).normalized()
		var up := side.cross(forward).normalized()
		if n > 0: travelled += points[n - 1].distance_to(points[n])
		var ring: Array = []
		for k in range(SIDES + 1):
			var angle := TAU * k / SIDES
			var normal := side * cos(angle) + up * sin(angle)
			var braid := 1.0 + 0.09 * cos(3.0 * angle + travelled * TAU / 0.18)
			ring.append([points[n] + normal * RADIUS * braid, normal, Vector2(float(k) / SIDES, travelled / 0.18), -side*sin(angle)+up*cos(angle)])
		rings.append(ring)
	for n in range(points.size()-1):
		for k in range(SIDES):
			for corner in [[n, k], [n + 1, k], [n + 1, k + 1], [n, k], [n + 1, k + 1], [n, k + 1]]:
				var vertex: Array = rings[corner[0]][corner[1]]
				immediate.surface_set_normal(vertex[1])
				immediate.surface_set_uv(vertex[2])
				immediate.surface_set_tangent(Plane(vertex[3],1.0))
				immediate.surface_add_vertex(vertex[0])
	immediate.surface_end()

static func fiber_normal() -> ImageTexture:
	var image := Image.create(128, 128, true, Image.FORMAT_RGB8)
	for x in range(128):
		for y in range(128):
			var slope := sin(TAU * (3.0*x/128.0 + y/64.0)) * 0.35
			var normal := Vector3(slope, slope*0.5 + sin(x*2.1+y*0.7)*0.12, 1).normalized()
			image.set_pixel(x,y,Color(normal.x*0.5+0.5,normal.y*0.5+0.5,normal.z*0.5+0.5))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
