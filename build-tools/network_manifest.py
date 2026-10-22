"""生成联机脚本指纹；源工程实时计算，导出包使用此清单，跨平台统一换行。"""
import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "scripts/net_manifest.gd"


def fingerprint(root=ROOT):
    digest = hashlib.sha256()
    paths = sorted(p for p in (root / "scripts").glob("*.gd") if p.name != "net_manifest.gd")
    for path in paths:
        digest.update((path.relative_to(root).as_posix() + "\n").encode())
        digest.update(path.read_text(encoding="utf-8").replace("\r\n", "\n").encode())
        digest.update(b"\n")
    return digest.hexdigest()


def generate():
    content = ('extends RefCounted\n# 自动生成：python3 build-tools/network_manifest.py。导出前刷新，禁止手工填版本。\n'
               f'const FINGERPRINT := "{fingerprint()}"\n')
    if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != content:
        TARGET.write_bytes(content.encode("utf-8"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        if not TARGET.exists() or f'"{fingerprint()}"' not in TARGET.read_text(encoding="utf-8"):
            raise SystemExit("联机指纹过期，请运行 python3 build-tools/network_manifest.py")
    else:
        generate()
    print("Network fingerprint: " + fingerprint())
