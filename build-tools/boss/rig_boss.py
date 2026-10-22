"""给 Tripo 文生 3D 的「枯根巨像」自动建上半身骨架、绑定权重并手写动作，导出带动画 GLB。

在 Blender 5.2 后台运行：
  blender -b --python rig_boss.py -- <输出 GLB> [--preview <目录>]
输入固定为 build-tools/boss/source/root_colossus.glb（Tripo 原模型，最长边 1、脚底在原点、正前方 +X、Z 向上）。

做法：
1. 从网格推关节：|y| 较大且离地较高的顶点归为左右手臂，按高度分桶取质心得到肩、肘、手；
   躯干按高度切出腰、胸、颈、头。下半身根团（离地 0.30 以下）只挂在不动的 Root 上，保证扎根不滑动。
2. 不用 Blender 自动权重（Tripo 网格常有非流形面）；每个顶点按到骨段的距离取最近两根骨骼混合，
   再沿网格拓扑平滑权重。手和根团的网格连在一起，硬边界会在抬手时拉出细长“丝”；平滑后过渡分散到一片区域。
3. 动作在模型空间“前/侧/上”三个轴上直接写关键帧，带预备、过冲、回落与头部/手的跟随延迟，
   名称与 journey_boss_view.gd 对应：Idle、Roar、Emerge、ClawSwipe、RoarSky、Slam、SweepL、SweepR、Throw、Root、Stagger、Death。
   Godot 按模拟时间直接取样，不自走。
"""
import bpy, sys, os, math
from mathutils import Vector, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, 'source', 'root_colossus.glb')
FPS = 30
# Tripo 原模型的脸、眼睛和胸口发光树心都朝 +X（2026-10-22 渲染核对；此前误作 -X，游戏里背对玩家）。
FORWARD = Vector((1, 0, 0))
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

# —— 权重：到骨段的距离取最近两根，再沿拓扑平滑；贴地根团固定在 Root ——
segments = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in armature_data.bones}
groups = {name: mesh.vertex_groups.new(name=name) for name in segments}


def segment_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


pinned = []
raw_arm = [False] * len(verts)
for index, v in enumerate(verts):
    arm_side = 'L' if v.y > 0 else 'R'
    arm_reach = min(segment_distance(v, *segments[n + '.' + arm_side]) for n in ('UpperArm', 'Forearm', 'Hand'))
    armish = v.z > 0.18 and abs(v.y) > 0.15 and (arm_reach < 0.12 or (abs(v.y) > 0.28 and v.z > 0.2))
    # 手爪尖垂得比手腕低：靠近手骨的低处顶点也归手臂，否则抬手时爪尖被钉在地上拉长。
    claw = abs(v.y) > 0.24 and v.z > 0.05 and segment_distance(v, *segments['Hand.' + arm_side]) < 0.12
    armish = armish or claw
    raw_arm[index] = armish
    if v.z < BASE - 0.04 and not armish:
        groups['Root'].add([index], 1.0, 'REPLACE')
        if v.z < 0.08:
            pinned.append(index)
        continue
    candidates = []
    for name, (a, b) in segments.items():
        if armish and not name.endswith('.' + arm_side) and name != 'Chest':
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

# 左手在原模型里贴着根团，两边网格连在一起；抬手时中间会拉出一张膜。在平滑之前，
# 把离地较低、一端归手臂一端归根团的边（及其面）删掉：平滑不会跨过切口，抬手时手干净地离开根团。
import bmesh
cut_pairs = set()
for e in mesh.data.edges:
    a, b = e.vertices
    if raw_arm[a] != raw_arm[b] and max(verts[a].z, verts[b].z) < 0.34 and min(abs(verts[a].y), abs(verts[b].y)) > 0.18:
        cut_pairs.add((min(a, b), max(a, b)))
