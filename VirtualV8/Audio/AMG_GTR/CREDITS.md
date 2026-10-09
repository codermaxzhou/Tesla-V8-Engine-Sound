# AMG GT R-inspired audio recreation

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
