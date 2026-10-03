import Foundation
import Observation
#if os(iOS)
import CoreMotion
#endif

@MainActor @Observable final class MotionManager {
    private(set) var isSampling = false
    private(set) var status = "Not started"
    @ObservationIgnored private var generation = 0
    @ObservationIgnored var onSample: ((MotionSample) -> Void)?
    #if os(iOS)
    @ObservationIgnored private let manager = CMMotionManager()
    #endif

    var isAvailable: Bool {
        #if os(iOS)
        manager.isDeviceMotionAvailable
        #else
        false
        #endif
    }

    func start() {
        guard !isSampling else { return }
        #if os(iOS)
        guard manager.isDeviceMotionAvailable else { status = "Unavailable on this device"; return }
        // Device-motion access is initiated here, after the in-app explanation. No
        // unrelated motion-activity/pedometer permission is requested.
        manager.deviceMotionUpdateInterval = 1.0 / 50
        let epochOffset = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        generation += 1
        let generation = generation
        isSampling = true
        status = "Waiting for motion"
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            if let error {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.isSampling, self.generation == generation else { return }
                    self.stop()
                    self.status = "Motion unavailable: \(message)"
                }
                return
            }
            guard let motion else { return }
            let a = motion.userAcceleration
            let g = motion.gravity
            let r = motion.attitude.rotationMatrix
            // Attitude maps reference coordinates to device coordinates. Its transpose
            // maps measured acceleration back into the gravity-aligned reference frame.
            let horizontal = SensorVector(x: (r.m11 * a.x + r.m21 * a.y + r.m31 * a.z) * 9.80665,
                                          y: (r.m12 * a.x + r.m22 * a.y + r.m32 * a.z) * 9.80665, z: 0)
            let rotation = motion.rotationRate
            let sample = MotionSample(userAcceleration: SensorVector(x: a.x * 9.80665, y: a.y * 9.80665, z: a.z * 9.80665),
                                        gravity: SensorVector(x: g.x, y: g.y, z: g.z),
                                        horizontalAcceleration: horizontal,
                                        rotationRate: sqrt(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z),
                                        timestamp: epochOffset + motion.timestamp)
            Task { @MainActor [weak self] in
                guard let self, self.isSampling, self.generation == generation else { return }
                self.status = "Available"
                self.onSample?(sample)
            }
        }
        #else
        status = "Unavailable on this device"
        #endif
    }

    func stop() {
        generation += 1
        #if os(iOS)
        manager.stopDeviceMotionUpdates()
        #endif
        isSampling = false
        status = "Not started"
    }
}
