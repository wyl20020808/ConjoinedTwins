"""离屏原生渲染救援回归；保存退出码和日志，不发送桌面输入。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def interaction_mode():
    try:
        return json.loads(Path('D:/PersonalAgent-data/global-interaction-policy.json').read_text(encoding='utf-8-sig')).get('mode', 'work')
    except (OSError, ValueError):
        return 'work'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64.exe')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--cycles', type=int, default=16, choices=range(1, 129))
    parser.add_argument('--driver', choices=['opengl3', 'opengl3_angle', 'vulkan'])
    parser.add_argument('--method', choices=['gl_compatibility', 'mobile', 'forward_plus'])
    parser.add_argument('--verbose', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if interaction_mode() != 'idle':
        (output / 'summary.json').write_text(json.dumps({'status': 'deferred_by_work_mode', 'passed': False}), encoding='utf-8')
        print('deferred_by_work_mode: native renderer; ordinary headless tests remain available')
        return 2
    sources = list((ROOT / 'scripts').glob('*.gd')) + list((ROOT / 'scripts').glob('*.gdshader'))
    sources += [ROOT / 'project.godot', ROOT / 'tests/journey_rescue_transition.gd', Path(__file__)]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    command = [args.godot, '--path', str(ROOT), '--script', 'res://tests/journey_rescue_transition.gd',
               '--position', '-10000,-10000', '--resolution', '1280x720', '--log-file', str(output / 'godot.log'),
               '--', '--chapter=0', f'--cycles={args.cycles}']
    if args.driver:
        command[1:1] = ['--rendering-driver', args.driver]
        if args.driver == 'vulkan' and not args.method:
            command[1:1] = ['--rendering-method', 'mobile']
    if args.method:
        command[1:1] = ['--rendering-method', args.method]
    if args.verbose:
        command.insert(1, '--verbose')
    env = os.environ.copy()
    env['RESCUE_REPORT_DIR'] = str(output)
    startup = None
    if os.name == 'nt':
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
    timed_out = False
    deferred = False
    with (output / 'process.log').open('w', encoding='utf-8') as log:
        with subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, startupinfo=startup) as process:
            deadline = time.monotonic() + max(180, args.cycles * 7)
            while process.poll() is None:
                deferred = interaction_mode() != 'idle'
                timed_out = time.monotonic() > deadline
                if deferred or timed_out:
                    # 只取消当前检查自己创建的进程，不影响用户游戏或其他 Run。
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                    break
                time.sleep(1)
            code = process.wait()
    text = (output / 'process.log').read_text(encoding='utf-8', errors='replace')
    errors = [line for line in text.splitlines() if re.match(r'^(?:SCRIPT ERROR:|ERROR:|FAIL |WARNING:.*leak|CrashHandler)', line)]
    marker = f'JOURNEY_RESCUE_TRANSITION failures=0 cycles={args.cycles}'
    renderer = next((line for line in text.splitlines() if 'Using Device' in line), '')
    unchanged = all(p.exists() and hashlib.sha256(p.read_bytes()).hexdigest() == hashes[str(p.relative_to(ROOT))] for p in sources)
    passed = code == 0 and not errors and not timed_out and not deferred and marker in text and bool(renderer) and unchanged
    report = {'passed': passed, 'project': str(ROOT), 'command': command, 'exit_code': code, 'timeout': timed_out,
              'renderer': renderer, 'errors': errors, 'sources': hashes, 'sources_unchanged': unchanged,
              'scope': 'offscreen native renderer and production update path; no physical input or visible player acceptance'}
    if deferred:
        report['status'] = 'deferred_by_work_mode'
    (output / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(('PASS' if passed else 'FAIL') + ': ' + str(output / 'summary.json'))
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
