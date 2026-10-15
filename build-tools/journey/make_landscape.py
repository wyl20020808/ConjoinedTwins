"""Blender 后台生成可实例化的乔木、林下植物和村庄生活道具。
不嵌入重复贴图；运行时复用项目 PBR 材质。每个 GLB 只保留一个合并网格。
"""
import bpy, math, random, json, hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/landscape'
OUT.mkdir(exist_ok=True)
records=[]
colors=[('Bark',(.25,.17,.105,1)),('Leaf',(.12,.24,.065,1)),('Stone',(.32,.32,.27,1)),('Wood',(.33,.23,.13,1)),('Cloth',(.53,.38,.23,1)),('Iron',(.12,.14,.13,1))]
mats=[]
for name,color in colors:
 m=bpy.data.materials.new(name);m.diffuse_color=color;m.use_nodes=True;m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=color;mats.append(m)
class Mesh:
 def __init__(self): self.v=[];self.f=[];self.material=[]
 def face(self,points,mat):
  start=len(self.v);self.v.extend(points);self.f.append(tuple(range(start,start+len(points))));self.material.append(mat)
 def branch(self,a,b,r1,r2,mat=0,sides=7):
  a,b=Vector(a),Vector(b);axis=(b-a).normalized();u=axis.cross(Vector((0,1,0)))
  if u.length<.01:u=Vector((1,0,0))
  u.normalize();v=axis.cross(u).normalized()
  rings=[[p+r*(u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides)) for i in range(sides)] for p,r in [(a,r1),(b,r2)]]
  for i in range(sides):self.face([rings[0][i],rings[0][(i+1)%sides],rings[1][(i+1)%sides],rings[1][i]],mat)
  self.face(list(reversed(rings[0])),mat);self.face(rings[1],mat)
 def leaf(self,p,length,angle,tilt,mat=1):
  p=Vector(p);u=Vector((math.cos(angle),math.sin(angle),tilt)).normalized()*length;v=Vector((-math.sin(angle),math.cos(angle),0))*length*.32
  # 叶片中脉略拱起，轮廓收尖，正反面由运行材质统一照明。
  self.face([p,p+u*.4+v,p+u*.52+Vector((0,0,length*.08))],mat)
  self.face([p,p+u*.52+Vector((0,0,length*.08)),p+u*.4-v],mat)
  self.face([p+u*.4+v,p+u,p+u*.52+Vector((0,0,length*.08))],mat)
  self.face([p+u*.52+Vector((0,0,length*.08)),p+u,p+u*.4-v],mat)
 def box(self,p,size,mat):
  x,y,z=p;a,b,c=[s/2 for s in size];v=[(x+sx*a,y+sy*b,z+sz*c) for sx,sy,sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
  for ids in [(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]:self.face([v[i] for i in ids],mat)
 def save(self,name):
  bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
  mesh=bpy.data.meshes.new(name);mesh.from_pydata(self.v,[],self.f);mesh.update()
  for mat in mats:mesh.materials.append(mat)
  for p,m in zip(mesh.polygons,self.material):p.material_index=m;p.use_smooth=m in [0,1]
  uv=mesh.uv_layers.new(name='UVMap')
  for p in mesh.polygons:
   for i in p.loop_indices:
    v=mesh.vertices[mesh.loops[i].vertex_index].co;uv.data[i].uv=(v.x*1.2+v.y*.5,v.z*.5)
  obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
  bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_materials='EXPORT',export_animations=False)
  file=OUT/(name+'.glb');records.append({'name':name,'bytes':file.stat().st_size,'vertices':len(self.v),'faces':len(self.f),'sha256':hashlib.sha256(file.read_bytes()).hexdigest()})

def tree(seed,birch=False):
 rng=random.Random(seed);mesh=Mesh();height=rng.uniform(12,16);lean=Vector((rng.uniform(-.7,.7),rng.uniform(-.7,.7),height));radius=.23 if birch else .48
 last=Vector((0,0,0))
 for j in range(1,10):
  f=j/9;p=lean*f+Vector((math.sin(f*6)*.16,math.sin(f*5)*.19,0));mesh.branch(last,p,radius*(1-(j-1)/10)**1.1,radius*(1-j/10)**1.1);last=p
 for n in range(6):
  a=n*math.tau/6;mesh.branch((0,0,.3),(math.cos(a)*1.2,math.sin(a)*1.2,.02),radius*.5,.03)
 for n in range(22 if birch else 30):
  angle=n*2.399+seed;h=rng.uniform(.25,.87);origin=lean*h
  length=rng.uniform(2.0,4.7)*(1.0 if not birch else .7)*(1.3-h*.5)
  tip=origin+Vector((math.cos(angle)*length,math.sin(angle)*length,rng.uniform(1,2.3)))
  mesh.branch(origin,tip,.10*(1-h*.6),.016)
  for twig in range(4):
   f=.4+twig*.2;end=origin.lerp(tip,f)+Vector((rng.uniform(-1.2,1.2),rng.uniform(-1.2,1.2),rng.uniform(.1,.7)))
   mesh.branch(origin.lerp(tip,max(0,f-.3)),end,.024,.006,sides=5)
   for leaf in range(14):
    p=end+Vector((rng.uniform(-.8,.8),rng.uniform(-.8,.8),rng.uniform(-.5,.7)))
    mesh.leaf(p,rng.uniform(.25,.55),rng.random()*math.tau,rng.uniform(-.5,.5))
 mesh.save('birch' if birch else 'oak_%d'%seed)
for seed in [7,17]:tree(seed)
tree(31,True)
mesh=Mesh();rng=random.Random(77)
for frond in range(11):
 a=frond*2.399;length=rng.uniform(.65,1.05);tip=Vector((math.cos(a)*length,math.sin(a)*length,.35))
 mesh.branch((0,0,0),tip,.008,.002,sides=4)
 for n in range(1,11):
  f=n/11;p=tip*f+Vector((0,0,math.sin(f*math.pi)*.35))
  for side in [-1,1]:mesh.leaf(p,(1-f)*.23+.035,a+side*1.05,.1)
mesh.save('fern')
mesh=Mesh();rng=random.Random(28)
for i in range(32):
 a=rng.random()*math.tau;p=Vector((rng.uniform(-.4,.4),rng.uniform(-.4,.4),0));h=rng.uniform(.15,.5);v=Vector((math.cos(a)*.05,math.sin(a)*.05,0));tip=p+Vector((math.cos(a)*.12,math.sin(a)*.12,h));mesh.face([p-v,p+v,tip],1)
mesh.save('grass')
mesh=Mesh();rng=random.Random(19)
for n in range(20):
 a=rng.random()*math.tau;p=Vector((math.cos(a)*rng.random()*.7,math.sin(a)*rng.random()*.7,rng.uniform(.2,.9)));mesh.branch((0,0,0),p,.018,.005,sides=5)
 for k in range(9):mesh.leaf(p+Vector((rng.uniform(-.3,.3),rng.uniform(-.3,.3),rng.uniform(-.2,.2))),rng.uniform(.15,.28),rng.random()*math.tau,.3)
mesh.save('shrub')
mesh=Mesh()
for n in range(12):
 a=n*math.tau/12
 for row in range(3):
  mesh.box((math.cos(a)*1.0,math.sin(a)*1.0,.17+row*.32),(.45,.35,.29),2)
for x in [-1.15,1.15]:mesh.box((x,0,1.6),(.12,.16,2.4),3)
mesh.branch((-1.4,0,2.65),(1.4,0,2.65),.10,.10,3)
mesh.branch((0,0,.2),(0,0,2.65),.015,.015,4)
mesh.save('well')
mesh=Mesh()
for n in range(6):mesh.branch((-.7,(n%3)*.3,n//3*.3+.15),(.7,(n%3)*.3,n//3*.3+.15),.14,.12,0,sides=8)
mesh.save('woodpile')
mesh=Mesh();mesh.branch((0,0,0),(0,0,1),.36,.32,3,sides=12)
for h in [.1,.45,.85]:
 for i in range(12):
  a=i*math.tau/12;b=(i+1)*math.tau/12;mesh.branch((math.cos(a)*.365,math.sin(a)*.365,h),(math.cos(b)*.365,math.sin(b)*.365,h),.023,.023,5,sides=4)
mesh.save('barrel')
mesh=Mesh()
for x in [-2,2]:mesh.branch((x,0,0),(x,0,2.6),.05,.04,3)
mesh.branch((-2,0,2.4),(2,0,2.4),.009,.009,4,sides=4)
for n in range(5):
 x=-1.6+n*.7;mesh.face([(x,0,2.4),(x+.5,0,2.4),(x+.54,.08,1.5),(x+.05,.08,1.45)],4)
mesh.save('washing_line')
( ROOT/'build-tools/journey/landscape-assets.json').write_text(json.dumps({'generator':'make_landscape.py','license':'Project-generated; CC0','assets':records},indent=2))
print('LANDSCAPE ASSETS',len(records))
# 既有建筑只转换成无贴图的静态网格；共享 PBR 贴图在运行时绑定，避免每栋房子重复解码。
for name in ['house_0','house_1','house_2','fence']:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/journey'/(name+'.glb')))
 objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
 for obj in objects:
  for slot in obj.material_slots:
   if slot.material:
    old=slot.material.name
    key='Wood' if 'oak' in old.lower() else ('Stone' if 'stone' in old.lower() else ('Roof' if 'tiles' in old.lower() else ('Plaster' if 'plaster' in old.lower() else ('Iron' if 'iron' in old.lower() else 'Window'))))
    mat=bpy.data.materials.get(key)
    if not mat:
     mat=bpy.data.materials.new(key);mat.diffuse_color=(.35,.3,.24,1)
    slot.material=mat
 bpy.ops.object.select_all(action='DESELECT')
 for obj in objects:obj.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
 target=OUT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animations=False)
 records.append({'name':name,'bytes':target.stat().st_size,'source':'assets/journey/'+name+'.glb','sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
(ROOT/'build-tools/journey/landscape-assets.json').write_text(json.dumps({'generator':'make_landscape.py','license':'Project-generated; CC0','assets':records},indent=2))
# 远景树复用低面数网格；近景仍使用完整叶片。二者共用材质与树干位置。
for name in ['oak_7','oak_17','birch']:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 bpy.ops.import_scene.gltf(filepath=str(OUT/(name+'.glb')))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
 for obj in meshes:
  bpy.context.view_layer.objects.active=obj
  mod=obj.modifiers.new('Distance LOD','DECIMATE');mod.ratio=.24
  bpy.ops.object.modifier_apply(modifier=mod.name)
 target=OUT/(name+'_lod.glb')
 bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',export_animations=False)
 records.append({'name':name+'_lod','bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
(ROOT/'build-tools/journey/landscape-assets.json').write_text(json.dumps({'generator':'make_landscape.py','license':'Project-generated; CC0','assets':records},indent=2))
