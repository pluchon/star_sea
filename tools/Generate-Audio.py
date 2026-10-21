"""生成项目自有音频；交叠连接环境循环，保留脚步材质差异。仅依赖标准库。"""

from array import array
from pathlib import Path
import hashlib
import json
import math
import random
import sys
import wave
import argparse

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
            if kind == "cave_wind":
                value = low[channel] * 3.2 * (0.6 + 0.25 * math.sin(time * .38)) + math.sin(math.tau * 83 * time + channel * .08) * .035
            elif kind == "cave_drip":
                phase = time % 1.73
                drop = math.sin(math.tau * (970 - phase * 280) * phase) * math.exp(-phase * 25)
                echo = math.sin(math.tau * 650 * max(phase - .23, 0)) * math.exp(-max(phase - .23, 0) * 18) * .25 if phase > .23 else 0
                value = (drop + echo) * .1 + low[channel] * .11
            elif kind == "wind":
                value = (low[channel] * 2.8 + body[channel] * 0.18) * gust
            elif kind == "shore":
                swell = (0.5 + 0.5 * math.sin(time * 0.83 + 0.45 * math.sin(time * 0.19))) ** 2
                wash = low[channel] * 1.8 + body[channel] * 0.65 + white * 0.025
                value = wash * (0.18 + 0.82 * swell)
            elif kind == "rustle":
                value = (body[channel] - low[channel]) * (0.3 + 0.7 * gust ** 3) + low[channel] * 0.4
            elif kind == "rain":
                # 细密的高频沙沙声打底，叠加随机的水滴声和远处低沉的雨幕。
                hiss = (white - body[channel]) * (0.55 + 0.1 * math.sin(time * 0.37 + channel))
                drop = (rng.random() < 0.0016) * rng.uniform(0.4, 1.0) * (1.0 if channel == 0 else rng.uniform(0.3, 1.0))
                value = hiss * 0.8 + low[channel] * 0.9 + drop * 0.6
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


def machinery(kind: str) -> dict:
    """分开模拟旋转谐波、气流、阻尼共振与机械锁扣，避免同一噪声改名复用。"""
    duration = {"engine": 12.0, "ship_land": 1.6, "ship_hatch": 1.25, "waterfall": 16.0}[kind]
    rng = random.Random(20261020 + sum(kind.encode()))
    count = round(duration * RATE)
    values = array("f")
    low = [0.0, 0.0]
    air = [0.0, 0.0]
    for index in range(count):
        time = index / RATE
        for channel in range(2):
            white = rng.uniform(-1, 1)
            low[channel] += (white - low[channel]) * 0.025
            air[channel] += (white - air[channel]) * 0.22
            if kind == "engine":
                # 整数周期的谐波与慢速调幅：循环时不发生相位跳变。
                rotor = sum(math.sin(math.tau * frequency * time + channel * 0.06) * amplitude
                            for frequency, amplitude in [(48, .28), (96, .08), (144, .045), (288, .025)])
                value = rotor * (.82 + .06 * math.sin(math.tau * time / 3)) + low[channel] * .7 + air[channel] * .07
            elif kind == "ship_land":
                # 三支支架依次接地，低频冲击之后是阻尼振动与减压气声。
                value = 0.0
                for delay, weight in [(0.025, 1), (.085, .7), (.14, .55)]:
                    t = max(time - delay, 0)
                    attack = min(t / .005, 1)
                    value += weight * attack * (math.sin(math.tau * 62 * t) * math.exp(-t * 13)
                                                + .23 * math.sin(math.tau * 173 * t) * math.exp(-t * 30))
                hiss = max(0, time - .18)
                value += (air[channel] - low[channel]) * min(hiss * 15, 1) * math.exp(-hiss * 4) * .75
            elif kind == "ship_hatch":
                # 锁扣、缓速电机与末端锁止分别占据不同的时间段。
                drive = math.sin(math.pi * min(max((time - .09) / .95, 0), 1)) ** 2
                phase = math.tau * (225 * time + 65 * time * time - 32 * time ** 3)
                value = drive * (.18 * math.sin(phase) + .045 * math.sin(phase * 2) + air[channel] * .3)
                for delay in (.025, 1.08):
                    t = max(time - delay, 0)
                    value += min(t * 600, 1) * math.exp(-t * 70) * (.5 * math.sin(math.tau * 410 * t) + air[channel])
            else:
                # 水幕的宽频冲击与低频水潭轰鸣，不使用显著音高。
                value = low[channel] * 2.8 + air[channel] * .65 + (white - air[channel]) * .10
                value *= .88 + .06 * math.sin(math.tau * time / 4 + channel * .3)
            if kind not in ("engine", "waterfall"):
                value *= min(time / .004, 1) * min((duration - time) / .06, 1)
            values.append(value)
    if kind in ("engine", "waterfall"):
        # 交叠循环保留接缝处的原始相邻样本，既不归零也不产生突跳。
        overlap = RATE
        for index in range(overlap):
            weight = .5 - .5 * math.cos(math.pi * index / (overlap - 1))
            for channel in range(2):
                tail_index = (count - overlap + index) * 2 + channel
                values[tail_index] = values[tail_index] * (1 - weight) + values[index * 2 + channel] * weight
        values = values[overlap * 2:]
    return write(kind, values, kind in ("engine", "waterfall"))


