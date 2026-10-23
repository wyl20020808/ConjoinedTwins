"""Blender 后台制作旅程道具；不打开窗口、不执行渲染。
运行：Blender --background --python build-tools/journey/make_assets.py
单位为米，Z 向上；GLB 导出时转换为 Godot 坐标。
"""
import bpy,math,random,json,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/journey'
OUT.mkdir(parents=True,exist_ok=True)
random.seed(42)
records=[]

def material(name,color,texture=None,roughness=.85,metallic=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=roughness;bs.inputs['Metallic'].default_value=metallic
 if texture and texture.exists():
  tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(texture),check_existing=True);m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
  # 木板扫描法线和粗糙度随 GLB 嵌入，避免只贴一张颜色图。
  if texture.name=='wood_planks_diff.jpg':
   for channel,filename in [('normal','wood_planks_nor.jpg'),('rough','wood_planks_rough.jpg')]:
    texpath=texture.parent/filename
    if not texpath.exists():continue
    node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(texpath),check_existing=True);node.image.colorspace_settings.name='Non-Color'
    if channel=='normal':
     normal=m.node_tree.nodes.new('ShaderNodeNormalMap');m.node_tree.links.new(node.outputs['Color'],normal.inputs['Color']);m.node_tree.links.new(normal.outputs['Normal'],bs.inputs['Normal'])
    else:m.node_tree.links.new(node.outputs['Color'],bs.inputs['Roughness'])
 return m
wood=material('Weathered oak',(.29,.18,.095),OUT/'wood_planks_diff.jpg')
wooddark=material('Dark oak',(.12,.072,.035))
plaster=material('Lime plaster',(.55,.51,.4),ROOT/'assets/env/rock_face_03_diff.jpg')
stone=material('Foundation stones',(.32,.33,.29),ROOT/'assets/env/rock_boulder_dry_diff.jpg')
roofmat=material('Clay roof tiles',(.24,.115,.075))
iron=material('Forged iron',(.08,.09,.085),roughness=.45,metallic=.7)
glass=material('Dark window glass',(.065,.11,.12),roughness=.22)
fur=material('Boar brown coat',(.115,.072,.038))
fur_light=material('Boar snout',(.19,.12,.075))
ivory=material('Ivory tusks',(.67,.62,.48))
eye=material('Eye',(.01,.008,.006),roughness=.16)
leaves=material('Pine needles',(.055,.105,.038))
bark=material('Tree bark',(.22,.13,.067),ROOT/'assets/decor/Pine_Bark_NormalTree.png')

def clear():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 bpy.context.scene.frame_start=1;bpy.context.scene.frame_end=25
 bpy.context.scene.render.fps=24

def finish_obj(obj,name,mat):
 obj.name=name;obj.data.materials.append(mat)
 return obj

def cube(name,pos,size,mat,bevel=.025):
 bpy.ops.mesh.primitive_cube_add(size=1,location=pos);o=bpy.context.object;o.dimensions=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('Worn edges','BEVEL');mod.width=bevel;mod.segments=2
  bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
 return finish_obj(o,name,mat)

def sphere(name,pos,size,mat):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=pos);o=bpy.context.object;o.scale=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for face in o.data.polygons:face.use_smooth=True
 return finish_obj(o,name,mat)

def cylinder(name,pos,radius,depth,mat,rotation=None,vertices=16):
 bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=pos);o=bpy.context.object
 if rotation:o.rotation_euler=rotation
 return finish_obj(o,name,mat)

def beam(name,start,end,radius,mat):
 direction=Vector(end)-Vector(start)
 o=cylinder(name,(Vector(start)+Vector(end))/2,radius,direction.length,mat)
 o.rotation_euler=direction.to_track_quat('Z','Y').to_euler();return o

def mesh(name,verts,faces,mat):
 data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
 o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);o.data.materials.append(mat)
 # 每个面有 UV，确保扫描材质在 GLB 中可用。
 uv=data.uv_layers.new(name='UVMap')
 for poly in data.polygons:
  for i,loop in enumerate(poly.loop_indices):uv.data[loop].uv=[(0,0),(1,0),(1,1),(0,1)][i%4]
 return o

def empty(name,pos=(0,0,0)):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=pos;return o

