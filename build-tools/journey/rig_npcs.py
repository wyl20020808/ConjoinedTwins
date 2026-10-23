"""给 Tripo 静态 NPC 自动建骨架、绑定权重并手写程序化动作，导出带动画的 GLB。

在 Blender 5.2 后台运行：
  blender -b --python rig_npcs.py -- <输出目录> <模型名...> [--preview]
模型名对应 assets/monsters/<名>.glb 或 assets/landscape/<名>.glb。

做法（不做任何外部骨架的重定向，所有轴向都是本脚本自己定义的）：
1. 从网格顶点自动推关节：贴地顶点聚类得到脚，按高度切片取躯干质心得到骨盆/胸/颈，
   躯干宽度以外的顶点归为手臂，离肩最远的一批点作为手（武器随手一起动）。
2. 建骨架后用 Blender 自动权重；没分到权重的顶点按到骨段的距离挂到最近的骨头上。
3. 动作在“前/侧/上”三个模型空间轴上直接写关键帧：待机呼吸、走、跑、攻击（蓄力→挥击）、受击。
4. --preview 时额外渲染骨架叠加图与几帧姿势，供人工检查。
"""
import bpy, bmesh, sys, os, math, json
from mathutils import Vector, Quaternion, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
FPS = 30

# 每个模型的朝向与类型。forward 为模型空间（Blender，Z 向上）的正前方。
# gait：步幅倍率；attack：swing 单手挥击 / slam 双手砸地 / draw 拉弓 / bite（四足）；raise：挥击举臂角度。
CONFIG = {
    # 狼的 Tripo 原模型头部向一侧扭了约 90°（鼻尖朝 +X），绑骨前先把头颈摆正。
    'grey_wolf': {'kind': 'quad', 'forward': (0, -1, 0), 'gait': 1.0, 'straighten_head': True},
    'bark_sprite': {'kind': 'quad', 'forward': (0, -1, 0), 'gait': 0.7},
    'raider': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 1.0, 'attack': 'swing', 'raise': 110},
    'raider_slinger': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.9, 'attack': 'draw'},
    'brute_charger': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.85, 'attack': 'swing', 'raise': 95},
    'stone_guard': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.5, 'attack': 'slam', 'raise': 85},
    'villager_farmer': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.8, 'attack': 'swing', 'raise': 60, 'main': 'R'},
    'villager_elder': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.6, 'attack': 'swing', 'raise': 50},
    'villager_blacksmith': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.8, 'attack': 'swing', 'raise': 90},
    'villager_merchant': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.7, 'attack': 'swing', 'raise': 50},
    # 2026-10-21 第二批 Tripo：三种怪物、三种村民，正前方均为 +X。根须蛛是多足，用 spider 骨架与三角步态。
    'root_spider': {'kind': 'spider', 'forward': (1, 0, 0), 'gait': 1.0},
    # 地精手臂短、紧贴身体，举太高会把手臂网格拉长；钳甲兵的大钳是独立网格块，摆臂过大会与肩甲脱开。
    'goblin_bomber': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.9, 'attack': 'swing', 'raise': 70, 'main': 'R'},
    'river_crab_knight': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.55, 'attack': 'slam', 'raise': 45, 'arm_gait': 0.3},
    'villager_fisher': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.7, 'attack': 'swing', 'raise': 50},
    'villager_miner': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.6, 'attack': 'swing', 'raise': 60},
    'villager_guard': {'kind': 'biped', 'forward': (1, 0, 0), 'gait': 0.8, 'attack': 'swing', 'raise': 70},
}


def source_path(name):
    for folder in ('assets/monsters', 'assets/landscape'):
        path = os.path.join(ROOT, folder, name + '.glb')
        if os.path.exists(path):
            return path
    raise FileNotFoundError(name)


def kmeans(points, k, axis_init):
    """一维初始化的小 k-means（点数几十到几百），返回各簇质心与成员。"""
    pts = sorted(points, key=axis_init)
    centers = [pts[int((i + 0.5) * len(pts) / k)].copy() for i in range(k)]
    for _ in range(20):
        groups = [[] for _ in range(k)]
        for p in points:
            groups[min(range(k), key=lambda i: (p - centers[i]).length_squared)].append(p)
        centers = [sum(g, Vector()) / len(g) if g else centers[i] for i, g in enumerate(groups)]
    return centers, groups


def frame_axes(forward):
    f = Vector(forward).normalized()
    up = Vector((0, 0, 1))
    left = up.cross(f).normalized()  # 面向 f、头朝上时的左侧
    return f, left, up


def band(verts, z0, z1):
    return [v for v in verts if z0 <= v.z <= z1]


def centroid(points):
    return sum(points, Vector()) / max(len(points), 1)