def traversal(kind: str) -> dict:
    rng = random.Random(20261021 + sum(kind.encode()))
    looping = kind == "high_wind"
    duration = 14 if looping else .48
    count = round(duration * RATE)
    overlap = RATE if looping else 0
    samples = array("f")
    low = [0.0, 0.0]
    body = [0.0, 0.0]
    for index in range(count + overlap):
        time = index / RATE
        for channel in range(2):
            white = rng.uniform(-1, 1)
            low[channel] += (white - low[channel]) * .025
            body[channel] += (white - body[channel]) * .19
            if looping:
                gust = .75 + .16 * math.sin(time * .47) + .08 * math.sin(time * 1.31 + channel)
                value = (low[channel] * 2.3 + body[channel] * .75 + white * .035) * gust
            else:
                # 低频布面抖开后留下两次短促的褶皱摩擦。
                envelope = min(time / .014, 1) * math.exp(-time * 12)
                pulse = math.exp(-((time - .14) / .025) ** 2) + .6 * math.exp(-((time - .26) / .04) ** 2)
                value = (low[channel] * 3 + body[channel]) * envelope + (white - body[channel]) * pulse * .15
                value *= min((duration - time) / .05, 1)
            samples.append(value)
    if looping:
        for index in range(overlap):
            weight = .5 - .5 * math.cos(math.pi * index / (overlap - 1))
            for channel in range(2):
                tail = (count + index) * 2 + channel
                samples[tail] = samples[tail] * (1 - weight) + samples[index * 2 + channel] * weight
        samples = samples[overlap * 2:]
    return write(kind, samples, looping)


def beacon() -> dict:
    rng = random.Random(20261028)
    samples = array("f")
    duration = 1.6
    for index in range(round(duration * RATE)):
        time = index / RATE
        attack = min(time / .025, 1)
        tail = min((duration - time) / .2, 1)
        for channel in range(2):
            resonance = sum(math.sin(math.tau * frequency * time + channel * .04) * amplitude
                            for frequency, amplitude in [(220, .3), (330, .14), (440, .08)])
            value = resonance * math.exp(-time * 2.8) + rng.uniform(-1, 1) * math.exp(-time * 12) * .12
            samples.append(value * attack * tail)
    return write("beacon_ignite", samples, False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=["ship", "waterfall", "traversal", "beacon", "cave"])
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    records = []
    if not args.only:
        records = [ambient(name, duration) for name, duration in
                   [("wind", 24), ("shore", 28), ("rustle", 24), ("space", 32), ("rain", 26)]]
        records.extend(footstep(surface, variant) for surface in ["grass", "sand", "rock", "snow"]
                       for variant in range(3))
    new_names = [] if args.only in ("traversal", "beacon", "cave") else (["waterfall"] if args.only == "waterfall" else ["engine", "ship_land", "ship_hatch"])
    if args.only is None:
        new_names.append("waterfall")
    records.extend(machinery(name) for name in new_names)
    if args.only in (None, "traversal"):
        records.extend(traversal(name) for name in ["glide_open", "high_wind"])
    if args.only in (None, "beacon"):
        records.append(beacon())
    if args.only in (None, "cave"):
        records.extend(ambient(name, 18) for name in ["cave_drip", "cave_wind"])
    report = OUTPUT.parents[1] / "test-output" / "audio" / "audio-generation.json"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"已生成 {len(records)} 个音频文件。")