bm = bmesh.new()
bm.from_mesh(mesh.data)
bm.faces.ensure_lookup_table()
bridge = [f for f in bm.faces if any((min(e.verts[0].index, e.verts[1].index), max(e.verts[0].index, e.verts[1].index)) in cut_pairs for e in f.edges)]
bmesh.ops.delete(bm, geom=bridge, context='FACES_ONLY')
bm.to_mesh(mesh.data)
bm.free()
print('BRIDGE CUT edges', len(cut_pairs), 'faces', len(bridge))

# 沿网格拓扑平滑全部骨骼权重：手与根团相连处、肩部与胸口的分界变成渐变，不再拉出细丝。
# Tripo 导出的网格在每条 UV 接缝处都拆开了顶点（近九百块），先按位置焊接成拓扑图再平滑，最后写回每个顶点。
from mathutils import kdtree
weld = {}
node_of = []
for v in verts:
    key = (round(v.x * 20000), round(v.y * 20000), round(v.z * 20000))
    node_of.append(weld.setdefault(key, len(weld)))
count = len(weld)
neighbors = [set() for _ in range(count)]
for e in mesh.data.edges:
    if (min(e.vertices), max(e.vertices)) in cut_pairs:
        continue
    a, b = node_of[e.vertices[0]], node_of[e.vertices[1]]
    if a != b:
        neighbors[a].add(b)
        neighbors[b].add(a)
names = list(segments)
weights = [dict() for _ in range(count)]
for index, v in enumerate(mesh.data.vertices):
    node = weights[node_of[index]]
    for g in v.groups:
        name = mesh.vertex_groups[g.group].name
        node[name] = max(node.get(name, 0.0), g.weight)
for node in weights:
    total = sum(node.values()) or 1.0
    for name in node:
        node[name] /= total
pinned_nodes = {node_of[i] for i in pinned}
for _ in range(14):
    smoothed = []
    for n in range(count):
        if n in pinned_nodes or not neighbors[n]:
            smoothed.append(weights[n])
            continue
        mix = {}
        for m in neighbors[n]:
            for name, w in weights[m].items():
                mix[name] = mix.get(name, 0.0) + w
        k = 0.6 / len(neighbors[n])
        out = {name: w * 0.4 for name, w in weights[n].items()}
        for name, w in mix.items():
            out[name] = out.get(name, 0.0) + w * k
        smoothed.append(out)
    weights = smoothed

# 焊接后仍不相连的小块（爪尖、碎叶）整体取最近主体顶点的权重，作为刚体跟随，抬手时不和手分开。
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
rigid = 0
for number, members in enumerate(islands):
    if number == main or len(members) > 1500:
        continue
    _, source, _ = tree.find(centroid([positions[n] for n in members]))
    for n in members:
        weights[n] = dict(weights[source])
    rigid += 1
print('WELDED', count, 'ISLANDS', len(islands), 'rigid', rigid)

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
# 在模型空间（静止姿势的骨架空间）写“相对父骨骼”的旋转：q_local = R^-1 · q · R。
rest = {b.name: b.matrix_local.to_quaternion() for b in armature_data.bones}
IDENTITY = Quaternion()


def world_rot(axis, degrees):
    return Quaternion(axis, math.radians(degrees))


def lean(deg):  # 正值向前（+X）俯身
    return world_rot(SIDE, deg)


def raise_side(side, deg):  # 手臂向身体外侧、向上抬
    return world_rot(FORWARD, deg * (1 if side == 'L' else -1))


def swing_front(side, deg):  # 手臂绕竖直轴摆向身前（+X）
    return world_rot(UP, deg * (-1 if side == 'L' else 1))


def reach_forward(deg):  # 垂下的手臂向前上方抬
    return world_rot(SIDE, -deg)


def twist(deg):  # 上身绕竖直轴转
    return world_rot(UP, deg)


def tilt(deg):  # 侧倾
    return world_rot(FORWARD, -deg)


def compose(*qs):
    out = Quaternion()
    for q in qs:
        out = q @ out
    return out


def pose(**rotations):
    # 关键字参数里用 UpperArm_L 表示骨骼 UpperArm.L。
    return {name.replace('_', '.'): q for name, q in rotations.items()}


