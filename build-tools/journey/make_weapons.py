"""用 Blender 生成三把新枪的低模 GLB：霰弹枪、喷火器、榴弹发射器。

在 Blender 5.x 后台运行：
  Blender -b --factory-startup --python build-tools/journey/make_weapons.py

约定（与 scripts/journey_combat_view.gd 的手持枪一致）：
- 原点在握把，枪管沿 Blender +Y（导出 glTF 后为 Godot -Z，即枪口朝前）。
- 单位为米，整枪长约 1.0–1.25 米，与现有程序化冲锋枪同尺度。
- 每把枪只用 3–4 个纯色 PBR 材质，不带贴图，体积只有几十 KB。
- 枪口位置写入名为 Muzzle 的空物体，弹匣/油罐/弹鼓写入 Magazine 空物体，供游戏挂枪口焰和左手。
"""
import bpy, os, math

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', '..', 'assets', 'weapons'))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color, metal=0.0, rough=0.6, emit=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = rough
    if emit > 0:
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = emit
    return m


def finish(obj, material, bevel=0.0):
    obj.data.materials.append(material)
    if bevel > 0:
        mod = obj.modifiers.new('bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = 'ANGLE'
    bpy.ops.object.shade_flat()
    return obj


def box(name, center, size, material, bevel=0.008):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return finish(obj, material, bevel)


def tube(name, center, radius, length, material, axis='Y', vertices=12, depth_radius=None):
    # 沿枪管方向（+Y）放置的圆柱；axis='Z' 时竖放。
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=length, location=center)
    obj = bpy.context.active_object
    obj.name = name
    if axis == 'Y':
        obj.rotation_euler = (math.pi / 2, 0, 0)
    elif axis == 'X':
        obj.rotation_euler = (0, math.pi / 2, 0)
    bpy.ops.object.transform_apply(rotation=True)
    return finish(obj, material)


