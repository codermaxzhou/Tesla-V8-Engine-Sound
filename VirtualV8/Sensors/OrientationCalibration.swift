import Foundation

/// Collect several seconds of straight acceleration. Horizontal vectors are in device
/// coordinates so a saved mount axis remains correct through turns and new motion sessions.
struct OrientationCalibration {
    private(set) var isCollecting = false
    private(set) var status = "Fallback mount axis — calibrate for best response"
    private var startedAt: Double?
    private var vectors: [SensorVector] = []
    mutating func start() {
        isCollecting = true; startedAt = nil; vectors.removeAll(keepingCapacity: true)
        status = "Collecting: accelerate gently in a straight line for 4 seconds"
    }
    mutating func ingest(_ sample: MotionSample, gpsAcceleration: Double) -> SensorVector? {
        guard isCollecting else { return nil }
        let v = sample.horizontalDeviceAcceleration
        if startedAt == nil, v.magnitude > 0.4 { startedAt = sample.timestamp }
        guard let startedAt else { return nil }
        if v.magnitude > 0.4, sample.rotationRate < 0.5 {
            // GPS resolves the acceleration/braking sign when available. Without a reliable
            // signed reference the guided procedure requires acceleration, not braking.
            let sign = gpsAcceleration < -0.4 ? -1.0 : 1.0
            vectors.append(SensorVector(x: v.x * sign, y: v.y * sign, z: v.z * sign))
        }
        guard sample.timestamp - startedAt >= 4 else { return nil }
        isCollecting = false
        guard vectors.count >= 25 else { status = "Not enough acceleration — retry straight acceleration"; return nil }
        // Power iteration on the 3D covariance finds the dominant horizontal mount direction.
        var axis = vectors[0]
        for _ in 0..<12 {
            var next = SensorVector(x: 0, y: 0, z: 0)
            for v in vectors {
                let dot = v.x * axis.x + v.y * axis.y + v.z * axis.z
                next.x += dot * v.x; next.y += dot * v.y; next.z += dot * v.z
            }
            let length = next.magnitude
            guard length > 0.001 else { status = "Direction unclear — retry"; return nil }
            axis = SensorVector(x: next.x / length, y: next.y / length, z: next.z / length)
        }
        let total = vectors.reduce(0) { $0 + $1.magnitude * $1.magnitude }
        let along = vectors.reduce(0) { sum, v in
            let dot = v.x * axis.x + v.y * axis.y + v.z * axis.z
            return sum + dot * dot
        }
        guard along / max(0.001, total) > 0.85 else { status = "Mixed directions — retry a straight segment"; return nil }
        let signed = vectors.reduce(0) { $0 + $1.x * axis.x + $1.y * axis.y + $1.z * axis.z }
        if signed < 0 { axis = SensorVector(x: -axis.x, y: -axis.y, z: -axis.z) }
        status = "Calibrated — recalibrate after moving the phone"
        return axis
    }
    mutating func markCalibrated() { status = "Calibrated — recalibrate after moving the phone" }
    mutating func reset() { self = Self() }
}
