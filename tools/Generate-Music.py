"""生成晨的原创稀疏器乐；使用加法合成、轻微失谐和离线回声，无外部录音。"""

from array import array
from pathlib import Path
import json
import math
import runpy

helpers = runpy.run_path(str(Path(__file__).with_name("Generate-Audio.py")))
rate = helpers["RATE"]
duration = 52
samples = array("f", [0.0]) * (rate * duration * 2)


def note(midi: int, onset: float, length: float, gain: float, pan: float, pad: bool = False):
    frequency = 440 * 2 ** ((midi - 69) / 12)
    start = round(onset * rate)
    for index in range(round(length * rate)):
        time = index / rate
        attack = min(1.0, time / (0.8 if pad else 0.025))
        release = min(1.0, (length - time) / (1.0 if pad else 0.45))
        envelope = attack * release * math.exp(-time * (0.18 if pad else 1.15))
        tone = math.sin(math.tau * frequency * time)
        tone += math.sin(math.tau * frequency * 2.002 * time) * (0.12 if pad else 0.23)
        tone += math.sin(math.tau * frequency * 3.0 * time) * 0.035
        value = tone * envelope * gain
        for channel, stereo in enumerate((1.0 - pan * 0.25, 1.0 + pan * 0.25)):
            position = (start + index) * 2 + channel
            if position < len(samples):
                samples[position] += value * stereo


# 自编稀疏旋律，留白长于连续演奏；低声部只提供稀疏和声。
melody = [(0, 74), (2.4, 81), (5.2, 78), (9.6, 76), (12.0, 73), (16.8, 74),
          (19.2, 78), (21.6, 81), (26.4, 83), (28.8, 81), (33.6, 78),
          (36.0, 76), (40.8, 74), (43.2, 81)]
for index, (onset, pitch) in enumerate(melody):
    note(pitch, onset + 0.8, 4.8, 0.20, math.sin(index * 1.4))
for onset, pitches in [(0.0, [50, 57, 64]), (12.0, [47, 54, 61]),
                       (24.0, [43, 50, 57]), (36.0, [50, 57, 64])]:
    for pitch in pitches:
        note(pitch, onset, 10.0, 0.035, 0.0, True)
dry = samples[:]
for delay, gain in [(0.31, 0.18), (0.59, 0.11), (0.97, 0.07)]:
    offset = round(delay * rate) * 2
    for index in range(offset, len(samples)):
        samples[index] += dry[index - offset] * gain
record = helpers["write"]("dawn_theme", samples, False)
target = Path(__file__).resolve().parents[1] / "test-output/acceptance/music-generation.json"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(record, ensure_ascii=False))