def cone(name, center, r1, r2, length, material, vertices=12):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=length, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = (-math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    return finish(obj, material)


def marker(name, location):
    empty = bpy.data.objects.new(name, None)
    empty.location = location
    bpy.context.scene.collection.objects.link(empty)


def export(name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + '.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_apply=True, export_yup=True)
    print('wrote', path, os.path.getsize(path))


def shotgun():
    reset()
    steel = mat('shotgun_steel', (0.16, 0.18, 0.2), 0.85, 0.35)
    wood = mat('shotgun_wood', (0.42, 0.24, 0.12), 0.0, 0.55)
    brass = mat('shotgun_brass', (0.85, 0.62, 0.22), 0.9, 0.3)
    box('Receiver', (0, 0.08, 0.02), (0.07, 0.26, 0.11), steel)
    tube('Barrel', (0, 0.58, 0.05), 0.022, 0.78, steel)
    tube('MagTube', (0, 0.5, -0.008), 0.018, 0.62, steel)
    box('Pump', (0, 0.42, -0.01), (0.06, 0.2, 0.06), wood, 0.012)
    for n in range(4):
        box('PumpGroove%d' % n, (0, 0.35 + n * 0.045, -0.042), (0.062, 0.012, 0.008), steel, 0.0)
    box('Grip', (0, -0.02, -0.07), (0.05, 0.08, 0.14), wood, 0.012)
    bpy.context.active_object.rotation_euler = (math.radians(-18), 0, 0)
    box('Stock', (0, -0.24, -0.035), (0.06, 0.36, 0.09), wood, 0.015)
    bpy.context.active_object.rotation_euler = (math.radians(6), 0, 0)
    box('ButtPad', (0, -0.43, -0.05), (0.065, 0.03, 0.12), steel, 0.006)
    box('TriggerGuard', (0, 0.02, -0.06), (0.012, 0.08, 0.035), steel, 0.004)
    box('Bead', (0, 0.96, 0.08), (0.012, 0.012, 0.012), brass, 0.0)
    for n in range(3):
        tube('Shell%d' % n, (0.042, 0.02 + n * 0.035, 0.02), 0.011, 0.05, brass, axis='Z', vertices=8)
    marker('Muzzle', (0, 0.98, 0.05))
    marker('Magazine', (0, 0.42, -0.01))
    export('shotgun')


def flamer():
    reset()
    body = mat('flamer_body', (0.22, 0.25, 0.22), 0.6, 0.45)
    tank = mat('flamer_tank', (0.86, 0.36, 0.12), 0.3, 0.45)
    stripe = mat('flamer_stripe', (0.95, 0.82, 0.25), 0.2, 0.5)
    pilot = mat('flamer_pilot', (0.35, 0.75, 1.0), 0.0, 0.3, emit=4.0)
    tube('Body', (0, 0.18, 0.03), 0.045, 0.5, body, vertices=14)
    tube('Shroud', (0, 0.55, 0.03), 0.05, 0.26, body, vertices=14)
    for n in range(5):
        tube('Fin%d' % n, (0, 0.46 + n * 0.045, 0.03), 0.058, 0.012, body, vertices=14)
    cone('Nozzle', (0, 0.76, 0.03), 0.04, 0.022, 0.16, body)
    tube('PilotLight', (0, 0.8, -0.02), 0.012, 0.06, pilot, vertices=8)
    tube('Tank', (0, 0.12, -0.1), 0.065, 0.42, tank, vertices=16)
    tube('TankStripe', (0, 0.12, -0.1), 0.067, 0.05, stripe, vertices=16)
    tube('Hose', (0.04, 0.0, -0.035), 0.012, 0.13, body, axis='Z', vertices=8)
    box('Grip', (0, -0.06, -0.05), (0.05, 0.07, 0.14), body, 0.01)
    bpy.context.active_object.rotation_euler = (math.radians(-15), 0, 0)
    box('FrontGrip', (0, 0.38, -0.06), (0.045, 0.06, 0.12), body, 0.01)
    box('Stock', (0, -0.18, 0.02), (0.05, 0.26, 0.07), body, 0.012)
    marker('Muzzle', (0, 0.86, 0.03))
    marker('Magazine', (0, 0.12, -0.1))
    export('flamer')


def launcher():
    reset()
    olive = mat('launcher_olive', (0.33, 0.38, 0.2), 0.2, 0.6)
    steel = mat('launcher_steel', (0.15, 0.16, 0.17), 0.85, 0.35)
    warn = mat('launcher_warn', (0.95, 0.75, 0.2), 0.1, 0.5)
    box('Frame', (0, 0.12, 0.02), (0.07, 0.34, 0.09), steel, 0.01)
    tube('Drum', (0, 0.16, 0.0), 0.095, 0.16, olive, vertices=6)
    for n in range(6):
        a = n * math.pi / 3
        tube('Chamber%d' % n, (math.cos(a) * 0.06, 0.245, math.sin(a) * 0.06), 0.022, 0.012, steel, vertices=8)
    tube('Barrel', (0, 0.52, 0.03), 0.045, 0.5, olive, vertices=14)
    tube('MuzzleRing', (0, 0.77, 0.03), 0.052, 0.04, warn, vertices=14)
    box('Sight', (0, 0.42, 0.1), (0.02, 0.06, 0.05), steel, 0.004)
    box('Grip', (0, -0.06, -0.06), (0.05, 0.07, 0.14), olive, 0.012)
    bpy.context.active_object.rotation_euler = (math.radians(-15), 0, 0)
    box('FrontGrip', (0, 0.44, -0.05), (0.045, 0.06, 0.11), olive, 0.01)
    box('Stock', (0, -0.19, 0.0), (0.05, 0.3, 0.075), steel, 0.012)
    box('ButtPad', (0, -0.35, -0.01), (0.06, 0.03, 0.1), olive, 0.008)
    marker('Muzzle', (0, 0.8, 0.03))
    marker('Magazine', (0, 0.16, 0.0))
    export('launcher')


shotgun()
flamer()
launcher()
