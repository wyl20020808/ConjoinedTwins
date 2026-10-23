"""在独立离屏窗口记录生产展示耗时；策略切回 work 时只停止本次进程。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def idle():
    try:
        return json.loads(Path('D:/PersonalAgent-data/global-interaction-policy.json').read_text(encoding='utf-8-sig')).get('mode') == 'idle'
    except (OSError, ValueError):
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--headless', action='store_true')
    parser.add_argument('--runtime', action='store_true', help='运行现有完整生产循环预算检查')
    args = parser.parse_args()
    output = args.output.resolve()
    if output == ROOT or ROOT in output.parents or (output.exists() and any(output.iterdir())):
        parser.error('输出必须为工程外的空目录')
    output.mkdir(parents=True, exist_ok=True)
    if not args.headless and not idle():
        print('deferred_by_work_mode')
        return 2
    sources = list((ROOT / 'scripts').glob('*.gd')) + list((ROOT / 'scripts').glob('*.gdshader'))
    sources += [ROOT / 'project.godot', ROOT / 'tests/stutter_render_profile.gd', ROOT / 'tests/journey_runtime_budget.gd', ROOT / 'tests/stutter_runtime_profile.gd',
                ROOT / 'tests/fixtures/stutter_timed_view.gd', Path(__file__)]
    hashes = lambda: {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    initial = hashes()
    command = ['D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64.exe', '--path', str(ROOT),
               '--script', 'res://tests/stutter_runtime_profile.gd' if args.runtime else 'res://tests/stutter_render_profile.gd']
    command += ['--headless'] if args.headless else ['--position', '-10000,-10000', '--resolution', '1280x720']
    if args.runtime:
        command += ['--', '--chapter=0']
    env = os.environ.copy()
    env['STUTTER_RENDER_REPORT'] = str(output / 'frames.json')
    env['JOURNEY_PERF_REPORT'] = str(output / 'runtime.json')
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    stopped = ''
    with (output / 'engine.log').open('w', encoding='utf-8') as log:
        with subprocess.Popen(command, env=env, startupinfo=startup, stdout=log, stderr=subprocess.STDOUT) as process:
            deadline = time.monotonic() + 180
            while process.poll() is None:
                if (not args.headless and not idle()) or time.monotonic() > deadline:
                    stopped = 'deferred_by_work_mode' if not args.headless and not idle() else 'timeout'
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                    break
                time.sleep(0.5)
            code = process.wait()
    lines = (output / 'engine.log').read_text(encoding='utf-8', errors='replace').splitlines()
    errors = [line for line in lines if re.match(r'^(?:ERROR:|SCRIPT ERROR:|FAIL |WARNING:.*leak|CrashHandler)', line)]
    stable = hashes() == initial
    passed = code == 0 and not errors and not stopped and stable and (output / ('runtime.json' if args.runtime else 'frames.json')).exists()
    (output / 'summary.json').write_text(json.dumps({'passed': passed, 'exit_code': code, 'errors': errors,
        'stopped': stopped, 'sources': initial, 'sources_unchanged': stable}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'passed={passed} exit={code} errors={len(errors)} stopped={stopped}')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
