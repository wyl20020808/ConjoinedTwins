"""给 Boss 召唤的飞行小怪（火蝠、潮汐水母）建骨架、绑定权重并手写动作，导出带动画 GLB。

在 Blender 5.2 后台运行：
  blender -b --python rig_minions.py -- <名字> <输入 GLB> <输出 GLB> [--preview <目录>]
名字为 ember_bat 或 tide_jelly。输入是 Tripo 原模型（最长边约 1、底部在原点、脸朝 -Y、Z 向上）。

做法：
1. 先把模型绕 Z 转 90°，让脸朝 +X（与 journey_enemy_view.gd 里其他怪物的原生朝向一致）。
2. 骨架很简单，权重按部位直接算（翼按离身体的横向距离在翼根/翼尖之间渐变；水母触手按方位分四束、按高度分三节渐变）。
3. 动作名与 journey_enemy_view.gd 一致：Idle / Walk / Run / Attack / Hit。画面按模拟量取样，不自走：
   Idle 2 秒内拍翼 4 次；Run/Walk 一个步幅周期拍翼 2 次；Attack 前 45% 蓄力、后 55% 出手；Hit 0.32 秒受击。
"""
import bpy, sys, os, math
from mathutils import Vector, Quaternion, Matrix

FPS = 30
args = sys.argv[sys.argv.index('--') + 1:]
NAME, SOURCE, OUTPUT = args[0], args[1], args[2]
PREVIEW = args[args.index('--preview') + 1] if '--preview' in args else ''

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SOURCE)
mesh = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
# 先带着父级变换落到世界坐标，再删掉导入时的空节点，最后把脸从 -Y 转到 +X。
world = mesh.matrix_world.copy()
mesh.parent = None
mesh.matrix_world = Matrix.Rotation(math.pi / 2, 4, 'Z') @ world
for other in list(bpy.context.scene.objects):
    if other != mesh:
        bpy.data.objects.remove(other)
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
print('BOUNDS', [round(min(v.co[i] for v in mesh.data.vertices), 3) for i in range(3)], [round(max(v.co[i] for v in mesh.data.vertices), 3) for i in range(3)])
verts = [v.co.copy() for v in mesh.data.vertices]
FORWARD = Vector((1, 0, 0))
LEFT = Vector((0, 1, 0))
UP = Vector((0, 0, 1))

armature_data = bpy.data.armatures.new(NAME + 'Rig')
armature = bpy.data.objects.new(NAME + 'Rig', armature_data)
bpy.context.scene.collection.objects.link(armature)
bpy.context.view_layer.objects.active = armature
bpy.ops.object.mode_set(mode='EDIT')
edit = armature_data.edit_bones


def bone(name, head, tail, parent=None):
    b = edit.new(name)
    b.head, b.tail = Vector(head), Vector(tail)
    b.align_roll(UP if abs((b.tail - b.head).normalized().dot(UP)) < 0.9 else FORWARD)
    if parent:
        b.parent = edit[parent]
    return b


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


weights = []  # 每个顶点 {骨骼: 权重}

if NAME == 'ember_bat':
    # 身体中心约 z 0.45，头 z 0.62，翼根在 |y| 0.09、z 0.6，翼尖到 |y| 0.49。
    bone('Root', (0, 0, 0), (0, 0, 0.1))
    bone('Body', (0, 0, 0.25), (0, 0, 0.58), 'Root')
    bone('Head', (0, 0, 0.58), (0.05, 0, 0.75), 'Body')
    bone('Feet', (0, 0, 0.25), (0, 0, 0.05), 'Body')
    for side, s in (('L', 1), ('R', -1)):
        bone('Wing.' + side, (0, s * 0.09, 0.6), (0, s * 0.27, 0.72), 'Body')
        bone('WingTip.' + side, (0, s * 0.27, 0.72), (0, s * 0.49, 0.75), 'Wing.' + side)
    for v in verts:
        ay = abs(v.y)
        side = 'L' if v.y > 0 else 'R'
        wing = smooth(0.07, 0.13, ay)
        tip = smooth(0.24, 0.32, ay)
        body = 1.0 - wing
        w = {}
        if body > 0:
            head = smooth(0.56, 0.64, v.z) * body
            feet = (1.0 - smooth(0.14, 0.24, v.z)) * body
            w['Head'] = head
            w['Feet'] = feet
            w['Body'] = max(0.0, body - head - feet)
        if wing > 0:
            w['Wing.' + side] = wing * (1.0 - tip)
            w['WingTip.' + side] = wing * tip
        weights.append(w)
