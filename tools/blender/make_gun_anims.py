# 枪械动作片段：在 Adventurer_A 骨架上为上半身制作收枪、取枪、捡枪、背枪、丢枪、各枪换弹与泵动的关键帧动画。
# 每个片段导出为仅含动作的 glb（assets/humans/gun_anims/gun_<片段>.glb，Godot 导入时按 bonemap 重定向到主角），
# 同时把枪身与双手目标的曲线写入 scripts/gun_action_curves.gd，供游戏按模拟时间采样并用手部 IK 精确贴合。
# 用法：blender -b --factory-startup --python tools/blender/make_gun_anims.py -- [预览图目录]
#
# 坐标约定（与游戏 journey_combat_view.gd 的胸口锚点一致）：
#   以胸口骨骼（Torso = UpperChest）为原点，right/up/forward 为角色右、世界上、角色前，单位为游戏米，
#   以主角手臂总长 0.87 为基准；游戏里按实际手臂长度等比缩放位置。枪的本地坐标为游戏坐标：枪口 -Z、上 +Y。
# Blender 世界系：角色前方 -Y、上方 +Z、角色左手 +X。
import bpy, sys, math, os
from mathutils import Vector, Matrix, Quaternion

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, "assets", "humans", "Adventurer_A.glb")
OUT_DIR = os.path.join(ROOT, "assets", "humans", "gun_anims")
CURVES = os.path.join(ROOT, "scripts", "gun_action_curves.gd")
GUN_PREVIEW = {"smg": "tripo_smg.glb", "shotgun": "tripo_shotgun.glb", "flamer": "tripo_flamer.glb", "launcher": "tripo_launcher.glb"}
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = argv[0] if argv else ""
FPS = 60
GAME_ARM = 0.87

# ---- 游戏侧常量（与 journey_combat_view.gd 保持一致）----
GRIP_RIGHT = Vector((0, -0.10, 0.12))
# 各枪模型的标记点（来自 process_tripo_weapons.py 规整后的 GLB）。
MODEL = {
    "smg": {"grip_left": Vector((0, -0.0315, -0.339)), "mag": Vector((0, -0.052, -0.133)), "handle": Vector((0, 0.147, 0.168))},
    "shotgun": {"grip_left": Vector((0, -0.0798, -0.339)), "port": Vector((0, -0.0865, -0.15))},
    "flamer": {"grip_left": Vector((0, -0.0258, -0.373)), "mag": Vector((0, -0.134, -0.143))},
    "launcher": {"grip_left": Vector((0, -0.0775, -0.3375)), "port": Vector((0, -0.04, -0.1425))},
}
CARRY_GRIP = Vector((0.15, -0.05, 0.35))
CARRY_DIR = Vector((-0.70, 0.55, 0.45))
BACK_OFFSET = Vector((0.0, 0.05, -0.30))
BACK_DIR = Vector((-0.50, 0.85, 0.0))
POUCH = Vector((-0.24, -0.5, 0.14))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SOURCE)
arm = bpy.data.objects["CharacterArmature"]
scene = bpy.context.scene
scene.render.fps = FPS
M = arm.matrix_world.copy()
Minv = M.inverted()
pose = arm.pose.bones
arm.animation_data.action = bpy.data.actions["CharacterArmature|Idle"]
scene.frame_set(0)
base = {pb.name: pb.matrix_basis.copy() for pb in pose}
arm.animation_data.action = None
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)

R = Vector((-1, 0, 0)); U = Vector((0, 0, 1)); F = Vector((0, -1, 0)); L = -R

def update():
    bpy.context.view_layer.update()

def world(pb):
    return M @ pb.matrix

def head(name):
    return M @ pose[name].head

def reset():
    for pb in pose:
        pb.matrix_basis = base[pb.name].copy()
    update()

reset()
CHAINS = {"UpperArm.L": "LowerArm.L", "LowerArm.L": "Wrist.L", "UpperArm.R": "LowerArm.R", "LowerArm.R": "Wrist.R"}
OFFSET = {}; LENGTH = {}
for bone, child in CHAINS.items():
    delta = head(child) - head(bone)
    OFFSET[bone] = world(pose[bone]).to_3x3().inverted() @ delta
    LENGTH[bone] = delta.length
ARM = LENGTH["UpperArm.R"] + LENGTH["LowerArm.R"]
S = ARM / GAME_ARM  # Blender 米 / 游戏米
print("ARM", ARM, "S", S)

def set_world(pb, matrix):
    pb.matrix = Minv @ matrix
    update()

