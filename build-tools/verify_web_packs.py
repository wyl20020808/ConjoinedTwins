"""拆包后的网页数据巡检：用生产网页服务 deploy/windows/serve_web.py 提供 builds/web，
逐章只挂载主包 + 该章数据包并整章流式加载。用生产服务而不是普通静态服务器，是为了覆盖
预压缩、Content-Encoding 等真实响应头（曾因 .pck 被 br 编码导致下载截断）。

用法：python build-tools/verify_web_packs.py [--web builds/web] [--engine 引擎路径]
任一章出现资源缺失、读取失败或下载失败即返回非零；日志写到 <web>/../web-packs-verify/。
通过只说明拆包没有漏掉桌面无头运行会读取的资源；浏览器内下载、缓存与渲染仍需真机试玩。
"""
import argparse
from pathlib import Path
import re
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENGINE = "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe"
# 资源缺失时 Godot 打印的错误；只统计这些，不把引擎退出时的泄漏提示当成失败。
MISSING = re.compile(r"(Resource file not found|Failed loading resource|Cannot open file|No loader found|VERIFY_WEB_PACKS (missing|asset error|stuck))")


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--web", type=Path, default=ROOT / "builds/web")
    parser.add_argument("--engine", default=DEFAULT_ENGINE)
    args = parser.parse_args()
    web = args.web.resolve()
    logs = web.parent / "web-packs-verify"
    logs.mkdir(exist_ok=True)
    port = free_port()
    server = subprocess.Popen([sys.executable, str(ROOT / "deploy/windows/serve_web.py"), "--root", str(web), "--port", str(port)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try:
            socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
            break
        except OSError:
            time.sleep(0.1)
    url = f"http://127.0.0.1:{port}/"
    failed = 0
    try:
        for chapter in range(4):
            log = logs / f"chapter_{chapter}.log"
            command = [args.engine, "--headless", "--main-pack", str(web / "index.pck"), "-s",
                       str(ROOT / "build-tools/verify_web_packs.gd"), "--", f"--packs-url={url}", f"--chapter={chapter}"]
            with log.open("w", encoding="utf-8") as output:
                code = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=1800).returncode
            text = log.read_text(encoding="utf-8", errors="ignore")
            problems = [line for line in text.splitlines() if MISSING.search(line)]
            summary = next((line for line in text.splitlines() if "VERIFY_WEB_PACKS done" in line), "no summary")
            print(f"chapter {chapter}: exit {code}, problems {len(problems)} | {summary}")
            for line in problems[:10]:
                print("   ", line)
            if code != 0 or problems:
                failed += 1
    finally:
        server.terminate()
        server.wait()
    print(f"VERIFY_WEB_PACKS chapters_failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
