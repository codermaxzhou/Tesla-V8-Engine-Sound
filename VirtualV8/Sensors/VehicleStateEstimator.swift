import Foundation

// Pure, deterministic estimator. No framework objects, permissions, timers or UI.
struct VehicleStateEstimator {
    var tuning = EstimatorTuning()
    private(set) var state = VehicleState()
    private(set) var location: LocationSample?
    private(set) var motion: MotionSample?
    private(set) var gpsAcceleration = 0.0
    private(set) var rawAcceleration = 0.0
    private(set) var rejectedLocationCount = 0
    private(set) var rejectedMotionCount = 0
    private(set) var forwardAxis: SensorVector?
    private(set) var didDetectLift = false
    private var motionAverage = SensorVector(x: 0, y: 0, z: 0)
    private var speedMs = 0.0
    private var reconcilingSpeed = false
    private var lowSpeedDuration = 0.0
    private var stopped = true
    private var accelerating = false
    private var recentAcceleration = 0.0
    private var liftRemaining = 0.0
    private var hasUpdated = false

    mutating func ingest(location sample: LocationSample, now: TimeInterval) {
        guard now.isFinite, sample.timestamp.isFinite, sample.speedKmh.isFinite,
              (0...250).contains(sample.speedKmh), sample.horizontalAccuracy.isFinite,
              (0...80).contains(sample.horizontalAccuracy), sample.speedAccuracy.isFinite,
              (0...5).contains(sample.speedAccuracy),
              (-0.25...3).contains(now - sample.timestamp) else {
            rejectedLocationCount += 1; return
        }
        if let previous = location {
            let dt = sample.timestamp - previous.timestamp
            guard dt >= 0.15 else { rejectedLocationCount += 1; return }
            let acceleration = (sample.speedKmh - previous.speedKmh) / 3.6 / dt
            guard abs(acceleration) <= 8 else { rejectedLocationCount += 1; return }
            gpsAcceleration = dt <= 3 ? acceleration : 0
            if dt > tuning.gpsHoldDuration, abs(sample.speedKmh / 3.6 - speedMs) > 2 {
                reconcilingSpeed = true
            }
            // Learn a horizontal forward direction from signed GPS acceleration and the
            // recent motion average. No assumption about the phone's mounting angle.
            let magnitude = hypot(motionAverage.x, motionAverage.y)
            if dt <= 2, abs(gpsAcceleration) > 0.4, magnitude > 0.4,
               abs(magnitude - abs(gpsAcceleration)) < 1.5,
               let motion, now - motion.timestamp < 0.3 {
                let sign = gpsAcceleration > 0 ? 1.0 : -1.0
                let candidate = SensorVector(x: sign * motionAverage.x / magnitude,
                                             y: sign * motionAverage.y / magnitude, z: 0)
                if let axis = forwardAxis {
                    // Reject contradictory direction (turning or handling), rather than flip.
                    if axis.x * candidate.x + axis.y * candidate.y > 0.7 {
                        let x = axis.x * 0.9 + candidate.x * 0.1
                        let y = axis.y * 0.9 + candidate.y * 0.1
                        let length = hypot(x, y)
                        forwardAxis = SensorVector(x: x / length, y: y / length, z: 0)
                    }
                } else { forwardAxis = candidate }
            }
        } else {
            speedMs = sample.speedKmh / 3.6
            stopped = sample.speedKmh < tuning.stoppedSpeedKmh
        }
        location = sample
    }

    mutating func ingest(motion sample: MotionSample, now: TimeInterval) {
        guard sample.timestamp.isFinite, now.isFinite,
              (-0.1...0.5).contains(now - sample.timestamp),
              sample.userAcceleration.isFinite, sample.gravity.isFinite,
              sample.horizontalAcceleration.isFinite, sample.rotationRate.isFinite,
              sample.userAcceleration.magnitude <= 12,
              (0.8...1.2).contains(sample.gravity.magnitude), sample.rotationRate < 1.5,
              motion == nil || sample.timestamp > motion!.timestamp else {
            rejectedMotionCount += 1; return
        }
        let dt = motion.map { min(0.1, sample.timestamp - $0.timestamp) } ?? 0.02
        let alpha = blend(dt, timeConstant: 0.35)
        motionAverage.x += (sample.horizontalAcceleration.x - motionAverage.x) * alpha
        motionAverage.y += (sample.horizontalAcceleration.y - motionAverage.y) * alpha
        motion = sample
    }

    mutating func resetCalibration() { forwardAxis = nil }

    func gpsStatus(now: TimeInterval) -> String {
        guard let location else { return "Waiting for valid speed" }
        let age = now - location.timestamp
        if age <= tuning.gpsHoldDuration { return "Available" }
        return age <= tuning.gpsHoldDuration + 2 ? "Signal lost — holding" : "Signal lost — decaying"
    }