else:
    # 水母：伞盖 z>0.55，触手在伞下按方位分前后左右四束，每束三节。
    bone('Root', (0, 0, 0), (0, 0, 0.1))
    bone('Bell', (0, 0, 0.55), (0, 0, 0.98), 'Root')
    QUAD = {'F': Vector((1, 0, 0)), 'B': Vector((-1, 0, 0)), 'L': Vector((0, 1, 0)), 'R': Vector((0, -1, 0))}
    LEVELS = [0.55, 0.38, 0.2, 0.0]
    for q, d in QUAD.items():
        for n in range(3):
            head = d * 0.12 + Vector((0, 0, LEVELS[n]))
            tail = d * 0.12 + Vector((0, 0, LEVELS[n + 1]))
            bone('Tent%s%d' % (q, n + 1), head, tail, 'Bell' if n == 0 else 'Tent%s%d' % (q, n))
    for v in verts:
        bell = smooth(0.5, 0.6, v.z)
        w = {'Bell': bell}
        flat = Vector((v.x, v.y, 0))
        if bell < 1.0:
            # 方位权重：与四个方向的夹角余弦取正，平方后归一。
            dirs = {}
            for q, d in QUAD.items():
                c = max(0.0, flat.normalized().dot(d)) if flat.length > 1e-4 else 0.25
                dirs[q] = c * c
            total = sum(dirs.values()) or 1.0
            # 高度：三节之间线性渐变。
            for q, c in dirs.items():
                c = c / total * (1.0 - bell)
                if c < 1e-4:
                    continue
                z = v.z
                for n in range(3):
                    top, bottom = LEVELS[n], LEVELS[n + 1]
                    mid = (top + bottom) / 2
                    span = (top - bottom)
                    k = max(0.0, 1.0 - abs(z - mid) / span)
                    if n == 0 and z > mid:
                        k = 1.0
                    if n == 2 and z < mid:
                        k = 1.0
                    w['Tent%s%d' % (q, n + 1)] = w.get('Tent%s%d' % (q, n + 1), 0.0) + c * k
        weights.append(w)

bpy.ops.object.mode_set(mode='OBJECT')
groups = {}
for index, w in enumerate(weights):
    total = sum(w.values()) or 1.0
    for name, value in w.items():
        if value / total < 0.002:
            continue
        if name not in groups:
            groups[name] = mesh.vertex_groups.new(name=name)
        groups[name].add([index], value / total, 'REPLACE')
modifier = mesh.modifiers.new('Armature', 'ARMATURE')
modifier.object = armature
mesh.parent = armature

rest = {b.name: b.matrix_local.to_quaternion() for b in armature_data.bones}
IDENTITY = Quaternion()


def rot(axis, degrees):
    return Quaternion(axis, math.radians(degrees))


