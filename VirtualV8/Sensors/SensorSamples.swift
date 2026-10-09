import Foundation

// All sample times are seconds since Unix epoch. Motion uptime is converted at acquisition.
struct LocationSample: Sendable {
    var speedKmh: Double
    var timestamp: TimeInterval
    var horizontalAccuracy: Double
    var speedAccuracy: Double
}

struct SensorVector: Sendable, Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double
    var magnitude: Double { sqrt(x * x + y * y + z * z) }
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

struct MotionSample: Sendable {
    var userAcceleration: SensorVector // m/s², device coordinates
    var gravity: SensorVector // g, device coordinates
    var horizontalAcceleration: SensorVector // m/s², attitude reference coordinates
    var rotationRate: Double // rad/s; reject handling / mount movement
    var timestamp: TimeInterval
    var attitude: SensorAttitude? = nil
    // Remove vertical acceleration in device space; the calibrated axis follows the mount,
    // rather than a compass heading that becomes wrong as the car turns.
    var horizontalDeviceAcceleration: SensorVector {
        let g = gravity
        let dot = userAcceleration.x * g.x + userAcceleration.y * g.y + userAcceleration.z * g.z
        let norm = max(0.001, g.magnitude * g.magnitude)
        return SensorVector(x: userAcceleration.x - dot * g.x / norm,
                            y: userAcceleration.y - dot * g.y / norm,
                            z: userAcceleration.z - dot * g.z / norm)
    }
}

struct SensorAttitude: Sendable {
    var roll: Double
    var pitch: Double
    var yaw: Double
}

enum ApplicationInputMode: String, CaseIterable, Identifiable {
    case simulation = "Simulation"
    case realDrive = "Real Drive"
    var id: String { rawValue }
}

struct EstimatorTuning: Codable, Equatable {
    var throttleSensitivity = 1.0
    // Alpha values are specified at 50 Hz and converted using actual elapsed time.
    var accelerationSmoothingAlpha = 0.30
    var jerkSmoothingAlpha = 0.25
    var throttleAttackAlpha = 0.45
    var throttleReleaseAlpha = 0.20
    var gpsCorrectionGain = 0.10 // per second of fresh GPS reference
    var accelerationDeadZone = 0.12
    var jerkThreshold = 1.5
    var stoppedSpeedKmh = 2.5
    var stoppedDuration = 1.5
    var gpsHoldDuration = 3.0

    init() {}
    enum CodingKeys: String, CodingKey {
        case throttleSensitivity, accelerationSmoothingAlpha, jerkSmoothingAlpha
        case throttleAttackAlpha, throttleReleaseAlpha, gpsCorrectionGain
        case accelerationDeadZone, jerkThreshold, stoppedSpeedKmh, stoppedDuration, gpsHoldDuration
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        // Existing saved calibrations retain every supported field; new response controls
        // get low-latency defaults when loading the previous schema.
        throttleSensitivity = try c.decodeIfPresent(Double.self, forKey: .throttleSensitivity) ?? throttleSensitivity
        accelerationSmoothingAlpha = try c.decodeIfPresent(Double.self, forKey: .accelerationSmoothingAlpha) ?? accelerationSmoothingAlpha
        jerkSmoothingAlpha = try c.decodeIfPresent(Double.self, forKey: .jerkSmoothingAlpha) ?? jerkSmoothingAlpha
        throttleAttackAlpha = try c.decodeIfPresent(Double.self, forKey: .throttleAttackAlpha) ?? throttleAttackAlpha
        throttleReleaseAlpha = try c.decodeIfPresent(Double.self, forKey: .throttleReleaseAlpha) ?? throttleReleaseAlpha
        gpsCorrectionGain = try c.decodeIfPresent(Double.self, forKey: .gpsCorrectionGain) ?? gpsCorrectionGain
        accelerationDeadZone = try c.decodeIfPresent(Double.self, forKey: .accelerationDeadZone) ?? accelerationDeadZone
        jerkThreshold = try c.decodeIfPresent(Double.self, forKey: .jerkThreshold) ?? jerkThreshold
        stoppedSpeedKmh = try c.decodeIfPresent(Double.self, forKey: .stoppedSpeedKmh) ?? stoppedSpeedKmh
        stoppedDuration = try c.decodeIfPresent(Double.self, forKey: .stoppedDuration) ?? stoppedDuration
        gpsHoldDuration = try c.decodeIfPresent(Double.self, forKey: .gpsHoldDuration) ?? gpsHoldDuration
    }
}

func sensorBlend(_ alpha: Double, deltaTime: Double) -> Double {
    let bounded = alpha.isFinite ? min(0.99, max(0.001, alpha)) : 0.3
    return 1 - pow(1 - bounded, max(0, deltaTime) * 50)
}
