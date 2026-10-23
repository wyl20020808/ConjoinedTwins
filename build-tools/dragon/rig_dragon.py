"""给 Tripo 文生 3D 的「烬翼魔龙」建骨架、绑定权重并手写动作，导出带动画 GLB。

在 Blender 5.2 后台运行：
  blender -b --python rig_dragon.py -- <输出 GLB> [--preview <目录>] [--shots 动作:秒,动作:秒...]
输入固定为 build-tools/dragon/source/fire_dragon.glb（Tripo 原模型：最长边约 1、脚底在原点、
脸朝 -Y、Z 向上；半直立姿势，后腿站立、前肢短小、双翼向上张开呈 V 形、长尾拖地向 +Y）。

做法与第一章 rig_boss.py 相同：
1. 关节位置取自原模型几何剖面（2026-10-22 用 profile 脚本按切片求质心，见 docs/BOSS_CH2_DESIGN.md），
   脚、翼尖等末端再按顶点实时求取，换模型时只需核对打印的 JOINTS。
2. 不用 Blender 自动权重；每个顶点按到骨段的距离取最近两根（按部位限定候选骨骼），
   再按位置焊接 UV 接缝后沿拓扑平滑，翼膜在指骨之间平滑过渡。
3. 动作在模型空间“前（-Y）/左（+X）/上（+Z）”上直接写关键帧；Godot 按模拟时间取样，不自走。
   动作名与 scripts/journey_dragon_view.gd 对应。
"""
import bpy, sys, os, math, bmesh
from mathutils import Vector, Quaternion, kdtree

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, 'source', 'fire_dragon.glb')
FPS = 30
FORWARD = Vector((0, -1, 0))
LEFT = Vector((1, 0, 0))
UP = Vector((0, 0, 1))

args = sys.argv[sys.argv.index('--') + 1:]
OUTPUT = args[0]
PREVIEW = args[args.index('--preview') + 1] if '--preview' in args else ''
SHOTS = args[args.index('--shots') + 1] if '--shots' in args else ''

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


def centroid(points):
    total = Vector()
    for p in points:
        total += p
    return total / max(1, len(points))


def mirror(p, side):
    return Vector((abs(p.x) * side, p.y, p.z))


# —— 关节（模型坐标，左侧 +X）——
# 躯干中线：剖面质心（|x|<0.07 的切片）。
HIPS = Vector((0, -0.02, 0.19))
BELLY = Vector((0, -0.14, 0.27))
CHEST = Vector((0, -0.25, 0.37))
NECK1 = Vector((0, -0.31, 0.45))
NECK2 = Vector((0, -0.35, 0.52))
HEAD = Vector((0, -0.385, 0.545))
SNOUT = Vector((0, -0.50, 0.525))
JAW = Vector((0, -0.40, 0.515))
JAW_TIP = Vector((0, -0.485, 0.49))
TAIL = [Vector((0, 0.04, 0.17)), Vector((0, 0.12, 0.135)), Vector((0.02, 0.20, 0.08)), Vector((0.04, 0.28, 0.045)),
        Vector((0.05, 0.36, 0.035)), Vector((0.04, 0.43, 0.05)), Vector((0, 0.49, 0.09))]


def leg_chain(side):
    foot = [v for v in verts if side * v.x > 0.06 and v.z < 0.03]
    toe = min(foot, key=lambda v: v.y)
    heel = centroid(foot)
    # 尾根贴地处（y>0.06）不算腿。
    ankle = centroid([v for v in verts if side * v.x > 0.06 and 0.04 < v.z < 0.07 and -0.2 < v.y < 0.06])
    knee = centroid([v for v in verts if side * v.x > 0.05 and 0.10 < v.z < 0.13 and -0.2 < v.y < 0.06])
    hip = Vector((side * 0.075, -0.05, 0.21))
    return hip, knee, Vector((ankle.x, ankle.y, ankle.z)), Vector((heel.x, toe.y + 0.02, 0.01))


