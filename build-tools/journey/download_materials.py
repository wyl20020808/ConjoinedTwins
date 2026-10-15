import concurrent.futures,urllib.request,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/journey'
def fetch(item):
 asset,channel,remote=item
 url=f'https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/{asset}/{asset}_{remote}_1k.jpg'
 target=OUT/f'{asset}_{channel}.jpg'
 if target.exists(): data=target.read_bytes()
 else:
  data=urllib.request.urlopen(url,timeout=30).read()
  if not data.startswith(b'\xff\xd8'):raise RuntimeError('Expected JPEG')
  target.write_bytes(data)
 return dict(path=str(target.relative_to(ROOT)),source=url,page=f'https://polyhaven.com/a/{asset}',license='CC0',bytes=len(data),sha256=hashlib.sha256(data).hexdigest())
items=[('forest_leaves_02','diff','diffuse'),('forest_leaves_02','nor','nor_gl'),('forest_leaves_02','rough','rough'),('wood_planks','diff','diff'),('wood_planks','nor','nor_gl'),('wood_planks','rough','rough')]
records=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
 for future in [pool.submit(fetch,item) for item in items]:
  try: records.append(future.result());print(records[-1]['path'],records[-1]['bytes'],flush=True)
  except Exception as exc:print('DOWNLOAD FAILED',str(exc),flush=True)
(ROOT/'build-tools/journey/material-sources.json').write_text(json.dumps(records,indent=2))
