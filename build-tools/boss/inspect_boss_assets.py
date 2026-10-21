"""检查 Boss 用 Tripo GLB：尺寸、面数、材质与贴图，并渲染正/侧两张预览。
blender -b --python inspect_boss_assets.py -- <输出目录>"""
import bpy, sys, os, math
from mathutils import Vector
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
out = sys.argv[sys.argv.index('--') + 1]
for name in ['root_colossus', 'root_spike', 'seed_pod', 'binding_root', 'root_wall']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, 'source', name + '.glb') if name == 'root_colossus' else os.path.join(ROOT, 'assets/boss', name + '.glb'))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3); faces = 0
    for o in meshes:
        faces += len(o.data.polygons)
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    mats = {m.name for o in meshes for m in o.data.materials if m}
    imgs = [(i.name, tuple(i.size)) for i in bpy.data.images]
    print('ASSET', name, 'meshes', len(meshes), 'faces', faces, 'min', tuple(round(v, 3) for v in lo), 'max', tuple(round(v, 3) for v in hi), 'mats', mats, 'imgs', imgs)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = scene.render.resolution_y = 512
    world = bpy.data.worlds.new('w'); world.color = (0.6, 0.6, 0.6); scene.world = world
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); scene.collection.objects.link(sun)
    sun.rotation_euler = (0.8, 0.2, 0.5); sun.data.energy = 3
    center = (lo + hi) / 2; size = max(hi - lo)
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); scene.collection.objects.link(cam); scene.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = size * 1.2
    for label, direction in [('front', Vector((0, -1, 0))), ('side', Vector((1, 0, 0)))]:
        cam.location = center - direction * size * 3
        cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(out, f'{name}_{label}.png')
        bpy.ops.render.render(write_still=True)
