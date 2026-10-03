import Foundation

/// Bounded control-rate look-ahead for continuous audio, never for drivetrain decisions.
/// This cannot remove Bluetooth transport latency or predict future pedal/shift events.
struct AudioLatencyCompensator {
    let configuration = EngineProfile.americanV8
    private var previousRPM: Double?
    mutating func reset() { previousRPM = nil }
    mutating func rpm(for engine: EngineState, milliseconds: Double, deltaTime: Double) -> Double {
        guard engine.isRunning, engine.rpm.isFinite, deltaTime.isFinite, deltaTime > 0 else {
            reset(); return 0
        }
        let rpm = min(configuration.hardLimiterRPM, max(configuration.idleRPM, engine.rpm))
        defer { previousRPM = rpm }
        guard let previousRPM else { return rpm }
        let seconds = milliseconds.isFinite ? min(1000, max(0, milliseconds)) / 1000 : 0
        let rate = min(4000, max(-4000, (rpm - previousRPM) / deltaTime))
        let lead = min(1200, max(-1200, rate * seconds))
        return min(configuration.hardLimiterRPM, max(configuration.idleRPM, rpm + lead))
    }
}