def key(action_name, frames):
    """frames: [(秒, {骨骼: 模型空间旋转})]。未列出的骨骼回到静止姿势；关键帧为贝塞尔缓入缓出。"""
    action = bpy.data.actions.new(action_name)
    armature.animation_data_create()
    armature.animation_data.action = action
    names = [b.name for b in armature_data.bones]
    for seconds, rotations in frames:
        rotations = dict(rotations)
        # 大角度抬臂分给锁骨 35%、上臂 65%，肩部蒙皮按两段过渡。
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
            # roll.<骨骼>：绕骨骼自身长轴（局部 Y）旋转，用于前臂、手腕的内外翻（掌心朝上/朝下）。
            roll = Quaternion(Vector((0, 1, 0)), math.radians(rotations.get('roll.' + name, 0.0)))
            pb.rotation_quaternion = r.inverted() @ q @ r @ roll
            pb.keyframe_insert('rotation_quaternion', frame=frame, group=name)
    track = armature.animation_data.nla_tracks.new()
    track.name = action_name
    track.strips.new(action_name, 1, action)
    armature.animation_data.action = None
    return action


def lag(frames, bones, delay):
    """跟随：指定骨骼取 delay 秒之前那一关键帧的姿势，模拟头部、手腕的惯性滞后。"""
    out = []
    for t, p in frames:
        p = dict(p)
        earlier = [q for (s, q) in frames if s <= t - delay]
        for b in bones:
            p[b] = earlier[-1].get(b, IDENTITY) if earlier else IDENTITY
        out.append((t, p))
    return out


# 待机：6 秒循环。呼吸起伏、头缓慢环视、双臂错相摆动、上身轻微侧晃，避免木桩感。
def idle_at(t):
    a = t / 6.0 * math.tau
    breath = math.sin(a * 2)
    return pose(Spine=compose(tilt(1.5 * math.sin(a)), lean(1.5 + breath * 1.5)),
                Chest=compose(lean(breath * 2.5), twist(3 * math.sin(a))),
                Neck=compose(twist(9 * math.sin(a + 0.6)), lean(-breath * 1.5)),
                Head=compose(twist(6 * math.sin(a + 1.1)), tilt(3 * math.sin(a))),
                UpperArm_L=compose(raise_side('L', 4 + 4 * math.sin(a * 2 + 0.4)), swing_front('L', 5 * math.sin(a))),
                UpperArm_R=compose(raise_side('R', 4 + 4 * math.sin(a * 2 + 2.0)), swing_front('R', -5 * math.sin(a + 0.8))),
                Forearm_L=reach_forward(6 + 5 * math.sin(a * 2 - 0.5)),
                Forearm_R=reach_forward(6 + 5 * math.sin(a * 2 + 1.1)),
                Hand_L=reach_forward(8 * math.sin(a * 2 - 1.0)),
                Hand_R=reach_forward(8 * math.sin(a * 2 + 0.6)))


key('Idle', [(n * 0.5, idle_at(n * 0.5)) for n in range(13)])

# 怒吼：下沉蓄力 → 挺胸张臂仰头 → 颤抖保持 → 回落。
roar_crouch = pose(Spine=lean(12), Chest=lean(14), Neck=lean(10), Head=lean(8),
                   UpperArm_L=compose(raise_side('L', -6), reach_forward(10)), UpperArm_R=compose(raise_side('R', -6), reach_forward(10)),
                   Forearm_L=reach_forward(25), Forearm_R=reach_forward(25))
roar_peak = pose(Spine=lean(-8), Chest=lean(-16), Neck=lean(-16), Head=lean(-18),
                 UpperArm_L=raise_side('L', 40), UpperArm_R=raise_side('R', 40),
                 Forearm_L=raise_side('L', 18), Forearm_R=raise_side('R', 18),
                 Hand_L=raise_side('L', 15), Hand_R=raise_side('R', 15))