def rotate(name, axis, angle, pivot):
    turn = Matrix.Translation(pivot) @ Matrix.Rotation(angle, 4, axis) @ Matrix.Translation(-pivot)
    set_world(pose[name], turn @ world(pose[name]))

def aim(name, target):
    pb = pose[name]
    start = M @ pb.head
    current = world(pb).to_3x3() @ OFFSET[name]
    turn = current.rotation_difference(target - start).to_matrix().to_4x4()
    set_world(pb, Matrix.Translation(start) @ turn @ Matrix.Translation(-start) @ world(pb))

def limb(upper, lower, target, pole):
    a = head(upper)
    l1, l2 = LENGTH[upper], LENGTH[lower]
    d = target - a
    dist = min(max(d.length, abs(l1 - l2) + 0.001), (l1 + l2) * 0.999)
    direction = d.normalized()
    along = (l1 * l1 + dist * dist - l2 * l2) / (2 * dist)
    rise = math.sqrt(max(0.0, l1 * l1 - along * along))
    side = (pole - direction * pole.dot(direction)).normalized()
    aim(upper, a + direction * along + side * rise)
    aim(lower, a + direction * dist)

def ease(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)

def lerp(a, b, t):
    return a + (b - a) * t

def keys(times, values, t):
    """分段平滑插值；values 为 Vector 或 float。"""
    if t <= times[0]: return values[0]
    for n in range(1, len(times)):
        if t <= times[n]:
            return lerp(values[n - 1], values[n], ease((t - times[n - 1]) / max(1e-6, times[n] - times[n - 1])))
    return values[-1]

# ---- 枪的姿势：用（右手握点、枪口方向、枪身上方）描述，四元数在 (right, up, back) 右手系下 ----
def basis_from(direction, up):
    z = -direction.normalized()
    x = up.cross(z).normalized()
    y = z.cross(x).normalized()
    return Matrix((x, y, z)).transposed()

def roll(direction, up, angle):
    return Quaternion(direction.normalized(), angle) @ up

def to_e(v):
    """(right, up, forward) → (right, up, back)。"""
    return Vector((v.x, v.y, -v.z))

class Gun:
    def __init__(self, grip, direction, up):
        self.basis = basis_from(to_e(direction), to_e(up))
        self.origin = to_e(grip) - self.basis @ GRIP_RIGHT
    def at(self, local):
        return self.origin + self.basis @ local
    @staticmethod
    def blend(a, b, t):
        g = Gun.__new__(Gun)
        g.origin = lerp(a.origin, b.origin, t)
        g.basis = a.basis.to_quaternion().slerp(b.basis.to_quaternion(), t).to_matrix()
        return g

def gun_from_origin(origin, direction, up):
    g = Gun.__new__(Gun)
    g.basis = basis_from(to_e(direction), to_e(up))
    g.origin = to_e(origin)
    return g

CARRY = Gun(CARRY_GRIP, CARRY_DIR, Vector((0, 0, 1)))
BACK = gun_from_origin(BACK_OFFSET, BACK_DIR, Vector((0, 0, -1)))
OVER_R = Gun(Vector((0.34, 0.42, -0.02)), Vector((-0.15, 0.95, -0.25)), Vector((0.2, 0.0, -1)))
LOW_R = Gun(Vector((0.36, -0.72, 0.42)), Vector((0.05, -0.45, 0.9)), Vector((0, 1, 0)))
RELEASE = Gun(Vector((0.62, 0.05, 0.34)), Vector((0.75, 0.25, 0.6)), Vector((0, 1, 0)))
OVER_L_BACK = gun_from_origin(Vector((-0.30, 0.42, -0.12)), Vector((-0.2, 0.95, -0.2)), Vector((0, 0, -1)))
LOW_L = gun_from_origin(Vector((-0.34, -0.66, 0.40)), Vector((-0.2, -0.3, 0.95)), Vector((0, 1, 0)))

def reload_pose(lift, direction, angle):
    d = direction.normalized()
    return Gun(CARRY_GRIP + Vector((0, 0.15, -0.02)) * 1.0 + Vector((0.0, lift, 0.0)), d, roll(d, Vector((0, 0, 1)) - d * d.z, angle))

MAG_POSE = reload_pose(0.0, Vector((-0.55, 0.45, 0.70)), -0.85)
SHELL_POSE = reload_pose(-0.05, Vector((-0.45, 0.35, 0.82)), -1.15)
LAUNCH_POSE = reload_pose(0.0, Vector((-0.30, 0.80, 0.52)), -0.35)
TANK_POSE = reload_pose(-0.04, Vector((-0.6, 0.4, 0.7)), -0.55)