def arm_chain(side):
    shoulder = Vector((side * 0.07, -0.22, 0.39))
    elbow = Vector((side * 0.075, -0.255, 0.28))
    hand = Vector((side * 0.072, -0.235, 0.17))
    tip = Vector((side * 0.075, -0.255, 0.12))
    return shoulder, elbow, hand, tip


def wing_chain(side):
    root = Vector((side * 0.085, -0.20, 0.40))
    elbow = Vector((side * 0.15, -0.22, 0.49))
    wing = [v for v in verts if side * v.x > 0.16 and v.z > 0.5]
    # 翼腕：翼前缘最高处的爪（正面图上 x≈±0.21、z≈0.59）。
    wrist = centroid([v for v in wing if abs(abs(v.x) - 0.21) < 0.03 and v.z > 0.57])
    far = [v for v in verts if side * v.x > 0.46]
    tip1 = max(far, key=lambda v: side * v.x)
    tip2 = mirror(Vector((0.44, -0.18, 0.42)), side)
    tip3 = mirror(Vector((0.32, -0.18, 0.31)), side)
    return root, elbow, wrist, tip1, tip2, tip3


L_LEG, R_LEG = leg_chain(1), leg_chain(-1)
L_ARM, R_ARM = arm_chain(1), arm_chain(-1)
L_WING, R_WING = wing_chain(1), wing_chain(-1)
print('JOINTS leg L', [tuple(round(c, 3) for c in p) for p in L_LEG])
print('JOINTS wing L', [tuple(round(c, 3) for c in p) for p in L_WING])

# —— 骨架 ——
armature_data = bpy.data.armatures.new('DragonRig')
armature = bpy.data.objects.new('DragonRig', armature_data)
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
bone('Hips', HIPS, BELLY, 'Root')
bone('Spine', BELLY, CHEST, 'Hips', True)
bone('Neck1', CHEST, NECK1, 'Spine', True)
bone('Neck2', NECK1, NECK2, 'Neck1', True)
bone('Head', NECK2, SNOUT, 'Neck2', True)
bone('Jaw', JAW, JAW_TIP, 'Head')
for n in range(len(TAIL) - 1):
    bone('Tail%d' % (n + 1), TAIL[n], TAIL[n + 1], 'Hips' if n == 0 else 'Tail%d' % n, n > 0)
for side, s in (('L', 1), ('R', -1)):
    hip, knee, ankle, toe = L_LEG if s > 0 else R_LEG
    bone('Thigh.' + side, hip, knee, 'Hips')
    bone('Shin.' + side, knee, ankle, 'Thigh.' + side, True)
    bone('Foot.' + side, ankle, toe, 'Shin.' + side, True)
    shoulder, elbow, hand, tip = L_ARM if s > 0 else R_ARM
    bone('Arm.' + side, shoulder, elbow, 'Spine')
    bone('Forearm.' + side, elbow, hand, 'Arm.' + side, True)
    bone('Hand.' + side, hand, tip, 'Forearm.' + side, True)
    root, welbow, wrist, tip1, tip2, tip3 = L_WING if s > 0 else R_WING
    bone('Wing.' + side, root, welbow, 'Spine')
    bone('WingFore.' + side, welbow, wrist, 'Wing.' + side, True)
    bone('Finger1.' + side, wrist, tip1, 'WingFore.' + side)
    bone('Finger2.' + side, wrist, tip2, 'WingFore.' + side)
    bone('Finger3.' + side, wrist, tip3, 'WingFore.' + side)
bpy.ops.object.mode_set(mode='OBJECT')

# —— 权重 ——
segments = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in armature_data.bones if b.name != 'Root'}
groups = {name: mesh.vertex_groups.new(name=name) for name in segments}


def segment_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def family(name):
    return name.split('.')[0].rstrip('0123456789')