def key(action_name, frames, scales=None):
    """frames: [(秒, {骨骼: 模型空间旋转})]；scales: [(秒, {骨骼: 等比缩放})]（水母伞盖收缩）。"""
    action = bpy.data.actions.new(action_name)
    armature.animation_data_create()
    armature.animation_data.action = action
    names = [b.name for b in armature_data.bones]
    for seconds, rotations in frames:
        frame = 1 + round(seconds * FPS)
        for name in names:
            pb = armature.pose.bones[name]
            pb.rotation_mode = 'QUATERNION'
            r = rest[name]
            pb.rotation_quaternion = r.inverted() @ rotations.get(name, IDENTITY) @ r
            pb.keyframe_insert('rotation_quaternion', frame=frame, group=name)
            pb.scale = (1, 1, 1)
            pb.location = (0, 0, 0)
            if scales:
                for s_sec, values in scales:
                    if abs(s_sec - seconds) < 1e-6 and name in values:
                        k = values[name]
                        pb.scale = (k[0], k[1], k[2]) if isinstance(k, tuple) else (k, k, k)
            pb.keyframe_insert('scale', frame=frame, group=name)
    track = armature.animation_data.nla_tracks.new()
    track.name = action_name
    track.strips.new(action_name, 1, action)
    armature.animation_data.action = None


def samples(length, fn, steps):
    return [(length * n / steps, fn(length * n / steps)) for n in range(steps + 1)]


if NAME == 'ember_bat':
    def flap(side, deg):  # 翼绕前后轴：正值上抬（绕 +X 正转把 +Y 侧抬起）
        return rot(FORWARD, deg if side == 'L' else -deg)

    def wings(up, tip_follow, sweep=0.0):
        out = {}
        for side in ('L', 'R'):
            s = 1 if side == 'L' else -1
            out['Wing.' + side] = rot(UP, -s * sweep) @ flap(side, up)
            out['WingTip.' + side] = rot(UP, -s * sweep) @ flap(side, up + tip_follow)
        return out

    def beat(t, period, amount=1.0):
        a = t / period * math.tau
        stroke = math.sin(a)
        p = wings(-8 + 38 * stroke * amount, 16 * math.sin(a - 0.8) * amount)
        p['Body'] = rot(LEFT, 6 * stroke)
        p['Head'] = rot(LEFT, -4 * stroke)
        p['Feet'] = rot(LEFT, 10 * math.sin(a - 1.0))
        return p

    key('Idle', samples(2.0, lambda t: beat(t, 0.5), 32))

    def run_at(t):
        p = beat(t, 0.5, 1.15)
        p['Body'] = rot(LEFT, 18) @ p['Body']  # 前倾冲刺
        return p

    key('Run', samples(1.0, run_at, 16))
    key('Walk', samples(1.0, lambda t: beat(t, 0.5, 0.9), 16))

    # 扑咬：0–0.45 后仰、双翼高举后收蓄力（伴随小幅颤动）→ 0.45–0.7 收翼俯冲张嘴 → 0.7–1.0 猛拍拉起。
    def attack_at(t):
        if t < 0.45:
            k = t / 0.45
            p = wings(10 + 30 * k + 3 * math.sin(t * 60), 14 * k, sweep=-20 * k)
            p['Body'] = rot(LEFT, -20 * k)
            p['Head'] = rot(LEFT, -14 * k)
        elif t < 0.7:
            k = (t - 0.45) / 0.25
            p = wings(40 - 70 * k, -20 * k, sweep=-20 + 45 * k)
            p['Body'] = rot(LEFT, -20 + 55 * k)
            p['Head'] = rot(LEFT, -14 + 30 * k)
        else:
            k = (t - 0.7) / 0.3
            p = wings(-30 + 30 * k + 25 * math.sin(k * math.pi), 10 * math.sin(k * math.pi), sweep=25 * (1 - k))
            p['Body'] = rot(LEFT, 35 * (1 - k))
            p['Head'] = rot(LEFT, 16 * (1 - k))
        p['Feet'] = rot(LEFT, 30 if t > 0.45 else 0)
        return p

    key('Attack', samples(1.0, attack_at, 30))

    def hit_at(t):
        k = math.sin(min(1.0, t / 0.32) * math.pi)
        p = wings(30 * k, -25 * k)
        p['Body'] = rot(LEFT, -25 * k) @ rot(FORWARD, 12 * k)
        p['Head'] = rot(LEFT, -15 * k)
        return p

    key('Hit', samples(0.32, hit_at, 8))
