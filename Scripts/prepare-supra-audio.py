#!/usr/bin/env python3
"""Original 2JZ-inspired inline-six, turbo intake and pressure-release sound design.
No commercial recordings or sampled V8 waveform; not a verified stock Supra recording.
Requires NumPy for authoring only. App has no added dependency.
"""
import importlib.util
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('audio_tools', ROOT / 'Scripts/prepare-v8-audio.py')
a = importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
RATE = a.RATE
OUT = ROOT / 'VirtualV8/Audio/Supra_2JZ'


def noise(count, seed, low, high):
    return a.level(a.bandpass(np.random.default_rng(seed).normal(size=count), low, high), 1)


def exhaust(rpm, count, seed):
    # Six four-stroke cylinders: three evenly spaced combustion events per revolution.
    rng = np.random.default_rng(seed)
    impulses = np.zeros(count)
    firings = round(count / RATE * rpm / 60 * 3)
    strengths = [.99, 1.02, .98, 1.01, 1, .97]
    for i in range(firings):
        index = round((i + rng.normal(0, .002)) / firings * count) % count
        impulses[index] += strengths[i % 6] * (1 + rng.normal(0, .015))
    f = np.fft.rfftfreq(count, 1 / RATE)
    response = (1 / (1 + 1j * f / 2400) - .45 / (1 + 1j * f / 95))
    response *= 1 + .55 / (1 + 2j * (f / 210 - 210 / np.maximum(f, 1)))
    response *= 1 + .3 / (1 + 3j * (f / 620 - 620 / np.maximum(f, 1)))
    response *= (1 - .2 * np.exp(-2j * np.pi * f * .006)) / np.sqrt(1 + (f / 3800) ** 8)
    spectrum = np.fft.rfft(impulses) * response; spectrum[0] = 0
    return a.level(np.fft.irfft(spectrum, n=count), 1)


def save_loop(name, audio, target=.11):
    audio = a.finish(audio, target)
    edge = round(.003 * RATE); fade = np.sin(np.linspace(0, np.pi / 2, edge)) ** 2
    audio[:edge] *= fade; audio[-edge:] *= fade[::-1]
    audio -= audio.mean(); audio *= min(1, .32 / max(np.max(np.abs(audio)), 1e-9))
    a.write(OUT / (name + '.wav'), audio)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    specs = [('idle', 750), ('low_1500', 1500), ('low_2600', 2600),
             ('mid_3600', 3600), ('mid_4700', 4700), ('high_5700', 5700),
             ('high_6600', 6600), ('load', 3600), ('intake', 3600), ('overrun', 3600)]
    for index, (name, rpm) in enumerate(specs):
        count = round(round(6 * rpm / 120) * 120 / rpm * RATE)
        pulse = exhaust(rpm, count, 200 + index)
        mechanical = noise(count, 220 + index, 400, 5500)
        cycles = round(count / RATE * rpm / 60 * 3)
        phase = 2 * np.pi * cycles * np.arange(count) / count
        if name == 'intake':
            audio = .7 * noise(count, 230, 900, 6500) + .3 * np.sin(phase * 2)
        elif name == 'overrun':
            audio = .9 * a.bandpass(pulse, 45, 1700) + .1 * mechanical
        else:
            audio = .87 * pulse + .1 * mechanical + .03 * np.sin(phase * 2)
        save_loop(name, audio, .075 if name == 'intake' else .09 if name in ['load', 'overrun'] else .11)
    # Broadband compressor air plus non-harmonic shaft whistle, not engine firing tone.
    count = 6 * RATE; t = np.arange(count) / RATE
    shaft = .62 * np.sin(2 * np.pi * 2800 * t) + .25 * np.sin(2 * np.pi * 4100 * t)
    shaft *= 1 + .06 * np.sin(2 * np.pi * 3 * t)
    save_loop('turbo_spool', .55 * shaft + .45 * noise(count, 240, 1600, 8500), .085)
    for index, name in enumerate(['shift_up_1', 'shift_up_2', 'downshift']):
        count = round((.16 if index < 2 else .28) * RATE)
        pulse = exhaust(4700 if index < 2 else 3800, count, 250 + index)
        envelope = np.sin(np.linspace(0, np.pi, count)) ** .8
        a.write(OUT / (name + '.wav'), a.finish(pulse * envelope, .105, False))
    for index, duration in enumerate([.12, .17, .09]):
        count = round(duration * RATE); t = np.arange(count) / RATE
        rasp = noise(count, 260 + index, 600, 6500) * np.exp(-t * (40 + index * 7))
        thump = np.sin(2 * np.pi * (100 + index * 11) * t) * np.exp(-t * 36)
        a.write(OUT / f'pop_{index + 1}.wav', a.finish((.68 * rasp + .32 * thump) * (1 - np.exp(-t * 2200)), .075, False))
    count = round(.18 * RATE); t = np.arange(count) / RATE
    a.write(OUT / 'limiter.wav', a.finish(exhaust(6700, count, 270) * (.15 + .85 * (np.sin(2 * np.pi * 34 * t) > .2)), .095, False))
    for index, duration in enumerate([.42, .54]):
        count = round(duration * RATE); t = np.arange(count) / RATE
        # A quick valve opening, descending whistle and pressure-driven air decay.
        envelope = (1 - np.exp(-t * 550)) * np.exp(-t * (7 + index * 2))
        sweep_phase = 2 * np.pi * (4200 * t - 2400 * t ** 2)
        hiss = noise(count, 280 + index, 1200, 9500)
        audio = (.86 * hiss + .14 * np.sin(sweep_phase)) * envelope
        a.write(OUT / f'pressure_release_{index + 1}.wav', a.finish(audio, .105, False))
    (OUT / 'CREDITS.md').write_text('''# Toyota Supra Mk4 / 2JZ-inspired audio recreation

All 20 WAVs are original procedural sound design, authored by
Scripts/prepare-supra-audio.py. No third-party recording is embedded.
This is an inline-six / twin-turbo-inspired recreation, not a recording of a
verified 2JZ-GTE or a calibrated stock Supra exhaust/intake installation.
The even six-cylinder combustion train differs from the V8 banks. Turbo shaft
whistle, compressor noise and pressure-release sweeps are deliberately audible
for MVP evaluation; they do not replicate exact sequential turbo operation or
a specific aftermarket blow-off valve. The shared preparation helpers only
perform filtering, leveling and WAV writing; they do not read V8 recordings.
All loops are 48 kHz mono with smooth boundaries and 0.32 peak headroom.
''')
    print('Prepared 20 original Supra-inspired WAVs including turbo spool and two release variants.')

if __name__ == '__main__':
    main()