def region(v):
    """按部位限定可选骨骼，避免翼膜被腿骨、尾巴被前肢等远处骨骼拉走。"""
    side = 'L' if v.x > 0 else 'R'
    ax = abs(v.x)
    if ax > 0.105 and v.z > 0.27 and v.y < -0.1:
        return 'wing', side
    if v.y > 0.03 and v.z < 0.2 and ax < 0.12:
        return 'tail', side
    if v.y < -0.36 and v.z > 0.44:
        return 'head', side
    if ax > 0.035 and v.y < -0.17 and 0.1 < v.z < 0.42 and ax < 0.12:
        return 'arm', side
    if ax > 0.04 and v.z < 0.24 and v.y > -0.2:
        return 'leg', side
    return 'body', side


ALLOWED = {
    'wing': {'Wing', 'WingFore', 'Finger', 'Spine'},
    'tail': {'Tail', 'Hips'},
    'head': {'Head', 'Jaw', 'Neck'},
    'arm': {'Arm', 'Forearm', 'Hand', 'Spine'},
    'leg': {'Thigh', 'Shin', 'Foot', 'Hips', 'Tail'},
    'body': {'Hips', 'Spine', 'Neck', 'Head', 'Tail', 'Thigh', 'Wing', 'Arm'},
}

kind_of = []
for index, v in enumerate(verts):
    kind, side = region(v)
    kind_of.append(kind)
    candidates = []
    for name, (a, b) in segments.items():
        if family(name) not in ALLOWED[kind]:
            continue
        if '.' in name and not name.endswith('.' + side):
            continue
        d = segment_distance(v, a, b)
        # 下颌：嘴线以下、头前部的顶点归 Jaw，其余头部顶点不吃 Jaw。
        if name == 'Jaw':
            below = v.z < JAW.z + (v.y - JAW.y) * 0.35 + 0.005
            if not (below and v.y < -0.405):
                continue
            d *= 0.5
        candidates.append((d, name))
    candidates.sort()
    if len(candidates) == 1:
        groups[candidates[0][1]].add([index], 1.0, 'REPLACE')
        continue
    (d0, n0), (d1, n1) = candidates[0], candidates[1]
    w0 = 1.0 / (d0 + 0.006) ** 4
    w1 = 1.0 / (d1 + 0.006) ** 4
    groups[n0].add([index], w0 / (w0 + w1), 'REPLACE')
    groups[n1].add([index], w1 / (w0 + w1), 'REPLACE')

# 焊接 UV 接缝后沿拓扑平滑：翼膜、肩部和尾根的分界变成渐变。下颌与头只轻度平滑，保持嘴缝分明。
weld = {}
node_of = []
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
ROUNDS = {'wing': 10, 'tail': 8, 'leg': 6, 'arm': 4, 'body': 8, 'head': 2}
for r in range(10):
    smoothed = []
    for n in range(count):
        if r >= ROUNDS[node_kind[n]] or not neighbors[n]:
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

# 焊接后仍不相连的小块（尖刺、爪尖）整体取最近主体顶点的权重，作为刚体跟随。
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
rest = {b.name: b.matrix_local.to_quaternion() for b in armature_data.bones}
IDENTITY = Quaternion()


def rot(axis, degrees):
    return Quaternion(axis, math.radians(degrees))


def pitch(deg):  # 正值低头（前方 -Y 转向 -Z）
    return rot(LEFT, deg)


def yaw(deg):  # 正值转向自身左侧（+X）
    return rot(UP, deg)


def roll(deg):  # 绕前后轴侧倾，正值左侧抬起
    return rot(FORWARD, deg)


def flap(side, deg):  # 翅膀绕前后轴上抬（正）或下压（负）
    return rot(Vector((0, 1, 0)), -deg if side == 'L' else deg)


def sweep(side, deg):  # 翅膀绕竖直轴向后收（正）或向前探（负）
    return rot(UP, deg if side == 'L' else -deg)


def twist_wing(side, deg):  # 翅膀绕翼展方向转：正值前缘上翘（迎角增大）
    return rot(LEFT, -deg)


def compose(*qs):
    out = Quaternion()
    for q in qs:
        out = q @ out
    return out


def pose(**rotations):
    # 关键字参数里用 Wing_L 表示骨骼 Wing.L。
    return {name.replace('_', '.'): q for name, q in rotations.items()}


