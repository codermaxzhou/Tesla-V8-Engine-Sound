#!/usr/bin/env python3
"""Generate original, low-amplitude synthetic WAVs; no vehicle recordings are used."""
from pathlib import Path
import math
import random
import struct
import wave

root = Path(__file__).resolve().parents[1] / 'VirtualV8' / 'Audio' / 'V8_62_NA'
root.mkdir(parents=True, exist_ok=True)
loops = {'idle': 750, 'low_1500': 1500, 'low_2500': 2500,
         'mid_3500': 3500, 'mid_4500': 4500, 'high_5500': 5500,
         'high_6500': 6500, 'load': 2100, 'intake': 6000, 'overrun': 1800}
transients = ['shift_up_1', 'shift_up_2', 'downshift', 'pop_1', 'pop_2', 'pop_3', 'limiter']
rate = 48000
for asset in list(loops) + transients:
    is_loop = asset in loops
    duration = 3 if is_loop else 0.24 if asset == 'downshift' else 0.12
    frequency = loops[asset] / 60 * 4 if is_loop else 85 if asset.startswith('pop') else 140
    rng = random.Random(asset)
    count = int(duration * rate)
    samples = bytearray()
    for i in range(count):
        t = i / rate
        phase = 2 * math.pi * frequency * t
        if asset == 'downshift':
            phase = 2 * math.pi * (100 * t + 800 * t * t)
        value = .16 * math.sin(phase) + .075 * math.sin(2 * phase) + .035 * math.sin(3 * phase)
        if asset == 'intake':
            value = .08 * math.sin(phase * 2) + .06 * math.sin(phase * 5) + .04 * math.sin(phase * 7)
        if not is_loop:
            envelope = math.sin(math.pi * i / count) ** 2 * math.exp(-t * 10)
            value = (value + .12 * rng.uniform(-1, 1)) * envelope
        samples.extend(struct.pack('<h', round(max(-.35, min(.35, value)) * 32767)))
    with wave.open(str(root / (asset + '.wav')), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(samples)
