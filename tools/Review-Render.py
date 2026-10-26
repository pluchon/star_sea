"""从原始机位图生成三轮对比、固定区域指标及裁切证据；需要 Pillow 和 NumPy。"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageOps


# 坐标按 1920×1080 原图记录；测量前须检查三个版本中对应区域的实际内容。
COLOR_REGIONS = {
    "s30_town_plaza": {"sky": (30, 40, 430, 180), "grass": (200, 950, 450, 1070)},
    "s41_ladder_from_spawn": {"sky": (30, 40, 430, 180), "grass": (700, 780, 1100, 1080)},
    "s49_range_from_spawn": {"sky": (30, 40, 430, 180), "grass": (700, 780, 1100, 1080)},
    "s62_materials": {"sky": (30, 40, 430, 180), "grass": (700, 780, 1100, 1080)},
}
GRASS_REGIONS = {
    "s62_materials": (600, 760, 1000, 1060),
    "s71_spawn_east": (600, 760, 1000, 1060),
}


def metrics(image: Image.Image, box: tuple[int, int, int, int]) -> dict:
    crop = image.crop(box)
    hsv = np.asarray(crop.convert("HSV"), dtype=float) / 255.0
    rgb = np.asarray(crop.convert("RGB"), dtype=float) / 255.0
    luminance = rgb @ np.array([0.2126, 0.7152, 0.0722])
    return {"box": box, "saturation_mean": float(hsv[:, :, 1].mean()),
            "value_mean": float(hsv[:, :, 2].mean()),
            "luminance_mean": float(luminance.mean()), "luminance_std": float(luminance.std())}


def panel(images: list[Image.Image], labels: list[str], width: int = 640, gray: bool = False) -> Image.Image:
    height = round(width * images[0].height / images[0].width)
    result = Image.new("RGB", (width * len(images), height + 28), "#171d25")
    draw = ImageDraw.Draw(result)
    for index, (source, label) in enumerate(zip(images, labels)):
        resized = source.resize((width, height), Image.Resampling.LANCZOS)
        if gray:
            resized = ImageOps.grayscale(resized).convert("RGB")
        result.paste(resized, (index * width, 28))
        draw.text((index * width + 10, 8), label, fill="white")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("before", "first", "after", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--reconstructed-before", nargs="*", default=[])
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    directories = [args.before, args.first, args.after]
    labels = ["Before step 1", "First round", "Correction"]
    report = {"color_regions": {}, "grass_regions": {}, "missing_before": [],
              "reconstructed_before": args.reconstructed_before}
    overview = []
    for path in sorted(args.after.glob("*.png")):
        sources, names = [], []
        by_version = {}
        for directory, label in zip(directories, labels):
            source = directory / path.name
            if not source.exists():
                continue
            image = Image.open(source).convert("RGB")
            if image.size != (1920, 1080):
                raise ValueError(f"固定区域指标要求 1920×1080 原图：{source}")
            sources.append(image)
            names.append(label + " (rebuilt)" if directory == args.before and path.stem in args.reconstructed_before else label)
            by_version[label] = image
        color = panel(sources, names)
        gray = panel(sources, names, gray=True)
        both = Image.new("RGB", (color.width, color.height * 2))
        both.paste(color)
        both.paste(gray, (0, color.height))
        both.save(args.output / f"{path.stem}.jpg", quality=88)
        overview.append(panel(sources, names, width=384))
        if labels[0] not in by_version:
            report["missing_before"].append(path.stem)
        if path.stem in COLOR_REGIONS:
            regions = {}
            for region, box in COLOR_REGIONS[path.stem].items():
                values = {key: metrics(img, box) for key, img in by_version.items()}
                if labels[0] in values:
                    original, final = values[labels[0]], values[labels[2]]
                    values["saturation_ratio"] = final["saturation_mean"] / max(original["saturation_mean"], 1e-6)
                    values["value_ratio"] = final["value_mean"] / max(original["value_mean"], 1e-6)
                    values["passed"] = values["saturation_ratio"] >= 0.95 and values["value_ratio"] >= 0.95
                regions[region] = values
                panel([img.crop(box) for img in sources], names, width=400).save(
                    args.output / f"{path.stem}-{region}.jpg", quality=92)
            report["color_regions"][path.stem] = regions
        if path.stem in GRASS_REGIONS:
            box = GRASS_REGIONS[path.stem]
            values = metrics(by_version[labels[2]], box)
            values["passed"] = values["luminance_std"] >= 0.035
            report["grass_regions"][path.stem] = values
            panel([img.crop(box) for img in sources], names, width=400).save(
                args.output / f"{path.stem}-brush.jpg", quality=94)
        if path.stem == "s62_materials":
            half = by_version[labels[2]].resize((960, 540), Image.Resampling.LANCZOS)
            half.save(args.output / "s62-half.png")
            half.crop((350, 70, 880, 330)).save(args.output / "s62-half-contours.png")
    if overview:
        width = max(row.width for row in overview)
        height = sum(row.height for row in overview)
        result = Image.new("RGB", (width, height), "#171d25")
        offset = 0
        for row in overview:
            result.paste(row, (0, offset))
            offset += row.height
        result.save(args.output / "overview.jpg", quality=85)
    (args.output / "metrics.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