def both(name, fn):
    """左右对称：fn(side) 返回该侧旋转。"""
    return {name + '.L': fn('L'), name + '.R': fn('R')}


def merge(*parts):
    out = {}
    for p in parts:
        out.update(p)
    return out


def key(action_name, frames):
    """frames: [(秒, {骨骼: 模型空间旋转})]。未列出的骨骼回到静止姿势。"""
    action = bpy.data.actions.new(action_name)
    armature.animation_data_create()
    armature.animation_data.action = action
    names = [b.name for b in armature_data.bones]
    for seconds, rotations in frames:
        rotations = dict(rotations)
        # 髋部整体俯仰/侧倾时，后腿与尾根按反向补偿：脚不离地滑动、尾巴不被甩上天或插进地里。
        hips = rotations.get('Hips')
        if hips is not None:
            back = hips.inverted()
            for name, amount in (('Thigh.L', 1.0), ('Thigh.R', 1.0), ('Tail1', 0.8)):
                rotations[name] = IDENTITY.slerp(back, amount) @ rotations.get(name, IDENTITY)
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
    track.strips.new(action_name, 1, action)
    armature.animation_data.action = None
    return action


def lag(frames, bones, delay):
    """跟随：指定骨骼取 delay 秒之前那一关键帧的姿势，模拟惯性滞后。"""
    out = []
    for t, p in frames:
        p = dict(p)
        earlier = [q for (s, q) in frames if s <= t - delay]
        for b in bones:
            p[b] = earlier[-1].get(b, IDENTITY) if earlier else IDENTITY
        out.append((t, p))
    return out


def tail_wave(phase, amount, lift=0.0):
    """尾巴：沿各节依次滞后的横摆，越往后摆幅越大；lift 为整体抬起（负值压低），按节累加，每节取 30%。"""
    out = {}
    for n in range(1, 7):
        out['Tail%d' % n] = compose(yaw(amount * (0.5 + n * 0.12) * math.sin(phase - n * 0.55)), pitch(lift * 0.3))
    return out


def wings_folded(amount):
    """半收翼：下压并向后收、指骨并拢。amount 0..1。"""
    return merge(both('Wing', lambda s: compose(flap(s, -32 * amount), sweep(s, 28 * amount))),
                 both('WingFore', lambda s: compose(flap(s, -20 * amount), sweep(s, 30 * amount))),
                 both('Finger1', lambda s: sweep(s, 18 * amount)),
                 both('Finger2', lambda s: compose(sweep(s, 24 * amount), flap(s, 10 * amount))),
                 both('Finger3', lambda s: compose(sweep(s, 30 * amount), flap(s, 18 * amount))))


def neck(pitch_deg, yaw_deg=0.0, head_pitch=0.0, jaw=0.0, head_yaw=0.0):
    return {'Neck1': compose(yaw(yaw_deg * 0.4), pitch(pitch_deg * 0.5)),
            'Neck2': compose(yaw(yaw_deg * 0.6), pitch(pitch_deg * 0.5)),
            'Head': compose(yaw(head_yaw), pitch(head_pitch)),
            'Jaw': pitch(jaw)}


# 待机（地面，4 秒循环）：胸口呼吸、头缓慢环视并偶尔张口吐气，双翼半收随呼吸起伏，尾巴慢摆。
def idle_at(t):
    a = t / 4.0 * math.tau
    breath = math.sin(a)
    p = merge(wings_folded(0.55 + 0.05 * breath), tail_wave(a, 6),
              neck(-3 + 4 * breath, 12 * math.sin(a * 0.5 + 0.4), head_pitch=3 * math.sin(a + 1), jaw=4 + 3 * max(0.0, math.sin(a * 0.5))),
              {'Hips': pitch(1.5 * breath), 'Spine': pitch(-2 * breath)},
              both('Arm', lambda s: pitch(-6 + 4 * math.sin(a + (0 if s == 'L' else 1.5)))))
    return p


key('Idle', [(n * 0.25, idle_at(n * 0.25)) for n in range(17)])


