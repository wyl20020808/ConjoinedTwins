"""把 Tripo 导出的枪械 GLB 规整成游戏用的持枪坐标系（Blender 后台运行）。

用法：Blender -b -P process_tripo_weapons.py -- 原始目录 输出目录
- 枪管朝 -Z、上方 +Y；按表中缩放，使右手握把落在 GRIP_RIGHT=(0,-0.10,0.12)。
- 写入空节点标记：Muzzle（枪口）、Magazine（弹匣/燃料罐/装填口）、GripLeft（左手握点）、
  Port（逐发装填口）、ChargingHandle（拉机柄）。
- 冲锋枪的弹匣按包围盒拆成独立网格 MagazineMesh，换弹时可整体拔出、插回。
表中坐标取自侧视渲染（长轴为 X、枪口朝 +X、上方 +Z，单位为原始归一化米）。"""
import bpy,bmesh,sys,math,os,mathutils
GRIP=(0.0,-0.10,0.12)
WEAPONS={
	"smg":{"axis":"x","scale":1.37,"grip":(-0.095,0.17),"marks":{"Muzzle":(0.5,0.295),"Magazine":(0.09,0.205),"GripLeft":(0.24,0.22),"ChargingHandle":(-0.13,0.35)},
		"split":((0.055,0.19),(-1.0,0.205))},
	"shotgun":{"axis":"x","scale":1.35,"grip":(-0.24,0.08),"marks":{"Muzzle":(0.5,0.155),"Magazine":(-0.04,0.09),"Port":(-0.04,0.09),"GripLeft":(0.10,0.095)}},
	# 榴弹发射器原始模型枪口朝 -X，先绕竖轴转 180°；坐标按转过后的侧视图量取。
	"launcher":{"axis":"-x","scale":1.5,"grip":(-0.205,0.09),"marks":{"Muzzle":(0.5,0.16),"Magazine":(-0.03,0.13),"Port":(-0.03,0.13),"GripLeft":(0.10,0.105)}},
	"flamer":{"axis":"z","scale":1.35,"grip":(-0.425,0.10),"marks":{"Muzzle":(0.5,0.18),"Magazine":(-0.23,0.075),"GripLeft":(-0.06,0.155)}},
}
argv=sys.argv[sys.argv.index('--')+1:]
src_dir,out_dir=argv[0],argv[1]
only=argv[2:] or list(WEAPONS)

def to_game(name,x,z):
	# 渲染坐标 → Blender 最终坐标：缩放、绕 Z 转 90°（+X→+Y，导出后为 glTF -Z），再平移让握把对齐。
	w=WEAPONS[name];s=w["scale"];gx,gz=w["grip"]
	return mathutils.Vector((0.0,(x-gx)*s-GRIP[2],(z-gz)*s+GRIP[1]))

for name in only:
	w=WEAPONS[name]
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=os.path.join(src_dir,name+".glb"))
	meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
	assert len(meshes)==1,name
	body=meshes[0]
	body.parent=None
	body.rotation_mode='XYZ'
	# 先把网格转到渲染坐标（长轴 X、枪口 +X、上方 +Z）。
	body.matrix_world={"z":mathutils.Matrix.Rotation(math.radians(90),4,'Z'),"-x":mathutils.Matrix.Rotation(math.radians(180),4,'Z')}.get(w["axis"],mathutils.Matrix.Identity(4))
	bpy.context.view_layer.objects.active=body
	body.select_set(True)
	bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
	for o in list(bpy.context.scene.objects):
		if o!=body:bpy.data.objects.remove(o)
	if "split" in w:
		(x0,x1),(z0,z1)=w["split"]
		bm=bmesh.new();bm.from_mesh(body.data)
		for f in bm.faces:
			c=f.calc_center_median()
			f.select=x0<=c.x<=x1 and z0<=c.z<=z1
		bm.to_mesh(body.data);bm.free()
		bpy.ops.object.mode_set(mode='EDIT')
		bpy.ops.mesh.separate(type='SELECTED')
		bpy.ops.object.mode_set(mode='OBJECT')
		part=[o for o in bpy.context.scene.objects if o.type=='MESH' and o!=body][0]
		part.name="MagazineMesh"
	body.name="Body"
	s=w["scale"]
	for o in [o for o in bpy.context.scene.objects if o.type=='MESH']:
		o.matrix_world=mathutils.Matrix.Translation(to_game(name,0,0))@mathutils.Matrix.Rotation(math.radians(90),4,'Z')@mathutils.Matrix.Scale(s,4)
		bpy.context.view_layer.objects.active=o
		bpy.ops.object.select_all(action='DESELECT');o.select_set(True)
		bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
	for mark,(x,z) in w["marks"].items():
		e=bpy.data.objects.new(mark,None);e.location=to_game(name,x,z)
		bpy.context.scene.collection.objects.link(e)
	tris=sum(len(p.vertices)-2 for o in bpy.context.scene.objects if o.type=='MESH' for p in o.data.polygons)
	pts=[o.matrix_world@mathutils.Vector(c) for o in bpy.context.scene.objects if o.type=='MESH' for c in o.bound_box]
	print("WEAPON",name,"tris",tris,"min",tuple(round(min(p[i] for p in pts),3) for i in range(3)),"max",tuple(round(max(p[i] for p in pts),3) for i in range(3)))
	bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir,name+".glb"),export_format='GLB',export_extras=False,export_cameras=False,export_lights=False)
