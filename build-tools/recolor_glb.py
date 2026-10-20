"""把 GLB 颜色贴图中高饱和的暖色（红橙黄）旋转到目标色相，其余像素不变。
用于从同一模型派生不同识别色版本（如橙色水晶门 → 青色水晶门）。
用法：recolor_glb.py 输入 输出 目标色相(0-1，青色约 0.5)
"""
import colorsys
import io
import json
import struct
import sys

from PIL import Image

src, dst, target = sys.argv[1], sys.argv[2], float(sys.argv[3])
b = open(src, "rb").read()
L = struct.unpack_from("<I", b, 12)[0]
j = json.loads(b[20:20 + L])
off = 20 + L
bl = struct.unpack_from("<I", b, off)[0]
old = b[off + 8:off + 8 + bl]
# 只处理被材质当作 baseColor 的贴图。
color_images = set()
for material in j.get("materials", []):
    texture = material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
    if texture is not None:
        color_images.add(j["textures"][texture["index"]]["source"])
replace = {}
for index in color_images:
    image = j["images"][index]
    view = j["bufferViews"][image["bufferView"]]
    start = view.get("byteOffset", 0)
    picture = Image.open(io.BytesIO(old[start:start + view["byteLength"]])).convert("RGB")
    pixels = picture.load()
    width, height = picture.size
    for y in range(height):
        for x in range(width):
            r, g, bl_ = pixels[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, bl_ / 255)
            # 暖色区间 [-0.05, 0.17]，饱和度越高旋转越完整，灰石与木纹基本不受影响。
            warm = h < 0.17 or h > 0.95
            if not warm or s < 0.25:
                continue
            weight = min(1.0, (s - 0.25) / 0.35)
            nh = (h + (target - (h if h < 0.5 else h - 1.0)) * weight) % 1.0
            nr, ng, nb = colorsys.hsv_to_rgb(nh, s, v)
            pixels[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255))
    out = io.BytesIO()
    picture.save(out, "JPEG", quality=90)
    image["mimeType"] = "image/jpeg"
    replace[image["bufferView"]] = out.getvalue()
new = bytearray()
for i, view in enumerate(j["bufferViews"]):
    start = view.get("byteOffset", 0)
    data = replace.get(i, old[start:start + view["byteLength"]])
    while len(new) % 4:
        new.append(0)
    view["byteOffset"] = len(new)
    view["byteLength"] = len(data)
    new += data
while len(new) % 4:
    new.append(0)
j["buffers"][0]["byteLength"] = len(new)
text = json.dumps(j, separators=(",", ":"), ensure_ascii=False).encode()
while len(text) % 4:
    text += b" "
total = 12 + 8 + len(text) + 8 + len(new)
with open(dst, "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, total))
    f.write(struct.pack("<II", len(text), 0x4E4F534A))
    f.write(text)
    f.write(struct.pack("<II", len(new), 0x004E4942))
    f.write(new)
print(dst.split("/")[-1], "recolored", len(replace), "image(s)")
