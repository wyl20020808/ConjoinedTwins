"""把 GLB 内嵌贴图缩到指定边长并重写缓冲区；几何、材质与扩展字段不变。
保留每张图原格式：JPEG 仍为 JPEG（q88），PNG 仍为 PNG（保留透明通道）。
用法：shrink_glb.py 输入 输出 [边长=1024]；输入输出可为同一路径。"""
import json,struct,sys,io
from PIL import Image
src,dst=sys.argv[1],sys.argv[2];size=int(sys.argv[3]) if len(sys.argv)>3 else 1024
b=open(src,'rb').read()
L=struct.unpack_from('<I',b,12)[0];j=json.loads(b[20:20+L])
off=20+L;bl=struct.unpack_from('<I',b,off)[0];old=b[off+8:off+8+bl]
replace={}
for im in j.get('images',[]):
    bv=j['bufferViews'][im['bufferView']];o=bv.get('byteOffset',0)
    I=Image.open(io.BytesIO(old[o:o+bv['byteLength']]))
    if max(I.size)<=size:continue
    png=I.format=='PNG'
    I=I.convert('RGBA' if png and 'A' in I.getbands() else 'RGB')
    w,h=I.size;k=size/max(w,h);I=I.resize((max(1,round(w*k)),max(1,round(h*k))),Image.LANCZOS)
    out=io.BytesIO()
    if png:I.save(out,'PNG',optimize=True);im['mimeType']='image/png'
    else:I.save(out,'JPEG',quality=88,optimize=True);im['mimeType']='image/jpeg'
    replace[im['bufferView']]=out.getvalue()
new=bytearray()
for i,bv in enumerate(j['bufferViews']):
    o=bv.get('byteOffset',0);data=replace.get(i,old[o:o+bv['byteLength']])
    while len(new)%4:new.append(0)
    bv['byteOffset']=len(new);bv['byteLength']=len(data);new+=data
while len(new)%4:new.append(0)
j['buffers'][0]['byteLength']=len(new)
js=json.dumps(j,separators=(',',':'),ensure_ascii=False).encode()
while len(js)%4:js+=b' '
total=12+8+len(js)+8+len(new)
with open(dst,'wb') as f:
    f.write(struct.pack('<III',0x46546C67,2,total));f.write(struct.pack('<II',len(js),0x4E4F534A));f.write(js)
    f.write(struct.pack('<II',len(new),0x004E4942));f.write(new)
print(dst.split('/')[-1],len(b),'->',total)
