# Virtual V8 — Hardened MVP

Virtual V8 turns vehicle speed and approximate pedal behavior into a virtual naturally aspirated V8 soundtrack and an eight-speed automatic driving display. This dependency-free SwiftUI iOS 17+ MVP works indoors in Simulation and with foreground phone sensors in Real Drive. It is a sound experience, not a vehicle-control or instrumentation system.

The final hardening pass preserves the existing drivetrain, audio layers, tuning, scenarios and CSV logging. It adds source-independent vehicle input providers, diagnostics, bounded audio latency compensation, strict concurrency checks and lifecycle recovery. There is no Tesla CAN access, account, backend, microphone use or route recording.

## Run

1. Open `VirtualV8.xcodeproj` in Xcode 15 or newer.
2. Select the shared **VirtualV8** scheme and an installed iPhone/iPad simulator.
3. Run. For a physical device, choose your development team under Signing & Capabilities.
4. Open **Simulation Mode** from the main screen.

Simulation needs no permissions. Real Drive asks for When In Use location access after the in-app explanation and starts device-motion updates only after **Enable Real Drive Sensors**. No account, backend, route recording, or application network requests are used.

## Controls

- **Engine Profile:** ten selectable profiles: the original American V8, BMW M3 S65, Supra 2JZ and AMG GT R, plus LFA, Murciélago, 996 GT3, RX-7 FD, F355 and Carrera GT. Stop the engine to change profile; selection persists. Branded sounds are labeled as recreations.
- **Driving Mode:** Comfort, Sport, and Track alter pedal response and automatic shift strategy.
- **Start Engine:** enters a short starting state, then idle. Starting an already running engine has no effect.
- **Stop Engine:** cancels the demo and resets RPM and gear. Simulation also resets manual inputs and speed; Real Drive keeps measuring actual vehicle speed while sound is off.
- **Accelerator:** 0–1, directly updates `estimatedThrottle`, the displayed throttle percentage, and smoothed engine response and load.
- **Brake:** 0–1, updates brake telemetry and engine load. Manual speed remains explicitly controlled by the speed slider; speed remains a simulation input rather than a full vehicle dynamics model.
- **Speed:** 0–250 km/h, updates the dashboard immediately and drives wheel-speed RPM and automatic gear decisions.
- **Automatic Demo:** runs for 42 seconds: start → idle → first-gear acceleration to 160 km/h with multiple upshifts → high RPM operation → throttle lift/overrun → braking with multiple downshifts and rev matching → stop → idle at 750 RPM. It uses the selected driving mode and the same drivetrain as manual control. The engine remains running at idle when the demo finishes.
- Moving any simulation input slider cancels the demo. Audio tuning sliders do not cancel it. The demo can also be cancelled with its button; engine stop cancels it immediately. Starting another demo resets it to the beginning.

**Driving Screen** shows only the large SwiftUI tachometer, speed, RPM, gear, estimated throttle and engine operating mode. Real Drive displays **Configure engine parameters while parked.**; advanced tuning is on **Developer / Calibration**, and calibration controls/navigation are disabled when the estimator reports movement. **Developer / Calibration** shows raw inputs, acceleration, current/target RPM, smoothed throttle, load, current/target gear, operating mode, shift type/progress, limiter status, vehicle state, current audio gains, audio engine status, fallback sample count, player starts, transient count, and recent events. All screens share the same controller. Opening Simulation controls explicitly selects Simulation and stops sensors. Navigation within the current input mode preserves engine/demo state; switching input modes clears the previous input state while keeping the engine running if already started.

## Architecture

```text
VirtualV8/
  App/           App entry point and shared controller lifetime
  Models/        VehicleState and selectable EngineProfile definitions
  Input/         VehicleInputProvider, SimulationInputProvider, PhoneSensorInputProvider
  Engine/        VirtualEngine, EngineState, and EngineOperatingMode
  Transmission/  VirtualTransmission, TransmissionState, and ShiftType
  Audio/         EngineAudioEngine, latency predictor, mixer, sample bank, backfire logic, WAV assets
  Simulation/    SimulationController, original DemoSequence, six deterministic scenario fixtures
  Sensors/       Core Location/Motion adapters, samples, estimator, sensor coordinator
  Views/         Navigation, dashboard, tachometer, diagnostics, sensor status, input/audio tuning
  Settings/      DrivingMode, bounded calibration/presets, UserDefaults persistence
  Logging/       DriveLogger, bounded CSV samples/history, timestamped events
VirtualV8Tests/   Engine, transmission, audio, sensors, calibration, persistence, logging, and scenarios
Scripts/         Shared test runner, reproducible V8 preparation and offline preview tools
```

`SimulationController` is a main-actor `@Observable` object owning published vehicle, engine, and transmission state. It coordinates two plain Swift models, `VirtualTransmission` and `VirtualEngine`. Views observe that state and send input actions; they contain no simulation algorithms.

### Dependency boundaries

| Layer | Responsibility and dependencies |
| --- | --- |
| Sensor Input | `LocationManager` and `MotionManager` translate Apple hardware callbacks into timestamped value samples. They know no powertrain, audio or UI logic. |
| Vehicle State Estimation | `VehicleStateEstimator` consumes those values and produces `VehicleState`; it is pure Swift and has no sensor-framework dependency. |
| Input Providers | `VehicleInputProvider` exposes state and lifecycle/update hooks. `SimulationInputProvider` handles manual/scenario inputs and derivatives; `PhoneSensorInputProvider` adapts the existing sensor coordinator/estimator. |
| Transmission | `VirtualTransmission` uses vehicle/engine state, driving mode and profile; it owns ratios, shift decisions and timed transitions without UI or sensor/audio frameworks. |
| Engine | `VirtualEngine` uses vehicle input and transmission ratio/shift information; it knows no input source, UI, logger or audio engine. |
| Audio | `AudioMixModel`/`BackfireController` calculate weights/events from value state. `EngineAudioEngine` owns AVFoundation output. Audio never feeds prediction back into the drivetrain. |
| Logging | `DriveLogger` receives value snapshots/events after an update. It owns bounded samples and CSV formatting, without sensor or powertrain ownership. |
| UI | SwiftUI observes published state and sends controller actions. Simulation/estimation algorithms stay outside Views. |

Only `SimulationController` composes these layers. Its per-step powertrain pipeline calls the selected `VehicleInputProvider` through the protocol; it contains no source-specific acceleration calculation. Sensor lifecycle/permission requests stay behind the phone provider. The `sensors` property is a read/tuning diagnostics facade retaining the existing UI, not a second acquisition controller. Selecting Real Drive alone does not request access; **Enable Real Drive Sensors** starts its provider explicitly. An injected provider can replay validated vehicle values without hardware.

