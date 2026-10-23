"""发布已导出的网页版及配套中继；保留旧网页、服务配置并在失败时恢复。

仅适用于现有 macOS launchd 部署。不会切换源码分支、下载模板或重启 Caddy。
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def reload_service(plist, label):
    domain = 'gui/' + str(os.getuid())
    subprocess.run(['launchctl', 'bootout', domain + '/' + label], check=True)
    # launchd may finish unloading asynchronously; retry only this service's bootstrap.
    for attempt in range(10):
        result = subprocess.run(['launchctl', 'bootstrap', domain, str(plist)], capture_output=True, text=True)
        if result.returncode == 0:
            return
        time.sleep(0.5)
    raise RuntimeError('Relay bootstrap failed: ' + result.stderr.strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--web-root', type=Path, required=True)
    parser.add_argument('--server-root', type=Path, required=True)
    parser.add_argument('--relay-plist', type=Path, required=True)
    args = parser.parse_args()
    source = ROOT / 'builds/web'
    for name in ['index.html', 'index.js', 'index.pck', 'index.wasm']:
        if not (source / name).is_file():
            raise RuntimeError('Missing export: ' + name)
    dirty = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no', '--',
                                    'scripts', 'scenes', 'project.godot'], cwd=ROOT, text=True)
    if dirty.strip():
        raise RuntimeError('Commit game source before publishing')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = args.server_root / 'web-history' / ('before-' + stamp)
    backup.parent.mkdir(parents=True, exist_ok=True)
    release = args.server_root / 'relay-releases' / (commit[:12] + '-' + stamp)
    (release / 'scripts').mkdir(parents=True)
    (release / 'scenes').mkdir()
    for name in ['net_relay.gd', 'net_identity.gd', 'net_manifest.gd']:
        shutil.copy2(ROOT / 'scripts' / name, release / 'scripts' / name)
    shutil.copy2(ROOT / 'scenes/net_relay.tscn', release / 'scenes/net_relay.tscn')
    (release / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="ConjoinedTwins Relay"\n', encoding='utf-8')
    old_plist = args.relay_plist.read_bytes()
    settings = plistlib.loads(old_plist)
    engine = settings['ProgramArguments'][0]
    settings['ProgramArguments'] = [engine, '--headless', '--path', str(release),
                                    'res://scenes/net_relay.tscn', '--', '--port=24680', '--ws-port=24681']
    settings['WorkingDirectory'] = str(release)
    staging = args.web_root.with_name(args.web_root.name + '-staging-' + stamp)
    shutil.copytree(source, staging)
    manifest = {'build': 'journey-continuous-landscape-20261015', 'commit': commit, 'protocol': 4,
                'published_utc': stamp, 'files': {p.name: {'bytes': p.stat().st_size, 'sha256': sha(p)}
                                                for p in sorted(staging.iterdir()) if p.is_file()}}
    (staging / 'version.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    backup.mkdir()
    (backup / 'relay.plist').write_bytes(old_plist)
    published = False
    try:
        args.relay_plist.write_bytes(plistlib.dumps(settings))
        reload_service(args.relay_plist, settings['Label'])
        # Wait for the dedicated relay socket before replacing the live static directory.
        import socket
        deadline = time.monotonic() + 20
        while True:
            try:
                with socket.create_connection(('127.0.0.1', 24681), timeout=1):
                    break
            except OSError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('Relay did not start')
                time.sleep(0.25)
        args.web_root.rename(backup / 'web')
        try:
            staging.rename(args.web_root)
        except Exception:
            (backup / 'web').rename(args.web_root)
            raise
        published = True
        with urllib.request.urlopen('http://127.0.0.1:8080/version.json', timeout=10) as response:
            actual = json.load(response)
        if actual != manifest:
            raise RuntimeError('Live version differs from staged release')
    except Exception:
        if published:
            args.web_root.rename(backup / 'failed-web')
            (backup / 'web').rename(args.web_root)
        args.relay_plist.write_bytes(old_plist)
        # bootstrap may have failed after bootout; unload only if currently loaded.
        subprocess.run(['launchctl', 'bootout', 'gui/' + str(os.getuid()) + '/' + settings['Label']], check=False)
        subprocess.run(['launchctl', 'bootstrap', 'gui/' + str(os.getuid()), str(args.relay_plist)], check=True)
        raise
    print(json.dumps({'commit': commit, 'web_root': str(args.web_root),
                      'backup': str(backup), 'relay_release': str(release)}, indent=2))


if __name__ == '__main__':
    main()