def biped_joints(verts, cfg):
    f, left, up = frame_axes(cfg['forward'])
    H = max(v.z for v in verts)
    lat = lambda v: v.dot(left)
    fwd = lambda v: v.dot(f)
    low = [v for v in verts if v.z < 0.05 * H]
    centers, _ = kmeans(low, 2, lat)
    foot_l, foot_r = sorted(centers, key=lat, reverse=True)
    mid_lat = (lat(foot_l) + lat(foot_r)) / 2
    hip_z = (0.36 if cfg.get('crouch') else 0.45) * H
    core = lambda vs, w: [v for v in vs if abs(lat(v) - mid_lat) < w * H]
    pelvis = centroid(core(band(verts, hip_z - 0.04 * H, hip_z + 0.04 * H), 0.12))
    pelvis.z = hip_z
    chest = centroid(core(band(verts, 0.64 * H, 0.72 * H), 0.12))
    chest.z = 0.68 * H
    neck = centroid(core(band(verts, 0.80 * H, 0.84 * H), 0.08))
    neck.z = 0.82 * H
    head_top = Vector((neck.x, neck.y, H))
    # 躯干半宽：胸部高度切片里离中线 70% 分位的横向距离。
    chest_band = band(verts, 0.6 * H, 0.75 * H)
    dists = sorted(abs(lat(v) - lat(chest)) for v in chest_band)
    half = dists[int(len(dists) * 0.55)] if dists else 0.12 * H
    half = max(half, 0.08 * H)
    joints = {'pelvis': pelvis, 'chest': chest, 'neck': neck, 'head_top': head_top,
              '_half': Vector((half, 0, 0))}
    for side, sign, foot in (('L', 1, foot_l), ('R', -1, foot_r)):
        shoulder = chest + left * (sign * half * 0.9)
        shoulder.z = 0.76 * H
        arm = [v for v in verts if 0.3 * H < v.z < 0.95 * H and sign * (lat(v) - lat(chest)) > half]
        if len(arm) < 20:
            hand = shoulder + Vector((0, 0, -0.3 * H)) + left * sign * 0.02 * H
        else:
            far = sorted(arm, key=lambda v: (v - shoulder).length, reverse=True)
            hand = centroid(far[:max(5, len(far) // 30)])
        elbow = (shoulder + hand) / 2 + f * 0.02 * H
        hip = pelvis + left * (sign * max(0.05 * H, abs(lat(foot) - lat(pelvis)) * 0.35))
        hip.z = hip_z - 0.03 * H
        ankle = foot.copy(); ankle.z = 0.05 * H
        knee = (hip + ankle) / 2 + f * 0.04 * H
        joints.update({f'shoulder.{side}': shoulder, f'elbow.{side}': elbow, f'hand.{side}': hand,
                       f'hip.{side}': hip, f'knee.{side}': knee, f'ankle.{side}': ankle})
    return joints


def quad_joints(verts, cfg):
    f, left, up = frame_axes(cfg['forward'])
    H = max(v.z for v in verts)
    fwd = lambda v: v.dot(f)
    lat = lambda v: v.dot(left)
    low = [v for v in verts if v.z < 0.06 * H]
    centers, _ = kmeans(low, 4, fwd)
    centers.sort(key=fwd, reverse=True)
    front = sorted(centers[:2], key=lat, reverse=True)
    hind = sorted(centers[2:], key=lat, reverse=True)
    body = band(verts, 0.45 * H, 0.75 * H)
    front_f = fwd(centroid(front)); hind_f = fwd(centroid(hind))
    shoulder_c = centroid([v for v in body if abs(fwd(v) - front_f) < 0.08])
    hip_c = centroid([v for v in body if abs(fwd(v) - hind_f) < 0.08])
    shoulder_c.z = hip_c.z = 0.62 * H
    nose = max(verts, key=fwd)
    head_c = centroid([v for v in verts if fwd(v) > fwd(nose) - 0.16 and v.z > 0.55 * H])
    tail_end = min(verts, key=fwd)
    joints = {'hip_c': hip_c, 'shoulder_c': shoulder_c, 'neck': shoulder_c + f * 0.08 + up * 0.08 * H,
              'head': head_c, 'nose': nose, 'tail_base': hip_c - f * 0.06 + up * 0.05 * H, 'tail_end': tail_end}
    for name, pair, top in (('front', front, shoulder_c), ('hind', hind, hip_c)):
        for side, paw in zip(('L', 'R'), pair):
            upper = paw.copy(); upper.z = top.z - 0.08 * H
            upper += f * (fwd(top) - fwd(paw)) * 0.3
            joint = paw.copy(); joint.z = 0.32 * H
            joint += f * (0.03 if name == 'hind' else -0.01)
            ankle = paw.copy(); ankle.z = 0.04 * H
            joints.update({f'{name}_top.{side}': upper, f'{name}_mid.{side}': joint, f'{name}_paw.{side}': ankle})
    return joints


def straighten_head(mesh, cfg):
    """四足模型头部朝向偏离身体前方时，把头颈顶点绕颈根竖轴转回正前方。
    鼻尖取前半身、0.55–0.8 身高内离头顶中心水平最远的点；权重随“比颈根更靠前”和“高于胸口”平滑增加，
    前腿与胸口下半部分不动。返回实际转过的角度（度）。"""
    f, left, up = frame_axes(cfg['forward'])
    verts = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
    H = max(v.z for v in verts)
    fwd = lambda v: v.dot(f)
    front = [v for v in verts if fwd(v) > 0.45 * max(fwd(u) for u in verts)]
    skull = centroid([v for v in front if v.z > 0.8 * H])
    snout = [v for v in front if 0.55 * H < v.z < 0.8 * H]
    flat = lambda v: Vector((v.x - skull.x, v.y - skull.y, 0))
    nose = max(snout, key=lambda v: flat(v).length)
    aim = flat(nose).normalized()
    yaw = math.atan2(aim.cross(f).z, aim.dot(f))
    pivot = centroid([v for v in verts if 0.45 * H < v.z < 0.75 * H and abs(fwd(v) - (fwd(skull) - 0.12)) < 0.04])
    rot = Matrix.Rotation(yaw, 4, 'Z')
    inv = mesh.matrix_world.inverted()
    for v in mesh.data.vertices:
        p = mesh.matrix_world @ v.co
        ahead = max(0.0, min(1.0, (fwd(p) - fwd(pivot)) / 0.08))
        high = max(0.0, min(1.0, (p.z - 0.5 * H) / (0.12 * H)))
        w = ahead * high
        if w <= 0.0:
            continue
        r = Matrix.Rotation(yaw * w, 4, 'Z')
        v.co = inv @ (Vector(pivot) + (r @ (p - pivot)))
    mesh.data.update()
    return math.degrees(yaw)


def spider_joints(verts, cfg):
    """多足：贴地顶点按绕身体中心的角度分组得到每条腿的脚（按角度间隙自动分出 4–8 条），
    髋点在身体边缘、膝点抬高形成拱形腿；身体中心到最前端为头。"""
    f, left, up = frame_axes(cfg['forward'])
    H = max(v.z for v in verts)
    body = [v for v in verts if v.z > 0.45 * H]
    c = centroid(body); c.z = 0.45 * H
    flat = lambda v: Vector((v.x - c.x, v.y - c.y, 0))
    radius = sorted(flat(v).length for v in body)[int(len(body) * 0.8)]
    feet = [v for v in verts if v.z < 0.06 * H and flat(v).length > 0.6 * radius]
    angle = lambda v: math.atan2(flat(v).dot(left), flat(v).dot(f))
    feet.sort(key=angle)
    groups = [[feet[0]]]
    for a, b in zip(feet, feet[1:]):
        if angle(b) - angle(a) > math.radians(14): groups.append([])
        groups[-1].append(b)
    if len(groups) > 1 and angle(feet[0]) + 2 * math.pi - angle(feet[-1]) < math.radians(14):
        groups[0] = groups.pop() + groups[0]
    groups = sorted([g for g in groups if len(g) >= 6], key=len, reverse=True)[:8]
    groups.sort(key=lambda g: angle(centroid(g)))
    nose = max(verts, key=lambda v: v.dot(f) if v.z > 0.25 * H else -1e9)
    joints = {'c': c, 'top': c + up * 0.3 * H, 'nose': nose, '_legs': len(groups)}
    for i, g in enumerate(groups):
        foot = centroid(g); foot.z = 0.03 * H
        d = flat(foot).normalized()
        hip = c + d * radius * 0.7; hip.z = 0.4 * H
        knee = hip + (foot - hip) * 0.45; knee.z = max(0.55 * H, hip.z + 0.1 * H)
        joints.update({f'leg_hip.{i}': hip, f'leg_knee.{i}': knee, f'leg_foot.{i}': foot})
    return joints


def build_armature(joints, kind):
    arm_data = bpy.data.armatures.new('Rig')
    rig = bpy.data.objects.new('Rig', arm_data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones

    def bone(name, head, tail, parent=None, connect=False):
        b = eb.new(name); b.head = head; b.tail = tail
        if (b.tail - b.head).length < 1e-3:
            b.tail = b.head + Vector((0, 0, 0.02))
        if parent:
            b.parent = eb[parent]; b.use_connect = connect
        return b

    j = joints
    if kind == 'spider':
        bone('Hips', j['c'], j['c'] + Vector((0, 0, 0.02)))
        bone('Spine', j['c'], j['top'], 'Hips')
        bone('Head', j['c'], j['nose'], 'Hips')
        for i in range(j['_legs']):
            bone(f'LegUpper.{i}', j[f'leg_hip.{i}'], j[f'leg_knee.{i}'], 'Hips')
            bone(f'LegLower.{i}', j[f'leg_knee.{i}'], j[f'leg_foot.{i}'], f'LegUpper.{i}', True)
        bpy.ops.object.mode_set(mode='OBJECT')
        return rig
    if kind == 'biped':
        bone('Hips', j['pelvis'], j['pelvis'] + Vector((0, 0, 0.05)))
        bone('Spine', j['pelvis'], j['chest'], 'Hips')
        bone('Neck', j['chest'], j['neck'], 'Spine', True)
        bone('Head', j['neck'], j['head_top'], 'Neck', True)
        for s in ('L', 'R'):
            bone(f'UpperArm.{s}', j[f'shoulder.{s}'], j[f'elbow.{s}'], 'Spine')
            bone(f'LowerArm.{s}', j[f'elbow.{s}'], j[f'hand.{s}'], f'UpperArm.{s}', True)
            bone(f'Thigh.{s}', j[f'hip.{s}'], j[f'knee.{s}'], 'Hips')
            bone(f'Shin.{s}', j[f'knee.{s}'], j[f'ankle.{s}'], f'Thigh.{s}', True)
    else:
        bone('Hips', j['hip_c'], j['hip_c'] + (j['shoulder_c'] - j['hip_c']) * 0.3)
        bone('Spine', j['hip_c'] + (j['shoulder_c'] - j['hip_c']) * 0.3, j['shoulder_c'], 'Hips', True)
        bone('Neck', j['shoulder_c'], j['neck'], 'Spine', True)
        bone('Head', j['neck'], j['head'], 'Neck', True)
        bone('Snout', j['head'], j['nose'], 'Head', True)
        bone('Tail', j['tail_base'], (j['tail_base'] + j['tail_end']) / 2, 'Hips')
        bone('TailTip', (j['tail_base'] + j['tail_end']) / 2, j['tail_end'], 'Tail', True)
        for leg, parent in (('front', 'Spine'), ('hind', 'Hips')):
            for s in ('L', 'R'):
                cap = leg.capitalize()
                bone(f'{cap}Upper.{s}', j[f'{leg}_top.{s}'], j[f'{leg}_mid.{s}'], parent)
                bone(f'{cap}Lower.{s}', j[f'{leg}_mid.{s}'], j[f'{leg}_paw.{s}'], f'{cap}Upper.{s}', True)
    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def segment_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def bind(mesh, rig, H, joints=None, cfg=None):
    """按到骨段的距离算平滑权重：最近骨段距离 d0，其余骨段按 exp(-((d-d0)/σ)²) 衰减，
    每个顶点保留最多 3 根骨，归一化。Tripo 网格多为非流形碎片，Blender 热扩散权重会整体失败。"""
    for o in bpy.context.selected_objects:
        o.select_set(False)
    mesh.select_set(True); rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type='ARMATURE_NAME')
    bones = [(b.name, rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local) for b in rig.data.bones
             if b.name != 'Hips' or True]
    sigma = 0.035 * H
    for name, _, _ in bones:
        if name not in mesh.vertex_groups:
            mesh.vertex_groups.new(name=name)
    allowed = lambda name, p: True
    if joints is not None and cfg and cfg['kind'] == 'biped':
        # 区域限制：手臂骨只管躯干宽度以外的顶点（中间的头发、斗篷、围裙不会被手带走），
        # 腿骨只管骨盆以下的顶点。
        f, left, up = frame_axes(cfg['forward'])
        half = joints['_half'].x
        chest_lat = joints['chest'].dot(left)
        hip_z = joints['pelvis'].z

        def allowed(name, p):
            if name.startswith(('UpperArm', 'LowerArm')):
                sign = 1 if name.endswith('.L') else -1
                # 身体后方的背包、斗篷不归手臂
                behind = p.dot(f) - joints['chest'].dot(f) < -0.12 * H
                return sign * (p.dot(left) - chest_lat) > half * 0.8 and not behind
            if name.startswith(('Thigh', 'Shin')):
                return p.z < hip_z + 0.03 * H
            return True
    for v in mesh.data.vertices:
        p = mesh.matrix_world @ v.co
        d = sorted((segment_distance(p, a, b), n) for n, a, b in bones if allowed(n, p))
        d0 = d[0][0]
        picked = [(math.exp(-((di - d0) / sigma) ** 2), n) for di, n in d[:3] if di - d0 < 2.5 * sigma]
        total = sum(w for w, _ in picked)
        for w, n in picked:
            mesh.vertex_groups[n].add([v.index], w / total, 'REPLACE')
    return 0


def q_axis(axis, degrees):
    return Quaternion(Vector(axis).normalized(), math.radians(degrees))


def keyframe_clip(rig, name, frames, loop, pose_fn):
    """pose_fn(t) 返回 {骨名: 模型空间四元数} 与髋部模型空间位移；t 为 0..1。"""
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    rests = {b.name: (rig.matrix_world.to_3x3() @ b.matrix_local.to_3x3()).to_quaternion() for b in rig.data.bones}
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    last = frames if loop else frames - 1
    for fr in range(frames + (1 if loop else 0)):
        t = (fr % frames) / frames if loop else fr / max(last, 1)
        rots, offset = pose_fn(t)
        for pb in rig.pose.bones:
            rest = rests[pb.name]
            q = rots.get(pb.name, Quaternion())
            # 模型空间旋转换到骨骼局部：rest⁻¹ · q · rest；父骨的旋转由层级自然累积。
            pb.rotation_quaternion = rest.inverted() @ q @ rest
            pb.keyframe_insert('rotation_quaternion', frame=fr)
        hips = rig.pose.bones['Hips']
        hips.location = rests['Hips'].inverted() @ Vector(offset)
        hips.keyframe_insert('location', frame=fr)
    action.frame_range = (0, frames if loop else last)
    return action


def biped_clips(rig, joints, cfg, H):
    f, left, up = frame_axes(cfg['forward'])
    # 绕左侧轴的正角度：向下的肢体往后摆。前摆取负值。
    swing = lambda deg: q_axis(left, -deg)
    lean = lambda deg: q_axis(left, deg)  # 正值：上身前倾（向上的骨往前倒）
    twist = lambda deg: q_axis(up, deg)
    side = lambda deg: q_axis(f, deg)
    # 主手：手离肩更远的一侧（多半拿着武器）。
    reach = {s: (joints[f'hand.{s}'] - joints[f'shoulder.{s}']).length for s in ('L', 'R')}
    main = cfg.get('main') or max(reach, key=reach.get)
    off = 'R' if main == 'L' else 'L'
    s_main = 1 if main == 'L' else -1

    def gait(t, amp_leg, amp_knee, amp_arm, elbow, bob, tilt):
        a = math.sin(t * 2 * math.pi)
        # 膝、肘的弯曲：小腿往后（swing 负角），前臂往前（swing 正角）。
        knee_l = amp_knee * max(0.0, -math.sin(t * 2 * math.pi + 0.6))
        knee_r = amp_knee * max(0.0, math.sin(t * 2 * math.pi + 0.6))
        rots = {
            'Thigh.L': swing(amp_leg * a), 'Thigh.R': swing(-amp_leg * a),
            'Shin.L': swing(-knee_l), 'Shin.R': swing(-knee_r),
            'UpperArm.L': swing(-amp_arm * a), 'UpperArm.R': swing(amp_arm * a),
            'LowerArm.L': swing(elbow), 'LowerArm.R': swing(elbow),
            'Spine': lean(tilt) @ twist(4 * a),
            'Head': lean(-tilt * 0.6),
        }
        return rots, up * (bob * H * abs(math.cos(t * 2 * math.pi)))

    def idle(t):
        a = math.sin(t * 2 * math.pi)
        return {'Spine': lean(1.5 * a), 'Neck': lean(-1.0 * a), 'Head': side(1.5 * math.sin(t * 2 * math.pi + 1.0)),
                'UpperArm.L': swing(2.5 * a), 'UpperArm.R': swing(-2.5 * a),
                'Thigh.L': swing(0.0), 'Thigh.R': swing(0.0)}, up * (0.006 * H * a)

    style = cfg.get('attack', 'swing')
    top = cfg.get('raise', 100)
    e = lambda x: x * x * (3 - 2 * x)

    def attack(t):
        # 0–0.45 蓄力，0.45–0.6 出手，0.6–1 收回
        wind = e(min(t / 0.45, 1.0))
        strike = e(max(0.0, min((t - 0.45) / 0.15, 1.0)))
        back = 1.0 - max(0.0, (t - 0.6) / 0.4)
        hold = wind * (1 - strike)
        if style == 'draw':
            # 弓手：持弓手平举向前，另一手后拉弓弦，出手时松开前送
            rots = {f'UpperArm.{main}': swing(70 * wind * back) @ side(-s_main * 10 * wind * back),
                    f'LowerArm.{main}': swing(-10 * wind * back),
                    f'UpperArm.{off}': swing((55 * hold + 70 * strike) * back) @ side(s_main * 25 * hold * back),
                    f'LowerArm.{off}': swing(100 * hold * back),
                    'Spine': twist(s_main * 25 * wind * back) @ lean(-5 * hold * back),
                    'Head': twist(-s_main * 20 * wind * back)}
            return rots, Vector()
        if style == 'slam':
            arm = (top * hold + 25 * strike) * back
            rots = {'UpperArm.L': swing(arm), 'UpperArm.R': swing(arm),
                    'LowerArm.L': swing(40 * hold * back), 'LowerArm.R': swing(40 * hold * back),
                    'Spine': lean((-10 * hold + 28 * strike) * back), 'Head': lean((5 * hold - 15 * strike) * back),
                    'Thigh.L': swing(-12 * strike * back), 'Thigh.R': swing(-12 * strike * back),
                    'Shin.L': swing(-20 * strike * back), 'Shin.R': swing(-20 * strike * back)}
            return rots, up * (-0.05 * H * strike * back)
        rots = {
            f'UpperArm.{main}': swing((top * hold + 35 * strike) * back) @ side(-s_main * 12 * wind * back),
            f'LowerArm.{main}': swing(50 * hold * back),
            f'UpperArm.{off}': swing((-20 * wind + 15 * strike) * back),
            'Spine': lean((-10 * hold + 16 * strike) * back) @ twist(s_main * (18 * wind - 32 * strike) * back),
            'Thigh.L': swing(-10 * strike * back), 'Thigh.R': swing(8 * strike * back),
            'Head': lean((4 * hold - 6 * strike) * back),
        }
        return rots, up * (-0.02 * H * strike * back)

    def hit(t):
        k = math.sin(min(t, 1.0) * math.pi)
        return {'Spine': lean(-16 * k), 'Head': lean(-12 * k), 'UpperArm.L': side(20 * k), 'UpperArm.R': side(-20 * k),
                'Thigh.L': swing(-6 * k), 'Thigh.R': swing(6 * k)}, -f * (0.03 * H * k)

    def talk(t):
        # 说话：主手在胸前比划两次，另一手轻摆，头随节奏点动
        p = t * 2 * math.pi
        g1 = max(0.0, math.sin(p)) ; g2 = max(0.0, math.sin(p * 2 + 1.0))
        # 大臂几乎不动（抬大臂会牵动肩部的头发与衣料），比划主要靠前臂。
        return {f'UpperArm.{main}': swing(6 * g1 + 4),
                f'LowerArm.{main}': swing(50 * g1 + 15),
                f'UpperArm.{off}': swing(3 * g2), f'LowerArm.{off}': swing(22 * g2),
                'Spine': twist(s_main * 6 * math.sin(p)) @ lean(2 * math.sin(p * 2)),
                'Head': lean(6 * math.sin(p * 2)) @ twist(-s_main * 8 * math.sin(p))}, Vector()

    def look(t):
        # 张望：头先转向一侧停住，再转向另一侧，最后回正
        p = t * 2 * math.pi
        turn = 35 * math.sin(p)
        return {'Head': twist(turn), 'Neck': twist(turn * 0.4), 'Spine': twist(turn * 0.15) @ lean(1.5 * math.sin(p * 2)),
                'UpperArm.L': swing(2 * math.sin(p)), 'UpperArm.R': swing(-2 * math.sin(p))}, Vector()

    keyframe_clip(rig, 'Idle', 60, True, idle)
    keyframe_clip(rig, 'Talk', 90, True, talk)
    keyframe_clip(rig, 'Look', 150, True, look)
    g = cfg.get('gait', 1.0)
    arm = cfg.get('arm_gait', 1.0)
    keyframe_clip(rig, 'Walk', 32, True, lambda t: gait(t, 26 * g, 40 * g, 20 * g * arm, 12 * arm, 0.018 * g, 4))
    keyframe_clip(rig, 'Run', 20, True, lambda t: gait(t, 42 * g, 70 * g, 40 * g * arm, 50 * arm, 0.035 * g, 12 * g))
    keyframe_clip(rig, 'Attack', 30, False, attack)
    keyframe_clip(rig, 'Hit', 12, False, hit)
    return main


def quad_clips(rig, joints, cfg, H):
    f, left, up = frame_axes(cfg['forward'])
    swing = lambda deg: q_axis(left, -deg)
    lean = lambda deg: q_axis(left, deg)
    yaw = lambda deg: q_axis(up, deg)

    def gait(t, amp, knee, bob, wag):
        p = t * 2 * math.pi
        # 对角步：左前与右后同相。
        phase = {'Front.L': 0.0, 'Hind.R': 0.0, 'Front.R': math.pi, 'Hind.L': math.pi}
        rots = {}
        for leg, ph in phase.items():
            cap, s = leg.split('.')
            a = math.sin(p + ph)
            rots[f'{cap}Upper.{s}'] = swing(amp * a)
            bend = knee * max(0.0, math.sin(p + ph + 0.8))
            rots[f'{cap}Lower.{s}'] = swing(-bend if cap == 'Front' else bend)
        rots['Spine'] = lean(3 * math.sin(2 * p))
        rots['Neck'] = lean(-4 * math.sin(2 * p + 0.5))
        rots['Tail'] = yaw(wag * math.sin(p)) @ lean(-10)
        rots['TailTip'] = yaw(wag * 0.6 * math.sin(p - 0.8))
        return rots, up * (bob * H * abs(math.cos(p)))

    def idle(t):
        p = t * 2 * math.pi
        return {'Spine': lean(1.5 * math.sin(p)), 'Neck': lean(-2 * math.sin(p + 0.6)),
                'Head': yaw(4 * math.sin(p * 0.5)), 'Tail': yaw(14 * math.sin(p * 2)) @ lean(-15),
                'TailTip': yaw(10 * math.sin(p * 2 - 0.7))}, up * (0.004 * H * math.sin(p))

    def attack(t):
        e = lambda x: x * x * (3 - 2 * x)
        crouch = e(min(t / 0.4, 1.0)); lunge = e(max(0.0, min((t - 0.4) / 0.15, 1.0)))
        back = 1.0 - max(0.0, (t - 0.65) / 0.35)
        k = (crouch * (1 - lunge)) * back
        l = lunge * back
        rots = {'Spine': lean(8 * k - 6 * l), 'Neck': lean(10 * k + 18 * l), 'Head': lean(-10 * k + 14 * l),
                'Snout': lean(-8 * l), 'FrontUpper.L': swing(-15 * k + 35 * l), 'FrontUpper.R': swing(-15 * k + 30 * l),
                'FrontLower.L': swing(25 * k - 10 * l), 'FrontLower.R': swing(25 * k - 10 * l),
                'HindUpper.L': swing(20 * k - 25 * l), 'HindUpper.R': swing(20 * k - 25 * l),
                'Tail': lean(-25 * k + 10 * l)}
        return rots, up * (-0.06 * H * k + 0.04 * H * l) + f * (0.08 * H * l)

    def hit(t):
        k = math.sin(min(t, 1.0) * math.pi)
        return {'Spine': lean(-10 * k), 'Neck': lean(-15 * k), 'Head': yaw(12 * k), 'Tail': lean(-30 * k)}, -f * (0.04 * H * k)

    keyframe_clip(rig, 'Idle', 60, True, idle)
    g = cfg.get('gait', 1.0)
    keyframe_clip(rig, 'Walk', 28, True, lambda t: gait(t, 24 * g, 30 * g, 0.015 * g, 12))
    keyframe_clip(rig, 'Run', 16, True, lambda t: gait(t, 30 * g, 45 * g, 0.035 * g, 20))
    keyframe_clip(rig, 'Attack', 30, False, attack)
    keyframe_clip(rig, 'Hit', 12, False, hit)
    return 'jaw'


def spider_clips(rig, joints, cfg, H):
    """三角步态：按角度顺序交替分成两组，一组抬腿前摆时另一组撑地后蹬；身体随步伐轻颠。
    攻击：前腿高举、身体后仰蓄力，再前扑砸下；受击：身体后缩、腿收拢。"""
    f, left, up = frame_axes(cfg['forward'])
    lean = lambda deg: q_axis(left, deg)
    legs = joints['_legs']
    out = [((joints[f'leg_foot.{i}'] - joints['c']) * Vector((1, 1, 0))).normalized() for i in range(legs)]
    # 绕切向轴转正角使腿向上抬；绕竖轴转使腿前后摆（按腿所在一侧决定方向，保持“前摆”一致）。
    lift = lambda i, deg: q_axis(up.cross(out[i]), -deg)
    sweep = lambda i, deg: q_axis(up, deg * (1 if out[i].dot(left) >= 0 else -1))
    front = [i for i in range(legs) if out[i].dot(f) > 0.3]

    def gait(t, amp, raise_deg, bob):
        p = t * 2 * math.pi
        rots = {}
        for i in range(legs):
            ph = 0.0 if i % 2 == 0 else math.pi
            a = math.sin(p + ph)
            up_amt = raise_deg * max(0.0, math.cos(p + ph))
            rots[f'LegUpper.{i}'] = sweep(i, amp * a) @ lift(i, up_amt)
            rots[f'LegLower.{i}'] = lift(i, -up_amt * 0.6)
        rots['Spine'] = lean(3 * math.sin(2 * p))
        rots['Head'] = lean(-3 * math.sin(2 * p + 0.4))
        return rots, up * (bob * H * abs(math.sin(2 * p)))

    def idle(t):
        p = t * 2 * math.pi
        rots = {'Spine': lean(2 * math.sin(p)), 'Head': q_axis(up, 6 * math.sin(p * 0.5))}
        for i in range(legs):
            rots[f'LegUpper.{i}'] = lift(i, 2.5 * math.sin(p + i))
        return rots, up * (0.01 * H * math.sin(p))

    def attack(t):
        e = lambda x: x * x * (3 - 2 * x)
        rear = e(min(t / 0.45, 1.0)); strike = e(max(0.0, min((t - 0.45) / 0.15, 1.0)))
        back = 1.0 - max(0.0, (t - 0.65) / 0.35)
        k = rear * (1 - strike) * back; l = strike * back
        rots = {'Spine': lean(-14 * k + 10 * l), 'Head': lean(-18 * k + 22 * l)}
        for i in range(legs):
            if i in front:
                rots[f'LegUpper.{i}'] = lift(i, 55 * k - 10 * l)
                rots[f'LegLower.{i}'] = lift(i, -30 * k + 15 * l)
            else:
                rots[f'LegUpper.{i}'] = lift(i, -8 * k)
        return rots, up * (0.08 * H * k - 0.04 * H * l) + f * (0.1 * H * l - 0.04 * H * k)

    def hit(t):
        k = math.sin(min(t, 1.0) * math.pi)
        rots = {'Spine': lean(-12 * k), 'Head': lean(-10 * k)}
        for i in range(legs):
            rots[f'LegUpper.{i}'] = lift(i, 18 * k)
            rots[f'LegLower.{i}'] = lift(i, -25 * k)
        return rots, -f * (0.05 * H * k) + up * (-0.03 * H * k)

    keyframe_clip(rig, 'Idle', 60, True, idle)
    g = cfg.get('gait', 1.0)
    keyframe_clip(rig, 'Walk', 24, True, lambda t: gait(t, 16 * g, 22 * g, 0.012))
    keyframe_clip(rig, 'Run', 14, True, lambda t: gait(t, 22 * g, 30 * g, 0.025))
    keyframe_clip(rig, 'Attack', 30, False, attack)
    keyframe_clip(rig, 'Hit', 12, False, hit)
    return 'jaw'


def preview(rig, mesh, out_dir, name, cfg):
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'TEXTURE'
    scene.render.resolution_x = 480; scene.render.resolution_y = 480
    rig.show_in_front = True
    rig.data.display_type = 'STICK'
    H = max((mesh.matrix_world @ Vector(c)).z for c in mesh.bound_box)
    cam_data = bpy.data.cameras.new('pcam'); cam_data.type = 'ORTHO'; cam_data.ortho_scale = 1.25 * max(H, 0.8)
    cam = bpy.data.objects.new('pcam', cam_data); scene.collection.objects.link(cam); scene.camera = cam
    light = bpy.data.lights.new('sun', 'SUN'); lo = bpy.data.objects.new('sun', light); scene.collection.objects.link(lo)
    f, left, up = frame_axes(cfg['forward'])
    center = Vector((0, 0, H * 0.5))
    shots = []
    clips = (('Idle', [0.0]), ('Talk', [0.25]), ('Look', [0.25]), ('Walk', [0.25])) if name.startswith('villager') else \
        (('Idle', [0.0]), ('Walk', [0.0, 0.25]), ('Run', [0.25]), ('Attack', [0.4, 0.55]), ('Hit', [0.5]))
    for clip, fracs in clips:
        action = bpy.data.actions.get(clip)
        rig.animation_data.action = action
        start, end = action.frame_range
        for frac in fracs:
            scene.frame_set(int(start + (end - start) * frac))
            for view, d in (('side', left), ('front34', (f + left * 0.6).normalized())):
                cam.location = center + d * 4.0
                cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
                path = os.path.join(out_dir, f'{name}-{clip}-{int(frac * 100)}-{view}.png')
                scene.render.filepath = path
                bpy.ops.render.render(write_still=True)
                shots.append(path)
    return shots


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    out_dir = argv[0]
    want_preview = '--preview' in argv
    names = [a for a in argv[1:] if not a.startswith('--')]
    os.makedirs(out_dir, exist_ok=True)
    report = {}
    for name in names:
        cfg = CONFIG[name]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = FPS
        bpy.ops.import_scene.gltf(filepath=source_path(name))
        mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
        straightened = straighten_head(mesh, cfg) if cfg.get('straighten_head') else 0.0
        if straightened:
            print('STRAIGHTENED', name, round(straightened, 1), 'degrees', flush=True)
        verts = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
        H = max(v.z for v in verts)
        joints = {'biped': biped_joints, 'quad': quad_joints, 'spider': spider_joints}[cfg['kind']](verts, cfg)
        rig = build_armature(joints, cfg['kind'])
        missing = bind(mesh, rig, H, joints, cfg)
        main_hand = {'biped': biped_clips, 'quad': quad_clips, 'spider': spider_clips}[cfg['kind']](rig, joints, cfg, H)
        rig.animation_data.action = bpy.data.actions['Idle']
        report[name] = {'straightened_head_degrees': round(straightened, 1), 'missing_weights': missing, 'verts': len(verts), 'main_hand': main_hand,
                        'joints': {k: [round(c, 3) for c in v] for k, v in joints.items() if not k.startswith('_')}}
        print('RIGGED', name, 'missing', missing, 'of', len(verts), 'main', main_hand, flush=True)
        if want_preview:
            preview(rig, mesh, out_dir, name, cfg)
        for o in bpy.data.objects:
            o.select_set(o in (mesh, rig))
        bpy.context.view_layer.objects.active = rig
        out = os.path.join(out_dir, name + '.glb')
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
                                  export_animations=True, export_animation_mode='ACTIONS',
                                  export_skins=True, export_yup=True, export_image_format='AUTO')
        print('EXPORTED', out, os.path.getsize(out), flush=True)
    with open(os.path.join(out_dir, 'rig-report.json'), 'w') as fh:
        json.dump(report, fh, indent=1)


main()
