"""生成可发给朋友的 Windows 安装器；复用既有导出和云更新数据包，不发布或重启服务。

默认先导出当前工程。--skip-export --source DIR 可以封装已导出的完整资源目录。
Inno Setup 6.7+ 的 ISCC.exe 通过 --iscc 指定，也可放在 PATH 中。
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import prepare_windows

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "builds/windows/installer"
INSTALL_HELP = """共生连线

双击桌面或开始菜单中的“共生连线”即可开始游戏。
游戏启动时自动检查更新，已安装的资源会复用；更新服务器暂时离线时仍可进入已有版本。
远程双人游玩需要主机的联机服务保持在线。
卸载：Windows 设置 → 应用 → 共生连线，或开始菜单中的“卸载共生连线”。
卸载保留玩家设置和已下载的更新，以便以后重新安装。
"""


def validate(source):
    """封装前核对主包、清单和所有数据包，避免生成缺少资源的安装器。"""
    for name in ("ConjoinedTwins.exe", "ConjoinedTwins.pck", "packs.json"):
        path = source / name
        if not path.is_file() or not path.stat().st_size:
            raise ValueError(f"缺少或为空：{path}")
    with (source / "ConjoinedTwins.exe").open("rb") as stream:
        signature = stream.read(2)
    if signature != b"MZ":
        raise ValueError("Windows 主程序不是 PE 文件")
    plan = json.loads((source / "packs.json").read_text(encoding="utf-8"))
    release = plan.get("release", "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,100}", release):
        raise ValueError("资源清单版本号无效")
    if not plan.get("packs"):
        raise ValueError("资源清单没有数据包")
    files = [source / name for name in ("ConjoinedTwins.exe", "ConjoinedTwins.pck", "packs.json")]
    for info in plan["packs"].values():
        relative = Path(info["file"])
        path = (source / relative).resolve()
        if (not path.is_relative_to(source.resolve()) or relative.parent != Path("packs")
                or relative.suffix != ".pck"):
            raise ValueError(f"非法数据包路径：{relative}")
        if path.stat().st_size != info["size"] or prepare_windows.sha(path) != info["sha256"]:
            raise ValueError(f"数据包校验失败：{relative}")
        files.append(path)
    return release, files


def build(source, iscc):
    release, files = validate(source)
    release_output = OUTPUT / release
    release_output.mkdir(parents=True, exist_ok=True)
    target = release_output / "共生连线_Setup.exe"
    if target.exists():
        raise FileExistsError(f"安装器已存在，保留原件：{target}")
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    evidence = release_output / f"evidence-{stamp}"
    evidence.mkdir()
    # 只暂存清单列出的文件，不把历史数据包和调试文件带进安装器。
    with tempfile.TemporaryDirectory(prefix="ct-installer-") as temp:
        payload = Path(temp)
        for path in files:
            dest = payload / path.relative_to(source)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)
        (payload / "安装说明.txt").write_text(INSTALL_HELP, encoding="utf-8-sig")
        command = [str(iscc), "/Qp", f"/DPayloadDir={payload}", f"/DRelease={release}",
                   f"/DOutputDir={release_output}", str(ROOT / "build-tools/windows-installer.iss")]
        with (evidence / "compile.log").open("w", encoding="utf-8") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=600)
    if result.returncode != 0 or not target.is_file():
        raise RuntimeError(f"安装器编译失败：{evidence / 'compile.log'}")
    receipt = {"release": release, "source": str(source), "installer": str(target),
               "size": target.stat().st_size, "sha256": prepare_windows.sha(target),
               "files": {p.relative_to(source).as_posix(): prepare_windows.sha(p) for p in files},
               "compile_exit": result.returncode, "gui_test": "not_run", "signed": False}
    (evidence / "build.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"安装器：{target}\n大小：{receipt['size']} bytes\nSHA-256：{receipt['sha256']}\n证据：{evidence}")
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-export", action="store_true")
    parser.add_argument("--source", type=Path, default=prepare_windows.OUTPUT)
    parser.add_argument("--engine", default=prepare_windows.DEFAULT_ENGINE)
    parser.add_argument("--iscc", default=shutil.which("ISCC.exe"))
    args = parser.parse_args()
    if not args.iscc or not Path(args.iscc).is_file():
        parser.error("找不到 Inno Setup 编译器，请用 --iscc 指定 ISCC.exe")
    if args.source != prepare_windows.OUTPUT and not args.skip_export:
        parser.error("指定 --source 时必须同时使用 --skip-export")
    if not args.skip_export:
        if not prepare_windows.templates() or not prepare_windows.export(args.engine):
            return 1
    build(args.source.resolve(), Path(args.iscc).resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
