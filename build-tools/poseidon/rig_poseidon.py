"""给 Tripo 文生 3D 的「海神波塞冬」建骨架、绑定权重并手写动作，导出带动画 GLB。

在 Blender 5.2 后台运行：
  blender -b --python rig_poseidon.py -- <输入 GLB> <输出 GLB> [--preview <目录>]
输入是 Tripo 原模型（最长边约 1、底部在原点、脸朝 -Y、Z 向上）：悬空姿势，双腿后屈下垂；右手（-X）握三叉神矛竖在身侧，
左手（+X）张开前伸；背后披风向两侧张开。

做法与 build-tools/dragon/rig_dragon.py 相同：
1. 关节取自网格剖面（2026-10-23 按切片质心与带坐标网格的正/侧视图求取）。
2. 每个顶点按部位限定候选骨骼，取最近两根按距离分权，再按位置焊接 UV 接缝后沿拓扑平滑；三叉神矛整体刚性挂在右手。
3. 动作在模型空间“前（-Y）/左（+X）/上（+Z）”上直接写关键帧；Godot 按模拟时间取样，不自走。
   动作名与 scripts/journey_poseidon_view.gd 对应。
"""
import bpy, sys, os, math
from mathutils import Vector, Quaternion, Matrix, kdtree

FPS = 30
FORWARD = Vector((0, -1, 0))
LEFT = Vector((1, 0, 0))
UP = Vector((0, 0, 1))
args = sys.argv[sys.argv.index('--') + 1:]
SOURCE, OUTPUT = args[0], args[1]
PREVIEW = args[args.index('--preview') + 1] if '--preview' in args else ''

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SOURCE)
mesh = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
world = mesh.matrix_world.copy()
mesh.parent = None
mesh.matrix_world = world
for other in list(bpy.context.scene.objects):
    if other != mesh:
        bpy.data.objects.remove(other)
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
verts = [v.co.copy() for v in mesh.data.vertices]

# —— 关节（模型坐标，左侧 +X）——
HIPS = Vector((0, -0.05, 0.46))
SPINE = Vector((0, -0.04, 0.58))
CHEST = Vector((0, -0.03, 0.70))
NECK = Vector((0, -0.04, 0.765))
HEAD = Vector((0, -0.04, 0.80))
CROWN = Vector((0, -0.04, 0.95))
ARMS = {  # 肩、肘、腕、手尖
    'L': [Vector((0.14, -0.03, 0.735)), Vector((0.28, -0.05, 0.635)), Vector((0.36, -0.12, 0.655)), Vector((0.43, -0.20, 0.685))],
    'R': [Vector((-0.14, -0.03, 0.735)), Vector((-0.27, -0.06, 0.63)), Vector((-0.33, -0.15, 0.635)), Vector((-0.36, -0.18, 0.63))],
}
LEGS = {  # 髋、膝、踝、脚尖（双腿后屈下垂，脚在身后）
    'L': [Vector((0.07, -0.06, 0.44)), Vector((0.10, -0.11, 0.26)), Vector((0.03, 0.10, 0.10)), Vector((0.02, 0.20, 0.02))],
    'R': [Vector((-0.07, -0.06, 0.44)), Vector((-0.09, -0.12, 0.26)), Vector((-0.03, 0.10, 0.10)), Vector((-0.02, 0.20, 0.02))],
}
CAPE = {  # 披风：肩后 → 中段 → 下摆角
    'L': [Vector((0.12, 0.06, 0.70)), Vector((0.30, 0.10, 0.48)), Vector((0.44, 0.08, 0.22))],
    'R': [Vector((-0.12, 0.06, 0.70)), Vector((-0.30, 0.10, 0.50)), Vector((-0.44, 0.08, 0.34))],
}
# 三叉神矛：矛杆从顶端（叉尖附近）到底端。
TRIDENT_TOP = Vector((-0.37, -0.19, 0.97))
TRIDENT_BOTTOM = Vector((-0.20, -0.17, 0.08))

armature_data = bpy.data.armatures.new('PoseidonRig')
armature = bpy.data.objects.new('PoseidonRig', armature_data)
bpy.context.scene.collection.objects.link(armature)
bpy.context.view_layer.objects.active = armature
bpy.ops.object.mode_set(mode='EDIT')
edit = armature_data.edit_bones


def bone(name, head, tail, parent=None, connect=False):
    b = edit.new(name)
    b.head, b.tail = head, tail
    b.align_roll(UP if abs((tail - head).normalized().dot(UP)) < 0.9 else FORWARD)
    if parent:
        b.parent = edit[parent]
        b.use_connect = connect
    return b


