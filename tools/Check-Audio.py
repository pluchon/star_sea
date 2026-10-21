"""检查音频交付的削波、静音、循环接点和素材差异，不代替听感验收。"""

from array import array
from pathlib import Path
import argparse
import hashlib
import json
import math
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]


def inspect(path: Path, loop: bool) -> dict:
    with wave.open(str(path), "rb") as audio:
        channels = audio.getnchannels()
        rate = audio.getframerate()
        width = audio.getsampwidth()
        frames = audio.getnframes()
        data = audio.readframes(frames)
    if width != 2 or frames == 0:
        return {"file": path.name, "passed": False, "error": "没有有效的十六位 PCM 数据"}
    pcm = array("h", data)
    if sys.byteorder != "little":
        pcm.byteswap()
    rms = math.sqrt(sum(value * value for value in pcm) / len(pcm)) / 32768
    peak = max(abs(value) for value in pcm) / 32768
    mean = abs(sum(pcm) / len(pcm)) / 32768
    window = min(rate // 5 * channels, len(pcm))
    head = math.sqrt(sum(value * value for value in pcm[:window]) / window) / 32768
    tail = math.sqrt(sum(value * value for value in pcm[-window:]) / window) / 32768
    seam = max(abs(pcm[channel] - pcm[-channels + channel]) for channel in range(channels)) / 32768
    delta_peak = max(abs(pcm[index] - pcm[index - channels]) for index in range(channels, len(pcm))) / 32768
    passed = peak < 0.99 and rms > 0.0005 and mean < 0.02
    if loop:
        passed = passed and min(head, tail) > rms * 0.3 and seam <= delta_peak
    return {"file": path.name, "passed": passed, "duration_s": frames / rate, "rms": rms,
            "peak": peak, "dc_offset": mean, "seam_delta": seam, "maximum_sample_delta": delta_peak,
            "head_rms": head, "tail_rms": tail, "sha256": hashlib.sha256(data).hexdigest()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--recordings", type=Path)
    parser.add_argument("--music-recording", type=Path)
    parser.add_argument("--ship-recordings", type=Path)
    parser.add_argument("--scope", choices=["dawn", "all"], default="all")
    args = parser.parse_args()
    if args.ship_recordings:
        records = [inspect(args.ship_recordings / f"{name}.wav", False) for name in ["engine", "ship_land", "ship_hatch"]]
        count_ok = all(record["duration_s"] > 1.8 for record in records)
        filename = "ship-audio-mix-checks.json"
    elif args.music_recording:
        records = [inspect(args.music_recording, False)]
        count_ok = records[0]["duration_s"] >= 4.0
        filename = "music-mix-checks.json"
    elif args.recordings:
        names = ["s6_shore", "s9_woodland", "s1_space"] if args.scope == "dawn" else ["s6_shore", "s9_woodland", "s7_ember", "s8_frost", "s1_space"]
        paths = [args.recordings / f"{name}.wav" for name in names]
        records = [inspect(path, False) for path in paths]
        count_ok = len(records) == len(names)
        filename = "audio-mix-checks.json"
    else:
        paths = [ROOT / "game" / "audio" / f"{name}.wav" for name in ["wind", "shore", "rustle", "space", "rain"]]
        paths.extend(sorted((ROOT / "game" / "audio").glob("step_*.wav")))
        paths.extend(ROOT / "game" / "audio" / f"{name}.wav" for name in ["dawn_theme", "engine", "ship_land", "ship_hatch", "waterfall", "glide_open", "high_wind"])
        records = [inspect(path, path.stem in ["wind", "shore", "rustle", "space", "rain", "engine", "waterfall", "high_wind"]) for path in paths]
        count_ok = len(records) == 24 and len({record["sha256"] for record in records}) == 24
        filename = "audio-asset-checks.json"
    report = {"passed": count_ok and all(record["passed"] for record in records), "records": records}
    output = ROOT / "test-output" / "acceptance" / filename
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "files": len(records), "report": str(output)}, ensure_ascii=False))
    sys.exit(0 if report["passed"] else 1)