def parent_keep(obj,parent):
 bpy.context.view_layer.update();transform=obj.matrix_world.copy();obj.parent=parent;obj.matrix_world=transform

def animate(obj,prop,values,clip):
 for frame,value in values:
  setattr(obj,prop,value);obj.keyframe_insert(data_path=prop,frame=frame)
 action=obj.animation_data.action;action.name=clip+'_'+obj.name
 track=obj.animation_data.nla_tracks.new();track.name=clip;track.strips.new(action.name,1,action)
 obj.animation_data.action=None

def export(name):
 # 按父节点与材质合并静态部件，保留活动铰点，避免每片屋瓦成为游戏节点。
 groups={}
 for obj in list(bpy.context.scene.objects):
  if obj.type!='MESH' or obj.animation_data:continue
  key=(obj.parent.name if obj.parent else None,tuple(mat.name for mat in obj.data.materials))
  groups.setdefault(key,[]).append(obj)
 for objects in groups.values():
  if len(objects)<2:continue
  bpy.ops.object.select_all(action='DESELECT')
  for obj in objects:obj.select_set(True)
  bpy.context.view_layer.objects.active=objects[0]
  bpy.ops.object.join()
 bpy.context.scene.frame_set(1)
 path=OUT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_yup=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_apply=True)
 data=path.read_bytes();records.append(dict(path=str(path.relative_to(ROOT)),bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),source='build-tools/journey/make_assets.py',license='Project-authored geometry; embedded textures retain CC0'))
 print('ASSET',name,len(data),flush=True)

# 三种村舍：石基、木骨架、坡屋顶、独立瓦片、窗框、门、烟囱。
for variant in range(3):
 clear();w=6.4+variant*.8;d=6.0;h=4.2+variant*.5
 cube('stone foundation',(0,0,.35),(w+.3,d+.3,.7),stone)
 cube('plaster walls',(0,0,h/2+.5),(w,d,h),plaster)
 for x in [-w/2,w/2]:
  for y in [-d/2,d/2]:cube('corner timber',(x,y,h/2+.6),(.22,.22,h+.4),wooddark)
 for z in [.8,2.6,h+.6]:
  for y in [-d/2-.02,d/2+.02]:cube('horizontal beam',(0,y,z),(w+.3,.16,.16),wooddark)
 for y in [-d/2-.02,d/2+.02]:
  for x in [-w*.27,w*.27]:
   cube('window inset',(x,y,2.3),(1.15,.12,1.4),glass)
   for dx in [-.64,.64]:cube('window jamb',(x+dx,y-.08,2.3),(.1,.13,1.6),wood)
   for z in [1.55,2.3,3.05]:cube('window sill',(x,y-.08,z),(1.38,.18,.1),wood)
   cube('window mullion',(x,y-.1,2.3),(.07,.13,1.5),wood)
 cube('oak door',(0,-d/2-.12,1.5),(1.35,.16,2.2),wood)
 sphere('door iron handle',(.43,-d/2-.25,1.45),(.055,.05,.055),iron)
 ridge=h+2.6;eave=h+.5
 mesh('gable', [(-w/2,-d/2,h+.5),(w/2,-d/2,h+.5),(0,-d/2,ridge),(-w/2,d/2,h+.5),(w/2,d/2,h+.5),(0,d/2,ridge)],[(0,1,2),(3,5,4)],plaster)
 for side in [-1,1]:
  slope=math.atan2(ridge-eave,w/2+.5)
  roof=cube('roof surface',(side*(w/4+.2),0,(ridge+eave)/2),(math.hypot(w/2+.5,ridge-eave),d+1,.16),roofmat)
  roof.rotation_euler.y=side*slope
  # 瓦片为实际几何，避免整片纯色屋顶。
  for row in range(6):
   t=(row+.5)/6;x=side*t*(w/2+.45);z=ridge-t*(ridge-eave)+.14
   for col in range(10):
    tile=cube('roof tile',(x,-d/2-.4+col*(d+.8)/10,z),(.72,(d+.8)/10-.025,.06),roofmat,.012);tile.rotation_euler.y=side*slope
 cube('chimney',(w*.27,d*.23,ridge-.1),(.8,.8,2.6),stone)
 cube('chimney cap',(w*.27,d*.23,ridge+1.25),(1.0,1.0,.18),stone)
 if variant==2:
  for x in [-1.8,1.8]:cube('porch post',(x,-d/2-1.3,1.5),(.14,.14,3),wood)
  roof=cube('porch roof',(0,-d/2-.9,3),(4,2,.16),wood);roof.rotation_euler.x=.1
 export('house_'+str(variant))

