"""从巨像真实蒙皮模型烘焙咆哮末姿，用 Voronoi 切面切割、封闭断面，保留外表 UV 和材质。"""
import bpy, bmesh, math, os, json
from mathutils import Vector
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../..'))
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT,'assets/boss/rigged/root_colossus.glb'))
arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
for track in arm.animation_data.nla_tracks: track.mute = True
action = next(a for a in bpy.data.actions if a.name.endswith('RoarSky'))
arm.animation_data.action = action
if action.slots: arm.animation_data.action_slot = action.slots[0]
bpy.context.scene.frame_set(round(action.frame_range[1]))
bpy.context.view_layer.update()
sources = [o for o in bpy.context.scene.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == arm for m in o.modifiers)]
print('SOURCE_MESHES',[(o.name,tuple(o.dimensions)) for o in sources],flush=True)
deps = bpy.context.evaluated_depsgraph_get()
combined = bmesh.new()
materials=[]
for obj in sources:
    mesh=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),depsgraph=deps)
    mesh.transform(obj.matrix_world)
    offset=len(materials); materials.extend(list(mesh.materials))
    for poly in mesh.polygons: poly.material_index += offset
    combined.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)
combined.verts.ensure_lookup_table()
vertices=[v.co.copy() for v in combined.verts]
print('BOUNDS',[(min(v[k] for v in vertices),max(v[k] for v in vertices)) for k in range(3)],flush=True)
# 最远点采样使头部、两臂和根部都有独立碎块，固定起点保证重建一致。
seeds=[max(vertices,key=lambda v:v.z).copy()]
for i in range(27):
    seeds.append(max(vertices,key=lambda v:min((v-s).length_squared for s in seeds)).copy())
with open(os.path.join(ROOT,'assets/boss/rigged/root_colossus_fracture.json'),'w',encoding='utf-8') as f:
    json.dump({'seeds':[[s.x,s.z,-s.y] for s in seeds]},f)
cap=bpy.data.materials.new('FracturedHeartwood'); cap.use_nodes=True
node=next((n for n in cap.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
if node is None:
    node=cap.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    output=cap.node_tree.nodes.new('ShaderNodeOutputMaterial')
    cap.node_tree.links.new(node.outputs['BSDF'],output.inputs['Surface'])
node.inputs['Base Color'].default_value=(.085,.025,.006,1)
node.inputs['Roughness'].default_value=.88
node.inputs['Emission Color'].default_value=(1,.18,.015,1)
node.inputs['Emission Strength'].default_value=.7
result=[]
for index,seed in enumerate(seeds):
    bm=combined.copy()
    for other in seeds:
        if (seed-other).length<1e-6: continue
        normal=(other-seed).normalized(); center=(seed+other)*.5
        cut=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.00001,plane_co=center,plane_no=normal,clear_outer=True,clear_inner=False)
        edges=[e for e in cut['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
        if edges:
            filled=bmesh.ops.holes_fill(bm,edges=edges,sides=0)
            for face in filled['faces']: face.material_index=len(materials)
    if not bm.faces: bm.free(); continue
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    mesh=bpy.data.meshes.new('BodyShard%02d'%index); bm.to_mesh(mesh); bm.free()
    for material in materials: mesh.materials.append(material)
    mesh.materials.append(cap)
    obj=bpy.data.objects.new(mesh.name,mesh); bpy.context.collection.objects.link(obj)
    result.append(obj)
combined.free()
bpy.ops.object.select_all(action='DESELECT')
for obj in result: obj.select_set(True)
output=os.path.join(ROOT,'assets/boss/rigged/root_colossus_fractured.glb')
bpy.ops.export_scene.gltf(filepath=output,use_selection=True,export_animations=False,export_format='GLB')
print('FRACTURE',len(result),'pieces',os.path.getsize(output),'bytes',flush=True)
