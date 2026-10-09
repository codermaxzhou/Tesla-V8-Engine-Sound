import SwiftUI

struct CalibrationControlsView: View {
    let controller: SimulationController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !controller.canCalibrate { Text("Configure engine parameters while parked.").foregroundStyle(.orange) }
            Picker("Calibration preset", selection: Binding(
                get: { controller.calibration.preset?.rawValue ?? "Custom" },
                set: { name in
                    if let preset = CalibrationPreset(rawValue: name) { controller.applyPreset(preset) }
                    else { controller.restoreCustomCalibration() }
                })) {
                Text("Custom").tag("Custom")
                ForEach(CalibrationPreset.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }.pickerStyle(.segmented)
            control("Throttle sensitivity", path: \.estimator.throttleSensitivity, range: 0.5...1.5, unit: "×")
            control("Acceleration smoothing alpha", path: \.estimator.accelerationSmoothingAlpha, range: 0.1...0.6, unit: "α")
            control("Jerk smoothing alpha", path: \.estimator.jerkSmoothingAlpha, range: 0.1...0.6, unit: "α")
            control("Throttle attack alpha", path: \.estimator.throttleAttackAlpha, range: 0.2...0.8, unit: "α")
            control("Throttle release alpha", path: \.estimator.throttleReleaseAlpha, range: 0.1...0.5, unit: "α")
            control("GPS correction gain", path: \.estimator.gpsCorrectionGain, range: 0.03...0.25, unit: "/s")
            control("Acceleration dead zone", path: \.estimator.accelerationDeadZone, range: 0.05...0.4, unit: "m/s²")
            control("Jerk threshold", path: \.estimator.jerkThreshold, range: 0.5...5, unit: "m/s³")
            control("RPM response", path: \.engine.rpmResponse, range: 0.5...2, unit: "×")
            control("Engine inertia", path: \.engine.inertia, range: 0.5...2, unit: "×")
            control("Upshift aggressiveness", path: \.transmission.upshiftAggressiveness, range: 0.75...1.2, unit: "×")
            control("Downshift aggressiveness", path: \.transmission.downshiftAggressiveness, range: 0.75...1.3, unit: "×")
            control("Shift duration", path: \.transmission.shiftDuration, range: 0.6...1.5, unit: "×")
            control("Backfire amount", path: \.audio.backfireAmount, range: 0...1, unit: "%")
            control("Engine volume", path: \.audio.engineVolume, range: 0...1, unit: "%")
            control("Intake volume", path: \.audio.intakeVolume, range: 0...1, unit: "%")
            control("Exhaust volume", path: \.audio.exhaustVolume, range: 0...1, unit: "%")
            Text("Changes save automatically. Named presets keep your last Custom calibration separately. Editing a preset creates a new Custom calibration.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Higher inertia slows RPM changes. Higher shift aggressiveness holds higher RPM; duration scales the next shift. Sensor controls affect Real Drive and the four latency scenarios. Original Simulation scenarios use fixed pedal inputs.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = controller.calibration.persistenceError { Text(error).foregroundStyle(.red) }
        }.disabled(!controller.canCalibrate)
    }
    private func control(_ title: String, path: WritableKeyPath<CalibrationValues, Double>,
                         range: ClosedRange<Double>, unit: String) -> some View {
        let binding = Binding(get: { controller.calibration.values[keyPath: path] },
                              set: { value in controller.updateCalibration { $0[keyPath: path] = value } })
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(unit == "%" ? String(format: "%.0f%%", binding.wrappedValue * 100)
                     : String(format: "%.2f %@", binding.wrappedValue, unit)).monospacedDigit()
            }
            Slider(value: binding, in: range, step: 0.01).accessibilityLabel(title)
        }
    }
}
