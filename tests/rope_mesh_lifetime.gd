extends SceneTree
const RopeView=preload("res://scripts/rope_view.gd")
var failures:=0
var changes:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var rope:=RopeView.new()
	root.add_child(rope)
	var start:Array[Vector3]=[Vector3.ZERO,Vector3(5,0,0)]
	rope.simulate(start,0,Color.WHITE,0)
	var original:Mesh=rope.mesh
	original.changed.connect(func():changes+=1)
	# 包含直立、沿纵深、弯折、零长度段以及救援末帧的两端点。
	var paths:Array=[start,[Vector3.ZERO,Vector3.UP,Vector3(0,1,1)],
		[Vector3.ZERO,Vector3.ZERO,Vector3(0,-8,2)], [Vector3(-2,0,0),Vector3(2,0,0)]]
	for raw in paths:
		var path:Array[Vector3]=[]
		path.assign(raw)
		rope.simulate(path,0,Color.WHITE,0)
		var valid:=true
		var travelled:=0.0
		for ring in range(rope.vertex_count/(rope.SIDES+1)):
			var point_index:=mini(ring,path.size()-1)
			if ring>0 and ring<path.size():travelled+=path[ring-1].distance_to(path[ring])
			for side in range(rope.SIDES+1):
				var index:=ring*(rope.SIDES+1)+side
				var offset:=index*rope.vertex_stride
				var vertex:=Vector3(rope.vertex_data.decode_float(offset),rope.vertex_data.decode_float(offset+4),rope.vertex_data.decode_float(offset+8))
				var delta:=vertex-path[point_index]
				var normal_at:=rope.normal_offset+index*rope.normal_stride
				var oct:=Vector2(rope.vertex_data.decode_u16(normal_at),rope.vertex_data.decode_u16(normal_at+2))/65535.0
				var normal:=Vector3.octahedron_decode(oct)
				var tangent_at:=rope.tangent_offset+index*rope.normal_stride
				var tangent_oct:=Vector2(rope.vertex_data.decode_u16(tangent_at),rope.vertex_data.decode_u16(tangent_at+2))/65535.0
				tangent_oct.y=tangent_oct.y*2-1
				var tangent:=Vector3.octahedron_decode(tangent_oct)
				valid=valid and vertex.is_finite() and rope.custom_aabb.has_point(vertex)
				valid=valid and delta.length()>rope.RADIUS*.90 and delta.length()<rope.RADIUS*1.10
				valid=valid and normal.dot(delta.normalized())>.999 and absf(normal.dot(tangent))<.001
				valid=valid and absf(rope.attribute_data.decode_float(rope.uv_offset+index*rope.uv_stride+4)-travelled/.18)<.0001
		check(valid,"缓冲区位置、包围盒、法线、切线与实际绳长 UV 有效")
	check(rope.mesh==original and changes==0,"两点复位与弯折共用同一渲染表面")
	var invalid:Array[Vector3]=[Vector3(NAN,0,0),Vector3.ONE]
	rope.simulate(invalid,0,Color.WHITE,0)
	check(not rope.visible,"无效几何不提交渲染器")
	rope.simulate(start,0,Color.WHITE,0)
	check(rope.visible and rope.mesh==original,"有效物理路径恢复后重新显示")
	rope.queue_free();original=null
	await process_frame
	print("ROPE_MESH_LIFETIME failures=",failures)
	quit(1 if failures else 0)
