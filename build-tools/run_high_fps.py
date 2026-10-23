"""Windows 高帧率启动：仅为本次游戏子进程选择 Vulkan、性能核心和帧率上限。"""
import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path('D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64.exe')

def configure_process(process, pcores=True, no_ecoqos=True):
    if os.name != 'nt':
        return {'applied':False,'reason':'Windows only'}
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    handle = wintypes.HANDLE(int(process._handle))
    result = {'applied':False,'chosen':[],'execution_throttling_disabled':False}
    if pcores:
        kernel.GetSystemCpuSetInformation.argtypes = [ctypes.c_void_p,wintypes.ULONG,ctypes.POINTER(wintypes.ULONG),wintypes.HANDLE,wintypes.ULONG]
        needed = wintypes.ULONG()
        kernel.GetSystemCpuSetInformation(None,0,ctypes.byref(needed),handle,0)
        if needed.value:
            data = ctypes.create_string_buffer(needed.value)
            if kernel.GetSystemCpuSetInformation(data,needed.value,ctypes.byref(needed),handle,0):
                cores=[];offset=0
                while offset<needed.value:
                    size=int.from_bytes(data.raw[offset:offset+4],'little')
                    if size<24:break
                    kind=int.from_bytes(data.raw[offset+4:offset+8],'little')
                    group=int.from_bytes(data.raw[offset+12:offset+14],'little')
                    if kind==0 and group==0:
                        cores.append({'logical':data.raw[offset+14],'efficiency':data.raw[offset+18]})
                    offset+=size
                if cores:
                    highest=max(c['efficiency'] for c in cores)
                    chosen=[c['logical'] for c in cores if c['efficiency']==highest]
                    mask=sum(1<<i for i in chosen)
                    kernel.SetProcessAffinityMask.argtypes = [wintypes.HANDLE,ctypes.c_size_t]
                    if kernel.SetProcessAffinityMask(handle,mask):
                        result.update(applied=True,chosen=chosen,cores=cores)
    if no_ecoqos:
        # EXECUTION_SPEED 的进程级显式关闭；不修改系统电源计划或其他进程。
        state=(wintypes.DWORD*3)(1,1,0)
        kernel.SetProcessInformation.argtypes = [wintypes.HANDLE,ctypes.c_int,ctypes.c_void_p,wintypes.DWORD]
        result['execution_throttling_disabled']=bool(kernel.SetProcessInformation(handle,4,ctypes.byref(state),ctypes.sizeof(state)))
    return result

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--engine',type=Path,default=ENGINE)
    parser.add_argument('--max-fps',type=int,default=144)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    if not args.engine.is_file():raise FileNotFoundError(args.engine)
    if args.max_fps<30 or args.max_fps>360:raise ValueError('帧率上限范围为 30–360')
    command=[str(args.engine),'--path',str(ROOT),'--rendering-method','mobile','--rendering-driver','vulkan','--disable-vsync','--max-fps',str(args.max_fps)]
    if args.check:command+=['--headless','--version']
    output=ROOT/'build-tools/cache/high-fps';output.mkdir(parents=True,exist_ok=True)
    with (output/'last-launch.log').open('w',encoding='utf-8') as log:
        child=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        settings=configure_process(child)
        receipt={'command':command,'process':settings,'scope':'仅本次游戏子进程，退出即结束；没有系统、驱动或注册表修改'}
        (output/'last-launch.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
        code=child.wait()
    print('高帧率游戏进程退出：',code)
    raise SystemExit(code)

if __name__=='__main__':main()
