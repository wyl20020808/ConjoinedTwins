"""Preserve reviewed production, captures and reports before the scoped fixes."""
from pathlib import Path
import zipfile
import hashlib
import json

root = Path(__file__).resolve().parents[1]
target = root / 'build-tools/art-demo/pre-review-fixes.zip'
if target.exists():
    print('Existing checkpoint retained')
else:
    files = []
    for directory in ['scripts', 'scenes', 'tests', 'docs']:
        files.extend(p for p in (root / directory).rglob('*') if p.is_file())
    files.extend([root / 'build-tools/collect_demo_evidence.py', root / 'ASSET_SOURCES.md'])
    with zipfile.ZipFile(target, 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, path.relative_to(root).as_posix())
    manifest = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    target.with_suffix('.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('Reviewed checkpoint preserved:', len(files), 'files')
