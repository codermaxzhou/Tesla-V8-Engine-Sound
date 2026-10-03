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

- **Engine Profile:** American 6.2L NA V8, the single available profile.
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
  Models/        VehicleState and the single EngineProfile
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

All mutable coordination, sensor state, audio graph mutation, settings, logging and UI publishing are `@MainActor`. Location delegates and motion callbacks copy value samples before hopping to that actor. Motion acquisition generations reject callbacks from a stopped/restarted session. Location managers are detached/disposed on stop, and callbacks are checked against the active manager identity. Sensor access is owned by one coordinator. AVAudioSession activation/deactivation runs on one serial background queue with generations guarding stale completions; audio render threads consume AVFoundation buffers and never mutate application state. Notification registrations use immutable token owners for safe cleanup. Complete Swift concurrency diagnostics are enabled in the project.

A cancellable timer supplies elapsed time to an accumulator. The controller always processes fixed 1/60-second steps: selected input (manual/demo or sensors → estimator) → transmission decision → engine update → backfire/audio control update → state publishing → SwiftUI. Large render frames are subdivided rather than changing physics behavior. Live elapsed time is capped at 0.2 seconds. Backgrounding freezes simulation/scenarios and clears the accumulator; foregrounding resumes from the paused point without catching up elapsed suspension time. Tests disable the timer and exercise the exact same loop with different frame durations. Events remain in memory, capped at 200 entries. Drive logging/history sample at 5 Hz after the engine/audio update; backfire pulses and shift types are retained until the next log sample.

## Real Drive input and estimation

Choose **Real Drive** on the main screen, read the explanation, then tap **Enable Real Drive Sensors**. Start the engine and open **Driving Screen**. That screen is a minimal dashboard. Sensor onboarding/status remain on the main navigation screen; advanced controls and telemetry are on Developer / Calibration. Switching to Simulation or disabling sensors stops both adapters. Backgrounding pauses acquisition, clears stale samples/forward-axis calibration, and resumes an enabled Real Drive session only when active again. There is no background location capability or Always authorization.

`LocationManager` lazily creates a Core Location manager, requests When In Use authorization, and retrieves speed, timestamp, horizontal accuracy and speed accuracy. Speed is converted from m/s to km/h. The estimator rejects negative/nonfinite/over-250 km/h speeds, horizontal accuracy worse than 80 m, invalid or worse-than-5 m/s speed accuracy, samples older than three seconds or too far in the future, duplicate/out-of-order timestamps, and implied acceleration above 8 m/s². Reduced-accuracy or poor reception can therefore leave the app waiting for a usable fix. Coordinates are neither retained nor published.

`MotionManager` samples device motion at 50 Hz. It collects user acceleration, gravity, attitude and rotation rate. User acceleration is converted from g to m/s²; the transpose of the attitude rotation matrix maps it into the gravity-aligned arbitrary reference frame. Motion uptime is converted to the same Unix timestamp convention as GPS. Nonfinite/stale/out-of-order samples, acceleration above 12 m/s², implausible gravity, and rapid phone rotation are rejected. Starting the device-motion API is the access request appropriate to this feature; the app does not request unrelated pedometer or activity-classification access. Unsupported devices and acquisition/permission errors are exposed in the UI.

Secure the phone in a fixed mount. The estimator learns a horizontal forward direction by correlating the recent horizontal motion average with signed GPS acceleration during straight acceleration or braking. Until that direction is learned, acceleration comes from GPS speed differences. Once calibrated, fresh motion projected onto that direction provides quick longitudinal response; stale motion falls back to GPS. Lateral motion is excluded by projection. Strongly contradictory calibration observations are ignored; **Relearn Forward Direction** in Developer / Calibration → Other Sensor Settings clears calibration after remounting. This is a practical MVP approximation, not full sensor fusion: turns, rough roads, phone handling, gyro drift, and GPS noise still require physical-device validation.

`VehicleStateEstimator` is a pure Swift, deterministic model accepting timestamped value samples. It publishes raw and smoothed acceleration, jerk, filtered speed, estimated throttle/brake and vehicle classification. Speed integrates filtered acceleration between fixes, is corrected toward GPS using an exponential filter, and uses a ±2 m/s corridor around the last anchor to bound drift. A distant fix after an outage is reconciled through the speed filter before enforcing that corridor. If valid GPS stops arriving, speed is held after the three-second freshness window for another two seconds, then decays at 0.5 m/s²; throttle fades to zero during the outage. It never immediately drops speed to zero. Without any GPS anchor, phone movement cannot generate speed or throttle.

Acceleration and throttle use exponential low-pass filters, a 0.12–0.30 m/s² acceleration dead zone/hysteresis, bounded jerk, and recent acceleration history. Typical sustained acceleration estimates are about 0.1–0.3 for weak, 0.3–0.6 for normal and 0.6–1.0 for strong acceleration. A sudden collapse after sustained acceleration uses a faster throttle-release filter and short lift hold to enter overrun without repeated oscillation. Negative filtered acceleration estimates brake input. These are sound-control estimates, not measurements of the actual pedals; steady-speed coasting and powered cruising cannot always be distinguished.

Stopped detection uses a default 2.5 km/h threshold sustained for 1.5 seconds, with a separate 3.5 km/h exit threshold. Stationary throttle is zero. `VehicleState.detectedStopped` supplies this delayed classification in Real Drive; its default nil preserves the original immediate manual Simulation behavior. Existing engine/transmission/audio models receive the same `VehicleState` input and contain no sensor framework code.

