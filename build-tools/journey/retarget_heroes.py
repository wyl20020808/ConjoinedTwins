"""把 Quaternius Adventurer 的动作按"骨骼朝向匹配"烘焙到 Tripo 主角的 Mixamo 骨架。

在 Blender 5.2 后台运行：
  blender -b --python retarget_heroes.py -- <hero.glb> <out.glb>

做法：
- 对动作源每根映射骨，计算它在世界空间里相对静止姿势的旋转 D，
  再用 D 转动它的静止"骨段方向"（本骨关节 → 子关节），得到这一帧肢体实际指向。
- 主角骨架自上而下：躯干、四肢骨只做最小旋转，让本骨段指向与动作源相同；
  髋、头、手、脚这类末端骨直接沿用动作源的世界旋转增量。
- 全程只用关节位置和世界空间旋转，不依赖两套骨骼各自的局部轴向。
- 髋部位移按身高比例缩放后保留（倒地、翻滚需要）。
- 骨骼改为 Godot 人形名，便于游戏里的手部 IK 等代码查找；Godot 导入时不再做重定向。
"""
import bpy, sys, os
from mathutils import Matrix, Vector, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
HUMANS = os.path.normpath(os.path.join(HERE, '..', '..', 'assets', 'humans'))
SOURCES = [os.path.join(HUMANS, 'Adventurer_A.glb'),
           (os.path.join(HUMANS, 'rescue_climb.glb'), 'Climb'),
           (os.path.join(HUMANS, 'rescue_ropepull.glb'), 'RopePull')]

RENAME = {
    'mixamorig:Hips': 'Hips', 'mixamorig:Spine': 'Spine', 'mixamorig:Spine1': 'Chest', 'mixamorig:Spine2': 'UpperChest',
    'mixamorig:Neck': 'Neck', 'mixamorig:Head': 'Head', 'mixamorig:HeadTop_End': 'HeadTop_End',
    'mixamorig:LeftShoulder': 'LeftShoulder', 'mixamorig:LeftArm': 'LeftUpperArm', 'mixamorig:LeftForeArm': 'LeftLowerArm', 'mixamorig:LeftHand': 'LeftHand',
    'mixamorig:RightShoulder': 'RightShoulder', 'mixamorig:RightArm': 'RightUpperArm', 'mixamorig:RightForeArm': 'RightLowerArm', 'mixamorig:RightHand': 'RightHand',
    'mixamorig:LeftUpLeg': 'LeftUpperLeg', 'mixamorig:LeftLeg': 'LeftLowerLeg', 'mixamorig:LeftFoot': 'LeftFoot', 'mixamorig:LeftToeBase': 'LeftToes', 'mixamorig:LeftToe_End': 'LeftToesEnd',
    'mixamorig:RightUpLeg': 'RightUpperLeg', 'mixamorig:RightLeg': 'RightLowerLeg', 'mixamorig:RightFoot': 'RightFoot', 'mixamorig:RightToeBase': 'RightToes', 'mixamorig:RightToe_End': 'RightToesEnd',
}

# 目标骨：('dir', 源骨, 源子关节骨, 目标子关节骨) 或 ('world', 源骨)
RULES = {
    'Hips': ('world', 'Body'),
    'Spine': ('dir', 'Abdomen', 'Torso', 'Chest'),
    'Chest': ('dir', 'Torso', 'Chest', 'UpperChest'),
    'UpperChest': ('dir', 'Chest', 'Neck', 'Neck'),
    'Neck': ('dir', 'Neck', 'Head', 'Head'),
    'Head': ('world', 'Head'),
}
for s, t in (('L', 'Left'), ('R', 'Right')):
    RULES.update({
        f'{t}Shoulder': ('dir', f'Shoulder.{s}', f'UpperArm.{s}', f'{t}UpperArm'),
        f'{t}UpperArm': ('dir', f'UpperArm.{s}', f'LowerArm.{s}', f'{t}LowerArm'),
        f'{t}LowerArm': ('dir', f'LowerArm.{s}', f'Wrist.{s}', f'{t}Hand'),
        f'{t}Hand': ('world', f'Wrist.{s}'),
        f'{t}UpperLeg': ('dir', f'UpperLeg.{s}', f'LowerLeg.{s}', f'{t}LowerLeg'),
        f'{t}LowerLeg': ('dir', f'LowerLeg.{s}', f'Foot.{s}', f'{t}Foot'),
        f'{t}Foot': ('world', f'Foot.{s}'),
    })


def armature():
    return [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]


