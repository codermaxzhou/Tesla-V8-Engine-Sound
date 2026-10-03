# Phase 7 design: direct vehicle data

Design only. There is no CAN communication, adapter discovery, Tesla decoding, or CAN provider implementation in this MVP.

## Provider seam

`VehicleInputProvider` is the main-actor interface consumed by `SimulationController`. Its `currentState`, `update(deltaTime:)`, start/stop and foreground hooks separate acquisition from the powertrain. `didDetectLift` carries a source-independent transition hint. The initializer accepts an injected provider so recorded frames can exercise the full drivetrain/audio/logger pipeline without sensors or hardware.

A future `CANVehicleInputProvider: VehicleInputProvider` would own:

1. A read-only, separately permissioned transport adapter (hardware/vendor to be selected).
2. A vehicle-specific frame decoder producing timestamped value samples.
3. Unit conversion, validity bounds, freshness checks, disconnect status and hold/decay policy.
4. A main-actor state adapter providing the existing `VehicleState` in km/h, m/s² and normalized pedal/brake units.

Transport work and decoding run off the main actor. Only immutable, validated samples cross to the provider actor. One selected provider owns input acquisition at a time. Start/stop are idempotent, stale callbacks must be rejected after source switches, and foreground changes stop acquisition unless a later, explicit background design is approved.

## Potential data mapping

| Vehicle datum | Mapping / policy |
| --- | --- |
| True accelerator position | Normalized `VehicleState.estimatedThrottle`; the legacy name remains compatible, but diagnostics/log metadata must identify it as measured rather than estimated |
| Vehicle speed | `speedKmh`; derive/filter acceleration and jerk from timestamped speeds where needed |
| Brake state/pressure | `brakeInput`; binary state can be mapped to a documented normalized value |
| Drive mode | Optional source metadata; map to Comfort/Sport/Track only through an explicit user preference, preserving manual presets |
| Motor torque | Optional typed metadata/diagnostic field; do not equate EV motor torque with combustion-engine RPM |
| Other useful vehicle data | Extend a source metadata/capabilities envelope without making the engine/audio depend on Tesla frames |

Distinguish unavailable fields from actual zero values. Do not invent true pedal/torque information from missing frames. Use receive time plus source timestamps where available; reject nonfinite, out-of-range, duplicate, out-of-order and stale data. Report source quality/freshness separately from the numeric vehicle state. Clear pedal/brake requests safely on disconnect, reconcile speed gradually, and make fallback selection explicit. Never silently switch from measured pedal input to estimated phone input while retaining old state.

## Incremental roadmap

1. Define hardware/transport and validated vehicle-specific schemas; add captured-frame replay fixtures and decoder tests before accessing a car.
2. Implement the read-only transport and decoder as separate modules. Test permission denial, wrong vehicle/schema, reconnect, delayed/out-of-order frames and missing signals.
3. Add the CAN provider and input selection/status UI. Inject it through the existing provider seam; disable the phone acquisition path while it is selected. Sensor mode remains a fallback chosen by the user, and Simulation remains available for regression testing.
4. Add source/capability metadata to diagnostics and versioned CSV export so measured versus estimated values can be distinguished. Preserve existing CSV fields or provide an explicit schema migration.
5. Validate first with recordings, then stationary hardware, then passenger-supervised road evaluation. Keep communication read-only: no vehicle actuation or write commands.

## What changes and what stays

The **Real Drive input adapter** can be replaced by the CAN provider. Core Location/Core Motion and `VehicleStateEstimator` are bypassed for authoritative pedal/speed/brake fields; they remain intact for Phone Sensor mode and may supply clearly identified missing fields only under a later, tested policy. Mode selection, provider diagnostics and source metadata expand.

`VirtualEngine`, `VirtualTransmission`, `AudioMixModel`, `BackfireController`, `EngineAudioEngine`, tachometer/driving dashboard, calibration presets, deterministic scenarios and the existing logger's sampling pipeline remain in place. The coordination loop still processes `VehicleState` at 60 Hz, independent of the transport or decoder. Audio route/latency handling is independent of vehicle-data access.