# 飞行振翅（1.0 秒循环）：下拍有力、上挥收拢指骨；前肢与后腿收起，尾巴随振翅上下起伏。
def fly_at(t):
    a = t * math.tau
    stroke = math.sin(a)  # 1 = 翼在最高处
    follow = math.sin(a - 0.7)
    tuck = merge(both('Thigh', lambda s: pitch(-55)), both('Shin', lambda s: pitch(70)), both('Foot', lambda s: pitch(-40)),
                 both('Arm', lambda s: pitch(-40)), both('Forearm', lambda s: pitch(50)))
    wings = merge(both('Wing', lambda s: compose(flap(s, -20 + 42 * stroke), sweep(s, -6 * stroke))),
                  both('WingFore', lambda s: compose(flap(s, 18 * follow), sweep(s, 8 * max(0.0, -follow)))),
                  both('Finger1', lambda s: flap(s, 12 * follow)),
                  both('Finger2', lambda s: flap(s, 14 * follow)),
                  both('Finger3', lambda s: compose(flap(s, 16 * follow), sweep(s, 6 * max(0.0, follow)))))
    body = {'Hips': pitch(4 * stroke), 'Spine': pitch(-5 * stroke)}
    return merge(tuck, wings, body, neck(10 - 6 * stroke, head_pitch=-12 + 4 * stroke, jaw=6), tail_wave(a * 0.5, 4, lift=-6 + 6 * stroke))


key('Fly', [(n / 12.0, fly_at(n / 12.0)) for n in range(13)])


# 滑翔（2 秒循环）：双翼平展微微颤动，尾巴缓摆。
def glide_at(t):
    a = t / 2.0 * math.tau
    wobble = math.sin(a)
    return merge(both('Thigh', lambda s: pitch(-55)), both('Shin', lambda s: pitch(70)), both('Foot', lambda s: pitch(-40)),
                 both('Arm', lambda s: pitch(-40)), both('Forearm', lambda s: pitch(50)),
                 both('Wing', lambda s: compose(flap(s, -24 + 3 * wobble), sweep(s, -4))),
                 both('WingFore', lambda s: flap(s, -4 + 2 * math.sin(a - 0.6))),
                 both('Finger3', lambda s: flap(s, 4 * math.sin(a - 1.0))),
                 neck(14, 6 * wobble, head_pitch=-14, jaw=4), tail_wave(a, 7, lift=-8))


key('Glide', [(n / 6.0, glide_at(n / 6.0)) for n in range(13)])

GROUND = idle_at(0.0)


# 降落（1.6 秒）：后仰刹车、双翼前探猛扇两下、后腿前伸 → 0.9 秒着地下蹲 → 起身站稳收翼。
def brake(stroke):
    return merge(both('Wing', lambda s: compose(flap(s, -10 + 40 * stroke), sweep(s, -22))),
                 both('WingFore', lambda s: compose(flap(s, 16 * stroke), sweep(s, -10))),
                 both('Finger3', lambda s: flap(s, 10 * stroke)),
                 {'Hips': pitch(-14), 'Spine': pitch(-10)}, neck(18, head_pitch=-8, jaw=10),
                 both('Thigh', lambda s: pitch(-20)), both('Shin', lambda s: pitch(10)),
                 both('Arm', lambda s: pitch(-30)), tail_wave(0, 0, lift=-10))


land_crouch = merge(wings_folded(0.15), {'Hips': pitch(10), 'Spine': pitch(14)}, neck(16, head_pitch=6, jaw=14),
                    both('Thigh', lambda s: pitch(-30)), both('Shin', lambda s: pitch(40)), both('Foot', lambda s: pitch(-12)),
                    both('Wing', lambda s: compose(flap(s, -30), sweep(s, 0))), tail_wave(0, 0, lift=6))
key('Land', lag([(0, fly_at(0.25)), (0.25, brake(1)), (0.5, brake(-1)), (0.7, brake(1)), (0.9, land_crouch),
                 (1.05, merge(land_crouch, {'Spine': pitch(18)})), (1.35, merge(wings_folded(0.4), neck(4, jaw=8))), (1.6, GROUND)],
                ['Head', 'Finger1.L', 'Finger1.R', 'Finger2.L', 'Finger2.R', 'Finger3.L', 'Finger3.R'], 0.06))

