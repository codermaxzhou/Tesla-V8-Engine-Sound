import SwiftUI

struct DiagnosticsView: View {
    let controller: SimulationController
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "Unknown") (\(info["CFBundleVersion"] as? String ?? "Unknown"))"
    }
    var body: some View {
        List {
            Section("Application") {
                LabeledContent("App version", value: version)
                LabeledContent("Engine profile", value: controller.profile.name)
                LabeledContent("Input", value: controller.inputMode.rawValue)
                LabeledContent("Lifecycle", value: controller.isForeground ? "Foreground" : "Paused")
                LabeledContent("Simulation frequency", value: "\(Int(controller.simulationFrequencyHz)) Hz fixed step")
            }
            Section("Audio") {
                LabeledContent("Audio engine status", value: controller.audio.status)
                LabeledContent("Audio route", value: controller.audio.routeDescription)
                LabeledContent("Actual I/O buffer", value: String(format: "%.1f ms", controller.audio.ioBufferDurationMs))
                LabeledContent("Reported output latency", value: String(format: "%.0f ms", controller.audio.outputLatencyMs))
                LabeledContent("Audio latency compensation", value: String(format: "%.0f ms", controller.audio.tuning.audioLatencyCompensationMs))
                LabeledContent("Audio RPM", value: String(format: "%.0f", controller.audio.compensatedRPM))
                Button("Retry / Resume Audio") { controller.audio.retryPlayback() }
                    .disabled(!controller.canCalibrate || !controller.engine.isRunning)
                Text("Speaker and Bluetooth use the system output route. Bluetooth delay varies by hardware. Compensation predicts continuous audio RPM only; shifts and unexpected throttle changes cannot be predicted.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Sensors") {
                LabeledContent("GPS status", value: controller.sensors.gpsStatus)
                LabeledContent("Location permission", value: controller.sensors.locationManager.permissionLabel)
                if let error = controller.sensors.locationManager.errorMessage { Text(error).foregroundStyle(.secondary) }
                LabeledContent("Motion status", value: controller.sensors.motionManager.status)
                LabeledContent("Motion available", value: controller.sensors.motionAvailable ? "Yes" : "No")
                LabeledContent("Location accuracy", value: controller.sensors.estimator.location.map {
                    String(format: "±%.0f m", $0.horizontalAccuracy)
                } ?? "No valid fix")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}
