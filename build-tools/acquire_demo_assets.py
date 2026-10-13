"""Download official CC0 assets without browser interaction."""
from pathlib import Path
import urllib.request
import json
import re
import zipfile
import hashlib

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build-tools/art-demo'

def get(url, target):
    if target.exists():
        return target.read_bytes()
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=45) as response:
        data = response.read()
    target.write_bytes(data)
    return data

def main():
    html = (WORK / 'industrial.html').read_text(encoding='utf-8')
    url = re.search(r'https://kenney.nl/[^\"\s]+\.zip', html).group()
    data = get(url, WORK / 'industrial.zip')
    with zipfile.ZipFile(WORK / 'industrial.zip') as archive:
        print('Industrial entries:', archive.namelist()[:35])
        archive.extractall(WORK / 'industrial')
    folder = get('https://drive.google.com/drive/folders/1sueV_4CGMpZC8y30mWfgKK9UaT3mkHBX', WORK / 'mech-drive.html').decode('utf-8')
    # Public folder metadata is embedded in the server response.
    import html as html_parser
    for match in re.finditer(r'data-id="([^"]+)"[^>]*', folder):
        nearby = folder[match.start():match.start()+4000]
        label = re.search(r'aria-label="([^"]+)"', nearby)
        if label:
            print(match.group(1), html_parser.unescape(label.group(1))[:180])
    flat = get('https://drive.google.com/drive/folders/1FGNJXIvvV0LXERKAggV9N_KKDKOQ1pls', WORK / 'mech-gltf.html').decode('utf-8')
    for match in re.finditer(r'data-id="([^"]+)"[^>]*', flat):
        label = re.search(r'aria-label="([^"]+)"', flat[match.start():match.start()+4000])
        if label:
            print(match.group(1), html_parser.unescape(label.group(1))[:180])
    print('Industrial SHA256', hashlib.sha256(data).hexdigest())
    assets = ROOT / 'assets'
    (assets / 'mechs').mkdir(parents=True, exist_ok=True)
    (assets / 'industrial').mkdir(parents=True, exist_ok=True)
    sources = []
    for name, file_id in [('George', '1CEATvzzC1w198kD9DLTamgMD8LsRwV1I'), ('Leela', '1BOAP-hwB8VlR6S9veirq5407h4dp0Vfq')]:
        url = 'https://drive.google.com/uc?export=download&id=' + file_id
        target = assets / 'mechs' / (name + '.gltf')
        payload = get(url, target)
        model = json.loads(payload)
        print(name, 'animations', [a['name'] for a in model.get('animations', [])], 'bytes', len(payload))
        sources.append({'author': 'Quaternius', 'page': 'https://quaternius.com/packs/animatedmech.html',
                        'download': url, 'file': str(target.relative_to(ROOT)), 'license': 'CC0', 'sha256': hashlib.sha256(payload).hexdigest()})
    import shutil
    texture_dir = assets / 'industrial/Textures'
    texture_dir.mkdir(exist_ok=True)
    shutil.copy2(WORK / 'industrial/Models/GLB format/Textures/colormap.png', texture_dir / 'colormap.png')
    shutil.copy2(WORK / 'industrial/License.txt', assets / 'industrial/License.txt')
    for name in ['building-a', 'building-f', 'building-k', 'building-p', 'shipping-container-a', 'detail-tank', 'chimney-large']:
        directory = WORK / 'industrial/Models/GLB format'
        source = directory / (name + '.glb')
        if source.exists():
            shutil.copy2(source, assets / 'industrial' / source.name)
        else:
            print('GLB missing', name)
    sources.append({'author': 'Kenney', 'page': 'https://kenney.nl/assets/city-kit-industrial',
                    'download': re.search(r'https://kenney.nl/[^\"\s]+\.zip', html).group(),
                    'archive': 'build-tools/art-demo/industrial.zip', 'license': 'CC0', 'sha256': hashlib.sha256(data).hexdigest()})
    (WORK / 'sources.json').write_text(json.dumps(sources, indent=2), encoding='utf-8')

if __name__ == '__main__':
    main()