# 起飞（1.2 秒）：下蹲蓄力、双翼高举 → 0.55 秒猛力下拍跃起 → 收腿接 Fly。
takeoff_crouch = merge({'Hips': pitch(8), 'Spine': pitch(12)}, neck(10, head_pitch=-6, jaw=6),
                       both('Thigh', lambda s: pitch(-28)), both('Shin', lambda s: pitch(38)), both('Foot', lambda s: pitch(-10)),
                       both('Wing', lambda s: compose(flap(s, 34), sweep(s, 10))), both('WingFore', lambda s: flap(s, 20)),
                       both('Finger3', lambda s: flap(s, 14)), tail_wave(0, 0, lift=4))
takeoff_push = merge({'Hips': pitch(-6), 'Spine': pitch(-6)}, neck(-6, head_pitch=-10, jaw=10),
                     both('Thigh', lambda s: pitch(10)), both('Shin', lambda s: pitch(-6)), both('Foot', lambda s: pitch(20)),
                     both('Wing', lambda s: compose(flap(s, -40), sweep(s, -10))), both('WingFore', lambda s: flap(s, -14)),
                     both('Finger3', lambda s: flap(s, -10)), tail_wave(0, 0, lift=-8))
key('Takeoff', lag([(0, GROUND), (0.4, takeoff_crouch), (0.55, takeoff_push), (0.8, fly_at(0.5)), (1.0, fly_at(0.75)), (1.2, fly_at(0.0))],
                   ['Head', 'Finger1.L', 'Finger1.R', 'Finger3.L', 'Finger3.R'], 0.05))


# 咆哮（2.4 秒）：吸气低头 → 挺胸仰头张大嘴、双翼高举张开 → 颤抖保持 → 回落。
def roar_peak(shake):
    return merge({'Hips': pitch(-8), 'Spine': pitch(-14 + shake)}, neck(-26, 3 * shake, head_pitch=-14 - shake, jaw=34 + 2 * shake),
                 both('Wing', lambda s: compose(flap(s, 24 + 2 * shake), sweep(s, -12))), both('WingFore', lambda s: flap(s, 12)),
                 both('Finger2', lambda s: flap(s, 6)), both('Finger3', lambda s: flap(s, 10)),
                 both('Arm', lambda s: pitch(-30)), both('Forearm', lambda s: pitch(-20)), tail_wave(shake, 4, lift=10))


roar_inhale = merge(wings_folded(0.5), {'Spine': pitch(12)}, neck(22, head_pitch=14, jaw=4), both('Arm', lambda s: pitch(10)),
                    tail_wave(0, 0, lift=-4))
key('Roar', lag([(0, GROUND), (0.45, roar_inhale), (0.75, roar_peak(0)), (0.95, roar_peak(1.5)), (1.15, roar_peak(-1.5)),
                 (1.35, roar_peak(1.5)), (1.55, roar_peak(-1.5)), (1.75, roar_peak(1)), (2.0, roar_peak(0)), (2.4, GROUND)],
                ['Head', 'Finger1.L', 'Finger1.R', 'Finger2.L', 'Finger2.R', 'Finger3.L', 'Finger3.R'], 0.06))


# 吐息（3.0 秒，BreathL / BreathR 镜像）：0–1.0 后仰吸气、胸口蓄光 → 1.0–1.2 头猛地前探压低、张大嘴 →
# 1.2–2.6 颈从正前方扫向一侧（左 +X 侧为 L）→ 2.6–3.0 合嘴回正。扫动角度与模拟的扇形吐息一致。
def breath_pose(s, sweep_amount, shake=0.0):
    sign = 1 if s == 'L' else -1
    return merge(wings_folded(0.35), {'Hips': pitch(4), 'Spine': compose(pitch(10), yaw(sign * 10 * sweep_amount))},
                 neck(30, sign * 45 * sweep_amount + shake, head_pitch=6, jaw=30, head_yaw=sign * 12 * sweep_amount),
                 both('Arm', lambda side: pitch(-10)), tail_wave(sweep_amount * 2, 5))