def record(path, only=None, rename=None):
    """返回 {动作名: [每帧 {源骨: (世界旋转增量, 世界位置)}]} 以及静止数据。"""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=path)
    src = armature()
    W = src.matrix_world.copy()
    rest_q = {b.name: (W @ b.matrix_local).to_quaternion() for b in src.data.bones}
    rest_p = {b.name: (W @ b.matrix_local).translation.copy() for b in src.data.bones}
    actions = [a for a in bpy.data.actions]
    if only is None:
        actions = [a for a in actions if a.name.startswith('CharacterArmature|')]
    out = {}
    for action in actions:
        name = rename or action.name
        src.animation_data_create()
        src.animation_data.action = action
        start, end = int(round(action.frame_range[0])), int(round(action.frame_range[1]))
        frames = []
        for f in range(start, end + 1):
            bpy.context.scene.frame_set(f)
            pose = {}
            for pb in src.pose.bones:
                m = W @ pb.matrix
                pose[pb.name] = (m.to_quaternion() @ rest_q[pb.name].inverted(), m.translation.copy())
            frames.append(pose)
        out[name] = frames
        print('REC', name, len(frames), flush=True)
    return out, rest_q, rest_p


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    hero_path, out_path = argv[0], argv[1]
    clips, rest_q, rest_p = record(SOURCES[0])
    for path, name in SOURCES[1:]:
        extra, _, _ = record(path, only=True, rename=name)
        clips.update(extra)
    src_height = rest_p['Body'].z - rest_p['Root'].z

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=hero_path)
    tgt = armature()
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    for old, new in RENAME.items():
        if tgt.data.bones.get(old):
            tgt.data.bones[old].name = new
    for mesh in [o for o in bpy.data.objects if o.type == 'MESH']:
        for old, new in RENAME.items():
            g = mesh.vertex_groups.get(old)
            if g:
                g.name = new
    T = tgt.matrix_world.to_quaternion()
    bones = list(tgt.data.bones)  # 父骨总在子骨之前
    R = {b.name: b.matrix_local.to_quaternion() for b in bones}
    P = {b.name: b.matrix_local.translation.copy() for b in bones}
    tgt_height = P['Hips'].z - min(P[n].z for n in P)
    scale = tgt_height / max(src_height, 1e-6)
    for pb in tgt.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    tgt.animation_data_create()

    def to_tgt(q):
        return T.inverted() @ q @ T

    for name, frames in clips.items():
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        tgt.animation_data.action = action
        rest_body = rest_p['Body']
        for f, pose in enumerate(frames):
            D = {}
            for b in bones:
                parent = D[b.parent.name] if b.parent else Quaternion()
                rule = RULES.get(b.name)
                if rule is None:
                    D[b.name] = parent
                elif rule[0] == 'world':
                    D[b.name] = to_tgt(pose[rule[1]][0])
                else:
                    _, sb, sc, tc = rule
                    src_dir = pose[sb][0] @ (rest_p[sc] - rest_p[sb])
                    want = (T.inverted() @ src_dir).normalized()
                    have = (parent @ (P[tc] - P[b.name])).normalized()
                    D[b.name] = have.rotation_difference(want) @ parent
            for b in bones:
                pb = tgt.pose.bones[b.name]
                parent = D[b.parent.name] if b.parent else Quaternion()
                pb.rotation_quaternion = R[b.name].inverted() @ parent.inverted() @ D[b.name] @ R[b.name]
                pb.keyframe_insert('rotation_quaternion', frame=f)
            hips = tgt.pose.bones['Hips']
            # 以 Root 为参照：动作源静止姿势里 Root 带一个整体偏移，动画里 Root 归零，直接相减会把角色抬走。
            move = T.inverted() @ ((pose['Body'][1] - pose['Root'][1]) - (rest_body - rest_p['Root'])) * scale
            hips.location = R['Hips'].inverted() @ move
            hips.keyframe_insert('location', frame=f)
        action.frame_range = (0, len(frames) - 1)
        print('BAKED', name, len(frames), flush=True)
    for o in bpy.data.objects:
        # 只导出骨架和蒙皮网格；Tripo 文件里那个未绑定的 Icosphere 不带。
        o.select_set(o.type == 'ARMATURE' or (o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers)))
    bpy.context.view_layer.objects.active = tgt
    bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', use_selection=True,
                              export_animations=True, export_animation_mode='ACTIONS',
                              export_skins=True, export_yup=True, export_image_format='AUTO')
    print('DONE', out_path, os.path.getsize(out_path), flush=True)


main()