def ef(v):
    """(right, up, forward) 游戏米 → (right, up, back)。"""
    return to_e(v)

# ---- 片段定义：返回本帧的身体姿势与双手、枪、道具 ----
# 每帧字典：gun(Gun) right(E 坐标或 None=握把) left(E 坐标或 None=护木) rw/lw（手在枪上的权重）
#          twist/bend/side（胸口偏航/前俯/侧倾，度）、look（头部俯仰度）、item（道具状态）、back(Gun 背上的第二把，可无)
def holster(u):
    g = Gun.blend(CARRY, OVER_R, ease(u / 0.55)) if u < 0.55 else Gun.blend(OVER_R, BACK, ease((u - 0.55) / 0.45))
    return {"gun": g, "lw": 1 - ease(u / 0.3), "left": ef(Vector((-0.30, -0.55, 0.10))),
        "twist": -22 * math.sin(math.pi * u), "bend": 4, "side": -6 * math.sin(math.pi * u), "look": 0}

def draw(u):
    # 右手先伸到背后握住枪（0–0.3），再越过右肩拉到身前。
    g = BACK if u < 0.3 else (Gun.blend(BACK, OVER_R, ease((u - 0.3) / 0.35)) if u < 0.65 else Gun.blend(OVER_R, CARRY, ease((u - 0.65) / 0.35)))
    right = None
    if u < 0.3:
        right = lerp(ef(Vector((0.30, -0.15, 0.30))), BACK.at(GRIP_RIGHT), ease(u / 0.3))
    return {"gun": g, "right": right, "rw": 1.0 if u >= 0.3 else 0.0, "lw": ease((u - 0.6) / 0.4),
        "left": ef(Vector((-0.30, -0.55, 0.10))),
        "twist": -24 * math.sin(math.pi * min(1, u * 1.2)), "bend": 4, "side": -7 * math.sin(math.pi * u), "look": 0}

def pickup(u):
    # 弯腰伸右手到右前下方接枪（0–0.35），再抬到抱枪位置；左手 0.6 后接上护木。
    g = LOW_R if u < 0.35 else Gun.blend(LOW_R, CARRY, ease((u - 0.35) / 0.65))
    reach = math.sin(math.pi * min(1, u / 0.7))
    return {"gun": g, "lw": ease((u - 0.6) / 0.4), "left": ef(Vector((-0.25, -0.45, 0.25))),
        "twist": -14 * reach, "bend": 34 * reach, "side": -8 * reach, "look": 22 * reach, "item": 1.0 if u < 0.35 else 0.0}

def stow(u):
    # 右手仍握枪；左手弯腰捡起第二把（0–0.3），经左肩甩上背（0.3–0.85），再回护木。
    reach = math.sin(math.pi * min(1, u / 0.6))
    back = LOW_L if u < 0.3 else (Gun.blend(LOW_L, OVER_L_BACK, ease((u - 0.3) / 0.3)) if u < 0.6 else Gun.blend(OVER_L_BACK, BACK, ease((u - 0.6) / 0.25)))
    holding = back.at(Vector((0, -0.05, -0.15)))
    left = holding if u < 0.85 else None
    return {"gun": CARRY, "back": back, "left": left, "lw": ease((u - 0.85) / 0.15),
        "twist": 16 * reach, "bend": 26 * math.sin(math.pi * min(1, u / 0.45)), "side": 8 * reach, "look": 15 * reach}

def toss(u):
    # 向右前方甩出：0.35 时松手，之后枪由游戏按落点抛物线接管。
    g = Gun.blend(CARRY, RELEASE, ease(u / 0.35))
    out = {"gun": g, "lw": 1 - ease(u / 0.2), "left": ef(Vector((-0.30, -0.55, 0.10))), "rw": 1.0 if u < 0.35 else 0.0,
        "right": ef(Vector((0.45, -0.25, 0.30))) if u >= 0.35 else None,
        "twist": -26 * math.sin(math.pi * min(1, u * 1.4)), "bend": 6, "side": -5, "look": 0}
    return out