breath_inhale = merge(wings_folded(0.6), {'Hips': pitch(-8), 'Spine': pitch(-16)}, neck(-30, head_pitch=-10, jaw=8),
                      both('Arm', lambda s: pitch(-24)), tail_wave(0, 0, lift=8))
for s in ('L', 'R'):
    key('Breath' + s, lag([(0, GROUND), (0.5, merge(breath_inhale, {'Spine': pitch(-10)})), (1.0, breath_inhale), (1.2, breath_pose(s, -0.08)),
                           (1.6, breath_pose(s, 0.3, 2)), (2.0, breath_pose(s, 0.62, -2)), (2.4, breath_pose(s, 0.92, 2)), (2.6, breath_pose(s, 1.0)),
                           (3.0, GROUND)], ['Head', 'Jaw'], 0.04))


# 仰天喷火（2.6 秒，召来火雨）：伏低 → 猛地抬头朝天张嘴喷火、双翼张开 → 收回。
def sky_pose(shake):
    return merge({'Hips': pitch(-12), 'Spine': pitch(-20)}, neck(-48, 2 * shake, head_pitch=-26, jaw=32 + shake),
                 both('Wing', lambda s: compose(flap(s, 30), sweep(s, -16))), both('WingFore', lambda s: flap(s, 14)),
                 both('Finger3', lambda s: flap(s, 12)), both('Arm', lambda s: pitch(-40)), tail_wave(shake, 3, lift=12))


key('SkyFire', lag([(0, GROUND), (0.5, merge(roar_inhale, {'Hips': pitch(6)})), (0.85, sky_pose(0)), (1.2, sky_pose(2)), (1.5, sky_pose(-2)),
                    (1.8, sky_pose(2)), (2.1, sky_pose(0)), (2.6, GROUND)], ['Head'], 0.05))


# 甩尾（2.0 秒）：身体向一侧拧转蓄力 → 1.0 秒尾巴横扫一圈拍地（地面冲击环）→ 回正。
def tail_swing(amount):
    out = {}
    for n in range(1, 7):
        out['Tail%d' % n] = compose(yaw(amount * (8 + n * 4)), pitch(-4 if amount else 0))
    return out


key('TailSwipe', lag([(0, GROUND), (0.5, merge(wings_folded(0.6), {'Hips': yaw(-14), 'Spine': yaw(-10)}, neck(10, 30), tail_swing(-1.0))),
                      (0.85, merge(wings_folded(0.5), {'Hips': yaw(-18), 'Spine': yaw(-12)}, neck(12, 36), tail_swing(-1.3))),
                      (1.0, merge(wings_folded(0.4), {'Hips': yaw(16), 'Spine': yaw(12)}, neck(6, -24, jaw=18), tail_swing(1.5))),
                      (1.2, merge(wings_folded(0.4), {'Hips': yaw(20), 'Spine': yaw(14)}, neck(6, -28, jaw=14), tail_swing(1.2))),
                      (1.6, merge(wings_folded(0.5), {'Hips': yaw(6)}, neck(2, -8), tail_swing(0.3))), (2.0, GROUND)],
                     ['Tail4', 'Tail5', 'Tail6', 'Head'], 0.06))


# 蓄焰（锁链破甲窗口，循环 2.0 秒）：伏低、双翼裹身、胸口熔岩随呼吸鼓动，头低垂缓慢左右摆。
def charge_at(t):
    a = t / 2.0 * math.tau
    pulse = math.sin(a)
    return merge(wings_folded(0.95), {'Hips': pitch(10 + 2 * pulse), 'Spine': pitch(16 - 4 * pulse)},
                 neck(24 + 4 * pulse, 10 * math.sin(a * 0.5), head_pitch=10, jaw=6 + 6 * max(0.0, pulse)),
                 both('Thigh', lambda s: pitch(-22)), both('Shin', lambda s: pitch(30)), both('Foot', lambda s: pitch(-8)),
                 both('Arm', lambda s: pitch(20)), tail_wave(a, 3, lift=-2))


