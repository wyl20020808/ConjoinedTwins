"""在既有 CC0 村民角色上新增 Throw 和 Push 骨骼动作，不改原资源。"""
import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Euler
ROOT=Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/humans/Adventurer_B.glb'))
scene=bpy.context.scene;scene.render.fps=24;scene.frame_start=1;scene.frame_end=85
rigs=[o for o in scene.objects if o.type=='ARMATURE']
for rig in rigs:
 if rig.animation_data:
  for track in rig.animation_data.nla_tracks:track.mute=not track.name.endswith('Idle')
scene.frame_set(1);bpy.context.view_layer.update()
base={}
for rig in rigs:
 evaluated=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
 base[rig.name]={bone.name:bone.matrix_basis.copy() for bone in evaluated.pose.bones}
 rig.animation_data_clear()
 for bone in rig.pose.bones:bone.matrix_basis=base[rig.name][bone.name]
for clip in ['Throw','Push']:
 for rig in rigs:
  for bone in rig.pose.bones:bone.matrix_basis=base[rig.name][bone.name]
  animated=['UpperArm.R','LowerArm.R','Chest'] if clip=='Throw' else ['UpperArm.R','UpperArm.L','LowerArm.R','LowerArm.L','Chest']
  for name in animated:
   bone=rig.pose.bones.get(name)
   if not bone:continue
   bone.rotation_mode='XYZ';initial=bone.rotation_euler.copy()
   for frame,weight in [(1,0),(20,.35),(58,1),(68,1),(73,-.4),(85,0)] if clip=='Throw' else [(1,.75),(13,.9),(25,.75),(49,.9),(85,.75)]:
    offset=(0,0,0)
    if name.startswith('UpperArm'):offset=(-1.1*weight,0,(-.25 if name.endswith('R') else .25)*weight)
    elif name.startswith('LowerArm'):offset=(-.9*weight,0,0)
    elif name=='Chest':offset=(.08*weight,0,.12*weight if clip=='Throw' else 0)
    bone.rotation_euler=Euler(tuple(initial[i]+offset[i] for i in range(3)))
    bone.keyframe_insert(data_path='rotation_euler',frame=frame)
  action=rig.animation_data.action
  if action:
   action.name=clip+'_'+rig.name
   track=rig.animation_data.nla_tracks.new();track.name=clip;track.strips.new(action.name,1,action);rig.animation_data.action=None
scene.frame_set(1)
path=ROOT/'assets/journey/villager_actions.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_yup=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_apply=False)
manifest=ROOT/'build-tools/journey/villager-actions.json'
manifest.write_text(json.dumps(dict(path=str(path.relative_to(ROOT)),source='assets/humans/Adventurer_B.glb; build-tools/journey/make_villager_actions.py',license='CC0; modified animation',bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),clips=['Throw','Push']),indent=2))
print('VILLAGER ACTIONS',len(rigs),path.stat().st_size)