roar_shake = pose(Spine=lean(-7), Chest=compose(lean(-14), twist(3)), Neck=lean(-18), Head=compose(lean(-20), twist(-4)),
                  UpperArm_L=raise_side('L', 43), UpperArm_R=raise_side('R', 37),
                  Forearm_L=raise_side('L', 22), Forearm_R=raise_side('R', 14),
                  Hand_L=raise_side('L', 18), Hand_R=raise_side('R', 12))
key('Roar', [(0, pose()), (0.35, roar_crouch), (0.62, roar_peak), (0.9, roar_shake), (1.2, roar_peak), (1.5, roar_shake),
             (1.8, roar_peak), (2.2, pose())])

# 破土绽放（4.6 秒）：0–3 秒像花苞一样向前蜷成一团、双臂抱在身前、头埋进胸口，随升起微微颤抖；
# 3–4.4 秒缓慢舒展，双臂向两侧张到最开，同时上身后仰、头仰起，像野兽被释放、花苞绽放；之后停在张开姿势。
def curled(tremble):
    return pose(Spine=compose(lean(40 + tremble), tilt(tremble * 0.6)), Chest=compose(lean(34 - tremble), twist(tremble)),
                Neck=lean(26), Head=compose(lean(24 + tremble), twist(-tremble)),
                UpperArm_L=compose(reach_forward(42), swing_front('L', 62 + tremble), raise_side('L', -6)),
                UpperArm_R=compose(reach_forward(42), swing_front('R', 62 - tremble), raise_side('R', -6)),
                Forearm_L=compose(swing_front('L', 48), reach_forward(20)), Forearm_R=compose(swing_front('R', 48), reach_forward(20)),
                Hand_L=compose(reach_forward(-35), swing_front('L', 20)), Hand_R=compose(reach_forward(-35), swing_front('R', 20)))


# 掌心朝上：前臂与手腕向外翻转（左右镜像），像花瓣向上打开。
# 方向经两种符号渲染比对确定（-1 时掌心与张开的手指朝上）。
SUPINATE = -1.0


def palms_up(amount):
    return {'roll.Forearm.L': SUPINATE * 55 * amount, 'roll.Hand.L': SUPINATE * 60 * amount,
            'roll.Forearm.R': -SUPINATE * 55 * amount, 'roll.Hand.R': -SUPINATE * 60 * amount}


def bloom(settle):
    p = pose(Spine=lean(-14 + settle), Chest=lean(-24 + settle), Neck=lean(-18), Head=lean(-26 + settle),
             UpperArm_L=compose(raise_side('L', 76 - settle), swing_front('L', -24)),
             UpperArm_R=compose(raise_side('R', 76 - settle), swing_front('R', -24)),
             Forearm_L=compose(raise_side('L', 22), swing_front('L', -8)), Forearm_R=compose(raise_side('R', 22), swing_front('R', -8)),
             Hand_L=raise_side('L', 28), Hand_R=raise_side('R', 28))
    p.update(palms_up(1.0))
    return p


EMERGE_BLOOM = bloom(3)
key('Emerge', lag([(0, curled(0)), (0.5, curled(2)), (1.0, curled(-2)), (1.5, curled(2)), (2.0, curled(-2)), (2.5, curled(2)), (3.0, curled(0)),
                   (3.45, pose(Spine=lean(22), Chest=lean(14), Neck=lean(10), Head=lean(6),
                               UpperArm_L=compose(reach_forward(30), swing_front('L', 20), raise_side('L', 25)),
                               UpperArm_R=compose(reach_forward(30), swing_front('R', 20), raise_side('R', 25)))),
                   (3.9, dict(pose(Spine=lean(2), Chest=lean(-8), Neck=lean(-6), Head=lean(-10),
                                   UpperArm_L=compose(raise_side('L', 58), swing_front('L', -8)), UpperArm_R=compose(raise_side('R', 58), swing_front('R', -8)),
                                   Forearm_L=raise_side('L', 14), Forearm_R=raise_side('R', 14)), **palms_up(0.6))),
                   (4.4, bloom(0)), (4.6, EMERGE_BLOOM)],
                  ['Head', 'Hand.L', 'Hand.R', 'Forearm.L', 'Forearm.R'], 0.08))