bone('Root', Vector((0, 0, 0)), Vector((0, 0, 0.1)))
bone('Hips', HIPS, SPINE, 'Root')
bone('Spine', SPINE, CHEST, 'Hips', True)
bone('Chest', CHEST, NECK, 'Spine', True)
bone('Neck', NECK, HEAD, 'Chest', True)
bone('Head', HEAD, CROWN, 'Neck', True)
for side in ('L', 'R'):
    s, e, w, t = ARMS[side]
    bone('UpperArm.' + side, s, e, 'Chest')
    bone('Forearm.' + side, e, w, 'UpperArm.' + side, True)
    bone('Hand.' + side, w, t, 'Forearm.' + side, True)
    h, k, a, toe = LEGS[side]
    bone('Thigh.' + side, h, k, 'Hips')
    bone('Shin.' + side, k, a, 'Thigh.' + side, True)
    bone('Foot.' + side, a, toe, 'Shin.' + side, True)
    c0, c1, c2 = CAPE[side]
    bone('Cape1.' + side, c0, c1, 'Chest')
    bone('Cape2.' + side, c1, c2, 'Cape1.' + side, True)
bpy.ops.object.mode_set(mode='OBJECT')

# —— 权重 ——
segments = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in armature_data.bones if b.name != 'Root'}
groups = {name: mesh.vertex_groups.new(name=name) for name in segments}


def segment_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def trident(v):
    if v.y > -0.08:
        return False
    if v.z > 0.78 and v.x < -0.24:
        return True
    # 正视图（x-z）上离矛杆直线的距离。
    a, b = Vector((TRIDENT_TOP.x, TRIDENT_TOP.z)), Vector((TRIDENT_BOTTOM.x, TRIDENT_BOTTOM.z))
    p = Vector((v.x, v.z))
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (a + ab * t - p).length < 0.035


def region(v):
    side = 'L' if v.x > 0 else 'R'
    ax = abs(v.x)
    if trident(v):
        return 'trident', 'R'
    if v.z > 0.76 and ax < 0.15:
        return 'head', side
    if v.z > 0.56 and ax < 0.11 and v.y < -0.1:
        return 'head', side  # 胡子随头
    if (v.y > 0.04 and v.z < 0.72 and ax > 0.06) or (ax > 0.22 and v.z < 0.56):
        return 'cape', side
    if ax > 0.17 and v.z > 0.55:
        return 'arm', side
    if v.z < 0.44:
        return 'leg', side
    return 'body', side


ALLOWED = {
    'head': {'Head', 'Neck'},
    'arm': {'UpperArm', 'Forearm', 'Hand', 'Chest'},
    'cape': {'Cape1', 'Cape2', 'Chest', 'Spine'},
    'leg': {'Thigh', 'Shin', 'Foot', 'Hips'},
    'body': {'Hips', 'Spine', 'Chest', 'Neck', 'UpperArm', 'Thigh', 'Cape1'},
}


def family(name):
    return name.split('.')[0]


kind_of = []
for index, v in enumerate(verts):
    kind, side = region(v)
    kind_of.append(kind)
    if kind == 'trident':
        groups['Hand.R'].add([index], 1.0, 'REPLACE')
        continue
    candidates = []
    for name, (a, b) in segments.items():
        if family(name) not in ALLOWED[kind]:
            continue
        if '.' in name and not name.endswith('.' + side):
            continue
        candidates.append((segment_distance(v, a, b), name))
    candidates.sort()
    if len(candidates) == 1:
        groups[candidates[0][1]].add([index], 1.0, 'REPLACE')
        continue
    (d0, n0), (d1, n1) = candidates[0], candidates[1]
    w0 = 1.0 / (d0 + 0.006) ** 4
    w1 = 1.0 / (d1 + 0.006) ** 4
    groups[n0].add([index], w0 / (w0 + w1), 'REPLACE')
    groups[n1].add([index], w1 / (w0 + w1), 'REPLACE')

# 焊接 UV 接缝后沿拓扑平滑（神矛不参与，保持刚性）。
weld, node_of = {}, []
for v in verts:
    key = (round(v.x * 20000), round(v.y * 20000), round(v.z * 20000))
    node_of.append(weld.setdefault(key, len(weld)))
count = len(weld)
neighbors = [set() for _ in range(count)]
for e in mesh.data.edges:
    a, b = node_of[e.vertices[0]], node_of[e.vertices[1]]
    if a != b:
        neighbors[a].add(b)
        neighbors[b].add(a)
