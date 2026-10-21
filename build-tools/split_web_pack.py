"""网页包按章节拆分：把 Godot 导出的整包 index.pck 拆成主包与若干章节数据包。

用法：python build-tools/split_web_pack.py builds/web     （prepare_web.py 导出后自动调用）

- 主包 index.pck：脚本、场景、着色器、界面图标、章节封面和字体，打开网页即可显示主界面。
- 章节数据包 packs/<组>[@贴图格式].<哈希>.pck：按 build-tools/chapter_usage.json 记录的
  “每章实际用到的资源”分组。所有章节都用的资源进 common，只有部分章节用的按使用组合分组
  （如 c01 = 第一、二章共用），多个章节共用的包只下载一次。
- VRAM 压缩贴图按格式再拆：桌面浏览器只下载 s3tc，手机只下载 etc2，各省约一半贴图流量。
- 用量记录里从未出现的资源一律放进 common：宁可多下载，也不让某章缺资源。

文件内容逐字节取自原包（不重新导出、不改资源），目录项的 MD5 原样保留。
输出 packs.json（章节 → 所需数据包）与 sw-files.json（Service Worker 缓存清单）。
PCK 格式按 Godot 4.7 导出的版本 4 读写：文件头 + 16 字节对齐的数据区 + 末尾目录。
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
USAGE = ROOT / "build-tools/chapter_usage.json"
CHAPTERS = ["0", "1", "2", "3"]
CORE_PREFIXES = ("assets/ui/", "assets/fonts/")
BUILD_FILE = "ct_build.txt"
ALIGN = 16


def read_pack(path):
    data = path.read_bytes()
    if data[:4] != b"GDPC":
        raise SystemExit("不是 Godot PCK")
    version, major, minor, patch, flags = struct.unpack_from("<5I", data, 4)
    if version != 4:
        raise SystemExit(f"只支持 Godot 4.7 导出的 PCK 格式版本 4，实际为 {version}")
    file_base, directory = struct.unpack_from("<2Q", data, 24)
    count = struct.unpack_from("<I", data, directory)[0]
    cursor = directory + 4
    entries = []
    for _ in range(count):
        length = struct.unpack_from("<I", data, cursor)[0]
        raw_path = data[cursor + 4:cursor + 4 + length]
        cursor += 4 + length
        offset, size = struct.unpack_from("<2Q", data, cursor)
        md5 = data[cursor + 16:cursor + 32]
        entry_flags = struct.unpack_from("<I", data, cursor + 32)[0]
        cursor += 36
        start = file_base + offset
        entries.append({"path": raw_path.rstrip(b"\0").decode(), "raw_path": raw_path, "md5": md5,
                        "flags": entry_flags, "data": data[start:start + size]})
    return {"header": (version, major, minor, patch, flags)}, entries


def write_pack(path, header, entries):
    version, major, minor, patch, flags = header
    blob = bytearray()
    blob += b"GDPC" + struct.pack("<5I", version, major, minor, patch, flags)
    blob += struct.pack("<2Q", 0, 0)  # 数据区基址与目录偏移，稍后回填
    blob += b"\0" * 64
    blob += b"\0" * (-len(blob) % ALIGN)
    file_base = len(blob)
    rows = []
    for entry in entries:
        offset = len(blob) - file_base
        blob += entry["data"]
        blob += b"\0" * (-len(blob) % ALIGN)
        rows.append((entry, offset))
    directory = len(blob)
    blob += struct.pack("<I", len(rows))
    for entry, offset in rows:
        blob += struct.pack("<I", len(entry["raw_path"])) + entry["raw_path"]
        blob += struct.pack("<2Q", offset, len(entry["data"])) + entry["md5"] + struct.pack("<I", entry["flags"])
    struct.pack_into("<2Q", blob, 24, file_base, directory)
    path.write_bytes(bytes(blob))
    return len(blob)


def text_entry(path, text):
    raw = path.encode() + b"\0"
    raw += b"\0" * (-len(raw) % 4)
    data = text.encode()
    return {"path": path, "raw_path": raw, "md5": hashlib.md5(data).digest(), "flags": 0, "data": data}


def source_map(entries):
    """用包内 .import / .remap 文件把导入产物映射回源文件（不依赖本机 .godot 缓存）。"""
    mapping = {}
    for entry in entries:
        path = entry["path"]
        if path.endswith(".import") or path.endswith(".remap"):
            source = path.rsplit(".", 1)[0]
            for target in re.findall(r'res://(\.godot/[^"]+)', entry["data"].decode("utf-8", "ignore")):
                mapping[target] = source
    return mapping


def classify(path, mapping):
    if path.endswith(".import") or path.endswith(".remap"):
        source = path.rsplit(".", 1)[0]
    elif path.startswith(".godot/imported/") or path.startswith(".godot/exported/"):
        source = mapping.get(path)
    else:
        source = path
    match = re.search(r"\.(s3tc|etc2|bptc|astc)\.ctex$", path)
    return source, match.group(1) if match else ""


def group_of(source, usage):
    if source is None or not source.startswith("assets/") or source.startswith(CORE_PREFIXES):
        return "core"
    who = [c for c in CHAPTERS if source in usage[c]]
    if len(who) in (0, len(CHAPTERS)):
        return "common"
    return "c" + "".join(who)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", type=Path, help="导出目录，内含整包 index.pck")
    args = parser.parse_args()
    usage_data = json.loads(USAGE.read_text(encoding="utf-8"))
    usage = {c: set(usage_data["chapters"][c]) for c in CHAPTERS}
    pack_path = args.web / "index.pck"
    info, entries = read_pack(pack_path)
    mapping = source_map(entries)
    groups = collections.defaultdict(list)
    for entry in entries:
        source, feature = classify(entry["path"], mapping)
        group = group_of(source, usage)
        name = group if group == "core" or not feature else f"{group}@{feature}"
        groups[name].append(entry)
    out_dir = args.web / "packs"
    out_dir.mkdir(exist_ok=True)
    for old in out_dir.glob("*.pck"):
        old.unlink()
    build = hashlib.sha256(pack_path.read_bytes()).hexdigest()[:16]
    manifest = {"build": build, "packs": {}, "chapters": {c: [] for c in CHAPTERS}}
    sw_files = {}
    for name in sorted(groups):
        if name == "core":
            continue
        temp = out_dir / f"{name}.tmp"
        size = write_pack(temp, info["header"], groups[name])
        digest = hashlib.sha256(temp.read_bytes()).hexdigest()[:12]
        file_name = f"{name.replace('@', '-')}.{digest}.pck"
        temp.replace(out_dir / file_name)
        feature = name.split("@")[1] if "@" in name else ""
        manifest["packs"][name] = {"file": f"packs/{file_name}", "size": size, "feature": feature, "hash": digest}
        sw_files[f"packs/{file_name}"] = digest
        group = name.split("@")[0]
        members = CHAPTERS if group == "common" else list(group[1:])
        for chapter in members:
            manifest["chapters"][chapter].append(name)
    # 主包写入构建号，网页据此确认清单与主包来自同一次导出。
    core = groups["core"] + [text_entry(BUILD_FILE, build)]
    full = pack_path.with_name("index.full.pck")
    pack_path.replace(full)
    core_size = write_pack(pack_path, info["header"], core)
    full.unlink()
    (args.web / "packs.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    (args.web / "sw-files.json").write_text(json.dumps(sw_files, indent=1), encoding="utf-8")
    print(f"core index.pck: {core_size / 1e6:.1f} MB, {len(core)} files, build {build}")
    for name, pack in manifest["packs"].items():
        print(f"  {name:14s} {pack['size'] / 1e6:7.1f} MB  {pack['file']}")
    for chapter in CHAPTERS:
        for feature in ("s3tc", "etc2"):
            total = sum(manifest["packs"][n]["size"] for n in manifest["chapters"][chapter]
                        if manifest["packs"][n]["feature"] in ("", feature))
            print(f"  chapter {chapter} ({feature}): {total / 1e6:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
