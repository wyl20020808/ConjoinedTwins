"""在任务独占隐藏父窗口中进行有界渲染诊断，不操作桌面、输入或系统设置。"""
import argparse
import ctypes
import json
from ctypes import wintypes
import os
from pathlib import Path
import subprocess
import time
from run_high_fps import configure_process

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path('D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--label', required=True)
    parser.add_argument('--driver', default='opengl3_angle')
    parser.add_argument('--method', default='gl_compatibility')
    parser.add_argument('--phases', default='')
    parser.add_argument('--no-render', action='store_true')
    parser.add_argument('--separate', action='store_true')
    parser.add_argument('--pcores', action='store_true')
    parser.add_argument('--no-ecoqos', action='store_true')
    parser.add_argument('--script', default='res://tests/dense_frame_diagnosis.gd')
    parser.add_argument('--max-fps', type=int, default=0)
    args = parser.parse_args()
    out = Path('D:/ConjoinedTwins-task-temp/dense-performance-evidence/deep-20261018')
    out.mkdir(parents=True, exist_ok=True)
    user32 = ctypes.WinDLL('user32', use_last_error=True)
    user32.CreateWindowExW.restype = wintypes.HWND
    user32.CreateWindowExW.argtypes = [wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD,
        ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wintypes.HWND, wintypes.HMENU, wintypes.HINSTANCE, wintypes.LPVOID]
    parent = user32.CreateWindowExW(0x08000000, 'STATIC', 'ConjoinedTwins-frame-diagnosis', 0x80000000,
        0, 0, 1280, 720, None, None, None, None)
    if not parent:
        raise ctypes.WinError(ctypes.get_last_error())
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    env = os.environ.copy()
    env['DENSE_FRAME_REPORT'] = str(out / (args.label + '.json'))
    env['DENSE_FRAME_PHASES'] = args.phases
    command = [str(ENGINE), '--path', str(ROOT), '--wid', str(parent), '--single-window',
        '--resolution', '1280x720', '--audio-driver', 'Dummy', '--accessibility', 'disabled',
        '--disable-vsync', '--rendering-method', args.method, '--rendering-driver', args.driver,
        '--max-fps',str(args.max_fps),'--script', args.script]
    if args.no_render:
        command.append('--disable-render-loop')
    if args.separate:
        command += ['--render-thread', 'separate']
    try:
        with (out / (args.label + '.log')).open('w', encoding='utf-8') as log:
            log.write(str(command) + '\n'); log.flush()
            child = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW)
            settings=configure_process(child,args.pcores,args.no_ecoqos)
            (out/(args.label+'-process.json')).write_text(json.dumps(settings,indent=2),encoding='utf-8')
            start = time.monotonic()
            try:
                while child.poll() is None:
                    if user32.IsWindowVisible(parent):
                        raise RuntimeError('Hidden diagnostic parent became visible')
                    if time.monotonic() - start > 90:
                        raise TimeoutError('Diagnostic exceeded 90 seconds')
                    message = wintypes.MSG()
                    while user32.PeekMessageW(ctypes.byref(message), None, 0, 0, 1):
                        user32.TranslateMessage(ctypes.byref(message))
                        user32.DispatchMessageW(ctypes.byref(message))
                    time.sleep(.004)
            finally:
                if child.poll() is None:
                    child.kill()
                child.wait()
            print(args.label, 'exit', child.returncode)
            if child.returncode:
                raise RuntimeError('Diagnostic failed; inspect retained log')
    finally:
        user32.DestroyWindow.argtypes = [wintypes.HWND]
        user32.DestroyWindow(parent)

if __name__ == '__main__':
    main()
