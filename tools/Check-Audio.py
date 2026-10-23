"""检查音频交付的削波、静音、循环接点和素材差异，不代替听感验收。"""

from array import array
from pathlib import Path
import argparse
import hashlib
import json
import math
import sys
import wave
import re
import shutil
import subprocess

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


def inspect_music(path: Path) -> dict:
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise RuntimeError("缺少 ffmpeg 或 ffprobe，无法检查音乐响度和格式。")
    result = subprocess.run(["ffmpeg", "-nostdin", "-i", str(path), "-af", "astats=metadata=0:reset=0", "-f", "null", "-"], capture_output=True, check=True)
    stats = result.stderr.decode("utf-8", errors="replace")
    rms = float(re.findall(r"RMS level dB: ([-\d.]+)", stats)[-1])
    peak = float(re.findall(r"Peak level dB: ([-\d.]+)", stats)[-1])
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(path)], capture_output=True, check=True)
    stream = json.loads(probe.stdout)["streams"][0]
    return {"file": path.name, "rms_dbfs": rms, "peak_dbfs": peak, "duration_s": float(stream["duration"]),
            "passed": -26 <= rms <= -18 and peak <= -1 and stream["codec_name"] == "vorbis" and int(stream["sample_rate"]) == 44100 and stream["channels"] == 2}


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
        paths = [ROOT / "game" / "audio" / f"{name}.wav" for name in ["wind", "shore", "rustle", "space", "rain", "cave_drip", "cave_wind", "ruin_wind", "night_insects"]]
        paths.extend(sorted((ROOT / "game" / "audio").glob("step_*.wav")))
        paths.extend(ROOT / "game" / "audio" / f"{name}.wav" for name in ["engine", "ship_land", "ship_hatch", "waterfall", "glide_open", "high_wind", "beacon_ignite", "lift_start", "lift_hum", "discover"])
        paths.append(ROOT / "game/audio/music/fallback/dawn_theme.wav")
        records = [inspect(path, path.stem in ["wind", "shore", "rustle", "space", "rain", "engine", "waterfall", "high_wind", "cave_drip", "cave_wind", "lift_hum", "ruin_wind", "night_insects"]) for path in paths]
        count_ok = len(records) == 32 and len({record["sha256"] for record in records}) == 32
        music = [inspect_music(path) for path in sorted((ROOT / "game/audio/music").glob("*.ogg"))]
        source = (ROOT / "game/audio/music/来源.md").read_text(encoding="utf-8")
        count_ok = count_ok and len(music) == 27 and all(record["file"] in source for record in music)
        records.extend(music)
        filename = "audio-asset-checks.json"
    report = {"passed": count_ok and all(record["passed"] for record in records), "records": records}
    output = ROOT / "test-output" / "acceptance" / filename
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "files": len(records), "report": str(output)}, ensure_ascii=False))
    sys.exit(0 if report["passed"] else 1)
