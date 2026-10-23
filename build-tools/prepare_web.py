"""网页版导出准备：项目本地获取官方 4.7.1 Web（无线程）模板，并在需要时导出网页版。

用法：
  python build-tools/prepare_web.py --templates-only [--download-seconds N]   # 只准备/校验模板
  python build-tools/prepare_web.py [--engine 引擎路径]                        # 校验模板后导出到 builds/web/
无线程模板不依赖 COOP/COEP 响应头；产物是静态文件，部署见 docs/WEB_ONLINE.md。
导出后按章节拆包（split_web_pack.py），生成 packs.json、Service Worker（web/sw.js）与启动背景图，
再对引擎、主包和全部章节包预压缩。章节拆包与缓存说明见 docs/CHAPTER_MENU_ONLINE.md。
"""
import argparse
import datetime
import hashlib
import gzip
import json
from pathlib import Path
import re
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
    from network_manifest import generate
    generate()
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
        if run([sys.executable, str(ROOT / "build-tools/split_web_pack.py"), str(OUTPUT)], evidence / "split.log", 600) != 0:
            raise RuntimeError("Chapter pack split failed; see split.log")
        compress_packs(OUTPUT)
        finalize_shell(OUTPUT)
        # 预压缩可避免每次首访都在服务器上重新压缩引擎；PCK 默认也不会动态压缩。
        # 章节包不在这里：它们由 compress_packs 另存为 .pckz，不能有 .br/.gz 同名文件（见该函数说明）。
        targets = ["index.js", "index.wasm", "index.pck"]
        for name in targets:
            path = OUTPUT / name
            compressed = gzip.compress(path.read_bytes(), compresslevel=6, mtime=0)
            (path.parent / (path.name + ".gz")).write_bytes(compressed)
            print(f"Precompressed {name}: {path.stat().st_size} -> {len(compressed)} bytes", flush=True)
            # brotli 比 gzip 再小约 20%，所有主流浏览器（含 iOS Safari）均支持；本机没有 brotli 命令时跳过。
            brotli = shutil.which("brotli")
            if brotli:
                target = path.parent / (path.name + ".br")
                subprocess.run([brotli, "-q", "11", "-w", "22", "-f", "-o", str(target), str(path)], check=True)
                print(f"Precompressed {name}: {path.stat().st_size} -> {target.stat().st_size} bytes (brotli)", flush=True)
        fill_boot_size(OUTPUT)
    print(f"export exit={code}, files={files}, evidence={evidence}", flush=True)
    return code == 0 and required.issubset(files)


def short_hash(path):
    return sha(path)[:12]


def compress_packs(output):
    """章节包另存 brotli 压缩版 .pckz，并写入 packs.json 的 transfer 字段，由游戏下载后自行解压。

    不能用 .pck.br 让服务器发 Content-Encoding：浏览器交给引擎的是解压后的数据，Godot 的 HTTPRequest
    却按响应头里压缩后的 Content-Length 停止读取，文件被截断（实测“下载失败，状态 200，结果 0”）。
    .pckz 没有同名预压缩文件，服务器按普通二进制原样发送；原 .pck 也保留不压缩，作解压失败时的后备。
    """
    brotli = shutil.which("brotli")
    manifest_path = output / "packs.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for name, info in manifest["packs"].items():
        source = output / info["file"]
        for stale in (source.with_name(source.name + ".br"), source.with_name(source.name + ".gz")):
            stale.unlink(missing_ok=True)
        if not brotli:
            continue
        target = source.with_suffix(".pckz")
        subprocess.run([brotli, "-q", "11", "-w", "22", "-f", "-o", str(target), str(source)], check=True)
        # 压缩不划算（贴图本身已压缩）时只发原包。
        if target.stat().st_size >= source.stat().st_size * 0.97:
            target.unlink()
            continue
        info["transfer"] = str(target.relative_to(output)).replace("\\", "/")
        info["transfer_size"] = target.stat().st_size
        info["transfer_hash"] = short_hash(target)
        print(f"Packed {info['file']}: {source.stat().st_size} -> {target.stat().st_size} bytes (.pckz)", flush=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    if not brotli:
        print("brotli 命令不存在：章节包只发未压缩原包", flush=True)


def finalize_shell(output):
    """拆包之后：修正启动页里主包的大小、写入启动背景图与 Service Worker 缓存清单。"""
    html = output / "index.html"
    text = html.read_text(encoding="utf-8")
    core = (output / "index.pck").stat().st_size
    # 引擎按 fileSizes 计算启动进度；主包已拆小，必须改成拆分后的大小。
    text = re.sub(r'"index\.pck":\s*\d+', f'"index.pck":{core}', text)
    html.write_text(text, encoding="utf-8")
    shutil.copyfile(ROOT / "assets/ui/covers/home.jpg", output / "loading_bg.jpg")
    files = json.loads((output / "sw-files.json").read_text(encoding="utf-8"))
    for name in ("index.js", "index.wasm", "index.pck", "index.audio.worklet.js", "index.audio.position.worklet.js", "loading_bg.jpg"):
        if (output / name).exists():
            files[name] = short_hash(output / name)
    manifest = json.loads((output / "packs.json").read_text(encoding="utf-8"))
    for info in manifest["packs"].values():
        if "transfer" in info:
            files[info["transfer"]] = info["transfer_hash"]
    build = manifest["build"]
    worker = (ROOT / "web/sw.js").read_text(encoding="utf-8")
    worker = worker.replace("'__BUILD__'", json.dumps(build)).replace("__FILES__", json.dumps(files, indent=1))
    (output / "sw.js").write_text(worker, encoding="utf-8")
    (output / "sw-files.json").unlink()
    print(f"Shell finalized: core {core} bytes, {len(files)} cached files, build {build}", flush=True)


def fill_boot_size(output):
    """启动页提示里的首次下载量：引擎与主包的实际压缩传输大小（优先 brotli，其次 gzip）。"""
    total = 0
    for name in ("index.wasm", "index.pck", "index.js"):
        path = output / name
        packed = [p for p in (path.parent / (name + ".br"), path.parent / (name + ".gz")) if p.exists()]
        total += packed[0].stat().st_size if packed else path.stat().st_size
    html = output / "index.html"
    html.write_text(html.read_text(encoding="utf-8").replace("__BOOT_MB__", str(max(1, round(total / 1048576)))), encoding="utf-8")


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
