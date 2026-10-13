"""Preserve the whitebox baseline and retrieve small official asset pages."""
from pathlib import Path
import hashlib
import json
import zipfile
import urllib.request
import re

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build-tools/art-demo'

def main():
    WORK.mkdir(parents=True, exist_ok=True)
    backup = WORK / 'whitebox-baseline.zip'
    if not backup.exists():
        files = [ROOT / n for n in ['project.godot', 'export_presets.cfg', 'README.md', '启动白盒.cmd', '验证白盒.cmd']]
        for directory in ['scripts', 'scenes', 'tests', 'docs']:
            files.extend(p for p in (ROOT / directory).rglob('*') if p.is_file())
        files.extend(p for p in (ROOT / 'build-tools').glob('*.py') if p.name != Path(__file__).name)
        manifest = {}
        with zipfile.ZipFile(backup, 'x', zipfile.ZIP_DEFLATED) as archive:
            for p in files:
                name = p.relative_to(ROOT).as_posix()
                archive.write(p, name)
                manifest[name] = hashlib.sha256(p.read_bytes()).hexdigest()
        (WORK / 'recovery.json').write_text(json.dumps({'archive': str(backup), 'files': manifest,
            'old_package': 'builds/macos/ConjoinedTwins-macOS-universal.zip',
            'package_preservation': 'Existing packaging script copies previous ZIP into history before export.'}, indent=2), encoding='utf-8')
        print('Baseline preserved:', len(manifest), 'files')
    else:
        print('Existing baseline preserved; no overwrite')
    pages = {'mech': 'https://quaternius.com/packs/animatedmech.html',
             'industrial': 'https://kenney.nl/assets/city-kit-industrial'}
    for name, url in pages.items():
        target = WORK / (name + '.html')
        if not target.exists():
            request = urllib.request.Request(url, headers={'User-Agent': 'ConjoinedTwins-ArtDemo/1.0'})
            with urllib.request.urlopen(request, timeout=30) as response:
                target.write_bytes(response.read())
        text = target.read_text(encoding='utf-8')
        links = re.findall(r'href=[\"\x27]([^\"\x27]+)', text)
        print(name, 'license:', 'CC0' in text or 'Creative Commons CC0' in text)
        print('\n'.join(link for link in links if any(k in link.lower() for k in ['download', 'drive.google', '.zip', 'creativecommons', 'itch.io'])))

if __name__ == '__main__':
    main()