# 挥爪抓人（入场破土后，2.6 秒）：左爪先向外后方大幅蓄力，再以抓取的姿势横扫过身前、甩过头；
# 右爪紧接着镜像一次。上身随挥爪大幅拧转前扑，头追着爪子看，爪尖收拢如抓物。
# 掌心领路：挥动的手臂前臂和手腕外翻约 90°（掌心朝上的一半），侧举时掌心朝前、横扫时朝着扫过的方向，
# 手腕向掌心一侧勾起抓取，而不是向下耷拉、用手背或手缘带着走。
def palm_lead(s, amount=1.0):
    sign = 1 if s == 'L' else -1
    return {'roll.Forearm.' + s: SUPINATE * sign * 45 * amount, 'roll.Hand.' + s: SUPINATE * sign * 45 * amount}


def claw_wind(s):
    sign = 1 if s == 'L' else -1
    o = 'R' if s == 'L' else 'L'
    return dict(pose(Spine=compose(twist(18 * sign), lean(-6)), Chest=compose(twist(30 * sign), lean(-12)), Neck=twist(-10 * sign),
                Head=compose(twist(-16 * sign), lean(-8)),
                **{'UpperArm_' + s: compose(raise_side(s, 72), swing_front(s, -50)), 'Forearm_' + s: compose(raise_side(s, 25), reach_forward(20)),
                   'Hand_' + s: compose(raise_side(s, 20), swing_front(s, -10)),
                   'UpperArm_' + o: compose(raise_side(o, 20), reach_forward(25)), 'Forearm_' + o: reach_forward(25)}), **palm_lead(s))


def claw_strike(s, extra=0):
    sign = 1 if s == 'L' else -1
    o = 'R' if s == 'L' else 'L'
    # 从侧上方（蓄力位）斜向下扫到身前中间偏下：落点比最初略高（外展 30°→40°），前臂顺直，
    # 手腕不再向下勾，爪尖顺着扫下的方向伸出而不是指地。
    return pose(Spine=compose(twist(-16 * sign - extra * 0.3 * sign), lean(14)), Chest=compose(twist(-30 * sign - extra * 0.5 * sign), lean(22)),
                Neck=compose(twist(12 * sign), lean(4)), Head=compose(twist(18 * sign), lean(8)),
                **{'UpperArm_' + s: compose(raise_side(s, 40), swing_front(s, 95 + extra), reach_forward(28)),
                   'Forearm_' + s: swing_front(s, 30),
                   'Hand_' + s: swing_front(s, 20 + extra * 0.5),
                   'UpperArm_' + o: compose(raise_side(o, 28), swing_front(o, -20)), 'Forearm_' + o: raise_side(o, 15)}) | palm_lead(s)


crouch = roar_crouch
# 起始姿势与 Emerge 结尾一致，绽放后直接接挥爪，不经过回弹到下蹲的跳变。
key('ClawSwipe', lag([(0, EMERGE_BLOOM), (0.35, claw_wind('L')), (0.62, claw_strike('L')), (0.8, claw_strike('L', 18)),
                      (1.1, pose(Chest=lean(10), UpperArm_L=compose(raise_side('L', 35), swing_front('L', 60)))),
                      (1.4, claw_wind('R')), (1.67, claw_strike('R')), (1.85, claw_strike('R', 18)),
                      (2.25, pose(Chest=lean(8), UpperArm_R=compose(raise_side('R', 30), swing_front('R', 50)))), (2.6, pose())],
                     ['Head', 'Hand.L', 'Hand.R'], 0.05))

# 仰天咆哮（2.2 秒）：吸气下沉 → 猛地后仰、头甩向天、双臂向后上方张开 → 颤抖保持 → 回落前倾。
sky_inhale = pose(Spine=lean(14), Chest=lean(18), Neck=lean(12), Head=lean(12),
                  UpperArm_L=compose(raise_side('L', 10), reach_forward(20)), UpperArm_R=compose(raise_side('R', 10), reach_forward(20)),
                  Forearm_L=reach_forward(30), Forearm_R=reach_forward(30), Hand_L=reach_forward(20), Hand_R=reach_forward(20))