All mutable coordination, sensor state, audio graph mutation, settings, logging and UI publishing are `@MainActor`. Location delegates copy value samples before hopping to that actor; motion callbacks deliver directly from the main operation queue. Motion acquisition generations reject callbacks from a stopped/restarted session. Location managers are detached/disposed on stop, and callbacks are checked against the active manager identity. Sensor access is owned by one coordinator. AVAudioSession activation/deactivation runs on one serial background queue with generations guarding stale completions; audio render threads consume AVFoundation buffers and never mutate application state. Notification registrations use immutable token owners for safe cleanup. Complete Swift concurrency diagnostics are enabled in the project.

A cancellable timer supplies elapsed time to an accumulator. The controller always processes fixed 1/60-second steps: selected input (manual/demo or sensors → estimator) → transmission decision → engine update → backfire/audio control update → state publishing → SwiftUI. Large render frames are subdivided rather than changing physics behavior. Live elapsed time is capped at 0.2 seconds. Backgrounding freezes simulation/scenarios and clears the accumulator; foregrounding resumes from the paused point without catching up elapsed suspension time. Tests disable the timer and exercise the exact same loop with different frame durations. Events remain in memory, capped at 200 entries. Drive logging samples at 5 Hz; the 10-second latency graph samples at 20 Hz after the engine/audio update; backfire pulses and shift types are retained until the next log sample.

## Real Drive input and estimation

Choose **Real Drive**, read the explanation, then **Enable Real Drive Sensors**. Location uses When In Use only, `kCLLocationAccuracyBestForNavigation`, no distance filter, automotive activity, and no automatic pausing. It reads `CLLocation.speed` directly, with timestamp/horizontal/speed accuracy. The estimator rejects negative, nonfinite, over-250 km/h, stale/future, out-of-order, poor-accuracy and physically implausible GPS samples. No coordinate differencing or route recording is used.

Core Motion samples `CMDeviceMotion.userAcceleration`, gravity, attitude and actual timestamps at a requested **50 Hz** using a gravity-aligned reference frame. Filtering uses actual sample spacing, not a constant assumed interval. The **60 Hz** simulation keeps running between GPS callbacks. The audio engine renders continuously. Motion handlers already execute on the main operation queue; their value delivery now uses that actor directly, without another queued task. Acquisition/estimation, simulation and audio control are serialized independently of view rendering. Heavy main-thread work can still delay control updates; no audio render callback accesses SwiftUI or mutable simulation state.

### Mount orientation

In Developer / Calibration, expand **Orientation & stopped detection**, then tap **Calibrate Orientation** while parked. Secure the phone before starting. Gently accelerate straight for several seconds, with a passenger observing. Collection begins only at meaningful horizontal motion. Four seconds of valid samples feed a covariance/power-iteration dominant-direction estimate. Insufficient or mixed directions ask for a retry. GPS acceleration can resolve braking sign; without a signed reference, the guided procedure assumes forward acceleration.

Gravity is projected out of user acceleration. The learned 3D vector is stored **in device/mount coordinates**, so it follows the vehicle through turns rather than becoming a fixed compass heading. Portrait, landscape and tilted mounts are supported. The vector persists locally and survives foreground/background motion restarts. Recalibrate after moving or rotating the mount; the phone cannot know a saved mount is still correct. Automatic direction learning from signed GPS/motion correlation remains a fallback. Until calibrated, the phone's upper edge is an approximate forward axis; lateral acceleration may contaminate this fallback. Uncalibrated phone movement without any GPS anchor is ignored. A calibrated mount can continue motion prediction without GPS.

### Motion-first complementary filter

1. Project motion into the mounted forward axis; reject nonfinite, excessive acceleration, invalid gravity, out-of-order samples and strong handling rotation.
2. Lightly filter acceleration, differentiate using the actual motion timestamp interval, then lightly filter jerk. Alpha controls are defined at 50 Hz and converted as `1 - (1 - alpha)^(dt * 50)`.
3. `ThrottleEstimator` combines positive acceleration, meaningful positive jerk, speed and recent acceleration history. Dead zones, start/stop hysteresis, a minimum transient threshold and separate attack/release coefficients reject small vibration. A strong-to-zero transition emits an explicit lift event immediately, then rapidly releases throttle. Engine overrun and probabilistic backfire can consume that event before the filtered throttle settles. A meaningful launch can leave the stopped latch before GPS speed rises.
4. Integrate acceleration into `predictedSpeedMs` on each simulation step. Clamp speed to 0–250 km/h. The first valid GPS fix bootstraps an uninitialized speed anchor; subsequent measurements never hard-snap prediction.
5. While a GPS reference is fresh, reconcile through `predictedSpeed += (gpsSpeed - predictedSpeed) * (1 - (1 - gain)^dt)`. Gain is per second, so behavior does not depend on UI/GPS callback frequency. Poor speed accuracy weakens correction. This preserves rapid IMU transients while gradually correcting long-term integration drift.
6. During GPS dropout, continue motion integration and increase heuristic uncertainty. After 15 seconds, gradually reduce acceleration influence. If both streams are absent, hold briefly then cautiously decay speed. Returning GPS reconciles through the same bounded filter. Missing motion uses GPS-derived acceleration as a degraded fallback; GPS denial leaves visible diagnostics and Simulation remains available.

The engine combines driveline RPM with converter slip and a bounded, decaying throttle-attack flare, then applies its existing inertia and shift/rev-match interpolation. Load/intake/exhaust audio respond directly to estimated throttle and meaningful jerk before drivetrain load settles. Load/intake gains use a 28 ms attack envelope; other layers retain their click-avoiding fades. This is an approximation of pedal behavior, not real accelerator measurement.

### VirtualEngine

The American profile has a 750 RPM idle, 6,500 RPM redline, 6,400 RPM soft limiter, and 6,700 RPM hard safety limit. Start establishes running RPM at idle, then produces a brief smooth start flare. Once running, RPM never falls below idle. Engine stop immediately returns it to zero.

Pedal response and load are filtered over time. At rest, throttle controls free revving. At road speed, wheel RPM determines the engine target, with a simplified torque-converter coupling/slip model near rest. RPM follows the target using `1 - exp(-rate * deltaTime)`, which cannot overshoot. Acceleration, throttle lift, shifts, aggressive rev matching, and return to idle use different response rates. Overrun keeps RPM coupled to road speed while throttle/load fall. The soft limiter reduces target RPM; the hard cap bounds every update.

This is a believable MVP approximation, not a torque curve or full physical drivetrain. Keeping manual road speed constant while lifting the throttle keeps the engine turning with the wheels, as expected during overrun.

