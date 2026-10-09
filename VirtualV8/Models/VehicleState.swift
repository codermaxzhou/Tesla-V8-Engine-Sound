import Foundation

struct VehicleState {
    var speedKmh: Double = 0
    var accelerationMs2: Double = 0
    var smoothedAccelerationMs2: Double = 0
    var jerkMs3: Double = 0
    var estimatedThrottle: Double = 0
    var brakeInput: Double = 0
    // nil preserves the original immediate manual-simulation stop behavior.
    var detectedStopped: Bool? = nil
    var gpsSpeedKmh: Double? = nil
    var predictedSpeedKmh: Double = 0
    var rawEstimatedThrottle: Double = 0
    var gpsSpeedAccuracy: Double? = nil // m/s, as reported by Core Location
    var isGpsValid = false
    var didDetectThrottleLift = false
    var rawLongitudinalAccelerationMs2: Double { accelerationMs2 }
    var filteredLongitudinalAccelerationMs2: Double { smoothedAccelerationMs2 }
    private var classificationAcceleration: Double { detectedStopped == nil ? accelerationMs2 : smoothedAccelerationMs2 }
    var isAccelerating: Bool { detectedStopped != true && classificationAcceleration > 0.05 }
    var isDecelerating: Bool { detectedStopped != true && classificationAcceleration < -0.05 }
    var isStopped: Bool { detectedStopped ?? (speedKmh < 0.1) }
}
