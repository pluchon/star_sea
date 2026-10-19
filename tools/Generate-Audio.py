"""生成项目自有的环境音和脚步音；仅使用 Python 标准库。"""

from pathlib import Path
import math
import random
import struct
import wave

RATE = 22050
OUTPUT = Path(__file__).resolve().parents[1] / "game" / "audio"


def generate(name: str, duration: float, kind: str) -> None:
    rng = random.Random(20261019 + len(name))
    count = int(duration * RATE)
    values = bytearray()
    low = [0.0, 0.0]
    for index in range(count):
        time = index / RATE
        envelope = min(1.0, time / 0.2, (duration - time) / 0.2)
        for channel in range(2):
            white = rng.uniform(-1.0, 1.0)
            low[channel] += (white - low[channel]) * 0.045
            if kind == "wind":
                gust = 0.4 + 0.3 * math.sin(math.tau * time / 8.0 + channel * 0.7)
                sample = (low[channel] * 1.8 + white * 0.025) * gust * 0.7
            elif kind == "shore":
                swell = (0.5 + math.sin(math.tau * time / 8.0) * 0.5) ** 1.8
                sample = (low[channel] * 1.8 + white * 0.15) * (0.2 + swell * 0.65)
            elif kind == "step":
                sample = (white * 0.4 + low[channel] * 2.0) * math.exp(-time * 34.0)
                envelope = min(1.0, time / 0.004)
            else:
                sample = sum(math.sin(math.tau * frequency * time + channel * 0.12) * amplitude
                             for frequency, amplitude in [(55, 0.12), (82.5, 0.045), (110, 0.018)])
                sample *= 0.65 + math.sin(math.tau * time / 24.0) * 0.25
            values.extend(struct.pack("<h", int(max(-0.98, min(0.98, sample * envelope)) * 32767)))
    with wave.open(str(OUTPUT / f"{name}.wav"), "wb") as audio:
        audio.setnchannels(2)
        audio.setsampwidth(2)
        audio.setframerate(RATE)
        audio.writeframes(values)


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    generate("wind", 16.0, "wind")
    generate("shore", 16.0, "shore")
    generate("space", 24.0, "space")
    generate("step", 0.22, "step")
