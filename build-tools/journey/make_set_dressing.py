"""Blender 后台生成林地与村庄布景；每件单网格，共享命名材质，不携带贴图副本。"""
import bpy, math, random, json, hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/landscape'
COLORS={'Bark':(.23,.17,.10,1),'Wood':(.36,.24,.12,1),'Stone':(.34,.36,.31,1),
        'Moss':(.18,.27,.09,1),'Leaf':(.17,.32,.10,1),'Endgrain':(.57,.39,.20,1),
        'ClothRed':(.54,.19,.12,1),'ClothCream':(.75,.65,.43,1),'Clay':(.56,.30,.19,1),
        'Iron':(.12,.15,.14,1),'Glow':(.95,.64,.25,1),'Produce':(.76,.40,.12,1),
        'Soil':(.19,.14,.09,1),'GroundShade':(0,0,0,1)}
mats={}
for name,color in COLORS.items():
 m=bpy.data.materials.new(name);m.diffuse_color=color;m.use_nodes=True
 m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=color;mats[name]=m
records=[]
class Mesh:
 def __init__(self):self.v=[];self.f=[];self.m=[]
 def face(self,points,mat):
  start=len(self.v);self.v.extend(points);self.f.append(tuple(range(start,start+len(points))));self.m.append(mat)
 def box(self,p,size,mat):
  x,y,z=p;a,b,c=[v/2 for v in size]
  pts=[(x+sx*a,y+sy*b,z+sz*c) for sx,sy,sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
  for ix in [(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]:self.face([pts[i] for i in ix],mat)
 def pole(self,a,b,r,mat,r2=None,sides=8,cap=None):
  a,b=Vector(a),Vector(b);axis=(b-a).normalized();u=axis.cross(Vector((0,1,0)))
  if u.length<.01:u=Vector((1,0,0))
  u.normalize();v=axis.cross(u).normalized()
  rings=[[p+radius*(u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides)) for i in range(sides)] for p,radius in [(a,r),(b,r if r2 is None else r2)]]
  for i in range(sides):self.face([rings[0][i],rings[0][(i+1)%sides],rings[1][(i+1)%sides],rings[1][i]],mat)
  self.face(list(reversed(rings[0])),cap or mat);self.face(rings[1],cap or mat)
 def rock(self,p,size,mat,seed):
  rng=random.Random(seed);x,y,z=p;sx,sy,sz=size;segments=8
  rings=[]
  for h,r in [(0,.8),(.35,1),(.78,.8),(1,.3)]:
   rings.append([(x+sx*r*math.cos(i*math.tau/segments)*rng.uniform(.85,1.15),y+sy*r*math.sin(i*math.tau/segments)*rng.uniform(.85,1.15),z+sz*h) for i in range(segments)])
  for k in range(3):
   for i in range(segments):self.face([rings[k][i],rings[k][(i+1)%segments],rings[k+1][(i+1)%segments],rings[k+1][i]],'Moss' if mat=='Stone' and k==2 else mat)
  self.face(rings[-1],mat)
 def leaf(self,p,tip,width,mat='Leaf'):
  p,tip=Vector(p),Vector(tip);d=tip-p;v=Vector((-d.y,d.x,0)).normalized()*width;mid=p.lerp(tip,.5)+Vector((0,0,.06))
  self.face([p,mid+v,tip,mid],mat);self.face([p,mid,tip,mid-v],mat)
 def save(self,name):
  bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
  mesh=bpy.data.meshes.new(name);mesh.from_pydata(self.v,[],self.f);mesh.update();names=list(dict.fromkeys(self.m))
  for key in names:mesh.materials.append(mats[key])
  for face,key in zip(mesh.polygons,self.m):face.material_index=names.index(key)
  uv=mesh.uv_layers.new(name='UVMap')
  for poly in mesh.polygons:
   for loop in poly.loop_indices:
    p=mesh.vertices[mesh.loops[loop].vertex_index].co;uv.data[loop].uv=(p.x*.5+.5,p.y*.5+.5) if name=="detail_contact" else (p.x*.45+p.y*.25,p.z*.5)
  obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
  file=OUT/(name+'.glb');bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',export_animations=False)
  records.append({'file':str(file.relative_to(ROOT)),'bytes':file.stat().st_size,'triangles':sum(len(f)-2 for f in self.f),'sha256':hashlib.sha256(file.read_bytes()).hexdigest()})

m=Mesh();m.pole((-2.1,0,.38),(2.1,.2,.5),.4,'Bark',.3,10,'Endgrain')
for i in range(5):
 x=-1.8+i*.8;m.pole((x,.1,.5),(x+.4,.7,.9),.11,'Bark',.025,6)
 m.rock((x,-.12,.61),(.36,.24,.14),'Moss',i)
m.pole((.6,-1.0,0),(.6,-1.0,.7),.36,'Bark',.27,10,'Endgrain')
for i in range(5):
 a=i*math.tau/5;m.pole((.6,-1,.16),(.6+math.cos(a)*.8,-1+math.sin(a)*.8,.02),.13,'Bark',.025,6)
m.save('detail_deadwood')
m=Mesh()
for i,p in enumerate([(-1.0,.2,0),(.5,0,0),(1.2,.8,0),(-.2,-.8,0)]):m.rock(p,(.8,.7,.7 if i else 1.3),'Stone',31+i)
m.save('detail_moss_rocks')
m=Mesh();rng=random.Random(7)
for plant in range(4):
 root=Vector((rng.uniform(-1,1),rng.uniform(-1,1),0))
 for frond in range(7):
  a=frond*2.399+plant;length=rng.uniform(.65,1.2);end=root+Vector((math.cos(a)*length,math.sin(a)*length,.4))
  m.pole(root,end,.012,'Leaf',.004,4)
  for i in range(1,7):
   f=i/7;p=root.lerp(end,f)+Vector((0,0,math.sin(f*math.pi)*.24))
   for side in [-1,1]:m.leaf(p,p+Vector((math.cos(a+side)*(.32*(1-f)+.08),math.sin(a+side)*(.32*(1-f)+.08),.1)),.06*(1-f)+.02)
for i in range(6):
 x=rng.uniform(-1.5,1.5);y=rng.uniform(-1.5,1.5)
 m.pole((x,y,0),(x,y,.22),.035,'ClothCream',sides=5);m.rock((x,y,.18),(.14,.14,.1),'Clay',i)
m.save('detail_fern_bed')
m=Mesh()
for x in [-1.8,1.8]:
 for y in [-1,1]:m.box((x,y,1.6),(.12,.12,3.2),'Wood')
for y in [-1.05,1.05]:m.box((0,y,2.9),(3.9,.14,.14),'Wood')
for strip in range(8):
 x=-2+strip*.5;mat='ClothRed' if strip%2 else 'ClothCream'
 m.face([(x,-1.25,2.8),(x+.5,-1.25,2.8),(x+.5,0,3.5),(x,0,3.5)],mat)
 m.face([(x,0,3.5),(x+.5,0,3.5),(x+.5,1.25,2.8),(x,1.25,2.8)],mat)
 m.face([(x,-1.25,2.8),(x,-1.25,2.5),(x+.5,-1.25,2.5),(x+.5,-1.25,2.8)],mat)
m.box((0,-.65,1.0),(3.6,.9,.15),'Wood')
for x in [-1.3,0,1.3]:
 m.box((x,-.65,1.2),(1.1,.75,.22),'Wood')
 for n in range(6):m.rock((x+(n%3-1)*.27,-.65+(n//3-.5)*.28,1.3),(.12,.12,.15),'Produce',n)
m.box((1.3,.7,.3),(.8,.8,.6),'Wood');m.pole((-1,.6,0),(-1,.6,.7),.33,'Clay',.28,10)
m.save('detail_market')
m=Mesh()
for x in [-1.4,1.4]:m.box((x,0,1.45),(.15,.15,2.9),'Wood')
m.box((0,.5,.1),(3.3,2.1,.2),'Stone')
m.box((0,-.75,2.9),(3.3,1.8,.13),'Wood')
for x in [-1.6,1.6]:
 m.pole((x,-.5,0),(x,-.5,.6),.3,'Clay',.35,10)
 for n in range(7):
  a=n*2.399;m.leaf((x,-.5,.55),(x+math.cos(a)*.45,-.5+math.sin(a)*.4,1.1),.11)
m.box((.4,-.6,.55),(1.8,.5,.12),'Wood')
for x in [-.3,1.1]:m.box((x,-.6,.25),(.12,.4,.5),'Wood')
m.save('detail_porch')
m=Mesh();m.box((0,0,.07),(3.7,4.6,.14),'Soil')
for x in [-1.85,1.85]:m.box((x,0,.17),(.12,4.6,.22),'Wood')
for y in [-2.3,2.3]:m.box((0,y,.17),(3.7,.12,.22),'Wood')
for x in [-1.2,0,1.2]:
 for y in [-1.7,-.6,.6,1.7]:
  for n in range(5):
   a=n*2.399;m.leaf((x,y,.15),(x+math.cos(a)*.4,y+math.sin(a)*.4,.55),.16)
m.save('detail_garden')
m=Mesh();m.pole((0,0,0),(0,0,3.7),.09,'Iron',.07,8);m.pole((0,0,3.7),(.6,0,3.7),.05,'Iron',sides=6)
m.box((.6,0,3.25),(.38,.38,.6),'Glow')
for x in [.39,.81]:
 for y in [-.21,.21]:m.box((x,y,3.25),(.045,.045,.75),'Iron')
for z in [2.87,3.63]:m.box((.6,0,z),(.55,.55,.09),'Iron')
m.save('detail_lantern')
m=Mesh();m.face([(-1,-1,0),(1,-1,0),(1,1,0),(-1,1,0)],'GroundShade');m.save('detail_contact')
(ROOT/'build-tools/journey/set-dressing-assets.json').write_text(json.dumps({'generator':'make_set_dressing.py','license':'Original project geometry','assets':records},indent=2)+'\n')
print('SET DRESSING',len(records),'bytes',sum(r['bytes'] for r in records))
