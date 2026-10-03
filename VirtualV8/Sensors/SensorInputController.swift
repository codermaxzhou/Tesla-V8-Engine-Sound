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
        estimator = VehicleStateEstimator()
        gpsStatus = "Not started"; motionAvailable = false
    }

    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value
        if !value {
            locationManager.stop(); motionManager.stop()
            estimator = VehicleStateEstimator()
            gpsStatus = "Paused"; motionAvailable = false
        } else if sensorsEnabled { locationManager.start(); motionManager.start() }
    }

    // Also used by deterministic indoor tests; these do not open hardware or permissions.
    func ingest(location: LocationSample, now: TimeInterval) { estimator.ingest(location: location, now: now) }
    func ingest(motion: MotionSample, now: TimeInterval) { estimator.ingest(motion: motion, now: now) }
    func resetCalibration() { estimator.resetCalibration() }

    func update(deltaTime: Double, now: TimeInterval = Date().timeIntervalSince1970) -> VehicleState {
        guard foreground else { return estimator.state }
        estimator.tuning = tuning
        let state = estimator.update(now: now, deltaTime: deltaTime)
        gpsStatus = estimator.gpsStatus(now: now)
        motionAvailable = estimator.motion.map { now - $0.timestamp <= 0.25 } ?? false
        return state
    }
}
