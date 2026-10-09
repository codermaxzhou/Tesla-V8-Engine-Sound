# Motion-first estimation validation

This change keeps the existing SwiftUI navigation, input-provider seam, engine profiles,
eight-speed transmission, WAV banks, continuous audio graph, presets and CSV export.
The source remains dependency-free and contains no CAN communication or Kalman filter.

## Changed files

| Area | Files and purpose |
|---|---|
| Sensor samples | `SensorSamples.swift`, `VehicleState.swift`: attitude, reference/device vectors, response tuning, predicted/GPS speed, accuracy, raw throttle, and immediate lift event |
| Acquisition | `MotionManager.swift`, `LocationManager.swift`: actual 50 Hz motion timestamps/attitude, direct main-queue delivery, navigation GPS configuration |
| Estimation | `VehicleStateEstimator.swift`: acceleration integration, gradual GPS reconciliation, filtering, dropout uncertainty, stopped/launch detection |
| New pure models | `ThrottleEstimator.swift`, `OrientationCalibration.swift`: asymmetric pedal estimate; four-second dominant horizontal mount direction |
| Sensor lifecycle | `SensorInputController.swift`: calibration action/persistence and preserved mount axis across restarts |
| Powertrain | `VirtualEngine.swift`: bounded transient RPM attack and immediate lift/overrun; transmission behavior remains intact |
| Audio | `AudioMixModel.swift`, `EngineAudioEngine.swift`: direct perceptual load/intake attack and lift events, best-effort 5 ms I/O preference and actual-buffer diagnostics |
| Indoor replay | `SimulationScenario.swift`, `SimulationInputProvider.swift`, `SimulationController.swift`: four repeatable virtual-sensor scenarios and clean manual handoff |
| Tuning | `CalibrationSettings.swift`, `CalibrationControlsView.swift`, `SensorTuningView.swift`: eight persisted/bounded estimator controls and old-schema migration |
| Diagnostics | `DeveloperView.swift`, `SensorStatusView.swift`, `DiagnosticsView.swift`: orientation workflow, GPS/prediction/jerk/throttle/frequency/age/accuracy, actual audio buffer |
| Graphs/logging | `DriveLogger.swift`, `DriveHistoryView.swift`: 10-second 20 Hz graph buffer, five Canvas traces, appended 5 Hz CSV telemetry |
| Tests/project/docs | `LatencyEstimatorTests.swift`, `EstimatorTests.swift`, `CalibrationLoggingTests.swift`, `project.pbxproj`, `README.md`, this document |

## Requirement evidence

| Requirements | Current evidence |
|---|---|
| Motion-first modular pipeline; no GPS callback gate | Phone provider remains unchanged; estimator ingests motion independently; controller keeps fixed 60 Hz transmission/engine/audio steps |
| Device motion, 50 Hz, user acceleration, attitude, timestamps | MotionManager acquisition code; timestamp/filter unit regression; physical-delivery test requires unlocked connected phone |
| Calibration across mount orientation, saved vector, fallback | Dominant-axis/tilted-gravity regression and saved-orientation/restart regression; Developer calibration workflow |
| Light acceleration and jerk filtering with actual dt | Exact alpha and irregular-timestamp jerk assertions |
| Fast throttle, dead zone, hysteresis, attack/release | Before-new-GPS launch regression; asymmetric release/lift regression; noise rejection regression |
| Nonnegative integrated prediction | Five-second motion-only dropout and negative-speed clamp regressions |
| Validated direct GPS speed; gradual correction | Existing invalid/out-of-order/accuracy checks; new convergence and returning-GPS no-snap regressions |
| Extended GPS dropout | Fresh motion remains active; bounded heuristic uncertainty and decaying acceleration influence; both-sensors-missing hold/decay regressions |
| Engine inertia, throttle transient and shift response | Existing idle/limiter/shift/kickdown/anti-hunting tests; new sensor-to-engine attack and early overrun regressions |
| Fast audio path independent of GPS/load convergence | Audio attack regression with zero engine load; clocked sensor-controller-to-mixer regression within 80 ms |
| Continuous AVAudioEngine, preloaded assets and route handling | Existing device playback, offline render, interruption/reconnect/media-reset tests; RPM does not restart loops |
| Vehicle telemetry and Developer tuning persistence | Current state fields/UI; all eight nondefault settings survive controller relaunch; old JSON loads new defaults |
| Ten-second graph | Bounded 200-point 20 Hz regression and interactive five-trace rendering verification |
| CSV export | Existing-column order retained, 17-column populated export checked against disk; interactive export reached “CSV ready” |
| Four latency replays and preserved Simulation | 50 Hz motion / 1 Hz GPS runner regressions, no-snap/dropout checks, scenario determinism/final idle, manual handoff regression |
| No new CAN/complex fusion/heavy dependency | Input-provider interface and unchanged transmission; pure Swift filters/models; original framework-only dependency set |
| Physical road perceptual response | **Pending user driving evaluation**; software timing does not prove phone-to-speaker latency |

## Reproduce

Run the full Xcode test scheme on an iOS simulator. `bash Scripts/test-controller.sh`
runs portable regressions on macOS (physical-device tests skip there). For physical
verification, use the connected iPhone as the test destination and run
`LatencyEstimatorTests/testPhysicalDeviceMotionDeliveryAndStationaryEstimator` plus
`AudioTests/testDevicePlaybackSessionStaysRunningAcrossRPMChanges`. Unlock the phone
first and keep it securely resting. These checks do not require driving or calibration
of the actual car.

For a road evaluation, calibrate the secured mount, start with the phone speaker and
zero latency compensation, and have a passenger observe acceleration/lift response.
Compare GPS versus predicted speed and export a short CSV. Bluetooth, road vibration,
mount movement, phone scheduling and time-pitch/output buffering remain measurable
sources of delay; an indoor/control-model test cannot validate all of them.

## Current verification results (2026-10-04)

- Complete native simulator scheme: 97 passed, 1 physical-device-only test skipped.
- Latest lift/audio follow-up: 40 passed, 1 physical-device-only test skipped.
- Latest signed iPhone build: succeeded.
- Interactive Mac Catalyst: GPS-lag scenario completed and returned to idle; five
  10-second graphs rendered; 51-row CSV export reached the share-ready state;
  Real Drive onboarding remained available.
- Physical iPhone 13: build/signing succeeded, but Xcode could not launch tests
  because the device was locked. Actual motion-delivery/audio checks remain
  unverified until the phone is unlocked and the tests are rerun.
- Road perceptual latency: pending user evaluation with a secured mount.
