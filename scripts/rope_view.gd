extends MeshInstance3D

# 绳子的画面表现：一根有重量、会下垂、会甩动的细麻绳。
# 规则（长度上限、绕柱、受阻）仍完全由 rope_solver / road_run 决定，这里只把它画得像真绳子：
# 两端钉在两人腰间，中间是一串质点，按 Verlet 积分加重力，再反复把相邻质点拉回固定段长（总长 = 生产绳长）。
# 两人靠近时绳子自然垂下、拖地；拉满时绷直；绕住柱子或滚球时沿求解出的绕障路径贴紧。
const SEGMENTS := 32
const RADIUS := 0.045
const SIDES := 7
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
	rope_material.roughness = 0.9
	rope_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rope_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = rope_material

# 两股麻绳拧在一起的斜纹：深浅交替的斜条带，沿绳子方向重复。
static func braid_texture() -> ImageTexture:
	var image := Image.create(32, 32, true, Image.FORMAT_RGB8)
	for x in range(32):
		for y in range(32):
			var stripe := fposmod((x + y) / 16.0, 1.0)
			var shade := 0.62 + 0.38 * smoothstep(0.0, 0.25, stripe) * smoothstep(0.75, 0.5, stripe)
			image.set_pixel(x, y, Color(shade, shade * 0.93, shade * 0.82))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func reset(start: Vector3, finish: Vector3) -> void:
	points.resize(SEGMENTS + 1)
	previous.resize(SEGMENTS + 1)
	for n in range(SEGMENTS + 1):
		points[n] = start.lerp(finish, float(n) / SEGMENTS)
		previous[n] = points[n]

# path：从 01 到 02 的折线（视图坐标）。只有两个点时绳子自由下垂；有中间点说明绕住了障碍，沿折线贴紧。
func simulate(path: Array[Vector3], delta: float, tint: Color, glow: float) -> void:
	var start: Vector3 = path[0]
	var finish: Vector3 = path[path.size() - 1]
	if points.size() != SEGMENTS + 1 or points[0].distance_to(start) > 3.0 or points[SEGMENTS].distance_to(finish) > 3.0:
		reset(start, finish)
	rope_material.albedo_color = tint
	rope_material.emission_enabled = glow > 0.0
	rope_material.emission = tint
	rope_material.emission_energy_multiplier = glow
	if path.size() > 2:
		# 绕障时贴着求解路径：按弧长把质点均匀铺上去，速度清零，脱开后再从这里自然落下。
		var total := 0.0
		for n in range(1, path.size()): total += path[n - 1].distance_to(path[n])
		for n in range(SEGMENTS + 1):
			points[n] = along(path, total * n / SEGMENTS)
			previous[n] = points[n]
		draw()
		return
	var span := start.distance_to(finish)
	# 规则绳长 7.33 米，两人靠近时整段余量全垂下来会拖在地上看不见；画面上只放出有限余量，
	# 让绳子在两人之间弯成一道明显的弧，拉开到接近上限时自然绷直。
	var slack := clampf(length - span, 0.0, 0.45 + 0.1 * span)
	var rest := (span + slack) / SEGMENTS
	var dt := clampf(delta, 0.0, 1.0 / 30.0)
	for n in range(1, SEGMENTS):
		var velocity := (points[n] - previous[n]) * 0.985
		previous[n] = points[n]
		points[n] += velocity + (GRAVITY + WIND) * dt * dt
	for iteration in range(ITERATIONS):
		points[0] = start
		points[SEGMENTS] = finish
		for n in range(SEGMENTS):
			var offset := points[n + 1] - points[n]
			var distance := offset.length()
			if distance < 0.00001: continue
			var correction := offset * (1.0 - rest / distance) * 0.5
			if n > 0: points[n] += correction
			if n + 1 < SEGMENTS: points[n + 1] -= correction
		# 拖地的部分躺在路面上，不穿进地里。
		for n in range(1, SEGMENTS):
			if points[n].y < RADIUS: points[n].y = RADIUS
	points[0] = start
	points[SEGMENTS] = finish
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
	immediate.clear_surfaces()
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var travelled := 0.0
	var normal_hint := Vector3.UP
	for n in range(SEGMENTS + 1):
		var forward := (points[mini(n + 1, SEGMENTS)] - points[maxi(n - 1, 0)]).normalized()
		if forward.length() < 0.5: forward = Vector3.RIGHT
		if absf(forward.dot(normal_hint)) > 0.95: normal_hint = Vector3.FORWARD
		var side := forward.cross(normal_hint).normalized()
		var up := side.cross(forward).normalized()
		if n > 0: travelled += points[n - 1].distance_to(points[n])
		var ring: Array = []
		for k in range(SIDES + 1):
			var angle := TAU * k / SIDES
			var normal := side * cos(angle) + up * sin(angle)
			ring.append([points[n] + normal * RADIUS, normal, Vector2(float(k) / SIDES, travelled / 0.12)])
		rings.append(ring)
	for n in range(SEGMENTS):
		for k in range(SIDES):
			for corner in [[n, k], [n + 1, k], [n + 1, k + 1], [n, k], [n + 1, k + 1], [n, k + 1]]:
				var vertex: Array = rings[corner[0]][corner[1]]
				immediate.surface_set_normal(vertex[1])
				immediate.surface_set_uv(vertex[2])
				immediate.surface_add_vertex(vertex[0])
	immediate.surface_end()
