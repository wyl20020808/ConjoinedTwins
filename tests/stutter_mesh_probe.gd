extends SceneTree

var changes:=0
func _initialize()->void:
	var mesh:=BoxMesh.new()
	mesh.size=Vector3(2,3,4)
	mesh.get_surface_count()
	mesh.changed.connect(func():changes+=1)
	for frame in range(120):
		mesh.size=Vector3(2,3,4)
		mesh.get_surface_count()
	print("IDENTICAL_BOX_UPDATES=120 MESH_CHANGES=",changes)
	quit()