**Developer Mode** adds raw GPS speed/timestamp/accuracy, filtered speed, raw and filtered acceleration, jerk, estimated throttle, lift detection, raw motion vectors/timestamp, and rejected-sample counts. It exposes `accelerationSmoothing`, `speedSmoothing`, and `throttleSmoothing` as time constants in seconds, plus stopped threshold/duration. Higher time constants smooth more; settings persist with the shared calibration. GPS, motion, location accuracy and audio status are also shown in Real Drive.

Apple API references: [Core Location When In Use authorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()) and [CMDeviceMotion measurements](https://developer.apple.com/documentation/coremotion/cmdevicemotion).

### VirtualEngine

The profile has a 750 RPM idle, 6,500 RPM redline, 6,400 RPM soft limiter, and 6,700 RPM hard safety limit. Start establishes running RPM at idle, then produces a brief smooth start flare. Once running, RPM never falls below idle. Engine stop immediately returns it to zero.

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

`AudioMixModel` is a pure Swift control model updated by the same fixed 60 Hz simulation loop. Its logical layers are `idle`, `lowRPM`, `midRPM`, `highRPM`, `highLoad`, `intake`, `overrun`, `shiftTransient`, `revMatch`, `backfire`, and `limiter`. RPM-band smoothstep crossfades overlap at 1,000–1,200, 2,500–3,000, and 4,500–5,000 RPM. Gain targets follow exponential smoothing with an approximately 83 ms time constant. Adjacent samples within a band also crossfade, and playback-rate adjustment stays between 0.85 and 1.15.

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
| Acceleration smoothing | 0.05–1.50 s | Sensor acceleration filter time constant |
| Throttle smoothing | 0.10–1.50 s | Sensor throttle filter time constant; lift still releases faster |
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

`CalibrationSettings` stores active values, the custom snapshot and selected preset as versioned JSON data in `UserDefaults` under `VirtualV8.calibration.v1`. App startup restores and bounds the data; corrupt data falls back to neutral defaults with a visible message. Existing Simulation audio sliders and other sensor controls save through the same store. Mute, master/shift volume, audio latency compensation and stopped/speed-filter controls also persist. Existing Phase 5 JSON migrates with latency defaulting to 0; saved custom values are retained. Selecting a named preset keeps the active latency setting because transport latency is independent of driving style. Input mode defaults to Simulation on every launch; sensor access never starts automatically from saved calibration. Tests inject isolated defaults domains or disable persistence entirely.

### Repeatable Simulation scenarios

The original 42-second Automatic Demo remains available. **Run Scenario** restarts the virtual engine/transmission, preserves calibration/driving mode and any active log, and uses one of six fixed input sequences:

| Scenario | Duration | Focus |
| --- | --- | --- |
| City Driving | 58 s | Moderate acceleration, cruise, braking, second pull-away |
| Full Throttle Acceleration | 60 s | Full pedal, 180 km/h peak, upshifts and overrun |
| Highway Cruise | 93 s | On-ramp, 110–120 km/h cruise, exit/downshifts |
| Lift-Off and Downshift | 57 s | High load, abrupt lift, overrun and braking/rev matching |
| Stop-and-Go | 57 s | Three low-speed starts and stops |
| Aggressive Sport Drive | 67 s | Hard acceleration, lift, braking, kickdown, second acceleration |

Each fixture interpolates speed continuously between timestamped points and changes pedal/brake inputs at defined times. Its final idle interval allows sequential downshifts and RPM settling. Use Sport/Track calibration to compare the aggressive scenario in those modes; scenarios never overwrite a selected calibration. Inputs and drivetrain replay are deterministic across different render frame durations. Probabilistic audio events retain the existing audio model. Manual sliders cancel a scenario, and Stop Engine cancels it immediately. Sensor smoothing/sensitivity knobs affect Real Drive estimation; the indoor fixtures intentionally retain direct, repeatable manual throttle inputs.

### Drive logs, CSV and timeline

On Developer / Calibration, tap **Start Logging**, run a scenario or drive with Real Drive, then **Stop Logging** and **Export CSV** while parked. Export writes a UTF-8 local `.csv` file; **Share CSV / Save to Files** opens the platform share flow for saving/copying it. No file is uploaded automatically. Export is disabled until logging stops, so the export is a stable snapshot.

`DriveLogger` samples at 5 Hz and retains at most 18,000 rows (one hour), then stops automatically. It logs UTC ISO-8601 timestamps with milliseconds, speed, raw/filtered acceleration, jerk, estimated throttle, RPM, gear, target gear, engine mode, shift type and backfire event. Numeric fields use a locale-independent decimal point. Short shift/backfire events are latched within each 200 ms sample interval; `shiftType` and `backfireEvent` can therefore describe an event within that interval rather than only the instant sampled. The event list separately timestamps engine changes, shifts, throttle lifts, backfires, scenarios/presets and logging transitions; it keeps the latest 200 events.

Logs are in memory until exported. A new logging session replaces the previous session; backgrounding stops logging and closing the app loses unexported rows. Exported files use unique names in the app's temporary directory; use Share CSV to save a durable copy to Files. Neither logs nor calibration include GPS coordinates or routes.

The optional **Show speed / throttle / RPM graphs** switch renders three lightweight SwiftUI Canvas traces from an independent 300-point buffer (recent 60 seconds at 5 Hz). History works even when logging is off. The buffer is bounded and graphs have fixed scales of 250 km/h, 100% throttle and 6,700 RPM.

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
- Throttle/brake are estimated from phone acceleration, not measured pedals. GPS noise, gradients, turns, rough surfaces, a loose mount, motion denial and orientation drift can affect estimates. Powered cruise versus coasting cannot always be distinguished; GPS loss holds/decays cautiously and suppresses throttle until usable fixes return.
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
