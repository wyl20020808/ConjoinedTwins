# 为冒险者角色生成救援用的两段循环动画（RopePull 拉绳、Climb 攀绳），导出为仅含动作的 glb。
# 用法：blender -b --factory-startup --python tools/blender/make_rescue_anims.py -- [预览图目录]
# 角色坐标（Blender 世界系）：前方 -Y，上方 +Z，角色左手 +X。
import bpy, sys, math, os
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, "assets", "humans", "Adventurer_A.glb")
OUTPUT = os.path.join(ROOT, "assets", "humans", "rescue_anims.glb")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = argv[0] if argv else ""
FRAMES = 24
F = Vector((0, -1, 0))
U = Vector((0, 0, 1))
L = Vector((1, 0, 0))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SOURCE)
arm = bpy.data.objects["CharacterArmature"]
scene = bpy.context.scene
M = arm.matrix_world.copy()
Minv = M.inverted()
pose = arm.pose.bones

# 以 Idle 第 0 帧为基础姿势（保留手指等自然弯曲）。
arm.animation_data.action = bpy.data.actions["CharacterArmature|Idle"]
scene.frame_set(0)
base = {pb.name: pb.matrix_basis.copy() for pb in pose}
arm.animation_data.action = None
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)

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
# 链条在骨骼局部系下的偏移（从本骨头部指向下一关节），用于瞄准。
CHAINS = {"UpperArm.L": "LowerArm.L", "LowerArm.L": "Wrist.L", "UpperArm.R": "LowerArm.R", "LowerArm.R": "Wrist.R",
    "UpperLeg.L": "LowerLeg.L", "LowerLeg.L": "Foot.L", "UpperLeg.R": "LowerLeg.R", "LowerLeg.R": "Foot.R"}
OFFSET = {}
LENGTH = {}
for bone, child in CHAINS.items():
    delta = head(child) - head(bone)
    OFFSET[bone] = world(pose[bone]).to_3x3().inverted() @ delta
    LENGTH[bone] = delta.length
FOOT_HOME = {side: head("Foot." + side) for side in "LR"}
FOOT_ROT = {side: world(pose["Foot." + side]).to_3x3().normalized() for side in "LR"}
SHOULDER = {side: head("UpperArm." + side) for side in "LR"}

def set_world(pb, matrix):
    pb.matrix = Minv @ matrix
    update()

def rotate(name, axis, angle, pivot):
    turn = Matrix.Translation(pivot) @ Matrix.Rotation(angle, 4, axis) @ Matrix.Translation(-pivot)
    set_world(pose[name], turn @ world(pose[name]))

def shift(name, offset):
    set_world(pose[name], Matrix.Translation(offset) @ world(pose[name]))

def aim(name, target):
    pb = pose[name]
    start = M @ pb.head
    current = world(pb).to_3x3() @ OFFSET[name]
    turn = current.rotation_difference(target - start).to_matrix().to_4x4()
    set_world(pb, Matrix.Translation(start) @ turn @ Matrix.Translation(-start) @ world(pb))

def limb(upper, lower, target, pole):
    # 解析两段 IK：在 pole 方向弯曲，够不到时伸直指向目标。
    a = head(upper)
    l1, l2 = LENGTH[upper], LENGTH[lower]
    d = target - a
    dist = min(max(d.length, abs(l1 - l2) + 0.001), (l1 + l2) * 0.999)
    direction = d.normalized()
    end = a + direction * dist
    along = (l1 * l1 + dist * dist - l2 * l2) / (2 * dist)
    rise = math.sqrt(max(0.0, l1 * l1 - along * along))
    side = (pole - direction * pole.dot(direction)).normalized()
    aim(upper, a + direction * along + side * rise)
    aim(lower, end)
    return end

def foot(side, target, pitch=0.0):
    rotation = Matrix.Rotation(pitch, 3, L) @ FOOT_ROT[side]
    set_world(pose["Foot." + side], Matrix.Translation(target) @ rotation.to_4x4())

def ease(t):
    return 0.5 - 0.5 * math.cos(math.pi * t)

def lean_body(back, down, lean):
    pivot = head("Hips")
    # 绕 X 轴负角度使胸口移向 +Y（角色背后），即后仰。
    rotate("Body", L, -lean, pivot)
    shift("Body", -F * back - U * down)

def legs(targets, pole, pitches=(0.0, 0.0)):
    for i, side in enumerate("LR"):
        end = limb("UpperLeg." + side, "LowerLeg." + side, targets[i], pole)
        foot(side, end, pitches[i])

def grip_cycle(p, near, far, arc):
    # p < 0.5：握绳把手从 far 拉到 near；之后松手绕弧线回到 far。
    if p < 0.5:
        return far.lerp(near, ease(p / 0.5))
    u = (p - 0.5) / 0.5
    return near.lerp(far, ease(u)) + arc * math.sin(math.pi * u)

