"""生成 build-tools/chapter_usage.json：每章（含战斗训练）实际用到的源资源清单，供网页按章拆包。

用法：python build-tools/chapter_usage.py [--engine 引擎路径]
每章启动一个无头 Godot 进程运行 chapter_asset_usage.gd，按多个种子把整章流式加载走一遍，
记录 ResourceLoader 解析过的全部路径，再借助工程 .import 文件把导入产物映射回 assets/ 源文件。
新增、删除资源或改动章节内容后重新运行；未记录到的资源由拆包脚本放进所有章节共用的 common 包。
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pck_report  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build-tools/chapter_usage.json"
DEFAULT_ENGINE = "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe"
CHAPTERS = {"0": "0", "1": "1", "2": "2", "3": "training"}
SEEDS = "20261012,7,99173,424242,31337,5150"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", default=DEFAULT_ENGINE)
    args = parser.parse_args()
    mapping = {"res://" + k.replace(os.sep, "/"): v.replace(os.sep, "/") for k, v in pck_report.sources().items()}
    result = {"generated": datetime.datetime.now().isoformat(timespec="seconds"), "seeds": SEEDS, "chapters": {}}
    with tempfile.TemporaryDirectory() as temp:
        for key, chapter in CHAPTERS.items():
            out = Path(temp) / f"usage_{key}.json"
            command = [args.engine, "--headless", "--path", str(ROOT), "-s", "res://build-tools/chapter_asset_usage.gd",
                       "--", f"--chapter={chapter}", f"--seeds={SEEDS}", f"--out={out}"]
            code = subprocess.run(command, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1800).returncode
            if code != 0 or not out.exists():
                print(f"chapter {chapter}: exit {code}", file=sys.stderr)
                return 1
            sources = set()
            for path in json.loads(out.read_text(encoding="utf-8"))["paths"]:
                source = mapping.get(path) or (path[6:] if path.startswith("res://assets/") else None)
                if source:
                    sources.add(source)
            result["chapters"][key] = sorted(sources)
            print(f"chapter {chapter}: {len(sources)} source assets")
    OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
