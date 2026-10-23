"""渲染带动画 GLB 的若干动作帧（正面/侧面），用于检查重定向。
用法：blender -b --python preview_clips.py -- <out_dir> <glb> <clip:frac,...>"""
import bpy, sys, os
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:]
out_dir, path, spec = argv[0], argv[1], argv[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'STUDIO'; scene.display.shading.color_type = 'TEXTURE'
scene.render.resolution_x = 360; scene.render.resolution_y = 480
rig = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
cam_data = bpy.data.cameras.new('c'); cam_data.type = 'ORTHO'; cam_data.ortho_scale = 1.3
cam = bpy.data.objects.new('c', cam_data); scene.collection.objects.link(cam); scene.camera = cam
name = os.path.splitext(os.path.basename(path))[0]
for item in spec.split(','):
    clip, frac = item.split(':')
    action = bpy.data.actions.get('CharacterArmature|' + clip)
    rig.animation_data.action = action
    s, e = action.frame_range
    scene.frame_set(int(s + (e - s) * float(frac)))
    for view, d in (('front', Vector((0, 1, 0))), ('side', Vector((1, 0, 0)))):
        cam.location = Vector((0, 0, 0.55)) + d * 4
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(out_dir, f'{name}-{clip}-{int(float(frac)*100)}-{view}.png')
        bpy.ops.render.render(write_still=True)
