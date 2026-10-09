import Foundation

/// Pedal-like envelope from IMU measurements. No GPS gate and no hardware/UI dependencies.
struct ThrottleEstimator {
    private(set) var rawThrottle = 0.0
    private(set) var filteredThrottle = 0.0
    private(set) var didDetectLift = false
    private var accelerating = false
    private var recentAcceleration = 0.0
    private var liftRemaining = 0.0

    mutating func update(acceleration: Double, rawAcceleration: Double, jerk: Double,
                         speedKmh: Double, stationary: Bool, dt: Double, tuning: EstimatorTuning) {
        let deadZone = tuning.accelerationDeadZone
        // A real launch can leave the stopped latch before GPS catches up. Vibration below
        // the transient threshold cannot open this gate.
        let launch = rawAcceleration > max(0.4, deadZone * 2)
        didDetectLift = recentAcceleration > 1.2 && rawAcceleration < deadZone
            && filteredThrottle > 0.35 && liftRemaining <= 0
        if didDetectLift { liftRemaining = 0.25 }
        liftRemaining = max(0, liftRemaining - dt)
        recentAcceleration += (max(0, acceleration) - recentAcceleration) * (1 - exp(-dt / 0.6))
        if acceleration > deadZone + 0.08 { accelerating = true }
        if acceleration < deadZone { accelerating = false }
        rawThrottle = accelerating ? max(0, acceleration - deadZone) / 4 : 0
        if accelerating, rawAcceleration > max(0.4, deadZone * 2), jerk > tuning.jerkThreshold {
            rawThrottle += min(0.18, (jerk - tuning.jerkThreshold) * 0.01)
        }
        if accelerating { rawThrottle += min(0.04, max(0, speedKmh) / 2500) }
        if (stationary && !launch) || liftRemaining > 0 { rawThrottle = 0 }
        rawThrottle = min(1, max(0, rawThrottle * tuning.throttleSensitivity))
        let alpha = rawThrottle > filteredThrottle ? tuning.throttleAttackAlpha : tuning.throttleReleaseAlpha
        filteredThrottle += (rawThrottle - filteredThrottle) * sensorBlend(alpha, deltaTime: dt)
        if filteredThrottle < 0.001 { filteredThrottle = 0 }
    }
}
