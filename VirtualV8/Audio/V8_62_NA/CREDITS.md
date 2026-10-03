# V8 audio source credits

Retrieved 2026-10-03. Each creator's Freesound page identifies the recording as **Creative Commons 0 (CC0 1.0)**:
<https://creativecommons.org/publicdomain/zero/1.0/>.

| Source file | Recording / creator | Source page |
| --- | --- | --- |
| `348430-classic-v8-idle.mp3` | “Classic Car Idle.wav” — jackthemurray; described as a 350 Rocket V8 in a garage | https://freesound.org/people/jackthemurray/sounds/348430/ |
| `651534-v8-rev.mp3` | “v8 engine rev.wav” — overmedium; throaty V8 throttle blips, vehicle unspecified | https://freesound.org/people/overmedium/sounds/651534/ |
| `360451-corvette-c5.mp3` | “Corvette C5 INOX 2001.flac” — Galarne; recorded 2001 Corvette C5 | https://freesound.org/people/Galarne/sounds/360451/ |

These are the publicly provided HQ **MP3 previews**, not the creators' original lossless WAV/FLAC downloads. No login-protected original was retrieved. `sources.json` records public download URLs and SHA-256 hashes. Raw files stay outside the application bundle; only processed WAVs plus their credits ship in `Audio/V8_62_NA`.

## Processing / derivatives

`Scripts/prepare-v8-audio.py` converts to 48 kHz mono, selects engine sections, filters unwanted low-frequency source pitch/background energy, stitches overlapping grains, and adds original two-bank RPM-timed pressure pulses and damped exhaust reflections. It levels/saturates gently, removes loop DC offset, and preserves 0.32 peak headroom. Prepared continuous loops are approximately six seconds with circular overlap/add and whole four-stroke cycles. The preparation script lists exact source time ranges.

- `idle`: Corvette section 14.0–16.5 s plus classic idle 15.0–22.0 s and a modest original pulse component.
- Low/mid/high RPM: progressively selected Corvette idle/rev/pass-by sections (14.0–16.5, 19.6–21.2, 34.8–36.0 and 49.8–50.65 s), shaped as textures over RPM-correct pressure pulses. Recorded low harmonics are filtered to avoid changing source RPM fighting the virtual engine.
- `load`, `intake`: filtered texture from overmedium 2.25–3.7 s; intake is a designed layer, not a dedicated intake-microphone recording.
- `overrun`: filtered Corvette idle texture with quieter designed pressure pulses; not a measured off-throttle dyno sample.
- Shift/rev-match events: overmedium sections 3.85–4.06, 4.15–4.34 and 2.18–2.50 s with event envelopes. These are designed transition effects, not recordings of a specific automatic gearbox.
- Pops: recorded rev texture shaped into short decaying exhaust pops with original low-frequency pressure thumps.
- Limiter: original timed pressure pulses gated into a short ignition-cut effect.

This is a **hybrid recorded/procedural V8** sound set. The virtual profile remains American 6.2L NA V8, but this is not a verified recording of that exact engine or calibrated steady-RPM dyno sampling. Source RPM values are unavailable. The prepared WAV reference RPMs describe their designed pulse timing.

The previous sine-wave generator is retained only for explicitly regenerating synthetic placeholders. Runtime missing-file fallbacks also remain synthetic and independent of these third-party recordings.
