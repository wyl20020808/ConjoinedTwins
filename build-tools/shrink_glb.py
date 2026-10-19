"""把 GLB 内嵌贴图缩到指定边长并重写缓冲区；几何不变。用法：shrink_glb.py 输入 输出 [边长]"""
import json,struct,sys,io
from PIL import Image
src,dst=sys.argv[1],sys.argv[2];size=int(sys.argv[3]) if len(sys.argv)>3 else 1024
b=open(src,'rb').read()
L=struct.unpack_from('<I',b,12)[0];j=json.loads(b[20:20+L])
off=20+L;bl=struct.unpack_from('<I',b,off)[0];old=b[off+8:off+8+bl]
replace={}
for im in j.get('images',[]):
    bv=j['bufferViews'][im['bufferView']];o=bv.get('byteOffset',0)
    I=Image.open(io.BytesIO(old[o:o+bv['byteLength']])).convert('RGB')
    if max(I.size)>size:I=I.resize((size,size),Image.LANCZOS)
    out=io.BytesIO();I.save(out,'JPEG',quality=88,optimize=True);replace[im['bufferView']]=out.getvalue()
    im['mimeType']='image/jpeg'
new=bytearray()
for i,bv in enumerate(j['bufferViews']):
    o=bv.get('byteOffset',0);data=replace.get(i,old[o:o+bv['byteLength']])
    while len(new)%4:new.append(0)
    bv['byteOffset']=len(new);bv['byteLength']=len(data);new+=data
while len(new)%4:new.append(0)
j['buffers'][0]['byteLength']=len(new)
js=json.dumps(j,separators=(',',':')).encode()
while len(js)%4:js+=b' '
total=12+8+len(js)+8+len(new)
with open(dst,'wb') as f:
    f.write(struct.pack('<III',0x46546C67,2,total));f.write(struct.pack('<II',len(js),0x4E4F534A));f.write(js)
    f.write(struct.pack('<II',len(new),0x004E4942));f.write(new)
print(dst.split('/')[-1],len(b),'->',total)