    mutating func update(now: TimeInterval, deltaTime dt: Double) -> VehicleState {
        guard now.isFinite, dt.isFinite, dt > 0, dt <= 0.25 else { return state }
        let gpsAge = location.map { max(0, now - $0.timestamp) } ?? .infinity
        let motionFresh = motion.map { now - $0.timestamp <= 0.25 } ?? false
        var acceleration = gpsAge <= tuning.gpsHoldDuration ? gpsAcceleration : 0
        if motionFresh, let axis = forwardAxis, let motion {
            let projected = motion.horizontalAcceleration.x * axis.x + motion.horizontalAcceleration.y * axis.y
            acceleration = projected
        }
        // No speed anchor means handheld motion cannot create a moving vehicle.
        if location == nil || gpsAge > tuning.gpsHoldDuration { acceleration = 0 }
        rawAcceleration = max(-8, min(8, acceleration))
        let priorAcceleration = state.smoothedAccelerationMs2
        let filtered = priorAcceleration + (rawAcceleration - priorAcceleration) * blend(dt, timeConstant: tuning.accelerationSmoothing)
        let jerk = hasUpdated ? max(-20, min(20, (filtered - priorAcceleration) / dt)) : 0
        hasUpdated = true

        if let location {
            if gpsAge <= tuning.gpsHoldDuration {
                // Integrate only within a small corridor around GPS. Motion supplies the
                // fast response; GPS bounds drift and provides the absolute speed anchor.
                speedMs += filtered * dt
                let gpsMs = location.speedKmh / 3.6
                let predicted = max(0, gpsMs + gpsAcceleration * min(gpsAge, 1))
                speedMs += (predicted - speedMs) * blend(dt, timeConstant: tuning.speedSmoothing)
                // After a long outage the new fix may be far from the decayed speed.
                // Reconcile through the filter before applying the local drift corridor.
                if reconcilingSpeed, abs(speedMs - gpsMs) <= 2 { reconcilingSpeed = false }
                if !reconcilingSpeed {
                    speedMs = max(max(0, gpsMs - 2), min(gpsMs + 2, speedMs))
                }
            } else if gpsAge > tuning.gpsHoldDuration + 2 {
                speedMs = max(0, speedMs - 0.5 * dt)
            }
        }
        speedMs = max(0, min(250 / 3.6, speedMs))
        let speedKmh = speedMs * 3.6
        if speedKmh < tuning.stoppedSpeedKmh {
            lowSpeedDuration += dt
            if lowSpeedDuration >= tuning.stoppedDuration { stopped = true }
        } else {
            lowSpeedDuration = 0
            if speedKmh > tuning.stoppedSpeedKmh + 1 { stopped = false }
        }
        recentAcceleration += (max(0, filtered) - recentAcceleration) * blend(dt, timeConstant: 0.8)
        didDetectLift = !stopped && recentAcceleration > 1.2 && rawAcceleration < 0.15 && state.estimatedThrottle > 0.35
        if didDetectLift { liftRemaining = 0.6 }
        liftRemaining = max(0, liftRemaining - dt)
        if filtered > 0.3 { accelerating = true }
        if filtered < 0.12 { accelerating = false }
        var targetThrottle = accelerating ? max(0, filtered - 0.12) / 4 : 0
        if accelerating { targetThrottle += max(0, jerk) * 0.008 + min(0.06, speedKmh / 2000) }
        if stopped || liftRemaining > 0 || gpsAge > tuning.gpsHoldDuration { targetThrottle = 0 }
        targetThrottle = min(1, targetThrottle * tuning.throttleSensitivity)
        let throttleTime = liftRemaining > 0 ? 0.08 : tuning.throttleSmoothing
        let throttle = state.estimatedThrottle + (targetThrottle - state.estimatedThrottle) * blend(dt, timeConstant: throttleTime)
        let brakeTarget = stopped ? 0 : min(1, max(0, -filtered - 0.25) / 5)
        let brake = state.brakeInput + (brakeTarget - state.brakeInput) * blend(dt, timeConstant: 0.2)
        state = VehicleState(speedKmh: speedKmh, accelerationMs2: rawAcceleration,
                             smoothedAccelerationMs2: filtered, jerkMs3: jerk,
                             estimatedThrottle: stopped ? 0 : throttle, brakeInput: brake,
                             detectedStopped: stopped)
        return state
    }

    private func blend(_ dt: Double, timeConstant: Double) -> Double {
        1 - exp(-dt / max(0.02, timeConstant.isFinite ? timeConstant : 0.3))
    }
}
