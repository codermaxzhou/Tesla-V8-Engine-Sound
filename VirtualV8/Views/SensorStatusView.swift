import SwiftUI

struct SensorStatusView: View {
    let controller: SimulationController
    private var sensors: SensorInputController { controller.sensors }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !sensors.sensorsEnabled {
                Text("Location provides ground speed and its accuracy. Motion estimates acceleration and throttle lift. Pedal position is an approximation; no vehicle connection is required.")
                Text("Sensor data stays in memory on this device. No route is stored or uploaded. Access is used only while the app is in the foreground.")
                Text("Secure the phone before driving. The forward direction is learned during straight acceleration or braking; GPS is used until calibration is ready. Have a passenger operate controls on the road.")
                Button("Enable Real Drive Sensors", systemImage: "location") { controller.enablePhoneInput() }
                    .buttonStyle(.borderedProminent)
            } else {
                LabeledContent("GPS", value: sensors.gpsStatus)
                LabeledContent("Location permission", value: sensors.locationManager.permissionLabel)
                LabeledContent("Motion", value: sensors.motionAvailable ? "Available" : sensors.motionManager.status)
                LabeledContent("Location accuracy", value: sensors.estimator.location.map { String(format: "±%.0f m", $0.horizontalAccuracy) } ?? "—")
                LabeledContent("Forward direction", value: sensors.estimator.forwardAxis == nil ? "Learning — GPS acceleration" : "Calibrated")
                if let error = sensors.locationManager.errorMessage { Text(error).foregroundStyle(.secondary) }
                Button("Disable Sensors") { controller.disablePhoneInput() }
            }
            LabeledContent("Audio", value: controller.audio.isActive ? "Running" : "Stopped")
        }
        .font(.subheadline)
    }
}

struct SensorTelemetryView: View {
    let sensors: SensorInputController
    var body: some View {
        let estimator = sensors.estimator
        LabeledContent("GPS", value: sensors.gpsStatus)
        LabeledContent("Motion", value: sensors.motionAvailable ? "Available" : sensors.motionManager.status)
        LabeledContent("Raw GPS speed", value: estimator.location.map { String(format: "%.2f km/h", $0.speedKmh) } ?? "—")
        LabeledContent("GPS timestamp", value: estimator.location.map { String(format: "%.3f", $0.timestamp) } ?? "—")
        LabeledContent("Accuracy", value: estimator.location.map { String(format: "±%.1f m / ±%.2f m/s", $0.horizontalAccuracy, $0.speedAccuracy) } ?? "—")
        LabeledContent("Filtered speed", value: String(format: "%.2f km/h", estimator.state.speedKmh))
        LabeledContent("Raw acceleration", value: String(format: "%.3f m/s²", estimator.rawAcceleration))
        LabeledContent("Filtered acceleration", value: String(format: "%.3f m/s²", estimator.state.smoothedAccelerationMs2))
        LabeledContent("Jerk", value: String(format: "%.3f m/s³", estimator.state.jerkMs3))
        LabeledContent("Estimated throttle", value: String(format: "%.3f", estimator.state.estimatedThrottle))
        LabeledContent("Lift detected", value: estimator.didDetectLift ? "Yes" : "No")
        LabeledContent("Rejected GPS / motion", value: "\(estimator.rejectedLocationCount) / \(estimator.rejectedMotionCount)")
        if let motion = estimator.motion {
            LabeledContent("Motion timestamp", value: String(format: "%.3f", motion.timestamp))
            LabeledContent("User acceleration (device)", value: vector(motion.userAcceleration))
            LabeledContent("Gravity (g)", value: vector(motion.gravity))
        }
    }
    private func vector(_ v: SensorVector) -> String { String(format: "%.2f, %.2f, %.2f", v.x, v.y, v.z) }
}
