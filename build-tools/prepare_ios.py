"""iOS 导出准备：项目本地获取官方 4.7.1 iOS 模板，并在需要时导出 Xcode 工程。

用法：
  python build-tools/prepare_ios.py --templates-only [--download-seconds N]   # 只准备/校验模板
  python build-tools/prepare_ios.py                                           # 校验模板后导出 Xcode 工程
导出产物是 Xcode 工程，需要拷到 Mac 用 Xcode 签名安装；详见 docs/IOS_ONLINE.md。
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
TEMPLATE = CACHE / "ios.zip"
MANIFEST = CACHE / "ios-template-source.json"
OUTPUT = ROOT / "builds/ios"
ENGINE = "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe"
API = "https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.7.1-stable"
ASSET = "Godot_v4.7.1-stable_export_templates.tpz"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def templates(download_seconds=None):
    CACHE.mkdir(parents=True, exist_ok=True)
    if MANIFEST.exists() and TEMPLATE.exists():
        evidence = json.loads(MANIFEST.read_text(encoding="utf-8"))
        if evidence["version"] != "4.7.1-stable" or evidence["ios_template_sha256"] != sha(TEMPLATE):
            raise RuntimeError("Cached iOS template identity mismatch; files retained")
        with zipfile.ZipFile(TEMPLATE) as zipped:
            if zipped.testzip() is not None:
                raise RuntimeError("Cached iOS template ZIP corrupted")
        print("Verified project-local iOS template cache", flush=True)
        return True
    request = urllib.request.Request(API, headers={"User-Agent": "ConjoinedTwins-packager"})
    with urllib.request.urlopen(request, timeout=60) as response:
        release = json.load(response)
    asset = next(a for a in release["assets"] if a["name"] == ASSET)
    try:
        evidence = extract(asset, CACHE, download_seconds, ("/version.txt", "/ios.zip"))
    except DownloadCheckpoint as checkpoint:
        print(str(checkpoint), flush=True)
        return False
    evidence.update({"version": "4.7.1-stable", "release": release["html_url"],
                     "url": asset["browser_download_url"], "asset_size": asset["size"],
                     "official_archive_sha256": asset.get("digest", "").removeprefix("sha256:"),
                     "installed_globally": False, "ios_template_sha256": sha(TEMPLATE),
                     "checksum_boundary": "全归档官方 SHA-256 校验未执行；仅检查选取条目 CRC、ios.zip 内部 CRC 和本地 SHA-256"})
    MANIFEST.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Official iOS template extracted and CRC verified", flush=True)
    return True


def run(command, log, timeout):
    with log.open("w", encoding="utf-8") as output:
        process = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    return process.returncode


def export():
    stamp = datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%SZ")
    evidence = ROOT / f"builds/ios-evidence-{stamp}"
    evidence.mkdir(parents=True)
    if OUTPUT.exists():
        history = ROOT / f"builds/ios-history/{stamp}"
        history.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(OUTPUT), str(history))
        print(f"Previous Xcode project moved to {history}", flush=True)
    OUTPUT.mkdir(parents=True)
    if run([ENGINE, "--headless", "--path", str(ROOT), "--import"], evidence / "import.log", 900) != 0:
        raise RuntimeError("Headless import failed; see import.log")
    code = run([ENGINE, "--headless", "--path", str(ROOT), "--export-release", "iOS",
                str(OUTPUT / "ConjoinedTwins.ipa")], evidence / "export.log", 1800)
    projects = list(OUTPUT.glob("*.xcodeproj"))
    print(f"export exit={code}, xcodeproj={[p.name for p in projects]}, evidence={evidence}", flush=True)
    return code == 0 and bool(projects)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--templates-only", action="store_true")
    parser.add_argument("--download-seconds", type=float)
    args = parser.parse_args()
    if not templates(args.download_seconds):
        return 2
    if args.templates_only:
        return 0
    return 0 if export() else 1


if __name__ == "__main__":
    sys.exit(main())