key('Charge', [(n * 0.25, charge_at(n * 0.25)) for n in range(9)])

# 锁链压制（硬直，循环）：被锁链拽倒，胸口贴地、双翼摊开、头无力垂下挣扎；0.4 秒后进入 0.4–2.0 循环段。
pinned = merge({'Hips': pitch(22), 'Spine': pitch(22)}, neck(34, head_pitch=14, jaw=12),
               both('Wing', lambda s: compose(flap(s, -50), sweep(s, -6))), both('WingFore', lambda s: flap(s, -10)),
               both('Thigh', lambda s: pitch(-40)), both('Shin', lambda s: pitch(60)), both('Foot', lambda s: pitch(-20)),
               both('Arm', lambda s: pitch(-30)), both('Forearm', lambda s: pitch(30)), tail_wave(0, 0, lift=-6))
pinned_struggle = merge(pinned, {'Spine': compose(pitch(18), roll(4))}, neck(26, 14, head_pitch=6, jaw=26),
                        both('Wing', lambda s: compose(flap(s, -42), sweep(s, -4))))
key('Pinned', [(0, merge(roar_peak(0), {'Spine': pitch(-20)})), (0.4, pinned), (0.9, pinned_struggle), (1.4, pinned), (2.0, pinned)])

# 倒下（3.0 秒）：仰头哀嚎 → 向侧面倒地、翼摊开、头尾垂地。
death = merge({'Hips': compose(pitch(18), roll(-10)), 'Spine': compose(pitch(26), roll(-14))}, neck(44, 24, head_pitch=24, jaw=20, head_yaw=10),
              both('Wing', lambda s: compose(flap(s, -58), sweep(s, 14))), both('WingFore', lambda s: flap(s, -22)),
              both('Finger3', lambda s: flap(s, -8)),
              both('Thigh', lambda s: pitch(-48)), both('Shin', lambda s: pitch(70)), both('Foot', lambda s: pitch(-20)),
              both('Arm', lambda s: pitch(-20)), tail_wave(1.0, 6, lift=-4))
key('Death', [(0, GROUND), (0.5, roar_peak(0)), (1.0, merge(roar_peak(1), {'Spine': pitch(-24)})), (2.2, death), (3.0, death)])

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

# —— 预览：正前偏侧与侧面渲染关键姿势 ——
if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = scene.render.resolution_y = 420
    world = bpy.data.worlds.new('w'); world.color = (0.75, 0.75, 0.75); scene.world = world
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); scene.collection.objects.link(sun)
    sun.rotation_euler = (0.7, 0.0, -0.6); sun.data.energy = 4
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); scene.collection.objects.link(cam); scene.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 1.35
    shots = [('Idle', 0), ('Fly', 0.0), ('Fly', 0.25), ('Fly', 0.5), ('Fly', 0.75), ('Glide', 0), ('Land', 0.9), ('Takeoff', 0.4),
             ('Roar', 1.0), ('BreathL', 1.0), ('BreathL', 2.4), ('SkyFire', 1.2), ('TailSwipe', 1.0), ('Charge', 0.5), ('Pinned', 1.0), ('Death', 2.6)]
    if SHOTS:
        shots = [(s.split(':')[0], float(s.split(':')[1])) for s in SHOTS.split(',')]
    for track in armature.animation_data.nla_tracks:
        track.mute = True
    for view, where in (('front', Vector((-1.6, -2.6, 1.3))), ('side', Vector((3.0, 0.0, 0.7)))):
        cam.location = where
        cam.rotation_euler = (Vector((0, 0, 0.3)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        for name, seconds in shots:
            armature.animation_data.action = bpy.data.actions[name]
            scene.frame_set(1 + round(seconds * FPS))
            scene.render.filepath = os.path.join(PREVIEW, f'{view}_{name}_{seconds}.png')
            bpy.ops.render.render(write_still=True)