weights = [dict() for _ in range(count)]
node_kind = [''] * count
for index, v in enumerate(mesh.data.vertices):
    node = weights[node_of[index]]
    node_kind[node_of[index]] = kind_of[index]
    for g in v.groups:
        name = mesh.vertex_groups[g.group].name
        node[name] = max(node.get(name, 0.0), g.weight)
for node in weights:
    total = sum(node.values()) or 1.0
    for name in node:
        node[name] /= total
ROUNDS = {'head': 3, 'arm': 4, 'cape': 8, 'leg': 6, 'body': 6, 'trident': 0}
for r in range(8):
    smoothed = []
    for n in range(count):
        if r >= ROUNDS[node_kind[n]] or not neighbors[n]:
            smoothed.append(weights[n])
            continue
        mix = {}
        for m in neighbors[n]:
            if node_kind[m] == 'trident':
                continue
            for name, w in weights[m].items():
                mix[name] = mix.get(name, 0.0) + w
        k = 0.6 / len(neighbors[n])
        out = {name: w * 0.4 for name, w in weights[n].items()}
        for name, w in mix.items():
            out[name] = out.get(name, 0.0) + w * k
        total = sum(out.values()) or 1.0
        smoothed.append({name: w / total for name, w in out.items()})
    weights = smoothed

# 焊接后仍不相连的小块（王冠尖、护腕宝石等）整体取最近主体顶点的权重，作为刚体跟随。
island = [-1] * count
islands = []
for start in range(count):
    if island[start] >= 0:
        continue
    stack, members = [start], []
    island[start] = len(islands)
    while stack:
        n = stack.pop()
        members.append(n)
        for m in neighbors[n]:
            if island[m] < 0:
                island[m] = len(islands)
                stack.append(m)
    islands.append(members)
main = max(range(len(islands)), key=lambda i: len(islands[i]))
positions = [None] * count
for index, v in enumerate(verts):
    positions[node_of[index]] = v
tree = kdtree.KDTree(len(islands[main]))
for n in islands[main]:
    tree.insert(positions[n], n)
tree.balance()
for number, members in enumerate(islands):
    if number == main or len(members) > 1500 or any(node_kind[n] == 'trident' for n in members):
        continue
    center = Vector()
    for n in members:
        center += positions[n]
    _, source, _ = tree.find(center / len(members))
    for n in members:
        weights[n] = dict(weights[source])
print('WELDED', count, 'ISLANDS', len(islands))

for g in list(mesh.vertex_groups):
    g.remove(list(range(len(verts))))
for index in range(len(verts)):
    node = sorted(weights[node_of[index]].items(), key=lambda kv: -kv[1])[:4]
    total = sum(w for _, w in node) or 1.0
    for name, w in node:
        if w / total > 0.002:
            groups[name].add([index], w / total, 'REPLACE')
modifier = mesh.modifiers.new('Armature', 'ARMATURE')
modifier.object = armature
mesh.parent = armature

# —— 动作 ——
rest = {b.name: b.matrix_local.to_quaternion() for b in armature_data.bones}
IDENTITY = Quaternion()


def rot(axis, degrees):
    return Quaternion(axis, math.radians(degrees))


def pitch(deg):  # 正值前倾 / 前摆（前方 -Y 转向 -Z）
    return rot(LEFT, deg)


def yaw(deg):  # 正值转向自身左侧（+X）
    return rot(UP, deg)


def lift(side, deg):  # 手臂侧举：正值向上抬（绕前后轴）
    return rot(Vector((0, 1, 0)), deg if side == 'R' else -deg)


def compose(*qs):
    out = Quaternion()
    for q in qs:
        out = q @ out
    return out


def merge(*parts):
    out = {}
    for p in parts:
        out.update(p)
    return out


def both(name, fn):
    return {name + '.L': fn('L'), name + '.R': fn('R')}


def key(action_name, frames):
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
    track = armature.animation_data.nla_tracks.new()
    track.name = action_name
    track.strips.new(action_name, 1, action)
    armature.animation_data.action = None


def grip(arm_lift, arm_pitch=0.0):
    """右手反向转回手臂的抬举与前摆，让神矛大体保持竖直（神矛整体挂在右手上）。"""
    return {'Hand.R': compose(pitch(-arm_pitch), lift('R', -arm_lift))}


def cape(phase, amount, lift_back=0.0):
    """披风：两侧下摆随相位前后翻动，越往下摆幅越大；lift_back 为整体向后扬起。"""
    out = {}
    for side, s in (('L', 1), ('R', -1)):
        out['Cape1.' + side] = compose(pitch(-lift_back * 0.5 - amount * 0.5 * math.sin(phase + s * 0.6)), lift(side, 3 * math.sin(phase)))
        out['Cape2.' + side] = pitch(-lift_back * 0.5 - amount * math.sin(phase - 0.8 + s * 0.6))
    return out