def rope_pull(s):
    pulse = 0.5 - 0.5 * math.cos(4 * math.pi * s)
    lean_body(0.10 + 0.04 * pulse, 0.14 + 0.03 * pulse, math.radians(16 + 7 * pulse))
    rotate("Chest", U, 0.14 * math.sin(2 * math.pi * s), head("Chest"))
    rotate("Head", L, math.radians(12 + 5 * pulse), head("Head"))
    stance = [FOOT_HOME["L"] + F * 0.26 + L * 0.04, FOOT_HOME["R"] - F * 0.24 - L * 0.04]
    legs(stance, F + L * 0.2)
    for i, side in enumerate("LR"):
        sign = 1 if side == "L" else -1
        near = Vector((sign * 0.10, 0.06, 0.98))
        far = Vector((sign * 0.05, -0.28, 1.16))
        hand = grip_cycle((s + 0.5 * i) % 1.0, near, far, U * 0.10 + L * sign * 0.10)
        limb("UpperArm." + side, "LowerArm." + side, hand, -U + L * sign * 0.6 - F * 0.3)

def climb(s):
    bob = math.sin(4 * math.pi * s)
    lean_body(-0.02, -0.04 * bob, math.radians(6))
    rotate("Head", L, math.radians(-14), head("Head"))
    for i, side in enumerate("LR"):
        sign = 1 if side == "L" else -1
        high = Vector((sign * 0.06, -0.20, 1.76))
        low = Vector((sign * 0.07, -0.24, 1.22))
        hand = grip_cycle((s + 0.5 * i) % 1.0, high, low, L * sign * 0.12 - F * 0.04)
        limb("UpperArm." + side, "LowerArm." + side, hand, -U * 0.5 + L * sign - F * 0.4)
    # 双脚交替蹬崖壁：与同侧手相反相位。
    targets = []
    pitches = []
    for i, side in enumerate("LR"):
        sign = 1 if side == "L" else -1
        q = (s + 0.5 * i + 0.5) % 1.0
        step = ease(q / 0.5) if q < 0.5 else 1.0 - ease((q - 0.5) / 0.5)
        targets.append(Vector((sign * 0.14, -0.26 - 0.04 * step, 0.12 + 0.34 * step)))
        pitches.append(-0.5 - 0.4 * step)
    legs(targets, F + U * 0.6)

def bake(name, fn):
    action = bpy.data.actions.new(name)
    arm.animation_data.action = action
    for frame in range(FRAMES + 1):
        reset()
        fn((frame % FRAMES) / FRAMES)
        for pb in pose:
            pb.keyframe_insert("location", frame=frame)
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("scale", frame=frame)
    action.use_fake_user = True
    return action

if arm.animation_data is None:
    arm.animation_data_create()
actions = [bake("RopePull", rope_pull), bake("Climb", climb)]

def preview(folder):
    os.makedirs(folder, exist_ok=True)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 360
    scene.render.resolution_y = 360
    scene.display.shading.color_type = "OBJECT"
    bpy.ops.mesh.primitive_cylinder_add(radius=0.015, depth=4)
    rope = bpy.context.active_object
    camera = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.4
    scene.collection.objects.link(camera)
    scene.camera = camera
    views = {"side": (Vector((4, 0, 0.9)), (math.radians(90), 0, math.radians(90))),
        "back": (Vector((2.6, 2.6, 1.6)), (math.radians(75), 0, math.radians(135)))}
    for action in actions:
        arm.animation_data.action = action
        if action.name == "Climb":
            rope.location = (0, -0.22, 1.5)
            rope.rotation_euler = (0, 0, 0)
        else:
            rope.location = (0, -1.4, 0.75)
            rope.rotation_euler = (math.radians(-80), 0, 0)
        for view, (where, angles) in views.items():
            camera.location = where
            camera.rotation_euler = angles
            for frame in (0, 6, 12, 18):
                scene.frame_set(frame)
                scene.render.filepath = os.path.join(folder, "%s_%s_%02d.png" % (action.name, view, frame))
                bpy.ops.render.render(write_still=True)

if PREVIEW:
    preview(PREVIEW)

# 只保留骨架和一个小的蒙皮网格（保证导出蒙皮信息，Godot 才会生成 Skeleton3D）。
for obj in list(bpy.data.objects):
    if obj.type == "MESH" and obj.name != "Backpack":
        bpy.data.objects.remove(obj, do_unlink=True)
# Blender 5 的分槽动作在 ACTIONS 模式下只可靠导出当前动作；每个动作单独导出一个 glb。
bpy.ops.object.select_all(action="SELECT")
for action in actions:
    arm.animation_data.action = action
    path = os.path.join(os.path.dirname(OUTPUT), "rescue_%s.glb" % action.name.lower())
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animation_mode="ACTIVE_ACTIONS",
        export_force_sampling=True, export_frame_range=False, export_anim_single_armature=True)
    print("EXPORTED", path, action.name)
