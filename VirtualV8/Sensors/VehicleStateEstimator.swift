import Foundation

// Pure complementary estimator: motion drives transients; GPS corrects the speed reference.
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
    private(set) var calibration = OrientationCalibration()
    private(set) var didDetectLift = false
    private(set) var motionFrequencyHz = 0.0
    private(set) var gpsAge = Double.infinity
    private(set) var motionAge = Double.infinity
    private(set) var speedUncertaintyMs = 0.0
    private(set) var predictedSpeedMs = 0.0
    private var motionAverage = SensorVector(x: 0, y: 0, z: 0)
    private var filteredAcceleration = 0.0
    private var filteredJerk = 0.0
    private var throttleEstimator = ThrottleEstimator()
    private var lowSpeedDuration = 0.0
    private var stopped = true

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
            // Automatic sign learning remains as a fallback. Explicit calibration provides
            // the multi-second direction estimate and can operate without a new GPS fix.
            let magnitude = motionAverage.magnitude
            if forwardAxis == nil, !calibration.isCollecting, dt <= 2,
               abs(gpsAcceleration) > 0.4, magnitude > 0.4,
               abs(magnitude - abs(gpsAcceleration)) < 1.5,
               let motion, now - motion.timestamp < 0.3 {
                let sign = gpsAcceleration > 0 ? 1.0 : -1.0
                forwardAxis = SensorVector(x: sign * motionAverage.x / magnitude,
                                          y: sign * motionAverage.y / magnitude,
                                          z: sign * motionAverage.z / magnitude)
                calibration.markCalibrated()
            }
        } else if predictedSpeedMs == 0 {
            // Bootstrap the first absolute speed anchor. Subsequent fixes never snap speed.
            predictedSpeedMs = sample.speedKmh / 3.6
            stopped = sample.speedKmh < tuning.stoppedSpeedKmh
        }
        location = sample
    }

    mutating func ingest(motion sample: MotionSample, now: TimeInterval) {
        guard sample.timestamp.isFinite, now.isFinite,
              (-0.1...0.5).contains(now - sample.timestamp),
              sample.userAcceleration.isFinite, sample.gravity.isFinite,
              sample.horizontalAcceleration.isFinite, sample.rotationRate.isFinite,
              sample.attitude.map({ $0.roll.isFinite && $0.pitch.isFinite && $0.yaw.isFinite }) ?? true,
              sample.userAcceleration.magnitude <= 12,
              (0.8...1.2).contains(sample.gravity.magnitude), sample.rotationRate < 1.5,
              motion == nil || sample.timestamp > motion!.timestamp else {
            rejectedMotionCount += 1; return
        }
        let dt = motion.map { min(0.1, sample.timestamp - $0.timestamp) } ?? 0.02
        let frequency = 1 / max(0.001, dt)
        motionFrequencyHz += (frequency - motionFrequencyHz) * 0.2
        let horizontal = sample.horizontalDeviceAcceleration
        let averageAlpha = sensorBlend(0.1, deltaTime: dt)
        motionAverage.x += (horizontal.x - motionAverage.x) * averageAlpha
        motionAverage.y += (horizontal.y - motionAverage.y) * averageAlpha
        motionAverage.z += (horizontal.z - motionAverage.z) * averageAlpha
        if let axis = calibration.ingest(sample, gpsAcceleration: gpsAcceleration) { forwardAxis = axis }
        motion = sample
        // Fallback assumes the phone's upper edge points forward. Project out gravity so
        // tilted portrait/landscape mounts can still be calibrated in three dimensions.
        let axis = forwardAxis ?? SensorVector(x: 0, y: 1, z: 0)
        let projected = horizontal.x * axis.x + horizontal.y * axis.y + horizontal.z * axis.z
        let safe = location == nil && forwardAxis == nil ? 0 : projected
        filterAcceleration(safe, dt: dt)
    }

    mutating func restoreForwardAxis(_ axis: SensorVector?) {
        guard let axis, axis.isFinite, axis.magnitude > 0.9, axis.magnitude < 1.1 else { return }
        forwardAxis = axis
        calibration.markCalibrated()
    }
    mutating func beginCalibration() { calibration.start() }
    mutating func resetCalibration() { forwardAxis = nil; calibration.reset() }

    func gpsStatus(now: TimeInterval) -> String {
        guard let location else { return "Waiting for valid speed" }
        let age = now - location.timestamp
        if age <= tuning.gpsHoldDuration { return "Available" }
        return age <= tuning.gpsHoldDuration + 2 ? "Signal lost — holding" : "Signal lost — predicting"
    }

    private mutating func filterAcceleration(_ acceleration: Double, dt: Double) {
        rawAcceleration = max(-8, min(8, acceleration))
        let previous = filteredAcceleration
        filteredAcceleration += (rawAcceleration - previous) * sensorBlend(tuning.accelerationSmoothingAlpha, deltaTime: dt)
        let jerk = max(-40, min(40, (filteredAcceleration - previous) / max(0.001, dt)))
        filteredJerk += (jerk - filteredJerk) * sensorBlend(tuning.jerkSmoothingAlpha, deltaTime: dt)
    }

    mutating func update(now: TimeInterval, deltaTime dt: Double) -> VehicleState {
        guard now.isFinite, dt.isFinite, dt > 0, dt <= 0.25 else { return state }
        gpsAge = location.map { max(0, now - $0.timestamp) } ?? .infinity
        let gpsFresh = gpsAge <= tuning.gpsHoldDuration
        motionAge = motion.map { max(0, now - $0.timestamp) } ?? .infinity
        let motionFresh = motionAge <= 0.25
        if !motionFresh {
            // GPS acceleration is a degraded fallback, never the gate for fresh motion.
            filterAcceleration(gpsFresh ? gpsAcceleration : 0, dt: dt)
        }
        let acceleration = abs(filteredAcceleration) < tuning.accelerationDeadZone ? 0 : filteredAcceleration
        let trust = gpsFresh ? 1 : exp(-max(0, gpsAge - 15) / 20)
        // With a calibrated axis but no GPS yet, allow a guided motion-only launch.
        let integrationTrust = location == nil ? (forwardAxis == nil ? 0.0 : 1.0) : trust
        predictedSpeedMs += acceleration * dt * integrationTrust
        if gpsFresh, let location {
            // Gain is per second, not per rendered frame. Accuracy weakens a poor fix.
            let confidence = 1 / max(1, location.speedAccuracy)
            let gain = min(0.25, max(0.03, tuning.gpsCorrectionGain)) * confidence
            let blend = 1 - pow(1 - gain, dt)
            predictedSpeedMs += (location.speedKmh / 3.6 - predictedSpeedMs) * blend
            speedUncertaintyMs += (location.speedAccuracy - speedUncertaintyMs) * blend
        } else {
            speedUncertaintyMs = min(50, speedUncertaintyMs + dt * 0.15)
            // Only decay when BOTH sensors have been absent for an extended interval.
            if !motionFresh, gpsAge > tuning.gpsHoldDuration + 2 {
                predictedSpeedMs -= 0.5 * dt
            }
        }
        predictedSpeedMs = max(0, min(250 / 3.6, predictedSpeedMs))
        let speed = predictedSpeedMs * 3.6
        let launching = motionFresh && rawAcceleration > max(0.4, tuning.accelerationDeadZone * 2)
        if launching || speed > tuning.stoppedSpeedKmh + 1 {
            stopped = false; lowSpeedDuration = 0
        } else if speed < tuning.stoppedSpeedKmh {
            lowSpeedDuration += dt
            if lowSpeedDuration >= tuning.stoppedDuration { stopped = true }
        } else { lowSpeedDuration = 0 }
        throttleEstimator.update(acceleration: filteredAcceleration, rawAcceleration: rawAcceleration,
                                 jerk: filteredJerk, speedKmh: speed, stationary: stopped, dt: dt, tuning: tuning)
        didDetectLift = throttleEstimator.didDetectLift
        let brakeTarget = stopped ? 0 : min(1, max(0, -filteredAcceleration - 0.25) / 5)
        let brake = state.brakeInput + (brakeTarget - state.brakeInput) * (1 - exp(-dt / 0.2))
        state = VehicleState(speedKmh: speed, accelerationMs2: rawAcceleration,
                             smoothedAccelerationMs2: filteredAcceleration, jerkMs3: filteredJerk,
                             estimatedThrottle: throttleEstimator.filteredThrottle, brakeInput: brake,
                             detectedStopped: stopped, gpsSpeedKmh: location?.speedKmh,
                             predictedSpeedKmh: speed, rawEstimatedThrottle: throttleEstimator.rawThrottle,
                             gpsSpeedAccuracy: location?.speedAccuracy, isGpsValid: gpsFresh,
                             didDetectThrottleLift: didDetectLift)
        return state
    }
}
