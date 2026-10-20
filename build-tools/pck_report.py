"""列出 Godot 4 PCK 的体积构成：按导入类型和源资源汇总，便于比较网页包瘦身前后。

用法：python build-tools/pck_report.py builds/web/index.pck [--top 30]
只读取 GDPC 头和目录表（格式版本 3，Godot 4.x），不解包、不修改文件。
"""
import argparse
import collections
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]


def entries(pck):
    with open(pck, "rb") as stream:
        if stream.read(4) != b"GDPC":
            raise SystemExit("不是 Godot PCK")
        version = struct.unpack("<I", stream.read(4))[0]
        if version < 3:
            raise SystemExit(f"不支持的 PCK 格式版本 {version}")
        stream.read(16 + 8)  # 引擎版本、标志、文件基址
        stream.seek(struct.unpack("<Q", stream.read(8))[0])
        for _ in range(struct.unpack("<I", stream.read(4))[0]):
            length = struct.unpack("<I", stream.read(4))[0]
            path = stream.read(length).rstrip(b"\0").decode()
            _offset, size = struct.unpack("<QQ", stream.read(16))
            stream.read(16 + 4)  # MD5、标志
            yield path, size


def sources():
    """把 .godot/imported 下的导入产物映射回 assets/ 源文件。"""
    mapping = {}
    for imported in ROOT.rglob("*.import"):
        if ".godot" in imported.parts:
            continue
        text = imported.read_text(encoding="utf-8", errors="ignore")
        for target in re.findall(r'res://(\.godot/imported/[^"]+)', text):
            mapping[target] = str(imported.relative_to(ROOT))[:-len(".import")]
    return mapping


def kind(path):
    if ".s3tc." in path or ".etc2." in path or ".astc." in path or ".bptc." in path:
        return "ctex(vram)"
    return path.rsplit(".", 1)[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pck", type=Path)
    parser.add_argument("--top", type=int, default=30)
    args = parser.parse_args()
    rows = list(entries(args.pck))
    total = sum(size for _, size in rows)
    print(f"{args.pck}: {len(rows)} 个文件，{total / 1e6:.1f} MB（文件 {args.pck.stat().st_size / 1e6:.1f} MB）")
    by_kind = collections.Counter()
    for path, size in rows:
        by_kind[kind(path)] += size
    for name, size in by_kind.most_common(12):
        print(f"  {name:<14}{size / 1e6:8.1f} MB")
    mapping = sources()
    by_source = collections.Counter()
    for path, size in rows:
        by_source[mapping.get(path, path)] += size
    by_dir = collections.Counter()
    for path, size in by_source.items():
        by_dir["/".join(path.split("/")[:2])] += size
    print("按目录：")
    for name, size in by_dir.most_common(12):
        print(f"  {size / 1e6:7.1f} MB  {name}")
    print(f"最大的 {args.top} 个源资源：")
    for name, size in by_source.most_common(args.top):
        print(f"  {size / 1e6:7.2f} MB  {name}")


if __name__ == "__main__":
    main()