### VirtualTransmission

Eight forward ratios: `4.56, 2.97, 2.08, 1.69, 1.27, 1.00, 0.85, 0.65`. Final drive is `3.55`; default tire circumference is `2.10 m` and can be configured on initialization.

```text
wheelRPM = (speedKmh / 3.6) / tireCircumference * 60
engineRPM = wheelRPM * gearRatio * finalDrive
```

Comfort shifts around 2,200–3,000 RPM at light throttle and holds gears longer under heavy throttle. Sport targets 3,500–5,000 RPM. Track approaches redline under heavy throttle, with an upshift safety threshold below the soft limiter to avoid becoming stuck on the cut.

Decisions consider speed, measured RPM, throttle, mode, and predicted RPM in the destination gear. Minimum dwell times (0.6–1.0 seconds), a 0.65-second cooldown, distinct up/down thresholds, and a two-second opposite-direction lock prevent hunting. High throttle can kick down multiple gears when predicted RPM is safe. A pedal request made during cooldown is retained until safe, and released if the pedal is lifted. Gear values are bounded to 1–8 and low-speed downshifts return the transmission to first.

With neutral tuning, shifts last 150–450 ms depending on throttle and mode. Calibration scales the next shift duration within a final 150–650 ms bound; an active shift keeps its captured duration. The current gear stays engaged until the timed transition finishes; the engine smoothly follows a ratio-derived target during that transition. Upshifts visibly reduce RPM, and downshifts flare RPM upward. Sport/Track, high-throttle, and braking downshifts enter `revMatch`. Developer Mode exposes current and target values for inspection.

### Audio architecture

`EngineAudioEngine` owns one `AVAudioEngine` graph. Ten persistent `AVAudioPlayerNode` loop voices feed bounded `AVAudioUnitVarispeed` units and the main mixer. A four-player pool schedules short events without interrupting continuous loops. RPM updates change gain and pitch parameters; they never reschedule or restart loops. Engine stop fades gains before stopping playback. Mute fades gains to zero while keeping loop phase and the graph running.

`AudioMixModel` is a pure Swift control model updated by the same fixed 60 Hz simulation loop. Its logical layers are `idle`, `lowRPM`, `midRPM`, `highRPM`, `highLoad`, `intake`, `overrun`, `shiftTransient`, `revMatch`, `backfire`, and `limiter`. RPM-band smoothstep crossfades overlap at 1,000–1,200, 2,500–3,000, and 4,500–5,000 RPM. Gain targets follow exponential smoothing with an approximately 83 ms time constant; load/intake attack uses a faster 28 ms time constant. Adjacent samples within a band also crossfade, and playback-rate adjustment stays between 0.85 and 1.15.

Throttle/load independently drive load, intake, and exhaust intensity. Upshifts duck the continuous load layer, play an alternating shift transient once, and recover after the shift. Downshifts play a blip while continuous audio follows the existing RPM flare. Throttle lift blends into overrun, including free-rev lift at rest; this audio behavior does not change the drivetrain's operating mode. Limiter transients fire intermittently when the existing engine reports limiting or RPM approaches the hard limit. The Phase 2 soft limiter remains intact.

`BackfireController` checks an aggressive lift (previous throttle > 0.6, current < 0.15, RPM > 3,000), overrun or stationary RPM decay, deceleration, cooldown, probability, and burst bounds. Default probabilities are 0.015 Comfort, 0.22 Sport, and 0.45 Track, scaled by the backfire-amount control. Minimum intervals are 5 / 2.5 / 1.8 seconds; maximum bursts are 1 / 2 / 3 pops. Single pops dominate, and additional pops use irregular 120–310 ms spacing. Raising amount increases probability and gain; zero disables new bursts. Backfire is intentionally not guaranteed for every lift.

