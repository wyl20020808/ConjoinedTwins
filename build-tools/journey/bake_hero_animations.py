"""把 Quaternius Adventurer 的动作烘焙到 Tripo 主角的 Mixamo 骨架。
在 Blender 5.2 后台模式运行；输出带动画的 GLB，Godot 导入时不再做重定向。
用法：blender -b --python bake_hero_animations.py -- <hero.glb> <out.glb> [clip1,clip2]
"""
import bpy, sys, os, math
from mathutils import Matrix, Vector, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'assets', 'humans', 'Adventurer_A.glb'))
RENAME = {
    'mixamorig:Hips':'Hips', 'mixamorig:Spine':'Spine', 'mixamorig:Spine1':'Chest', 'mixamorig:Spine2':'UpperChest',
    'mixamorig:Neck':'Neck', 'mixamorig:Head':'Head', 'mixamorig:HeadTop_End':'HeadTop_End',
    'mixamorig:LeftShoulder':'LeftShoulder', 'mixamorig:LeftArm':'LeftUpperArm', 'mixamorig:LeftForeArm':'LeftLowerArm', 'mixamorig:LeftHand':'LeftHand',
    'mixamorig:RightShoulder':'RightShoulder', 'mixamorig:RightArm':'RightUpperArm', 'mixamorig:RightForeArm':'RightLowerArm', 'mixamorig:RightHand':'RightHand',
    'mixamorig:LeftUpLeg':'LeftUpperLeg', 'mixamorig:LeftLeg':'LeftLowerLeg', 'mixamorig:LeftFoot':'LeftFoot', 'mixamorig:LeftToeBase':'LeftToes', 'mixamorig:LeftToe_End':'LeftToesEnd',
    'mixamorig:RightUpLeg':'RightUpperLeg', 'mixamorig:RightLeg':'RightLowerLeg', 'mixamorig:RightFoot':'RightFoot', 'mixamorig:RightToeBase':'RightToes', 'mixamorig:RightToe_End':'RightToesEnd',
}
MAP = {
    'Body':'Hips', 'Hips':'Spine', 'Abdomen':'Chest', 'Torso':'UpperChest',
    'Neck':'Neck', 'Head':'Head',
    'Shoulder.L':'LeftShoulder', 'UpperArm.L':'LeftUpperArm', 'LowerArm.L':'LeftLowerArm', 'Wrist.L':'LeftHand',
    'Shoulder.R':'RightShoulder', 'UpperArm.R':'RightUpperArm', 'LowerArm.R':'RightLowerArm', 'Wrist.R':'RightHand',
    'UpperLeg.L':'LeftUpperLeg', 'LowerLeg.L':'LeftLowerLeg', 'Foot.L':'LeftFoot', 'PT.L':'LeftToes',
    'UpperLeg.R':'RightUpperLeg', 'LowerLeg.R':'RightLowerLeg', 'Foot.R':'RightFoot', 'PT.R':'RightToes',
}

def import_glb(path):
    bpy.ops.import_scene.gltf(filepath=path)

def armatures():
    return [o for o in bpy.data.objects if o.type == 'ARMATURE']

