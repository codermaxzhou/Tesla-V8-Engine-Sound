import Foundation
import Observation

@MainActor @Observable final class SensorInputController {
    let locationManager = LocationManager()
    let motionManager = MotionManager()
    var tuning = EstimatorTuning() { didSet { onTuningChange?(tuning) } }
    @ObservationIgnored var onTuningChange: ((EstimatorTuning) -> Void)?
    private(set) var estimator = VehicleStateEstimator()
    private(set) var sensorsEnabled = false
    private(set) var gpsStatus = "Not started"
    private(set) var motionAvailable = false
    @ObservationIgnored private var foreground = true

    @ObservationIgnored private var defaults: UserDefaults?
    private static let axisKey = "VirtualV8.orientation.deviceAxis.v1"
    func configurePersistence(_ defaults: UserDefaults?) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.axisKey), let axis = try? JSONDecoder().decode(SensorVector.self, from: data) {
            estimator.restoreForwardAxis(axis)
        }
    }
    private func clearSamples() {
        let axis = estimator.forwardAxis
        estimator = VehicleStateEstimator()
        estimator.restoreForwardAxis(axis)
    }

    init() {
        locationManager.onSample = { [weak self] sample in
            self?.ingest(location: sample, now: Date().timeIntervalSince1970)
        }
        motionManager.onSample = { [weak self] sample in
            self?.ingest(motion: sample, now: Date().timeIntervalSince1970)
        }
    }

    func enable() {
        sensorsEnabled = true
        if foreground { locationManager.start(); motionManager.start() }
    }

    func disable() {
        sensorsEnabled = false
        locationManager.stop(); motionManager.stop()
        clearSamples()
        gpsStatus = "Not started"; motionAvailable = false
    }

    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value
        if !value {
            locationManager.stop(); motionManager.stop()
            clearSamples()
            gpsStatus = "Paused"; motionAvailable = false
        } else if sensorsEnabled { locationManager.start(); motionManager.start() }
    }

    // Also used by deterministic indoor tests; these do not open hardware or permissions.
    func ingest(location: LocationSample, now: TimeInterval) {
        let prior = estimator.forwardAxis
        estimator.ingest(location: location, now: now)
        if estimator.forwardAxis != prior, let axis = estimator.forwardAxis,
           let data = try? JSONEncoder().encode(axis) { defaults?.set(data, forKey: Self.axisKey) }
    }
    func ingest(motion: MotionSample, now: TimeInterval) {
        let prior = estimator.forwardAxis
        estimator.tuning = tuning
        estimator.ingest(motion: motion, now: now)
        if estimator.forwardAxis != prior, let axis = estimator.forwardAxis,
           let data = try? JSONEncoder().encode(axis) { defaults?.set(data, forKey: Self.axisKey) }
    }
    func beginCalibration() { estimator.beginCalibration() }
    func resetCalibration() { estimator.resetCalibration(); defaults?.removeObject(forKey: Self.axisKey) }

    func update(deltaTime: Double, now: TimeInterval = Date().timeIntervalSince1970) -> VehicleState {
        guard foreground else { return estimator.state }
        estimator.tuning = tuning
        let state = estimator.update(now: now, deltaTime: deltaTime)
        gpsStatus = estimator.gpsStatus(now: now)
        motionAvailable = estimator.motion.map { now - $0.timestamp <= 0.25 } ?? false
        return state
    }
}