def sky_peak(shake):
    # 躯干后仰保持较小（约 25°），只把颈和头再抬高一些：头仰向天空，又不会躲到胸口后面，正面低机位仍看得到脸和张开的嘴。
    return dict(pose(Spine=lean(-9 + shake), Chest=compose(lean(-16 - shake), twist(2 * shake)), Neck=lean(-18), Head=compose(lean(-28 + shake), twist(-2 * shake)),
                UpperArm_L=compose(raise_side('L', 52 + 2 * shake), swing_front('L', -30)),
                UpperArm_R=compose(raise_side('R', 52 - 2 * shake), swing_front('R', -30)),
                Forearm_L=compose(raise_side('L', 25), swing_front('L', -10)), Forearm_R=compose(raise_side('R', 25), swing_front('R', -10)),
                Hand_L=raise_side('L', 25 + 4 * shake), Hand_R=raise_side('R', 25 - 4 * shake)), **palms_up(0.8))


key('RoarSky', [(0, pose()), (0.32, sky_inhale), (0.55, sky_peak(0)), (0.72, sky_peak(1.5)), (0.9, sky_peak(-1.5)), (1.08, sky_peak(1.5)),
                (1.26, sky_peak(-1.5)), (1.44, sky_peak(1.5)), (1.62, sky_peak(-1)), (1.8, sky_peak(0)),
                (2.2, pose(Spine=lean(6), Chest=lean(8), Head=lean(4)))])

# 单臂插地（根刺，用 R 臂）：0–0.6 拧身举臂蓄力 → 0.6–0.72 砸地 → 0.9 回弹 → 停住 → 拔出收回。
slam_wind = pose(Spine=compose(lean(-6), twist(14)), Chest=compose(lean(-10), twist(12)), Head=compose(lean(-4), twist(-8)),
                 UpperArm_R=compose(reach_forward(75), raise_side('R', 20)), Forearm_R=reach_forward(25), Hand_R=reach_forward(15),
                 UpperArm_L=raise_side('L', 12))
slam_hit = pose(Spine=compose(lean(18), twist(-10)), Chest=compose(lean(22), twist(-8)), Neck=lean(6), Head=lean(12),
                UpperArm_R=compose(reach_forward(62), raise_side('R', -5)), Forearm_R=reach_forward(-15), Hand_R=reach_forward(-20),
                UpperArm_L=compose(raise_side('L', 18), reach_forward(10)))
slam_settle = pose(Spine=compose(lean(15), twist(-8)), Chest=compose(lean(19), twist(-6)), Neck=lean(4), Head=lean(8),
                   UpperArm_R=compose(reach_forward(64), raise_side('R', -3)), Forearm_R=reach_forward(-10), Hand_R=reach_forward(-15),
                   UpperArm_L=compose(raise_side('L', 14), reach_forward(6)))
key('Slam', lag([(0, pose()), (0.3, pose(Chest=twist(6), UpperArm_R=reach_forward(30))), (0.6, slam_wind), (0.72, slam_hit),
                 (0.9, slam_settle), (1.5, slam_settle), (1.75, pose(Chest=lean(6), UpperArm_R=reach_forward(30))), (2.0, pose())],
                ['Head'], 0.08))


