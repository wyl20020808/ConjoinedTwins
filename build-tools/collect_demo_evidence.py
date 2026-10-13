"""Bind final source, captures, baseline preservation and package evidence."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    package_dir = ROOT / 'builds/macos/evidence-20261012T091835175791Z'
    package = json.loads((package_dir / 'run.json').read_text(encoding='utf-8'))
    test = json.loads((ROOT / 'tests/road_result.json').read_text(encoding='utf-8'))
    recovery = json.loads((ROOT / 'build-tools/art-demo/recovery.json').read_text(encoding='utf-8'))
    assert all(sha(ROOT / name) == digest for name, digest in test['source_sha256'].items())
    retained = {name: sha(ROOT / name) == digest for name, digest in recovery['files'].items()
                if name.startswith('scripts/') or name.startswith('tests/') or name == 'scenes/main.tscn'}
    assert all(retained.values()), 'Old source or test changed'
    assert package['sha256'] == sha(ROOT / 'builds/macos/ConjoinedTwins-macOS-universal.zip')
    assert package['self_test'] == 'pass' and test['self_test'] == 'pass'
    logs = {}
    for name in ['import.log', 'export.log', 'validation.log', 'exported-pck-smoke.log', 'headless.log']:
        payload = (package_dir / name).read_bytes()
        try:
            text = payload.decode('utf-8')
        except UnicodeDecodeError:
            text = payload.decode('gb18030', errors='replace')
        logs[name] = {'error_lines': [line for line in text.splitlines() if 'ERROR:' in line], 'sha256': sha(package_dir / name)}
        assert not logs[name]['error_lines'], name
    captures = json.loads((ROOT / 'docs/screenshots/capture.json').read_text(encoding='utf-8'))
    for capture in captures:
        path = ROOT / capture['file'].removeprefix('res://')
        capture['sha256'] = sha(path)
        assert capture['save_error'] == 0
    result = {'executor_self_test': 'pass', 'production_sources': test['source_sha256'],
              'unchanged_historical_files': retained, 'new_test_count': test['count'], 'finish_seconds': test['finish_seconds'],
              'package': package, 'package_logs': logs, 'captures': captures, 'capture_log_sha256': sha(ROOT / 'tests/capture.log'),
              'decision_review': 'pending', 'controller_tests': [], 'visible_gui': 'deferred_by_work_mode',
              'mac_runtime': 'pending_user_playtest', 'human_input_motion_comfort': 'pending_user_playtest'}
    (ROOT / 'docs/ART_DEMO_EVIDENCE.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Final evidence bound:', test['count'], 'checks;', len(captures), 'production captures;', len(retained), 'unchanged historical files')
    print('Package:', package['size'], 'bytes SHA256', package['sha256'])

if __name__ == '__main__': main()
