#!/usr/bin/env python3
"""AMG GT R-inspired hybrid cross-plane V8 bank, not an authentic M178 recording.
Original pressure, intake and turbo design plus credited generic CC0 V8 texture.
NumPy/afconvert are authoring tools only; the app has no added dependency.
"""
import importlib.util
import json
import hashlib
import tempfile
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('audio_tools', ROOT / 'Scripts/prepare-v8-audio.py')
a = importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
RATE = a.RATE
OUT = ROOT / 'VirtualV8/Audio/AMG_GTR'


def noise(count, seed, low, high):
    return a.level(a.bandpass(np.random.default_rng(seed).normal(size=count), low, high), 1)


def exhaust(rpm, count, seed):
    rng = np.random.default_rng(seed)
    banks = [np.zeros(count), np.zeros(count)]
    order = [0, 1, 1, 0, 1, 0, 0, 1]
    firings = round(count / RATE * rpm / 60 * 4)
    strength = [1.04, .94, 1.02, .97, 1.01, .96, 1.03, .98]
    for i in range(firings):
        index = round((i + rng.normal(0, .004)) / firings * count) % count
        banks[order[i % 8]][index] += strength[i % 8] * (1 + rng.normal(0, .025))
    f = np.fft.rfftfreq(count, 1 / RATE)
    response = 1 / (1 + 1j * f / 2800) - .45 / (1 + 1j * f / 75)
    response *= 1 + .9 / (1 + 1.8j * (f / 135 - 135 / np.maximum(f, 1)))
    response *= 1 + .45 / (1 + 2.5j * (f / 340 - 340 / np.maximum(f, 1)))
    response /= np.sqrt(1 + (f / 3700) ** 8)
    paths = np.fft.rfft(banks[0]) * (1 - .25 * np.exp(-2j * np.pi * f * .012))
    paths += np.fft.rfft(banks[1]) * (.9 * np.exp(-2j * np.pi * f * .004)
                                               - .2 * np.exp(-2j * np.pi * f * .016))
    spectrum = paths * response; spectrum[0] = 0
    return a.level(np.fft.irfft(spectrum, n=count), 1)


def save_loop(name, audio, target=.11):
    audio = a.finish(audio, target)
    edge = round(.003 * RATE); fade = np.sin(np.linspace(0, np.pi / 2, edge)) ** 2
    audio[:edge] *= fade; audio[-edge:] *= fade[::-1]
    audio -= audio.mean(); audio *= min(1, .32 / max(np.max(np.abs(audio)), 1e-9))
    a.write(OUT / (name + '.wav'), audio)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((a.SOURCES / 'sources.json').read_text())
    source = next(item for item in manifest['sources'] if item['id'] == 'v8-rev')
    path = a.SOURCES / source['file']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == source['sha256']
    with tempfile.TemporaryDirectory(prefix='VirtualV8AMG-') as temporary:
        recorded = a.section(a.decode(path, Path(temporary)), 2.25, 3.7)
    specs = [('idle', 750), ('low_1500', 1500), ('low_2500', 2500),
             ('mid_3500', 3500), ('mid_4500', 4500), ('high_5500', 5500),
             ('high_6500', 6500), ('load', 3500), ('intake', 3500), ('overrun', 3500)]
    for index, (name, rpm) in enumerate(specs):
        count = round(round(6 * rpm / 120) * 120 / rpm * RATE)
        pulse = exhaust(rpm, count, 178 + index)
        rasp = a.texture(recorded, count, 1780 + index)
        rasp = a.level(a.bandpass(rasp, max(350, rpm / 60 * 5), 5000), 1)
        if name == 'intake':
            audio = .7 * noise(count, 300, 650, 4500) + .3 * a.bandpass(pulse, 600, 3500)
        elif name == 'overrun':
            audio = .9 * a.bandpass(pulse, 40, 1300) + .1 * rasp
        elif name == 'load':
            audio = .72 * pulse + .28 * rasp
        else:
            audio = .82 * pulse + .18 * rasp
        save_loop(name, audio, .07 if name == 'intake' else .09 if name in ['load', 'overrun'] else .11)
    count = 6 * RATE; t = np.arange(count) / RATE
    shaft = .6 * np.sin(2 * np.pi * 2150 * t) + .2 * np.sin(2 * np.pi * 3350 * t)
    save_loop('turbo_spool', .45 * shaft + .55 * noise(count, 310, 1000, 6500), .065)
    for index, name in enumerate(['shift_up_1', 'shift_up_2', 'downshift']):
        count = round((.18 if index < 2 else .3) * RATE)
        pulse = exhaust(5400 if index < 2 else 4100, count, 320 + index)
        rasp = a.texture(recorded, count, 330 + index, .06)
        envelope = np.sin(np.linspace(0, np.pi, count)) ** .65
        a.write(OUT / (name + '.wav'), a.finish((.75 * pulse + .25 * a.level(rasp, 1)) * envelope, .105, False))
    for index, duration in enumerate([.14, .19, .11]):
        count = round(duration * RATE); t = np.arange(count) / RATE
        crack = noise(count, 340 + index, 400, 5200) * np.exp(-t * (37 + index * 6))
        thump = np.sin(2 * np.pi * (78 + index * 8) * t) * np.exp(-t * 30)
        a.write(OUT / f'pop_{index + 1}.wav', a.finish((.5 * crack + .5 * thump) * (1 - np.exp(-t * 2200)), .085, False))
    count = round(.18 * RATE); t = np.arange(count) / RATE
    a.write(OUT / 'limiter.wav', a.finish(exhaust(6900, count, 350) * (.15 + .85 * (np.sin(2 * np.pi * 31 * t) > .2)), .095, False))
    for index, duration in enumerate([.35, .44]):
        count = round(duration * RATE); t = np.arange(count) / RATE
        envelope = (1 - np.exp(-t * 600)) * np.exp(-t * (9 + index * 2))
        hiss = noise(count, 360 + index, 850, 6500)
        whistle = np.sin(2 * np.pi * (3200 * t - 1900 * t ** 2))
        a.write(OUT / f'pressure_release_{index + 1}.wav', a.finish((.9 * hiss + .1 * whistle) * envelope, .075, False))
    (OUT / 'CREDITS.md').write_text('''# AMG GT R-inspired audio recreation

Original cross-plane V8 pressure pulses, manifold reflections, intake/turbo
noise, release events and exhaust pops are blended with filtered generic V8
texture. This is a sound recreation, not a recording of a verified AMG GT R,
a calibrated M178 engine, or an exact stock exhaust/recirculation-valve system.

Texture source: "v8 engine rev.wav" by overmedium (vehicle unspecified),
https://freesound.org/people/overmedium/sounds/651534/ — CC0 1.0,
https://creativecommons.org/publicdomain/zero/1.0/ . The already-credited public
HQ MP3 preview in AudioSources/V8 is used at 2.25–3.7 seconds. Its SHA-256 is
checked against AudioSources/V8/sources.json. No additional recording is used.

Scripts/prepare-amg-audio.py records the exact processing. The bank contains
20 replaceable 48 kHz mono WAVs, smooth loop boundaries, and 0.32 peak headroom.
''')
    print('Prepared 20 AMG GT R-inspired WAVs with cross-plane exhaust, turbo and release layers.')

if __name__ == '__main__':
    main()
