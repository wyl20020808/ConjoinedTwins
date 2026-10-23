"""后台生成制作资源的联系表，不是游戏运行截图。"""
import bpy,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build-tools/journey/evidence';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
items=['house_0','house_1','house_2','boar','cart','falling_tree','waterwheel','gate','drawbridge','fence','sign']
for n,name in enumerate(items):
 before=set(bpy.data.objects)
 bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/journey'/f'{name}.glb'))
 objects=list(set(bpy.data.objects)-before)
 for o in objects:
  if o.animation_data:o.animation_data_clear()
 # 统一在最终开桥姿态预览。
 for o in objects:
  if name=='drawbridge' and 'BridgePivot' in o.name:o.rotation_euler=(0,0,0)
 bpy.context.view_layer.update()
 vertices=[o.matrix_world@Vector(corner) for o in objects if o.type=='MESH' for corner in o.bound_box]
 lo=Vector(tuple(min(v[i] for v in vertices) for i in range(3)));hi=Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
 span=max(hi.x-lo.x,hi.y-lo.y,hi.z-lo.z)
 scale=5/max(span,.01)
 offset=Vector(((n%4)*7,(n//4)*8,0))
 group=bpy.data.objects.new('Preview_'+name,None);bpy.context.collection.objects.link(group)
 for o in objects:
  if o.parent is None:
   world=o.matrix_world.copy();o.parent=group;o.matrix_world=world
 group.scale=(scale,scale,scale);group.location=offset-Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))*scale
 bpy.ops.object.text_add(location=offset+Vector((-2.8,-3,0.03)))
 label=bpy.context.object;label.data.body=name;label.data.size=.55
bpy.ops.mesh.primitive_plane_add(size=200,location=(10,8,-.08))
plane=bpy.context.object
mat=bpy.data.materials.new('Slate');mat.diffuse_color=(.12,.14,.13,1);plane.data.materials.append(mat)
world=bpy.context.scene.world or bpy.data.worlds.new('World');bpy.context.scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.45,.5,.55,1);world.node_tree.nodes['Background'].inputs[1].default_value=.5
for pos,power,size in [((5,-10,24),4500,16),((22,15,15),2500,12)]:
 data=bpy.data.lights.new('Area','AREA');data.energy=power;data.shape='DISK';data.size=size;o=bpy.data.objects.new('Area',data);bpy.context.collection.objects.link(o);o.location=pos;o.rotation_euler=(Vector((10,8,0))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(29,-32,32));cam=bpy.context.object;cam.rotation_euler=(Vector((10,8,1))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=35;bpy.context.scene.camera=cam
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.filepath=str(OUT/'blender-assets-preview.png')
bpy.ops.render.render(write_still=True)
