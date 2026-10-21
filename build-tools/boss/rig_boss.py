"""给 Tripo 文生 3D 的「枯根巨像」自动建上半身骨架、按距离绑定权重并手写动作，导出带动画 GLB。

在 Blender 5.2 后台运行：
  blender -b --python rig_boss.py -- <输出 GLB> [--preview <目录>]
输入固定为 build-tools/boss/source/root_colossus.glb（Tripo 原模型，最长边 1、脚底在原点、正前方 -X、Z 向上）。

做法：
1. 从网格推关节：|y| 较大且离地较高的顶点归为左右手臂，按高度分桶取质心得到肩、肘、手；
   躯干按高度切出腰、胸、颈、头。下半身根团（离地 0.30 以下）只挂在不动的 Root 上，保证扎根不滑动。
2. 不用 Blender 自动权重（Tripo 网格常有非流形面）；每个顶点按到骨段的距离取最近两根骨骼平滑混合。
3. 动作在模型空间“前/侧/上”三个轴上直接写关键帧，名称与 journey_boss_view.gd 对应：
   Idle、Roar、Slam、SweepL、SweepR、Throw、Root、Stagger、Death。Godot 按模拟时间直接 seek，不自走。
"""
import bpy, sys, os, math
from mathutils import Vector, Quaternion, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
SOURCE = os.path.join(HERE, 'source', 'root_colossus.glb')
FPS = 30
FORWARD = Vector((-1, 0, 0))
SIDE = Vector((0, 1, 0))
UP = Vector((0, 0, 1))
BASE = 0.30

args = sys.argv[sys.argv.index('--') + 1:]
OUTPUT = args[0]
PREVIEW = args[args.index('--preview') + 1] if '--preview' in args else ''

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SOURCE)
mesh = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for other in list(bpy.context.scene.objects):
    if other != mesh and other.type == 'EMPTY':
        bpy.data.objects.remove(other)
verts = [v.co.copy() for v in mesh.data.vertices]
top = max(v.z for v in verts)


def centroid(points):
    total = Vector()
    for p in points:
        total += p
    return total / max(1, len(points))


# —— 关节 ——
def arm_chain(side):
    # 离地 0.2 以下是根团的根须，不参与推算手的位置。
    arm = [v for v in verts if side * v.y > 0.24 and v.z > 0.2]
    lowest = min(v.z for v in arm)
    highest = max(v.z for v in arm)
    hand = centroid([v for v in arm if v.z < lowest + 0.08])
    shoulder_band = [v for v in verts if side * v.y > 0.14 and side * v.y < 0.26 and v.z > highest - 0.16]
    shoulder = centroid(shoulder_band) if shoulder_band else Vector((0, side * 0.2, highest - 0.08))
    shoulder.y = side * max(abs(shoulder.y), 0.2)
    mid_z = (shoulder.z + hand.z) * 0.5
    elbow_band = [v for v in arm if abs(v.z - mid_z) < 0.04]
    elbow = centroid(elbow_band) if elbow_band else (shoulder + hand) * 0.5
    clavicle = Vector((shoulder.x * 0.5, side * 0.08, shoulder.z + 0.01))
    tip = hand + (hand - elbow).normalized() * 0.06
    return clavicle, shoulder, elbow, hand, tip


def torso_center(z):
    band = [v for v in verts if abs(v.z - z) < 0.025 and abs(v.y) < 0.16]
    return centroid(band) if band else Vector((0, 0, z))


left = arm_chain(1)
right = arm_chain(-1)
pelvis = torso_center(BASE + 0.08)
waist = torso_center(0.52)
chest = torso_center(0.68)
neck = torso_center(top - 0.17)
head_top = Vector((neck.x, 0, top))
for p in (pelvis, waist, chest, neck):
    p.y = 0.0
print('JOINTS pelvis', pelvis, 'chest', chest, 'neck', neck, 'L', [tuple(round(c, 3) for c in p) for p in left])

# —— 骨架 ——
armature_data = bpy.data.armatures.new('ColossusRig')
armature = bpy.data.objects.new('ColossusRig', armature_data)
bpy.context.scene.collection.objects.link(armature)
bpy.context.view_layer.objects.active = armature
bpy.ops.object.mode_set(mode='EDIT')
edit = armature_data.edit_bones