def reload_mag(u, kind):
    # 冲锋枪：抬枪侧倾，左手拔弹匣丢掉（0.2–0.4），从左腰取新弹匣（0.4–0.56），插入（0.56–0.77），拉机柄（0.8–0.9）。
    m = MODEL[kind]
    lift = ease(u / 0.12) * (1 - ease((u - 0.9) / 0.1))
    g = Gun.blend(CARRY, MAG_POSE, lift)
    grip = g.at(m["grip_left"]); well = g.at(m["mag"])
    pulled = g.at(m["mag"] + Vector((0, -0.34, 0.06))); below = g.at(m["mag"] + Vector((0, -0.28, 0.03)))
    handle = g.at(m["handle"] + Vector((0.06, 0, 0))); handle_back = g.at(m["handle"] + Vector((0.06, 0, 0.18)))
    pouch = ef(POUCH)
    left = keys([0.1, 0.2, 0.32, 0.4, 0.52, 0.56, 0.7, 0.77, 0.82, 0.87, 0.94],
        [grip, well, pulled, pulled, pouch, pouch, below, well, handle, handle_back, grip], u)
    item = 0.0
    if 0.2 <= u < 0.4: item = 1.0
    elif 0.4 <= u < 0.5: item = 2.0
    elif 0.5 <= u < 0.56: item = 3.0
    elif 0.56 <= u < 0.77: item = 1.0
    return {"gun": g, "left": left, "lw": 1.0 if (u < 0.1 or u >= 0.94) else 0.0, "item": item,
        "twist": 10 * lift, "bend": 8 * lift + 6 * math.sin(math.pi * min(1, max(0, (u - 0.38) / 0.24))), "side": 5 * lift, "look": 18 * lift}

def reload_tank(u, kind):
    m = MODEL[kind]
    lift = ease(u / 0.1) * (1 - ease((u - 0.9) / 0.1))
    g = Gun.blend(CARRY, TANK_POSE, lift)
    grip = g.at(m["grip_left"]); tank = g.at(m["mag"]); side = g.basis @ Vector((0.05, 0, 0))
    pouch = ef(POUCH)
    left = keys([0.08, 0.22, 0.3, 0.38, 0.46, 0.6, 0.66, 0.8, 0.86, 0.94],
        [grip, tank, tank + side, tank - side, tank, pouch, pouch, tank, tank, grip], u)
    return {"gun": g, "left": left, "lw": 1.0 if (u < 0.08 or u >= 0.94) else 0.0, "item": 0.0,
        "twist": 8 * lift, "bend": 6 * lift + 6 * math.sin(math.pi * min(1, max(0, (u - 0.45) / 0.3))), "side": 4 * lift, "look": 16 * lift}

def shell_start(u, pose_gun):
    g = Gun.blend(CARRY, pose_gun, ease(u))
    grip = g.at(MODEL["shotgun"]["grip_left"])
    return {"gun": g, "left": lerp(grip, ef(POUCH), ease(u)), "lw": 0.0, "twist": 8 * ease(u), "bend": 7 * ease(u), "side": 4 * ease(u), "look": 16 * ease(u)}

def shell_cycle(u, pose_gun, kind):
    g = pose_gun
    port = g.at(MODEL[kind]["port"]); under = port - (g.basis @ Vector((0, 0.12, 0)))
    pouch = ef(POUCH)
    left = keys([0.0, 0.15, 0.5, 0.7, 0.85, 1.0], [pouch, pouch, under, port, under, pouch], u)
    return {"gun": g, "left": left, "lw": 0.0, "item": 1.0 if 0.15 <= u < 0.72 else 0.0,
        "twist": 8, "bend": 7 + 3 * math.sin(math.pi * u), "side": 4, "look": 16}

def shell_end(u, pose_gun, kind):
    g = Gun.blend(pose_gun, CARRY, ease(u))
    grip = g.at(MODEL[kind]["grip_left"])
    return {"gun": g, "left": lerp(ef(POUCH), grip, ease(u)), "lw": ease((u - 0.8) / 0.2),
        "twist": 8 * (1 - ease(u)), "bend": 7 * (1 - ease(u)), "side": 4 * (1 - ease(u)), "look": 16 * (1 - ease(u))}

def pump(u):
    stroke = math.sin(math.pi * u)
    g = CARRY
    grip = g.at(MODEL["shotgun"]["grip_left"] + Vector((0, 0, 0.16 * stroke)))
    return {"gun": g, "left": grip, "lw": 0.0, "twist": -3 * stroke, "bend": 2 * stroke, "side": 0, "look": 0}

