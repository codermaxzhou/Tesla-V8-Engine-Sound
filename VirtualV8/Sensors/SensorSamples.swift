import Foundation

// All sample times are seconds since Unix epoch. Motion uptime is converted at acquisition.
struct LocationSample: Sendable {
    var speedKmh: Double
    var timestamp: TimeInterval
    var horizontalAccuracy: Double
    var speedAccuracy: Double
}

struct SensorVector: Sendable {
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
}

enum ApplicationInputMode: String, CaseIterable, Identifiable {
    case simulation = "Simulation"
    case realDrive = "Real Drive"
    var id: String { rawValue }
}

struct EstimatorTuning: Codable, Equatable {
    var throttleSensitivity = 1.0
    // Exponential filter time constants in seconds (larger means smoother).
    var accelerationSmoothing = 0.3
    var speedSmoothing = 0.8
    var throttleSmoothing = 0.4
    var stoppedSpeedKmh = 2.5
    var stoppedDuration = 1.5
    var gpsHoldDuration = 3.0
}
