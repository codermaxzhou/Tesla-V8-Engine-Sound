#!/usr/bin/env python3
"""Six original classic-car-inspired banks; no third-party recordings.
Engine layouts, harmonic balance, exhaust reflections and intake are distinct.
These are designed recreations, not verified manufacturer recordings.
NumPy is for authoring only. Existing banks are never rewritten.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('audio_tools', ROOT / 'Scripts/prepare-v8-audio.py')
a = importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
RATE = a.RATE
PROFILES = [
    dict(id='lexus-lfa', folder='Lexus_LFA', name='Lexus LFA V10', events=5,
         refs=[900,1800,3400,4800,6200,7600,8800], redline=9000,
         body=390, ring=1550, cutoff=7400, delay=.0018, clarity=.88, intake=.55, grit=.045, seed=100),
    dict(id='lamborghini-murcielago', folder='Lamborghini_Murcielago', name='Murcielago 6.2L V12', events=6,
         refs=[900,1600,2900,4100,5300,6400,7400], redline=7600,
         body=170, ring=720, cutoff=5600, delay=.0054, clarity=.68, intake=.22, grit=.08, seed=200),
    dict(id='porsche-996-gt3', folder='Porsche_996_GT3', name='Porsche 996 GT3 flat-six', events=3,
         refs=[850,1700,3000,4200,5500,6600,7600], redline=7800,
         body=245, ring=980, cutoff=5200, delay=.0041, clarity=.63, intake=.25, grit=.13, seed=300),
    dict(id='mazda-rx7-fd', folder='Mazda_RX7_FD', name='Mazda RX-7 FD two-rotor', events=2,
         refs=[850,1800,3100,4400,5600,6800,7800], redline=8000, turbo=True,
         body=320, ring=1250, cutoff=6500, delay=.001, clarity=.9, intake=.23, grit=.035, seed=400),
    dict(id='ferrari-f355', folder='Ferrari_F355', name='Ferrari F355 flat-plane V8', events=4,
         refs=[1000,1800,3200,4500,5900,7100,8300], redline=8500,
         body=420, ring=1800, cutoff=8000, delay=.0026, clarity=.92, intake=.35, grit=.06, seed=500),
    dict(id='porsche-carrera-gt', folder='Porsche_Carrera_GT', name='Porsche Carrera GT V10', events=5,
         refs=[900,1800,3100,4400,5800,7000,8200], redline=8400,
         body=290, ring=1100, cutoff=6500, delay=.0036, clarity=.7, intake=.38, grit=.105, seed=600),
]


def noise(count, seed, low, high):
    return a.level(a.bandpass(np.random.default_rng(seed).normal(size=count), low, high), 1)


def pressure(p, rpm, count, seed):
    rng = np.random.default_rng(seed)
    banks = [np.zeros(count), np.zeros(count)]
    firings = round(count / RATE * rpm / 60 * p['events'])
    for i in range(firings):
        index = round((i + rng.normal(0, .0015 if p['clarity'] > .8 else .003)) / firings * count) % count
        variation = 1 + .02 * np.sin(i * .73) + rng.normal(0, p['grit'] * .1)
        banks[i % 2][index] += variation
    f = np.fft.rfftfreq(count, 1 / RATE)
    response = 1 / (1 + 1j * f / (p['cutoff'] * .6)) - p['clarity'] * .65 / (1 + 1j * f / 110)
    for frequency, strength, damping in [(p['body'], .6, 2), (p['ring'], .4, 3.5)]:
        response *= 1 + strength / (1 + damping * 1j * (f / frequency - frequency / np.maximum(f, 1)))
    response /= np.sqrt(1 + (f / p['cutoff']) ** 8)
    paths = np.fft.rfft(banks[0]) * (1 - .18 * np.exp(-2j * np.pi * f * p['delay'] * 3))
    paths += np.fft.rfft(banks[1]) * ((.82 + .16 * p['clarity']) * np.exp(-2j * np.pi * f * p['delay'])
                                               - .13 * np.exp(-2j * np.pi * f * p['delay'] * 4))
    spectrum = paths * response; spectrum[0] = 0
    return a.level(np.fft.irfft(spectrum, n=count), 1)


def save_loop(root, name, audio, target):
    audio = a.finish(audio, target)
    edge = round(.003 * RATE); fade = np.sin(np.linspace(0, np.pi / 2, edge)) ** 2
    audio[:edge] *= fade; audio[-edge:] *= fade[::-1]
    audio -= audio.mean(); audio *= min(1, .32 / max(np.max(np.abs(audio)), 1e-9))
    a.write(root / (name + '.wav'), audio)


def prepare(p):
    root = ROOT / 'VirtualV8/Audio' / p['folder']; root.mkdir(parents=True, exist_ok=True)
    loop_names = ['idle','low_a','low_b','mid_a','mid_b','high_a','high_b','load','intake','overrun']
    refs = p['refs'] + [p['refs'][3]] * 3
    for index, (name, rpm) in enumerate(zip(loop_names, refs)):
        count = round(round(6 * rpm / 120) * 120 / rpm * RATE)
        pulse = pressure(p, rpm, count, p['seed'] + index)
        breath = noise(count, p['seed'] + 20 + index, 550, p['cutoff'])
        cycles = round(count / RATE * rpm / 60 * p['events'])
        phase = 2 * np.pi * cycles * np.arange(count) / count
        # Different layouts/pipe resonances plus induction orders produce independent banks.
        orders = np.sin(phase * 2) + .3 * np.sin(phase * 3)
        if name == 'intake':
            audio = (1 - p['intake']) * breath + p['intake'] * a.level(orders, 1)
        elif name == 'overrun':
            audio = .92 * a.bandpass(pulse, 45, 1900) + .08 * breath
        else:
            audio = (1 - p['grit']) * pulse + p['grit'] * breath
            audio += p['clarity'] * .08 * min(1, rpm / p['redline']) * orders
        if p['events'] == 2 and name == 'idle':
            # Mild rotary texture, without pretending to simulate a ported race engine.
            audio *= 1 + .055 * np.sin(2 * np.pi * 5 * np.arange(count) / RATE)
        save_loop(root, name, audio, .075 if name == 'intake' else .09 if name in ['load','overrun'] else .11)
    for index, name in enumerate(['shift_up_1','shift_up_2','downshift']):
        count = round((.16 if index < 2 else .28) * RATE)
        pulse = pressure(p, p['refs'][4 if index < 2 else 3], count, p['seed'] + 40 + index)
        envelope = np.sin(np.linspace(0, np.pi, count)) ** .75
        a.write(root / (name + '.wav'), a.finish(pulse * envelope, .105, False))
    for index, duration in enumerate([.12,.17,.095]):
        count = round(duration * RATE); t = np.arange(count) / RATE
        crack = noise(count, p['seed'] + 50 + index, 500, p['cutoff']) * np.exp(-t * (40 + index * 6))
        thump = np.sin(2 * np.pi * (p['body'] * .4 + index * 7) * t) * np.exp(-t * 33)
        a.write(root / f'pop_{index + 1}.wav', a.finish((.65 * crack + .35 * thump) * (1 - np.exp(-t * 2200)), .075, False))
    count = round(.18 * RATE); t = np.arange(count) / RATE
    cut = pressure(p, p['redline'] - 100, count, p['seed'] + 60)
    a.write(root / 'limiter.wav', a.finish(cut * (.15 + .85 * (np.sin(2 * np.pi * 35 * t) > .2)), .095, False))
    if p.get('turbo'):
        count = 6 * RATE; t = np.arange(count) / RATE
        shaft = .6 * np.sin(2 * np.pi * 3100 * t) + .2 * np.sin(2 * np.pi * 4650 * t)
        save_loop(root, 'turbo_spool', .55 * shaft + .45 * noise(count, p['seed'] + 70, 1800, 8500), .085)
        for index, duration in enumerate([.4,.52]):
            count = round(duration * RATE); t = np.arange(count) / RATE
            envelope = (1 - np.exp(-t * 600)) * np.exp(-t * (8 + index * 2))
            hiss = noise(count, p['seed'] + 80 + index, 1000, 9000)
            whistle = np.sin(2 * np.pi * (4500 * t - 2700 * t ** 2))
            a.write(root / f'pressure_release_{index + 1}.wav', a.finish((.85 * hiss + .15 * whistle) * envelope, .105, False))
    (root / 'design.json').write_text(json.dumps(p, indent=2) + '\n')
    (root / 'CREDITS.md').write_text(f'''# {p['name']} inspired audio recreation

All WAVs are original procedural sound design generated by
Scripts/prepare-classic-audio.py; no external recording is embedded.
This is not a verified recording of the named car, manufacturer-endorsed audio,
or a calibrated reproduction of its exact exhaust/intake or transient behavior.
Design parameters and reference RPMs are recorded in design.json. The synthesis
uses layout-specific firing-event timing, bank paths, pipe resonances, harmonic
balance and seeded broadband mechanical/air texture. Rotary timing follows
rotor events per eccentric-shaft revolution, not piston-cylinder counting.
All loops have smooth edges, removed DC, 48 kHz mono PCM and 0.32 peak headroom.
Replace these with properly licensed recordings for greater authenticity.
''')
    print(f"Prepared {p['name']}: {20 if p.get('turbo') else 17} WAVs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=[p['id'] for p in PROFILES])
    args = parser.parse_args()
    for profile in PROFILES:
        if args.profile is None or profile['id'] == args.profile: prepare(profile)

if __name__ == '__main__':
    main()
