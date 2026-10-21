"""Windows 桌面版打包：项目本地获取官方 4.7.1 Windows 发布模板，导出并打成可直接发给朋友的 zip。

用法：
  python build-tools/prepare_windows.py --templates-only [--download-seconds N]   # 只准备/校验模板
  python build-tools/prepare_windows.py [--engine 引擎路径]                        # 导出到 builds/windows/ 并打包 zip

模板只从 Godot 官方 GitHub 发布包里按 HTTP Range 读取 windows_release_x86_64.exe 一个条目，
存到被 Git 忽略的 build-tools/cache/，来源记录在 windows-template-source.json，不做全局安装。
导出全部资源在同一个 .pck 里（只含桌面 s3tc 贴图），不需要按章节下载。
联机默认连接 net_client.gd 的 DEFAULT_SERVER（主机电脑经 SakuraFrp 隧道发布的 wss 地址）。
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from official_range import extract, DownloadCheckpoint

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "build-tools/cache"
TEMPLATE = CACHE / "windows_release_x86_64.exe"
MANIFEST = CACHE / "windows-template-source.json"
OUTPUT = ROOT / "builds/windows/ConjoinedTwins"
ARCHIVE = ROOT / "builds/windows/ConjoinedTwins-Windows.zip"
DEFAULT_ENGINE = "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe"
API = "https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.7.1-stable"
ASSET = "Godot_v4.7.1-stable_export_templates.tpz"
README = """共生连线 · Windows 版

1. 把整个文件夹解压到任意位置（不要只拖出 exe，ConjoinedTwins.pck 必须和它放在一起）。
2. 双击 ConjoinedTwins.exe。Windows 若提示“已保护你的电脑”，点“更多信息” → “仍要运行”（程序没有数字签名）。
3. 在主界面选好章节 → 开始页选“远程双人” → 点“连接队友”。服务器地址已经填好，不用改。
   联机章节以 01 号（先连上的人）选的为准，两人都载入完成后点“出发”。
4. 操作：WASD 移动，空格跳跃，鼠标左键射击，R 换弹，Q 换枪，G 丢枪，Esc 暂停；也支持手柄。

需要主机那台电脑保持开机，并运行着联机服务（deploy\\windows\\启动网页服务器.cmd）和 SakuraFrp。
"""


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def templates(download_seconds=None):
    CACHE.mkdir(parents=True, exist_ok=True)
    if MANIFEST.exists() and TEMPLATE.exists():
        evidence = json.loads(MANIFEST.read_text(encoding="utf-8"))
        if evidence["version"] != "4.7.1-stable" or evidence["windows_template_sha256"] != sha(TEMPLATE):
            raise RuntimeError("Cached Windows template identity mismatch; files retained")
        print("Verified project-local Windows template cache", flush=True)
        return True
    request = urllib.request.Request(API, headers={"User-Agent": "ConjoinedTwins-packager"})
    with urllib.request.urlopen(request, timeout=60) as response:
        release = json.load(response)
    asset = next(a for a in release["assets"] if a["name"] == ASSET)
    try:
        evidence = extract(asset, CACHE, download_seconds, ("/version.txt", "/windows_release_x86_64.exe"))
    except DownloadCheckpoint as checkpoint:
        print(str(checkpoint), flush=True)
        return False
    evidence.update({"version": "4.7.1-stable", "release": release["html_url"],
                     "url": asset["browser_download_url"], "asset_size": asset["size"],
                     "official_archive_sha256": asset.get("digest", "").removeprefix("sha256:"),
                     "installed_globally": False, "windows_template_sha256": sha(TEMPLATE),
                     "checksum_boundary": "全归档官方 SHA-256 校验未执行；仅检查选取条目 CRC 和本地 SHA-256"})
    MANIFEST.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Official Windows template extracted and CRC verified", flush=True)
    return True


def run(command, log, timeout):
    with log.open("w", encoding="utf-8") as output:
        return subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=timeout).returncode


def export(engine):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    evidence = ROOT / f"builds/windows-evidence-{stamp}"
    evidence.mkdir(parents=True)
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True)
    if run([engine, "--headless", "--path", str(ROOT), "--import"], evidence / "import.log", 900) != 0:
        raise RuntimeError("Headless import failed; see import.log")
    code = run([engine, "--headless", "--path", str(ROOT), "--export-release", "Windows Desktop",
                str(OUTPUT / "ConjoinedTwins.exe")], evidence / "export.log", 1800)
    exe, pck = OUTPUT / "ConjoinedTwins.exe", OUTPUT / "ConjoinedTwins.pck"
    if code != 0 or not exe.exists() or not pck.exists():
        print(f"export exit={code}, files={sorted(p.name for p in OUTPUT.iterdir())}, evidence={evidence}", flush=True)
        return False
    (OUTPUT / "使用说明.txt").write_text(README.replace("\n", "\r\n"), encoding="utf-8-sig")
    ARCHIVE.unlink(missing_ok=True)
    with zipfile.ZipFile(ARCHIVE, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(OUTPUT.iterdir()):
            archive.write(path, f"ConjoinedTwins/{path.name}")
    print(f"exe {exe.stat().st_size} bytes, pck {pck.stat().st_size} bytes", flush=True)
    print(f"zip {ARCHIVE} {ARCHIVE.stat().st_size} bytes sha256 {sha(ARCHIVE)}", flush=True)
    print(f"export exit={code}, evidence={evidence}", flush=True)
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--templates-only", action="store_true")
    parser.add_argument("--download-seconds", type=float)
    parser.add_argument("--engine", default=DEFAULT_ENGINE)
    args = parser.parse_args()
    if not templates(args.download_seconds):
        return 2
    if args.templates_only:
        return 0
    return 0 if export(args.engine) else 1


if __name__ == "__main__":
    sys.exit(main())