clear()
cube('cart bed',(0,0,1.05),(1.5,2.3,.16),wood)
for x in [-.78,.78]:
 for z in [1.22,1.5,1.78]:cube('side planks',(x,0,z),(.11,2.3,.18),wood)
 for y in [-1,1]:cube('upright',(x,y,1.5),(.11,.11,1.3),wooddark)
for y in [-1.12,1.12]:cube('end board',(0,y,1.52),(1.5,.1,.75),wood)
for x in [-.94,.94]:
 wheel=empty('Wheel',(x,0,.65))
 bpy.ops.mesh.primitive_torus_add(major_radius=.58,minor_radius=.055,major_segments=24,minor_segments=8,location=(x,0,.65),rotation=(0,math.pi/2,0));o=finish_obj(bpy.context.object,'iron wheel rim',iron);parent_keep(o,wheel)
 hub=cylinder('hub',(x,0,.65),.13,.22,wooddark,(0,math.pi/2,0));parent_keep(hub,wheel)
 for n in range(10):
  angle=n*math.tau/10
  spoke=beam('spoke',(x,0,.65),(x,math.cos(angle)*.56,.65+math.sin(angle)*.56),.035,wood);parent_keep(spoke,wheel)
 animate(wheel,'rotation_euler',[(1,(0,0,0)),(25,(math.tau,0,0))],'WheelTurn')
for x in [-.5,.5]:beam('handle',(x,-.8,1.0),(x,-2.6,.65),.065,wood)
for n in range(3):sphere('grain sack',((n-1)*.4,.2,1.48),(.35,.52,.42),plaster)
export('cart')

# 可辨认的野猪：肩背、长鼻、獠牙、耳朵、鬃毛、四条活动腿。
clear()
body=empty('BoarBody')
for name,pos,size,mat in [('body',(0,0,1.05),(.53,1,.55),fur),('shoulder',(0,-.4,1.25),(.5,.6,.55),fur),('head',(0,-1.0,1.0),(.38,.5,.4),fur),('snout',(0,-1.44,.88),(.25,.28,.2),fur_light)]:parent_keep(sphere(name,pos,size,mat),body)
for x in [-.2,.2]:
 parent_keep(sphere('nostril',(x*.5,-1.69,.92),(.045,.025,.04),eye),body)
 parent_keep(sphere('eye',(x*1.65,-1.12,1.19),(.045,.06,.045),eye),body)
 tusk=beam('curved tusk',(x,-1.4,.8),(x*1.9,-1.52,1.08),.045,ivory);parent_keep(tusk,body)
 ear=mesh('ear',[(x*1.6,-.94,1.25),(x*2,-.72,1.8),(x*.7,-.66,1.4)],[(0,1,2)],fur);parent_keep(ear,body)
for n in range(12):
 y=-.7+n*.12
 parent_keep(beam('coarse mane',(0,y,1.52),(0,y+.1,1.72),.025,fur_light),body)
for x in [-.34,.34]:
 for y in [-.6,.62]:
  leg=empty('Leg',(x,y,.88))
  parent_keep(cylinder('foreleg',(x,y,.55),.12,.65,fur),leg)
  parent_keep(cube('hoof',(x,y-.05,.13),(.24,.32,.2),wooddark),leg)
  phase=1 if (x*y)>0 else -1
  animate(leg,'rotation_euler',[(1,(phase*.45,0,0)),(7,(-phase*.45,0,0)),(13,(phase*.45,0,0)),(19,(-phase*.45,0,0)),(25,(phase*.45,0,0))],'Charge')
animate(body,'location',[(1,(0,0,0)),(7,(0,0,.08)),(13,(0,0,0)),(19,(0,0,.08)),(25,(0,0,0))],'Charge')
beam('tail',(0,.85,1.2),(.08,1.25,1.35),.035,fur)
export('boar')

