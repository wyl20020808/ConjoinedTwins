"""确定性生成有根、分叉树干和独立叶片的轻量树；每棵仅两个材质批次。"""
import bpy
import math
import random
import json
import hashlib
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/landscape'
records = []

for species, seed in [('oak_7', 7), ('oak_17', 17), ('birch', 31)]:
    for lod in [False, True]:
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.delete(use_global=False)
        rng = random.Random(seed)
        vertices, faces, slots, uvs = [], [], [], []

        def face(points, material, tex):
            start = len(vertices)
            vertices.extend(points)
            faces.append(tuple(range(start, start + len(points))))
            slots.append(material)
            uvs.extend(tex)

        def branch(a, b, radius, tip):
            a, b = Vector(a), Vector(b)
            axis = (b-a).normalized()
            right = axis.cross(Vector((0, 1, 0))).normalized()
            up = axis.cross(right).normalized()
            count = 5 if lod else 8
            for n in range(count):
                angles = [2*math.pi*n/count, 2*math.pi*(n+1)/count]
                offsets = [math.cos(t)*right+math.sin(t)*up for t in angles]
                face([a+offsets[0]*radius, a+offsets[1]*radius,
                      b+offsets[1]*tip, b+offsets[0]*tip], 0,
                     [(n/count, 0), ((n+1)/count, 0), ((n+1)/count, (b-a).length), (n/count, (b-a).length)])

        def leaf(center, length, angle, tilt):
            # 叶片不是透明卡片：折起的中脉和不对称轮廓，减少过绘制。
            axis = Vector((math.cos(angle), math.sin(angle), tilt)).normalized()
            across = axis.cross(Vector((0, 0, 1))).normalized()*length*.36
            center = Vector(center)
            points = [center-axis*length*.5, center+across,
                      center+axis*length*.55, center-across,
                      center+Vector((0, 0, length*.075))]
            coords = [(0.5, 0), (0, .45), (.5, 1), (1, .45), (.5, .45)]
            for n in range(4):
                face([points[n], points[(n+1)%4], points[4]], 1,
                     [coords[n], coords[(n+1)%4], coords[4]])

        birch = species == 'birch'
        height = 14 if birch else (12.7 if seed == 7 else 11.8)
        trunk = Vector((0, 0, 0))
        for n in range(7):
            next_point = Vector((math.sin(n*.6)*.35, math.cos(n*.8)*.24, (n+1)*height/8))
            branch(trunk, next_point, (.28 if birch else .52)*(1-n/8), (.28 if birch else .52)*(1-(n+1)/8))
            trunk = next_point
        for n in range(6):
            angle = n*math.pi/3+.3
            branch((math.cos(angle)*1.2, math.sin(angle)*1.2, .025), (0, 0, .8), .06, .22)
        for n in range(28):
            angle = n*2.399+seed
            z = 4.0+n*.28
            reach = (2.0 if birch else 3.6)*(1-.42*n/28)
            base = Vector((.15, 0, z-1))
            end = Vector((math.cos(angle)*reach, math.sin(angle)*reach, z+.5))
            branch(base, end, .065 if birch else .115, .022)
            for twig in range(3):
                tangle = angle+(twig-1)*.65
                tip = end+Vector((math.cos(tangle)*.9, math.sin(tangle)*.9, .5+twig*.12))
                branch(end, tip, .026, .008)
                for k in range(6 if lod else 13):
                    t = rng.uniform(.05, 1.15)
                    center = end.lerp(tip, t)+Vector((rng.uniform(-.65,.65), rng.uniform(-.65,.65), rng.uniform(-.25,.6)))
                    leaf(center, rng.uniform(.7,1.1) if lod else rng.uniform(.42,.8), rng.uniform(0, math.tau), rng.uniform(-.4,.5))
        mesh = bpy.data.meshes.new('NaturalTree')
        mesh.from_pydata(vertices, [], faces)
        mesh.update()
        node = bpy.data.objects.new('NaturalTree', mesh)
        bpy.context.collection.objects.link(node)
        for name, color in [('Bark', (.25,.19,.12,1)), ('NaturalLeaf', (.17,.28,.065,1))]:
            mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
            mat.diffuse_color = color
            mesh.materials.append(mat)
        uv = mesh.uv_layers.new(name='UVMap')
        for index, polygon in enumerate(mesh.polygons):
            polygon.material_index = slots[index]
            polygon.use_smooth = slots[index] == 0
            for loop in polygon.loop_indices:
                uv.data[loop].uv = uvs[loop]
        bpy.context.view_layer.objects.active = node
        node.select_set(True)
        name = 'natural_'+species+('_lod' if lod else '')
        path = OUT/(name+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', export_animations=False)
        assert path.stat().st_size < 5_000_000
        records.append({'file':path.relative_to(ROOT).as_posix(), 'bytes':path.stat().st_size,
                        'triangles':sum(len(f)-2 for f in faces), 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(ROOT/'build-tools/journey/natural-tree-assets.json').write_text(json.dumps(records, indent=2)+'\n')
