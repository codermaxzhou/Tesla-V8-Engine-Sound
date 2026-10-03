#!/usr/bin/env python3
"""Build recorded/procedural V8 loops from credited CC0 preview sources.

Authoring tool only: requires Python + NumPy and macOS afconvert. The iOS app has
no added dependency. Sources and exact provenance are in AudioSources/V8/.
This is hybrid sound design, not a calibrated dyno recording of a 6.2L engine.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RATE = 48000
SOURCES = ROOT / 'AudioSources' / 'V8'
DEFAULT_OUTPUT = ROOT / 'VirtualV8' / 'Audio' / 'V8_62_NA'


def decode(path, temporary):
    wav = temporary / (path.stem + '.wav')
    subprocess.run(['/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEI16@48000',
                    str(path), str(wav)], check=True)
    with wave.open(str(wav)) as reader:
        pcm = np.frombuffer(reader.readframes(reader.getnframes()), '<i2').astype(np.float64)
        return pcm.reshape(-1, reader.getnchannels()).mean(axis=1) / 32768


def section(source, start, end):
    result = source[round(start * RATE):round(end * RATE)].copy()
    if len(result) < round((end - start) * RATE) - 1:
        raise ValueError('Source is truncated; do not build from a partial download')
    return result - result.mean()


def bandpass(audio, low, high):
    # Circular frequency filtering keeps the loop seam as smooth as its interior.
    f = np.fft.rfftfreq(len(audio), 1 / RATE)
    high_pass = (f / max(low, 1)) ** 4 / (1 + (f / max(low, 1)) ** 4)
    low_pass = 1 / np.sqrt(1 + (f / high) ** 8)
    return np.fft.irfft(np.fft.rfft(audio) * high_pass * low_pass, n=len(audio))


def rms(audio):
    return float(np.sqrt(np.mean(audio * audio)))


def level(audio, target):
    return audio * target / max(rms(audio), 1e-9)


def texture(source, count, seed, grain_seconds=0.18):
    """Circular overlap-add of recorded grains: no speech-length repeated rev sweeps."""
    rng = np.random.default_rng(seed)
    grain = round(grain_seconds * RATE)
    if len(source) <= grain:
        raise ValueError('Source segment too short')
    window = np.hanning(grain)
    output, weights = np.zeros(count), np.zeros(count)
    hop = grain // 3
    for position in range(0, count, hop):
        start = int(rng.integers(0, len(source) - grain))
        sample = source[start:start + grain].copy()
        # Limit field-recording amplitude changes so loops do not pump/pass by.
        sample = level(sample, 1)
        indices = (position + np.arange(grain)) % count
        np.add.at(output, indices, sample * window)
        np.add.at(weights, indices, window)
    return output / np.maximum(weights, 1e-9)


def pressure(rpm, count, seed, brightness):
    """Cross-plane two-bank firing train with unequal manifold paths and cylinder energy."""
    rng = np.random.default_rng(seed)
    bank_a, bank_b = np.zeros(count), np.zeros(count)
    # A four-stroke V8 fires eight times per 720 degrees. This odd/even-bank order
    # creates the uneven individual-bank spacing responsible for the V8 burble.
    firing_order = [1, 8, 7, 2, 6, 5, 4, 3]
    pulse_count = round(count / RATE * rpm / 60 * 4)
    cylinder_strength = [.99, .92, 1.04, .97, .94, 1.03, .96, 1.01]
    for firing in range(pulse_count):
        cylinder = firing_order[firing % 8]
        bank = bank_a if cylinder % 2 else bank_b
        cycle = firing // 8
        irregularity = 0.008 if rpm < 1200 else 0.002
        position = (firing / pulse_count + rng.normal(0, irregularity) / pulse_count) * count
        index = int(round(position)) % count
        variation = 1 + .045 * np.sin(cycle * .71) + rng.normal(0, .018)
        bank[index] += cylinder_strength[cylinder - 1] * variation
    f = np.fft.rfftfreq(count, 1 / RATE)
    # Pressure rise/blowdown, resonant pipe body and damped reflected waves.
    pulse = (1 / (1 + 1j * f / 1700) - .55 / (1 + 1j * f / 110))
    resonances = 1 + .65 / (1 + 1j * (f / 145 - 145 / np.maximum(f, 1)))
    resonances += .38 / (1 + 1j * (f / 360 - 360 / np.maximum(f, 1)))
    cutoff = 950 + brightness * 1700
    response = pulse * resonances / np.sqrt(1 + (f / cutoff) ** 6)
    paths_a = np.exp(-2j * np.pi * f * .0031) - .24 * np.exp(-2j * np.pi * f * .0107)
    paths_b = .82 * np.exp(-2j * np.pi * f * .0053) - .2 * np.exp(-2j * np.pi * f * .0141)
    spectrum = (np.fft.rfft(bank_a) * paths_a + np.fft.rfft(bank_b) * paths_b) * response
    spectrum[0] = 0
    return np.fft.irfft(spectrum, n=count)


def finish(audio, target=0.11, loop=True):
    audio = level(audio - audio.mean(), target)
    # Gentle saturator produces broad combustion harmonics, then preserves headroom.
    audio = .32 * np.tanh(audio / .32)
    if loop:
        audio -= audio.mean()
    audio *= min(1, .32 / max(np.max(np.abs(audio)), 1e-9))
    if not loop:
        edge = min(round(.005 * RATE), len(audio) // 2)
        fade = np.sin(np.linspace(0, np.pi / 2, edge)) ** 2
        audio[:edge] *= fade
        audio[-edge:] *= fade[::-1]
    return audio


def write(path, audio):
    pcm = np.round(np.clip(audio, -.32, .32) * 32767).astype('<i2')
    with wave.open(str(path), 'wb') as writer:
        writer.setnchannels(1); writer.setsampwidth(2); writer.setframerate(RATE)
        writer.writeframes(pcm.tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((SOURCES / 'sources.json').read_text())
    with tempfile.TemporaryDirectory(prefix='VirtualV8Authoring-') as temporary:
        decoded = {}
        for source in manifest['sources']:
            path = SOURCES / source['file']
            if hashlib.sha256(path.read_bytes()).hexdigest() != source['sha256']:
                raise ValueError('Source checksum mismatch: ' + path.name)
            decoded[source['id']] = decode(path, Path(temporary))
    idle = section(decoded['classic-idle'], 15.0, 22.0)
    c5_idle = section(decoded['corvette'], 14.0, 16.5)
    c5_low = section(decoded['corvette'], 19.6, 21.2)
    c5_mid = section(decoded['corvette'], 34.8, 36.0)
    c5_high = section(decoded['corvette'], 49.8, 50.65)
    rev = section(decoded['v8-rev'], 2.25, 3.7)
    loop_specs = [
        ('idle', 750, c5_idle, .12), ('low_1500', 1500, c5_idle, .22),
        ('low_2500', 2500, c5_low, .4), ('mid_3500', 3500, c5_low, .58),
        ('mid_4500', 4500, c5_mid, .72), ('high_5500', 5500, c5_high, .88),
        ('high_6500', 6500, c5_high, 1), ('load', 3500, rev, .8),
        ('intake', 3500, rev, .7), ('overrun', 3500, c5_idle, .2)]
    for index, (name, rpm, source, brightness) in enumerate(loop_specs):
        # Whole 720-degree cycles align the firing sequence at the loop boundary.
        cycles = round(6 * rpm / 120)
        count = round(cycles * 120 / rpm * RATE)
        timed = level(pressure(rpm, count, 62 + index, brightness), 1)
        recorded = texture(source, count, 620 + index)
        if name == 'idle':
            # Keep natural combustion irregularity and mechanical texture at idle.
            recorded = bandpass(recorded, 35, 1800)
            mechanical = bandpass(texture(idle, count, 710), 250, 2400)
            audio = .6 * level(recorded, 1) + .32 * timed + .08 * level(mechanical, 1)
        elif name == 'intake':
            audio = bandpass(recorded, 550, 4500) + .12 * bandpass(timed, 500, 3500)
        elif name == 'load':
            audio = .65 * timed + .65 * level(bandpass(recorded, 180, 3300), 1)
        elif name == 'overrun':
            audio = .75 * bandpass(timed, 35, 1100) + .25 * level(bandpass(recorded, 250, 1500), 1)
        else:
            # Recorded exhaust rasp rides the RPM-correct bank pulses. Removing low
            # source harmonics avoids a field recording's changing pitch fighting RPM.
            audio = .67 * timed + .43 * level(bandpass(recorded, max(160, rpm / 60 * 4 * 1.3),
                                                     1700 + brightness * 2200), 1)
        target = .075 if name == 'intake' else .09 if name in ['overrun', 'load'] else .11
        write(args.output / (name + '.wav'), finish(audio, target))
    # Real throttle-blip texture for transitions, with short non-looping envelopes.
    for name, start, end in [('shift_up_1', 3.85, 4.06), ('shift_up_2', 4.15, 4.34),
                             ('downshift', 2.18, 2.50)]:
        sample = section(decoded['v8-rev'], start, end)
        sample = bandpass(sample, 90, 3500)
        envelope = np.sin(np.linspace(0, np.pi, len(sample))) ** .7
        write(args.output / (name + '.wav'), finish(sample * envelope, .105, False))
    for index in range(3):
        duration = [.135, .18, .105][index]
        count = round(duration * RATE); time = np.arange(count) / RATE
        noise = texture(rev, count, 850 + index, .06)
        rasp = level(bandpass(noise, 500, 5500), 1) * np.exp(-time * (42 + index * 6))
        thump = np.sin(2 * np.pi * (88 - index * 7) * time) * np.exp(-time * 33)
        envelope = 1 - np.exp(-time * 2200)
        write(args.output / ('pop_' + str(index + 1) + '.wav'),
              finish((.55 * rasp + .45 * thump) * envelope, .075, False))
    count = round(.18 * RATE); time = np.arange(count) / RATE
    cut = level(pressure(6500, count, 911, 1), 1)
    envelope = .18 + .82 * (np.sin(2 * np.pi * 32 * time) > .2)
    write(args.output / 'limiter.wav', finish(cut * envelope, .095, False))
    print('Prepared 17 hybrid V8 WAV assets at 48 kHz mono; peak <= 0.32.')


if __name__ == '__main__':
    main()