# 横扫：外展拧身蓄力 → 绕竖直轴贴地扫过身前 → 甩过头再回弹 → 收回。
def sweep(s):
    sign = 1 if s == 'L' else -1
    wind = pose(Spine=twist(16 * sign), Chest=compose(twist(18 * sign), lean(-4)), Head=twist(-10 * sign),
                **{'UpperArm_' + s: compose(raise_side(s, 48), swing_front(s, -28)), 'Forearm_' + s: raise_side(s, 14), 'Hand_' + s: raise_side(s, 10)})
    mid = pose(Spine=compose(twist(-6 * sign), lean(12)), Chest=compose(twist(-10 * sign), lean(14)), Head=twist(4 * sign),
               **{'UpperArm_' + s: compose(raise_side(s, 22), swing_front(s, 50), reach_forward(18)), 'Forearm_' + s: swing_front(s, 18)})
    end = pose(Spine=compose(twist(-22 * sign), lean(10)), Chest=compose(twist(-26 * sign), lean(12)), Head=twist(-12 * sign),
               **{'UpperArm_' + s: compose(raise_side(s, 18), swing_front(s, 82)), 'Forearm_' + s: swing_front(s, 26), 'Hand_' + s: swing_front(s, 15)})
    over = pose(Spine=compose(twist(-25 * sign), lean(11)), Chest=compose(twist(-29 * sign), lean(13)), Head=twist(-14 * sign),
                **{'UpperArm_' + s: compose(raise_side(s, 16), swing_front(s, 86)), 'Forearm_' + s: swing_front(s, 30), 'Hand_' + s: swing_front(s, 20)})
    return lag([(0, pose()), (0.35, pose(Chest=twist(8 * sign), **{'UpperArm_' + s: raise_side(s, 20)})), (0.7, wind), (0.85, mid),
                (1.0, end), (1.12, over), (1.5, end), (2.0, pose())], ['Head', 'Hand.' + s], 0.06)


key('SweepL', sweep('L'))
key('SweepR', sweep('R'))

# 抛掷孢果：后仰双臂举到肩后蓄力 → 向前甩出 → 前冲回落。
throw_back = pose(Spine=lean(-10), Chest=lean(-18), Neck=lean(-8), Head=lean(-10),
                  UpperArm_L=compose(reach_forward(72), raise_side('L', 18)), UpperArm_R=compose(reach_forward(72), raise_side('R', 18)),
                  Forearm_L=reach_forward(30), Forearm_R=reach_forward(30), Hand_L=reach_forward(20), Hand_R=reach_forward(20))
throw_out = pose(Spine=lean(12), Chest=lean(18), Neck=lean(4), Head=lean(6),
                 UpperArm_L=reach_forward(55), UpperArm_R=reach_forward(55),
                 Forearm_L=reach_forward(-10), Forearm_R=reach_forward(-10), Hand_L=reach_forward(-15), Hand_R=reach_forward(-15))
key('Throw', lag([(0, pose()), (0.35, pose(Spine=lean(-4), Chest=lean(-6))), (0.7, throw_back), (0.84, throw_out),
                  (1.0, pose(Spine=lean(14), Chest=lean(20), UpperArm_L=reach_forward(50), UpperArm_R=reach_forward(50))),
                  (1.3, throw_out), (1.8, pose())], ['Head', 'Hand.L', 'Hand.R'], 0.07))

# 扎根汲取：双臂举起 → 猛插入地 → 抽吸时上身起伏（0.8–2.0 循环段首尾一致）。
root_lift = pose(Chest=lean(-10), Head=lean(-8), UpperArm_L=reach_forward(70), UpperArm_R=reach_forward(70),
                 Forearm_L=reach_forward(20), Forearm_R=reach_forward(20))
root_hold = pose(Spine=lean(22), Chest=lean(24), Neck=lean(-10), Head=lean(-8),
                 UpperArm_L=compose(reach_forward(55), raise_side('L', -5)), UpperArm_R=compose(reach_forward(55), raise_side('R', -5)),
                 Forearm_L=reach_forward(-15), Forearm_R=reach_forward(-15))
root_pull = pose(Spine=lean(18), Chest=lean(18), Neck=lean(-14), Head=lean(-14),
                 UpperArm_L=compose(reach_forward(52), raise_side('L', -3)), UpperArm_R=compose(reach_forward(52), raise_side('R', -3)),
                 Forearm_L=reach_forward(-12), Forearm_R=reach_forward(-12))
