extends SceneTree
func _initialize() -> void:
	call_deferred("inspect")
func inspect() -> void:
	var demo = load("res://scripts/road_demo.gd").new()
	root.add_child(demo)
	for path in ["res://assets/industrial/building-a.glb", "res://assets/industrial/building-k.glb", "res://assets/mechs/George.gltf", "res://assets/mechs/Leela.gltf"]:
		var node = load(path).instantiate()
		root.add_child(node)
		print(path, " scale ", node.scale, " bounds ", demo.model_bounds(node, node))
		node.queue_free()
	demo.queue_free()
	await process_frame
	quit()
