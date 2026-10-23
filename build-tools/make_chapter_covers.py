"""把 capture_chapter_covers.gd 渲染的原始画面裁成章节封面。

用法：
  CAPTURE_TIMEOUT=600 python build-tools/capture_hidden.py res://build-tools/capture_chapter_covers.gd
  python build-tools/make_chapter_covers.py
输出 assets/ui/covers/chapter_<n>.jpg（960×540，主界面卡片、章节载入画面和网页启动页共用）。
封面直接取自生产场景渲染，不另行绘制，保证与对应章节的实际画面一致。

2026-10-21 起 assets/ui/covers/ 改用用户提供的美术图（主页 home.jpg 与四章封面，1280×720），
本脚本保留，需要时可重新从游戏画面取景；运行会覆盖现有封面。
"""
from pathlib import Path
from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
CAPTURE = ROOT / "builds/cover-capture"
OUT = ROOT / "assets/ui/covers"
# 章节 → 选用的机位编号（见 capture_chapter_covers.gd 的 SHOTS）。
PICKS = {0: 1, 1: 3, 2: 7, 3: 9}
SIZE = (960, 540)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for chapter, shot in PICKS.items():
        source = CAPTURE / f"shot_{shot:02d}_ch{chapter}.png"
        image = Image.open(source).convert("RGB").resize(SIZE, Image.LANCZOS)
        # 轻微提高饱和与对比，让小尺寸卡片在暗色界面上仍然醒目。
        image = ImageEnhance.Color(image).enhance(1.08)
        image = ImageEnhance.Contrast(image).enhance(1.05)
        target = OUT / f"chapter_{chapter}.jpg"
        image.save(target, quality=84, optimize=True, progressive=True)
        print(f"{target.relative_to(ROOT)}: {target.stat().st_size} bytes from {source.name}")


if __name__ == "__main__":
    main()
