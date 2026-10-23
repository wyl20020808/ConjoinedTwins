"""生成网页版用的中文字体子集 assets/fonts/NotoSansSC-web-subset.otf。

浏览器里的 Godot 无法使用系统字体，中文会显示成方框，所以网页版需要随包携带字体。
完整的 Noto Sans SC 约 8 MB，这里只保留：ASCII、常用中文标点、GB2312 一级汉字（3755 个常用字），
以及项目 scripts/ 和 scenes/ 中出现过的所有字符。项目新增了生僻字时重新运行本脚本即可。

用法（开发机运行，需要 pip 包 fonttools）：
  python build-tools/make_web_font.py
源字体：Noto Sans SC Regular（SIL Open Font License 1.1），来自 https://github.com/notofonts/noto-cjk ，
下载到被 Git 忽略的 build-tools/cache/fonts/ 后再运行。
"""
from pathlib import Path
import sys

from fontTools import subset

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "build-tools/cache/fonts/NotoSansSC-Regular.otf"
OUTPUT = ROOT / "assets/fonts/NotoSansSC-web-subset.otf"


def gb2312_level1():
    # GB2312 一级汉字区位：高字节 0xB0–0xD7，低字节 0xA1–0xFE（0xD7FA 之后为空位）。
    chars = []
    for high in range(0xB0, 0xD8):
        for low in range(0xA1, 0xFF):
            try:
                chars.append(bytes([high, low]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return chars


def project_chars():
    chars = set()
    for folder in ("scripts", "scenes"):
        for path in (ROOT / folder).rglob("*"):
            if path.suffix in (".gd", ".tscn", ".tres"):
                chars.update(path.read_text(encoding="utf-8"))
    return chars


def main():
    if not SOURCE.exists():
        print(f"缺少源字体：{SOURCE}", file=sys.stderr)
        return 1
    text = set(chr(c) for c in range(0x20, 0x7F))
    text.update("，。、；：？！“”‘’（）《》【】—…·～￥％＋－×÷＝＜＞／＼｜　0123456789")
    text.update(gb2312_level1())
    text.update(c for c in project_chars() if ord(c) >= 0x20)
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_outline = True
    font = subset.load_font(str(SOURCE), options)
    subsetter = subset.Subsetter(options)
    subsetter.populate(text="".join(sorted(text)))
    subsetter.subset(font)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    subset.save_font(font, str(OUTPUT), options)
    print(f"{OUTPUT} {OUTPUT.stat().st_size} bytes, {len(text)} chars requested")
    return 0


if __name__ == "__main__":
    sys.exit(main())
