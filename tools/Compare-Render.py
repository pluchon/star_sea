"""生成同机位彩色、灰度和参考对比图，原始截图保持不变。"""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


def panel(paths: list[Path], labels: list[str], gray: bool = False) -> Image.Image:
    width, height = 640, 360
    result = Image.new("RGB", (width * len(paths), height + 32), "#171d25")
    draw = ImageDraw.Draw(result)
    for index, (path, label) in enumerate(zip(paths, labels)):
        with Image.open(path) as source:
            image = ImageOps.contain(source.convert("RGB"), (width, height))
        if gray:
            image = ImageOps.grayscale(image).convert("RGB")
        result.paste(image, (index * width + (width - image.width) // 2, 32 + (height - image.height) // 2))
        draw.text((index * width + 12, 10), label, fill="white")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--references", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    rows: list[Image.Image] = []
    for after in sorted(args.after.glob("*.png")):
        before = args.before / after.name
        if not before.is_file():
            panel([after], [after.stem]).save(args.output / f"{after.stem}.jpg", quality=85)
            continue
        color = panel([before, after], [f"{after.stem} | Before", "After"])
        gray = panel([before, after], ["Before | Grayscale", "After | Grayscale"], gray=True)
        paired = Image.new("RGB", (color.width, color.height + gray.height))
        paired.paste(color)
        paired.paste(gray, (0, color.height))
        paired.save(args.output / f"{after.stem}.jpg", quality=85)
        rows.append(color.resize((960, 294)))
        if args.references:
            if after.stem in ("s1_space", "s7_ember", "s8_frost"):
                continue
            if after.stem in ("s30_town_plaza", "s38_temple_hall", "s43_ladder_base", "s35_beacon_top"):
                references = [args.references / "sable-0.jpg", args.references / "journey-0.jpg"]
            else:
                references = [args.references / "firewatch-forest.jpg", args.references / "firewatch-range.jpg"]
            if all(path.is_file() for path in references):
                comparison = panel(references + [before, after], ["Reference 1", "Reference 2", "Before", "After"])
                comparison.save(args.output / f"{after.stem}-reference.jpg", quality=85)
    if rows:
        overview = Image.new("RGB", (960 * 2, 294 * ((len(rows) + 1) // 2)), "#171d25")
        for index, row in enumerate(rows):
            overview.paste(row, ((index % 2) * 960, (index // 2) * 294))
        overview.save(args.output / "overview.jpg", quality=85)


if __name__ == "__main__":
    main()
