import bpy, sys, os, time
from mathutils import Vector
argv = sys.argv[sys.argv.index('--')+1:]
src, dst, target = argv[0], argv[1], int(argv[2])
t0=time.time()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes=[o for o in bpy.data.objects if o.type=='MESH']
tris=0
for o in meshes:
    o.data.calc_loop_triangles(); tris += len(o.data.loop_triangles)
print('BEFORE tris',tris,'meshes',len(meshes), flush=True)
ratio=min(1.0, float(target)/max(1,tris))
for o in meshes:
    bpy.context.view_layer.objects.active=o
    o.select_set(True)
    m=o.modifiers.new('dec','DECIMATE')
    m.decimate_type='COLLAPSE'
    m.ratio=ratio
    m.use_collapse_triangulate=True
    bpy.ops.object.modifier_apply(modifier=m.name)
    o.select_set(False)
after=0
for o in meshes:
    o.data.calc_loop_triangles(); after += len(o.data.loop_triangles)
print('AFTER tris',after,'ratio',round(ratio,5), flush=True)
for img in list(bpy.data.images):
    w,h=img.size
    if w>1024 or h>1024:
        s=1024.0/max(w,h)
        img.scale(max(1,int(w*s)), max(1,int(h*s)))
        img.pack()
        print('IMAGE',img.name,'->',tuple(img.size), flush=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_apply=True,
    export_image_format='AUTO', export_materials='EXPORT', export_texcoords=True,
    export_normals=True, export_yup=True)
print('DONE',dst,os.path.getsize(dst),'secs',round(time.time()-t0,1), flush=True)
