import SwiftUI

struct DeveloperView: View {
    let controller: SimulationController
    @State private var showHistory = false

    var body: some View {
        List {
            Section { NavigationLink("Diagnostics") { DiagnosticsView(controller: controller) }.disabled(!controller.canCalibrate) }
            Section("Calibration") { CalibrationControlsView(controller: controller) }
            Section("Drive Logging") { DriveLoggingView(controller: controller) }
            Section("Recent History") {
                Toggle("Show latency graphs", isOn: $showHistory).disabled(!controller.canCalibrate)
                if showHistory { DriveHistoryView(logger: controller.logger) }
            }
            Section("Live State") {
                LabeledContent("Raw throttle", value: String(format: "%.3f", controller.vehicle.rawEstimatedThrottle))
                LabeledContent("Brake", value: String(format: "%.3f", controller.vehicle.brakeInput))
                LabeledContent("Speed", value: String(format: "%.1f km/h", controller.vehicle.speedKmh))
                LabeledContent("Acceleration", value: String(format: "%.2f m/s²", controller.vehicle.accelerationMs2))
                LabeledContent("Current RPM", value: String(format: "%.0f", controller.engine.rpm))
                LabeledContent("Target RPM", value: String(format: "%.0f", controller.engine.targetRPM))
                LabeledContent("Engine throttle", value: String(format: "%.3f", controller.engine.throttle))
                LabeledContent("Load", value: String(format: "%.3f", controller.engine.load))
                LabeledContent("Current gear", value: "\(controller.transmission.currentGear)")
                LabeledContent("Target gear", value: "\(controller.transmission.targetGear)")
                LabeledContent("Engine mode", value: controller.operatingMode.label)
                LabeledContent("Shift state", value: controller.transmission.isShifting ? controller.transmission.shiftType.rawValue : "none")
                LabeledContent("Shift progress", value: "\(Int(controller.transmission.shiftProgress * 100))%")
                LabeledContent("Limiter", value: controller.engine.isOnLimiter ? "Active" : "Inactive")
                LabeledContent("Vehicle", value: controller.vehicle.isStopped ? "Stopped" : controller.vehicle.isAccelerating ? "Accelerating" : controller.vehicle.isDecelerating ? "Decelerating" : "Cruising")
            }
            Section("Sensors & Estimator") {
                LabeledContent("Input mode", value: controller.inputMode.rawValue)
                SensorTelemetryView(sensors: controller.sensors, inputEstimator: controller.inputEstimator)
            }
            Section("Other Sensor Settings") {
                DisclosureGroup("Orientation & stopped detection") {
                    SensorTuningView(sensors: controller.sensors)
                    Text("Secure the phone. Begin while parked, then gently accelerate straight. Collection starts at meaningful motion and takes 4 seconds. Have a passenger supervise; recalibrate after moving the mount.").font(.caption)
                    Text(controller.sensors.estimator.calibration.status).font(.caption)
                    Button("Calibrate Orientation") { controller.sensors.beginCalibration() }
                    Button("Reset Orientation") { controller.sensors.resetCalibration() }
                }.disabled(!controller.canCalibrate)
            }
            Section("Other Audio Controls") {
                AudioTuningView(audio: controller.audio, includeLayerControls: false).disabled(!controller.canCalibrate)
            }
            Section("Audio Layers") {
                LabeledContent("Audio engine", value: controller.audio.isActive ? "Running" : "Stopped")
                LabeledContent("Player starts", value: "\(controller.audio.startCount)")
                LabeledContent("Fallback samples", value: "\(controller.audio.fallbackAssets.count)")
                LabeledContent("Transient events", value: "\(controller.audio.transientCount)")
                ForEach(AudioLayer.allCases) { layer in
                    LabeledContent(layer.label, value: String(format: "%.3f", controller.audio.layerGains[layer, default: 0]))
                }
                if let error = controller.audio.errorMessage { Text(error).foregroundStyle(.red) }
            }
            Section("Recent Events") {
                ForEach(controller.events) { event in
                    HStack(alignment: .top) {
                        Text(event.timestamp, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
                        Text(event.message)
                    }.font(.caption.monospaced())
                }
            }
        }
        .navigationTitle("Developer / Calibration")
        .navigationBarTitleDisplayMode(.inline)
    }
}