CLIPS = {
    "Holster": (0.25, holster, "smg"),
    "Draw": (0.30, draw, "shotgun"),
    "Pickup": (0.35, pickup, "smg"),
    "Stow": (0.45, stow, "smg"),
    "Toss": (0.30, toss, "shotgun"),
    "ReloadMag": (1.40, lambda u: reload_mag(u, "smg"), "smg"),
    "ReloadTank": (1.80, lambda u: reload_tank(u, "flamer"), "flamer"),
    "ShellStart": (1.0 / 6.0, lambda u: shell_start(u, SHELL_POSE), "shotgun"),
    "ShellLoad": (1.0 / 3.0, lambda u: shell_cycle(u, SHELL_POSE, "shotgun"), "shotgun"),
    "ShellEnd": (0.15, lambda u: shell_end(u, SHELL_POSE, "shotgun"), "shotgun"),
    "Pump": (0.28, pump, "shotgun"),
    "GrenadeStart": (0.25, lambda u: shell_start(u, LAUNCH_POSE), "launcher"),
    "GrenadeLoad": (52.0 / 120.0, lambda u: shell_cycle(u, LAUNCH_POSE, "launcher"), "launcher"),
    "GrenadeEnd": (0.15, lambda u: shell_end(u, LAUNCH_POSE, "launcher"), "launcher"),
}

# ---- 摆姿势 ----
def chest():
    return head("Torso")

def to_world(e):
    """(right, up, back) 游戏米（相对胸口）→ Blender 世界坐标。"""
    return chest() + (R * e.x + U * e.y - F * e.z) * S

def body(frame):
    pivot = head("Abdomen")
    for name, share in (("Abdomen", 0.45), ("Torso", 0.55)):
        p = head(name)
        rotate(name, U, math.radians(frame.get("twist", 0)) * share, p)
        rotate(name, L, math.radians(frame.get("bend", 0)) * share, p)
        rotate(name, F, math.radians(frame.get("side", 0)) * share, p)
    look = math.radians(frame.get("look", 0))
    rotate("Neck", L, look * 0.4, head("Neck"))
    rotate("Head", L, look * 0.6, head("Head"))
    rotate("Head", U, -math.radians(frame.get("twist", 0)) * 0.5, head("Head"))

def hands(frame, kind):
    gun = frame["gun"]
    right = frame.get("right") if frame.get("right") is not None and frame.get("rw", 1.0) < 0.5 else gun.at(GRIP_RIGHT)
    lw = frame.get("lw", 1.0)
    on_gun = gun.at(MODEL[kind]["grip_left"])
    loose = frame.get("left") if frame.get("left") is not None else on_gun
    left = lerp(loose, on_gun, lw)
    limb("UpperArm.R", "LowerArm.R", to_world(right), -U * 0.6 + R * 1.0 + F * 0.1)
    limb("UpperArm.L", "LowerArm.L", to_world(left), -U * 0.6 + L * 1.0 + F * 0.1)
    return right, left

if arm.animation_data is None:
    arm.animation_data_create()
records = {}
actions = []
for name, (length, fn, kind) in CLIPS.items():
    action = bpy.data.actions.new("Gun" + name)
    arm.animation_data.action = action
    count = max(2, round(length * FPS))
    rows = []
    for frame in range(count + 1):
        u = frame / count
        reset()
        data = fn(u)
        body(data)
        right, left = hands(data, kind)
        for pb in pose:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("location", frame=frame)
        gun = data["gun"]
        q = gun.basis.to_quaternion()
        back = data.get("back")
        bq = back.basis.to_quaternion() if back else Quaternion((1, 0, 0, 0))
        row = [gun.origin.x, gun.origin.y, gun.origin.z, q.x, q.y, q.z, q.w,
            right.x, right.y, right.z, float(data.get("rw", 1.0)),
            left.x, left.y, left.z, float(data.get("lw", 1.0)), float(data.get("item", 0.0)),
            (back.origin.x if back else 0.0), (back.origin.y if back else 0.0), (back.origin.z if back else 0.0),
            bq.x, bq.y, bq.z, bq.w]
        rows.append(row)
    action.use_fake_user = True
    records[name] = (length, count, rows)
    actions.append((name, action, kind))
    print("CLIP", name, length, count)