On iOS, playback uses `AVAudioSession` with `.playback` and `.mixWithOthers`, without microphone permission. The system routes this playback category to the iPhone speaker, headphones or selected Bluetooth/A2DP output (including vehicle audio where supported); no Core Bluetooth permission or hardware-specific transport is needed. Select/pair the route using iOS audio controls while parked. We do not force speaker output or switch to microphone/HFP audio. See [Apple's playback/A2DP routing documentation](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetootha2dp).

Session activation/deactivation runs on a serial background queue. Generation checks protect rapid start/stop, backgrounding and interruptions from stale activation completions. Phone calls pause playback; it resumes only when iOS supplies `shouldResume`. Otherwise use **Diagnostics → Retry / Resume Audio** or explicitly Stop/Start Engine while parked. Disconnecting a route pauses output rather than unexpectedly playing through the speaker. Connecting a new route permits recovery; a reconnect does not override an active interruption. Running-graph configuration changes stop/reschedule loop buffers once, and media-service resets recreate the graph and its observer. These lifecycle restarts are distinct from normal RPM updates, which never restart players. See [Apple's route guidance](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes).

Backgrounding immediately pauses audio and acquisition, clears stale sensor samples and stops logging. On return, enabled sensors reacquire, the simulation resumes without a time jump, and audio resumes only if interruption/route policy permits. No background audio or location entitlement is enabled. Permission denial and GPS/motion errors remain visible; missing motion falls back to valid GPS, and missing GPS follows the estimator's hold/decay policy. Neither case prevents Simulation Mode. Audio errors remain visible without stopping the virtual drivetrain; manual retry is available while parked.

### V8 samples, sources and replacement

`Audio/V8_62_NA/` contains 17 hybrid recorded/procedural WAV files:

```text
idle.wav
low_1500.wav, low_2500.wav
mid_3500.wav, mid_4500.wav
high_5500.wav, high_6500.wav
load.wav, intake.wav, overrun.wav
shift_up_1.wav, shift_up_2.wav, downshift.wav
pop_1.wav, pop_2.wav, pop_3.wav, limiter.wav
```

The current set combines CC0 recordings by jackthemurray (350 Rocket V8 idle), overmedium (V8 throttle blips) and Galarne (Corvette C5) with original cross-plane, two-bank RPM-timed pressure pulses. It replaces the earlier three-sine-wave samples with recorded exhaust/mechanical texture, unequal bank pulse spacing, damped exhaust reflections, short recorded blip/shift textures and less tonal pops/limiter effects. All filenames and runtime layering remain unchanged; engine/transmission/sensor behavior is preserved.

Credits, source links, processing time ranges and limitations ship in [Audio/V8_62_NA/CREDITS.md](VirtualV8/Audio/V8_62_NA/CREDITS.md). Raw public HQ MP3 previews and SHA-256 checksums are kept in [AudioSources/V8](AudioSources/V8/CREDITS.md) outside the app bundle. These lossy field recordings are not calibrated steady-RPM recordings of the exact American 6.2L engine. Prepared reference RPMs describe the designed pressure-pulse timing. Load/intake/overrun/shift layers are designed derivatives, not separately measured dyno/microphone tracks.

Regenerate with `python3 Scripts/prepare-v8-audio.py` on macOS using Python + NumPy. NumPy is only an offline authoring dependency; the iOS app remains dependency-free. The script uses the system `afconvert`, verifies source hashes and produces roughly six-second 48 kHz mono WAV loops with DC removal, seamless circular grain stitching and peak ≤ 0.32. Use `--output <directory>` to prepare a separate candidate set. The older `generate-placeholder-audio.py` is retained as an explicit synthetic alternative; running it overwrites the current WAVs with placeholders.

`bash Scripts/render-audio-preview.sh` renders the existing 44-second Sport demo through the same offline AVAudioEngine graph into `AudioPreview/v8-demo.wav`. Optional arguments select a candidate asset directory and output WAV for A/B comparison. This requires macOS 14+ and Xcode command-line tools; no microphone or real driving is involved.

Replace WAV files while retaining their names and the RPM references in `AudioSampleBank`. The folder is copied into the application bundle by Xcode. Files are converted to 48 kHz mono Float32 PCM, checked for valid finite samples, and peak-limited to 0.35. Invalid/missing files use a synthetic PCM fallback; Developer Mode exposes the fallback count. Files longer than 30 seconds are rejected. Use seamless continuous loops and short enveloped events; abrupt replacement edges receive a short fade. Additional mixer headroom keeps the layered output below clipping in rendering tests.

### Audio controls and indoor testing

Simulation Mode adds mute, master volume, engine volume, intake volume, exhaust volume, backfire amount, and shift-transient volume. Changes apply live and persist with the shared calibration. The same audio controls are available separately on Developer / Calibration while parked. Start with the default 45% master level. Audio tuning leaves demo/manual input ownership unchanged.

Run the demo to exercise rising RPM, multiple shifts, high load, lift/overrun, blips, and idle. For manual tests, set speed as desired and move the accelerator. Free revving at zero speed also exercises pitch, limiter cuts, overrun on lift, and probabilistic pops in Sport/Track. Developer gains are the smoothed logical layer levels before the per-voice headroom factor; transient gains are ready-to-play levels, not an event activity meter. `Player starts` should stay constant across RPM changes and mute, except for an actual engine restart or audio route/interruption recovery.

## Developer Mode: calibration and testing

Open **Developer / Calibration** from the main screen or Simulation Mode. Simulation allows live tuning at any simulated speed. Real Drive permits tuning only while the vehicle estimator reports stopped with speed below 2.5 km/h; parameters are locked in both the UI and controller while moving. The stopped estimate is approximate: configure only while actually parked. The Real Drive dashboard contains no sliders or sensor calibration controls. Start/Stop remain on the main screen and Simulation screen.

| Control | Range | Meaning |
| --- | --- | --- |
| Throttle sensitivity | 0.5–1.5× | Multiplies the estimated Real Drive throttle before clamping to 0–1 |
| Acceleration smoothing alpha | 0.10–0.60; default 0.30 | Larger alpha responds faster (50 Hz reference) |
| Jerk smoothing alpha | 0.10–0.60; default 0.25 | Light jerk filtering |
| Throttle attack alpha | 0.20–0.80; default 0.45 | Fast throttle increase |
| Throttle release alpha | 0.10–0.50; default 0.20 | Stable but prompt lift release |
| GPS correction gain | 0.03–0.25; default 0.10 | Fresh GPS correction per second |
| Acceleration dead zone | 0.05–0.40 m/s²; default 0.12 | Ignore vibration near zero |
| Jerk threshold | 0.50–5.00 m/s³; default 1.50 | Minimum positive jerk accent |
| RPM response | 0.5–2.0× | Scales the existing RPM response rates |
| Engine inertia | 0.5–2.0× | Divides response rate; larger means slower RPM changes |
| Upshift aggressiveness | 0.75–1.20× | Scales the existing upshift RPM strategy, retaining limiter safety |
| Downshift aggressiveness | 0.75–1.30× | Scales downshift thresholds/kickdown response and rev-match response |
| Shift duration | 0.6–1.5× | Scales the next shift duration, bounded to 150–650 ms |
| Backfire amount | 0–100% | Existing probability/gain control |
| Engine / intake / exhaust volume | 0–100% each | Existing independent audio gains |
| Audio latency compensation | 0–1000 ms | Bounded continuous-audio RPM look-ahead; default 0, available in Other Audio Controls |

Bounds and 0.01 value resolution are enforced in the settings model as well as the calibration sliders, preventing Float rounding from turning an unchanged preset into Custom. The original exponential RPM interpolation, wheel-speed mapping, limiter, shift cooldown, gear dwell times, anti-hunting and audio graph remain in use. Tuning changes never restart audio loops.

**Comfort**, **Sport** and **Track** presets set the corresponding driving mode plus calibration values. Comfort lowers volume/backfire and favors smoother estimates/earlier shifts. Sport raises shift RPM, response and rev-match strength. Track sharpens response, holds higher RPM and strengthens sound/downshifts. **Custom** is stored separately: selecting a named preset preserves the most recent custom calibration; editing a preset creates a new custom copy. Selecting Custom restores it.

`CalibrationSettings` stores active values, the custom snapshot and selected preset as versioned JSON data in `UserDefaults` under `VirtualV8.calibration.v1`. App startup restores and bounds the data; corrupt data falls back to neutral defaults with a visible message. Existing Simulation audio sliders and other sensor controls save through the same store. Mute, master/shift volume, audio latency compensation and stopped-detection controls also persist. Older JSON retains engine, transmission, audio, sensitivity and stopped settings; removed time-constant sensor filters migrate to the new low-latency alpha defaults. All eight current estimator controls persist with active/custom calibration. The forward mount vector is saved separately in UserDefaults under VirtualV8.orientation.deviceAxis.v1. Selecting a named preset keeps the active latency setting because transport latency is independent of driving style. Input mode defaults to Simulation on every launch; sensor access never starts automatically from saved calibration. Tests inject isolated defaults domains or disable persistence entirely.

### Repeatable Simulation scenarios

The original 42-second Automatic Demo remains available. **Run Scenario** restarts the virtual engine/transmission, preserves calibration/driving mode and any active log, and uses one of ten repeatable input sequences:

| Scenario | Duration | Focus |
| --- | --- | --- |
| City Driving | 58 s | Moderate acceleration, cruise, braking, second pull-away |
| Full Throttle Acceleration | 60 s | Full pedal, 180 km/h peak, upshifts and overrun |
| Highway Cruise | 93 s | On-ramp, 110–120 km/h cruise, exit/downshifts |
| Lift-Off and Downshift | 57 s | High load, abrupt lift, overrun and braking/rev matching |
| Stop-and-Go | 57 s | Three low-speed starts and stops |
| Aggressive Sport Drive | 67 s | Hard acceleration, lift, braking, kickdown, second acceleration |
| Latency A · Sudden Acceleration | 45 s | Motion step equivalent to ~80% throttle, before a new GPS fix |
| Latency B · Throttle Lift | 45 s | Strong acceleration to zero; fast lift and overrun |
| Latency C · GPS Lag | 45 s | 50 Hz IMU / 1 Hz GPS with one-second measurement delay |
| Latency D · GPS Dropout | 45 s | Virtual GPS disabled for five seconds while IMU continues |

Each fixture interpolates speed continuously between timestamped points and changes pedal/brake inputs at defined times. Its final idle interval allows sequential downshifts and RPM settling. Use Sport/Track calibration to compare the aggressive scenario in those modes; scenarios never overwrite a selected calibration. Inputs and drivetrain replay are deterministic across different render frame durations. Probabilistic audio events retain the existing audio model. Manual sliders cancel a scenario, and Stop Engine cancels it immediately. The original six scenarios retain direct, repeatable manual inputs. The four latency scenarios replay the same pure estimator behind PhoneSensorInputProvider, including its calibration/tuning, 50 Hz motion timestamps and slow GPS samples. They need no hardware or permissions. Each has idle, launch, lift, braking, stop and final idle; C adds GPS delay and D drops five updates. Repeat them at different calibration values and compare the telemetry/graphs. Manual sliders still cancel a scenario.

### Drive logs, CSV and timeline

On Developer / Calibration, tap **Start Logging**, run a scenario or drive with Real Drive, then **Stop Logging** and **Export CSV** while parked. Export writes a UTF-8 local `.csv` file; **Share CSV / Save to Files** opens the platform share flow for saving/copying it. No file is uploaded automatically. Export is disabled until logging stops, so the export is a stable snapshot.

`DriveLogger` samples at 5 Hz and retains at most 18,000 rows (one hour), then stops automatically. It logs UTC ISO-8601 timestamps with milliseconds, speed, raw/filtered acceleration, jerk, estimated throttle, RPM, gear, target gear, engine mode, shift type and backfire event. Appended fields are gpsSpeed (km/h), predictedSpeed (km/h), gpsSpeedAccuracy (m/s), rawThrottle and filteredThrottle. Unavailable GPS fields are empty; no false zero fix is logged. Existing columns retain their order. Numeric fields use a locale-independent decimal point. Short shift/backfire events are latched within each 200 ms sample interval; `shiftType` and `backfireEvent` can therefore describe an event within that interval rather than only the instant sampled. The event list separately timestamps engine changes, shifts, throttle lifts, backfires, scenarios/presets and logging transitions; it keeps the latest 200 events.

Logs are in memory until exported. A new logging session replaces the previous session; backgrounding stops logging and closing the app loses unexported rows. Exported files use unique names in the app's temporary directory; use Share CSV to save a durable copy to Files. Neither logs nor calibration include GPS coordinates or routes.

The optional **Show latency graphs** switch renders five lightweight SwiftUI Canvas traces from an independent 200-point buffer (recent 10 seconds at 20 Hz): GPS speed, predicted speed, filtered longitudinal acceleration, throttle and RPM. History works with logging off. Missing GPS values create gaps; acceleration has a signed scale. A separate bounded 5 Hz history remains available to the logger. Developer telemetry also shows speed difference, speed accuracy, raw/filtered acceleration and throttle, jerk, measured motion frequency, GPS age and heuristic speed uncertainty.

## Build and validation

Unsigned SDK builds (do not require an installed simulator runtime):

```sh
xcodebuild -project VirtualV8.xcodeproj -target VirtualV8 \
  -configuration Debug -sdk iphoneos \
  SYMROOT=/tmp/VirtualV8DeviceBuild OBJROOT=/tmp/VirtualV8DeviceIntermediates \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project VirtualV8.xcodeproj -target VirtualV8 \
  -configuration Debug -sdk iphonesimulator \
  SYMROOT=/tmp/VirtualV8SimulatorBuild OBJROOT=/tmp/VirtualV8SimulatorIntermediates \
  CODE_SIGNING_ALLOWED=NO build
```

Run the native XCTest suite with **Product → Test**, or:

```sh
xcodebuild -project VirtualV8.xcodeproj -scheme VirtualV8 \
  -destination 'platform=iOS Simulator,name=<installed simulator name>' test
```

If no simulator runtime is installed, run the same controller tests on macOS 14+:

```sh
./Scripts/test-controller.sh
```

The fallback script creates and removes a temporary dependency-free Swift package containing the existing controller sources and tests. It does not modify the Xcode project or add a production dependency.

Hardening validation uses Xcode 27.0 and the iOS 27 iPhone 18 Pro simulator:

- Native simulator tests pass (64 tests, zero failures). Unsigned device and Mac Catalyst SDK builds succeed, and the final iOS app was installed/launched on the simulator. Complete concurrency checking reports no Swift source warnings.
- The 64-test native suite retains all 55 previous regressions and adds provider injection/lifecycle, simulation derivative/lift boundaries, phone input without fixes, background freeze/resume, audio interruption/reconnect/media-reset rendering, bounded latency prediction, Phase 5 settings migration/persistence and unchanged drivetrain/shift timing with compensation. Audio asset validation also checks loop DC, boundary continuity, non-silent RMS, duration and headroom.
- Existing tests cover idle/RPM rise/fall/limits, upshift/downshift/kickdown/anti-hunting/gear ranges, estimator noise/throttle/stopped/lift behavior, audio band weights/backfire cooldown and complete acceleration/deceleration scenarios.
- The macOS test runner runs the same suite with its one iOS-only playback-session test skipped.
- Interactive Mac Catalyst verification confirms live route/status diagnostics, migration of the previous Custom calibration, and latency slider changes persisting across quit/relaunch.
- Real Bluetooth routes, phone calls, permission dialogs and mounted-phone road estimates still require physical-device evaluation; simulator/offline rendering cannot establish their hardware behavior.

Optional local Mac Catalyst UI verification build (requires macOS 14+):

```sh
xcodebuild -project VirtualV8.xcodeproj -target VirtualV8 \
  -configuration Debug -sdk macosx \
  SUPPORTS_MACCATALYST=YES SDK_VARIANT=iosmac \
  SYMROOT=/tmp/VirtualV8Catalyst OBJROOT=/tmp/VirtualV8CatalystIntermediates \
  CODE_SIGNING_ALLOWED=NO build
codesign --force --deep --sign - /tmp/VirtualV8Catalyst/Debug-maccatalyst/VirtualV8.app
open /tmp/VirtualV8Catalyst/Debug-maccatalyst/VirtualV8.app
```

Manual indoor audio checklist:

1. Navigate through Driving, Simulation, and Developer screens; confirm state survives navigation.
2. Start the engine, wait for idle, and move each slider; confirm numeric labels, dashboard, tachometer, and developer values update.
3. Run the automatic demo; observe 160 km/h, high RPM, smooth shift-related RPM drops/flares, throttle lift, braking/downshifts, and final 750 RPM idle at rest.
4. Move a slider during the demo; confirm manual control resumes.
5. Stop during a demo; confirm the demo stops, RPM becomes zero, inputs reset, and audio fades out.
6. Mute/unmute while running; confirm silence/recovery without increasing player starts.
7. Change all six audio controls; confirm gains and output respond independently while the demo continues.
8. Select Sport/Track, rev above 3,000 RPM, and lift rapidly; some eligible lifts should produce short irregular pops, with quiet lifts between them.
9. Check Developer Mode for audio errors/fallbacks and verify shifting produces events while the graph stays running.

Real Drive acceptance checks (physical device):

1. Enable sensors after onboarding; confirm the iOS location purpose text and available GPS/motion/accuracy status. Denial should leave Simulation available and Real Drive waiting safely for valid speed.
2. Secure the phone, accelerate/brake in a straight line, and confirm forward calibration. Repeat with a different mounting orientation using Relearn Forward Direction.
3. Have a passenger inspect Developer telemetry during acceleration, lift, braking and a sustained stop; confirm smooth throttle/RPM, shifts and eventual idle.
4. Briefly lose reception; confirm held speed followed by cautious decay, zero estimated throttle, and smooth recovery on a valid fix.
5. Background/foreground the app and switch back to Simulation; confirm acquisition stops/starts appropriately and manual inputs/demo still work.

## Diagnostics and Bluetooth latency

Open **Diagnostics** from the main screen or Developer / Calibration while parked. It reports app version/build, current engine profile/input, foreground state, configured 60 Hz fixed simulation step, audio status/route, system-reported output latency, configured compensation, predicted audio RPM, GPS status/permission, motion status/freshness and location accuracy. The frequency is the configured fixed step, not a promise of a 60 FPS display or a measured sensor rate. System-reported output latency is informative and is not a complete end-to-end Bluetooth measurement.

`audioLatencyCompensationMs` is a persisted 0–1000 ms control, default 0. `AudioLatencyCompensator` estimates the current RPM slope, limits it to ±4000 RPM/s, applies a lead of at most ±1200 RPM, and clamps audible RPM to the current profile's 750–6700 RPM bounds. It resets its history on stop, backgrounding and recovery. The prediction changes continuous-band weights/sample pitch only; actual engine RPM, transmission decisions, shift/backfire/limiter event timing, displayed drivetrain RPM and CSV logs remain authoritative and unchanged. No artificial audio delay is added.

Bluetooth delay varies between phones, codecs, speakers, vehicles and reconnection sessions. Larger compensation can overshoot or sound early during an unpredictable lift/shift. It cannot predict future inputs/transients or remove buffering in external hardware. Start at 0; compare a repeatable scenario on the speaker and selected route, then adjust modestly while parked. The iPhone speaker is the reference for evaluating responsiveness. There is no hardware-specific Bluetooth optimization in this MVP.

## How to tune and evaluate

1. Select a preset, then run the same Simulation scenario before/after each change. Start at low volume and keep latency at 0 for drivetrain comparisons.
2. Tune throttle/acceleration filters with a fixed mounted phone and real sensor data; indoor manual inputs bypass estimation filters intentionally. Use a passenger for observation and configure only while parked.
3. Change RPM response/inertia first; then shift aggressiveness/duration. Use target RPM, shift progress, timeline and graphs to check smoothness and hunting. Limits and shift safety remain enforced.
4. Tune layer volumes and backfire amount independently. Use lower backfire amounts for occasional pops, or 100% for repeatable downshift bursts. Change latency last for the specific output hardware.
5. Log a repeatable run at 5 Hz, stop, export and save the CSV. Record the preset/custom settings and output route with the evaluation notes. Unexported logs are lost when closing the app.

## Known limitations and safety

- The powertrain is a simplified virtual model, not physical torque/vehicle dynamics. The simulation speed slider/scenario dictates speed. Its tachometer and gear do not represent the EV's actual propulsion system.
- Throttle/brake are estimated from phone acceleration, not measured pedals. GPS noise, gradients, turns, rough surfaces, a loose mount, motion denial and orientation drift can affect estimates. Powered cruise versus coasting cannot always be distinguished; Fresh calibrated motion remains responsive during GPS loss; long outages accumulate drift and uncertainty. GPS-free estimates should not be used as a reliable speedometer.
- WAV assets are a hybrid of CC0 V8 field-recording previews and original procedural pulse layers. They improve recorded texture but do not constitute lossless, calibrated samples of the exact 6.2L profile. Dedicated steady-RPM/on-load/off-load recordings, hardware-specific latency work and physical-device sensor refinement remain future work.
- This release works in the foreground. Backgrounding pauses sound/sensors/scenarios and stops logging. Reacquisition may take time; permission denial is recoverable through iOS Settings or by using Simulation.
- Calibration locks use an approximate stopped estimate; they are not proof that the car is safely parked. Secure the phone before moving, set volume low enough to hear traffic/alerts, obey local requirements, and have a passenger operate/observe controls. Do not interact with Developer, diagnostics, logging or simulation controls while driving. Configure engine parameters while actually parked.
- No vehicle commands, Tesla CAN access, Bluetooth data adapter, route recording, backend or account system exist. Bluetooth audio is ordinary system playback and is separate from vehicle-data integration.

## Phase 7: Tesla CAN / direct vehicle-data roadmap

The design is documented in [Docs/Phase7VehicleData.md](Docs/Phase7VehicleData.md). No `CANVehicleInputProvider` implementation or communication is shipped.

A future provider will compose a read-only transport, vehicle-specific decoder, timestamp/quality validation and a `VehicleState` adapter. True pedal, speed and brake replace phone estimates; mode, motor torque and other signals use optional source metadata. Develop with captured-frame replay first, then test disconnects/stale data/permissions and stationary hardware before supervised road evaluation.

For CAN mode, replace the selected **PhoneSensorInputProvider** with **CANVehicleInputProvider** through the existing protocol seam and bypass `VehicleStateEstimator` for authoritative signals. Keep Phone Sensor and Simulation providers as selectable fallbacks. Extend source diagnostics and CSV schema metadata explicitly. `VirtualEngine`, `VirtualTransmission`, layered audio/backfire, calibration, driving UI, scenarios and the logger sampling pipeline remain unchanged; none should import Tesla frames or transport APIs.

### Real Drive display and downshift pops

While Real Drive is selected and the virtual engine is running in the foreground, the app disables automatic screen dimming/locking. Stopping the engine, switching to Simulation, leaving the app, or losing the active scene restores normal auto-lock. The side button can still lock the phone manually.

Backfire amount now controls short downshift exhaust bursts as well as the existing probabilistic throttle-lift pops. At **100%**, every downshift whose current or rev-match target RPM is at least 1500 produces a randomly sized burst of 2–5 pops after the rev-match blip, including Comfort. Lower amounts retain mode-dependent probability and shorter bursts; 0% disables pops. Idle-speed downshifts are quiet. Each app audio instance starts with a fresh random seed; tests can inject a seed for repeatable audio regressions. Bursts use randomized 60–140 ms initial delay and irregular 70–200 ms spacing, a 550 ms cooldown, and replace pending bursts rather than stacking them. This is an intentionally aggressive tuning option, not a claim that all stock V8s backfire this way.

Pop voices have more output presence than before, retain their event accents, and respect mute/volume fades without restarting the engine loops. The virtual RPM flare and transmission behavior are unchanged. To render the Sport demo with maximum pops: `bash Scripts/render-audio-preview.sh VirtualV8/Audio/V8_62_NA AudioPreview/downshift-pops.wav 1`.

### BMW M3 S65 profile

Select **BMW M3 E90/E92/E93 · 4.0L S65 V8** in the Engine Profile picker while parked with the engine stopped. The selection persists independently of driving/calibration presets. Selecting a different profile resets the stopped drivetrain and audio graph; profile changes are blocked while running. The original American bank remains intact.

The S65 profile uses a brighter, less bass-heavy pressure/rasp balance and a prominent designed induction layer. It includes 17 separate WAVs under `Audio/BMW_S65`, with idle at 800 RPM, low references at 1800/3200, mid at 4500/5800 and high at 7000/8200. Smooth band weights, limited pitch adjustment, audio latency bounds, limiter events and the tachometer follow the selected profile. Shift, rev-match, overrun and randomized pops use its own assets. Upshift thresholds scale with the selected redline so the S65 can reach its higher bands in Track mode; the American thresholds remain unchanged. The existing virtual eight-speed gearbox remains shared; this does not simulate a BMW-specific gearbox.

Its 8,400 RPM redline follows [BMW's M3 Saloon specifications](https://www.press.bmwgroup.com/global/article/detail/T0011998EN/the-new-bmw-m3-saloon?language=en). Idle (800), soft limiter (8300) and hard safety bound (8500) are MVP approximations. These assets are **S65-inspired hybrid sound design**, not verified recordings of an S65 or an exact reproduction of a stock M3 exhaust. Original pulse/induction synthesis is mixed with filtered generic CC0 textures whose sources ship in `Audio/BMW_S65/CREDITS.md`; no commercial vehicle recording is embedded without reuse rights.

Rebuild the bank with the NumPy authoring runtime using `python3 Scripts/prepare-s65-audio.py`. The iOS application needs no extra dependency. Replace files with licensed steady-RPM S65 WAVs using the filenames and references in `AudioSampleBank.samples(for:)`; Xcode copies the complete bank folder. Render a demo with `bash Scripts/render-audio-preview.sh VirtualV8/Audio/BMW_S65 AudioPreview/bmw-s65-demo.wav 0.8 bmw-s65`.

### Classic Toyota Supra Mk4 turbo profile

Select **Toyota Supra Mk4 · 3.0L 2JZ-GTE Twin Turbo** with the engine stopped. This represents the [A80/Mk4 twin-turbo inline-six family described by Toyota](https://www.toyota-global.com/company/history_of_toyota/75years/vehicle_lineage/car/id60006850/index.html). Idle 750, redline 6800, soft limiter 6700 and hard bound 7000 are MVP tuning values, not a specification for every model year or modified engine.

`Audio/Supra_2JZ` contains 20 original procedural WAVs: six-cylinder exhaust/induction layers, turbo spool/whistle, two air-pressure release variants and the existing transition/pop categories. These are **2JZ-inspired recreated sounds**, not recordings of an actual Supra. Six-cylinder pressure timing uses three combustion events per crankshaft revolution and is distinct from the V8 banks. Author them with `python3 Scripts/prepare-supra-audio.py`; NumPy is an authoring dependency only. Provenance and limitations ship in the bank's `CREDITS.md`.

The audio mixer estimates a bounded turbo-pressure envelope from RPM, throttle and engine load, with gradual spool-up and faster decay. A strong lift crossing below 20% throttle or a loaded upshift plays one release hiss/descending whistle when pressure is present. It vents the audio pressure envelope, uses a 450 ms cooldown, and requires renewed throttle/boost before another lift release. This is sound behavior only: it does not change simulated engine RPM, vehicle acceleration or transmission physics, and does not simulate sequential turbo hardware or compressor surge. Intake volume controls both turbo spool and release; mute silences them. Developer Mode shows `turboSpoolGain` and `pressureReleaseGain` alongside the existing gains.

The original V8 profiles have zero turbo/release gain and never emit these events. The shared eight-speed virtual gearbox, profile persistence, randomized pops, screen-awake behavior, sensors and logging remain intact. Render a demo with `bash Scripts/render-audio-preview.sh VirtualV8/Audio/Supra_2JZ AudioPreview/supra-2jz-demo.wav 0.7 supra-2jz`. Replace WAVs with licensed recordings using `AudioSampleBank.samples(for:)` references and `pressure_release_1/2.wav` names.

### Mercedes-AMG GT R profile

Select **Mercedes-AMG GT R · 4.0L Biturbo V8** with the engine stopped. This follows the [4.0L V8 biturbo GT R described by Mercedes-Benz](https://media.mbusa.com/news/the-new-mercedes-amg-gt-r-1), rather than the different GT Black Series engine. The MVP uses 750 idle, 7000 redline, 6900 soft limiter and 7200 hard bound as tuning approximations. Profile selection persists and the existing eight-speed virtual transmission remains shared; no AMG gearbox or boost/torque physics are claimed.

`Audio/AMG_GTR` contains 20 dedicated WAVs: deeper cross-plane pressure/rasp, intake, a subdued turbo whistle, pressure-release variants, overrun, shift/rev-match events, heavier pops and limiter. These are **AMG GT R-inspired recreated sounds**, not verified M178/GT R recordings or an exact stock exhaust/valve system. The design blends original pulse/noise synthesis with the already-credited generic CC0 V8 rev texture; exact source details ship in the bank's `CREDITS.md`.

The shared turbo envelope produces load-dependent spool and pressure release on strong lifts/loaded upshifts. Intake Volume controls both; Backfire Amount controls the existing randomized exhaust pops. American, BMW and Supra banks and mixer behavior remain intact. Author this bank using `python3 Scripts/prepare-amg-audio.py` with NumPy/macOS afconvert; neither is an iOS dependency. Render with `bash Scripts/render-audio-preview.sh VirtualV8/Audio/AMG_GTR AudioPreview/amg-gtr-demo.wav 0.8 amg-gtr`. Replace WAVs later with licensed, RPM-labeled recordings using the names/reference RPMs in `AudioSampleBank.samples(for:)`.

### Six classic sports/supercar profiles

All six are selectable from Engine Profile with the engine stopped, and selection persists. Existing profiles are unchanged. These banks contain **original procedural sound recreations**, not verified recordings of the named vehicles. The descriptions below are sound-design targets, not measured acoustic matching claims. Intake/load/overrun, upshift, rev-match, randomized pops and limiter behavior remain shared; the RX-7 additionally uses turbo spool and pressure release.

| Profile | Designed character | MVP idle / redline | Bank folder |
| --- | --- | --- | --- |
| Lexus LFA 4.8L V10 | Clear rising V10 with prominent induction orders | 900 / 9000 | `Lexus_LFA` |
| Lamborghini Murciélago 6.2L V12 | Deeper, layered V12 howl | 900 / 7600 | `Lamborghini_Murcielago` |
| Porsche 911 GT3 (996) 3.6L flat-six | Mechanical texture and sharper rasp | 850 / 7800 | `Porsche_996_GT3` |
| Mazda RX-7 FD 13B-REW twin-turbo rotary | Rotary buzz, compressor whistle and release | 850 / 8000 | `Mazda_RX7_FD` |
| Ferrari F355 3.5L flat-plane V8 | Bright metallic exhaust harmonics | 1000 / 8500 | `Ferrari_F355` |
| Porsche Carrera GT 5.7L V10 | Rougher, more resonant V10 voice than the LFA | 900 / 8400 | `Porsche_Carrera_GT` |

The layouts follow manufacturer references: [Lexus LFA](https://media.lexus.co.uk/lexus-lfa/), [Murciélago](https://www.lamborghini.com/de-en/node/1900), [996 GT3](https://newsroom.porsche.com/en_US/2024/products/porsche-911-gt3-25-years-performance-37558.html), [RX-7 FD](https://www.mazdausa.com/discover/rx-7-heaven), [F355](https://www.ferrari.com/en-US/magazine/articles/the-f355-celebrates-30-years), and [Carrera GT](https://pnr-prd2-pub1.newsroom.porsche.com/en_US/2025/company/porsche-carrera-gt-claims-coveted-spot-on-2026-hagerty-bull-market-list.html). Idle, limiting and response settings are MVP approximations; the shared eight-speed simulation does not recreate each car's original gearbox, rotary thermodynamics, torque curve or exhaust installation.

`EngineProfile.audioReferences` provides each new bank's seven idle/low/mid/high reference RPMs. `AudioSampleBank` maps them to `idle`, `low_a/b`, `mid_a/b`, `high_a/b` plus load/intake/overrun. Each naturally aspirated bank has 17 WAVs; RX-7 has 20. Rotary fallback uses two rotor firing events per eccentric-shaft revolution, instead of the piston-cylinder formula. Every bank includes `design.json` and `CREDITS.md`, 48 kHz mono audio, smooth edges and peak headroom. Only the selected bank is loaded into the graph.

Generate all six with `python3 Scripts/prepare-classic-audio.py` using the NumPy authoring runtime, or one with `--profile lexus-lfa` (other IDs: `lamborghini-murcielago`, `porsche-996-gt3`, `mazda-rx7-fd`, `ferrari-f355`, `porsche-carrera-gt`). This does not rewrite existing banks and adds no iOS runtime dependency. Replace the new WAVs with properly licensed RPM-labeled recordings using the metadata references for better authenticity. Example preview: `bash Scripts/render-audio-preview.sh VirtualV8/Audio/Lexus_LFA AudioPreview/lexus-lfa-demo.wav 0.7 lexus-lfa`. Render all six with one compilation using `bash Scripts/render-audio-preview.sh VirtualV8/Audio AudioPreview/Classics 0.7 --all-classics`.

### Profile selection on iPhone

The main Engine Profile row opens an explicit list of all ten profiles. Tap a row to select it; the screen returns to the main menu and the profile name updates. Rows call the controller with stable catalog IDs rather than binding a SwiftUI Picker to the full profile struct. Selection and audio-bank metadata persist together. While running, the list explains the lockout and provides a Stop Engine action; stop, then choose a profile. Real Drive tuning remains restricted to parked state. Unknown IDs and changes while running/moving are rejected without modifying the drivetrain or saved choice.


## Motion-first latency validation

The estimator and `ThrottleEstimator` have regressions for timestamp-based filtering/jerk, launch before new GPS, asymmetric throttle release/lift, 5-second GPS dropout, nonnegative prediction, gradual GPS correction/recovery, vibration rejection, dominant mount calibration, all four 50 Hz / 1 Hz replays, settings/schema migration and orientation persistence. A clocked sensor-controller integration test verifies that throttle, RPM and load/intake gains begin responding within 80 ms without a new GPS sample. CSV export is checked against its on-disk content and the appended telemetry schema. Existing powertrain, audio, lifecycle, logging and scenario tests remain in the suite.

Remaining measurable latency includes the sensor sample interval (nominal 20 ms), actual device-motion delivery, the next 60 Hz control step (up to ~17 ms plus scheduling), configurable filter/envelope settling, main-thread contention, AVAudioUnitTimePitch buffering and hardware output transport. The app requests a 5 ms AVAudioSession I/O buffer as a best-effort preference; Diagnostics displays the actual negotiated duration. WAVs and one-shots are already preloaded, and RPM changes do not restart players. Bluetooth can add substantial variable delay that these estimator changes cannot remove; use the phone speaker or wired output for sensor-latency evaluation. The software integration timing is deterministic control-path evidence, not a measured physical phone-to-speaker latency claim. A secured-phone road evaluation with a passenger remains necessary to measure actual perceptual response and tune mount/road behavior.