def legs(phase, amount, tuck=0.0):
    """双腿下垂轻摆；tuck 为收腿（膝盖上提）。"""
    out = {}
    for side, s in (('L', 1), ('R', -1)):
        swing = amount * math.sin(phase + s * 1.2)
        out['Thigh.' + side] = pitch(-swing - tuck)
        out['Shin.' + side] = pitch(swing * 0.6 + tuck * 1.2)
    return out


def idle_at(t):
    a = t / 4.0 * math.tau
    breath = math.sin(a)
    return merge({'Spine': pitch(2 * breath), 'Chest': pitch(-2 * breath), 'Head': compose(yaw(6 * math.sin(a * 0.5)), pitch(-2 * breath))},
                 both('UpperArm', lambda s: lift(s, 4 * math.sin(a + (0 if s == 'L' else 1.4)))),
                 both('Forearm', lambda s: pitch(-4 * math.sin(a + 0.7))),
                 cape(a * 2, 10, 6), legs(a, 6))


key('Idle', [(n * 0.25, idle_at(n * 0.25)) for n in range(17)])
CALM = idle_at(0.0)

# 举矛（1.6 秒，激流 / 巨浪 / 召唤前摇共用）：右臂把神矛高举过头，左手前伸蓄力，挺胸抬头。
raise_peak = merge({'Spine': pitch(-6), 'Chest': pitch(-8), 'Head': pitch(-10)},
                   {'UpperArm.R': lift('R', 70), 'Forearm.R': lift('R', 20)}, grip(80),
                   {'UpperArm.L': compose(pitch(-30), lift('L', 15)), 'Forearm.L': pitch(-15)},
                   cape(0.5, 6, 18), legs(0, 4, 8))
key('Raise', [(0, CALM), (0.5, merge(raise_peak, {'Chest': pitch(-4)})), (0.9, raise_peak),
              (1.2, merge(raise_peak, {'Head': pitch(-14)})), (1.6, raise_peak)])

# 掷矛激流（1.0 秒）：神矛从头顶向前下方猛刺，身体前压，披风后扬。
thrust_out = merge({'Spine': pitch(14), 'Chest': pitch(10), 'Head': pitch(8)},
                   {'UpperArm.R': compose(lift('R', 20), pitch(55)), 'Forearm.R': pitch(10)}, grip(20),
                   {'UpperArm.L': compose(lift('L', 30), pitch(-10))},
                   cape(1.5, 8, 26), legs(0, 4, -6))
key('Thrust', [(0, raise_peak), (0.15, merge(raise_peak, {'UpperArm.R': lift('R', 85)}, grip(95))), (0.35, thrust_out), (0.7, thrust_out), (1.0, CALM)])

# 顿矛（1.4 秒，震环 / 入场收尾）：双手握矛高举 → 向下猛顿水面，身体下压。
slam_up = merge({'Spine': pitch(-10), 'Chest': pitch(-8), 'Head': pitch(-12)},
                {'UpperArm.R': lift('R', 95), 'Forearm.R': lift('R', 10)}, grip(100),
                {'UpperArm.L': compose(lift('L', 70), pitch(-20)), 'Forearm.L': pitch(-30)},
                cape(0, 6, 10), legs(0, 4, 12))
slam_down = merge({'Spine': pitch(20), 'Chest': pitch(16), 'Head': pitch(10)},
                  {'UpperArm.R': compose(lift('R', 10), pitch(30)), 'Forearm.R': pitch(-10)}, grip(10),
                  {'UpperArm.L': compose(lift('L', -10), pitch(30))},
                  cape(2.0, 10, 30), legs(0, 4, -10))
key('Slam', [(0, CALM), (0.6, slam_up), (0.85, slam_up), (1.0, slam_down), (1.2, slam_down), (1.4, CALM)])

# 召唤（1.6 秒）：双臂向两侧张开上扬、仰头。
summon_peak = merge({'Spine': pitch(-8), 'Chest': pitch(-10), 'Head': pitch(-16)},
                    both('UpperArm', lambda s: lift(s, 40)), both('Forearm', lambda s: lift(s, 15)), grip(50),
                    cape(1.0, 8, 20), legs(0, 6, 6))
key('Summon', [(0, CALM), (0.6, summon_peak), (1.0, merge(summon_peak, {'Head': pitch(-20)})), (1.6, summon_peak)])

