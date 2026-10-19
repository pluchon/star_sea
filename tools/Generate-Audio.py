"""生成项目自有音频；交叠连接环境循环，保留脚步材质差异。仅依赖标准库。"""

from array import array
from pathlib import Path
import hashlib
import json
import math
import random
import sys
import wave

RATE = 22050
OUTPUT = Path(__file__).resolve().parents[1] / "game" / "audio"


def write(name: str, samples: array, loop: bool) -> dict:
    peak = max(abs(value) for value in samples)
    rms = math.sqrt(sum(value * value for value in samples) / len(samples))
    gain = min(0.72 / max(peak, 1e-9), (0.15 if loop else 0.12) / max(rms, 1e-9))
    pcm = array("h", (round(value * gain * 32767) for value in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    path = OUTPUT / f"{name}.wav"
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(2)
        audio.setsampwidth(2)
        audio.setframerate(RATE)
        audio.writeframes(pcm.tobytes())
    return {"name": name, "duration_s": len(samples) / (RATE * 2), "peak": peak * gain,
            "rms": rms * gain, "loop": loop, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def ambient(kind: str, duration: int) -> dict:
    rng = random.Random(20261019 + sum(kind.encode()))
    count = duration * RATE
    overlap = RATE * 2
    values = array("f")
    low = [0.0, 0.0]
    body = [0.0, 0.0]
    for index in range(count + overlap):
        time = index / RATE
        common = rng.uniform(-1.0, 1.0)
        for channel in range(2):
            white = common * 0.7 + rng.uniform(-1.0, 1.0) * 0.3
            low[channel] += (white - low[channel]) * 0.018
            body[channel] += (white - body[channel]) * 0.16
            gust = 0.65 + 0.18 * math.sin(time * 0.71) + 0.12 * math.sin(time * 0.23 + channel * 0.4)
            if kind == "wind":
                value = (low[channel] * 2.8 + body[channel] * 0.18) * gust
            elif kind == "shore":
                swell = (0.5 + 0.5 * math.sin(time * 0.83 + 0.45 * math.sin(time * 0.19))) ** 2
                wash = low[channel] * 1.8 + body[channel] * 0.65 + white * 0.025
                value = wash * (0.18 + 0.82 * swell)
            elif kind == "rustle":
                value = (body[channel] - low[channel]) * (0.3 + 0.7 * gust ** 3) + low[channel] * 0.4
            else:
                value = sum(math.sin(math.tau * frequency * time + channel * 0.04) * amplitude
                            for frequency, amplitude in [(49, 0.08), (73.5, 0.025), (98, 0.01)])
                value = value * (0.65 + math.sin(time * 0.17) * 0.2) + low[channel] * 0.035
            values.append(value)
    # 接入原始开头后，循环接点两侧保持原始相邻采样，不定期淡出到静音。
    result = values[overlap * 2:count * 2]
    for index in range(overlap):
        weight = 0.5 - math.cos(math.pi * index / (overlap - 1)) * 0.5
        for channel in range(2):
            tail = values[(count + index) * 2 + channel]
            head = values[index * 2 + channel]
            result.append(tail * (1.0 - weight) + head * weight)
    return write(kind, result, True)


def footstep(surface: str, variant: int) -> dict:
    rng = random.Random(20261019 + sum(surface.encode()) * 7 + variant)
    duration = 0.32
    values = array("f")
    low = 0.0
    for index in range(round(duration * RATE)):
        time = index / RATE
        white = rng.uniform(-1.0, 1.0)
        low += (white - low) * 0.09
        impact = math.sin(math.tau * (78.0 + variant * 5.0) * time) * math.exp(-time * 42.0)
        attack = min(1.0, time / 0.004)
        if surface == "rock":
            value = impact * 0.75 + white * math.exp(-time * 75.0) * 0.16
        elif surface == "sand":
            value = impact * 0.25 + low * math.exp(-time * 18.0) * 1.9
        elif surface == "snow":
            crunch = (white - low) * (0.6 + 0.4 * math.sin(time * 290.0))
            value = impact * 0.16 + crunch * math.exp(-time * 24.0) * 0.4
        else:
            value = impact * 0.32 + (low * 0.9 + white * 0.06) * math.exp(-time * 23.0)
        value *= attack * min(1.0, (duration - time) / 0.03)
        values.extend((value, value))
    return write(f"step_{surface}_{variant}", values, False)


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    records = [ambient(name, duration) for name, duration in
               [("wind", 24), ("shore", 28), ("rustle", 24), ("space", 32)]]
    records.extend(footstep(surface, variant) for surface in ["grass", "sand", "rock", "snow"]
                   for variant in range(3))
    report = OUTPUT.parents[1] / "test-output" / "acceptance" / "audio-generation.json"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"已生成 {len(records)} 个音频文件。")
