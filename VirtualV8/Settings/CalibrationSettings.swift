import Foundation
import Observation

struct EngineTuning: Codable, Equatable {
    var rpmResponse = 1.0
    var inertia = 1.0
}

struct TransmissionTuning: Codable, Equatable {
    // Larger aggressiveness holds higher RPM. Duration is a multiplier, latched per shift.
    var upshiftAggressiveness = 1.0
    var downshiftAggressiveness = 1.0
    var shiftDuration = 1.0
}

struct CalibrationValues: Codable, Equatable {
    var drivingMode = DrivingMode.comfort
    var engine = EngineTuning()
    var transmission = TransmissionTuning()
    var estimator = EstimatorTuning()
    var audio = AudioTuning()

    func bounded() -> Self {
        var value = self
        func limit(_ x: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            let clamped = x.isFinite ? min(range.upperBound, max(range.lowerBound, x)) : fallback
            // Match the displayed 0.01 resolution; Float-backed sliders must not turn an
            // unchanged named preset into Custom solely because of representation noise.
            return (clamped * 100).rounded() / 100
        }
        value.engine.rpmResponse = limit(engine.rpmResponse, 0.5...2, 1)
        value.engine.inertia = limit(engine.inertia, 0.5...2, 1)
        value.transmission.upshiftAggressiveness = limit(transmission.upshiftAggressiveness, 0.75...1.2, 1)
        value.transmission.downshiftAggressiveness = limit(transmission.downshiftAggressiveness, 0.75...1.3, 1)
        value.transmission.shiftDuration = limit(transmission.shiftDuration, 0.6...1.5, 1)
        value.estimator.throttleSensitivity = limit(estimator.throttleSensitivity, 0.5...1.5, 1)
        value.estimator.accelerationSmoothing = limit(estimator.accelerationSmoothing, 0.05...1.5, 0.3)
        value.estimator.throttleSmoothing = limit(estimator.throttleSmoothing, 0.1...1.5, 0.4)
        value.estimator.speedSmoothing = limit(estimator.speedSmoothing, 0.1...2, 0.8)
        value.estimator.stoppedSpeedKmh = limit(estimator.stoppedSpeedKmh, 1...3, 2.5)
        value.estimator.stoppedDuration = limit(estimator.stoppedDuration, 0.5...3, 1.5)
        value.estimator.gpsHoldDuration = limit(estimator.gpsHoldDuration, 1...5, 3)
        value.audio.masterVolume = limit(audio.masterVolume, 0...1, 0.45)
        value.audio.engineVolume = limit(audio.engineVolume, 0...1, 1)
        value.audio.intakeVolume = limit(audio.intakeVolume, 0...1, 0.5)
        value.audio.exhaustVolume = limit(audio.exhaustVolume, 0...1, 0.8)
        value.audio.backfireAmount = limit(audio.backfireAmount, 0...1, 0.5)
        value.audio.shiftTransientVolume = limit(audio.shiftTransientVolume, 0...1, 0.7)
        value.audio.audioLatencyCompensationMs = limit(audio.audioLatencyCompensationMs, 0...1000, 0)
        return value
    }
}

enum CalibrationPreset: String, CaseIterable, Identifiable, Codable {
    case comfort = "Comfort", sport = "Sport", track = "Track"
    var id: String { rawValue }
    var values: CalibrationValues {
        var values = CalibrationValues()
        switch self {
        case .comfort:
            values.drivingMode = .comfort
            values.audio.masterVolume = 0.35; values.audio.engineVolume = 0.75
            values.audio.backfireAmount = 0.08
            values.estimator.accelerationSmoothing = 0.5; values.estimator.throttleSmoothing = 0.6
            values.transmission.upshiftAggressiveness = 0.9
            values.transmission.downshiftAggressiveness = 0.9; values.transmission.shiftDuration = 1.1
            values.engine.rpmResponse = 0.85; values.engine.inertia = 1.2
        case .sport:
            values.drivingMode = .sport
            values.audio.masterVolume = 0.45; values.audio.engineVolume = 0.9
            values.audio.backfireAmount = 0.5; values.audio.intakeVolume = 0.65
            values.estimator.accelerationSmoothing = 0.25; values.estimator.throttleSmoothing = 0.3
            values.engine.rpmResponse = 1.2; values.engine.inertia = 0.9
            values.transmission.upshiftAggressiveness = 1.02
            values.transmission.downshiftAggressiveness = 1.15; values.transmission.shiftDuration = 0.9
        case .track:
            values.drivingMode = .track
            values.audio.masterVolume = 0.6; values.audio.exhaustVolume = 1
            values.audio.intakeVolume = 0.8; values.audio.backfireAmount = 0.8
            values.estimator.throttleSensitivity = 1.15
            values.estimator.accelerationSmoothing = 0.18; values.estimator.throttleSmoothing = 0.2
            values.engine.rpmResponse = 1.5; values.engine.inertia = 0.75
            values.transmission.upshiftAggressiveness = 1.1
            values.transmission.downshiftAggressiveness = 1.3; values.transmission.shiftDuration = 0.75
        }
        return values
    }
}

@MainActor @Observable final class CalibrationSettings {
    private(set) var values = CalibrationValues()
    private(set) var customValues = CalibrationValues()
    private(set) var preset: CalibrationPreset?
    private(set) var persistenceError: String?
    @ObservationIgnored private let defaults: UserDefaults?
    static let storageKey = "VirtualV8.calibration.v1"
    private struct Saved: Codable {
        var values: CalibrationValues
        var custom: CalibrationValues
        var preset: CalibrationPreset?
    }

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.storageKey) {
            if let saved = try? JSONDecoder().decode(Saved.self, from: data) {
                values = saved.values.bounded(); customValues = saved.custom.bounded(); preset = saved.preset
            } else { persistenceError = "Saved calibration could not be read. Using defaults." }
        }
    }
    func update(_ edit: (inout CalibrationValues) -> Void) {
        var changed = values
        edit(&changed)
        changed = changed.bounded()
        guard changed != values else { return }
        values = changed; customValues = changed; preset = nil
        save()
    }
    func apply(_ preset: CalibrationPreset) {
        self.preset = preset
        // A named preset never overwrites the last customized calibration.
        var selected = preset.values
        // Transport latency belongs to the route, not the driving style.
        selected.audio.audioLatencyCompensationMs = values.audio.audioLatencyCompensationMs
        values = selected.bounded()
        save()
    }
    func restoreCustom() { values = customValues; preset = nil; save() }
    private func save() {
        guard let defaults else { return }
        do {
            defaults.set(try JSONEncoder().encode(Saved(values: values, custom: customValues, preset: preset)), forKey: Self.storageKey)
            persistenceError = nil
        } catch { persistenceError = "Calibration could not be saved: \(error.localizedDescription)" }
    }
}