def main():
    argv = sys.argv[sys.argv.index('--')+1:]
    hero_path, out_path = argv[0], argv[1]
    clips = set(argv[2].split(',')) if len(argv) > 2 else None
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    import_glb(SRC)
    src = armatures()[0]
    src_actions = [a for a in bpy.data.actions if a.name.startswith('CharacterArmature|')]
    src_actions.sort(key=lambda a: a.name)
    print('SRC actions', len(src_actions), flush=True)
    src_world = src.matrix_world.copy()
    src_rest = {name: (src_world @ src.data.bones[name].matrix_local) for name in MAP if src.data.bones.get(name)}
    src_rest_body_z = src_rest['Body'].translation.z if 'Body' in src_rest else 1.0
    recorded = {}
    for action in src_actions:
        short = action.name.split('|')[-1]
        if clips and short not in clips:
            continue
        src.animation_data_create()
        src.animation_data.action = action
        start, end = int(round(action.frame_range[0])), int(round(action.frame_range[1]))
        frames = list(range(start, end+1))
        data = []
        for f in frames:
            bpy.context.scene.frame_set(f)
            bpy.context.view_layer.update()
            pose = {}
            for sname in MAP:
                pb = src.pose.bones.get(sname)
                if pb is None: continue
                pose[sname] = src_world @ pb.matrix
            data.append((f, pose))
        recorded[short] = data
        print('REC', short, 'frames', len(frames), flush=True)
    # 清空场景，导入目标
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    import_glb(hero_path)
    tgt = armatures()[0]
    # 重命名骨骼和顶点组
    for old, new in RENAME.items():
        b = tgt.data.bones.get(old)
        if b: b.name = new
    for mesh in [o for o in bpy.data.objects if o.type=='MESH']:
        for old, new in RENAME.items():
            g = mesh.vertex_groups.get(old)
            if g: g.name = new
    # 记录目标静止矩阵
    tgt_world = tgt.matrix_world.copy()
    rest = {name: (tgt_world @ tgt.data.bones[name].matrix_local) for name in MAP.values() if tgt.data.bones.get(name)}
    tgt.animation_data_create()
    for pb in tgt.pose.bones: pb.rotation_mode = 'QUATERNION'
    # 静止骨盆高度，用于纵向缩放
    tgt_rest_hips = rest['Hips'].translation.z
    vertical_scale = tgt_rest_hips / max(src_rest_body_z, 0.001)
    for short, data in recorded.items():
        action = bpy.data.actions.new('CharacterArmature|' + short)
        action.use_fake_user = True
        tgt.animation_data.action = action
        for f, pose in data:
            for pb in tgt.pose.bones: pb.matrix_basis = Matrix.Identity(4)
            for sname, tname in MAP.items():
                if sname not in pose or tname not in rest: continue
                delta = src_rest[sname].inverted() @ pose[sname]
                pb = tgt.pose.bones[tname]
                m_world = rest[tname] @ delta
                m = tgt_world.inverted() @ m_world
                # 髋部只取旋转，不复制源动作的位移；世界位移由游戏模拟，位移会把角色压进地面。
                m.translation = rest[tname].translation
                pb.matrix = m
            bpy.context.view_layer.update()
            for tname in rest:
                pb = tgt.pose.bones[tname]
                pb.keyframe_insert('rotation_quaternion', frame=f)
        action.frame_end = data[-1][0]
        print('BAKED', action.name, 'frames', len(data), flush=True)
    # 别名：游戏用 HitRecieve_1
    if bpy.data.actions.get('CharacterArmature|HitRecieve'):
        alias = bpy.data.actions['CharacterArmature|HitRecieve'].copy()
        alias.name = 'CharacterArmature|HitRecieve_1'
        alias.use_fake_user = True
    # 动作源没有 Jump，用 Idle 静止姿势加髋部起伏与屈膝合成一个 31 帧跳跃。
    idle = bpy.data.actions.get('CharacterArmature|Idle')
    if idle:
        tgt.animation_data.action = idle
        bpy.context.scene.frame_set(0)
        bpy.context.view_layer.update()
        base_rot = {name: tgt.pose.bones[name].rotation_quaternion.copy() for name in rest}
        base_hip = tgt.pose.bones['Hips'].location.copy()
        jump = bpy.data.actions.new('CharacterArmature|Jump')
        jump.use_fake_user = True
        tgt.animation_data.action = jump
        keys = {0:(0.0,0.0),6:(-0.07,0.55),12:(0.24,0.05),18:(0.30,0.30),24:(0.08,0.15),27:(-0.05,0.45),30:(0.0,0.0)}
        for f in range(0,31):
            dz,bend = 0.0,0.0
            for k in sorted(keys):
                if f==k: dz,bend=keys[k]
            for name in rest:
                pb = tgt.pose.bones[name]
                pb.rotation_quaternion = base_rot[name]
            hips = tgt.pose.bones['Hips']
            hips.location = base_hip
            bpy.context.view_layer.update()
            if abs(dz)>0.0001:
                m = hips.matrix.copy(); m.translation.z += dz; hips.matrix = m
            for name in ['LeftLowerLeg','RightLowerLeg']:
                pb = tgt.pose.bones[name]
                pb.rotation_quaternion = base_rot[name] @ Quaternion((1,0,0),bend)
            bpy.context.view_layer.update()
            for name in rest:
                pb = tgt.pose.bones[name]
                pb.keyframe_insert('rotation_quaternion', frame=f)
                if name == 'Hips': pb.keyframe_insert('location', frame=f)
        jump.frame_end = 30
        print('BAKED CharacterArmature|Jump', flush=True)
    # 导出
    for o in bpy.data.objects: o.select_set(False)
    meshes = [o for o in bpy.data.objects if o.type=='MESH']
    tgt.select_set(True)
    for m in meshes: m.select_set(True)
    bpy.context.view_layer.objects.active = tgt
    bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', use_selection=True,
        export_animations=True, export_animation_mode='ACTIONS', export_nla_strips=False,
        export_anim_single_armature=True, export_skins=True, export_apply=False,
        export_yup=True, export_image_format='AUTO')
    print('DONE', out_path, os.path.getsize(out_path), flush=True)

main()
