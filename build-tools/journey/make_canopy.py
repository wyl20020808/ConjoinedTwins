"""生成紧凑树冠：少量连续叶簇取代远处亚像素叶片，保留原树资源。"""
import bpy
import random
import math
import json
import hashlib
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/landscape'
records = []
materials = []
for name, color in [('Bark', (.25, .19, .12, 1)), ('Leaf', (.22, .36, .12, 1))]:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    materials.append(mat)


def branch(a, b, radius):
    delta = Vector(b) - Vector(a)
    bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=radius, radius2=radius*.45,
                                    depth=delta.length, location=(Vector(a)+Vector(b))*.5)
    node = bpy.context.object
    node.rotation_euler = delta.to_track_quat('Z', 'Y').to_euler()
    node.data.materials.append(materials[0])


for species, seed in [('oak_7', 7), ('oak_17', 17), ('birch', 31)]:
    for lod in [False, True]:
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.delete(use_global=False)
        rng = random.Random(seed)
        birch = species == 'birch'
        height = 14 if birch else 13
        branch((0, 0, 0), (.3, -.2, height-1), .24 if birch else .48)
        for n in range(24):
            angle = n*2.399+seed
            z = 5.5+n*.29
            reach = (1.7 if birch else 2.8)*(1-.35*n/24)
            center = (math.cos(angle)*reach, math.sin(angle)*reach, z)
            branch((.1, 0, z-1.8), center, .09)
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1 if lod else 2, radius=1, location=center)
            node = bpy.context.object
            node.scale = (rng.uniform(.8, 1.3) if birch else rng.uniform(1.1, 1.75),
                          rng.uniform(1.0, 1.6), rng.uniform(.65, 1.2))
            node.rotation_euler.z = angle
            # 叶簇起伏保留轮廓，连续面积降低闪烁和几何负担。
            for vertex in node.data.vertices:
                vertex.co *= rng.uniform(.88, 1.12)
            node.data.materials.append(materials[1])
            for face in node.data.polygons:
                face.use_smooth = True
        bpy.ops.object.select_all(action='SELECT')
        bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
        bpy.ops.object.join()
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        node = bpy.context.object
        # 保持世界原点在树根，便于复用既有实例变换。
        bpy.context.scene.cursor.location = (0, 0, 0)
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        name = 'grove_'+species+('_lod' if lod else '')
        file = OUT/(name+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(file), export_format='GLB', export_animations=False)
        records.append({'file': str(file.relative_to(ROOT)), 'bytes': file.stat().st_size,
                        'triangles': sum(len(f.vertices)-2 for f in node.data.polygons),
                        'sha256': hashlib.sha256(file.read_bytes()).hexdigest()})
(ROOT/'build-tools/journey/canopy-assets.json').write_text(json.dumps(records, indent=2)+'\n')