clear()
trunk=empty('FallPivot')
parent_keep(cylinder('bark trunk',(0,0,5.2),.42,10.4,bark,vertices=20),trunk)
for n in range(6):
 z=3+n*1.25;radius=2.3-n*.3
 bpy.ops.mesh.primitive_cone_add(vertices=16,radius1=radius,radius2=.12,depth=3,location=(0,0,z));parent_keep(finish_obj(bpy.context.object,'needle crown',leaves),trunk)
for n in range(9):
 a=n*2.4;z=2+n*.8
 parent_keep(beam('branch',(0,0,z),(math.cos(a)*1.7,math.sin(a)*1.7,z+.4),.085,bark),trunk)
animate(trunk,'rotation_euler',[(1,(0,0,0)),(6,(0,.06,0)),(12,(0,.25,0)),(18,(0,.8,0)),(25,(0,math.pi/2,0))],'Fall')
export('falling_tree')

clear()
wheel=empty('WheelRotor',(0,0,3))
for x in [-.6,.6]:
 bpy.ops.mesh.primitive_torus_add(major_radius=2.7,minor_radius=.12,major_segments=32,minor_segments=8,location=(x,0,3),rotation=(0,math.pi/2,0));parent_keep(finish_obj(bpy.context.object,'wheel ring',wooddark),wheel)
for n in range(16):
 a=n*math.tau/16
 paddle=cube('water paddle',(0,math.cos(a)*2.7,3+math.sin(a)*2.7),(1.5,.5,.15),wood);paddle.rotation_euler.x=a;parent_keep(paddle,wheel)
 for x in [-.55,.55]:parent_keep(beam('wheel spoke',(x,0,3),(x,math.cos(a)*2.65,3+math.sin(a)*2.65),.07,wood),wheel)
for x in [-1.2,1.2]:cube('stone bearing',(x,0,1.5),(.65,.8,3),stone)
cylinder('axle',(0,0,3),.18,3,iron,(0,math.pi/2,0))
animate(wheel,'rotation_euler',[(1,(0,0,0)),(121,(math.tau,0,0))],'WheelTurn');bpy.context.scene.frame_end=121
export('waterwheel')

clear()
for x in [-3.5,3.5]:cube('stone gate post',(x,0,2.8),(.8,.9,5.6),stone)
cube('gate header',(0,0,5.2),(8,.6,.5),wooddark)
gate=empty('GateLift')
for n in range(13):parent_keep(cube('gate plank',(-3+n*.5,0,2.5),(.35,.28,4.7),wood),gate)
for z in [.6,2.4,4.4]:parent_keep(cube('iron strap',(0,-.2,z),(6.4,.1,.14),iron),gate)
animate(gate,'location',[(1,(0,0,0)),(25,(0,0,5.5))],'GateOpen')
export('gate')

clear()
bridge=empty('BridgePivot',(0,-4,0))
for n in range(20):parent_keep(cube('bridge plank',(0,-3.8+n*.4,0),(6.8,.37,.18),wood),bridge)
for side in [-1,1]:
 parent_keep(cube('stringer',(side*2.3,0,-.25),(.3,8,.4),wooddark),bridge)
 for n in range(5):parent_keep(cube('railing post',(side*3.2,-3.5+n*1.7,.7),(.12,.12,1.5),wood),bridge)
 parent_keep(beam('rope rail',(side*3.2,-3.8,1.4),(side*3.2,3.8,1.4),.04,wooddark),bridge)
animate(bridge,'rotation_euler',[(1,(math.pi/2,0,0)),(25,(0,0,0))],'BridgeLower')
export('drawbridge')

clear()
for x in [-2.7,2.7]:cube('fence post',(x,0,.8),(.15,.15,1.6),wooddark)
for z in [.5,1.2]:cube('fence rail',(0,0,z),(6,.13,.16),wood)
export('fence')
clear()
cube('sign post',(0,0,1.3),(.18,.18,2.6),wooddark)
for z in [2.1,2.6]:cube('sign board',(.4,0,z),(2,.14,.38),wood)
export('sign')
(ROOT/'build-tools/journey/generated-assets.json').write_text(json.dumps(records,indent=2))
print('COMPLETE',len(records),'assets',flush=True)