def bone(name, head, tail, parent=None, connect=False):
    b = edit.new(name)
    b.head, b.tail = head, tail
    b.align_roll(FORWARD)
    if parent:
        b.parent = edit[parent]
        b.use_connect = connect
    return b


bone('Root', Vector((0, 0, 0)), Vector((0, 0, BASE)))
bone('Spine', Vector((pelvis.x, 0, BASE)), waist, 'Root')
bone('Chest', waist, chest, 'Spine', True)
bone('Neck', chest, neck, 'Chest', True)
bone('Head', neck, head_top, 'Neck', True)
for side, chain in (('L', left), ('R', right)):
    clavicle, shoulder, elbow, hand, tip = chain
    bone('Clavicle.' + side, clavicle, shoulder, 'Chest')
    bone('UpperArm.' + side, shoulder, elbow, 'Clavicle.' + side, True)
    bone('Forearm.' + side, elbow, hand, 'UpperArm.' + side, True)
    bone('Hand.' + side, hand, tip, 'Forearm.' + side, True)
bpy.ops.object.mode_set(mode='OBJECT')

# —— 权重：到骨段的距离，最近两根平滑混合；根团只挂 Root ——
segments = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in armature_data.bones}
groups = {name: mesh.vertex_groups.new(name=name) for name in segments}


def segment_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


for index, v in enumerate(verts):
    arm_side = 'L' if v.y > 0 else 'R'
    # 手臂只认离手臂骨段很近的顶点；手下方贴地的根须仍属于根团，不随手臂摆动。
    arm_reach = min(segment_distance(v, *segments[n + '.' + arm_side]) for n in ('UpperArm', 'Forearm', 'Hand'))
    armish = v.z > 0.18 and abs(v.y) > 0.15 and (arm_reach < 0.12 or (abs(v.y) > 0.28 and v.z > 0.2))
    # 手爪尖垂得比手腕低，靠近手骨的低处顶点也归手臂，否则抬手时爪尖被钉在地上拉长。
    claw = abs(v.y) > 0.25 and v.z > 0.12 and segment_distance(v, *segments['Hand.' + arm_side]) < 0.075
    armish = armish or claw
    if v.z < BASE - 0.04 and not armish:
        groups['Root'].add([index], 1.0, 'REPLACE')
        continue
    candidates = []
    for name, (a, b) in segments.items():
        if armish and not name.endswith('.' + arm_side) and name not in ('Chest',):
            continue
        if not armish and name.split('.')[0] in ('UpperArm', 'Forearm', 'Hand'):
            continue
        candidates.append((segment_distance(v, a, b), name))
    candidates.sort()
    (d0, n0), (d1, n1) = candidates[0], candidates[1]
    w0 = 1.0 / (d0 + 0.01) ** 4
    w1 = 1.0 / (d1 + 0.01) ** 4
    groups[n0].add([index], w0 / (w0 + w1), 'REPLACE')
    groups[n1].add([index], w1 / (w0 + w1), 'REPLACE')
    if v.z < BASE + 0.06 and not armish:
        # 根团到腰部的过渡：靠下的顶点保留一部分 Root 权重，扎根处不跟着晃。
        groups['Root'].add([index], (BASE + 0.06 - v.z) / 0.1, 'ADD')

modifier = mesh.modifiers.new('Armature', 'ARMATURE')
modifier.object = armature
mesh.parent = armature

# —— 动作 ——
# 在模型空间（静止姿势的骨架空间）写“相对父骨骼”的旋转：q_local = R^-1 · q · R。
rest = {b.name: b.matrix_local.to_quaternion() for b in armature_data.bones}


def world_rot(axis, degrees):
    return Quaternion(axis, math.radians(degrees))


def lean(deg):  # 正值向前（-X）俯身
    return world_rot(SIDE, -deg)


def raise_side(side, deg):  # 手臂向身体外侧、向上抬
    return world_rot(FORWARD * -1, deg * (1 if side == 'L' else -1))


def swing_front(side, deg):  # 手臂绕竖直轴摆向身前
    return world_rot(UP, deg * (1 if side == 'L' else -1))


def reach_forward(deg):  # 手臂向前上方抬（垂臂指向前方）
    return world_rot(SIDE, deg)


def twist(deg):
    return world_rot(UP, deg)


IDENTITY = Quaternion()


def pose(**rotations):
    return rotations


