extends SceneTree

const Run = preload("res://scripts/road_run.gd")
var checks: Array = []
var scene

func _initialize() -> void:
	call_deferred("verify")

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	print("PASS " if passed else "FAIL ", name)

func install(kind: String, triggered: bool = true) -> void:
	scene.run.retry()
	scene.run.generation_enabled = false
	scene.run.install_block(Run.Templates.make_block(kind, 1, 0), 0, "scene")
	if triggered:
		for spec in scene.run.hazard_specs: spec.trigger = 0.0
	scene.run.revision += 1
	scene.sync_view()

func verify() -> void:
	scene = load("res://scenes/road_demo.tscn").instantiate()
	scene.capture_mode = true
	scene.run.generation_enabled = false
	root.add_child(scene)
	await process_frame
	scene.run.generation_enabled = false
	install("hammer")
	for time in [0.2, 2.6, 3.5, 7.0, 8.0]:
		scene.run.elapsed = time
		scene.sync_view()
		var sample: Dictionary = scene.run.hazard_sample(0, time)
		var view: Node3D = scene.hazard_views[0]
		var valid := true
		for p in sample.parts:
			var body: MeshInstance3D = view.get_node(p.name)
			var size: Vector2 = p.get("size", p.rect.size)
			valid = valid and body.mesh.size.is_equal_approx(Vector3(size.x, p.top - p.bottom, size.y) / scene.SCALE)
			valid = valid and is_equal_approx(body.rotation.y, p.get("angle", 0.0))
			var offset: Vector2 = p.rect.get_center() - sample.rect.get_center()
			valid = valid and body.position.is_equal_approx(Vector3(offset.x, (p.top + p.bottom) * 0.5, -offset.y) / scene.SCALE)
		check("巨锤阶段模型与分部几何一致 " + sample.stage, valid)
	install("steam")
	for time in [0.2, 2.5, 3.0, 3.7, 3.9, 4.1]:
		scene.run.elapsed = time
		scene.sync_view()
		var sample: Dictionary = scene.run.hazard_sample(0, time)
		var jet: MeshInstance3D = scene.hazard_views[0].get_node("jet")
		check("蒸汽阶段显隐与实际喷流一致 " + sample.stage, jet.visible == sample.parts[1].active and is_equal_approx(jet.mesh.size.y, sample.parts[1].top / scene.SCALE))
	install("collapse")
	var view: Node3D = scene.hazard_views[0]
	var instance := view.get_instance_id()
	var grace: float = scene.run.hazard_specs[0].grace
	for time in [0.2, 0.8, grace + 0.01]:
		scene.run.elapsed = time
		scene.run.revision += 1
		scene.sync_view()
		var sample: Dictionary = scene.run.hazard_sample(0, time)
		var floor: MeshInstance3D = view.get_node("floor")
		var cracks := true
		for child in floor.get_children(): cracks = cracks and child.visible == sample.warning
		check("塌陷模型裂纹与真实支撑一致 " + sample.stage, floor.visible == sample.supported and cracks and scene.run.has_ground_support(Vector2(0, 550)) == sample.supported)
	var cut_surface := false
	var area := 0.0
	var expected := 0.0
	var matches := true
	for chunk in scene.scenery:
		if chunk.has_meta("road_slot"):
			var surface: MeshInstance3D = chunk.get_node("SupportSurface")
			cut_surface = cut_surface or surface.mesh != surface.get_meta("original_mesh")
			var required_plate: Rect2 = scene.run.obstacles[0]
			var required_hole := Rect2(required_plate.position.x / scene.SCALE, -required_plate.end.y / scene.SCALE - chunk.position.z, required_plate.size.x / scene.SCALE, required_plate.size.y / scene.SCALE)
			if required_hole.intersection(Rect2(-12.3, -4, 24.6, 8)).get_area() > 0:
				matches = matches and surface.mesh is ArrayMesh
			if surface.mesh is ArrayMesh:
				var plate: Rect2 = scene.run.obstacles[0]
				var hole := Rect2(plate.position.x / scene.SCALE, -plate.end.y / scene.SCALE - chunk.position.z, plate.size.x / scene.SCALE, plate.size.y / scene.SCALE)
				expected += 24.6 * 8.0 - hole.intersection(Rect2(-12.3, -4, 24.6, 8)).get_area()
				var vertices: PackedVector3Array = surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				for n in range(0, vertices.size(), 3):
					area += absf((vertices[n + 1] - vertices[n]).cross(vertices[n + 2] - vertices[n]).y) * 0.5
					var middle: Vector3 = (vertices[n] + vertices[n + 1] + vertices[n + 2]) / 3
					matches = matches and not hole.has_point(Vector2(middle.x, middle.z))
	check("生产塌陷实际切除道路顶部", cut_surface)
	check("塌陷切除范围与真实支撑矩形一致", matches and absf(area - expected) < 0.001)
	install("collapse", false)
	view = scene.hazard_views[0]
	var restored := true
	for chunk in scene.scenery:
		if chunk.has_meta("road_slot"):
			var surface: MeshInstance3D = chunk.get_node("SupportSurface")
			restored = restored and surface.mesh == surface.get_meta("original_mesh")
	check("重试池复用恢复地板路面和裂纹", view.get_instance_id() == instance and view.get_node("floor").visible and not view.get_node("floor").get_child(0).visible and restored)
	scene.queue_free()
	await process_frame
	var failed := 0
	for row in checks:
		if not row.passed: failed += 1
	var file := FileAccess.open("res://tests/obstacle_expansion_t04_scene_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failed": failed}, "\t"))
	file.close()
	quit(1 if failed else 0)