key('Root', [(0, pose()), (0.5, root_lift), (0.72, root_hold), (0.8, root_hold), (1.4, root_pull), (2.0, root_hold)])

# 硬直：被灼断后先猛一仰、随即前扑跪倒，之后上身无力起伏（0.35–2.0 循环段首尾一致）。
stagger = pose(Spine=lean(32), Chest=lean(26), Neck=lean(16), Head=lean(18),
               UpperArm_L=compose(reach_forward(30), raise_side('L', -12)), UpperArm_R=compose(reach_forward(30), raise_side('R', -12)),
               Forearm_L=reach_forward(-30), Forearm_R=reach_forward(-30))
stagger_sway = pose(Spine=compose(lean(29), tilt(4)), Chest=compose(lean(23), twist(5)), Neck=lean(19), Head=compose(lean(22), tilt(-6)),
                    UpperArm_L=compose(reach_forward(26), raise_side('L', -9)), UpperArm_R=compose(reach_forward(33), raise_side('R', -15)),
                    Forearm_L=reach_forward(-26), Forearm_R=reach_forward(-34))
key('Stagger', [(0, pose(Chest=lean(-12), Head=lean(-16))), (0.2, pose(Spine=lean(36), Chest=lean(30), Head=lean(22))), (0.35, stagger),
                (1.2, stagger_sway), (2.0, stagger)])

death = pose(Spine=compose(lean(38), tilt(12)), Chest=lean(30), Neck=lean(25), Head=compose(lean(25), tilt(10)),
             UpperArm_L=raise_side('L', -20), UpperArm_R=compose(reach_forward(40), raise_side('R', -20)),
             Forearm_L=reach_forward(-20), Forearm_R=reach_forward(-40))
key('Death', [(0, pose(Chest=lean(-12), Head=lean(-20))),
              (0.4, pose(Spine=lean(-6), Chest=lean(-16), Head=lean(-24), UpperArm_L=raise_side('L', 30), UpperArm_R=raise_side('R', 30))),
              (0.9, pose(Spine=lean(14), Chest=lean(12))), (2.0, death), (3.0, death)])

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

# —— 预览：从正前方偏侧（+X 侧）渲染关键姿势 ——
if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = scene.render.resolution_y = 400
    world = bpy.data.worlds.new('w'); world.color = (0.9, 0.9, 0.9); scene.world = world
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); scene.collection.objects.link(sun)
    sun.rotation_euler = (0.9, 0.0, 1.9); sun.data.energy = 4
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); scene.collection.objects.link(cam); scene.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 1.5
    cam.location = Vector((3, 1.0, 0.8))
    cam.rotation_euler = (Vector((0, 0, 0.5)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    shots = [('Emerge', 1.0), ('Emerge', 3.45), ('Emerge', 3.9), ('Emerge', 4.6), ('ClawSwipe', 0.62), ('ClawSwipe', 1.67), ('RoarSky', 1.0), ('Idle', 0), ('SweepL', 0.7),
             ('Throw', 0.7), ('Root', 1.0), ('Stagger', 1.0), ('Death', 2.5)]
    # --claw：只渲染挥爪序列，正前偏侧与俯视两个角度，核对掌心是否朝着手臂运动的方向。
    views = [('front', cam.location.copy())]
    if '--claw' in args:
        shots = [('ClawSwipe', t) for t in (0.2, 0.35, 0.48, 0.62, 0.72, 0.8, 0.95, 1.4, 1.55, 1.67, 1.85)]
        views.append(('top', Vector((0.6, 0.0, 3.5))))
    for track in armature.animation_data.nla_tracks:
        track.mute = True
    for view, where in views:
        cam.location = where
        cam.rotation_euler = (Vector((0, 0, 0.5)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        for name, seconds in shots:
            armature.animation_data.action = bpy.data.actions[name]
            scene.frame_set(1 + round(seconds * FPS))
            scene.render.filepath = os.path.join(PREVIEW, f'pose_{name}_{seconds}' + ('' if view == 'front' else '_' + view) + '.png')
            bpy.ops.render.render(write_still=True)
