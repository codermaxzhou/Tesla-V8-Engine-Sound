Hybrid recorded/procedural V8 assets prepared by Scripts/prepare-v8-audio.py.
CC0 V8 source recordings, creator credits, processing and limitations: CREDITS.md.
Raw source previews and checksums: AudioSources/V8/ (not bundled in the app).
48 kHz mono 16-bit PCM WAV; six-second continuous loops, peak <= 0.32.
The pulse timing follows the reference RPM. This is not calibrated lossless dyno
sampling of an exact American 6.2L engine. Keep filenames when replacing samples.
Reference RPMs: idle=750; low=1500/2500; mid=3500/4500; high=5500/6500;
load/intake/overrun=3500. Short shift/blip/pop/limiter assets are designed effects.
Scripts/generate-placeholder-audio.py is the older all-synthetic alternative;
running it overwrites these WAVs with placeholders. Missing-file runtime fallback
remains synthetic. The application has no new third-party dependency.