def key(action_name, frames, loop=False):
    """frames: [(秒, {骨骼: 模型空间旋转四元数})]。未列出的骨骼保持静止姿势。"""
    action = bpy.data.actions.new(action_name)
    armature.animation_data_create()
    armature.animation_data.action = action
    names = [b.name for b in armature_data.bones]
    for seconds, rotations in frames:
        rotations = dict(rotations)
        # 大角度抬臂分给锁骨 35%、上臂 65%，肩部蒙皮按两段过渡，不在单个关节处拉长。
        for side in ('L', 'R'):
            q = rotations.get('UpperArm.' + side)
            if q is not None and 'Clavicle.' + side not in rotations:
                rotations['Clavicle.' + side] = IDENTITY.slerp(q, 0.35)
                rotations['UpperArm.' + side] = IDENTITY.slerp(q, 0.65)
        frame = 1 + round(seconds * FPS)
        for name in names:
            pb = armature.pose.bones[name]
            pb.rotation_mode = 'QUATERNION'
            q = rotations.get(name, IDENTITY)
            r = rest[name]
            pb.rotation_quaternion = r.inverted() @ q @ r
            pb.keyframe_insert('rotation_quaternion', frame=frame, group=name)
    track = armature.animation_data.nla_tracks.new()
    track.name = action_name
    strip = track.strips.new(action_name, 1, action)
    armature.animation_data.action = None
    return action


def compose(*qs):
    out = Quaternion()
    for q in qs:
        out = q @ out
    return out


breathe = lambda s: pose(Chest=lean(s), Neck=lean(-s * 0.5),
                         **{'UpperArm.L': raise_side('L', s * 1.5), 'UpperArm.R': raise_side('R', s * 1.5)})
key('Idle', [(0, breathe(0)), (1.0, breathe(3)), (2.0, breathe(0)), (3.0, breathe(-2)), (4.0, breathe(0))], loop=True)

roar_peak = pose(Spine=lean(-8), Chest=lean(-14), Neck=lean(-18), Head=lean(-12),
                 **{'UpperArm.L': raise_side('L', 35), 'UpperArm.R': raise_side('R', 35),
                    'Forearm.L': raise_side('L', 15), 'Forearm.R': raise_side('R', 15)})
key('Roar', [(0, pose()), (0.5, roar_peak), (1.7, roar_peak), (2.2, pose())])

# 单臂插地（根刺）：0–0.6 举臂蓄力，0.6–0.75 砸下，之后保持并收回。
slam_up = pose(Chest=compose(lean(-8), twist(10)), Head=lean(-6),
               **{'UpperArm.R': compose(reach_forward(80), raise_side('R', 15)), 'Forearm.R': reach_forward(10)})
slam_down = pose(Spine=lean(16), Chest=compose(lean(18), twist(-6)), Head=lean(10),
                 **{'UpperArm.R': reach_forward(70), 'Forearm.R': reach_forward(-10), 'UpperArm.L': raise_side('L', 10)})
key('Slam', [(0, pose()), (0.6, slam_up), (0.75, slam_down), (1.6, slam_down), (2.0, pose())])


# 横扫：先把一侧手臂向外侧平举蓄力，再绕竖直轴贴地扫过身前到另一侧。
def sweep(side):
    other = 'R' if side == 'L' else 'L'
    sign = 1 if side == 'L' else -1
    wind = pose(Chest=twist(-18 * sign), Spine=lean(4),
                **{'UpperArm.' + side: compose(raise_side(side, 45), swing_front(side, -25)),
                   'Forearm.' + side: raise_side(side, 10)})
    mid = pose(Chest=twist(10 * sign), Spine=lean(14),
               **{'UpperArm.' + side: compose(raise_side(side, 25), swing_front(side, 55), reach_forward(15)),
                  'Forearm.' + side: swing_front(side, 10)})
    end = pose(Chest=twist(28 * sign), Spine=lean(10),
               **{'UpperArm.' + side: compose(raise_side(side, 20), swing_front(side, 85)),
                  'Forearm.' + side: swing_front(side, 20)})
    return [(0, pose()), (0.7, wind), (0.85, mid), (1.0, end), (1.5, end), (2.0, pose())]


key('SweepL', sweep('L'))
key('SweepR', sweep('R'))

