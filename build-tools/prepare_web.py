"""网页版导出准备：项目本地获取官方 4.7.1 Web（无线程）模板，并在需要时导出网页版。

用法：
  python build-tools/prepare_web.py --templates-only [--download-seconds N]   # 只准备/校验模板
  python build-tools/prepare_web.py [--engine 引擎路径]                        # 校验模板后导出到 builds/web/
无线程模板不依赖 COOP/COEP 响应头；产物是静态文件，部署见 docs/WEB_ONLINE.md。
"""
import argparse
import datetime
import hashlib
import gzip
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
TEMPLATE = CACHE / "web_nothreads_release.zip"
MANIFEST = CACHE / "web-template-source.json"
OUTPUT = ROOT / "builds/web"
DEFAULT_ENGINE = "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe"
API = "https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.7.1-stable"
ASSET = "Godot_v4.7.1-stable_export_templates.tpz"


def sha(path):
    # 不用 hashlib.file_digest：Mac 自带的 Python 3.9 也要能运行本脚本。
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def templates(download_seconds=None):
    CACHE.mkdir(parents=True, exist_ok=True)
    if MANIFEST.exists() and TEMPLATE.exists():
        evidence = json.loads(MANIFEST.read_text(encoding="utf-8"))
        if evidence["version"] != "4.7.1-stable" or evidence["web_template_sha256"] != sha(TEMPLATE):
            raise RuntimeError("Cached Web template identity mismatch; files retained")
        with zipfile.ZipFile(TEMPLATE) as zipped:
            if zipped.testzip() is not None:
                raise RuntimeError("Cached Web template ZIP corrupted")
        print("Verified project-local Web template cache", flush=True)
        return True
    request = urllib.request.Request(API, headers={"User-Agent": "ConjoinedTwins-packager"})
    with urllib.request.urlopen(request, timeout=60) as response:
        release = json.load(response)
    asset = next(a for a in release["assets"] if a["name"] == ASSET)
    try:
        evidence = extract(asset, CACHE, download_seconds, ("/version.txt", "/web_nothreads_release.zip"))
    except DownloadCheckpoint as checkpoint:
        print(str(checkpoint), flush=True)
        return False
    evidence.update({"version": "4.7.1-stable", "release": release["html_url"],
                     "url": asset["browser_download_url"], "asset_size": asset["size"],
                     "official_archive_sha256": asset.get("digest", "").removeprefix("sha256:"),
                     "installed_globally": False, "web_template_sha256": sha(TEMPLATE),
                     "checksum_boundary": "全归档官方 SHA-256 校验未执行；仅检查选取条目 CRC、web_nothreads_release.zip 内部 CRC 和本地 SHA-256"})
    MANIFEST.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Official Web template extracted and CRC verified", flush=True)
    return True


def run(command, log, timeout):
    with log.open("w", encoding="utf-8") as output:
        process = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    return process.returncode


def export(engine):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    evidence = ROOT / f"builds/web-evidence-{stamp}"
    evidence.mkdir(parents=True)
    if OUTPUT.exists():
        history = ROOT / f"builds/web-history/{stamp}"
        history.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(OUTPUT), str(history))
        print(f"Previous web build moved to {history}", flush=True)
    OUTPUT.mkdir(parents=True)
    if run([engine, "--headless", "--path", str(ROOT), "--import"], evidence / "import.log", 900) != 0:
        raise RuntimeError("Headless import failed; see import.log")
    code = run([engine, "--headless", "--path", str(ROOT), "--export-release", "Web",
                str(OUTPUT / "index.html")], evidence / "export.log", 1800)
    files = sorted(p.name for p in OUTPUT.iterdir())
    required = {"index.html", "index.js", "index.wasm", "index.pck"}
    if code == 0 and required.issubset(files):
        # 预压缩可避免每次首访都在服务器上重新压缩引擎；PCK 默认也不会动态压缩。
        for name in ("index.js", "index.wasm", "index.pck"):
            path = OUTPUT / name
            compressed = gzip.compress(path.read_bytes(), compresslevel=6, mtime=0)
            path.with_name(name + ".gz").write_bytes(compressed)
            print(f"Precompressed {name}: {path.stat().st_size} -> {len(compressed)} bytes", flush=True)
    print(f"export exit={code}, files={files}, evidence={evidence}", flush=True)
    return code == 0 and required.issubset(files)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--templates-only", action="store_true")
    parser.add_argument("--download-seconds", type=float)
    parser.add_argument("--engine", default=DEFAULT_ENGINE, help="Godot 4.7.1 可执行文件；Mac 上为 /Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    if not templates(args.download_seconds):
        return 2
    if args.templates_only:
        return 0
    return 0 if export(args.engine) else 1


if __name__ == "__main__":
    sys.exit(main())
