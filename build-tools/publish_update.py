"""发布桌面版云更新：导出 Windows 版 → 拆成主包与章节数据包 → 写入更新目录并生成 manifest.json。

用法：
  python build-tools/publish_update.py                  # 导出并发布（默认写到 D:/ConjoinedTwins-web/update）
  python build-tools/publish_update.py --skip-export    # 直接发布 builds/windows 里已导出的版本
  python build-tools/publish_update.py --servers-only   # 只改清单里的联机地址与备用更新链接，不重新打包

更新目录由 deploy/windows/serve_web.py 以 /update/ 提供（经现有隧道），玩家的游戏启动时读取
<更新链接>/manifest.json。文件名带内容哈希：未变化的数据包玩家不会重复下载。
联机地址与备用更新链接来自 update-config.json（主机本地配置，不入库，首次运行按内置默认生成）：
换隧道或节点后改这个文件，再运行 --servers-only，玩家下次检查更新就会换用新地址。
发布后需用新主包重启联机中继（start_server.ps1 会自动使用更新目录里的主包）。
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

import prepare_windows

ROOT = Path(__file__).resolve().parents[1]
STATE = Path("D:/ConjoinedTwins-web")
SPLIT = ROOT / "builds/update-split"
FORMAT = 1


def sha(path):
    return prepare_windows.sha(path)


def builtin_servers():
    text = (ROOT / "scripts/net_client.gd").read_text(encoding="utf-8")
    ws = re.search(r'const DEFAULT_SERVER := "([^"]*)"', text).group(1)
    udp = re.search(r'const DEFAULT_UDP_SERVER := "([^"]*)"', text).group(1)
    return {"udp": udp, "ws": ws}


def load_config(path):
    if not path.exists():
        config = {"servers": builtin_servers(), "update_urls": []}
        path.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"已生成联机与更新链接配置：{path}（换隧道后改这里，再运行 --servers-only）")
    config = json.loads(path.read_text(encoding="utf-8-sig"))
    return {"servers": dict(config.get("servers", {})), "update_urls": list(config.get("update_urls", []))}


def write_manifest(out, manifest):
    temp = out / "manifest.json.tmp"
    temp.write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    temp.replace(out / "manifest.json")


def engine_hash(engine):
    version = subprocess.run([engine, "--version"], capture_output=True, text=True, timeout=60).stdout.strip().splitlines()[-1]
    return version.rsplit(".", 1)[-1]


def publish(args, config):
    pck = prepare_windows.OUTPUT / "ConjoinedTwins.pck"
    release = prepare_windows.RELEASE.read_text(encoding="utf-8").strip() if prepare_windows.RELEASE.exists() else ""
    if not pck.exists() or not release:
        raise SystemExit("没有已导出的 Windows 版或版本号，先去掉 --skip-export 重新导出")
    if SPLIT.exists():
        shutil.rmtree(SPLIT)
    SPLIT.mkdir(parents=True)
    shutil.copy2(pck, SPLIT / "index.pck")
    subprocess.run([sys.executable, str(ROOT / "build-tools/split_web_pack.py"), str(SPLIT)], check=True)
    split = json.loads((SPLIT / "packs.json").read_text(encoding="utf-8"))
    files = args.out / "files"
    files.mkdir(parents=True, exist_ok=True)
    core_hash = sha(SPLIT / "index.pck")
    core_name = f"core.{core_hash[:12]}.pck"
    shutil.copy2(SPLIT / "index.pck", files / core_name)
    manifest = {"format": FORMAT, "release": release, "engine": engine_hash(args.engine),
                "published": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
                "core": {"file": f"files/{core_name}", "size": (files / core_name).stat().st_size, "sha256": core_hash},
                "packs": {}, **config}
    for name, info in split["packs"].items():
        source = SPLIT / info["file"]
        target = files / source.name
        if not target.exists():
            shutil.copy2(source, target)
        manifest["packs"][name] = {"file": f"files/{source.name}", "size": info["size"],
                                   "sha256": sha(target), "feature": info["feature"]}
    if not args.no_installer and prepare_windows.ARCHIVE.exists():
        installer = args.out / "installer"
        installer.mkdir(exist_ok=True)
        shutil.copy2(prepare_windows.ARCHIVE, installer / prepare_windows.ARCHIVE.name)
        manifest["installer"] = {"file": f"installer/{prepare_windows.ARCHIVE.name}",
                                 "size": prepare_windows.ARCHIVE.stat().st_size}
    previous = args.out / "manifest.json"
    keep = {Path(manifest["core"]["file"]).name} | {Path(p["file"]).name for p in manifest["packs"].values()}
    # 保留上一版的文件：正在下载上一版的玩家不会因为文件被删而失败。
    if previous.exists():
        old = json.loads(previous.read_text(encoding="utf-8"))
        keep |= {Path(old["core"]["file"]).name} | {Path(p["file"]).name for p in old.get("packs", {}).values()}
    write_manifest(args.out, manifest)
    for path in files.iterdir():
        if path.name not in keep:
            path.unlink()
    shutil.rmtree(SPLIT)
    total = manifest["core"]["size"] + sum(p["size"] for p in manifest["packs"].values())
    print(f"已发布 {release} → {args.out}")
    print(f"  主包 {manifest['core']['size'] / 1e6:.1f} MB，数据包 {len(manifest['packs'])} 个，合计 {total / 1e6:.1f} MB")
    print(f"  联机地址 {manifest['servers']}，备用更新链接 {manifest['update_urls']}")
    print("  记得用新主包重启联机中继：deploy\\windows\\启动网页服务器.cmd")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, default=STATE / "update")
    parser.add_argument("--config", type=Path, default=STATE / "update-config.json")
    parser.add_argument("--engine", default=prepare_windows.DEFAULT_ENGINE)
    parser.add_argument("--skip-export", action="store_true")
    parser.add_argument("--servers-only", action="store_true")
    parser.add_argument("--no-installer", action="store_true", help="不附带完整安装包（引擎升级时玩家需要它）")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    config = load_config(args.config)
    if args.servers_only:
        path = args.out / "manifest.json"
        if not path.exists():
            raise SystemExit("还没有发布过版本，先完整发布一次")
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest.update(config)
        write_manifest(args.out, manifest)
        print(f"已更新联机地址 {config['servers']}，备用更新链接 {config['update_urls']}")
        return 0
    if not args.skip_export:
        if not prepare_windows.templates() or not prepare_windows.export(args.engine):
            return 1
    publish(args, config)
    return 0


if __name__ == "__main__":
    sys.exit(main())