# 横挥（1.6 秒，巨浪）：左臂从右侧横扫到左侧，身体随之扭转。
def sweep_pose(k):
    return merge({'Spine': yaw(-20 + 40 * k), 'Chest': yaw(-10 + 20 * k), 'Head': yaw(-10 + 20 * k)},
                 {'UpperArm.L': compose(pitch(-60), yaw(-50 + 100 * k)), 'Forearm.L': pitch(-10)},
                 {'UpperArm.R': lift('R', 30)}, grip(30), cape(k * 3, 8, 14), legs(k, 5))


key('Sweep', [(0, CALM), (0.6, sweep_pose(0)), (1.0, sweep_pose(1.0)), (1.3, sweep_pose(1.05)), (1.6, CALM)])

# 凝聚潮汐之心（循环 2 秒）：双手高举头顶托着水球，身体后仰微颤。
def channel_at(t):
    a = t / 2.0 * math.tau
    shake = math.sin(a * 3)
    return merge({'Spine': pitch(-8 + shake), 'Chest': pitch(-10), 'Head': pitch(-22 + shake)},
                 both('UpperArm', lambda s: lift(s, 115 + 3 * shake)), both('Forearm', lambda s: lift(s, 25)), grip(130),
                 cape(a, 10, 16), legs(a, 4, 6))


key('Channel', [(n * 0.25, channel_at(n * 0.25)) for n in range(9)])

# 震落（硬直，循环）：被炸落到水面，前屈垂头、双臂无力下垂；0.5 秒后进入 0.5–2.5 循环段。
slumped = merge({'Hips': pitch(10), 'Spine': pitch(26), 'Chest': pitch(18), 'Head': pitch(30)},
                both('UpperArm', lambda s: lift(s, -35)), both('Forearm', lambda s: pitch(20)), grip(-35, 20),
                cape(0, 4, -4), legs(0, 2, -16))
struggle = merge(slumped, {'Spine': compose(pitch(18), rot(FORWARD, 6)), 'Head': compose(pitch(16), yaw(14))},
                 {'UpperArm.L': lift('L', -10)})
key('Stagger', [(0, merge(summon_peak, {'Spine': pitch(-20)})), (0.5, slumped), (1.2, struggle), (1.9, slumped), (2.5, slumped)])

# 倒下（3 秒）：仰天长啸 → 后仰、双臂摊开沉下。
death = merge({'Hips': pitch(-30), 'Spine': pitch(-30), 'Chest': pitch(-20), 'Head': pitch(-30)},
              both('UpperArm', lambda s: lift(s, 60)), both('Forearm', lambda s: lift(s, 20)), grip(60),
              cape(0, 4, 40), legs(0, 4, -20))
key('Death', [(0, CALM), (0.6, summon_peak), (1.2, merge(summon_peak, {'Head': pitch(-30)})), (2.4, death), (3.0, death)])

# 破水升起（入场，3 秒）：蜷身抱膝 → 舒展身体、双臂张开 → 回到待机。
curled = merge({'Hips': pitch(20), 'Spine': pitch(40), 'Chest': pitch(24), 'Head': pitch(30)},
               both('UpperArm', lambda s: compose(lift(s, -40), pitch(40))), both('Forearm', lambda s: pitch(60)), grip(-40, 100),
               cape(0, 2, -20), legs(0, 0, 40))
key('Rise', [(0, curled), (1.0, curled), (1.8, merge(summon_peak, {'Head': pitch(-6)})), (2.4, summon_peak), (3.0, CALM)])

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

if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = scene.render.resolution_y = 360
    world = bpy.data.worlds.new('w'); world.color = (0.75, 0.75, 0.75); scene.world = world
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); scene.collection.objects.link(sun)
    sun.rotation_euler = (0.7, 0.0, -0.6); sun.data.energy = 4
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); scene.collection.objects.link(cam); scene.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 1.4
    cam.location = Vector((0.8, -2.6, 1.0))
    cam.rotation_euler = (Vector((0, 0, 0.5)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    for track in armature.animation_data.nla_tracks:
        track.mute = True
    for name, seconds in (('Idle', 0.0), ('Raise', 1.0), ('Thrust', 0.4), ('Slam', 0.8), ('Slam', 1.05), ('Summon', 1.0),
                          ('Sweep', 1.0), ('Channel', 0.5), ('Stagger', 1.2), ('Death', 2.6), ('Rise', 0.5), ('Rise', 2.0)):
        armature.animation_data.action = bpy.data.actions[name]
        scene.frame_set(1 + round(seconds * FPS))
        scene.render.filepath = os.path.join(PREVIEW, f'poseidon_{name}_{seconds}.png')
        bpy.ops.render.render(write_still=True)