else:
    def tentacles(phase, amount, lift=0.0):
        out = {}
        for q, d in (('F', FORWARD), ('B', -FORWARD), ('L', LEFT), ('R', -LEFT)):
            axis = UP.cross(d)  # 绕此轴转：触手向外/内摆
            for n in range(3):
                swing = amount * math.sin(phase - n * 0.9) * (0.6 + n * 0.3) + lift
                out['Tent%s%d' % (q, n + 1)] = rot(axis, swing)
        return out

    def pulse(t, period, amount=1.0):
        a = t / period * math.tau
        squeeze = math.sin(a)
        p = tentacles(a, 14 * amount, lift=-6 * squeeze * amount)
        p['Bell'] = rot(FORWARD, 3 * math.sin(a * 0.5))
        return p, {'Bell': (1.0 + 0.08 * squeeze * amount, 1.0 + 0.08 * squeeze * amount, 1.0 - 0.1 * squeeze * amount)}

    def keyed(name, length, fn, steps):
        frames, scales = [], []
        for n in range(steps + 1):
            t = length * n / steps
            r, s = fn(t)
            frames.append((t, r))
            scales.append((t, s))
        key(name, frames, scales)

    keyed('Idle', 2.0, lambda t: pulse(t, 1.0), 24)
    keyed('Walk', 1.0, lambda t: pulse(t, 0.5, 1.2), 16)
    keyed('Run', 1.0, lambda t: pulse(t, 0.5, 1.3), 16)

    # 吐水弹：0–0.45 伞盖鼓起、触手外张蓄力 → 0.45–0.6 猛收喷射 → 回弹。
    def attack_at(t):
        if t < 0.45:
            k = t / 0.45
            p = tentacles(t * 30, 4, lift=-25 * k)
            return p, {'Bell': (1 + 0.18 * k, 1 + 0.18 * k, 1 - 0.08 * k)}
        if t < 0.6:
            k = (t - 0.45) / 0.15
            p = tentacles(0, 0, lift=-25 + 45 * k)
            p['Bell'] = rot(-LEFT, 14 * k)
            return p, {'Bell': (1.18 - 0.3 * k, 1.18 - 0.3 * k, 0.92 + 0.2 * k)}
        k = (t - 0.6) / 0.4
        p = tentacles(k * 6, 8 * (1 - k), lift=20 * (1 - k))
        p['Bell'] = rot(-LEFT, 14 * (1 - k))
        return p, {'Bell': (0.88 + 0.12 * k, 0.88 + 0.12 * k, 1.12 - 0.12 * k)}

    keyed('Attack', 1.0, attack_at, 30)

    def hit_at(t):
        k = math.sin(min(1.0, t / 0.32) * math.pi)
        p = tentacles(t * 40, 20 * k, lift=15 * k)
        p['Bell'] = rot(LEFT, -16 * k)
        return p, {'Bell': (1 - 0.12 * k, 1 - 0.12 * k, 1 + 0.1 * k)}

    keyed('Hit', 0.32, hit_at, 8)

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

if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = scene.render.resolution_y = 360
    world = bpy.data.worlds.new('w'); world.color = (0.75, 0.75, 0.75); scene.world = world
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); scene.collection.objects.link(sun)
    sun.rotation_euler = (0.7, 0.0, -0.6); sun.data.energy = 4
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); scene.collection.objects.link(cam); scene.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 1.3
    cam.location = Vector((2.6, -0.6, 0.9))
    cam.rotation_euler = (Vector((0, 0, 0.45)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    for track in armature.animation_data.nla_tracks:
        track.mute = True
    for name, seconds in (('Idle', 0.0), ('Idle', 0.125), ('Idle', 0.25), ('Idle', 0.375), ('Attack', 0.4), ('Attack', 0.6), ('Attack', 0.85), ('Hit', 0.16)):
        armature.animation_data.action = bpy.data.actions[name]
        scene.frame_set(1 + round(seconds * FPS))
        scene.render.filepath = os.path.join(PREVIEW, f'{NAME}_{name}_{seconds}.png')
        bpy.ops.render.render(write_still=True)