throw_back = pose(Spine=lean(-10), Chest=lean(-20), Head=lean(-10),
                  **{'UpperArm.L': reach_forward(80), 'UpperArm.R': reach_forward(80),
                     'Forearm.L': reach_forward(15), 'Forearm.R': reach_forward(15)})
throw_out = pose(Spine=lean(10), Chest=lean(16), Head=lean(6),
                 **{'UpperArm.L': reach_forward(55), 'UpperArm.R': reach_forward(55)})
key('Throw', [(0, pose()), (0.7, throw_back), (0.85, throw_out), (1.3, throw_out), (1.8, pose())])

root_hold = pose(Spine=lean(22), Chest=lean(24), Neck=lean(-10), Head=lean(-8),
                 **{'UpperArm.L': compose(reach_forward(55), raise_side('L', -5)),
                    'UpperArm.R': compose(reach_forward(55), raise_side('R', -5)),
                    'Forearm.L': reach_forward(-15), 'Forearm.R': reach_forward(-15)})
root_lift = pose(Chest=lean(-10), **{'UpperArm.L': reach_forward(75), 'UpperArm.R': reach_forward(75)})
key('Root', [(0, pose()), (0.5, root_lift), (0.8, root_hold), (2.0, root_hold)])

stagger = pose(Spine=lean(32), Chest=lean(26), Neck=lean(16), Head=lean(18),
               **{'UpperArm.L': compose(reach_forward(30), raise_side('L', -12)),
                  'UpperArm.R': compose(reach_forward(30), raise_side('R', -12)),
                  'Forearm.L': reach_forward(-30), 'Forearm.R': reach_forward(-30)})
stagger_sway = pose(Spine=lean(30), Chest=compose(lean(24), twist(4)), Neck=lean(18), Head=lean(20),
                    **{'UpperArm.L': compose(reach_forward(28), raise_side('L', -10)),
                       'UpperArm.R': compose(reach_forward(32), raise_side('R', -14)),
                       'Forearm.L': reach_forward(-28), 'Forearm.R': reach_forward(-32)})
key('Stagger', [(0, pose()), (0.35, stagger), (1.2, stagger_sway), (2.0, stagger)])

death = pose(Spine=compose(lean(38), world_rot(FORWARD, 10)), Chest=lean(30), Neck=lean(25), Head=lean(25),
             **{'UpperArm.L': raise_side('L', -20), 'UpperArm.R': compose(reach_forward(40), raise_side('R', -20)),
                'Forearm.L': reach_forward(-20), 'Forearm.R': reach_forward(-40)})
key('Death', [(0, pose(Chest=lean(-12), Head=lean(-20))), (0.6, pose(Spine=lean(12), Chest=lean(10))), (2.0, death), (3.0, death)])

# —— 导出 ——
bpy.context.scene.render.fps = FPS
bpy.ops.object.select_all(action='DESELECT')
armature.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active = armature
os.makedirs(os.path.dirname(os.path.abspath(OUTPUT)), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUTPUT, export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='NLA_TRACKS',
                          export_force_sampling=True, export_def_bones=False,
                          export_image_format='JPEG', export_jpeg_quality=88)
print('EXPORTED', OUTPUT)

# —— 预览：按动作取关键姿势正面渲染 ——
if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = scene.render.resolution_y = 400
    world = bpy.data.worlds.new('w'); world.color = (0.7, 0.7, 0.7); scene.world = world
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); scene.collection.objects.link(sun)
    sun.rotation_euler = (0.9, 0.0, -1.2); sun.data.energy = 4
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); scene.collection.objects.link(cam); scene.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 1.5
    cam.location = Vector((-3, -1.6, 0.6))
    cam.rotation_euler = (Vector((0, 0, 0.5)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    shots = [('Idle', 0), ('Roar', 1.0), ('Slam', 0.6), ('Slam', 1.0), ('SweepL', 0.7), ('SweepL', 1.0),
             ('Throw', 0.7), ('Root', 1.0), ('Stagger', 1.0), ('Death', 2.5)]
    for track in armature.animation_data.nla_tracks:
        track.mute = True
    for name, seconds in shots:
        armature.animation_data.action = bpy.data.actions[name]
        scene.frame_set(1 + round(seconds * FPS))
        scene.render.filepath = os.path.join(PREVIEW, f'pose_{name}_{seconds}.png')
        bpy.ops.render.render(write_still=True)