STRIDE = 23
with open(CURVES, "w") as f:
    f.write("# 由 tools/blender/make_gun_anims.py 生成，请勿手改。\n")
    f.write("# 每帧 %d 个数：枪原点(3) 枪朝向四元数(4) 右手目标(3) 右手在握把权重(1) 左手目标(3) 左手在护木权重(1) 道具状态(1) 背枪原点(3) 背枪四元数(4)。\n" % STRIDE)
    f.write("# 坐标相对胸口骨骼，轴为 (角色右, 世界上, 角色后)，单位为游戏米（手臂长 %.2f 为基准）。\n" % GAME_ARM)
    f.write("extends RefCounted\n\nconst FPS := %d\nconst STRIDE := %d\nconst ARM := %.2f\nconst CLIPS := {\n" % (FPS, STRIDE, GAME_ARM))
    for name, (length, count, rows) in records.items():
        flat = ",".join("%.4f" % v for row in rows for v in row)
        f.write('\t"%s":{"length":%.5f,"frames":%d,"data":[%s]},\n' % (name, length, count + 1, flat))
    f.write("}\n")
print("CURVES", CURVES)

# ---- 预览：每个片段 6 帧，正面斜 ¾ 与身后各一张，拼成对照图 ----
def preview(folder):
    import numpy
    os.makedirs(folder, exist_ok=True)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 320
    scene.render.resolution_y = 400
    scene.render.film_transparent = False
    guns = {}
    for kind, file in GUN_PREVIEW.items():
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "assets", "weapons", file))
        added = set(bpy.data.objects) - before
        root = bpy.data.objects.new("Gun_" + kind, None)
        scene.collection.objects.link(root)
        for obj in added:
            if obj.parent is None:
                obj.parent = root
        guns[kind] = root
    camera = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.5
    scene.collection.objects.link(camera)
    scene.camera = camera
    views = [(Vector((-1.6, -2.6, 1.55)), Vector((0, 0, 1.05))), (Vector((0.9, 2.8, 1.9)), Vector((0, 0, 1.05)))]
    cinv = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))  # glTF 导入的 (x,-z,y) → 游戏 (x,y,z)
    for name, action, kind in actions:
        arm.animation_data.action = action
        length, count, rows = records[name]
        tiles = []
        for k in range(6):
            frame = round(k * count / 5)
            scene.frame_set(frame)
            update()
            row = rows[frame]
            frame_m = Matrix.Identity(4)
            frame_m.col[0][:3] = R * S; frame_m.col[1][:3] = U * S; frame_m.col[2][:3] = -F * S
            frame_m.col[3][:3] = chest()
            for g_kind, root in guns.items():
                for obj in [root] + list(root.children_recursive):
                    obj.hide_render = g_kind != kind
            gm = Quaternion((row[6], row[3], row[4], row[5])).to_matrix().to_4x4()
            gm.translation = Vector(row[0:3])
            guns[kind].matrix_world = frame_m @ gm @ cinv
            for v, (eye, target) in enumerate(views):
                camera.location = eye
                camera.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
                path = os.path.join(folder, "_%s_%d_%d.png" % (name, k, v))
                scene.render.filepath = path
                bpy.ops.render.render(write_still=True)
                image = bpy.data.images.load(path)
                tiles.append(numpy.array(image.pixels[:]).reshape(400, 320, 4))
                bpy.data.images.remove(image)
                os.remove(path)
        # 两行：上为正面斜 ¾，下为身后；Blender 像素自下而上。
        top = numpy.concatenate([tiles[k * 2] for k in range(6)], axis=1)
        bottom = numpy.concatenate([tiles[k * 2 + 1] for k in range(6)], axis=1)
        sheet = numpy.concatenate([bottom, top], axis=0)
        out = bpy.data.images.new("sheet_" + name, sheet.shape[1], sheet.shape[0])
        out.pixels = sheet.ravel()
        out.filepath_raw = os.path.join(folder, "%s.png" % name)
        out.file_format = "PNG"
        out.save()
        print("SHEET", name)
    for root in guns.values():
        root.hide_render = True

if PREVIEW:
    preview(PREVIEW)

# 只保留骨架和一个小的蒙皮网格（保证导出蒙皮信息，Godot 才会生成 Skeleton3D）；每个动作单独导出。
for obj in list(bpy.data.objects):
    if obj.type == "MESH" and obj.name != "Backpack" or obj.type == "EMPTY" or obj.type == "CAMERA":
        bpy.data.objects.remove(obj, do_unlink=True)
os.makedirs(OUT_DIR, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
for name, action, kind in actions:
    arm.animation_data.action = action
    path = os.path.join(OUT_DIR, "gun_%s.glb" % name.lower())
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animation_mode="ACTIVE_ACTIONS",
        export_force_sampling=True, export_frame_range=False, export_anim_single_armature=True)
    print("EXPORTED", path, name)
