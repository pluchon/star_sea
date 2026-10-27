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
VERSION_COLOR_REGIONS = {
    "s3_ground_day": {"sky": (30, 40, 430, 180), "grass": (700, 780, 1100, 1080)},
    "s34_old_road": {"sky": (30, 40, 430, 180), "grass": (100, 800, 400, 1050)},
    "s30_town_plaza": COLOR_REGIONS["s30_town_plaza"],
    "s38_temple_hall": {},  # 室内没有天空和草地，不制造无意义的颜色基线。
    "s35_beacon_top": {"sky": (30, 40, 430, 180)},  # 此处是干旱地貌，不能把沙地当成草地。
    "s43_ladder_base": {"sky": (80, 30, 250, 120), "grass": (1670, 1040, 1780, 1075)},
    "s44_ladder_balcony": {"sky": (30, 40, 430, 180)},
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
    parser.add_argument("--version-tour", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    for name in ("before", "first", "after"):
        parser.add_argument("--" + name, type=Path)
    parser.add_argument("--reconstructed-before", nargs="*", default=[])
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.version_tour:
        version_review(args.version_tour, args.baseline, args.previous, args.output)
        return
    if any(value is None for value in (args.before, args.first, args.after)):
        parser.error("三轮对比需要 --before、--first、--after")
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


def flat_regions(rgb: np.ndarray) -> list[dict]:
    """按原图矩统计，连通区域可以呈不规则形状，避免缩图抹掉细纹后误报。"""
    from collections import deque
    luma = rgb @ np.array([.2126, .7152, .0722])
    height, width = luma.shape
    # 每个格子保留原图的一阶、二阶矩，统计不依赖缩图后的颜色。
    grid_w, grid_h = min(320, width), min(180, height)
    xs, ys = np.linspace(0, width, grid_w + 1, dtype=int), np.linspace(0, height, grid_h + 1, dtype=int)
    integral = np.pad(luma.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    integral2 = np.pad((luma * luma).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    counts = np.outer(np.diff(ys), np.diff(xs))
    def grid_sums(a):
        return a[np.ix_(ys[1:], xs[1:])] - a[np.ix_(ys[:-1], xs[1:])] - a[np.ix_(ys[1:], xs[:-1])] + a[np.ix_(ys[:-1], xs[:-1])]
    sums, squares = grid_sums(integral), grid_sums(integral2)
    means = sums / counts
    valid = np.maximum(0, squares / counts - means * means) < .02 ** 2
    findings = []
    seen_shapes = set()
    for offset in (0, .02):
        bins = np.floor((means + offset) / .04).astype(int)
        visited = np.zeros_like(valid)
        for y in range(grid_h):
            for x in range(grid_w):
                if visited[y, x] or not valid[y, x]:
                    continue
                queue = deque([(y, x)])
                visited[y, x] = True
                cells = []
                total = total2 = area = 0.
                while queue:
                    cy, cx = queue.popleft()
                    cells.append((cy, cx))
                    total += sums[cy, cx]
                    total2 += squares[cy, cx]
                    area += counts[cy, cx]
                    for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                        if 0 <= ny < grid_h and 0 <= nx < grid_w and not visited[ny, nx] and valid[ny, nx] and bins[ny, nx] == bins[y, x]:
                            visited[ny, nx] = True
                            queue.append((ny, nx))
                if area <= width * height * .05:
                    continue
                std = max(0, total2 / area - (total / area) ** 2) ** .5
                if std >= .02:
                    continue
                cells.sort()
                key = tuple(cells)
                if key in seen_shapes:
                    continue
                seen_shapes.add(key)
                rows = []
                for cy, cx in cells:
                    if rows and rows[-1][0] == cy and rows[-1][2] == cx:
                        rows[-1][2] = cx + 1
                    else:
                        rows.append([cy, cx, cx + 1])
                left, right = min(cx for _, cx in cells), max(cx for _, cx in cells) + 1
                top, bottom = min(cy for cy, _ in cells), max(cy for cy, _ in cells) + 1
                findings.append({"box_normalized": [xs[left] / width, ys[top] / height, xs[right] / width, ys[bottom] / height],
                                 "area_fraction": area / (width * height), "luminance_std": std,
                                 "shape": "connected_cells", "grid": [grid_w, grid_h], "cells_rle": rows})
    findings.sort(key=lambda row: (-row["area_fraction"], row["luminance_std"]))
    return findings[:20]


def version_review(tour: Path, baseline: Path | None, previous: Path | None, output: Path) -> None:
    manifest = json.loads(tour.read_text(encoding="utf-8-sig"))
    old = json.loads(previous.read_text(encoding="utf-8-sig")) if previous and previous.exists() else {}
    previous_comparable = old.get("measurement_version") == 2
    old_rows = {row["shot"]: row for row in old.get("results", [])} if previous_comparable else {}
    rows = []
    for entry in manifest.get("shots", []):
        if entry.get("view") != "forward" or not entry.get("passed"):
            continue
        path = Path(entry["screenshot"])
        image = Image.open(path).convert("RGB")
        rgb = np.asarray(image, dtype=float) / 255
        issues = []
        if image.size != (1920, 1080):
            issues.append("截图必须为 1920×1080，不能直接套用固定取样区域")
        flat = flat_regions(rgb)
        if flat:
            issues.append("超过画面 5% 的连通区域亮度标准差低于 0.02")
        mask_path, plain_path = Path(entry["ground_mask"]), Path(entry["no_outline"])
        mask_rgb = np.asarray(Image.open(mask_path).convert("RGB"), dtype=float) / 255
        plain = np.asarray(Image.open(plain_path).convert("RGB"), dtype=float) / 255
        ground = ((mask_rgb[:, :, 1] > mask_rgb[:, :, 0] * 1.5)
                  & (mask_rgb[:, :, 1] > mask_rgb[:, :, 2] * 1.5) & (mask_rgb[:, :, 1] > .15))
        ground[:image.height // 2] = False
        delta = (plain - rgb) @ np.array([.2126, .7152, .0722])
        outline = delta > .025
        density = float(outline[ground].mean()) if ground.any() else None
        if density is None or density > .04:
            issues.append("地面描边密度超过 4%" if density is not None else "没有可测量的地面区域")
        colors = {}
        source = baseline / f"{entry['shot']}.png" if baseline else None
        regions = VERSION_COLOR_REGIONS.get(entry["shot"])
        if regions == {}:
            colors = {"applicable": False, "reason": "室内机位，没有天空与草地"}
        elif source and source.exists() and regions is not None:
            original = Image.open(source).convert("RGB")
            if original.size != image.size:
                issues.append("基线分辨率不一致")
            else:
                for region, box in regions.items():
                    before, after = metrics(original, box), metrics(image, box)
                    ratios = {"saturation_ratio": after["saturation_mean"] / max(before["saturation_mean"], 1e-6),
                              "value_ratio": after["value_mean"] / max(before["value_mean"], 1e-6)}
                    ratios["passed"] = min(ratios.values()) >= .95
                    colors[region] = {"before": before, "after": after, **ratios}
                    if not ratios["passed"]:
                        issues.append(region + "饱和度或明度低于基线的 95%")
        else:
            issues.append("缺少原始颜色基线或经过核对的区域定义")
        if entry["shot"] == "s35_beacon_top":
            colors["grass_applicability"] = {"applicable": False, "reason": "当前与历史机位均为沙地，没有可比较的草地"}
        old_row = old_rows.get(entry["shot"], {})
        worse = False
        if old_row:
            worse = density is not None and old_row.get("outline_density") is not None and density > old_row["outline_density"] + 1e-6
            worse |= max((r["area_fraction"] for r in flat), default=0) > max((r["area_fraction"] for r in old_row.get("flat_regions", [])), default=0) + 1e-6
            for region, values in colors.items():
                old_values = old_row.get("colors", {}).get(region, {})
                if isinstance(values, dict) and isinstance(old_values, dict):
                    for field in ("saturation_ratio", "value_ratio"):
                        if field in values and field in old_values:
                            worse |= values[field] < old_values[field] - 1e-6
        rows.append({"shot": entry["shot"], "passed": not issues, "issues": issues,
                     "outline_density": density, "ground_pixels": int(ground.sum()),
                     "flat_regions": flat, "colors": colors, "worse_than_previous": bool(worse),
                     "image": str(path), "resolution": list(image.size), "ground_mask": str(mask_path), "no_outline": str(plain_path)})
    report = {"passed": len(rows) == 7 and all(row["passed"] for row in rows), "results": rows,
              "measurement_version": 2, "previous_comparable": previous_comparable,
              "baseline": str(baseline), "previous": str(previous) if previous else None,
              "color_comparison_limit": "历史截图保留来源与哈希；地形、选址和云层图案有变化，颜色比只提供复核线索，不能单独证明调色退化",
              "flat_search": "原图一阶和二阶矩的低方差格子连通分量，两次错开的亮度分箱；边界最多一个格子精度",
              "outline_method": "同机位关闭描边前后的亮度差，与场景分类渲染的地面掩码求交"}
    (output / "render.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    html = ['<!doctype html><meta charset="utf-8"><title>画面指标</title><style>body{font:16px sans-serif;background:#18202a;color:#eee}td,th{padding:12px;border:1px solid #607080}.worse{color:#ff7777}</style><table><tr><th>机位</th><th>结果</th><th>地面描边</th><th>天空／草地 S、V 与基线比</th><th>问题</th></tr>']
    import html as html_escape
    for row in rows:
        density = f"{row['outline_density']:.2%}" if row["outline_density"] is not None else "无有效区域"
        color_cells = []
        for region, value in row["colors"].items():
            if isinstance(value, dict) and "after" in value:
                color_cells.append(f"{region}: S={value['after']['saturation_mean']:.3f}, V={value['after']['value_mean']:.3f}; 比={value['saturation_ratio']:.3f}/{value['value_ratio']:.3f}")
        color_text = html_escape.escape("；".join(color_cells))
        css = ' class="worse"' if row["worse_than_previous"] else ''
        html.append(f"<tr{css}><td>{html_escape.escape(row['shot'])}</td><td>{'通过' if row['passed'] else '失败'}</td><td>{density}</td><td>{color_text}</td><td>{html_escape.escape('；'.join(row['issues']))}</td></tr>")
    (output / "render.html").write_text("\n".join(html) + "</table>", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "shots": len(rows), "report": str(output / 'render.json')}, ensure_ascii=False))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
