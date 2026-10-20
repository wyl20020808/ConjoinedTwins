"""NPC 模型正/侧视检查图：Blender 后台 Workbench 渲染，背后铺 0.1 单位网格（0 线加粗），
用于在绑定前读取关节坐标。用法：blender -b --python npc_turnaround.py -- <输出目录> <glb...>"""
import bpy, sys, os, json
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
out_dir, paths = argv[0], argv[1:]

def bar(name, loc, scale, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale
    o.data.materials.append(mat)

for path in paths:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    lo = Vector((1e9,)*3); hi = Vector((-1e9,)*3)
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    center = (lo + hi) / 2; size = max(hi - lo) * 1.15
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'FLAT'
    scene.display.shading.color_type = 'MATERIAL'
    scene.render.resolution_x = 768; scene.render.resolution_y = 768
    thin = bpy.data.materials.new('thin'); thin.diffuse_color = (0.25, 0.3, 0.35, 1)
    bold = bpy.data.materials.new('bold'); bold.diffuse_color = (0.9, 0.2, 0.2, 1)
    tex = bpy.data.materials.new('model'); tex.diffuse_color = (0.85, 0.8, 0.7, 1)
    for o in meshes:
        o.data.materials.clear(); o.data.materials.append(tex)
    cam_data = bpy.data.cameras.new('cam'); cam_data.type = 'ORTHO'; cam_data.ortho_scale = size
    cam = bpy.data.objects.new('cam', cam_data); scene.collection.objects.link(cam); scene.camera = cam
    name = os.path.splitext(os.path.basename(path))[0]
    steps = [i / 10 for i in range(-8, 13)]
    for view, offset in {'px': Vector((1, 0, 0)), 'ny': Vector((0, -1, 0))}.items():
        for o in [o for o in bpy.data.objects if o.name.startswith('grid')]:
            bpy.data.objects.remove(o)
        back = center - offset * (size * 0.6)
        for v in steps:
            m = bold if abs(v) < 1e-6 else thin
            w = 0.006 if abs(v) < 1e-6 else 0.0025
            # 水平线（Z 值）与竖线（Y 或 X 值）
            bar(f'grid_h{v}', Vector((back.x, back.y, v)), (0.001 if view=='px' else size*2, size*2 if view=='px' else 0.001, w), m)
            if view == 'px':
                bar(f'grid_v{v}', Vector((back.x, v, center.z)), (0.001, w, size*2), m)
            else:
                bar(f'grid_v{v}', Vector((v, back.y, center.z)), (w, 0.001, size*2), m)
        cam.location = center + offset * size * 3
        cam.rotation_euler = (offset * -1).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(out_dir, f'{name}-{view}.png')
        bpy.ops.render.render(write_still=True)
    with open(os.path.join(out_dir, f'{name}.json'), 'w') as f:
        json.dump({'lo': list(lo), 'hi': list(hi), 'center': list(center), 'ortho': size}, f)
    print('DONE', name, flush=True)
