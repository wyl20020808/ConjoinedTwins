"""Task-owned hidden parent from creation. No user windows, input or focus calls."""
import ctypes
from ctypes import wintypes
from pathlib import Path
import subprocess
import os
import time
import sys

ROOT = Path(__file__).resolve().parents[1]
ENGINE = 'D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe'

def main():
    user32 = ctypes.WinDLL('user32', use_last_error=True)
    user32.CreateWindowExW.restype = wintypes.HWND
    user32.CreateWindowExW.argtypes = [wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD,
        ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wintypes.HWND, wintypes.HMENU, wintypes.HINSTANCE, wintypes.LPVOID]
    # WS_POPUP with no WS_VISIBLE. Never ShowWindow, SetFocus, SetForegroundWindow.
    parent = user32.CreateWindowExW(0x08000000, 'STATIC', 'ConjoinedTwins-private-render-host', 0x80000000,
        0, 0, 1280, 720, None, None, None, None)
    if not parent:
        raise ctypes.WinError(ctypes.get_last_error())
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    command = [ENGINE, '--path', str(ROOT), '--wid', str(parent), '--single-window', '--resolution', '1280x720',
        '--audio-driver', 'Dummy', '--accessibility', 'disabled', '--script', sys.argv[1] if len(sys.argv) > 1 else 'res://tests/capture_road.gd', '--', '--capture-demo']
    try:
        log_name = Path(sys.argv[1]).stem.replace('capture_', '') + '-capture.log' if len(sys.argv) > 1 else 'capture.log'
        with (ROOT / 'tests' / log_name).open('w', encoding='utf-8') as log:
            log.write(str(command) + '\n'); log.flush()
            child = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            started = time.monotonic()
            try:
                while child.poll() is None:
                    if user32.IsWindowVisible(parent):
                        raise RuntimeError('Hidden host unexpectedly visible; capture aborted')
                    # 多机位取景（如章节封面）可用 CAPTURE_TIMEOUT 放宽；默认仍为 90 秒。
                    if time.monotonic() - started > float(os.environ.get('CAPTURE_TIMEOUT', '90')):
                        raise TimeoutError('Capture exceeded timeout')
                    message = wintypes.MSG()
                    while user32.PeekMessageW(ctypes.byref(message), None, 0, 0, 1):
                        user32.TranslateMessage(ctypes.byref(message))
                        user32.DispatchMessageW(ctypes.byref(message))
                    time.sleep(0.02)
            finally:
                if child.poll() is None:
                    child.kill()
                child.wait()
            print('Hidden render exit:', child.returncode)
            if child.returncode:
                raise RuntimeError('Capture failed; see tests/capture.log')
    finally:
        user32.DestroyWindow.argtypes = [wintypes.HWND]
        user32.DestroyWindow(parent)

if __name__ == '__main__': main()
