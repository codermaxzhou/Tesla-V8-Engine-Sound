#!/usr/bin/env python3
"""Author an S65-inspired hybrid bank, not an authentic BMW dyno recording.
Reuses credited CC0 V8 textures plus original higher-rev two-bank pressure,
induction harmonics and shorter exhaust resonances. No iOS runtime dependency.
"""
import importlib.util
import json
import hashlib
import tempfile
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('v8_authoring', ROOT / 'Scripts/prepare-v8-audio.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)
RATE = a.RATE
OUT = ROOT / 'VirtualV8/Audio/BMW_S65'


def pressure(rpm, count, seed):
    rng = np.random.default_rng(seed)
    banks = [np.zeros(count), np.zeros(count)]
    # Uneven cross-plane bank spacing; manifold geometry is deliberately approximate.
    order = [0, 1, 0, 1, 1, 0, 1, 0]
    firings = round(count / RATE * rpm / 60 * 4)
    for firing in range(firings):
        index = round((firing + rng.normal(0, .003)) / firings * count) % count
        banks[order[firing % 8]][index] += 1 + rng.normal(0, .02)
    f = np.fft.rfftfreq(count, 1 / RATE)
    response = (1 / (1 + 1j * f / 3600) - .7 / (1 + 1j * f / 180))
    response *= 1 + .45 / (1 + 2j * (f / 280 - 280 / np.maximum(f, 1)))
    response *= 1 + .35 / (1 + 3j * (f / 720 - 720 / np.maximum(f, 1)))
    response /= np.sqrt(1 + (f / 5600) ** 8)
    paths = np.fft.rfft(banks[0]) * (1 - .18 * np.exp(-2j * np.pi * f * .0051))
    paths += np.fft.rfft(banks[1]) * (.94 * np.exp(-2j * np.pi * f * .0012)
                                                - .15 * np.exp(-2j * np.pi * f * .0067))
    spectrum = paths * response
    spectrum[0] = 0
    return np.fft.irfft(spectrum, n=count)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sources = json.loads((a.SOURCES / 'sources.json').read_text())
    decoded = {}
    with tempfile.TemporaryDirectory(prefix='VirtualV8S65-') as temporary:
        for source in sources['sources']:
            path = a.SOURCES / source['file']
            assert hashlib.sha256(path.read_bytes()).hexdigest() == source['sha256']
            decoded[source['id']] = a.decode(path, Path(temporary))
    texture_source = a.section(decoded['v8-rev'], 2.25, 3.7)
    idle_source = a.section(decoded['corvette'], 14, 16.5)
    specs = [('idle', 800), ('low_1800', 1800), ('low_3200', 3200),
             ('mid_4500', 4500), ('mid_5800', 5800), ('high_7000', 7000),
             ('high_8200', 8200), ('load', 4500), ('intake', 4500), ('overrun', 4500)]
    for index, (name, rpm) in enumerate(specs):
        count = round(round(6 * rpm / 120) * 120 / rpm * RATE)
        pulse = a.level(pressure(rpm, count, 650 + index), 1)
        grain = a.texture(idle_source if name == 'idle' else texture_source, count, 6500 + index)
        grain = a.level(a.bandpass(grain, max(250, rpm / 60 * 5), 6500), 1)
        # Integer engine cycles keep the induction orders continuous at the loop seam.
        cycles = round(count / RATE * rpm / 60 * 4)
        phase = 2 * np.pi * cycles * np.arange(count) / count
        induction = np.sin(phase * 2) + .35 * np.sin(phase * 4)
        if name == 'intake':
            audio = .65 * grain + .35 * a.level(induction, 1)
        elif name == 'overrun':
            audio = .8 * a.bandpass(pulse, 80, 2000) + .2 * grain
        elif name == 'idle':
            audio = .65 * pulse + .35 * a.level(a.bandpass(grain, 200, 2400), 1)
        else:
            brightness = min(1, rpm / 8400)
            audio = .75 * pulse + .25 * grain + .12 * brightness * induction
        target = .075 if name == 'intake' else .09 if name in ['load', 'overrun'] else .11
        loop = a.finish(audio, target)
        # A very short raised-cosine edge makes even bright induction loops click-free.
        edge = round(.003 * RATE)
        fade = np.sin(np.linspace(0, np.pi / 2, edge)) ** 2
        loop[:edge] *= fade; loop[-edge:] *= fade[::-1]
        loop -= loop.mean()
        loop *= min(1, .32 / max(np.max(np.abs(loop)), 1e-9))
        a.write(OUT / (name + '.wav'), loop)
    for index, name in enumerate(['shift_up_1', 'shift_up_2', 'downshift']):
        count = round((.16 if index < 2 else .28) * RATE)
        t = np.arange(count) / RATE
        rpm = 6200 if index < 2 else 4800
        pulse = pressure(rpm, count, 700 + index)
        grain = a.texture(texture_source, count, 710 + index, .06)
        envelope = np.sin(np.linspace(0, np.pi, count)) ** .8
        a.write(OUT / (name + '.wav'), a.finish((.8 * a.level(pulse, 1) + .2 * a.level(grain, 1)) * envelope, .105, False))
    for index, duration in enumerate([.12, .17, .09]):
        count = round(duration * RATE); t = np.arange(count) / RATE
        noise = a.texture(texture_source, count, 720 + index, .06)
        rasp = a.level(a.bandpass(noise, 700, 7000), 1) * np.exp(-t * (40 + index * 7))
        thump = np.sin(2 * np.pi * (110 + index * 13) * t) * np.exp(-t * 35)
        a.write(OUT / f'pop_{index + 1}.wav', a.finish((.7 * rasp + .3 * thump) * (1 - np.exp(-t * 2200)), .075, False))
    count = round(.18 * RATE); t = np.arange(count) / RATE
    cut = pressure(8300, count, 740) * (.15 + .85 * (np.sin(2 * np.pi * 38 * t) > .2))
    a.write(OUT / 'limiter.wav', a.finish(cut, .095, False))
    credits = (ROOT / 'VirtualV8/Audio/V8_62_NA/CREDITS.md').read_text()
    (OUT / 'CREDITS.md').write_text('''# S65-inspired sound recreation

These are designed BMW S65-inspired sounds, not recordings of a verified BMW M3.
Original higher-rev bank pressure, induction harmonics and exhaust reflections
are blended with filtered generic CC0 V8 textures. See Scripts/prepare-s65-audio.py
for the exact construction. Idle/limiter values are MVP approximations; the
8,400 RPM redline follows BMW's S65 technical specifications. The sound bank
can be replaced later by licensed, RPM-labeled S65 recordings.

The following credits identify the generic texture sources; the American bank
processing description below is retained for provenance, not this bank's recipe.

''' + credits)
    print('Prepared 17 S65-inspired 48 kHz mono WAVs, peak <= 0.32.')

if __name__ == '__main__':
    main()
